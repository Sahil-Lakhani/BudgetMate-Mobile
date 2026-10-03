// Ports of the web app's UI primitives (src/components/Button, Card, Input, Badge,
// Select, SplitTag, PageLoader). Sizes/paddings follow the Tailwind classes literally.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

// ─── Button ──────────────────────────────────────────────────────────────────

enum ButtonVariant { primary, secondary, ghost, destructive, outline }

enum ButtonSize { normal, sm, lg, icon }

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    this.child,
    this.label,
    this.icon,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.normal,
    this.radius = 0, // web default is rounded-none; most call sites add rounded-[8px]/rounded-md
    this.expand = false,
    this.foreground,
    this.height,
    this.padding,
    this.alignment = MainAxisAlignment.center,
    this.semanticLabel,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final Widget? child;
  final String? label;
  final IconData? icon;
  final ButtonVariant variant;
  final ButtonSize size;
  final double radius;
  final bool expand;
  final Color? foreground;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final MainAxisAlignment alignment;
  final String? semanticLabel;

  /// Shows a spinner in place of the icon and ignores taps (e.g. while saving).
  final bool loading;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = widget;
    final onPressed = w.loading ? null : w.onPressed;
    final disabled = onPressed == null;
    final variant = w.variant, size = w.size, radius = w.radius, expand = w.expand;
    final child = w.child, label = w.label, icon = w.icon;

    final (Color bg, Color fg, Color? borderColor) = switch (variant) {
      ButtonVariant.primary => (c.ink, c.paper, null),
      ButtonVariant.secondary => (c.card, c.ink, c.border),
      ButtonVariant.ghost => (Colors.transparent, c.ink, null),
      ButtonVariant.destructive => (AppColors.red600, Colors.white, null),
      ButtonVariant.outline => (Colors.transparent, c.ink, c.border),
    };
    final textColor = w.foreground ?? fg;

    final h =
        w.height ??
        switch (size) {
          ButtonSize.normal => 40.0,
          ButtonSize.sm => 36.0,
          ButtonSize.lg => 44.0,
          ButtonSize.icon => 40.0,
        };
    final pad =
        w.padding ??
        switch (size) {
          ButtonSize.normal => const EdgeInsets.symmetric(horizontal: 16),
          ButtonSize.sm => const EdgeInsets.symmetric(horizontal: 12),
          ButtonSize.lg => const EdgeInsets.symmetric(horizontal: 32),
          ButtonSize.icon => EdgeInsets.zero,
        };
    final r = size == ButtonSize.sm || size == ButtonSize.lg ? (radius == 0 ? Radii.md : radius) : radius;

    final content =
        child ??
        Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: w.alignment,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (c, a) => ScaleTransition(
                scale: a,
                child: FadeTransition(opacity: a, child: c),
              ),
              child: w.loading
                  ? SizedBox(
                      key: const ValueKey('spin'),
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
                    )
                  : (icon != null
                        ? Icon(icon, key: const ValueKey('icon'), size: size == ButtonSize.icon ? 20 : 16, color: textColor)
                        : const SizedBox.shrink(key: ValueKey('none'))),
            ),
            if ((icon != null || w.loading) && label != null) const SizedBox(width: 8),
            if (label != null)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: textColor),
                ),
              ),
          ],
        );

    return Semantics(
      button: true,
      enabled: !disabled,
      label: w.semanticLabel,
      child: AnimatedScale(
        // Small press-down feedback
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          // A loading button stays fully visible; only truly disabled ones fade
          opacity: disabled && !w.loading ? 0.5 : 1,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(r),
              side: borderColor != null ? BorderSide(color: borderColor) : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              onHighlightChanged: disabled ? null : _setPressed,
              splashColor: c.newsLight.withValues(alpha: 0.3),
              highlightColor: variant == ButtonVariant.primary ? Colors.white10 : c.newsLight.withValues(alpha: 0.2),
              child: SizedBox(
                height: h,
                width: size == ButtonSize.icon ? h : (expand ? double.infinity : null),
                child: Padding(
                  padding: pad,
                  child: IconTheme(
                    data: IconThemeData(color: textColor, size: 16),
                    child: DefaultTextStyle(
                      style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: textColor),
                      child: Center(widthFactor: expand ? null : 1, child: content),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ghost icon button (`<Button variant="ghost" size="icon">`).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color,
    this.iconSize = 20,
    this.size = 40,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color? color;
  final double iconSize;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: AppButton(
        onPressed: onPressed,
        variant: ButtonVariant.ghost,
        size: ButtonSize.icon,
        height: size,
        radius: Radii.md,
        semanticLabel: tooltip,
        child: Icon(icon, size: iconSize, color: color ?? context.colors.ink),
      ),
    );
  }
}

// ─── Card ────────────────────────────────────────────────────────────────────

/// `rounded-lg border border-border bg-card shadow-sm`
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.leftAccent, this.borderColor, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? leftAccent; // border-l-4
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body = Padding(padding: padding, child: child);
    if (leftAccent != null) {
      body = Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: leftAccent!, width: 4)),
        ),
        child: body,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: borderColor ?? c.border),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1))],
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, child: body),
            ),
    );
  }
}

