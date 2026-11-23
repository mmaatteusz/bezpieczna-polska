import 'package:flutter/material.dart';

ThemeData buildSafetyTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF26435B),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFFC0D9EB) : const Color(0xFF24465F),
        onPrimary: dark ? const Color(0xFF142D40) : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF2B4355)
            : const Color(0xFFE2EBF1),
        onPrimaryContainer: dark
            ? const Color(0xFFD9EAF6)
            : const Color(0xFF183C55),
        secondary: dark ? const Color(0xFFB3C8DB) : const Color(0xFF486279),
        secondaryContainer: dark
            ? const Color(0xFF263C4B)
            : const Color(0xFFE9EFF3),
        onSecondaryContainer: dark
            ? const Color(0xFFD8E5EE)
            : const Color(0xFF2C465A),
        tertiary: dark ? const Color(0xFFFFC573) : const Color(0xFF875100),
        onTertiary: dark ? const Color(0xFF3B2608) : Colors.white,
        tertiaryContainer: dark
            ? const Color(0xFF352C22)
            : const Color(0xFFF9EBD5),
        onTertiaryContainer: dark
            ? const Color(0xFFFFDFAC)
            : const Color(0xFF513300),
        error: dark ? const Color(0xFFFFAEB8) : const Color(0xFFA12A40),
        onError: dark ? const Color(0xFF551B27) : Colors.white,
        errorContainer: dark
            ? const Color(0xFF40262D)
            : const Color(0xFFF8E1E4),
        onErrorContainer: dark
            ? const Color(0xFFFFD7DC)
            : const Color(0xFF65172A),
        surface: dark ? const Color(0xFF111B24) : const Color(0xFFF6F4EF),
        surfaceContainerLowest: dark
            ? const Color(0xFF192630)
            : const Color(0xFFFFFDF9),
        surfaceContainerLow: dark
            ? const Color(0xFF1C2A35)
            : const Color(0xFFF2F0EA),
        surfaceContainer: dark
            ? const Color(0xFF202F3A)
            : const Color(0xFFEFECE5),
        surfaceContainerHigh: dark
            ? const Color(0xFF293844)
            : const Color(0xFFE8E6DF),
        surfaceContainerHighest: dark
            ? const Color(0xFF354653)
            : const Color(0xFFE3E1D9),
        onSurface: dark ? const Color(0xFFE9EFF3) : const Color(0xFF192A36),
        onSurfaceVariant: dark
            ? const Color(0xFFB1C0CA)
            : const Color(0xFF53636D),
        outline: dark ? const Color(0xFF8295A2) : const Color(0xFF71818A),
        outlineVariant: dark
            ? const Color(0xFF344450)
            : const Color(0xFFD9DDD9),
        surfaceTint: Colors.transparent,
      );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.copyWith(
    headlineLarge: base.textTheme.headlineLarge?.copyWith(
      fontFamily: 'Source Serif 4',
      fontSize: 35,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.7,
      height: 1.03,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.25,
      height: 1.2,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.25,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.35),
    bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.35),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    labelMedium: base.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    ),
  );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(9),
  );

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      titleSpacing: 20,
      titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: 68,
      backgroundColor: scheme.surfaceContainerLowest,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: controlShape,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return text.labelMedium?.copyWith(
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          size: 23,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: controlShape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: controlShape,
        side: BorderSide(color: scheme.outline),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: controlShape,
        textStyle: text.labelLarge,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: controlShape,
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surfaceContainerLowest,
      selectedColor: scheme.primaryContainer,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
  );
}
