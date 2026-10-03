import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Replaces Flutter's red error screen with the web ErrorBoundary's friendly message.
void installErrorHandlers() {
  ErrorWidget.builder = (details) {
    if (kDebugMode) return ErrorWidget(details.exception);
    return const _FriendlyError();
  };
}

class _FriendlyError extends StatelessWidget {
  const _FriendlyError();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>() ?? AppColors.light;
    return Container(
      color: c.paper,
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Something went wrong',
            textAlign: TextAlign.center, style: inter(size: FontSizes.x2l, weight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 8),
        Text('Please go back and try again.', textAlign: TextAlign.center, style: inter(size: FontSizes.sm, color: c.news)),
      ]),
    );
  }
}
