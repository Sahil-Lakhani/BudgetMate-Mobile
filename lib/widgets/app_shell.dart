import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'footer.dart';
import 'offline_banner.dart';
import 'ui.dart';
import 'app_logo.dart';

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
                        child: Row(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
                          const AppLogo(size: 34),
                          Text(
                            'BudgetMate',
                            style: inter(size: FontSizes.xl, weight: FontWeight.w700, color: c.ink),
                          ),
                        ]),
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

/// Liquid Glass navbar: a glass capsule that refracts the page scrolling beneath it,
/// with a glass droplet marking the active tab. The droplet springs between tabs and
/// squashes/stretches with its speed; dragging along the bar turns it into a lens that
/// magnifies the icons and snaps to the nearest tab on release.
class _PillNavBar extends ConsumerStatefulWidget {
  const _PillNavBar({required this.currentPath});
  final String currentPath;

  @override
  ConsumerState<_PillNavBar> createState() => _PillNavBarState();
}

class _PillNavBarState extends ConsumerState<_PillNavBar> with TickerProviderStateMixin {
  static const _barHeight = 64.0;
  static const _inset = 6.0;
  static const _spring = SpringDescription(mass: 1, stiffness: 320, damping: 24);

  /// Droplet centre, in pixels from the left edge of the tab row.
  late final AnimationController _x = AnimationController.unbounded(vsync: this);

