import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Tailwind font sizes used by the web app (text-xs … text-4xl), in logical px.
abstract final class FontSizes {
  static const double xs11 = 11;
  static const double xs = 12;
  static const double sm = 14;
  static const double base = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double x2l = 24;
  static const double x3l = 30;
  static const double x4l = 36;
}

/// Shared radii: `rounded-md` 6, `rounded-[8px]`/`rounded-lg` 8, `rounded` 4.
abstract final class Radii {
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
}

/// Inter text style in a given color — the web uses Inter for both headings and body.
TextStyle inter({
  double size = FontSizes.sm,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
  double? letterSpacing,
  TextDecoration? decoration,
}) =>
    GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      decoration: decoration,
    );

ThemeData buildTheme(AppColors c) {
  final base = c.isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  // Per-widget text uses inter(); this covers Material defaults (pickers, menus, snackbars)
  final textTheme = base.textTheme.apply(fontFamily: GoogleFonts.inter().fontFamily, bodyColor: c.ink, displayColor: c.ink);

  return base.copyWith(
    scaffoldBackgroundColor: c.paper,
    canvasColor: c.paper,
    cardColor: c.card,
    dividerColor: c.border,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    colorScheme: (c.isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
      primary: c.ink,
      onPrimary: c.paper,
      secondary: c.secondary,
      surface: c.card,
      onSurface: c.ink,
      error: AppColors.red500,
      outline: c.border,
    ),
    extensions: [c],
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c.card,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.ink,
      selectionColor: c.ink.withValues(alpha: 0.2),
      selectionHandleColor: c.ink,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.news),
    dialogTheme: DialogThemeData(backgroundColor: c.card, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.card, surfaceTintColor: Colors.transparent),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: c.ink,
      headerForegroundColor: c.paper,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.paper : c.news),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.newsLight),
      trackOutlineColor: WidgetStatePropertyAll(c.border),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: inter(color: c.paper),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
