import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/services/notification_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;

RuleRow rule({
  DateTime? due,
  bool active = true,
  bool remind = true,
  int days = 1,
}) => RuleRow(
  id: 'r1',
  title: 'Rent',
  kind: ReminderKind.rent,
  type: CategoryType.expense,
  amountMinor: 1500000,
  categoryId: null,
  walletId: 'w',
  frequency: Frequency.monthly,
  intervalCount: 1,
  startDate: DateTime(2026, 1, 5),
  nextDue: due ?? DateTime(2026, 11, 5),
  endDate: null,
  active: active,
  autoPost: false,
  remind: remind,
  remindDaysBefore: days,
  note: '',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  final now = DateTime(2026, 10, 20, 10);

  test('reminds the configured number of days before at the chosen hour', () {
    expect(
      reminderTimeFor(
        rule(due: DateTime(2026, 11, 5), days: 2),
        hour: 9,
        now: now,
      ),
      DateTime(2026, 11, 3, 9),
    );
  });

  test('month and year boundaries', () {
    expect(
      reminderTimeFor(
        rule(due: DateTime(2027, 1, 1), days: 1),
        hour: 9,
        now: now,
      ),
      DateTime(2026, 12, 31, 9),
    );
  });

  test('inactive or reminder-disabled rules are not scheduled', () {
    expect(reminderTimeFor(rule(active: false), hour: 9, now: now), isNull);
    expect(reminderTimeFor(rule(remind: false), hour: 9, now: now), isNull);
  });

  test('if the lead time has passed, remind on the due day instead', () {
    expect(
      reminderTimeFor(
        rule(due: DateTime(2026, 10, 21), days: 3),
        hour: 9,
        now: now,
      ),
      DateTime(2026, 10, 21, 9),
    );
  });

  test('overdue items are not re-notified (they show in the app instead)', () {
    expect(
      reminderTimeFor(rule(due: DateTime(2026, 10, 10)), hour: 9, now: now),
      isNull,
    );
  });

  test('due today after the reminder hour has passed is not scheduled', () {
    expect(
      reminderTimeFor(
        rule(due: DateTime(2026, 10, 20), days: 0),
        hour: 9,
        now: now,
      ),
      isNull,
    );
    expect(
      reminderTimeFor(
        rule(due: DateTime(2026, 10, 20), days: 0),
        hour: 18,
        now: now,
      ),
      DateTime(2026, 10, 20, 18),
    );
  });

  group('resolveTimeZone', () {
    setUpAll(tzdata.initializeTimeZones);

    test('modern ids resolve directly', () {
      expect(
        resolveTimeZone(
          'Asia/Kolkata',
          const Duration(hours: 5, minutes: 30),
        ).name,
        'Asia/Kolkata',
      );
    });

    test(
      'the legacy Android id for India resolves instead of falling back to UTC',
      () {
        expect(
          resolveTimeZone(
            'Asia/Calcutta',
            const Duration(hours: 5, minutes: 30),
          ).name,
          'Asia/Kolkata',
        );
      },
    );

    test('unknown ids fall back to a zone with the same offset, never silently UTC', () {
      final loc = resolveTimeZone(
        'Mars/Olympus',
        const Duration(hours: 5, minutes: 30),
      );
      expect(loc.name, isNot('UTC'));
      expect(
        loc.timeZone(DateTime.now().millisecondsSinceEpoch).offset,
        const Duration(hours: 5, minutes: 30),
      );
    });
  });
}
