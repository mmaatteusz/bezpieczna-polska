import 'package:flutter/material.dart';

ThemeData buildSafetyTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF464950),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFFEFEFF1) : const Color(0xFF23252A),
        onPrimary: dark ? const Color(0xFF202227) : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF34363B)
            : const Color(0xFFEBECEE),
        onPrimaryContainer: dark
            ? const Color(0xFFF2F2F4)
            : const Color(0xFF26292F),
        secondary: dark ? const Color(0xFFC0C3CB) : const Color(0xFF515761),
        secondaryContainer: dark
            ? const Color(0xFF2E3137)
            : const Color(0xFFF2F1EE),
        onSecondaryContainer: dark
            ? const Color(0xFFE1E3E9)
            : const Color(0xFF363B44),
        tertiary: dark ? const Color(0xFFF4BD70) : const Color(0xFF865200),
        onTertiary: dark ? const Color(0xFF382507) : Colors.white,
        tertiaryContainer: dark
            ? const Color(0xFF352D23)
            : const Color(0xFFFAF0DD),
        onTertiaryContainer: dark
            ? const Color(0xFFFFDFAD)
            : const Color(0xFF5A3600),
        error: dark ? const Color(0xFFFFA5B4) : const Color(0xFFA21A37),
        onError: dark ? const Color(0xFF521222) : Colors.white,
        errorContainer: dark
            ? const Color(0xFF40282F)
            : const Color(0xFFFBE8EC),
        onErrorContainer: dark
            ? const Color(0xFFFFDCE2)
            : const Color(0xFF761127),
        surface: dark ? const Color(0xFF17181A) : const Color(0xFFFBFAF8),
        surfaceContainerLowest: dark
            ? const Color(0xFF1D1E21)
            : const Color(0xFFFFFFFF),
        surfaceContainerLow: dark
            ? const Color(0xFF222327)
            : const Color(0xFFF6F5F2),
        surfaceContainer: dark
            ? const Color(0xFF27282D)
            : const Color(0xFFF0EFEC),
        surfaceContainerHigh: dark
            ? const Color(0xFF303237)
            : const Color(0xFFE9E8E5),
        surfaceContainerHighest: dark
            ? const Color(0xFF3B3D43)
            : const Color(0xFFE3E2DF),
        onSurface: dark ? const Color(0xFFF2F1EE) : const Color(0xFF202227),
        onSurfaceVariant: dark
            ? const Color(0xFFB5B7BE)
            : const Color(0xFF565B65),
        outline: dark ? const Color(0xFF8D919A) : const Color(0xFF737780),
        outlineVariant: dark
            ? const Color(0xFF36373B)
            : const Color(0xFFDFDEDB),
        surfaceTint: Colors.transparent,
      );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.copyWith(
    headlineLarge: base.textTheme.headlineLarge?.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.9,
      height: 1.12,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.25,
      height: 1.2,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      height: 1.25,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.35),
    bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.35),
    labelLarge: base.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
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
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      titleSpacing: 20,
      titleTextStyle: text.titleMedium?.copyWith(
        color: scheme.onSurface,
        fontSize: 17,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: 62,
      backgroundColor: scheme.surface,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return text.labelMedium?.copyWith(
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          size: 22,
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
