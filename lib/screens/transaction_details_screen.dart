import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/loading.dart';
import '../widgets/ui.dart';

/// Port of pages/TransactionDetails.jsx (mobile layout).
class TransactionDetailsScreen extends ConsumerStatefulWidget {
  const TransactionDetailsScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<TransactionDetailsScreen> createState() => _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState extends ConsumerState<TransactionDetailsScreen> {
  late Future<Txn?> _future;
  bool _confirming = false;
  bool _deleting = false;
  String _deleteError = '';

  @override
  void initState() {
    super.initState();
    _future = ref.read(firestoreServiceProvider).getTransaction(ref.read(uidProvider)!, widget.id);
  }

  void _back() => context.canPop() ? context.pop() : context.go('/expenses');

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _deleteError = '';
    });
    try {
      await ref.read(firestoreServiceProvider).deleteTransaction(ref.read(uidProvider)!, widget.id);
      if (mounted) context.go('/expenses');
    } catch (e) {
      debugPrint('Error deleting transaction: $e');
      if (mounted) {
        setState(() {
          _deleteError = 'Failed to delete the transaction. Please try again.';
          _deleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Txn?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const PageSkeleton(SkeletonKind.detail, label: 'Loading transaction details…');
        final txn = snap.data;
        if (txn == null) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(snap.hasError ? "Couldn't load this transaction. Check your connection and try again." : 'Transaction not found.',
                  textAlign: TextAlign.center, style: inter(size: FontSizes.base, color: context.colors.news)),
              const SizedBox(height: 16),
              AppButton(onPressed: () => context.go('/expenses'), label: 'Back to Expenses'),
            ]),
          );
        }
        return _details(txn);
      },
    );
  }

  Widget _details(Txn txn) {
    final c = context.colors;
    final fc = ref.watch(formatCurrencyProvider);
    final amountColor = txn.isRefund ? AppColors.green600 : c.ink;

    return PageScroll(
      maxWidth: 672,
      children: [
        Row(children: [
          AppIconButton(icon: LucideIcons.arrowLeft, tooltip: 'Back to expenses', onPressed: _back),
          const SizedBox(width: 16),
          const Expanded(child: PageTitle('Transaction Details')),
          AppIconButton(
            icon: LucideIcons.trash2,
            tooltip: 'Delete transaction',
            color: AppColors.red500,
            onPressed: _deleting ? null : () => setState(() => _confirming = true),
          ),
        ]),
        if (_confirming)
          ConfirmBox(children: [
            Text("Delete this transaction? This can't be undone.", style: inter(size: FontSizes.sm, color: c.ink)),
            Row(spacing: 8, children: [
              AppButton(
                onPressed: _delete,
                loading: _deleting,
                label: _deleting ? 'Deleting…' : 'Delete',
                variant: ButtonVariant.destructive,
                size: ButtonSize.sm,
              ),
              AppButton(
                onPressed: _deleting ? null : () => setState(() => _confirming = false),
                label: 'Cancel',
                variant: ButtonVariant.ghost,
                size: ButtonSize.sm,
              ),
            ]),
            if (_deleteError.isNotEmpty) ErrorText(_deleteError),
          ]),
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: c.newsLight.withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: Icon(categoryIcon(txn.firstCategory), size: 24, color: c.ink),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(txn.merchant, style: inter(size: FontSizes.xl, weight: FontWeight.w700, color: c.ink)),
                      SplitTag(txn),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(LucideIcons.calendar, size: 12, color: c.news),
                      const SizedBox(width: 8),
                      Text(txn.date, style: inter(size: FontSizes.sm, color: c.news)),
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${txn.isRefund ? '+' : ''}${fc(txn.total.abs())}',
                      style: inter(size: FontSizes.xl, weight: FontWeight.w700, color: amountColor)),
                  Text(txn.isRefund ? 'Refund' : 'Total', style: inter(size: FontSizes.sm, weight: FontWeight.w700, color: c.news)),
                ]),
              ]),
            ),
            const SizedBox(height: 24),
            if (!txn.isRefund) ...[
              const SectionLabel('Line Items'),
              const SizedBox(height: 16),
              for (var i = 0; i < txn.lineItems.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  margin: EdgeInsets.only(bottom: i == txn.lineItems.length - 1 ? 0 : 12),
                  decoration: BoxDecoration(border: i == txn.lineItems.length - 1 ? null : Border(bottom: BorderSide(color: c.border))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(txn.lineItems[i].name, style: inter(size: FontSizes.base, weight: FontWeight.w500, color: c.ink)),
                        Text('${txn.lineItems[i].category} • Qty: ${_qty(txn.lineItems[i].quantity)}', style: inter(size: FontSizes.xs, color: c.news)),
                      ]),
                    ),
                    Text(fc(txn.lineItems[i].totalPrice != null && txn.lineItems[i].totalPrice != 0 ? txn.lineItems[i].totalPrice : txn.lineItems[i].price),
                        style: inter(size: FontSizes.base, weight: FontWeight.w500, color: c.ink)),
                  ]),
                ),
              const SizedBox(height: 24),
            ],
            Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
              if (txn.location != null) Text('Store Location: ${txn.location}', style: inter(size: FontSizes.xs, color: c.news)),
              Text('Source', style: inter(size: FontSizes.xs, color: c.news)),
              Text(_capitalizeWords(txn.raw['source'] as String? ?? 'Manual'), style: inter(size: FontSizes.xs, color: c.news)),
            ]),
          ]),
        ),
      ],
    );
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();
  static String _capitalizeWords(String s) => s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
}
