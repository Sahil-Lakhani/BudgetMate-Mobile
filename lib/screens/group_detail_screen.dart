import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/balances.dart';
import '../core/currency.dart';
import '../core/validation.dart';
import '../data/firestore_service.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/loading.dart';
import '../widgets/ui.dart';
import '../widgets/user_search.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  String? _confirming; // null | 'leave' | 'delete'
  bool _busy = false;
  String _error = '';
  bool _adding = false;
  String? _addingId;
  String _addError = '';

  Future<void> _addMember(Group group, UserProfile u) async {
    if (_addingId != null) return;
    setState(() {
      _addingId = u.userId;
      _addError = '';
    });
    final fs = ref.read(firestoreServiceProvider);
    final user = ref.read(currentUserProvider)!;
    try {
      await fs.addMemberToGroup(widget.groupId, u.toMember());
      // Best-effort, after the add has landed; a failed notification never reads as a failed add.
      fs.createNotification(u.userId, {
        'type': 'group_added',
        'groupId': widget.groupId,
        'groupName': group.name,
        'addedByName': user.displayName ?? user.email ?? '',
      }).catchError((Object e) => debugPrint('Notification not sent: $e'));
    } catch (e) {
      debugPrint('$e');
      setState(() => _addError = e is GroupError ? e.message : "Couldn't add that member. Try again.");
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  Future<void> _leaveOrDelete(bool delete) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final fs = ref.read(firestoreServiceProvider);
      delete ? await fs.deleteGroup(widget.groupId) : await fs.leaveGroup(widget.groupId, ref.read(uidProvider)!);
      if (mounted) context.go('/groups');
    } catch (e) {
      debugPrint('$e');
      setState(() {
        _error = delete ? "Couldn't delete the group. Try again." : "Couldn't leave the group. Try again.";
        _busy = false;
      });
    }
  }

  void _back() => context.go('/groups');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groupAsync = ref.watch(groupProvider(widget.groupId));
    if (groupAsync.isLoading && !groupAsync.hasValue) {
      return const PageSkeleton(SkeletonKind.detail, label: 'Loading group…');
    }
    final group = groupAsync.value;
    if (group == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(mainAxisSize: MainAxisSize.min, spacing: 16, children: [
          Text("This group doesn't exist, or you don't have access to it.",
              textAlign: TextAlign.center, style: inter(size: FontSizes.base, color: c.news)),
          AppButton(onPressed: _back, label: 'Back to groups', variant: ButtonVariant.secondary, radius: Radii.md),
        ]),
      );
    }

    final uid = ref.watch(uidProvider)!;
    final symbol = currencySymbol(ref.watch(currencyProvider));
    final splits = ref.watch(groupSplitsProvider(widget.groupId)).value ?? const <GroupSplit>[];
    final balances = computeBalances(splits, uid);
    final isCreator = group.createdBy == uid;
    final unsettled = splits.where((s) => s.participants.any((p) => !p.settled)).length;
    final isFull = group.memberIds.length >= groupMemberLimit;
    String memberName(String id) {
      final m = group.members.where((m) => m.userId == id).firstOrNull;
      if (m != null && m.displayName.isNotEmpty) return m.displayName;
      final b = balances.byMember[id]?.displayName ?? '';
      return b.isNotEmpty ? b : 'Member';
    }

    return PageScroll(
      children: [
        Row(children: [
          AppIconButton(icon: LucideIcons.arrowLeft, tooltip: 'Back to groups', onPressed: _back),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageTitle(group.name, size: FontSizes.x3l),
              Text('${group.members.length} members', style: inter(size: FontSizes.sm, color: c.news)),
            ]),
          ),
          const SizedBox(width: 8),
          AppButton(onPressed: () => context.push('/groups/${widget.groupId}/split/new'), icon: LucideIcons.plus, label: 'Add Split'),
        ]),
        // Balances
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('YOU OWE', style: inter(size: FontSizes.xs, color: c.news, letterSpacing: 0.6)),
                  Text('$symbol${balances.youOwe.toStringAsFixed(2)}',
                      style: inter(size: FontSizes.x2l, weight: FontWeight.w700, color: balances.youOwe > 0 ? AppColors.red500 : c.ink)),
                ]),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text("YOU'RE OWED", style: inter(size: FontSizes.xs, color: c.news, letterSpacing: 0.6)),
                  Text('$symbol${balances.owedToYou.toStringAsFixed(2)}',
                      style: inter(size: FontSizes.x2l, weight: FontWeight.w700, color: balances.owedToYou > 0 ? AppColors.green600 : c.ink)),
                ]),
              ),
            ]),
            if (balances.byMember.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(height: 1, color: c.border),
              const SizedBox(height: 16),
              for (final e in balances.byMember.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Expanded(
                      child: Text(e.value.amount > 0 ? '${memberName(e.key)} owes you' : 'You owe ${memberName(e.key)}',
                          style: inter(size: FontSizes.sm, color: c.ink)),
                    ),
                    Text('$symbol${e.value.amount.abs().toStringAsFixed(2)}',
                        style: inter(size: FontSizes.sm, color: e.value.amount > 0 ? AppColors.green600 : AppColors.red500)),
                  ]),
                ),
            ],
          ]),
        ),
        // Members
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(children: [
                Icon(LucideIcons.users, size: 16, color: c.ink),
                const SizedBox(width: 8),
                const CardTitle('Members'),
                const SizedBox(width: 6),
                Text('(${group.members.length}/$groupMemberLimit)', style: inter(size: FontSizes.sm, color: c.news)),
                const Spacer(),
                AppButton(
                  onPressed: !_adding && isFull
                      ? null
                      : () => setState(() {
                            _adding = !_adding;
                            _addError = '';
                          }),
                  icon: _adding ? LucideIcons.x : LucideIcons.userPlus,
                  label: _adding ? 'Done' : 'Add member',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.sm,
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_adding)
                  Container(
                    padding: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                      isFull
                          ? Text('${GroupErrors.full}.', style: inter(size: FontSizes.sm, color: c.news))
                          : UserSearch(addedIds: group.memberIds, onAdd: (u) => _addMember(group, u)),
                      if (_addingId != null)
                        Row(children: [
                          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: c.news)),
                          const SizedBox(width: 6),
                          Text('Adding…', style: inter(size: FontSizes.xs, color: c.news)),
                        ]),
                      if (_addError.isNotEmpty) ErrorText(_addError),
                      Text("New members see this group's splits but aren't part of splits made before they joined.",
                          style: inter(size: FontSizes.xs, color: c.news)),
                    ]),
                  ),
                for (var i = 0; i < group.members.length; i++)
                  MemberTile(
                    name: group.members[i].displayName,
                    email: group.members[i].email,
                    photoURL: group.members[i].photoURL,
                    border: i != group.members.length - 1,
                    trailing: group.members[i].userId == group.createdBy ? const Pill('Creator') : null,
                  ),
              ]),
            ),
          ]),
        ),
        // Splits
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Splits', style: inter(size: FontSizes.lg, weight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 12),
          if (splits.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                child: Text('No splits yet. Tap "Add Split" to create one.', textAlign: TextAlign.center, style: inter(size: FontSizes.base, color: c.news)),
              ),
            ),
          for (final s in splits) Padding(padding: const EdgeInsets.only(bottom: 12), child: _splitCard(c, s, uid, symbol)),
        ]),
        // Leave / delete
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            if (_confirming == null)
              AppButton(
                onPressed: () => setState(() => _confirming = isCreator ? 'delete' : 'leave'),
                icon: isCreator ? LucideIcons.trash2 : LucideIcons.logOut,
                label: isCreator ? 'Delete group' : 'Leave group',
                variant: ButtonVariant.ghost,
                foreground: AppColors.red500,
                expand: true,
                alignment: MainAxisAlignment.start,
              ),
            if (_confirming != null) ...[
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: _confirming == 'leave' ? 'Leave ' : 'Delete '),
                  TextSpan(text: group.name, style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.ink)),
                  TextSpan(
                    text: _confirming == 'leave'
                        ? "? Splits you're already part of stay as they are."
                        : " and all ${splits.length} split${splits.length != 1 ? 's' : ''}? This can't be undone.",
                  ),
                  if (_confirming == 'delete' && unsettled > 0)
                    TextSpan(
                      text: '\n$unsettled split${unsettled != 1 ? 's are' : ' is'} still unsettled.',
                      style: inter(size: FontSizes.sm, color: AppColors.red500),
                    ),
                ]),
                style: inter(size: FontSizes.sm, color: c.ink),
              ),
              Row(spacing: 12, children: [
                Expanded(
                  child: AppButton(
                    onPressed: _busy ? null : () => setState(() => _confirming = null),
                    label: 'Cancel',
                    variant: ButtonVariant.outline,
                    expand: true,
                  ),
                ),
                Expanded(
                  child: AppButton(
                    onPressed: _busy ? null : () => _leaveOrDelete(_confirming == 'delete'),
                    variant: ButtonVariant.destructive,
                    expand: true,
                    child: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_confirming == 'leave' ? 'Leave' : 'Delete'),
                  ),
                ),
              ]),
            ],
            if (_error.isNotEmpty) ErrorText(_error),
          ]),
        ),
      ],
    );
  }

  Widget _splitCard(AppColors c, GroupSplit s, String uid, String symbol) {
    final mine = s.participant(uid);
    final settledCount = s.participants.where((p) => p.settled).length;
    final allSettled = settledCount == s.participants.length;
    final payerName = s.payerId == uid ? 'you' : (s.payerName.isNotEmpty ? s.payerName : 'someone');
    final myPending = mine != null && !mine.settled && s.payerId != uid;

    return AppCard(
      onTap: () => context.push('/groups/${widget.groupId}/split/${s.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.merchant, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(size: FontSizes.base, weight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: 2),
            Text(s.date, style: inter(size: FontSizes.xs, color: c.news)),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '$symbol${s.totalAmount.toStringAsFixed(2)}', style: inter(size: FontSizes.xs, weight: FontWeight.w500, color: c.ink)),
                TextSpan(text: ' paid by $payerName'),
              ]),
              style: inter(size: FontSizes.xs, color: c.news),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (mine != null)
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '$symbol${mine.amount.toStringAsFixed(2)}'),
                TextSpan(text: ' your share', style: inter(size: FontSizes.xs, color: c.news)),
              ]),
              style: inter(size: FontSizes.sm, weight: FontWeight.w700, color: myPending ? AppColors.red500 : c.ink),
            )
          else
            Text('Not included', style: inter(size: FontSizes.xs, color: c.news)),
          const SizedBox(height: 4),
          Pill(allSettled ? 'Settled' : 'Pending', green: allSettled, muted: !allSettled),
        ]),
      ]),
    );
  }
}
