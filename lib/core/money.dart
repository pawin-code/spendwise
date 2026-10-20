import 'package:intl/intl.dart';

/// Authoritative money values are integers in minor units (paise / cents).
/// Floating point is never used for financial arithmetic.
const int kMaxAmountMinor = 100000000000; // 1,000,000,000.00

class CurrencyInfo {
  const CurrencyInfo(this.code, this.symbol, this.name, this.locale);
  final String code;
  final String symbol;
  final String name;
  final String locale;
}

const List<CurrencyInfo> kCurrencies = [
  CurrencyInfo('INR', '₹', 'Indian Rupee', 'en_IN'),
  CurrencyInfo('USD', r'$', 'US Dollar', 'en_US'),
  CurrencyInfo('EUR', '€', 'Euro', 'en_IE'),
  CurrencyInfo('GBP', '£', 'British Pound', 'en_GB'),
  CurrencyInfo('AED', 'AED ', 'UAE Dirham', 'en_US'),
  CurrencyInfo('SGD', r'S$', 'Singapore Dollar', 'en_SG'),
  CurrencyInfo('AUD', r'A$', 'Australian Dollar', 'en_AU'),
  CurrencyInfo('CAD', r'C$', 'Canadian Dollar', 'en_CA'),
];

CurrencyInfo currencyByCode(String? code) => kCurrencies.firstWhere(
  (c) => c.code == code,
  orElse: () => kCurrencies.first,
);

/// Formats [minor] (e.g. 123456 -> "₹1,234.56") using integer math only.
String formatMinor(
  int minor, {
  CurrencyInfo? currency,
  bool signed = false,
  bool hideZeroFraction = false,
}) {
  final cur = currency ?? kCurrencies.first;
  final negative = minor < 0;
  final abs = minor.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;
  final wholeText = NumberFormat.decimalPattern(cur.locale).format(whole);
  final fracText = (hideZeroFraction && frac == 0)
      ? ''
      : '.${frac.toString().padLeft(2, '0')}';
  final sign = negative ? '-' : (signed && minor > 0 ? '+' : '');
  return '$sign${cur.symbol}$wholeText$fracText';
}

/// Compact form for chart axes, e.g. 1.2L / 3.4K style is avoided because it is
/// locale specific; we use plain grouped whole units instead.
String formatMinorWhole(int minor, {CurrencyInfo? currency}) =>
    formatMinor(minor, currency: currency, hideZeroFraction: true);

/// Parses user text such as "1,250.5" into minor units. Returns null when the
/// text is not a valid positive-or-zero amount with at most two decimals.
int? parseAmountToMinor(String input) {
  var text = input.trim().replaceAll(',', '').replaceAll(' ', '');
  if (text.isEmpty) return null;
  final match = RegExp(r'^(\d{1,12})(?:\.(\d{0,2}))?$').firstMatch(text);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fracText = (match.group(2) ?? '').padRight(2, '0');
  final frac = int.parse(fracText);
  final total = whole * 100 + frac;
  if (total > kMaxAmountMinor) return null;
  return total;
}

/// Renders minor units as an editable plain string, e.g. 123450 -> "1234.50".
String minorToPlain(int minor) {
  final abs = minor.abs();
  final s = '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
  return minor < 0 ? '-$s' : s;
}

/// Splits [total] into [parts] shares without losing a paisa.
List<int> splitEvenly(int total, int parts) {
  final base = total ~/ parts;
  final remainder = total - base * parts;
  return List.generate(parts, (i) => base + (i < remainder ? 1 : 0));
}
