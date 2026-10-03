import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/currency.dart';
import '../core/errors.dart';
import '../core/utils.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/date_field.dart';
import '../widgets/footer.dart';
import '../widgets/ui.dart';

enum _Status { idle, preview, scanning, review, success }

class _ScanItem {
  _ScanItem({String name = '', String category = 'Other', String quantity = '1', String price = '0'})
      : name = TextEditingController(text: name),
        category = TextEditingController(text: category),
        quantity = TextEditingController(text: quantity),
        price = TextEditingController(text: price);
  final TextEditingController name, category, quantity, price;
  void dispose() {
    name.dispose();
    category.dispose();
    quantity.dispose();
    price.dispose();
  }
}

/// Port of pages/Scan.jsx: pick/snap → preview → Gemini analysis → review → save.
/// With [groupId] (from Add Split → Scan) the result continues to the split screen instead.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, this.initialFile, this.groupId});
  final File? initialFile;
  final String? groupId;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  _Status _status = _Status.idle;
  File? _file;
  String _error = '';
  final _merchant = TextEditingController();
  final _location = TextEditingController();
  final _total = TextEditingController();
  String _date = '';
  final List<_ScanItem> _items = [];
  Timer? _redirect;

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) _setFile(widget.initialFile!);
  }

  @override
  void dispose() {
    _redirect?.cancel();
    _merchant.dispose();
    _location.dispose();
    _total.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  void _setFile(File f) {
    setState(() {
      _error = '';
      _file = f;
      _status = _Status.preview;
    });
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      final f = File(picked.path);
      if (await f.length() > 15 * 1024 * 1024) {
        setState(() => _error = 'That image is larger than 15 MB. Please choose a smaller one.');
        return;
      }
      _setFile(f);
    } catch (e) {
      setState(() => _error = 'Please choose an image file (JPG, PNG, WebP or HEIC).');
    }
  }

  Future<void> _analyze() async {
    final f = _file;
    if (f == null) return;
    setState(() {
      _status = _Status.scanning;
      _error = '';
    });
    try {
      final data = await ref.read(geminiServiceProvider).analyzeReceipt(f);
      final items = (data['items'] as List?) ?? const [];
      if ((data['merchant'] ?? '').toString().isEmpty && items.isEmpty) {
        setState(() {
          _error = "We couldn't read a receipt in this image. Try a sharper, well-lit photo.";
          _status = _Status.preview;
        });
        return;
      }
      for (final i in _items) {
        i.dispose();
      }
      _items
        ..clear()
        ..addAll(items.whereType<Map>().map((it) => _ScanItem(
              name: '${it['name'] ?? ''}',
              price: it['price'] == null ? '0' : '${it['price']}',
              quantity: it['quantity'] == null ? '1' : '${it['quantity']}',
              category: '${it['category'] ?? 'Other'}',
            )));
      _merchant.text = '${data['merchant'] ?? ''}';
      _location.text = '${data['location'] ?? ''}';
      _total.text = data['total'] == null ? '' : '${data['total']}';
      _date = (data['date'] is String && (data['date'] as String).isNotEmpty) ? data['date'] as String : localDate();
      setState(() => _status = _Status.review);
    } catch (e) {
      debugPrint('Scan failed: $e');
      setState(() {
        _error = userMessage(e, 'Failed to analyze receipt. Please try again or check the image quality.');
        _status = _Status.preview;
      });
    }
  }

  Future<void> _save() async {
    final uid = ref.read(uidProvider);
    if (uid == null) return setState(() => _error = 'Your session has expired. Please sign in again.');
    if (_merchant.text.trim().isEmpty) return setState(() => _error = 'Please enter the merchant name.');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_date)) return setState(() => _error = 'Please enter the receipt date.');
    final total = parseNum(_total.text.replaceAll(',', '.'));
    if (!(total != null && total >= 0)) return setState(() => _error = 'Please enter a valid total amount.');
    if (widget.groupId == null && !_items.any((i) => i.name.text.trim().isNotEmpty)) {
      return setState(() => _error = 'Please keep at least one line item.');
    }
    setState(() => _error = '');

    final lineItems = _items.map((i) {
      final q = int.tryParse(i.quantity.text.trim().split('.').first) ?? 1;
      final p = parseNum(i.price.text.replaceAll(',', '.')) ?? 0;
      return {'name': i.name.text, 'quantity': q, 'price': p, 'totalPrice': p * q, 'category': i.category.text};
    }).toList();

    if (widget.groupId != null) {
      context.go('/groups/${widget.groupId}/split/new/screen', extra: {
        'merchant': _merchant.text,
        'totalAmount': total,
        'date': _date,
        'lineItems': lineItems,
      });
      return;
    }

    setState(() => _status = _Status.scanning);
    try {
      await ref.read(firestoreServiceProvider).saveTransaction(uid, {
        'merchant': _merchant.text,
        'location': _location.text,
        'date': _date,
        'total': total,
        'lineItems': lineItems,
      });
      setState(() => _status = _Status.success);
      _redirect = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) context.go('/expenses');
      });
    } catch (e) {
      debugPrint('Error saving transaction: $e');
      setState(() {
        _error = userMessage(e, 'Failed to save the expense. Please check the fields and try again.');
        _status = _Status.review;
      });
    }
  }

  void _cancel() => setState(() {
        _status = _Status.idle;
        _file = null;
        _error = '';
        _merchant.clear();
        _location.clear();
        _total.clear();
        _date = '';
        for (final i in _items) {
          i.dispose();
        }
        _items.clear();
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PageScroll(
      maxWidth: 672,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 8), child: const PageTitle('Scan Receipt', size: FontSizes.x3l)),
        if (_status == _Status.idle) _idleCard(c),
        if (_status == _Status.idle || _status == _Status.preview) _privacyNote(c),
        if (_status == _Status.preview) _previewCard(c),
        if (_status == _Status.scanning) _scanningCard(c),
        if (_status == _Status.review) _reviewCard(c),
        if (_status == _Status.success) _successCard(c),
      ],
    );
  }

  Widget _idleCard(AppColors c) => CustomPaint(
        painter: _DashedBorder(color: c.newsLight, width: 4, radius: Radii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Column(spacing: 16, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.newsLight, shape: BoxShape.circle),
              child: Icon(LucideIcons.camera, size: 32, color: c.ink),
            ),
            Column(children: [
              Text('Upload or Snap a Photo', style: inter(size: FontSizes.lg, weight: FontWeight.w700, color: c.ink)),
              Text('JPG, PNG, WebP or HEIC · up to 15 MB', style: inter(size: FontSizes.sm, color: c.news)),
            ]),
            Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 12, children: [
              AppButton(onPressed: () => _pick(ImageSource.gallery), icon: LucideIcons.upload, label: 'Upload File'),
              AppButton(onPressed: () => _pick(ImageSource.camera), icon: LucideIcons.camera, label: 'Use Camera', variant: ButtonVariant.secondary),
            ]),
            if (_error.isNotEmpty) ErrorText(_error, textAlign: TextAlign.center),
          ]),
        ),
      );

  Widget _privacyNote(AppColors c) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(
                text: "When you tap “Analyze Receipt”, the photo is sent to Google's Gemini AI service to read it. BudgetMate does not "
                    "store the photo — only the details you confirm. Avoid photos showing card numbers or other people's data. ",
              ),
              TextSpan(
                text: 'Privacy Policy',
                style: inter(size: FontSizes.xs, color: c.news, decoration: TextDecoration.underline),
                recognizer: TapGestureRecognizer()..onTap = () => openLegalPage(context, '/privacy#ai'),
              ),
            ]),
            textAlign: TextAlign.center,
            style: inter(size: FontSizes.xs, color: c.news),
          ),
        ),
      );

  Widget _previewCard(AppColors c) => AppCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            const Padding(padding: EdgeInsets.only(bottom: 8), child: CardTitle('Preview Receipt')),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 384),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(Radii.lg),
                      border: Border.all(color: c.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _file == null ? null : Image.file(_file!, fit: BoxFit.contain, semanticLabel: 'Receipt preview'),
                  ),
                ),
              ),
            ),
            if (_error.isNotEmpty) ErrorText(_error, textAlign: TextAlign.center),
            Row(spacing: 16, children: [
              Expanded(child: AppButton(onPressed: _analyze, icon: LucideIcons.check, label: 'Analyze Receipt', expand: true)),
              Expanded(
                child: AppButton(onPressed: _cancel, icon: LucideIcons.x, label: 'Remove', variant: ButtonVariant.secondary, expand: true),
              ),
            ]),
          ]),
        ),
      );

  Widget _scanningCard(AppColors c) => AppCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Column(spacing: 16, children: [
            SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3.5, color: c.ink)),
            Column(children: [
              Text('Analyzing Receipt...', style: inter(size: FontSizes.lg, weight: FontWeight.w700, color: c.ink)),
              Text('Extracting merchant, date, and line items.', textAlign: TextAlign.center, style: inter(size: FontSizes.sm, color: c.news)),
            ]),
          ]),
        ),
      );

  Widget _reviewCard(AppColors c) {
    final symbol = currencySymbol(ref.watch(currencyProvider));
    Widget labeled(String label, Widget child, {bool small = false}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: small ? 4 : 8, children: [
          small ? Text(label, style: inter(size: FontSizes.xs, color: c.news)) : Text(label, style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.ink)),
          child,
        ]);

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: CardTitle('Review Extracted Data')),
          if (widget.groupId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: c.ink.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(Radii.md)),
              child: Text("Splitting for a group — this receipt won't be saved to your expenses.", style: inter(size: FontSizes.xs, color: c.news)),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
            Expanded(child: labeled('Merchant', AppInput(controller: _merchant, semanticLabel: 'Merchant'))),
            Expanded(child: labeled('Location', AppInput(controller: _location, semanticLabel: 'Location'))),
          ]),
          Row(children: [
            Expanded(child: labeled('Date', DateField(value: _date, radius: 0, onChanged: (v) => setState(() => _date = v)))),
            const SizedBox(width: 16),
            const Expanded(child: SizedBox()),
          ]),
          labeled(
            'Line Items',
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border.all(color: c.newsLight, width: 2)),
              child: Column(children: [
                for (var i = 0; i < _items.length; i++)
                  Container(
                    padding: EdgeInsets.only(bottom: i == _items.length - 1 ? 0 : 8),
                    margin: EdgeInsets.only(bottom: i == _items.length - 1 ? 0 : 12),
                    decoration: BoxDecoration(border: i == _items.length - 1 ? null : Border(bottom: BorderSide(color: c.border))),
                    child: Column(spacing: 8, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(child: labeled('Item', AppInput(controller: _items[i].name, placeholder: 'Item Name'), small: true)),
                        const SizedBox(width: 8),
                        AppIconButton(
                          icon: LucideIcons.trash2,
                          iconSize: 16,
                          size: 36,
                          color: AppColors.red500,
                          tooltip: 'Remove item ${_items[i].name.text.isNotEmpty ? _items[i].name.text : i + 1}',
                          onPressed: () => setState(() => _items.removeAt(i).dispose()),
                        ),
                      ]),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                        Expanded(flex: 5, child: labeled('Category', AppInput(controller: _items[i].category, placeholder: 'Category'), small: true)),
                        Expanded(
                          flex: 3,
                          child: labeled('Qty', AppInput(controller: _items[i].quantity, placeholder: 'Qty', keyboardType: TextInputType.number), small: true),
                        ),
                        Expanded(
                          flex: 4,
                          child: labeled(
                            'Price',
                            AppInput(controller: _items[i].price, placeholder: 'Price', keyboardType: decimalKeyboard, inputFormatters: [decimalFormatter]),
                            small: true,
                          ),
                        ),
                      ]),
                    ]),
                  ),
              ]),
            ),
          ),
          labeled(
            'Total Amount',
            AppInput(controller: _total, prefix: symbol, keyboardType: decimalKeyboard, inputFormatters: [decimalFormatter], semanticLabel: 'Total Amount'),
          ),
          if (_error.isNotEmpty) ErrorText(_error),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(spacing: 16, children: [
              Expanded(
                child: AppButton(
                  onPressed: _save,
                  icon: LucideIcons.check,
                  label: widget.groupId != null ? 'Continue to Split' : 'Confirm & Save',
                  expand: true,
                ),
              ),
              AppButton(onPressed: _cancel, icon: LucideIcons.x, label: 'Cancel', variant: ButtonVariant.secondary),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _successCard(AppColors c) {
    final dark = c.isDark;
    return AppCard(
      borderColor: dark ? const Color(0xFF14532D) : const Color(0xFFBBF7D0),
      child: Container(
        color: dark ? const Color(0x3314532D) : const Color(0xFFF0FDF4),
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(spacing: 16, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: dark ? const Color(0x6614532D) : const Color(0xFFDCFCE7), shape: BoxShape.circle),
            child: Icon(LucideIcons.check, size: 32, color: dark ? AppColors.green400 : AppColors.green600),
          ),
          Column(children: [
            Text('Expense Saved!', style: inter(size: FontSizes.lg, weight: FontWeight.w700, color: dark ? AppColors.green400 : const Color(0xFF166534))),
            Text('Redirecting to expenses...', style: inter(size: FontSizes.sm, color: dark ? AppColors.green500 : AppColors.green600)),
          ]),
        ]),
      ),
    );
  }
}

/// `border-dashed border-4 border-news-light` box.
class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.width, required this.radius});
  final Color color;
  final double width;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius((Offset.zero & size).deflate(width / 2), Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 12.0, gap = 8.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