  /// 0 = resting droplet, 1 = enlarged lens while the finger is down.
  late final AnimationController _lens = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    reverseDuration: const Duration(milliseconds: 320),
  );

  double _tabWidth = 0;
  bool _dragging = false;
  int _dragIndex = -1;
  bool _placed = false;

  int get _activeIndex => _navItems.indexWhere((item) => _isActive(item, widget.currentPath));
  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;
  double _centerOf(int i) => (i + 0.5) * _tabWidth;
  int _indexAt(double x) => (x / _tabWidth).floor().clamp(0, _navItems.length - 1);

  @override
  void didUpdateWidget(_PillNavBar old) {
    super.didUpdateWidget(old);
    if (old.currentPath != widget.currentPath && !_dragging && _activeIndex >= 0) _springTo(_centerOf(_activeIndex));
  }

  @override
  void dispose() {
    _x.dispose();
    _lens.dispose();
    super.dispose();
  }

  void _springTo(double target, {double velocity = 0}) {
    if (_reduceMotion || _tabWidth == 0) {
      _x.value = target;
      return;
    }
    _x.animateWith(SpringSimulation(_spring, _x.value, target, velocity));
  }

  void _go(int i) {
    if (i == _activeIndex) {
      _springTo(_centerOf(i));
      return;
    }
    HapticFeedback.selectionClick();
    context.go(_navItems[i].path);
  }

  void _onDragStart(DragStartDetails d) {
    _dragging = true;
    _x.stop();
    _dragIndex = _indexAt(d.localPosition.dx);
    _lens.forward();
    _x.value = d.localPosition.dx.clamp(_tabWidth / 2, _tabWidth * (_navItems.length - 0.5));
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _x.value = (_x.value + d.delta.dx).clamp(_tabWidth / 2, _tabWidth * (_navItems.length - 0.5));
    final i = _indexAt(_x.value);
    if (i != _dragIndex) {
      _dragIndex = i;
      HapticFeedback.selectionClick(); // tick as the lens crosses each tab
    }
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    _lens.reverse();
    final i = _indexAt(_x.value);
    _springTo(_centerOf(i), velocity: d.velocity.pixelsPerSecond.dx);
    if (i != _activeIndex) context.go(_navItems[i].path);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unread = ref.watch(unreadNotificationsProvider).value?.length ?? 0;
    final active = _activeIndex;

    // Glass tuned per theme: a faint white veil on dark pages, a milky one on light pages
    final barSettings = LiquidGlassSettings(
      thickness: 18,
      blur: 18,
      glassColor: c.isDark ? const Color(0x9918181B) : const Color(0xA6FFFFFF),
      lightIntensity: c.isDark ? 0.6 : 0.9,
      ambientStrength: 0.3,
      refractiveIndex: 1.25,
      saturation: 1.6,
    );
    final dropSettings = LiquidGlassSettings(
      thickness: 22,
      blur: 2,
      glassColor: c.isDark ? const Color(0x26FFFFFF) : const Color(0x14000000),
      lightIntensity: 1.2,
      ambientStrength: 0.4,
      refractiveIndex: 1.45,
      chromaticAberration: 0.02,
      saturation: 1.4,
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        height: _barHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rowWidth = constraints.maxWidth - _inset * 2;
            _tabWidth = rowWidth / _navItems.length;
            if (!_placed && active >= 0) {
              _x.value = _centerOf(active);
              _placed = true;
            }

            return Semantics(
              container: true,
              label: 'Main navigation',
              child: GestureDetector(
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 1. The glass bar with the icons on it
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_barHeight / 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: c.isDark ? 0.45 : 0.12),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        // The bar never moves, so it uses live backdrop-blur glass ("fake"): the
                        // refracting renderer caches still shapes and showed stale content.
                        // The moving droplet below keeps real refraction.
                        child: LiquidGlass.withOwnLayer(
                          fake: true,
                          settings: barSettings,
                          shape: LiquidRoundedSuperellipse(
                            borderRadius: _barHeight / 2,
                            side: BorderSide(color: Colors.white.withValues(alpha: c.isDark ? 0.10 : 0.6), width: 0.8),
                          ),
                          child: GlassGlow(
                            glowColor: c.isDark ? Colors.white12 : Colors.white38,
                            hitTestBehavior: HitTestBehavior.translucent,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                    // 2. The droplet / lens (under the icons so they stay crisp)
                    if (active >= 0 || _dragging)
                      AnimatedBuilder(
                        animation: Listenable.merge([_x, _lens]),
                        builder: (context, _) {
                          // Squash & stretch: wider and flatter the faster it travels
                          final speed = _reduceMotion ? 0.0 : (_x.velocity.abs() / 2400).clamp(0.0, 0.32);
                          final lens = Curves.easeOutBack.transform(_lens.value.clamp(0.0, 1.0));
                          final baseW = _tabWidth - 4;
                          const baseH = _barHeight - _inset * 2;
                          final w = baseW * (1 + speed + 0.28 * lens);
                          final h = baseH * (1 - speed * 0.35 + 0.30 * lens);
                          return Positioned(
                            left: _inset + _x.value - w / 2,
                            top: (_barHeight - h) / 2,
                            width: w,
                            height: h,
                            child: IgnorePointer(
                              child: LiquidGlass.withOwnLayer(
                                settings: dropSettings,
                                shape: LiquidRoundedSuperellipse(
                                  borderRadius: h / 2,
                                  side: BorderSide(color: Colors.white.withValues(alpha: c.isDark ? 0.18 : 0.7), width: 0.8),
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          );
                        },
                      ),
                    // 3. Icons on top; the one under the lens grows while dragging
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(_inset),
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_x, _lens]),
                          builder: (context, _) => Row(
                            children: [
                              for (var i = 0; i < _navItems.length; i++)
                                Expanded(
                                  child: _GlassTab(
                                    item: _navItems[i],
                                    active: i == active,
                                    badge: _navItems[i].path == '/groups' && i != active ? unread : 0,
                                    magnify: _tabWidth == 0
                                        ? 0
                                        : _lens.value.clamp(0.0, 1.0) * (1 - ((_x.value - _centerOf(i)).abs() / _tabWidth)).clamp(0.0, 1.0),
                                    onTap: () => _go(i),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Icon-only tab. The active icon is full strength and slightly larger.
class _GlassTab extends StatelessWidget {
  const _GlassTab({required this.item, required this.active, required this.badge, required this.onTap, this.magnify = 0});
  final _NavItem item;
  final bool active;
  final int badge;
  final VoidCallback onTap;
  final double magnify; // 0..1, how close the dragging lens is

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: active,
      label: badge > 0 ? '${item.label}, $badge unread' : item.label,
      excludeSemantics: true,
      child: Tooltip(
        message: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: TweenAnimationBuilder<Color?>(
              duration: const Duration(milliseconds: 250),
              tween: ColorTween(end: active ? c.ink : c.ink.withValues(alpha: 0.55)),
              builder: (context, fg, _) => AnimatedScale(
                scale: active ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: Transform.scale(
                  // Follows the finger directly (no easing) while the lens passes over
                  scale: 1 + 0.3 * magnify,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      item.profile ? _TabAvatar(color: fg!) : Icon(item.icon, size: 22, color: fg),
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
              ),
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
