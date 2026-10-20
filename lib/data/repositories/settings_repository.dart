import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences. Contains no financial records.
class AppSettings {
  const AppSettings({
    this.onboardingDone = false,
    this.currencyCode = 'INR',
    this.themeMode = ThemeMode.system,
    this.accent = 'emerald',
    this.notificationsEnabled = false,
    this.budgetAlertsEnabled = true,
    this.plannedIncomeDay,
    this.reminderHour = 9,
  });

  final bool onboardingDone;
  final String currencyCode;
  final ThemeMode themeMode;
  final String accent;
  final bool notificationsEnabled;
  final bool budgetAlertsEnabled;

  /// Day of month the user expects income (1-28), or null.
  final int? plannedIncomeDay;
  final int reminderHour;

  AppSettings copyWith({
    bool? onboardingDone,
    String? currencyCode,
    ThemeMode? themeMode,
    String? accent,
    bool? notificationsEnabled,
    bool? budgetAlertsEnabled,
    Object? plannedIncomeDay = _keep,
    int? reminderHour,
  }) => AppSettings(
    onboardingDone: onboardingDone ?? this.onboardingDone,
    currencyCode: currencyCode ?? this.currencyCode,
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    budgetAlertsEnabled: budgetAlertsEnabled ?? this.budgetAlertsEnabled,
    plannedIncomeDay: identical(plannedIncomeDay, _keep)
        ? this.plannedIncomeDay
        : plannedIncomeDay as int?,
    reminderHour: reminderHour ?? this.reminderHour,
  );

  static const Object _keep = Object();
}

class SettingsRepository {
  SettingsRepository(this._prefs);
  final SharedPreferences _prefs;

  static const _kOnboarding = 'onboarding_done';
  static const _kCurrency = 'currency';
  static const _kTheme = 'theme_mode';
  static const _kAccent = 'accent';
  static const _kNotif = 'notifications_enabled';
  static const _kBudgetAlerts = 'budget_alerts_enabled';
  static const _kIncomeDay = 'planned_income_day';
  static const _kReminderHour = 'reminder_hour';

  AppSettings load() {
    final themeName = _prefs.getString(_kTheme);
    return AppSettings(
      onboardingDone: _prefs.getBool(_kOnboarding) ?? false,
      currencyCode: _prefs.getString(_kCurrency) ?? 'INR',
      themeMode:
          ThemeMode.values.where((m) => m.name == themeName).firstOrNull ??
          ThemeMode.system,
      accent: _prefs.getString(_kAccent) ?? 'emerald',
      notificationsEnabled: _prefs.getBool(_kNotif) ?? false,
      budgetAlertsEnabled: _prefs.getBool(_kBudgetAlerts) ?? true,
      plannedIncomeDay: _prefs.getInt(_kIncomeDay),
      reminderHour: _prefs.getInt(_kReminderHour) ?? 9,
    );
  }

  Future<void> save(AppSettings s) async {
    await _prefs.setBool(_kOnboarding, s.onboardingDone);
    await _prefs.setString(_kCurrency, s.currencyCode);
    await _prefs.setString(_kTheme, s.themeMode.name);
    await _prefs.setString(_kAccent, s.accent);
    await _prefs.setBool(_kNotif, s.notificationsEnabled);
    await _prefs.setBool(_kBudgetAlerts, s.budgetAlertsEnabled);
    if (s.plannedIncomeDay == null) {
      await _prefs.remove(_kIncomeDay);
    } else {
      await _prefs.setInt(_kIncomeDay, s.plannedIncomeDay!);
    }
    await _prefs.setInt(_kReminderHour, s.reminderHour);
  }

  /// Clears every preference (used by "Erase all data").
  Future<void> clear() => _prefs.clear();
}
