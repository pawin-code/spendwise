import 'package:spendwise/core/dates.dart';
import 'package:spendwise/domain/enums.dart';

/// The n-th occurrence (n = 0 is [start]) of a schedule. Monthly and yearly
/// schedules always count from [start] so Jan 31 -> Feb 28 -> Mar 31 (no drift).
DateTime occurrenceAt(DateTime start, Frequency f, int interval, int n) {
  final s = dateOnly(start);
  final step = interval < 1 ? 1 : interval;
  switch (f) {
    case Frequency.once:
      return s;
    case Frequency.daily:
      return DateTime(s.year, s.month, s.day + n * step);
    case Frequency.weekly:
      return DateTime(s.year, s.month, s.day + 7 * n * step);
    case Frequency.monthly:
      return addMonthsClamped(s, n * step);
    case Frequency.yearly:
      return addMonthsClamped(s, 12 * n * step);
  }
}

/// First occurrence strictly after [after], or null for one-off schedules.
DateTime? nextOccurrenceAfter(
  DateTime start,
  Frequency f,
  int interval,
  DateTime after,
) {
  if (f == Frequency.once) return null;
  final a = dateOnly(after);
  var n = 0;
  // Jump close to the answer, then step forward; bounded for safety.
  final s = dateOnly(start);
  final step = interval < 1 ? 1 : interval;
  if (a.isAfter(s)) {
    switch (f) {
      case Frequency.daily:
        n = a.difference(s).inDays ~/ step;
      case Frequency.weekly:
        n = a.difference(s).inDays ~/ (7 * step);
      case Frequency.monthly:
        n = (((a.year - s.year) * 12 + a.month - s.month) ~/ step) - 1;
      case Frequency.yearly:
        n = ((a.year - s.year) ~/ step) - 1;
      case Frequency.once:
        break;
    }
    if (n < 0) n = 0;
  }
  for (var i = 0; i < 100000; i++, n++) {
    final d = occurrenceAt(start, f, interval, n);
    if (d.isAfter(a)) return d;
  }
  return null;
}

/// All occurrences d with from <= d <= to, starting no earlier than [start]
/// and ending no later than [end] (if given). Capped at [limit] entries.
List<DateTime> occurrencesBetween({
  required DateTime start,
  required Frequency f,
  required int interval,
  required DateTime from,
  required DateTime to,
  DateTime? end,
  int limit = 400,
}) {
  final result = <DateTime>[];
  final lo = dateOnly(from);
  final hi = dateOnly(to);
  final endD = end == null ? null : dateOnly(end);
  if (f == Frequency.once) {
    final d = dateOnly(start);
    if (!d.isBefore(lo) &&
        !d.isAfter(hi) &&
        (endD == null || !d.isAfter(endD))) {
      result.add(d);
    }
    return result;
  }
  var d = dateOnly(start);
  var n = 0;
  if (d.isBefore(lo)) {
    final prev = nextOccurrenceAfter(
      start,
      f,
      interval,
      lo.subtract(const Duration(days: 1)),
    );
    if (prev == null) return result;
    d = prev;
    // Recover n lazily by walking; cheap relative to limit.
    while (occurrenceAt(start, f, interval, n) != d && n < 100000) {
      n++;
    }
  }
  while (!d.isAfter(hi) && result.length < limit) {
    if (endD != null && d.isAfter(endD)) break;
    result.add(d);
    n++;
    d = occurrenceAt(start, f, interval, n);
  }
  return result;
}
