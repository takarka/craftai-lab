import 'package:flutter/material.dart';

/// UK1: a shared vocabulary for every Builder component.
abstract final class BuilderColors {
  static const primary = Color(0xFF0047BA);
  static const primaryPressed = Color(0xFF003A99);
  static const primaryTint = Color(0xFFE3ECFB);
  static const accent = Color(0xFFE8772E);
  static const accentSoft = Color(0xFFFFB27A);
  static const warningTint = Color(0xFFFFE8D6);
  static const warning = Color(0xFFA23B00);
  static const ink = Color(0xFF0B1B33);
  static const inkSecondary = Color(0xFF4A5872);
  static const inkDisabled = Color(0xFF8A96AD);
  static const line = Color(0xFFD3DBEA);
  static const lineDisabled = Color(0xFFC4CFE3);
  static const accentBackground = Color(0xFFFFF4EA);
  static const surfaceDisabled = Color(0xFFE9EDF5);
  static const background = Color(0xFFF3F5FA);
  static const surface = Colors.white;

  static const palette = <String, Color>{
    'primary': primary,
    'primary-pressed': primaryPressed,
    'primary-tint': primaryTint,
    'accent': accent,
    'accent-soft': accentSoft,
    'warning-tint': warningTint,
    'warning': warning,
    'ink': ink,
    'ink-2': inkSecondary,
    'ink-3': inkDisabled,
    'line': line,
    'line-off': lineDisabled,
    'accent-bg': accentBackground,
    'surface-off': surfaceDisabled,
    'bg': background,
    'surface': surface,
  };
}

abstract final class BuilderSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const scale = [xxs, xs, sm, md, lg, xl, xxl];
}

abstract final class BuilderRadii {
  static const control = 12.0;
  static const chip = 13.0;
  static const tile = 14.0;
  static const card = 18.0;
  static const sheet = 24.0;
}

abstract final class BuilderShadows {
  static const card = [
    BoxShadow(color: Color(0x140B1B33), offset: Offset(0, 1), blurRadius: 2),
  ];
  static const sheet = [
    BoxShadow(color: Color(0x240B1B33), offset: Offset(0, 8), blurRadius: 24),
  ];
}

abstract final class BuilderType {
  static const display = TextStyle(
    fontFamily: 'Onest',
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.34,
  );
  static const h1 = TextStyle(
    fontFamily: 'Onest',
    fontSize: 28,
    height: 32 / 28,
    fontWeight: FontWeight.w700,
  );
  static const h2 = TextStyle(
    fontFamily: 'Onest',
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
  );
  static const h3 = TextStyle(
    fontFamily: 'Onest',
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w700,
  );
  static const title = TextStyle(
    fontFamily: 'Onest',
    fontSize: 16,
    height: 20 / 16,
    fontWeight: FontWeight.w700,
  );
  // The brief's accessibility requirement (>=16) takes precedence over UK1's 15.
  static const body = TextStyle(
    fontFamily: 'Onest',
    fontSize: 16,
    height: 23 / 16,
    fontWeight: FontWeight.w400,
  );
  static const small = TextStyle(
    fontFamily: 'Onest',
    fontSize: 13,
    height: 18 / 13,
    color: BuilderColors.inkSecondary,
  );
  static const label = TextStyle(
    fontFamily: 'Onest',
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.72,
    color: BuilderColors.inkSecondary,
  );
  static const mono = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 12.5,
    height: 18 / 12.5,
    color: BuilderColors.inkSecondary,
  );
}
