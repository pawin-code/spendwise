import 'package:flutter/material.dart';

/// SpendWise design tokens.
///
/// Principles: calm, confident, quiet luxury. A deep emerald + midnight navy
/// palette on soft cool neutrals, generous radii and spacing, soft layered
/// shadows instead of hard borders, and tabular, bold numerals for money.
class Brand {
  const Brand._();
  static const emerald = Color(0xFF0A7D5A);
  static const emeraldBright = Color(0xFF14B888);
  static const emeraldMint = Color(0xFF3DDC97);
  static const navy = Color(0xFF0B1F3A);
  static const midnight = Color(0xFF071427);
  static const income = Color(0xFF0A7D5A);
  static const expense = Color(0xFFC62F3F);
  static const gold = Color(0xFFF2B84B);
}

/// Spacing + radius scale used across the app.
class Gap {
  const Gap._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double radius = 24;
  static const double radiusSm = 16;
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

/// Colours and effects that are not part of [ColorScheme].
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.income,
    required this.expense,
    required this.warning,
    required this.navy,
    required this.cardShadow,
    required this.surfaceAlt,
    required this.heroGradient,
  });
  final Color income;
  final Color expense;
  final Color warning;
  final Color navy;
  final Color cardShadow;

  /// A slightly raised/tinted surface used inside cards (chips, key caps, tiles).
  final Color surfaceAlt;
  final List<Color> heroGradient;

  @override
  FinanceColors copyWith({
    Color? income,
    Color? expense,
    Color? warning,
    Color? navy,
    Color? cardShadow,
    Color? surfaceAlt,
    List<Color>? heroGradient,
  }) => FinanceColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    warning: warning ?? this.warning,
    navy: navy ?? this.navy,
    cardShadow: cardShadow ?? this.cardShadow,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    heroGradient: heroGradient ?? this.heroGradient,
  );

  @override
  FinanceColors lerp(ThemeExtension<FinanceColors>? other, double t) {
    if (other is! FinanceColors) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      navy: Color.lerp(navy, other.navy, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      heroGradient: t < 0.5 ? heroGradient : other.heroGradient,
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

  final bg = isDark ? const Color(0xFF070D17) : const Color(0xFFF3F6F5);
  final card = isDark ? const Color(0xFF0F1829) : Colors.white;
  final text = isDark ? const Color(0xFFE8EEF5) : const Color(0xFF0E1A2B);
  final muted = isDark ? const Color(0xFF93A4B7) : const Color(0xFF5B6B7A);
  final hairline = isDark ? const Color(0xFF1B2840) : const Color(0xFFE4EAE8);

  if (accent == 'emerald') {
    scheme = scheme.copyWith(
      primary: isDark ? Brand.emeraldMint : Brand.emerald,
      onPrimary: isDark ? const Color(0xFF00241A) : Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF0E3B2E)
          : const Color(0xFFD3F1E4),
      onPrimaryContainer: isDark
          ? const Color(0xFFBFF3DC)
          : const Color(0xFF053B2B),
      secondary: isDark ? const Color(0xFF9DB4D6) : Brand.navy,
      onSecondary: isDark ? const Color(0xFF0B1F3A) : Colors.white,
      secondaryContainer: isDark
          ? const Color(0xFF1C2C47)
          : const Color(0xFFE0E8F4),
      onSecondaryContainer: isDark
          ? const Color(0xFFD6E3F7)
          : const Color(0xFF0B1F3A),
    );
  }
  scheme = scheme.copyWith(
    surface: bg,
    onSurface: text,
    onSurfaceVariant: muted,
    outlineVariant: hairline,
    surfaceContainerHighest: isDark
        ? const Color(0xFF16233B)
        : const Color(0xFFE9EFEE),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final tt = base.textTheme.apply(bodyColor: text, displayColor: text);
  final textTheme = tt.copyWith(
    displaySmall: tt.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
    ),
    displayMedium: tt.displayMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -1.5,
    ),
    headlineMedium: tt.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
    ),
    headlineSmall: tt.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    titleLarge: tt.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    titleMedium: tt.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.1,
    ),
    titleSmall: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    bodyMedium: tt.bodyMedium?.copyWith(height: 1.4),
    bodyLarge: tt.bodyLarge?.copyWith(height: 1.45),
  );

  final shadow = isDark ? const Color(0x66000000) : const Color(0x140B1F3A);
  final heroGradient = isDark
      ? const [Color(0xFF0B1F3A), Color(0xFF0C3B3A), Color(0xFF0A6B52)]
      : const [Brand.midnight, Color(0xFF0C3A44), Brand.emerald];

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 22),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: card,
      surfaceTintColor: Colors.transparent,
      shadowColor: shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Gap.radius),
        side: BorderSide(color: hairline.withValues(alpha: isDark ? 1 : 0.7)),
      ),
    ),
    dividerTheme: DividerThemeData(color: hairline, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 54),
        elevation: 0,
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        side: BorderSide(color: hairline, width: 1.4),
        foregroundColor: text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: BorderSide(color: hairline),
        backgroundColor: card,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shadowColor: shadow,
      indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? scheme.primary : muted,
          size: 24,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 6,
      highlightElevation: 8,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      extendedTextStyle: textTheme.labelLarge?.copyWith(
        fontSize: 15,
        letterSpacing: 0.2,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xFFE8EEF5) : Brand.navy,
      contentTextStyle: TextStyle(
        color: isDark ? Brand.midnight : Colors.white,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: card,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: hairline),
      labelStyle: textTheme.labelLarge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.primary.withValues(alpha: 0.12),
      circularTrackColor: Colors.transparent,
    ),
    extensions: [
      FinanceColors(
        income: isDark ? Brand.emeraldMint : Brand.income,
        expense: isDark ? const Color(0xFFFF8A94) : Brand.expense,
        warning: isDark ? const Color(0xFFFFC857) : const Color(0xFFB45309),
        navy: Brand.navy,
        cardShadow: shadow,
        surfaceAlt: isDark ? const Color(0xFF16233B) : const Color(0xFFF1F5F4),
        heroGradient: heroGradient,
      ),
    ],
  );
}
