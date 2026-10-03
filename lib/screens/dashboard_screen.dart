import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/currency.dart';
import '../core/errors.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/insights.dart';
import '../widgets/loading.dart';
import '../widgets/ui.dart';

class DashboardStats {
  const DashboardStats({
    required this.monthlyTotal,
    required this.yearlyTotal,
    required this.income,
    required this.savingsAmount,
    required this.spendableAmount,
    required this.remainingSpendable,
    required this.categoryTotals,
  });
  final double monthlyTotal;
  final double yearlyTotal;
  final double income;
  final double savingsAmount;
  final double spendableAmount;
  final double remainingSpendable;
  final Map<String, double> categoryTotals;
}

/// Same math as Dashboard.jsx calculateStats.
DashboardStats computeDashboardStats(List<Txn> data, UserSettings? settings, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final currentMonth = localMonth(today);
  var monthly = 0.0, yearly = 0.0;
  final cats = <String, double>{};

  for (final t in data) {
    if (t.date.startsWith('${today.year}-')) yearly += t.total;
    if (t.date.startsWith(currentMonth)) monthly += t.total;
    if (t.isRefund) continue; // refunds count toward totals, not category spend
    if (t.raw['lineItems'] is List) {
      for (final item in t.lineItems) {
        cats[item.category] = (cats[item.category] ?? 0) + item.total;
      }
    } else {
      final cat = t.category ?? 'Other';
      cats[cat] = (cats[cat] ?? 0) + t.total;
    }
  }

  var income = 0.0, savings = 0.0, spendable = 0.0, remaining = 0.0;
  if (settings != null && settings.hasIncome) {
    income = settings.income;
    final sv = settings.savingsValue;
    savings = settings.savingsType == 'percentage' ? income * sv / 100 : sv;
    spendable = income - savings;
    remaining = spendable - monthly;
  }
  return DashboardStats(
    monthlyTotal: monthly,
    yearlyTotal: yearly,
    income: income,
    savingsAmount: savings,
    spendableAmount: spendable,
    remainingSpendable: remaining,
    categoryTotals: cats,
  );
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _promptChecked = false;
  int? _touchedSlice;

  void _maybePromptOnboarding(UserSettings? settings) {
    if (_promptChecked) return;
    _promptChecked = true;
    if (settings == null || !settings.hasIncome) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSettingsModal();
      });
    }
  }

  void _openSettingsModal() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => const _OnboardingDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(transactionsProvider);
    final settingsAsync = ref.watch(settingsProvider);

    if ((txAsync.isLoading && !txAsync.hasValue) || (settingsAsync.isLoading && !settingsAsync.hasValue)) {
      return const PageSkeleton(SkeletonKind.dashboard, label: 'Loading dashboard…');
    }
    if (txAsync.hasError && !txAsync.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ErrorText('Failed to load your data. Please check your connection.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          AppButton(onPressed: () => ref.invalidate(transactionsProvider), label: 'Retry', radius: Radii.md),
        ]),
      );
    }

    final transactions = txAsync.value ?? const [];
    final settings = settingsAsync.value;
    _maybePromptOnboarding(settings);
    final stats = computeDashboardStats(transactions, settings);
    final fc = ref.watch(formatCurrencyProvider);
    final c = context.colors;

    return PageScroll(
      onRefresh: () async => ref.invalidate(transactionsProvider),
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PageTitle('Financial Overview'),
          const SizedBox(height: 4),
          Text('Your daily financial digest.', style: inter(size: FontSizes.sm, color: c.news)),
        ]),
        _statsGrid(stats, fc),
        // Insights carries its own bottom gap, so an empty carousel leaves no double spacing
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Insights(transactions: transactions),
          _breakdownCard(stats, fc),
        ]),
        _recentActivity(transactions, fc),
      ],
    );
  }

  Widget _statsGrid(DashboardStats s, String Function(Object?) fc) {
    final c = context.colors;
    Widget tile(String title, IconData icon, Widget value, String caption) => AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.news))),
              Icon(icon, size: 16, color: c.ink),
            ]),
            const SizedBox(height: 8),
            value,
            const SizedBox(height: 4),
            Text(caption, style: inter(size: FontSizes.xs, color: c.news)),
          ]),
        );
    Text big(String text, [Color? color]) => Text(text,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(size: FontSizes.x2l, weight: FontWeight.w700, color: color ?? c.ink));

    final tiles = [
      tile(
        'Monthly Income',
        LucideIcons.wallet,
        s.income > 0
            ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: big(fc(s.income)))
            : SizedBox(
                height: 32,
                child: AppButton(onPressed: _openSettingsModal, label: 'Set', variant: ButtonVariant.outline, radius: Radii.sm, expand: true, height: 32),
              ),
        'Total monthly earnings',
      ),
      tile('Monthly Savings', LucideIcons.trendingUp,
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: big(fc(s.savingsAmount))), 'Target savings'),
      tile(
        'Remaining Budget',
        LucideIcons.piggyBank,
        FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: big(fc(s.remainingSpendable), s.remainingSpendable < 0 ? AppColors.red500 : null)),
        'After savings & expenses',
      ),
      tile('Monthly Spent', LucideIcons.arrowDownRight,
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: big(fc(s.monthlyTotal))),
          '${DateFormat.MMMM('en_US').format(DateTime.now())} expenses'),
    ];
    return Column(spacing: 16, children: [
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [Expanded(child: tiles[0]), Expanded(child: tiles[1])])),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [Expanded(child: tiles[2]), Expanded(child: tiles[3])])),
    ]);
  }

  Widget _breakdownCard(DashboardStats s, String Function(Object?) fc) {
    final c = context.colors;
    final palette = c.chart;
    final entries = s.categoryTotals.entries.toList();
    final data = [
      for (var i = 0; i < entries.length; i++) (name: capitalize(entries[i].key), value: entries[i].value, color: palette[i % palette.length])
    ]..sort((a, b) => b.value.compareTo(a.value));
    final top = data.take(5).toList();
    final touched = _touchedSlice != null && _touchedSlice! < top.length ? top[_touchedSlice!] : null;

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.fromLTRB(24, 24, 24, 8), child: CardTitle('Spending Breakdown', size: FontSizes.lg)),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: top.isEmpty
              ? SizedBox(height: 150, child: Center(child: Text('No spending data available.', style: inter(size: FontSizes.base, color: c.news))))
              : Column(children: [
                  SizedBox(
                    height: 250,
                    child: Stack(alignment: Alignment.center, children: [
                      PieChart(PieChartData(
                        centerSpaceRadius: 60,
                        sectionsSpace: 5,
                        startDegreeOffset: -90,
                        pieTouchData: PieTouchData(touchCallback: (event, response) {
                          final i = response?.touchedSection?.touchedSectionIndex;
                          if (event.isInterestedForInteractions && i != null && i >= 0) {
                            setState(() => _touchedSlice = i);
                          }
                        }),
                        sections: [
                          for (final d in top) PieChartSectionData(value: d.value, color: d.color, radius: 20, showTitle: false),
                        ],
                      )),
                      if (touched != null)
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(touched.name, style: inter(size: FontSizes.xs, color: c.news)),
                          Text(fc(touched.value), style: inter(size: FontSizes.sm, weight: FontWeight.w600, color: c.ink)),
                        ]),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 8, children: [
                    for (final d in top)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: d.color, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(d.name, style: inter(size: FontSizes.xs, color: c.news)),
                      ]),
                  ]),
                ]),
        ),
      ]),
    );
  }

  Widget _recentActivity(List<Txn> transactions, String Function(Object?) fc) {
    final c = context.colors;
    final recent = transactions.take(7).toList();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.fromLTRB(24, 24, 24, 8), child: CardTitle('Recent Activity', size: FontSizes.lg)),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: recent.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(children: [
                    Text('No recent transactions.', style: inter(size: FontSizes.base, color: c.news)),
                    const SizedBox(height: 12),
                    AppButton(onPressed: () => context.push('/expenses/add'), label: 'Add your first transaction', radius: Radii.md),
                  ]),
                )
              : Column(children: [
                  for (var i = 0; i < recent.length; i++)
                    InkWell(
                      onTap: () => context.push('/expenses/${recent[i].id}'),
                      child: Container(
                        padding: EdgeInsets.only(bottom: i == recent.length - 1 ? 0 : 8, top: i == 0 ? 0 : 12),
                        decoration: BoxDecoration(
                          border: i == recent.length - 1 ? null : Border(bottom: BorderSide(color: c.border)),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                Text(recent[i].merchant, style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.ink, height: 1)),
                                SplitTag(recent[i]),
                              ]),
                              Text('${recent[i].isRefund ? 'Refund' : (recent[i].lineItems.isNotEmpty ? recent[i].lineItems.first.category : 'General')} • ${recent[i].date}',
                                  style: inter(size: FontSizes.xs, color: c.news)),
                            ]),
                          ),
                          Text(
                            '${recent[i].isRefund ? '+' : '-'}${fc(recent[i].total.abs())}',
                            style: inter(size: FontSizes.sm, weight: FontWeight.w700, color: recent[i].isRefund ? AppColors.green600 : c.ink),
                          ),
                        ]),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

