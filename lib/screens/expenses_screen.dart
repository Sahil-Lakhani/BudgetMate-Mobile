import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/utils.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/loading.dart';
import '../widgets/ui.dart';

/// Same filter rules as Expenses.jsx: a transaction matches a category if any of its
/// line items has it; search covers merchant, item names and categories.
List<Txn> filterTransactions(List<Txn> all, {required String month, required String search, required String category}) {
  final term = search.trim().toLowerCase();
  return all.where((t) {
    final cats = t.lineItems.map((i) => i.category).where((c) => c.isNotEmpty).toList();
    final matchesSearch = term.isEmpty ||
        t.merchant.toLowerCase().contains(term) ||
        cats.any((c) => c.toLowerCase().contains(term)) ||
        t.lineItems.any((i) => i.name.toLowerCase().contains(term));
    final matchesCategory = category == 'All' || cats.contains(category);
    return matchesSearch && matchesCategory && t.date.startsWith(month);
  }).toList();
}

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String _search = '';
  String _category = 'All';
  String _month = localMonth();

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(transactionsProvider);
    if (txAsync.isLoading && !txAsync.hasValue) return const PageSkeleton(SkeletonKind.list, label: 'Loading expenses…');
    if (txAsync.hasError && !txAsync.hasValue) {
      return const StatusText('Failed to load transactions. Please check your connection.', error: true);
    }
    final c = context.colors;
    final fc = ref.watch(formatCurrencyProvider);
    final transactions = txAsync.value!;

    final sortedMonths = ({localMonth(), ...transactions.map((t) => t.month)}.toList()..sort()).reversed.toList();
    final categories = ['All', ...{for (final t in transactions) ...t.lineItems.map((i) => i.category).where((c) => c.isNotEmpty)}];
    final filtered = filterTransactions(transactions, month: _month, search: _search, category: _category);
    final total = filtered.fold<double>(0, (s, t) => s + t.total);

    return PageScroll(
      spacing: 12,
      onRefresh: () async => ref.invalidate(transactionsProvider),
      children: [
        // Monthly tabs
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sortedMonths.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final m = sortedMonths[i];
              return AppButton(
                onPressed: () => setState(() => _month = m),
                label: monthLabel(m),
                variant: _month == m ? ButtonVariant.primary : ButtonVariant.outline,
                radius: Radii.lg,
                padding: const EdgeInsets.symmetric(horizontal: 24),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        AppInput(
          initialValue: _search,
          onChanged: (v) => setState(() => _search = v),
          placeholder: 'Search merchant, item or category…',
          prefixIcon: LucideIcons.search,
          radius: Radii.lg,
          semanticLabel: 'Search expenses',
          textInputAction: TextInputAction.search,
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => AppButton(
              onPressed: () => setState(() => _category = categories[i]),
              label: categories[i],
              size: ButtonSize.sm,
              variant: _category == categories[i] ? ButtonVariant.primary : ButtonVariant.secondary,
              radius: Radii.lg,
            ),
          ),
        ),
        // Monthly total + add
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            Expanded(
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('Total Expenses', style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.news)),
                      Text(monthLabel(_month), style: inter(size: FontSizes.xs, color: c.news.withValues(alpha: 0.6))),
                    ]),
                  ),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight, // web: justify-between
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(fc(total), style: inter(size: FontSizes.x2l, weight: FontWeight.w700, color: c.ink)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            AppButton(
              onPressed: () => context.push('/expenses/add'),
              semanticLabel: 'Add transaction',
              radius: Radii.lg,
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Icon(LucideIcons.plus, size: 24, color: c.paper),
            ),
          ]),
        ),
        AppCard(
          padding: const EdgeInsets.all(8),
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Text(
                    _search.isNotEmpty || _category != 'All'
                        ? 'No transactions match your search.'
                        : 'No transactions in ${monthLabel(_month, withYear: false)}.',
                    textAlign: TextAlign.center,
                    style: inter(size: FontSizes.base, color: c.news),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    for (var i = 0; i < filtered.length; i++) ...[
                      _TxnRow(txn: filtered[i], fc: fc),
                      if (i != filtered.length - 1)
                        Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), color: const Color(0xFF6B7280)),
                    ],
                  ]),
                ),
        ),
      ],
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow({required this.txn, required this.fc});
  final Txn txn;
  final String Function(Object?) fc;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.lg),
      onTap: () => context.push('/expenses/${txn.id}'),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.newsLight.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: Icon(categoryIcon(txn.firstCategory), size: 20, color: c.ink),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(txn.merchant, style: inter(size: FontSizes.base, weight: FontWeight.w700, color: c.ink)),
                SplitTag(txn),
              ]),
              Text('${txn.date} • ${txn.isRefund ? 'Refund' : txn.firstCategory}', style: inter(size: FontSizes.xs, color: c.news)),
            ]),
          ),
          const SizedBox(width: 12),
          Text(
            '${txn.isRefund ? '+ ' : '- '}${fc(txn.total.abs())}',
            style: inter(size: FontSizes.lg, weight: FontWeight.w700, color: txn.isRefund ? AppColors.green600 : c.ink),
          ),
          const SizedBox(width: 16),
          Icon(LucideIcons.chevronRight, size: 16, color: c.ink),
        ]),
      ),
    );
  }
}
