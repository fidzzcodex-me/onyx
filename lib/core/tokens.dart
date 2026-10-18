import 'package:flutter/material.dart';

@immutable
class OnyxPalette extends ThemeExtension<OnyxPalette> {
  const OnyxPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.elevated,
    required this.border,
    required this.divider,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.accent,
    required this.accentHover,
    required this.accentMuted,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.terminalBg,
    required this.scrim,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color elevated;
  final Color border;
  final Color divider;
  final Color text;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;
  final Color accent;
  final Color accentHover;
  final Color accentMuted;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color terminalBg;
  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  static const dark = OnyxPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    surfaceAlt: Color(0xFF2A2A2A),
    elevated: Color(0xFF333333),
    border: Color(0xFF333333),
    divider: Color(0xFF2A2A2A),
    text: Color(0xFFE0E0E0),
    textSecondary: Color(0xFFB0B0B0),
    textMuted: Color(0xFF8C8C8C),
    textDisabled: Color(0xFF555555),
    accent: Color(0xFF4A90E2),
    accentHover: Color(0xFF5BA0F2),
    accentMuted: Color(0xFF2A4A6A),
    onAccent: Color(0xFF0B1B2E),
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFFB300),
    error: Color(0xFFEF5350),
    info: Color(0xFF29B6F6),
    terminalBg: Color(0xFF0D0D0D),
    scrim: Color(0xB3000000),
  );

  static const light = OnyxPalette(
    brightness: Brightness.light,
    bg: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF0F0F0),
    elevated: Color(0xFFFFFFFF),
    border: Color(0xFFE0E0E0),
    divider: Color(0xFFEBEBEB),
    text: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF4A4A4A),
    textMuted: Color(0xFF6B6B6B),
    textDisabled: Color(0xFFB5B5B5),
    accent: Color(0xFF1976D2),
    accentHover: Color(0xFF1565C0),
    accentMuted: Color(0xFFD6E6F7),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D32),
    warning: Color(0xFFB26A00),
    error: Color(0xFFC62828),
    info: Color(0xFF0277BD),
    terminalBg: Color(0xFF0D0D0D),
    scrim: Color(0x66000000),
  );

  @override
  OnyxPalette copyWith({Color? accent}) => OnyxPalette(
        brightness: brightness,
        bg: bg,
        surface: surface,
        surfaceAlt: surfaceAlt,
        elevated: elevated,
        border: border,
        divider: divider,
        text: text,
        textSecondary: textSecondary,
        textMuted: textMuted,
        textDisabled: textDisabled,
        accent: accent ?? this.accent,
        accentHover: accentHover,
        accentMuted: accentMuted,
        onAccent: onAccent,
        success: success,
        warning: warning,
        error: error,
        info: info,
        terminalBg: terminalBg,
        scrim: scrim,
      );

  @override
  OnyxPalette lerp(ThemeExtension<OnyxPalette>? other, double t) {
    if (other is! OnyxPalette) return this;
    return t < 0.5 ? this : other;
  }
}

extension OnyxContext on BuildContext {
  OnyxPalette get palette => Theme.of(this).extension<OnyxPalette>() ?? OnyxPalette.dark;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isWide => MediaQuery.sizeOf(this).width >= 720;
}

class Sp {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;
  static const double x16 = 64;
  static const double gutter = 16;
  static const double navHeight = 60;
  static const double tap = 48;
  static const double maxContent = 720;
}

class Rd {
  static const double control = 10;
  static const double card = 12;
  static const double dialog = 16;
  static const double sheet = 20;
  static BorderRadius get c => BorderRadius.circular(control);
  static BorderRadius get k => BorderRadius.circular(card);
  static BorderRadius get d => BorderRadius.circular(dialog);
  static BorderRadius get s => const BorderRadius.vertical(top: Radius.circular(sheet));
}

class Motion {
  static const Duration screen = Duration(milliseconds: 250);
  static const Duration detail = Duration(milliseconds: 300);
  static const Duration dialog = Duration(milliseconds: 200);
  static const Duration press = Duration(milliseconds: 100);
  static const Duration stagger = Duration(milliseconds: 50);
  static const Duration chart = Duration(milliseconds: 600);
  static const Duration splash = Duration(milliseconds: 600);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve pop = Curves.easeOutBack;
}
