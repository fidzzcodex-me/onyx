import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

class OnyxFonts {
  static TextStyle mono({double size = 13, Color? color, FontWeight? weight, double? height}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height,
    );
  }

  static String get monoFamily => GoogleFonts.jetBrainsMono().fontFamily ?? 'monospace';
}

class OnyxTheme {
  static ThemeData build(OnyxPalette p) {
    final base = ThemeData(
      brightness: p.brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      colorScheme: ColorScheme(
        brightness: p.brightness,
        primary: p.accent,
        onPrimary: p.onAccent,
        secondary: p.accent,
        onSecondary: p.onAccent,
        error: p.error,
        onError: Colors.white,
        surface: p.surface,
        onSurface: p.text,
        surfaceContainerHighest: p.surfaceAlt,
        outline: p.border,
        outlineVariant: p.divider,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: p.surfaceAlt.withValues(alpha: 0.6),
      hoverColor: p.surfaceAlt.withValues(alpha: 0.5),
      dividerColor: p.divider,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );

    final inter = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: p.text,
      displayColor: p.text,
    );

    final textTheme = inter.copyWith(
      headlineMedium: inter.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: -0.4),
      headlineSmall: inter.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.2),
      titleLarge: inter.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3),
      titleMedium: inter.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.35),
      titleSmall: inter.titleSmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
      bodyLarge: inter.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
      bodyMedium: inter.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
      bodySmall: inter.bodySmall?.copyWith(fontSize: 13, height: 1.4, color: p.textSecondary),
      labelLarge: inter.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      labelMedium: inter.labelMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: p.textSecondary),
      labelSmall: inter.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.2, color: p.textMuted),
    );

    final outline = OutlineInputBorder(
      borderRadius: Rd.c,
      borderSide: BorderSide(color: p.border),
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: Rd.k, side: BorderSide(color: p.border)),
      ),
      dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: Rd.d, side: BorderSide(color: p.border)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: Rd.s),
        showDragHandle: false,
        clipBehavior: Clip.antiAlias,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.elevated,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: Rd.c, side: BorderSide(color: p.border)),
        textStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.elevated,
        contentTextStyle: textTheme.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: Rd.c, side: BorderSide(color: p.border)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceAlt,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x3),
        border: outline,
        enabledBorder: outline,
        focusedBorder: OutlineInputBorder(borderRadius: Rd.c, borderSide: BorderSide(color: p.accent, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: Rd.c, borderSide: BorderSide(color: p.error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: Rd.c, borderSide: BorderSide(color: p.error, width: 1.5)),
        hintStyle: textTheme.bodyMedium?.copyWith(color: p.textMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: p.textSecondary),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: p.accent),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: p.error),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onAccent : p.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.surfaceAlt),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.border),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : Colors.transparent),
        checkColor: WidgetStatePropertyAll(p.onAccent),
        side: BorderSide(color: p.textMuted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.surfaceAlt,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.12),
        trackHeight: 3,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceAlt,
        circularTrackColor: p.surfaceAlt,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: 0.3),
        selectionHandleColor: p.accent,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _OnyxTransitions(),
        TargetPlatform.iOS: _OnyxTransitions(),
      }),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.elevated, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
        textStyle: textTheme.bodySmall?.copyWith(color: p.text),
      ),
    );
  }
}

class _OnyxTransitions extends PageTransitionsBuilder {
  const _OnyxTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Motion.standard, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}