/// `CardTitle`: text-2xl font-semibold leading-none tracking-tight (size overridable)
class CardTitle extends StatelessWidget {
  const CardTitle(this.text, {super.key, this.size = FontSizes.x2l, this.color, this.weight = FontWeight.w600});
  final String text;
  final double size;
  final Color? color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: inter(size: size, weight: weight, color: color ?? context.colors.ink, height: 1.0, letterSpacing: -0.025 * size),
  );
}

/// `CardDescription`: text-sm text-news
class CardDescription extends StatelessWidget {
  const CardDescription(this.text, {super.key, this.textAlign});
  final String text;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: textAlign,
    style: inter(size: FontSizes.sm, color: context.colors.news),
  );
}

// ─── Text helpers ────────────────────────────────────────────────────────────

/// Page heading: text-2xl font-bold text-ink
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key, this.size = FontSizes.x2l});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: inter(size: size, weight: FontWeight.w700, color: context.colors.ink, height: 1.25),
  );
}

/// Section label: text-sm font-medium text-news uppercase tracking-wider
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: context.colors.news, letterSpacing: 0.7),
  );
}

/// Form label: text-sm font-medium text-ink, optional red asterisk.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false, this.small = false});
  final String text;
  final bool required;
  final bool small; // text-xs text-news (line-item labels)
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: AppColors.red500),
            ),
        ],
      ),
      style: inter(size: small ? FontSizes.xs : FontSizes.sm, weight: FontWeight.w500, color: small ? c.news : c.ink),
    );
  }
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key, this.textAlign});
  final String text;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      textAlign: textAlign,
      style: inter(size: FontSizes.sm, color: AppColors.red500),
    ),
  );
}

// ─── Input ───────────────────────────────────────────────────────────────────

