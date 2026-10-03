import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/utils.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/loading.dart';
import '../widgets/ui.dart';

/// Last 6 months' totals, oldest first (Analytics.jsx computeMonthlyData).
List<({String name, double total})> monthlyTotals(List<Txn> data, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final months = [
    for (var i = 5; i >= 0; i--) DateTime(today.year, today.month - i, 1),
  ];
  final totals = {for (final m in months) localMonth(m): 0.0};
  for (final t in data) {
    if (totals.containsKey(t.month)) totals[t.month] = totals[t.month]! + t.total;
  }
  return [for (final m in months) (name: DateFormat.MMM('en_US').format(m), total: double.parse(totals[localMonth(m)]!.toStringAsFixed(2)))];
}

/// Top 5 categories by spend with item counts (Analytics.jsx computeCategories).
List<({String name, double amount, int count})> topCategories(List<Txn> data) {
  final totals = <String, double>{};
  final counts = <String, int>{};
  for (final t in data) {
    if (t.isRefund) continue;
    if (t.raw['lineItems'] is List) {
      for (final item in t.lineItems) {
        totals[item.category] = (totals[item.category] ?? 0) + item.total;
        counts[item.category] = (counts[item.category] ?? 0) + 1;
      }
    } else {
      final cat = t.category ?? 'Other';
      totals[cat] = (totals[cat] ?? 0) + t.total;
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
  }
  final list = [for (final e in totals.entries) (name: e.key, amount: double.parse(e.value.toStringAsFixed(2)), count: counts[e.key] ?? 0)]
    ..sort((a, b) => b.amount.compareTo(a.amount));
  return list.take(5).toList();
}

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(transactionsProvider);
    if (txAsync.isLoading && !txAsync.hasValue) return const PageSkeleton(SkeletonKind.analytics, label: 'Loading analytics…');
    if (txAsync.hasError && !txAsync.hasValue) {
      return const StatusText('Failed to load analytics data. Please check your connection.', error: true);
    }
    final c = context.colors;
    final fc = ref.watch(formatCurrencyProvider);
    final data = txAsync.value!;
    final monthly = monthlyTotals(data);
    final cats = topCategories(data);
    final currentMonthTotal = monthly.last.total;

    Widget card(String title, Widget body) => AppCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [CardTitle(title), const SizedBox(height: 24), body]),
          ),
        );
    Widget summaryBox(String title, String text) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.newsLight.withValues(alpha: 0.2), border: Border.all(color: c.newsLight)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: inter(size: FontSizes.base, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 4),
            Text(text, style: inter(size: FontSizes.sm, color: c.news)),
          ]),
        );

    return PageScroll(
      onRefresh: () async => ref.invalidate(transactionsProvider),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Opened from Settings, so it needs its own way back
          AppIconButton(
            icon: LucideIcons.arrowLeft,
            tooltip: 'Back to profile',
            onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const PageTitle('Analytics', size: FontSizes.x3l),
              const SizedBox(height: 8),
              Text('Deep dive into your spending habits.', style: inter(size: FontSizes.base, color: c.news)),
            ]),
          ),
        ]),
        card('Monthly Spending Trend', SizedBox(height: 300, child: _MonthlyBarChart(monthly: monthly, fc: fc))),
        card(
          'Top Categories',
          cats.isEmpty
              ? Text('No spending data yet. Add some transactions to see your breakdown.', style: inter(size: FontSizes.sm, color: c.news))
              : Column(spacing: 16, children: [
                  for (var i = 0; i < cats.length; i++)
                    Row(children: [
                      Text('${i + 1}', style: inter(size: FontSizes.lg, weight: FontWeight.w700, color: c.newsLight)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(cats[i].name, style: inter(size: FontSizes.base, weight: FontWeight.w500, color: c.ink)),
                          Text('${cats[i].count} ${cats[i].count == 1 ? 'item' : 'items'}', style: inter(size: FontSizes.xs, color: c.news)),
                        ]),
                      ),
                      Text(fc(cats[i].amount), style: inter(size: FontSizes.base, weight: FontWeight.w700, color: c.ink)),
                    ]),
                ]),
        ),
        card(
          'Summary',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            summaryBox('Total Transactions', '${data.length} ${data.length == 1 ? 'transaction' : 'transactions'} recorded'),
            summaryBox('This Month', '${fc(currentMonthTotal)} spent'),
          ]),
        ),
      ],
    );
  }
}

class _MonthlyBarChart extends StatelessWidget {
  const _MonthlyBarChart({required this.monthly, required this.fc});
  final List<({String name, double total})> monthly;
  final String Function(Object?) fc;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final axis = c.isDark ? const Color(0xFFA1A1A1) : const Color(0xFF808080);
    final grid = c.isDark ? const Color(0xFF262626) : const Color(0xFFE0E0E0);
    final maxY = monthly.fold<double>(0, (m, e) => e.total > m ? e.total : m);
    final top = maxY <= 0 ? 4.0 : _niceCeil(maxY);
    final axisStyle = inter(size: FontSizes.xs, color: axis);

    return BarChart(BarChartData(
      maxY: top,
      minY: 0,
      alignment: BarChartAlignment.spaceAround,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: top / 4,
        getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1, dashArray: const [3, 3]),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(monthly[v.toInt()].name, style: axisStyle)),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 64,
            interval: top / 4,
            getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(fc(v), style: axisStyle, maxLines: 1)),
          ),
        ),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => c.isDark ? const Color(0xFF171717) : Colors.white,
          tooltipBorder: BorderSide(color: c.isDark ? const Color(0xFF262626) : const Color(0xFF1A1A1A)),
          tooltipBorderRadius: BorderRadius.circular(8),
          getTooltipItem: (group, _, rod, _) => BarTooltipItem(
            '${monthly[group.x].name}\n',
            inter(size: FontSizes.sm, weight: FontWeight.w600, color: c.isDark ? const Color(0xFFEDEDED) : const Color(0xFF1A1A1A)),
            children: [
              TextSpan(
                text: 'Spent : ${fc(rod.toY)}',
                style: inter(size: FontSizes.sm, color: c.isDark ? const Color(0xFFEDEDED) : const Color(0xFF1A1A1A)),
              ),
            ],
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < monthly.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: monthly[i].total < 0 ? 0 : monthly[i].total,
              color: c.primary,
              width: 28,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ]),
      ],
    ));
  }

  /// Rounds up to a "nice" axis maximum (1, 2, 2.5, 5 × 10^n), like Recharts' auto domain.
  static double _niceCeil(double v) {
    var magnitude = 1.0;
    while (magnitude * 10 <= v) {
      magnitude *= 10;
    }
    while (magnitude > v) {
      magnitude /= 10;
    }
    for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (m * magnitude >= v) return m * magnitude;
    }
    return 10 * magnitude;
  }
}
