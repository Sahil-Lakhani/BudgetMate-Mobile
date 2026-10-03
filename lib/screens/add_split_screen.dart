import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/currency.dart';
import '../core/utils.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/date_field.dart';
import '../widgets/ui.dart';

class AddSplitScreen extends ConsumerStatefulWidget {
  const AddSplitScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<AddSplitScreen> createState() => _AddSplitScreenState();
}

class _AddSplitScreenState extends ConsumerState<AddSplitScreen> {
  bool _manual = false;
  final _merchant = TextEditingController();
  final _amount = TextEditingController();
  String _date = localDate();
  String _error = '';

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _continue() {
    if (_merchant.text.trim().isEmpty) return setState(() => _error = 'Merchant name is required');
    final total = parseDecimal(_amount.text);
    if (total == null || total <= 0) return setState(() => _error = 'Enter a valid amount');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_date)) return setState(() => _error = 'Choose a date');
    context.push('/groups/${widget.groupId}/split/new/screen', extra: {'merchant': _merchant.text.trim(), 'totalAmount': total, 'date': _date});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final symbol = currencySymbol(ref.watch(currencyProvider));

    Widget option(IconData icon, String title, String caption, VoidCallback onTap) => Expanded(
          child: AppCard(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
              child: Column(spacing: 12, children: [
                Icon(icon, size: 40, color: c.ink),
                Text(title, style: inter(size: FontSizes.base, weight: FontWeight.w500, color: c.ink)),
                Text(caption, textAlign: TextAlign.center, style: inter(size: FontSizes.xs, color: c.news)),
              ]),
            ),
          ),
        );

    return PageScroll(
      maxWidth: 512,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PageTitle('Add Split', size: FontSizes.x3l),
          const SizedBox(height: 4),
          Text('Scan a receipt or enter details manually', style: inter(size: FontSizes.sm, color: c.news)),
        ]),
        if (!_manual)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
              option(LucideIcons.scanLine, 'Scan Receipt', 'Use camera to extract total automatically',
                  () => context.push('/scan', extra: {'groupId': widget.groupId})),
              option(LucideIcons.penLine, 'Manual Entry', 'Enter merchant and amount yourself', () => setState(() => _manual = true)),
            ]),
          )
        else
          AppCard(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const CardTitle('Bill Details'),
              const SizedBox(height: 30),
              const FieldLabel('Merchant'),
              const SizedBox(height: 4),
              AppInput(controller: _merchant, maxLength: 100, placeholder: 'e.g. Pizza Palace', semanticLabel: 'Merchant'),
              const SizedBox(height: 16),
              FieldLabel('Total Amount ($symbol)'),
              const SizedBox(height: 4),
              AppInput(controller: _amount, keyboardType: decimalKeyboard, inputFormatters: [decimalFormatter], placeholder: '0.00', semanticLabel: 'Total Amount'),
              const SizedBox(height: 16),
              const FieldLabel('Date'),
              const SizedBox(height: 4),
              DateField(value: _date, radius: 0, onChanged: (v) => setState(() => _date = v)),
              if (_error.isNotEmpty) ...[const SizedBox(height: 16), ErrorText(_error)],
              const SizedBox(height: 24),
              Row(spacing: 12, children: [
                Expanded(child: AppButton(onPressed: () => setState(() => _manual = false), label: 'Back', variant: ButtonVariant.outline, expand: true)),
                Expanded(child: AppButton(onPressed: _continue, label: 'Continue', expand: true)),
              ]),
            ]),
          ),
      ],
    );
  }
}