/// `h-10 w-full border border-border bg-transparent px-3 text-sm`, focus → border-ink.
class AppInput extends StatelessWidget {
  const AppInput({
    super.key,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.placeholder,
    this.keyboardType,
    this.maxLength,
    this.radius = 0,
    this.prefix,
    this.prefixIcon,
    this.readOnly = false,
    this.onTap,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.inputFormatters,
    this.semanticLabel,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final String? placeholder;
  final TextInputType? keyboardType;
  final int? maxLength;
  final double radius;
  final String? prefix; // absolutely positioned symbol (e.g. "€")
  final IconData? prefixIcon;
  final bool readOnly;
  final VoidCallback? onTap;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final String? semanticLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color),
    );
    return Semantics(
      label: semanticLabel,
      textField: true,
      child: TextFormField(
        controller: controller,
        initialValue: controller == null ? initialValue : null,
        onChanged: onChanged,
        keyboardType: keyboardType,
        readOnly: readOnly,
        onTap: onTap,
        enabled: enabled,
        autofocus: autofocus,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        inputFormatters: [if (maxLength != null) LengthLimitingTextInputFormatter(maxLength), ...?inputFormatters],
        // 16px avoids iOS focus-zoom on web; native apps use the same size for parity with the mobile web
        style: inter(size: FontSizes.base, color: c.ink),
        cursorColor: c.ink,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          hintText: placeholder,
          hintStyle: inter(size: FontSizes.base, color: c.news),
          contentPadding: EdgeInsets.fromLTRB(prefix != null ? 28 : (prefixIcon != null ? 40 : 12), 10, 12, 10),
          prefixIcon: prefixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: Icon(prefixIcon, size: 16, color: c.news),
                )
              : (prefix != null
                    ? Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: Text(
                          prefix!,
                          style: inter(size: FontSizes.sm, color: c.news),
                        ),
                      )
                    : null),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          border: border(c.border),
          enabledBorder: border(c.border),
          disabledBorder: border(c.border.withValues(alpha: 0.5)),
          focusedBorder: border(c.ink),
          constraints: const BoxConstraints(minHeight: 40),
        ),
      ),
    );
  }
}

/// Decimal keyboard + digits/dot/comma only (web: type="number" inputMode="decimal").
const decimalKeyboard = TextInputType.numberWithOptions(decimal: true);
final decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

/// Normalises "12,50" → "12.50" before parsing.
double? parseDecimal(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

// ─── Badge ───────────────────────────────────────────────────────────────────

class AppBadge extends StatelessWidget {
  const AppBadge(this.text, {super.key, this.secondary = false});
  final String text;
  final bool secondary;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      color: secondary ? c.newsLight : c.ink,
      child: Text(
        text,
        style: inter(size: FontSizes.xs, weight: FontWeight.w600, color: secondary ? c.ink : Colors.white),
      ),
    );
  }
}

// ─── Select ──────────────────────────────────────────────────────────────────

class SelectOption<T> {
  const SelectOption(this.value, this.label);
  final T value;
  final String label;
}

/// Custom dropdown matching the web Select: bordered trigger with chevron,
/// floating list with a violet check on the selected row.
class AppSelect<T> extends StatefulWidget {
  const AppSelect({super.key, required this.value, required this.options, required this.onChanged, this.semanticLabel});
  final T value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  State<AppSelect<T>> createState() => _AppSelectState<T>();
}

class _AppSelectState<T> extends State<AppSelect<T>> {
  final _controller = MenuController();
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.options.where((o) => o.value == widget.value).firstOrNull;

    return LayoutBuilder(
      builder: (context, constraints) {
        return MenuAnchor(
          controller: _controller,
          onOpen: () => setState(() => _open = true),
          onClose: () => setState(() => _open = false),
          alignmentOffset: const Offset(0, 4),
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(c.card),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(8),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
            maximumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 240)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.lg),
                side: BorderSide(color: c.border),
              ),
            ),
          ),
          menuChildren: [
            for (final o in widget.options)
              MenuItemButton(
                onPressed: () => widget.onChanged(o.value),
                style: ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 40)),
                  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  overlayColor: WidgetStatePropertyAll(c.newsLight.withValues(alpha: 0.4)),
                ),
                child: SizedBox(
                  width: constraints.maxWidth - 24,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          o.label,
                          style: inter(
                            size: FontSizes.sm,
                            color: c.ink,
                            weight: o.value == widget.value ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (o.value == widget.value) Icon(LucideIcons.check, size: 16, color: c.primary),
                    ],
                  ),
                ),
              ),
          ],
          builder: (context, controller, _) => Semantics(
            button: true,
            label: widget.semanticLabel,
            value: selected?.label,
            child: Material(
              color: c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.lg),
                side: BorderSide(color: c.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.lg),
                onTap: () => controller.isOpen ? controller.close() : controller.open(),
                child: SizedBox(
                  height: 40,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selected?.label ?? '${widget.value}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: inter(size: FontSizes.sm, color: c.ink),
                          ),
                        ),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(LucideIcons.chevronDown, size: 16, color: c.news),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Segmented toggle (Percentage / Fixed) ───────────────────────────────────

