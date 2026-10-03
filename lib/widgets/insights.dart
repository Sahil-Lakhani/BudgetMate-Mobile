// Port of components/Insights.jsx: AI insights (opt-in, cached per month) + rule-based
// tips, shown as an auto-advancing (8s) slideshow with dot pagination.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/currency.dart';
import '../core/utils.dart';
import '../data/local_data.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

class RuleTip {
  const RuleTip({required this.title, required this.message, required this.icon, required this.iconColor, required this.priority});
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;
  final double priority;
}

/// Rule-based tips (price comparison, month-over-month trend, merchant habit). Pure for testing.
List<RuleTip> ruleBasedInsights(List<Txn> transactions, String currency, {DateTime? now}) {
  if (transactions.isEmpty) return const [];
  String fc(double a) => formatCurrency(a, currency);
  final today = now ?? DateTime.now();
  final currentMonth = localMonth(today);
  final lastMonth = localMonth(DateTime(today.year, today.month - 1, 1));
  final tips = <RuleTip>[];

  // 1–2. Price comparison of the same item across merchants (last 3 months)
  final groups = <String, List<({double unitPrice, String merchant, String date})>>{};
  for (final t in transactions) {
    for (final item in t.lineItems) {
      final price = item.totalPrice ?? item.price;
      if (!(item.price > 0 || price > 0)) continue;
      groups.putIfAbsent(item.name.toLowerCase().trim(), () => []).add((unitPrice: item.price, merchant: t.merchant, date: t.date));
    }
  }
  final threeMonthsAgo = DateTime(today.year, today.month - 3, today.day, today.hour, today.minute);
  groups.forEach((name, items) {
    if (items.length < 2) return;
    final recent = items.where((i) => !(DateTime.tryParse(i.date) ?? DateTime(0)).isBefore(threeMonthsAgo)).toList();
    if (recent.length < 2) return;
    recent.sort((a, b) => a.unitPrice.compareTo(b.unitPrice));
    final cheapest = recent.first;
    final expensive = recent.last;
    if (expensive.unitPrice > cheapest.unitPrice * 1.1 && cheapest.merchant != expensive.merchant) {
      tips.add(
        RuleTip(
          title: 'Smart Shopper Tip',
          message:
              'You paid ${fc(expensive.unitPrice)} for $name at ${expensive.merchant}, but it was only ${fc(cheapest.unitPrice)} at ${cheapest.merchant}.',
          icon: LucideIcons.lightbulb,
          iconColor: AppColors.yellow500,
          priority: expensive.unitPrice - cheapest.unitPrice,
        ),
      );
    }
  });

  // 3. Spending trend vs last month
  var currentTotal = 0.0, lastTotal = 0.0;
  for (final t in transactions) {
    if (t.date.startsWith(currentMonth)) currentTotal += t.total;
    if (t.date.startsWith(lastMonth)) lastTotal += t.total;
  }
  if (currentTotal > 0 && lastTotal > 0) {
    final diff = currentTotal - lastTotal;
    final percent = (diff / lastTotal * 100).toStringAsFixed(1);
    if (diff > 0) {
      tips.add(
        RuleTip(
          title: 'Spending Alert',
          message: "You've spent ${fc(diff)} ($percent%) more this month compared to last month.",
          icon: LucideIcons.trendingUp,
          iconColor: AppColors.red500,
          priority: 100,
        ),
      );
    } else if (diff < 0) {
      tips.add(
        RuleTip(
          title: 'Great Job!',
          message: "You've saved ${fc(diff.abs())} (${(diff / lastTotal * 100).abs().toStringAsFixed(1)}%) compared to last month!",
          icon: LucideIcons.trendingDown,
          iconColor: AppColors.green500,
          priority: 90,
        ),
      );
    }
  }

  // 4. Most frequent merchant this month
  final counts = <String, int>{};
  for (final t in transactions) {
    if (t.date.startsWith(currentMonth)) counts[t.merchant] = (counts[t.merchant] ?? 0) + 1;
  }
  String? top;
  var maxVisits = 0;
  counts.forEach((m, n) {
    if (n > maxVisits) {
      maxVisits = n;
      top = m;
    }
  });
  if (top != null && maxVisits > 2) {
    tips.add(
      RuleTip(
        title: 'Buying Habit',
        message: "You've visited $top $maxVisits times this month.",
        icon: LucideIcons.shoppingBag,
        iconColor: AppColors.blue500,
        priority: 10,
      ),
    );
  }

  tips.sort((a, b) => b.priority.compareTo(a.priority));
  final seen = <String>{};
  return tips.where((t) => seen.add(t.message)).take(3).toList();
}

class _Slide {
  const _Slide.loading() : ai = null, rule = null, loading = true;
  const _Slide.ai(this.ai) : rule = null, loading = false;
  const _Slide.rule(this.rule) : ai = null, loading = false;
  final Map<String, dynamic>? ai;
  final RuleTip? rule;
  final bool loading;
  bool get isAi => ai != null || loading;
}

class Insights extends ConsumerStatefulWidget {
  const Insights({super.key, required this.transactions});
  final List<Txn> transactions;

  @override
  ConsumerState<Insights> createState() => _InsightsState();
}

