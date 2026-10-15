import 'package:flutter/material.dart';

/// The BudgetMate app icon (assets/logo/icon-512.png) as a rounded tile.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32, this.semanticLabel});

  final double size;

  /// Leave null when the word "BudgetMate" is shown next to it, so screen readers skip the logo.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/logo/icon-512.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
      ),
    );
  }
}