class ToggleChoice extends StatelessWidget {
  const ToggleChoice({super.key, required this.label, required this.selected, required this.onTap, this.small = false});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = small ? Radii.md : Radii.lg;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? c.ink : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r),
            side: BorderSide(color: selected ? c.ink : c.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(r),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? 8 : 12, vertical: small ? 4 : 6),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: inter(size: small ? FontSizes.xs : FontSizes.sm, color: selected ? c.paper : c.news),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── SplitTag ────────────────────────────────────────────────────────────────

/// Small pill on ledger entries that came from a group split.
class SplitTag extends StatelessWidget {
  const SplitTag(this.txn, {super.key});
  final Txn txn;

  @override
  Widget build(BuildContext context) {
    if (!txn.isSplit) return const SizedBox.shrink();
    final c = context.colors;
    final refund = txn.isRefund;
    final bg = refund ? (c.isDark ? const Color(0x4D14532D) : const Color(0xFFDCFCE7)) : c.ink.withValues(alpha: 0.1);
    final fg = refund ? (c.isDark ? AppColors.green400 : AppColors.green700) : c.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.users, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            refund ? 'Split refund' : 'Split expense',
            style: inter(size: FontSizes.xs11, weight: FontWeight.w500, color: fg, height: 1),
          ),
        ],
      ),
    );
  }
}

// ─── Loading / status ────────────────────────────────────────────────────────

class PageLoader extends StatelessWidget {
  const PageLoader({super.key, this.label = 'Loading…'});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.4,
      child: Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: context.colors.news)),
      ),
    ),
  );
}

/// "Loading dashboard…" style centered status text (p-8 text-center text-news).
class StatusText extends StatelessWidget {
  const StatusText(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: inter(size: FontSizes.base, color: error ? AppColors.red500 : context.colors.news),
      ),
    ),
  );
}

/// Round avatar with initial fallback.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.url, required this.name, this.size = 32});
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final fallback = Center(
      child: Text(
        initial,
        style: inter(size: size * 0.4, weight: FontWeight.w700, color: c.ink),
      ),
    );
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: c.newsLight,
        child: (url == null || url!.isEmpty) ? fallback : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

/// Inline confirm box used for destructive actions (red-bordered card with buttons).
class ConfirmBox extends StatelessWidget {
  const ConfirmBox({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFCA5A5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: children),
    );
  }
}

/// Category → icon mapping shared by Expenses and TransactionDetails.
IconData categoryIcon(String? category) {
  final cat = (category ?? '').toLowerCase();
  if (cat.contains('grocer') || cat.contains('food')) return LucideIcons.shoppingBasket;
  if (cat.contains('cloth') || cat.contains('wear')) return LucideIcons.shirt;
  if (cat.contains('electr') || cat.contains('mobile') || cat.contains('phone')) return LucideIcons.smartphone;
  if (cat.contains('transport') || cat.contains('gas') || cat.contains('fuel') || cat.contains('uber')) return LucideIcons.car;
  if (cat.contains('home') || cat.contains('rent') || cat.contains('house')) return LucideIcons.house;
  if (cat.contains('util') || cat.contains('bill') || cat.contains('internet')) return LucideIcons.zap;
  if (cat.contains('restaurant') || cat.contains('dining') || cat.contains('eat')) return LucideIcons.utensils;
  if (cat.contains('coffee') || cat.contains('cafe')) return LucideIcons.coffee;
  return LucideIcons.tag;
}
