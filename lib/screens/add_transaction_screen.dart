import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/currency.dart';
import '../core/errors.dart';
import '../core/utils.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/date_field.dart';
import '../widgets/ui.dart';

const transactionCategories = [
  'Groceries',
  'Clothing',
  'Electronics',
  'Transportation',
  'Home & Garden',
  'Utilities',
  'Restaurant',
  'Coffee & Cafe',
  'General',
];

class _ItemForm {
  _ItemForm() : name = TextEditingController(), quantity = TextEditingController(text: '1'), price = TextEditingController(text: '0');
  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController price;
  String category = 'General';

  double get qty => parseDecimal(quantity.text) ?? 0;
  double get unit => parseDecimal(price.text) ?? 0;
  double get total => qty * unit;

  void dispose() {
    name.dispose();
    quantity.dispose();
    price.dispose();
  }
}

/// Port of pages/AddTransaction.jsx (manual entry).
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _merchant = TextEditingController();
  final _location = TextEditingController();
  String _date = localDate();
  final _items = [_ItemForm()];
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _merchant.dispose();
    _location.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  double get _total => _items.fold(0, (s, i) => s + i.total);

  void _back() => context.canPop() ? context.pop() : context.go('/expenses');

  Future<void> _submit() async {
    if (_merchant.text.trim().isEmpty) return setState(() => _error = 'Please enter a merchant name.');
    if (_date.isEmpty) return setState(() => _error = 'Please select a date.');
    if (!_items.any((i) => i.name.text.trim().isNotEmpty)) return setState(() => _error = 'Please add at least one item with a name.');
    final badNumber = _items.any((i) =>
        i.name.text.trim().isNotEmpty && (i.unit < 0 || (i.quantity.text.trim().isNotEmpty && !((parseDecimal(i.quantity.text) ?? 0) > 0))));
    if (badNumber) return setState(() => _error = "Prices can't be negative and quantities must be greater than zero.");

    setState(() {
      _error = '';
      _saving = true;
    });
    try {
      final valid = _items.where((i) => i.name.text.trim().isNotEmpty).map((i) {
        final q = (parseDecimal(i.quantity.text) ?? 0) == 0 ? 1.0 : parseDecimal(i.quantity.text)!;
        return {'name': i.name.text.trim(), 'category': i.category, 'quantity': q, 'price': i.unit, 'totalPrice': q * i.unit};
      }).toList();

      await ref.read(firestoreServiceProvider).saveTransaction(ref.read(uidProvider)!, {
        'merchant': _merchant.text.trim(),
        'date': _date,
        'location': _location.text.trim(),
        'lineItems': valid,
        'total': _total,
        'source': 'manual',
      });
      if (mounted) context.go('/expenses');
    } catch (e) {
      debugPrint('Error saving transaction: $e');
      if (mounted) setState(() => _error = userMessage(e, 'Failed to save the transaction. Please check the fields and try again.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final symbol = currencySymbol(ref.watch(currencyProvider));

    return PageScroll(
      maxWidth: 768,
      children: [
        Row(children: [
          AppIconButton(icon: LucideIcons.arrowLeft, tooltip: 'Back to expenses', onPressed: _back),
          const SizedBox(width: 16),
          const Expanded(child: PageTitle('Add Transaction')),
        ]),
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionLabel('Transaction Details'),
            const SizedBox(height: 16),
            const FieldLabel('Merchant Name', required: true),
            const SizedBox(height: 8),
            AppInput(controller: _merchant, maxLength: 100, placeholder: 'e.g. REWE, Lidl', radius: Radii.lg, semanticLabel: 'Merchant Name'),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const FieldLabel('Date', required: true),
                  const SizedBox(height: 8),
                  DateField(value: _date, onChanged: (v) => setState(() => _date = v)),
                ]),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const FieldLabel('Location'),
                  const SizedBox(height: 8),
                  AppInput(controller: _location, maxLength: 100, placeholder: 'e.g. Berlin', radius: Radii.lg, semanticLabel: 'Location'),
                ]),
              ),
            ]),
            const SizedBox(height: 24),
            Container(height: 1, color: c.border),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: SectionLabel('Line Items')),
              AppButton(
                onPressed: () => setState(() => _items.add(_ItemForm())),
                icon: LucideIcons.plus,
                label: 'Add Item',
                variant: ButtonVariant.secondary,
                size: ButtonSize.sm,
                radius: Radii.lg,
              ),
            ]),
            const SizedBox(height: 8),
            for (var i = 0; i < _items.length; i++) _itemFields(i, symbol),
            const SizedBox(height: 24),
            Container(height: 1, color: c.border),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.newsLight.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(Radii.lg)),
              child: Row(children: [
                Expanded(child: Text('Total Amount', style: inter(size: FontSizes.lg, weight: FontWeight.w500, color: c.ink))),
                Text('$symbol${_total.toStringAsFixed(2)}', style: inter(size: FontSizes.x2l, weight: FontWeight.w700, color: c.ink)),
              ]),
            ),
            if (_error.isNotEmpty) ...[const SizedBox(height: 24), ErrorText(_error)],
            const SizedBox(height: 40),
            Row(spacing: 12, children: [
              Expanded(
                child: AppButton(
                  onPressed: _saving ? null : _back,
                  label: 'Cancel',
                  variant: ButtonVariant.secondary,
                  radius: Radii.lg,
                  expand: true,
                ),
              ),
              Expanded(
                child: AppButton(onPressed: _submit, loading: _saving, label: _saving ? 'Saving...' : 'Save Transaction', radius: Radii.lg, expand: true),
              ),
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _itemFields(int index, String symbol) {
    final c = context.colors;
    final item = _items[index];
    Widget field(String label, Widget input) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FieldLabel(label, small: true),
          const SizedBox(height: 6),
          input,
        ]);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        SizedBox(
          height: 32,
          child: Row(children: [
            Expanded(child: Text('Item ${index + 1}', style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.ink))),
            if (_items.length > 1)
              AppIconButton(
                icon: LucideIcons.trash2,
                iconSize: 16,
                size: 32,
                color: AppColors.red500,
                tooltip: 'Remove item ${index + 1}',
                onPressed: () => setState(() => _items.removeAt(index).dispose()),
              ),
          ]),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          Expanded(
            child: field(
                'Item Name',
                AppInput(
                    controller: item.name,
                    maxLength: 100,
                    placeholder: 'e.g., Milk, Bread',
                    radius: Radii.lg,
                    semanticLabel: 'Item ${index + 1} name')),
          ),
          Expanded(
            child: field(
              'Category',
              AppSelect<String>(
                value: item.category,
                semanticLabel: 'Item ${index + 1} category',
                options: [for (final cat in transactionCategories) SelectOption(cat, cat)],
                onChanged: (v) => setState(() => item.category = v),
              ),
            ),
          ),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          Expanded(
            child: field(
              'Quantity',
              AppInput(
                controller: item.quantity,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                radius: Radii.lg,
                onChanged: (_) => setState(() {}),
                semanticLabel: 'Item ${index + 1} quantity',
              ),
            ),
          ),
          Expanded(
            child: field(
              'Price ($symbol)',
              AppInput(
                controller: item.price,
                keyboardType: decimalKeyboard,
                inputFormatters: [decimalFormatter],
                radius: Radii.lg,
                onChanged: (_) => setState(() {}),
                semanticLabel: 'Item ${index + 1} price',
              ),
            ),
          ),
        ]),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Item Total: ', style: inter(size: FontSizes.sm, color: c.news)),
            TextSpan(text: '$symbol${item.total.toStringAsFixed(2)}', style: inter(size: FontSizes.sm, weight: FontWeight.w700, color: c.ink)),
          ]),
          textAlign: TextAlign.right,
        ),
      ]),
    );
  }
}
