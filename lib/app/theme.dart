import 'package:flutter/material.dart';

/// Brand colours: emerald (primary) and deep navy.
class Brand {
  const Brand._();
  static const emerald = Color(0xFF047857);
  static const emeraldBright = Color(0xFF10B981);
  static const navy = Color(0xFF0B1F3A);
  static const income = Color(0xFF047857);
  static const expense = Color(0xFFB91C1C);
}

class AccentTheme {
  const AccentTheme(this.key, this.name, this.seed, {this.pro = false});
  final String key;
  final String name;
  final Color seed;
  final bool pro;
}

const List<AccentTheme> kAccentThemes = [
  AccentTheme('emerald', 'Emerald', Brand.emerald),
  AccentTheme('ocean', 'Ocean', Color(0xFF0369A1), pro: true),
  AccentTheme('violet', 'Violet', Color(0xFF6D28D9), pro: true),
  AccentTheme('sunset', 'Sunset', Color(0xFFC2410C), pro: true),
  AccentTheme('rose', 'Rose', Color(0xFFBE123C), pro: true),
];

AccentTheme accentByKey(String key) => kAccentThemes.firstWhere(
  (a) => a.key == key,
  orElse: () => kAccentThemes.first,
);

/// Colours that depend on light/dark that are not part of ColorScheme.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.income,
    required this.expense,
    required this.warning,
    required this.navy,
  });
  final Color income;
  final Color expense;
  final Color warning;
  final Color navy;

  @override
  FinanceColors copyWith({
    Color? income,
    Color? expense,
    Color? warning,
    Color? navy,
  }) => FinanceColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    warning: warning ?? this.warning,
    navy: navy ?? this.navy,
  );

  @override
  FinanceColors lerp(ThemeExtension<FinanceColors>? other, double t) {
    if (other is! FinanceColors) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      navy: Color.lerp(navy, other.navy, t)!,
    );
  }
}

extension FinanceColorsX on BuildContext {
  FinanceColors get finance => Theme.of(this).extension<FinanceColors>()!;
}

ThemeData buildTheme(Brightness brightness, {String accent = 'emerald'}) {
  final isDark = brightness == Brightness.dark;
  final seed = accentByKey(accent).seed;
  var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  if (accent == 'emerald') {
    scheme = scheme.copyWith(
      primary: isDark ? const Color(0xFF34D399) : Brand.emerald,
      onPrimary: isDark ? const Color(0xFF00241A) : Colors.white,
      secondary: isDark ? const Color(0xFF9DB4D6) : Brand.navy,
      onSecondary: isDark ? const Color(0xFF0B1F3A) : Colors.white,
      surface: isDark ? const Color(0xFF0B1220) : const Color(0xFFF7F9FA),
      onSurface: isDark ? const Color(0xFFE6EDF5) : const Color(0xFF0F172A),
    );
  } else {
    scheme = scheme.copyWith(
      surface: isDark ? const Color(0xFF0B1220) : const Color(0xFFF7F9FA),
    );
  }
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final text = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isDark ? const Color(0xFF131C2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? const Color(0xFF223049) : const Color(0xFFE5EAF0),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF131C2E) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF223049) : const Color(0xFFD5DDE6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: isDark ? const Color(0xFF0F1727) : Colors.white,
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStatePropertyAll(
        text.labelSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 11),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    extensions: [
      FinanceColors(
        income: isDark ? const Color(0xFF34D399) : Brand.income,
        expense: isDark ? const Color(0xFFF87171) : Brand.expense,
        warning: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
        navy: Brand.navy,
      ),
    ],
  );
}
