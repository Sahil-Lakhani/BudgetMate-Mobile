import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'footer.dart';
import 'offline_banner.dart';
import 'ui.dart';

class _NavItem {
  const _NavItem(this.icon, this.label, this.path, {this.profile = false, this.alsoActiveOn = const []});
  final IconData icon;
  final String label;
  final String path;
  final bool profile; // shows the user's Google photo instead of an icon
  final List<String> alsoActiveOn;
}

const _navItems = [
  _NavItem(LucideIcons.layoutDashboard, 'Dashboard', '/'),
  _NavItem(LucideIcons.receipt, 'Expenses', '/expenses'),
  _NavItem(LucideIcons.scanLine, 'Scan', '/scan'),
  _NavItem(LucideIcons.users, 'Groups', '/groups'),
  // Profile = the Settings page; Analytics opens from there
  _NavItem(LucideIcons.user, 'Profile', '/settings', profile: true, alsoActiveOn: ['/analytics']),
];

bool _isActive(_NavItem item, String path) =>
    path == item.path || (item.path != '/' && path.startsWith('${item.path}/')) || item.alsoActiveOn.contains(path);

/// App frame: header with the app name, plus a floating pill navbar at the bottom.
/// The theme switch lives on the Profile page.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final path = GoRouterState.of(context).uri.path;

    // Status bar icons must contrast with the header (dark icons on the light theme)
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.paper,
        // Content scrolls behind the floating bar; PageScroll pads for it
        extendBody: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(73),
          child: Container(
            decoration: BoxDecoration(
              color: c.card,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 72,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/'),
                        child: Text(
                          'BudgetMate',
                          style: inter(size: FontSizes.xl, weight: FontWeight.w700, color: c.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(child: child),
          ],
        ),
        bottomNavigationBar: _PillNavBar(currentPath: path),
      ),
    );
  }
}

/// Floating rounded bar. One filled pill sits behind the tabs and slides to the active
/// tab; tab widths animate on the same curve so the pill always lines up with its tab.
class _PillNavBar extends ConsumerWidget {
  const _PillNavBar({required this.currentPath});
  final String currentPath;

  static const _duration = Duration(milliseconds: 380);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final unread = ref.watch(unreadNotificationsProvider).value?.length ?? 0;
    final activeIndex = _navItems.indexWhere((item) => _isActive(item, currentPath));
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion ? Duration.zero : _duration;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: c.isDark ? 0.5 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Semantics(
          container: true,
          label: 'Main navigation',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final total = constraints.maxWidth;
              final count = _navItems.length;
              // Active tab is wide enough for icon + label; the rest share what's left
              final activeWidth = activeIndex < 0 ? total / count : (total * 0.36).clamp(112.0, 150.0);
              final inactiveWidth = activeIndex < 0 ? total / count : (total - activeWidth) / (count - 1);

              return Stack(
                children: [
                  // The sliding pill
                  AnimatedPositioned(
                    duration: duration,
                    curve: _curve,
                    left: activeIndex < 0 ? 0 : activeIndex * inactiveWidth,
                    top: 0,
                    bottom: 0,
                    width: activeWidth,
                    child: AnimatedOpacity(
                      duration: duration,
                      opacity: activeIndex < 0 ? 0 : 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                  ),
                  // Fill the bar's height so each tab is vertically centred in the pill
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < count; i++)
                          AnimatedContainer(
                            duration: duration,
                            curve: _curve,
                            width: i == activeIndex ? activeWidth : inactiveWidth,
                            child: _PillTab(
                              item: _navItems[i],
                              active: i == activeIndex,
                              badge: _navItems[i].path == '/groups' && i != activeIndex ? unread : 0,
                              duration: duration,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({required this.item, required this.active, required this.badge, required this.duration});
  final _NavItem item;
  final bool active;
  final int badge;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      button: true,
      selected: active,
      label: badge > 0 ? '${item.label}, $badge unread' : item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (active) return;
          HapticFeedback.selectionClick();
          context.go(item.path);
        },
        // Icon colour cross-fades as the pill arrives / leaves
        child: TweenAnimationBuilder<Color?>(
          duration: duration,
          curve: Curves.easeOut,
          tween: ColorTween(end: active ? c.paper : c.ink.withValues(alpha: 0.6)),
          builder: (context, fg, _) => ClipRect(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  // A small pop on the icon when its tab becomes active
                  scale: active ? 1.0 : 0.92,
                  duration: duration,
                  curve: Curves.easeOutBack,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      item.profile ? _TabAvatar(color: fg!) : Icon(item.icon, size: 20, color: fg),
                      if (badge > 0)
                        Positioned(
                          top: -6,
                          right: -8,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 16),
                            height: 16,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.red500,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: c.card, width: 1.5),
                            ),
                            child: Text(
                              badge > 9 ? '9+' : '$badge',
                              style: inter(size: 9, weight: FontWeight.w600, color: Colors.white, height: 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Label fades and slides in beside the icon; the old tab's label fades out
                Flexible(
                  child: AnimatedSize(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0.25, 0), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      ),
                      child: active
                          ? Padding(
                              key: const ValueKey('label'),
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: inter(size: FontSizes.sm, weight: FontWeight.w600, color: fg),
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('none')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The user's Google photo (or initial) used as the Profile tab icon.
class _TabAvatar extends ConsumerWidget {
  const _TabAvatar({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Container(
      width: 22,
      height: 22,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
      child: Avatar(url: user?.photoURL, name: user?.displayName ?? user?.email ?? '', size: 16),
    );
  }
}

/// Scrollable page body with the legal footer underneath (web: <main>). The bottom
/// padding clears the floating navbar (Scaffold.extendBody reports it in MediaQuery).
class PageScroll extends StatelessWidget {
  const PageScroll({super.key, required this.children, this.spacing = 24, this.maxWidth, this.onRefresh});
  final List<Widget> children;
  final double spacing;
  final double? maxWidth;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: spacing, children: children);
    if (maxWidth != null) {
      body = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth!),
          child: body,
        ),
      );
    }
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        body,
        const SizedBox(height: 48),
        Container(
          padding: const EdgeInsets.only(top: 24),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: const Footer(),
        ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, color: c.ink, backgroundColor: c.card, child: list);
  }
}
