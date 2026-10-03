import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Shown while the saved sign-in is restored. Same #121212 as the Android launch
/// screen and the login page, so startup reads as one continuous screen.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Semantics(
        label: 'Checking your session…',
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('BudgetMate',
                  style: inter(size: FontSizes.x4l, weight: FontWeight.w700, color: Colors.white, letterSpacing: -0.9)),
              const SizedBox(height: 20),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: const LinearProgressIndicator(minHeight: 3, color: Colors.white, backgroundColor: AppColors.zinc300Dim),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
