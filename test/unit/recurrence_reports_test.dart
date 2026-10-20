import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/enums.dart';
import 'package:spendwise/domain/recurrence.dart';
import 'package:spendwise/domain/reports.dart';

import '../helpers.dart';

void main() {
  group('occurrenceAt', () {
    test('monthly schedules count from the start and do not drift', () {
      final start = DateTime(2026, 1, 31);
      expect(
        occurrenceAt(start, Frequency.monthly, 1, 1),
        DateTime(2026, 2, 28),
      );
      expect(
        occurrenceAt(start, Frequency.monthly, 1, 2),
        DateTime(2026, 3, 31),
      );
      expect(
        occurrenceAt(start, Frequency.monthly, 1, 3),
        DateTime(2026, 4, 30),
      );
      expect(
        occurrenceAt(start, Frequency.monthly, 3, 1),
        DateTime(2026, 4, 30),
      );
    });

    test('weekly, daily and yearly steps', () {
      final d = DateTime(2026, 10, 20);
      expect(occurrenceAt(d, Frequency.weekly, 2, 1), DateTime(2026, 11, 3));
      expect(occurrenceAt(d, Frequency.daily, 1, 12), DateTime(2026, 11, 1));
      expect(
        occurrenceAt(DateTime(2028, 2, 29), Frequency.yearly, 1, 1),
        DateTime(2029, 2, 28),
      );
    });

    test('daylight saving transitions keep calendar dates', () {
      // Date-only arithmetic is calendar based, so there is no 23/25h drift.
      expect(
        occurrenceAt(DateTime(2026, 3, 7), Frequency.daily, 1, 2),
        DateTime(2026, 3, 9),
      );
      expect(
        occurrenceAt(DateTime(2026, 11, 1), Frequency.weekly, 1, 1),
        DateTime(2026, 11, 8),
      );
    });
  });

  group('nextOccurrenceAfter', () {
    test('returns the first occurrence strictly after a date', () {
      final start = DateTime(2026, 1, 15);
      expect(
        nextOccurrenceAfter(start, Frequency.monthly, 1, DateTime(2026, 1, 15)),
        DateTime(2026, 2, 15),
      );
      expect(
        nextOccurrenceAfter(start, Frequency.monthly, 1, DateTime(2026, 2, 14)),
        DateTime(2026, 2, 15),
      );
      expect(
        nextOccurrenceAfter(start, Frequency.monthly, 1, DateTime(2026, 2, 15)),
        DateTime(2026, 3, 15),
      );
      expect(
        nextOccurrenceAfter(start, Frequency.monthly, 1, DateTime(2025, 6, 1)),
        DateTime(2026, 1, 15),
      );
    });

    test('one-off schedules have no next occurrence', () {
      expect(
        nextOccurrenceAfter(
          DateTime(2026, 1, 1),
          Frequency.once,
          1,
          DateTime(2025, 1, 1),
        ),
        isNull,
      );
    });

    test('weekly and daily intervals', () {
      expect(
        nextOccurrenceAfter(
          DateTime(2026, 10, 5),
          Frequency.weekly,
          1,
          DateTime(2026, 10, 20),
        ),
        DateTime(2026, 10, 26),
      );
      expect(
        nextOccurrenceAfter(
          DateTime(2026, 10, 1),
          Frequency.daily,
          3,
          DateTime(2026, 10, 9),
        ),
        DateTime(2026, 10, 10),
      );
    });

    test('far-in-the-past starts resolve quickly and correctly', () {
      expect(
        nextOccurrenceAfter(
          DateTime(2000, 1, 31),
          Frequency.monthly,
          1,
          DateTime(2026, 10, 20),
        ),
        DateTime(2026, 10, 31),
      );
    });
  });

  group('occurrencesBetween', () {
    test('lists every due date in a window', () {
      final r = occurrencesBetween(
        start: DateTime(2026, 1, 31),
        f: Frequency.monthly,
        interval: 1,
        from: DateTime(2026, 2, 1),
        to: DateTime(2026, 5, 1),
      );
      expect(r, [
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });

    test('honours the end date and the one-off case', () {
      final r = occurrencesBetween(
        start: DateTime(2026, 10, 1),
        f: Frequency.weekly,
        interval: 1,
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 12, 31),
        end: DateTime(2026, 10, 15),
      );
      expect(r, [
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 8),
        DateTime(2026, 10, 15),
      ]);
      expect(
        occurrencesBetween(
          start: DateTime(2026, 10, 9),
          f: Frequency.once,
          interval: 1,
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 10, 31),
        ),
        [DateTime(2026, 10, 9)],
      );
      expect(
        occurrencesBetween(
          start: DateTime(2026, 11, 9),
          f: Frequency.once,
          interval: 1,
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 10, 31),
        ),
        isEmpty,
      );
    });
  });

  group('report ranges', () {
    test('period ranges and labels', () {
      final a = DateTime(2026, 10, 20);
      expect(rangeFor(ReportPeriod.day, a).days, 1);
      expect(
        rangeFor(ReportPeriod.week, a),
        DateRange(DateTime(2026, 10, 19), DateTime(2026, 10, 26)),
      );
      expect(
        rangeFor(ReportPeriod.month, a),
        DateRange(DateTime(2026, 10), DateTime(2026, 11)),
      );
      expect(
        rangeFor(ReportPeriod.quarter, a),
        DateRange(DateTime(2026, 10), DateTime(2027, 1)),
      );
      expect(
        rangeFor(ReportPeriod.year, a),
        DateRange(DateTime(2026), DateTime(2027)),
      );
      expect(
        rangeLabel(ReportPeriod.quarter, rangeFor(ReportPeriod.quarter, a)),
        'Q4 2026',
      );
      expect(
        rangeLabel(ReportPeriod.month, rangeFor(ReportPeriod.month, a)),
        'October 2026',
      );
    });

    test('previous range and anchor shifting cross year boundaries', () {
      final jan = rangeFor(ReportPeriod.month, DateTime(2026, 1, 10));
      expect(
        previousRange(ReportPeriod.month, jan),
        DateRange(DateTime(2025, 12), DateTime(2026, 1)),
      );
      expect(
        shiftAnchor(ReportPeriod.quarter, DateTime(2026, 1, 5), -1),
        DateTime(2025, 10, 5),
      );
      expect(
        previousRange(
          ReportPeriod.year,
          rangeFor(ReportPeriod.year, DateTime(2026, 6, 1)),
        ),
        DateRange(DateTime(2025), DateTime(2026)),
      );
      final week = rangeFor(ReportPeriod.week, DateTime(2026, 10, 20));
      expect(
        previousRange(ReportPeriod.week, week),
        DateRange(DateTime(2026, 10, 12), DateTime(2026, 10, 19)),
      );
    });

    test('percentChange handles zero base', () {
      expect(percentChange(150, 100), 50);
      expect(percentChange(50, 100), -50);
      expect(percentChange(10, 0), isNull);
    });
  });

  group('buildBuckets', () {
    test('weekly report has seven daily buckets and excludes transfers', () {
      final r = rangeFor(ReportPeriod.week, DateTime(2026, 10, 20));
      final b = buildBuckets(ReportPeriod.week, r, [
        txn(amount: 1000, at: DateTime(2026, 10, 19, 12)),
        txn(amount: 500, at: DateTime(2026, 10, 19, 20)),
        txn(
          type: TxnType.income,
          amount: 9000,
          category: 'cat_salary',
          at: DateTime(2026, 10, 25, 12),
        ),
        txn(
          type: TxnType.transfer,
          amount: 7000,
          toWallet: 'b',
          category: null,
          at: DateTime(2026, 10, 21, 12),
        ),
        txn(amount: 123, at: DateTime(2026, 10, 26, 12)), // outside range
      ]);
      expect(b.length, 7);
      expect(b.first.expenseMinor, 1500);
      expect(b.last.incomeMinor, 9000);
      expect(b.fold<int>(0, (a, c) => a + c.expenseMinor), 1500);
    });

    test('yearly report has twelve monthly buckets', () {
      final r = rangeFor(ReportPeriod.year, DateTime(2026, 3, 1));
      final b = buildBuckets(ReportPeriod.year, r, [
        txn(amount: 100, at: DateTime(2026, 12, 31, 12)),
        txn(amount: 200, at: DateTime(2026, 1, 1, 12)),
      ]);
      expect(b.length, 12);
      expect(b.first.expenseMinor, 200);
      expect(b.last.expenseMinor, 100);
    });

    test('daily report has no buckets', () {
      final r = rangeFor(ReportPeriod.day, DateTime(2026, 10, 20));
      expect(buildBuckets(ReportPeriod.day, r, [txn()]), isEmpty);
    });
  });
}
