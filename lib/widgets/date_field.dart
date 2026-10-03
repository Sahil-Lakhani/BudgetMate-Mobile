import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/utils.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Date input showing YYYY-MM-DD (web: <Input type="date">), opens the native picker.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged, this.radius = Radii.lg, this.semanticLabel = 'Date'});
  final String value; // YYYY-MM-DD or ''
  final ValueChanged<String> onChanged;
  final double radius;
  final String semanticLabel;

  Future<void> _pick(BuildContext context) async {
    final initial = DateTime.tryParse(value) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) onChanged(localDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      value: value,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: () => _pick(context),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), border: Border.all(color: c.border)),
          child: Row(children: [
            Expanded(
              child: Text(value.isEmpty ? 'yyyy-mm-dd' : value, style: inter(size: FontSizes.base, color: value.isEmpty ? c.news : c.ink)),
            ),
            Icon(LucideIcons.calendar, size: 16, color: c.ink),
          ]),
        ),
      ),
    );
  }
}
