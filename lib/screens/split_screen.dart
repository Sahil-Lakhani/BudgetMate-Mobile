import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/balances.dart';
import '../core/currency.dart';
import '../core/utils.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/loading.dart';
import '../widgets/ui.dart';

/// Navigation data is untrusted: anything that isn't a positive amount becomes null.
double? normaliseTotal(Object? value) {
  final n = parseNum(value);
  if (n == null || n <= 0) return null;
  return round2(n);
}

/// Assign shares and confirm (port of pages/SplitScreen.jsx).
class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key, required this.groupId, this.data});
  final String groupId;
  final Map<String, dynamic>? data; // merchant, totalAmount, date, lineItems?

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> {
  late final String? _merchant = widget.data?['merchant'] as String?;
  late final String _date = (widget.data?['date'] as String?) ?? localDate();
  late final double? _total = normaliseTotal(widget.data?['totalAmount']);
  late final List<Map<String, dynamic>>? _lineItems =
      (widget.data?['lineItems'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Group? _group;
  bool _loading = true;
  final Map<String, bool> _active = {};
  final Map<String, double> _amounts = {};
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final g = await ref.read(firestoreServiceProvider).getGroup(widget.groupId);
      _group = g;
      if (g != null && _total != null) {
        for (final m in g.members) {
          _active[m.userId] = true;
        }
        _splitEqually(g.members);
      }
    } catch (e) {
      debugPrint('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _me => ref.read(uidProvider)!;
  List<GroupMember> get _activeMembers => _group?.members.where((m) => _active[m.userId] == true).toList() ?? const [];

  TextEditingController _ctrl(String uid) => _controllers.putIfAbsent(uid, TextEditingController.new);

  void _setAmount(String uid, double v, {bool updateText = true}) {
    _amounts[uid] = v;
    if (updateText) _ctrl(uid).text = v.toStringAsFixed(2);
  }

  void _splitEqually([List<GroupMember>? members]) {
    final list = members ?? _activeMembers;
    final payerIndex = list.indexWhere((m) => m.userId == _me);
    final shares = distributeEvenly(_total ?? 0, list.length, payerIndex);
    for (var i = 0; i < list.length; i++) {
      _setAmount(list[i].userId, shares[i]);
    }
    setState(() {});
  }

  void _toggle(String uid) {
    if (uid == _me) return; // payer is always a participant
    final next = {..._active, uid: !(_active[uid] ?? false)};
    final nowActive = _group!.members.where((m) => next[m.userId] == true).toList();
    if (nowActive.isEmpty) return;
    _active
      ..clear()
      ..addAll(next);
    _splitEqually(nowActive);
  }

  Future<void> _confirm(double assignedDiff) async {
    if (assignedDiff.abs() >= 0.005) return;
    final group = _group!;
    final user = ref.read(currentUserProvider)!;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final participants = group.members
          .where((m) => _active[m.userId] == true && (m.userId == user.uid || (_amounts[m.userId] ?? 0) > 0))
          .map((m) => {'userId': m.userId, 'displayName': m.displayName, 'photoURL': m.photoURL, 'amount': _amounts[m.userId] ?? 0, 'status': 'pending'})
          .toList();

      final fs = ref.read(firestoreServiceProvider);
      final result = await fs.createSplit(widget.groupId, user.uid,
          merchant: _merchant!, date: _date, totalAmount: _total!, participants: participants, lineItems: _lineItems);

      // Best-effort fan-out: the split is saved, so failed notifications never surface as errors
      await Future.wait(participants.where((p) => p['userId'] != user.uid).map((p) => fs.createNotification(p['userId'] as String, {
            'type': 'split_added',
            'splitId': result.splitId,
            'groupId': widget.groupId,
            'groupName': group.name,
            'payerName': user.displayName ?? user.email ?? '',
            'merchant': _merchant,
            'amount': p['amount'],
          }).catchError((Object e) => debugPrint('Notification not sent: $e'))));

      if (mounted) context.go('/groups/${widget.groupId}');
    } catch (e) {
      debugPrint('$e');
      if (mounted) {
        setState(() {
          _error = 'Failed to save split. Try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading) {
      return const PageSkeleton(SkeletonKind.detail, label: 'Loading group…');
    }
    Widget message(String text, String button, String target) => PageScroll(children: [
          Text(text, style: inter(size: FontSizes.base, color: c.news)),
          Align(alignment: Alignment.centerLeft, child: AppButton(onPressed: () => context.go(target), label: button)),
        ]);

    final group = _group;
    if (group == null || _merchant == null || _merchant.isEmpty || _total == null) {
      return message('Missing split data. Go back and try again.', 'Back to Group', '/groups/${widget.groupId}');
    }
    if (!group.members.any((m) => m.userId == _me)) {
      return message("You're no longer a member of this group, so you can't split a bill in it.", 'Back to Groups', '/groups');
    }

    final symbol = currencySymbol(ref.watch(currencyProvider));
    final total = _total;
    final active = _activeMembers;
    final assigned = round2(active.fold(0.0, (s, m) => s + (_amounts[m.userId] ?? 0)));
    final diff = round2(total - assigned);
    final valid = diff.abs() < 0.005;
    final zeroShare = active.where((m) => m.userId != _me && !((_amounts[m.userId] ?? 0) > 0)).toList();
    final dark = c.isDark;

    return PageScroll(
      maxWidth: 512,
      children: [
        Row(children: [
          AppIconButton(
            icon: LucideIcons.arrowLeft,
            tooltip: 'Go back',
            onPressed: () => context.canPop() ? context.pop() : context.go('/groups/${widget.groupId}'),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const PageTitle('Split Bill', size: FontSizes.x3l),
              Text('$_merchant · $symbol${total.toStringAsFixed(2)}', style: inter(size: FontSizes.sm, color: c.news)),
            ]),
          ),
        ]),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(children: [
                const Expanded(child: CardTitle('Assign Shares')),
                AppButton(
                  onPressed: () => _splitEqually(),
                  icon: LucideIcons.equal,
                  label: 'Split equally',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.sm,
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(children: [
                for (var i = 0; i < group.members.length; i++)
                  _SplitRow(
                    member: group.members[i],
                    controller: _ctrl(group.members[i].userId),
                    isActive: _active[group.members[i].userId] == true,
                    isLastActive: group.members[i].userId == _me || (active.length == 1 && _active[group.members[i].userId] == true),
                    symbol: symbol,
                    last: i == group.members.length - 1,
                    onToggle: () => _toggle(group.members[i].userId),
                    onChanged: (v) => setState(() {
                      final n = parseDecimal(v) ?? 0;
                      _setAmount(group.members[i].userId, n < 0 ? 0 : round2(n), updateText: false);
                    }),
                  ),
              ]),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: valid
                ? (dark ? const Color(0x3314532D) : const Color(0xFFF0FDF4))
                : (dark ? const Color(0x337F1D1D) : const Color(0xFFFEF2F2)),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(children: [
            Expanded(
              child: Text('Assigned',
                  style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: valid ? AppColors.green700 : AppColors.red600)),
            ),
            Flexible(
              child: Text(
                '$symbol${assigned.toStringAsFixed(2)} / $symbol${total.toStringAsFixed(2)}'
                '${valid ? '' : ' (${diff > 0 ? '-' : '+'}${diff.abs().toStringAsFixed(2)} remaining)'}',
                textAlign: TextAlign.right,
                style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: valid ? AppColors.green700 : AppColors.red600),
              ),
            ),
          ]),
        ),
        if (zeroShare.isNotEmpty)
          Text(
            '${zeroShare.map((m) => m.displayName.isNotEmpty ? m.displayName : (m.email.isNotEmpty ? m.email : 'A member')).join(', ')} '
            '${zeroShare.length == 1 ? 'has' : 'have'} a 0.00 share and will be left out of this split.',
            style: inter(size: FontSizes.xs, color: c.news),
          ),
        Text(
          "The full $symbol${total.toStringAsFixed(2)} is added to your expenses now; each share comes back as a refund when it's settled.",
          style: inter(size: FontSizes.xs, color: c.news),
        ),
        if (_error.isNotEmpty) ErrorText(_error),
        AppButton(
          onPressed: !valid || _saving ? null : () => _confirm(diff),
          expand: true,
          child: _saving
              ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.paper)),
                  const SizedBox(width: 8),
                  const Text('Saving…'),
                ])
              : const Text('Confirm Split'),
        ),
      ],
    );
  }
}

