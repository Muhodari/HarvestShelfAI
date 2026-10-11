import 'package:flutter/material.dart';

import '../models/category.dart';

/// Brand palette, shared with the logo (scripts/make_logo.py).
///
/// The interface is deliberately quiet: white background, soft grey
/// surfaces without borders, one green accent. Category colours are used
/// only where they carry meaning.
abstract final class Brand {
  static const green = Color(0xFF1E5E39);
  static const greenDeep = Color(0xFF14462A);
  static const greenBright = Color(0xFF2A7A4C);
  static const tomato = Color(0xFFE8553D);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF4F5F2); // cards, inputs
  static const ink = Color(0xFF17201B);
  static const inkSoft = Color(0xFF68716C);
  static const line = Color(0xFFE9EAE5);
  static const danger = Color(0xFFB3261E);
}

const _radius = 16.0;

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.green,
    primary: Brand.green,
    onPrimary: Colors.white,
    secondary: Brand.green,
    surface: Brand.background,
    onSurface: Brand.ink,
    error: Brand.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Nunito',
  );

  // Sizes and weights are merged into the base styles (not replacing them),
  // then font and colour are applied to every style.
  final sized = base.textTheme.merge(
    const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
      titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 17, height: 1.45),
      bodyMedium: TextStyle(fontSize: 15.5, height: 1.4),
      bodySmall: TextStyle(fontSize: 14, height: 1.4), // secondary text
      labelLarge: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
    ),
  );
  final applied = sized.apply(
    fontFamily: 'Nunito',
    bodyColor: Brand.ink,
    displayColor: Brand.ink,
  );
  final text = applied.copyWith(
    bodySmall: applied.bodySmall!.copyWith(color: Brand.inkSoft),
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_radius),
  );
  final noBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(_radius),
    borderSide: BorderSide.none,
  );

  return base.copyWith(
    scaffoldBackgroundColor: Brand.background,
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.background,
      foregroundColor: Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: Brand.ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: Brand.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: shape,
        elevation: 0,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: shape,
        side: const BorderSide(color: Brand.line, width: 1.5),
        foregroundColor: Brand.ink,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Brand.green,
        textStyle: text.labelLarge,
        minimumSize: const Size(48, 48),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: noBorder,
      enabledBorder: noBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: const BorderSide(color: Brand.green, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: const BorderSide(color: Brand.danger, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: const BorderSide(color: Brand.danger, width: 1.5),
      ),
      labelStyle: const TextStyle(color: Brand.inkSoft),
      prefixIconColor: Brand.inkSoft,
      suffixIconColor: Brand.inkSoft,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Brand.green.withValues(alpha: 0.10),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: 'Nunito',
          fontSize: 12.5,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: s.contains(WidgetState.selected) ? Brand.green : Brand.inkSoft,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? Brand.green : Brand.inkSoft,
        ),
      ),
    ),
    listTileTheme: const ListTileThemeData(iconColor: Brand.inkSoft),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 15,
        color: Colors.white,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Brand.background,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(
      color: Brand.line,
      space: 1,
      thickness: 1,
    ),
  );
}

/// Category colours. All give at least 4.5:1 contrast with white, and each
/// pairs with an icon and a word so meaning never depends on colour alone.
Color categoryColor(TriageCategory c) => switch (c) {
  TriageCategory.fresh => const Color(0xFF2E7D4F),
  TriageCategory.sellSoon => const Color(0xFF8F5B00),
  TriageCategory.discountToday => const Color(0xFFB4470A),
  TriageCategory.spoilageRisk => const Color(0xFFB3261E),
  TriageCategory.uncertain => const Color(0xFF5F6368),
};

IconData categoryIcon(TriageCategory c) => switch (c) {
  TriageCategory.fresh => Icons.check_circle_rounded,
  TriageCategory.sellSoon => Icons.schedule_rounded,
  TriageCategory.discountToday => Icons.sell_rounded,
  TriageCategory.spoilageRisk => Icons.warning_rounded,
  TriageCategory.uncertain => Icons.help_rounded,
};
