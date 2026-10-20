import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/core/dates.dart';
import 'package:spendwise/core/money.dart';

void main() {
  group('parseAmountToMinor', () {
    test('parses whole and decimal amounts exactly', () {
      expect(parseAmountToMinor('0'), 0);
      expect(parseAmountToMinor('1'), 100);
      expect(parseAmountToMinor('1.5'), 150);
      expect(parseAmountToMinor('1.05'), 105);
      expect(parseAmountToMinor('1234.56'), 123456);
      expect(parseAmountToMinor('1,234.56'), 123456);
      expect(parseAmountToMinor(' 99 '), 9900);
      expect(parseAmountToMinor('5.'), 500);
    });

    test('is exact where binary floating point is not', () {
      // 0.1 + 0.2 != 0.3 in doubles; minor units must stay exact.
      expect(
        parseAmountToMinor('0.10')! + parseAmountToMinor('0.20')!,
        parseAmountToMinor('0.30'),
      );
      expect(parseAmountToMinor('19.99')! * 3, 5997);
    });

    test('rejects invalid input', () {
      for (final bad in [
        '',
        'abc',
        '-5',
        '1.234',
        '1..2',
        '.5',
        '1e5',
        '₹5',
        '1,2,3x',
        '9999999999999',
      ]) {
        expect(parseAmountToMinor(bad), isNull, reason: bad);
      }
    });

    test('rejects amounts above the maximum', () {
      expect(parseAmountToMinor('1000000000.01'), isNull);
      expect(parseAmountToMinor('1000000000'), kMaxAmountMinor);
    });
  });

  group('formatMinor', () {
    test('formats INR with Indian grouping', () {
      expect(formatMinor(0), '₹0.00');
      expect(formatMinor(5), '₹0.05');
      expect(formatMinor(123456), '₹1,234.56');
      expect(formatMinor(12345678), '₹1,23,456.78');
      expect(formatMinor(1000000000), '₹1,00,00,000.00');
    });

    test('handles negatives, signs and hidden zero fractions', () {
      expect(formatMinor(-2550), '-₹25.50');
      expect(formatMinor(2550, signed: true), '+₹25.50');
      expect(formatMinor(2500, hideZeroFraction: true), '₹25');
      expect(formatMinor(2501, hideZeroFraction: true), '₹25.01');
    });

    test('uses US grouping for USD', () {
      expect(
        formatMinor(123456789, currency: currencyByCode('USD')),
        r'$1,234,567.89',
      );
    });

    test('unknown currency code falls back to INR', () {
      expect(currencyByCode('XXX').code, 'INR');
    });
  });

  test('minorToPlain round-trips with parseAmountToMinor', () {
    for (final v in [0, 1, 99, 100, 12345, 99999999]) {
      expect(parseAmountToMinor(minorToPlain(v)), v);
    }
  });

  test('splitEvenly never loses a paisa', () {
    final parts = splitEvenly(10001, 3);
    expect(parts.fold<int>(0, (a, b) => a + b), 10001);
    expect(parts, [3334, 3334, 3333]);
  });

  group('dates', () {
    test('month boundaries across year end', () {
      expect(startOfNextMonth(DateTime(2026, 12, 31)), DateTime(2027, 1));
      expect(startOfMonth(DateTime(2026, 1, 31, 23, 59)), DateTime(2026, 1));
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2026, 2), 28);
    });

    test('addMonthsClamped keeps the end of month', () {
      expect(addMonthsClamped(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonthsClamped(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
      expect(
        addMonthsClamped(DateTime(2026, 11, 30), 3),
        DateTime(2027, 2, 28),
      );
      expect(
        addMonthsClamped(DateTime(2026, 3, 15), -3),
        DateTime(2025, 12, 15),
      );
    });

    test('remaining days includes today', () {
      expect(remainingDaysInMonthInclusive(DateTime(2026, 10, 31)), 1);
      expect(remainingDaysInMonthInclusive(DateTime(2026, 10, 1)), 31);
      expect(remainingDaysInMonthInclusive(DateTime(2026, 2, 28)), 1);
    });

    test('week and quarter starts', () {
      expect(
        startOfWeek(DateTime(2026, 10, 20)),
        DateTime(2026, 10, 19),
      ); // Monday
      expect(
        startOfWeek(DateTime(2026, 10, 18)),
        DateTime(2026, 10, 12),
      ); // Sunday -> previous Monday
      expect(startOfQuarter(DateTime(2026, 11, 3)), DateTime(2026, 10));
      expect(startOfQuarter(DateTime(2026, 3, 31)), DateTime(2026, 1));
    });

    test('monthKey round trip', () {
      expect(parseMonthKey(monthKey(DateTime(2026, 7, 9))), DateTime(2026, 7));
    });
  });
}
