import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 16),
        child: Column(mainAxisSize: MainAxisSize.min, spacing: 16, children: [
          Text('404', style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.news)),
          Text('Page not found', style: inter(size: FontSizes.x3l, weight: FontWeight.w700, color: c.ink)),
          Text("The page you're looking for doesn't exist or has moved.",
              textAlign: TextAlign.center, style: inter(size: FontSizes.base, color: c.news)),
          AppButton(onPressed: () => context.go('/'), label: 'Go to dashboard', radius: Radii.md),
        ]),
      ),
    );
  }
}
