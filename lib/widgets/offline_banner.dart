import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Amber "You're offline" bar (web: components/OfflineBanner.jsx).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, snap) {
        final results = snap.data;
        final offline = results != null && results.every((r) => r == ConnectivityResult.none);
        if (!offline) return const SizedBox.shrink();
        return Semantics(
          liveRegion: true,
          child: Container(
            width: double.infinity,
            color: AppColors.amber500,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(LucideIcons.wifiOff, size: 16, color: Colors.black),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  "You're offline. Changes can't be saved until your connection is back.",
                  style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: Colors.black),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
