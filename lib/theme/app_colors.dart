import 'package:flutter/material.dart';

/// Design tokens copied 1:1 from the web app's `src/index.css` (`:root` and `.dark`).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.paper,
    required this.ink,
    required this.news,
    required this.newsLight,
    required this.card,
    required this.border,
    required this.primary,
    required this.secondary,
    required this.isDark,
  });

  final Color paper; // page background
  final Color ink; // primary text
  final Color news; // secondary text
  final Color newsLight; // subtle fills
  final Color card;
  final Color border;
  final Color primary; // violet accent
  final Color secondary; // emerald accent
  final bool isDark;

  static const light = AppColors(
    paper: Color(0xFFF4F4F5), // Zinc 100
    ink: Color(0xFF18181B), // Zinc 900
    news: Color(0xFF71717A), // Zinc 500
    newsLight: Color(0xFFE4E4E7), // Zinc 200
    card: Color(0xFFFFFFFF),
    border: Color(0xFFD4D4D8), // Zinc 300
    primary: Color(0xFF8B5CF6), // Violet 500
    secondary: Color(0xFF10B981), // Emerald 500
    isDark: false,
  );

  static const dark = AppColors(
    paper: Color(0xFF09090B), // Zinc 950
    ink: Color(0xFFFAFAFA), // Zinc 50
    news: Color(0xFFA1A1AA), // Zinc 400
    newsLight: Color(0xFF27272A), // Zinc 800
    card: Color(0xFF18181B), // Zinc 900
    border: Color(0xFF27272A), // Zinc 800
    primary: Color(0xFFA78BFA), // Violet 400
    secondary: Color(0xFF34D399), // Emerald 400
    isDark: true,
  );

  // Tailwind palette colors used directly by the web pages
  static const red400 = Color(0xFFF87171);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const green400 = Color(0xFF4ADE80);
  static const green500 = Color(0xFF22C55E);
  static const green600 = Color(0xFF16A34A);
  static const green700 = Color(0xFF15803D);
  static const amber500 = Color(0xFFF59E0B);
  static const yellow500 = Color(0xFFEAB308);
  static const blue500 = Color(0xFF3B82F6);
  static const zinc300 = Color(0xFFD4D4D8);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc300Dim = Color(0x33D4D4D8); // zinc-300 at 20%, splash progress track

  /// Red for error text, matching `text-red-500`.
  Color get danger => red500;

  /// Positive amounts (refunds), matching `text-green-600`.
  Color get positive => green600;

  /// Chart palette from Dashboard.jsx / Analytics.jsx
  List<Color> get chart => isDark
      ? const [Color(0xFFA78BFA), Color(0xFF34D399), Color(0xFFFBBF24), Color(0xFFF87171), Color(0xFF60A5FA), Color(0xFFF472B6), Color(0xFF818CF8)]
      : const [Color(0xFF8B5CF6), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFF3B82F6), Color(0xFFEC4899), Color(0xFF6366F1)];

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      paper: Color.lerp(paper, other.paper, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      news: Color.lerp(news, other.news, t)!,
      newsLight: Color.lerp(newsLight, other.newsLight, t)!,
      card: Color.lerp(card, other.card, t)!,
      border: Color.lerp(border, other.border, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
