import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/currency.dart';
import '../core/errors.dart';
import '../data/auth_service.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/footer.dart';
import '../widgets/ui.dart';

typedef _Budget = ({String income, String savingsType, String savingsValue});

/// Port of pages/Settings.jsx.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _empty = (income: '', savingsType: 'percentage', savingsValue: '');
  _Budget _saved = _empty;
  _Budget _budget = _empty;
  bool _loaded = false;
  bool _saving = false;
  String _saveError = '';

  bool _aiSaving = false;
  String _dataBusy = ''; // '', 'export', 'delete'
  String _dataError = '';
  bool _confirmDelete = false;
  final _deleteText = TextEditingController();
  final _income = TextEditingController();
  final _savingsValue = TextEditingController();

  @override
  void initState() {
    super.initState();
    _deleteText.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(firestoreServiceProvider).getUserSettings(ref.read(uidProvider)!);
      if (s != null && mounted) {
        final b = (income: s.incomeText, savingsType: s.savingsType, savingsValue: s.savingsValueText);
        setState(() {
          _saved = b;
          _budget = b;
          _income.text = b.income;
          _savingsValue.text = b.savingsValue;
        });
      }
    } catch (e) {
      debugPrint('$e');
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _deleteText.dispose();
    _income.dispose();
    _savingsValue.dispose();
    super.dispose();
  }

  bool get _dirty => _budget != _saved;

  void _change({String? income, String? savingsType, String? savingsValue}) => setState(() {
        _budget = (
          income: income ?? _budget.income,
          savingsType: savingsType ?? _budget.savingsType,
          savingsValue: savingsValue ?? _budget.savingsValue,
        );
      });

  Future<void> _save() async {
    final inc = parseDecimal(_budget.income) ?? 0;
    final sv = parseDecimal(_budget.savingsValue) ?? 0;
    if (inc < 0 || sv < 0) return setState(() => _saveError = "Amounts can't be negative.");
    if (_budget.savingsType == 'percentage' && sv > 100) return setState(() => _saveError = "A savings percentage can't be more than 100%.");
    if (_budget.savingsType == 'fixed' && sv > inc) return setState(() => _saveError = "Your savings goal can't be larger than your income.");
    setState(() {
      _saving = true;
      _saveError = '';
    });
    try {
      await ref.read(firestoreServiceProvider).updateUserSettings(ref.read(uidProvider)!, {
        'income': _budget.income.replaceAll(',', '.'),
        'savingsType': _budget.savingsType,
        'savingsValue': _budget.savingsValue.replaceAll(',', '.'),
      });
      setState(() => _saved = _budget);
    } catch (e) {
      setState(() => _saveError = userMessage(e, 'Failed to save. Please try again.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() => setState(() {
        _budget = _saved;
        _income.text = _saved.income;
        _savingsValue.text = _saved.savingsValue;
      });

  Future<void> _toggleAi(bool enabled) async {
    setState(() {
      _aiSaving = true;
      _dataError = '';
    });
    try {
      await ref.read(firestoreServiceProvider).updateUserSettings(ref.read(uidProvider)!, {'aiInsights': enabled});
    } catch (e) {
      setState(() => _dataError = userMessage(e, "Couldn't update the AI setting. Please try again."));
    } finally {
      if (mounted) setState(() => _aiSaving = false);
    }
  }

  Future<void> _export() async {
    setState(() {
      _dataBusy = 'export';
      _dataError = '';
    });
    try {
      await ref.read(accountServiceProvider).exportAndShare(ref.read(uidProvider)!);
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _dataError = 'Export failed. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _dataBusy = '');
    }
  }

  Future<void> _delete() async {
    setState(() {
      _dataBusy = 'delete';
      _dataError = '';
    });
    try {
      await ref.read(accountServiceProvider).deleteAccount();
      // Auth state → null; the router sends the user to /login
    } catch (e) {
      debugPrint('$e');
      if (!mounted) return;
      setState(() {
        _dataError = e is SignInCancelled
            ? 'Account deletion was cancelled — please confirm with Google to continue.'
            : (e is FirebaseAuthException && e.code == 'user-mismatch')
                ? 'Please confirm with the same Google account you are signed in with.'
                : 'Account deletion failed. Please try again, or contact us via the Impressum.';
        _dataBusy = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final currency = ref.watch(currencyProvider);
    final symbol = currencySymbol(currency);
    final aiOn = ref.watch(settingsProvider).value?.aiInsights ?? false;
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;

    final inc = parseDecimal(_budget.income) ?? 0;
    final sv = parseDecimal(_budget.savingsValue) ?? 0;
    final savingsAmount = _budget.savingsType == 'percentage' ? inc * sv / 100 : sv;
    final spendable = inc - savingsAmount;

    Widget section(String title, List<Widget> children, {double spacing = 12}) => AppCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CardTitle(title, size: FontSizes.lg),
              const SizedBox(height: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: spacing, children: children),
            ]),
          ),
        );
    Text label(String t) => Text(t, style: inter(size: FontSizes.base, weight: FontWeight.w500, color: c.ink));

    return PageScroll(
      maxWidth: 672,
      spacing: 16,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PageTitle('Profile', size: FontSizes.x3l),
          Text('Manage your account and preferences.', style: inter(size: FontSizes.base, color: c.news)),
        ]),
        if (user != null) ...[
          // Profile
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Avatar(url: user.photoURL, name: user.displayName ?? user.email ?? '?', size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.displayName ?? '', style: inter(size: FontSizes.base, weight: FontWeight.w600, color: c.ink, height: 1.25)),
                  Text(user.email ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(size: FontSizes.sm, color: c.news)),
                ]),
              ),
              const SizedBox(width: 16),
              AppButton(
                onPressed: () => ref.read(authServiceProvider).signOut(),
                icon: LucideIcons.logOut,
                label: 'Sign Out',
                variant: ButtonVariant.secondary,
                size: ButtonSize.sm,
              ),
            ]),
          ),
          // Analytics moved off the navbar; it opens from here
          AppCard(
            onTap: () => context.push('/analytics'),
            padding: const EdgeInsets.all(20),
            child: Semantics(
              button: true,
              label: 'Analytics',
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.newsLight.withValues(alpha: 0.5), shape: BoxShape.circle),
                  child: Icon(LucideIcons.chartPie, size: 20, color: c.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Analytics', style: inter(size: FontSizes.base, weight: FontWeight.w600, color: c.ink)),
                    Text('Spending trends and top categories', style: inter(size: FontSizes.sm, color: c.news)),
                  ]),
                ),
                Icon(LucideIcons.chevronRight, size: 20, color: c.news),
              ]),
            ),
          ),
          section('Appearance', [
            Row(children: [
              Icon(isDark ? LucideIcons.moon : LucideIcons.sun, size: 20, color: c.ink),
              const SizedBox(width: 12),
              Expanded(child: Text('Dark mode', style: inter(size: FontSizes.base, weight: FontWeight.w500, color: c.ink))),
              Semantics(
                label: 'Dark mode',
                toggled: isDark,
                child: Switch(value: isDark, onChanged: (v) => ref.read(themeProvider.notifier).setDark(v)),
              ),
            ]),
          ]),
          section('Currency', [
            AppSelect<String>(
              value: currency,
              semanticLabel: 'Currency',
              options: [for (final cur in currencies) SelectOption(cur.code, cur.label)],
              onChanged: (code) => ref
                  .read(firestoreServiceProvider)
                  .updateUserSettings(user.uid, {'currency': code}).catchError((Object e) => debugPrint('Failed to save currency $e')),
            ),
          ]),
          section('Budget', [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
              label('Monthly Income'),
              AppInput(
                controller: _income,
                enabled: _loaded,
                keyboardType: decimalKeyboard,
                inputFormatters: [decimalFormatter],
                prefix: symbol,
                placeholder: 'e.g. 3000',
                radius: Radii.lg,
                onChanged: (v) => _change(income: v),
                semanticLabel: 'Monthly Income',
              ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
              label('Savings Goal Type'),
              Row(spacing: 8, children: [
                ToggleChoice(label: 'Percentage (%)', selected: _budget.savingsType == 'percentage', onTap: () => _change(savingsType: 'percentage')),
                ToggleChoice(label: 'Fixed ($symbol)', selected: _budget.savingsType == 'fixed', onTap: () => _change(savingsType: 'fixed')),
              ]),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
              label(_budget.savingsType == 'percentage' ? 'Savings Percentage' : 'Savings Amount'),
              AppInput(
                controller: _savingsValue,
                enabled: _loaded,
                keyboardType: decimalKeyboard,
                inputFormatters: [decimalFormatter],
                prefix: _budget.savingsType == 'percentage' ? '%' : symbol,
                placeholder: _budget.savingsType == 'percentage' ? 'e.g. 20' : 'e.g. 600',
                radius: Radii.lg,
                onChanged: (v) => _change(savingsValue: v),
                semanticLabel: _budget.savingsType == 'percentage' ? 'Savings Percentage' : 'Savings Amount',
              ),
            ]),
            if ((inc > 0 && savingsAmount > 0) || _dirty)
              Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 12, children: [
                Expanded(
                  child: inc > 0 && savingsAmount > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: c.newsLight.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(Radii.lg),
                            border: Border.all(color: c.border),
                          ),
                          child: Text.rich(
                            TextSpan(children: [
                              const TextSpan(text: 'Saving '),
                              TextSpan(
                                  text: '$symbol${savingsAmount.toStringAsFixed(2)}/mo',
                                  style: inter(size: FontSizes.base, weight: FontWeight.w500, color: c.ink)),
                              const TextSpan(text: ' · '),
                              TextSpan(text: '$symbol${spendable.toStringAsFixed(2)}', style: inter(size: FontSizes.base, weight: FontWeight.w500, color: c.ink)),
                              const TextSpan(text: ' spendable'),
                            ]),
                            style: inter(size: FontSizes.base, color: c.news),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (_dirty)
                  Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
                    if (_saveError.isNotEmpty) SizedBox(width: 160, child: ErrorText(_saveError)),
                    Row(spacing: 12, children: [
                      AppButton(
                        onPressed: _save,
                        loading: _saving,
                        label: _saving ? 'Saving...' : 'Save',
                        radius: Radii.lg,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                      ),
                      GestureDetector(onTap: _reset, child: Text('Reset', style: inter(size: FontSizes.sm, color: c.news))),
                    ]),
                  ]),
              ]),
          ]),
          section('AI insights', spacing: 8, [
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(
                      text: "Once a month, send last month's expenses (dates, merchants, amounts, items — not your name or email) "
                          "to Google's Gemini AI to get personalised saving tips. Off by default; you can switch it off at any time. ",
                    ),
                    TextSpan(
                      text: 'Details',
                      style: inter(size: FontSizes.sm, color: c.news, decoration: TextDecoration.underline),
                      recognizer: TapGestureRecognizer()..onTap = () => openLegalPage(context, '/privacy#ai'),
                    ),
                  ]),
                  style: inter(size: FontSizes.sm, color: c.news),
                ),
              ),
              Semantics(
                label: 'AI insights',
                toggled: aiOn,
                child: Switch(value: aiOn, onChanged: _aiSaving ? null : _toggleAi),
              ),
            ]),
          ]),
          section('Your data', spacing: 16, [
            Text('Download a copy of everything stored for your account, or permanently delete your account and data.',
                style: inter(size: FontSizes.sm, color: c.news)),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              AppButton(
                onPressed: _dataBusy.isNotEmpty ? null : _export,
                variant: ButtonVariant.secondary,
                radius: Radii.md,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _dataBusy == 'export'
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))
                      : Icon(LucideIcons.download, size: 16, color: c.ink),
                  const SizedBox(width: 8),
                  const Text('Export my data (JSON)'),
                ]),
              ),
              if (!_confirmDelete)
                AppButton(
                  onPressed: _dataBusy.isNotEmpty ? null : () => setState(() => _confirmDelete = true),
                  icon: LucideIcons.trash2,
                  label: 'Delete account',
                  variant: ButtonVariant.secondary,
                  foreground: c.isDark ? AppColors.red400 : AppColors.red600,
                  radius: Radii.md,
                ),
            ]),
            if (_confirmDelete)
              ConfirmBox(children: [
                Text(
                  'This permanently deletes your expenses, settings, notifications and profile, removes you from your '
                  'groups and deletes your sign-in account. Split records you shared with others stay visible to them. '
                  'This cannot be undone. You will be asked to confirm with Google.',
                  style: inter(size: FontSizes.sm, color: c.ink),
                ),
                Text('Type DELETE to confirm', style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.ink)),
                AppInput(controller: _deleteText, radius: Radii.md, semanticLabel: 'Type DELETE to confirm'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  AppButton(
                    onPressed: _deleteText.text != 'DELETE' || _dataBusy.isNotEmpty ? null : _delete,
                    loading: _dataBusy == 'delete',
                    label: _dataBusy == 'delete' ? 'Deleting…' : 'Permanently delete',
                    variant: ButtonVariant.destructive,
                    radius: Radii.md,
                  ),
                  AppButton(
                    onPressed: _dataBusy == 'delete'
                        ? null
                        : () => setState(() {
                              _confirmDelete = false;
                              _deleteText.clear();
                            }),
                    label: 'Cancel',
                    variant: ButtonVariant.ghost,
                    radius: Radii.md,
                  ),
                ]),
              ]),
            if (_dataError.isNotEmpty) ErrorText(_dataError),
          ]),
        ],
      ],
    );
  }
}