class _InsightsState extends ConsumerState<Insights> {
  List<Map<String, dynamic>> _aiInsights = const [];
  bool _loadingAI = false;
  int _current = 0;
  Timer? _timer;
  int _slideCount = 0;
  String? _fetchedFor; // avoid refetching on every rebuild

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer(int count) {
    if (count == _slideCount) return;
    _slideCount = count;
    _timer?.cancel();
    if (_current >= count) _current = 0;
    if (count <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) setState(() => _current = (_current + 1) % _slideCount);
    });
  }

  Future<void> _maybeFetchAI(bool aiEnabled, String currency) async {
    final uid = ref.read(uidProvider);
    if (!aiEnabled || uid == null || widget.transactions.isEmpty) return;
    final key = LocalData.insightsCacheKey(uid, localMonth());
    final token = '$key|$currency|${widget.transactions.length}';
    if (_fetchedFor == token) return;
    _fetchedFor = token;

    final local = ref.read(localDataProvider);
    final cached = local.getString(key);
    if (cached != null) {
      try {
        final list = (jsonDecode(cached) as List).cast<Map<String, dynamic>>();
        if (mounted) setState(() => _aiInsights = list);
        return;
      } catch (_) {
        await local.remove(key);
      }
    }

    final now = DateTime.now();
    final lastMonth = localMonth(DateTime(now.year, now.month - 1, 1));
    final prev = widget.transactions.where((t) => t.date.startsWith(lastMonth) && !t.isRefund).toList();
    if (prev.length < 5) return;

    setState(() => _loadingAI = true);
    try {
      final result = await ref.read(geminiServiceProvider).generateMonthlyInsights(prev, currency);
      final suggestions = result['suggestions'];
      if (suggestions is List) {
        final list = suggestions.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        if (mounted) setState(() => _aiInsights = list);
        await local.setString(key, jsonEncode(list));
      }
    } catch (e) {
      debugPrint('Error fetching AI insights: $e');
    } finally {
      if (mounted) setState(() => _loadingAI = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final aiEnabled = ref.watch(settingsProvider).value?.aiInsights ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeFetchAI(aiEnabled, currency);
    });

    final slides = <_Slide>[
      if (_loadingAI) const _Slide.loading() else ..._aiInsights.map(_Slide.ai),
      ...ruleBasedInsights(widget.transactions, currency).map(_Slide.rule),
    ];
    _restartTimer(slides.length);
    if (slides.isEmpty) return const SizedBox.shrink();
    final item = slides[_current.clamp(0, slides.length - 1)];

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: AppCard(
        leftAccent: c.ink,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Row(
                children: [
                  Icon(item.isAi ? LucideIcons.sparkles : LucideIcons.lightbulb, size: 20, color: item.isAi ? c.ink : c.news),
                  const SizedBox(width: 8),
                  Expanded(child: CardTitle(item.isAi ? 'AI Finance Assistant' : 'Insights & Tips', size: FontSizes.lg)),
                  Row(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < slides.length; i++)
                        Semantics(
                          button: true,
                          label: 'Go to slide ${i + 1}',
                          child: GestureDetector(
                            onTap: () => setState(() => _current = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: i == _current ? 16 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i == _current ? c.ink : c.newsLight,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 200,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Center(
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0.05, 0), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(key: ValueKey(_current * 1000 + slides.length), child: _slideBody(item, currency)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slideBody(_Slide item, String currency) {
    final c = context.colors;
    if (item.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(LucideIcons.sparkles, size: 16, color: c.news),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Analyzing last month's spending patterns...",
                style: inter(size: FontSizes.sm, color: c.news),
              ),
            ),
          ],
        ),
      );
    }
    if (item.ai != null) {
      final ai = item.ai!;
      final greenBg = c.isDark ? const Color(0x4D14532D) : const Color(0xFFDCFCE7);
      final greenFg = c.isDark ? AppColors.green400 : AppColors.green700;
      return SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${ai['title'] ?? ''}',
              style: inter(size: FontSizes.base, weight: FontWeight.w700, color: c.ink),
            ),
            const SizedBox(height: 4),
            Text(
              '${ai['insight'] ?? ''}',
              style: inter(size: FontSizes.sm, color: c.news, height: 1.625),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: greenBg, borderRadius: BorderRadius.circular(Radii.md)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.trendingDown, size: 12, color: greenFg),
                      const SizedBox(width: 4),
                      Text(
                        'Save ~${formatCurrency(ai['estimated_saving_per_month'], currency)}',
                        style: inter(size: FontSizes.xs, weight: FontWeight.w500, color: greenFg),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    'Action: ${ai['action'] ?? ''}',
                    style: inter(size: FontSizes.xs, color: c.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'AI-generated suggestion — may be inaccurate. Not financial advice.',
              style: inter(size: FontSizes.xs11, color: c.news),
            ),
          ],
        ),
      );
    }
    final tip = item.rule!;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The web hides the tip icon below 640px, so phones show title + message only
          Text(
            tip.title,
            style: inter(size: FontSizes.base, weight: FontWeight.w700, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            tip.message,
            style: inter(size: FontSizes.sm, color: c.news, height: 1.625),
          ),
        ],
      ),
    );
  }
}
