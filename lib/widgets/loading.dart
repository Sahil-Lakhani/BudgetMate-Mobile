// Loading placeholders: a shimmer sweep over grey "bones" shaped like the page that is
// about to appear, so layouts don't jump when data arrives.
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Drives the shimmer of every [Bone] below it from one animation (1.4s loop).
/// Holds still when the system asks for reduced motion.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return _ShimmerScope(animation: still ? null : _c, child: widget.child);
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.animation, required super.child});
  final Animation<double>? animation;

  static Animation<double>? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;

  @override
  bool updateShouldNotify(_ShimmerScope old) => old.animation != animation;
}

/// One grey placeholder block; a highlight sweeps across it inside a [Shimmer].
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 14, this.radius = 6, this.circle = false});
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = c.newsLight;
    final highlight = c.isDark ? const Color(0xFF3F3F46) : const Color(0xFFF4F4F5);
    final shape = circle ? BoxShape.circle : BoxShape.rectangle;
    final borderRadius = circle ? null : BorderRadius.circular(radius);
    final animation = _ShimmerScope.of(context);

    BoxDecoration deco(double t) => BoxDecoration(
          shape: shape,
          borderRadius: borderRadius,
          gradient: LinearGradient(
            // Highlight band travels from off the left edge to off the right edge
            begin: Alignment(-3 + 4 * t, 0),
            end: Alignment(-1 + 4 * t, 0),
            colors: [base, highlight, base],
            stops: const [0.25, 0.5, 0.75],
          ),
        );

    final size = Size(circle ? height : (width ?? double.infinity), height);
    if (animation == null) {
      return Container(width: size.width, height: size.height, decoration: BoxDecoration(color: base, shape: shape, borderRadius: borderRadius));
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) => Container(width: size.width, height: size.height, decoration: deco(animation.value)),
    );
  }
}

/// Card outline with bones inside (cards themselves don't shimmer, only their content).
class _BoneCard extends StatelessWidget {
  const _BoneCard({required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.lg), border: Border.all(color: c.border)),
      child: child,
    );
  }
}

Widget _rows(int count, {bool avatar = true}) => Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              if (avatar) ...[const Bone(height: 40, circle: true), const SizedBox(width: 16)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                  FractionallySizedBox(widthFactor: 0.4 + (i % 3) * 0.15, child: const Bone(height: 14)),
                  const FractionallySizedBox(widthFactor: 0.35, child: Bone(height: 10)),
                ]),
              ),
              const SizedBox(width: 16),
              const Bone(width: 64, height: 16),
            ]),
          ),
      ],
    );

/// The page shapes the app shows while loading.
enum SkeletonKind { dashboard, list, analytics, detail, groups }

class PageSkeleton extends StatelessWidget {
  const PageSkeleton(this.kind, {super.key, this.label = 'Loading…'});
  final SkeletonKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Shimmer(
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: _children(),
          ),
        ),
      ),
    );
  }

  List<Widget> _children() {
    const gap = SizedBox(height: 24);
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: const [
      Bone(width: 220, height: 28),
      Bone(width: 160, height: 14),
    ]);
    switch (kind) {
      case SkeletonKind.dashboard:
        Widget tile() => const Expanded(
              child: _BoneCard(
                padding: EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                  Bone(width: 100, height: 12),
                  Bone(width: 110, height: 24),
                  Bone(width: 80, height: 10),
                ]),
              ),
            );
        return [
          title,
          gap,
          Row(spacing: 16, children: [tile(), tile()]),
          const SizedBox(height: 16),
          Row(spacing: 16, children: [tile(), tile()]),
          gap,
          const _BoneCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Bone(width: 180, height: 18),
              SizedBox(height: 32),
              Center(child: Bone(height: 160, circle: true)),
              SizedBox(height: 16),
            ]),
          ),
          gap,
          _BoneCard(child: _rows(4, avatar: false)),
        ];
      case SkeletonKind.list:
        return [
          Row(spacing: 8, children: const [
            Bone(width: 140, height: 40, radius: Radii.lg),
            Bone(width: 110, height: 40, radius: Radii.lg),
            Expanded(child: Bone(height: 40, radius: Radii.lg)),
          ]),
          const SizedBox(height: 16),
          const Bone(height: 42, radius: Radii.lg),
          const SizedBox(height: 12),
          Row(spacing: 8, children: const [
            Bone(width: 48, height: 36, radius: Radii.lg),
            Bone(width: 90, height: 36, radius: Radii.lg),
            Bone(width: 100, height: 36, radius: Radii.lg),
          ]),
          const SizedBox(height: 12),
          const Bone(height: 64, radius: Radii.lg),
          const SizedBox(height: 12),
          _BoneCard(padding: const EdgeInsets.all(12), child: _rows(6)),
        ];
      case SkeletonKind.analytics:
        return [
          title,
          gap,
          _BoneCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Bone(width: 200, height: 20),
              const SizedBox(height: 32),
              SizedBox(
                height: 200,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  for (final h in const [80.0, 130.0, 60.0, 170.0, 110.0, 150.0]) Bone(width: 28, height: h, radius: 4),
                ]),
              ),
            ]),
          ),
          gap,
          _BoneCard(child: _rows(4, avatar: false)),
        ];
      case SkeletonKind.detail:
        return [
          const Row(children: [Bone(width: 32, height: 32, radius: 8), SizedBox(width: 16), Bone(width: 200, height: 26)]),
          gap,
          _BoneCard(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Row(children: [
                Bone(height: 48, circle: true),
                SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [Bone(width: 140, height: 18), Bone(width: 100, height: 12)])),
                Bone(width: 70, height: 22),
              ]),
              const SizedBox(height: 24),
              _rows(3, avatar: false),
            ]),
          ),
        ];
      case SkeletonKind.groups:
        return [
          title,
          gap,
          const _BoneCard(
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [Bone(width: 60, height: 10), Bone(width: 80, height: 20)])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [Bone(width: 70, height: 10), Bone(width: 80, height: 20)])),
            ]),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < 3; i++) ...[
            _BoneCard(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6), child: _rows(1)),
            const SizedBox(height: 12),
          ],
        ];
    }
  }
}