/// Two-step onboarding: currency, then income + savings goal (Dashboard.jsx modal).
class _OnboardingDialog extends ConsumerStatefulWidget {
  const _OnboardingDialog();

  @override
  ConsumerState<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends ConsumerState<_OnboardingDialog> {
  int _step = 1;
  String _error = '';
  bool _saving = false;
  late String _currency = ref.read(currencyProvider);
  String _savingsType = 'percentage';
  final _income = TextEditingController();
  final _savings = TextEditingController();

  @override
  void dispose() {
    _income.dispose();
    _savings.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = '');
    final incomeVal = parseDecimal(_income.text);
    final savingsVal = parseDecimal(_savings.text);
    if (incomeVal == null || incomeVal <= 0) return setState(() => _error = 'Please enter a valid income greater than 0.');
    if (savingsVal == null || savingsVal < 0) return setState(() => _error = 'Please enter a savings goal of 0 or more.');
    if (_savingsType == 'percentage' && savingsVal > 100) return setState(() => _error = "A savings percentage can't be more than 100%.");
    if (_savingsType == 'fixed' && savingsVal > incomeVal) return setState(() => _error = "Your savings goal can't be larger than your income.");

    setState(() => _saving = true);
    try {
      final uid = ref.read(uidProvider)!;
      // Same field types as the web form (strings from inputs)
      await ref.read(firestoreServiceProvider).updateUserSettings(uid, {
        'currency': _currency,
        'income': _income.text.trim().replaceAll(',', '.'),
        'savingsType': _savingsType,
        'savingsValue': _savings.text.trim().replaceAll(',', '.'),
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = userMessage(e, 'Failed to save settings. Please try again.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final symbol = currencySymbol(_currency);
    final dialogBg = c.isDark ? const Color(0xFF171717) : Colors.white; // neutral-900 / white
    final dialogBorder = c.isDark ? const Color(0xFF262626) : const Color(0xFFE5E5E5);

    return Dialog(
      backgroundColor: dialogBg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: BorderSide(color: dialogBorder)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 448),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(_step == 1 ? 'Welcome to BudgetMate' : 'Setup Your Budget',
                    style: inter(size: FontSizes.lg, weight: FontWeight.w700, color: c.ink)),
              ),
              AppIconButton(icon: LucideIcons.x, tooltip: 'Close', color: c.news, size: 36, onPressed: () => Navigator.of(context).pop()),
            ]),
            Text('Step $_step of 2', style: inter(size: FontSizes.xs, color: c.news)),
            const SizedBox(height: 20),
            Row(spacing: 8, children: [
              Expanded(child: Container(height: 4, decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(99)))),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: _step == 2 ? c.ink : (c.isDark ? const Color(0xFF404040) : const Color(0xFFE5E5E5)),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            if (_step == 1) ..._stepOne(c) else ..._stepTwo(c, symbol),
          ]),
        ),
      ),
    );
  }

  List<Widget> _stepOne(AppColors c) => [
        Text('Choose your preferred currency. You can change this later in Settings.', style: inter(size: FontSizes.sm, color: c.news)),
        const SizedBox(height: 16),
        const FieldLabel('Currency'),
        const SizedBox(height: 4),
        AppSelect<String>(
          value: _currency,
          semanticLabel: 'Currency',
          options: [for (final cur in currencies) SelectOption(cur.code, cur.label)],
          onChanged: (v) => setState(() => _currency = v),
        ),
        const SizedBox(height: 24),
        AppButton(
          onPressed: () => setState(() {
            _error = '';
            _step = 2;
          }),
          label: 'Next →',
          radius: Radii.md,
          expand: true,
        ),
      ];

  List<Widget> _stepTwo(AppColors c, String symbol) => [
        Text('Enter your monthly income and savings goal to calculate your budget.', style: inter(size: FontSizes.sm, color: c.news)),
        const SizedBox(height: 16),
        FieldLabel('Monthly Income ($symbol)'),
        const SizedBox(height: 4),
        AppInput(
          controller: _income,
          keyboardType: decimalKeyboard,
          inputFormatters: [decimalFormatter],
          placeholder: 'e.g. $symbol 3000',
          radius: Radii.md,
          semanticLabel: 'Monthly Income',
        ),
        const SizedBox(height: 16),
        const FieldLabel('Savings Goal'),
        const SizedBox(height: 4),
        Row(spacing: 8, children: [
          ToggleChoice(label: 'Percentage (%)', small: true, selected: _savingsType == 'percentage', onTap: () => setState(() => _savingsType = 'percentage')),
          ToggleChoice(label: 'Fixed Amount ($symbol)', small: true, selected: _savingsType == 'fixed', onTap: () => setState(() => _savingsType = 'fixed')),
        ]),
        const SizedBox(height: 8),
        AppInput(
          controller: _savings,
          keyboardType: decimalKeyboard,
          inputFormatters: [decimalFormatter],
          placeholder: _savingsType == 'percentage' ? 'e.g. 20' : 'e.g. $symbol 500',
          radius: Radii.md,
          semanticLabel: _savingsType == 'percentage' ? 'Savings percentage' : 'Savings amount',
        ),
        if (_error.isNotEmpty) ...[const SizedBox(height: 16), ErrorText(_error)],
        const SizedBox(height: 16),
        Row(spacing: 8, children: [
          Expanded(
            child: AppButton(
              onPressed: () => setState(() {
                _error = '';
                _step = 1;
              }),
              label: '← Back',
              variant: ButtonVariant.outline,
              radius: Radii.md,
              expand: true,
            ),
          ),
          Expanded(
            child: AppButton(
              onPressed: _save,
              loading: _saving,
              label: _saving ? 'Saving...' : 'Save & Calculate',
              radius: Radii.md,
              expand: true,
            ),
          ),
        ]),
      ];
}