/// Port of components/SplitRow.jsx.
class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.member,
    required this.controller,
    required this.isActive,
    required this.isLastActive,
    required this.symbol,
    required this.last,
    required this.onToggle,
    required this.onChanged,
  });

  final GroupMember member;
  final TextEditingController controller;
  final bool isActive;
  final bool isLastActive;
  final String symbol;
  final bool last;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final toggleDisabled = isActive && isLastActive;
    final name = member.displayName.isNotEmpty ? member.displayName : (member.email.isNotEmpty ? member.email : 'member');

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: isActive ? 1 : 0.4,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.border))),
        child: Row(children: [
          Avatar(url: member.photoURL, name: name, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(member.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.ink)),
              Text(member.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(size: FontSizes.xs, color: c.news)),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            height: 34,
            child: Semantics(
              label: 'Share for $name',
              textField: true,
              child: TextField(
                controller: controller,
                enabled: isActive,
                onChanged: onChanged,
                keyboardType: decimalKeyboard,
                inputFormatters: [decimalFormatter],
                // Inactive rows show an empty field (web: value="")
                style: inter(size: FontSizes.sm, color: isActive ? c.ink : Colors.transparent),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: isActive ? c.paper : c.newsLight,
                  prefixText: '$symbol ',
                  prefixStyle: inter(size: FontSizes.xs, color: c.news),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: c.border)),
                  disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide(color: c.ink)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: '${isActive ? 'Remove' : 'Add'} $name ${isActive ? 'from' : 'to'} split',
            child: Opacity(
              opacity: toggleDisabled ? 0.4 : 1,
              child: GestureDetector(
                onTap: toggleDisabled ? null : onToggle,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isActive ? c.ink : c.paper,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: isActive ? c.ink : c.news, width: 2),
                  ),
                  child: isActive ? Icon(LucideIcons.check, size: 12, color: c.paper) : null,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
