import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/ids.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

abstract class NotificationService {
  Future<void> init();

  /// Asks Android for POST_NOTIFICATIONS (API 33+). Returns whether granted.
  Future<bool> requestPermission();

  Future<bool> hasPermission();

  /// Replaces all pending bill reminders with ones derived from [rules].
  /// Reminder text never contains amounts (lock-screen privacy).
  Future<void> rescheduleBillReminders(
    List<RuleRow> rules, {
    required int hour,
    DateTime? now,
  });

  Future<void> showBudgetAlert({
    required String key,
    required String title,
    required String body,
  });

  Future<void> cancelAll();
}

class NoopNotificationService implements NotificationService {
  @override
  Future<void> cancelAll() async {}
  @override
  Future<bool> hasPermission() async => false;
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> rescheduleBillReminders(
    List<RuleRow> rules, {
    required int hour,
    DateTime? now,
  }) async {}
  @override
  Future<void> showBudgetAlert({
    required String key,
    required String title,
    required String body,
  }) async {}
}

/// Legacy Android/ICU zone ids that the `timezone` database spells differently.
const Map<String, String> _tzAliases = {
  'Asia/Calcutta': 'Asia/Kolkata',
  'Asia/Katmandu': 'Asia/Kathmandu',
  'Asia/Saigon': 'Asia/Ho_Chi_Minh',
  'Asia/Rangoon': 'Asia/Yangon',
  'Europe/Kiev': 'Europe/Kyiv',
  'America/Buenos_Aires': 'America/Argentina/Buenos_Aires',
  'Asia/Dacca': 'Asia/Dhaka',
};

/// Finds a usable [tz.Location] for the id the device reports. Falls back to an
/// alias, then to any zone whose current UTC offset equals [offset], and only
/// as a last resort to UTC. (Requires `initializeTimeZones()` to have run.)
tz.Location resolveTimeZone(String id, Duration offset) {
  for (final candidate in [id, _tzAliases[id]]) {
    if (candidate == null) continue;
    try {
      return tz.getLocation(candidate);
    } catch (_) {}
  }
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  for (final loc in tz.timeZoneDatabase.locations.values) {
    if (loc.name.contains('/') &&
        !loc.name.startsWith('Etc/') &&
        loc.timeZone(nowMs).offset == offset) {
      return loc;
    }
  }
  return tz.UTC;
}

/// When a reminder should fire for [rule], or null if it should not be
/// scheduled (inactive, disabled, or already in the past).
DateTime? reminderTimeFor(
  RuleRow rule, {
  required int hour,
  required DateTime now,
}) {
  if (!rule.active || !rule.remind) return null;
  final due = dateOnly(rule.nextDue);
  final day = DateTime(due.year, due.month, due.day - rule.remindDaysBefore);
  final at = DateTime(day.year, day.month, day.day, hour);
  if (!at.isAfter(now)) {
    // The lead time has passed. If the bill is due today/future, remind on the due day.
    final dueAt = DateTime(due.year, due.month, due.day, hour);
    return dueAt.isAfter(now) ? dueAt : null;
  }
  return at;
}

class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _billChannel = AndroidNotificationDetails(
    'bill_reminders',
    'Bill reminders',
    channelDescription: 'Reminders for bills, rent and subscriptions you added',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _budgetChannel = AndroidNotificationDetails(
    'budget_alerts',
    'Budget alerts',
    channelDescription: 'Alerts when spending reaches your budget thresholds',
    importance: Importance.defaultImportance,
  );

  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(
        resolveTimeZone(info.identifier, DateTime.now().timeZoneOffset),
      );
    } catch (e) {
      debugPrint('Timezone setup failed, using UTC: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<bool> hasPermission() async {
    await init();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<void> rescheduleBillReminders(
    List<RuleRow> rules, {
    required int hour,
    DateTime? now,
  }) async {
    await init();
    await _plugin.cancelAllPendingNotifications();
    if (!await hasPermission()) return;
    final current = now ?? DateTime.now();
    for (final rule in rules) {
      final at = reminderTimeFor(rule, hour: hour, now: current);
      if (at == null) continue;
      final due = dateOnly(rule.nextDue);
      final today = dateOnly(current);
      final when = due.difference(today).inDays;
      final body = when <= 0
          ? 'Due today. Open SpendWise to mark it as paid.'
          : 'Due in $when day${when == 1 ? '' : 's'}.';
      try {
        await _plugin.zonedSchedule(
          id: stableHash('bill:${rule.id}'),
          title: rule.title,
          body: body,
          scheduledDate: tz.TZDateTime.from(at, tz.local),
          notificationDetails: const NotificationDetails(android: _billChannel),
          // Inexact + idle-allowed: no SCHEDULE_EXACT_ALARM permission needed.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'bill:${rule.id}',
        );
      } catch (e) {
        debugPrint('Could not schedule reminder: $e');
      }
    }
  }

  @override
  Future<void> showBudgetAlert({
    required String key,
    required String title,
    required String body,
  }) async {
    await init();
    if (!await hasPermission()) return;
    await _plugin.show(
      id: stableHash('budget:$key'),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: _budgetChannel),
    );
  }

  @override
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
