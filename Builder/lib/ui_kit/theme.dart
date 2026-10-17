import 'package:flutter/material.dart';
import 'tokens.dart';

abstract final class BuilderTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    fontFamily: 'Onest',
    scaffoldBackgroundColor: BuilderColors.background,
    colorScheme: const ColorScheme.light(
      primary: BuilderColors.primary,
      onPrimary: Colors.white,
      primaryContainer: BuilderColors.primaryTint,
      onPrimaryContainer: BuilderColors.primary,
      secondary: BuilderColors.accent,
      onSecondary: BuilderColors.ink,
      error: BuilderColors.warning,
      onError: Colors.white,
      errorContainer: BuilderColors.warningTint,
      surface: BuilderColors.surface,
      onSurface: BuilderColors.ink,
      onSurfaceVariant: BuilderColors.inkSecondary,
      outline: BuilderColors.line,
    ),
    textTheme: const TextTheme(
      displaySmall: BuilderType.display,
      headlineLarge: BuilderType.h1,
      headlineMedium: BuilderType.h2,
      titleLarge: BuilderType.h3,
      titleMedium: BuilderType.title,
      bodyLarge: BuilderType.body,
      bodyMedium: BuilderType.body,
      bodySmall: BuilderType.small,
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      labelSmall: BuilderType.label,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'Onest',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: BuilderColors.ink,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: BuilderColors.line,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BuilderColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BuilderColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BuilderColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BuilderColors.warning, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BuilderColors.warning, width: 2),
      ),
      hintStyle: const TextStyle(color: BuilderColors.inkSecondary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: BuilderColors.ink,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 350),
    ),
  );
}
