/// Date helpers. All boundaries are computed in the device's local time zone.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

/// First instant of the following month (exclusive upper bound).
DateTime startOfNextMonth(DateTime d) => DateTime(d.year, d.month + 1);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

/// Adds [months] keeping the day-of-month where possible, clamping to the
/// last valid day (Jan 31 + 1 month = Feb 28/29).
DateTime addMonthsClamped(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  final day = d.day > daysInMonth(year, month)
      ? daysInMonth(year, month)
      : d.day;
  return DateTime(year, month, day, d.hour, d.minute, d.second);
}

String monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

DateTime parseMonthKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]));
}

/// Number of days from [today] to the last day of [today]'s month, inclusive of
/// both ends (on the last day this is 1).
int remainingDaysInMonthInclusive(DateTime today) =>
    daysInMonth(today.year, today.month) - today.day + 1;

/// Start of the ISO week (Monday) containing [d].
DateTime startOfWeek(DateTime d) =>
    dateOnly(d).subtract(Duration(days: d.weekday - 1));

DateTime startOfQuarter(DateTime d) =>
    DateTime(d.year, ((d.month - 1) ~/ 3) * 3 + 1);

DateTime startOfYear(DateTime d) => DateTime(d.year);
