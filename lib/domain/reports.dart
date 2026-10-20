import 'package:intl/intl.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/data/database/app_database.dart';
import 'package:spendwise/domain/enums.dart';

enum ReportPeriod { day, week, month, quarter, year, custom }

extension ReportPeriodLabel on ReportPeriod {
  String get label => switch (this) {
    ReportPeriod.day => 'Daily',
    ReportPeriod.week => 'Weekly',
    ReportPeriod.month => 'Monthly',
    ReportPeriod.quarter => 'Quarterly',
    ReportPeriod.year => 'Yearly',
    ReportPeriod.custom => 'Custom',
  };
}

/// Half-open date range [from, toExclusive).
class DateRange {
  const DateRange(this.from, this.toExclusive);
  final DateTime from;
  final DateTime toExclusive;

  int get days => toExclusive.difference(from).inDays;

  @override
  bool operator ==(Object other) =>
      other is DateRange &&
      other.from == from &&
      other.toExclusive == toExclusive;

  @override
  int get hashCode => Object.hash(from, toExclusive);
}

DateRange rangeFor(ReportPeriod p, DateTime anchor, {DateRange? custom}) {
  final a = dateOnly(anchor);
  switch (p) {
    case ReportPeriod.day:
      return DateRange(a, DateTime(a.year, a.month, a.day + 1));
    case ReportPeriod.week:
      final s = startOfWeek(a);
      return DateRange(s, DateTime(s.year, s.month, s.day + 7));
    case ReportPeriod.month:
      return DateRange(startOfMonth(a), startOfNextMonth(a));
    case ReportPeriod.quarter:
      final s = startOfQuarter(a);
      return DateRange(s, DateTime(s.year, s.month + 3));
    case ReportPeriod.year:
      return DateRange(DateTime(a.year), DateTime(a.year + 1));
    case ReportPeriod.custom:
      return custom ?? DateRange(startOfMonth(a), startOfNextMonth(a));
  }
}

/// Moves [anchor] by [steps] periods (negative = earlier).
DateTime shiftAnchor(ReportPeriod p, DateTime anchor, int steps) {
  final a = dateOnly(anchor);
  switch (p) {
    case ReportPeriod.day:
      return DateTime(a.year, a.month, a.day + steps);
    case ReportPeriod.week:
      return DateTime(a.year, a.month, a.day + 7 * steps);
    case ReportPeriod.month:
      return addMonthsClamped(a, steps);
    case ReportPeriod.quarter:
      return addMonthsClamped(a, 3 * steps);
    case ReportPeriod.year:
      return addMonthsClamped(a, 12 * steps);
    case ReportPeriod.custom:
      return a;
  }
}

/// The range immediately before [r], with the same logical length.
DateRange previousRange(ReportPeriod p, DateRange r) {
  switch (p) {
    case ReportPeriod.day:
    case ReportPeriod.week:
    case ReportPeriod.custom:
      final d = r.days;
      return DateRange(
        DateTime(r.from.year, r.from.month, r.from.day - d),
        r.from,
      );
    case ReportPeriod.month:
      return DateRange(DateTime(r.from.year, r.from.month - 1), r.from);
    case ReportPeriod.quarter:
      return DateRange(DateTime(r.from.year, r.from.month - 3), r.from);
    case ReportPeriod.year:
      return DateRange(DateTime(r.from.year - 1), r.from);
  }
}

String rangeLabel(ReportPeriod p, DateRange r) {
  final last = DateTime(
    r.toExclusive.year,
    r.toExclusive.month,
    r.toExclusive.day - 1,
  );
  switch (p) {
    case ReportPeriod.day:
      return DateFormat('EEE, d MMM yyyy').format(r.from);
    case ReportPeriod.week:
      return '${DateFormat('d MMM').format(r.from)} – ${DateFormat('d MMM yyyy').format(last)}';
    case ReportPeriod.month:
      return DateFormat('MMMM yyyy').format(r.from);
    case ReportPeriod.quarter:
      return 'Q${(r.from.month - 1) ~/ 3 + 1} ${r.from.year}';
    case ReportPeriod.year:
      return '${r.from.year}';
    case ReportPeriod.custom:
      return '${DateFormat('d MMM yyyy').format(r.from)} – ${DateFormat('d MMM yyyy').format(last)}';
  }
}

class Bucket {
  const Bucket(this.label, this.start, this.incomeMinor, this.expenseMinor);
  final String label;
  final DateTime start;
  final int incomeMinor;
  final int expenseMinor;
}

enum Granularity { none, day, week, month }

Granularity granularityFor(ReportPeriod p, DateRange r) {
  switch (p) {
    case ReportPeriod.day:
      return Granularity.none;
    case ReportPeriod.week:
      return Granularity.day;
    case ReportPeriod.month:
      return Granularity.week;
    case ReportPeriod.quarter:
    case ReportPeriod.year:
      return Granularity.month;
    case ReportPeriod.custom:
      if (r.days <= 1) return Granularity.none;
      if (r.days <= 31) return Granularity.day;
      if (r.days <= 140) return Granularity.week;
      return Granularity.month;
  }
}

/// Groups income/expense (transfers and deleted rows excluded) into buckets.
List<Bucket> buildBuckets(
  ReportPeriod p,
  DateRange r,
  Iterable<TxnRow> txns, {
  DateTime? asOf,
}) {
  final g = granularityFor(p, r);
  if (g == Granularity.none) return const [];
  final starts = <DateTime>[];
  var cursor = r.from;
  while (cursor.isBefore(r.toExclusive)) {
    starts.add(cursor);
    cursor = switch (g) {
      Granularity.day => DateTime(cursor.year, cursor.month, cursor.day + 1),
      Granularity.week => DateTime(cursor.year, cursor.month, cursor.day + 7),
      Granularity.month => DateTime(cursor.year, cursor.month + 1),
      Granularity.none => r.toExclusive,
    };
  }
  final income = List<int>.filled(starts.length, 0);
  final expense = List<int>.filled(starts.length, 0);
  for (final t in txns) {
    if (t.deletedAt != null || t.type == TxnType.transfer) continue;
    if (asOf != null && t.occurredAt.isAfter(asOf)) continue;
    if (t.occurredAt.isBefore(r.from) ||
        !t.occurredAt.isBefore(r.toExclusive)) {
      continue;
    }
    var idx = starts.length - 1;
    for (var i = 0; i < starts.length; i++) {
      if (i + 1 < starts.length && t.occurredAt.isBefore(starts[i + 1])) {
        idx = i;
        break;
      }
    }
    if (t.type == TxnType.income) {
      income[idx] += t.amountMinor;
    } else {
      expense[idx] += t.amountMinor;
    }
  }
  String labelFor(DateTime d, int i) => switch (g) {
    Granularity.day => r.days <= 8 ? DateFormat('E').format(d) : '${d.day}',
    Granularity.week => 'W${i + 1}',
    Granularity.month => DateFormat('MMM').format(d),
    Granularity.none => '',
  };
  return [
    for (var i = 0; i < starts.length; i++)
      Bucket(labelFor(starts[i], i), starts[i], income[i], expense[i]),
  ];
}

/// Percentage change from [previous] to [current]; null when previous is 0.
int? percentChange(int current, int previous) {
  if (previous == 0) return null;
  return ((current - previous) * 100 / previous).round();
}
