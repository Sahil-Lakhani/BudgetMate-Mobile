import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/balances.dart';
import '../core/currency.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/loading.dart';
import '../widgets/ui.dart';

/// Live splits across all of the user's groups, so balances move when anyone adds or settles.
final _allSplitsProvider = StreamProvider<List<GroupSplit>>((ref) {
  final ids = ref.watch(groupsProvider.select((g) => (g.value ?? const <Group>[]).map((x) => x.id).join(',')));
  if (ids.isEmpty) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).watchSplitsForGroups(ids.split(','));
});

/// "+€12.00" / "−€3.50" colored net amount (web: renderNet).
class NetAmount extends StatelessWidget {
  const NetAmount(this.value, {super.key, required this.symbol, this.size = FontSizes.xs, this.weight = FontWeight.w400});
  final double value;
  final String symbol;
  final double size;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = value > 0 ? AppColors.green600 : (value < 0 ? AppColors.red500 : c.news);
    return Text(
      '${value > 0 ? '+' : value < 0 ? '−' : ''}$symbol${value.abs().toStringAsFixed(2)}',
      style: inter(size: size, weight: weight, color: color).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _openNotification(BuildContext context, WidgetRef ref, AppNotification n) async {
    final uid = ref.read(uidProvider)!;
    ref.read(firestoreServiceProvider).markNotificationRead(uid, n.id).catchError((Object e) => debugPrint('$e'));
    context.push(n.type == 'group_added' ? '/groups/${n.groupId}' : '/groups/${n.groupId}/split/${n.splitId}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final uid = ref.watch(uidProvider)!;
    final symbol = currencySymbol(ref.watch(currencyProvider));
    final groupsAsync = ref.watch(groupsProvider);
    final groups = groupsAsync.value ?? const <Group>[];
    final splits = ref.watch(_allSplitsProvider).value ?? const <GroupSplit>[];
    final notifications = [...?ref.watch(unreadNotificationsProvider).value]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final overall = computeBalances(splits, uid);

    return PageScroll(
      onRefresh: () async => ref.invalidate(groupsProvider),
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const PageTitle('Groups', size: FontSizes.x3l),
              const SizedBox(height: 4),
              Text('Split bills with friends', style: inter(size: FontSizes.sm, color: c.news)),
            ]),
          ),
          AppButton(onPressed: () => context.push('/groups/new'), icon: LucideIcons.plus, label: 'New Group'),
        ]),
        if (groups.isNotEmpty)
          AppCard(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(LucideIcons.scale, size: 14, color: c.news),
                const SizedBox(width: 8),
                Text('OVERALL BALANCE', style: inter(size: FontSizes.xs, color: c.news, letterSpacing: 0.6)),
              ]),
              const SizedBox(height: 12),
              Row(spacing: 16, children: [
                Expanded(child: _stat(c, 'You owe', '$symbol${overall.youOwe.toStringAsFixed(2)}', overall.youOwe > 0 ? AppColors.red500 : c.ink)),
                Expanded(
                  child: _stat(c, "You're owed", '$symbol${overall.owedToYou.toStringAsFixed(2)}', overall.owedToYou > 0 ? AppColors.green600 : c.ink),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Net', style: inter(size: FontSizes.xs, color: c.news)),
                    NetAmount(overall.net, symbol: symbol, size: FontSizes.xl, weight: FontWeight.w700),
                  ]),
                ),
              ]),
            ]),
          ),
        if (notifications.isNotEmpty)
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                child: Row(children: [
                  Icon(LucideIcons.bell, size: 16, color: c.ink),
                  const SizedBox(width: 8),
                  const Expanded(child: CardTitle('Activity')),
                  AppButton(
                    onPressed: () => ref.read(firestoreServiceProvider).markAllNotificationsRead(uid).catchError((Object e) => debugPrint('$e')),
                    label: 'Mark all read',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.sm,
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(children: [
                  for (var i = 0; i < notifications.length; i++)
                    Container(
                      decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.border))),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Radii.md),
                        onTap: () => _openNotification(context, ref, notifications[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          child: _notificationRow(c, notifications[i], symbol),
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        if (groupsAsync.isLoading && !groupsAsync.hasValue)
          // Placeholder group cards while the list loads
          Semantics(
            label: 'Loading groups…',
            child: Shimmer(
              child: Column(spacing: 12, children: [
                for (var i = 0; i < 3; i++)
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(children: [
                      const Bone(height: 40, circle: true),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                          FractionallySizedBox(widthFactor: 0.5 + i * 0.1, child: const Bone(height: 14)),
                          const FractionallySizedBox(widthFactor: 0.3, child: Bone(height: 10)),
                        ]),
                      ),
                    ]),
                  ),
              ]),
            ),
          )
        else if (groupsAsync.hasError && !groupsAsync.hasValue)
          const ErrorText("Couldn't load your groups. Check your connection and try again.", textAlign: TextAlign.center)
        else if (groups.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
              child: Column(spacing: 16, children: [
                Icon(LucideIcons.users, size: 48, color: c.news),
                Column(children: [
                  Text('No groups yet', style: inter(size: FontSizes.base, weight: FontWeight.w500, color: c.ink)),
                  const SizedBox(height: 4),
                  Text('Create a group to start splitting bills', style: inter(size: FontSizes.sm, color: c.news)),
                ]),
                AppButton(onPressed: () => context.push('/groups/new'), label: 'Create your first group'),
              ]),
            ),
          )
        else
          Column(spacing: 12, children: [
            for (final g in groups) _groupCard(context, c, g, computeBalances(splits.where((s) => s.groupId == g.id).toList(), uid).net, symbol),
          ]),
      ],
    );
  }

  Widget _stat(AppColors c, String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: inter(size: FontSizes.xs, color: c.news)),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: inter(size: FontSizes.xl, weight: FontWeight.w700, color: color))),
      ]);

  Widget _notificationRow(AppColors c, AppNotification n, String symbol) {
    final bold = inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.ink);
    final groupAdded = n.type == 'group_added';
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(
            groupAdded
                ? TextSpan(children: [
                    TextSpan(text: n.addedByName.isNotEmpty ? n.addedByName : 'Someone', style: bold),
                    const TextSpan(text: ' added you to '),
                    TextSpan(text: n.groupName.isNotEmpty ? n.groupName : 'a group', style: bold),
                  ])
                : TextSpan(children: [
                    TextSpan(text: n.payerName, style: bold),
                    const TextSpan(text: ' added you to a split at '),
                    TextSpan(text: n.merchant, style: bold),
                  ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: inter(size: FontSizes.sm, color: c.ink),
          ),
          Text(groupAdded ? 'New group' : n.groupName, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(size: FontSizes.xs, color: c.news)),
        ]),
      ),
      if (!groupAdded) ...[
        const SizedBox(width: 12),
        Text('$symbol${n.amount.toStringAsFixed(2)}', style: inter(size: FontSizes.sm, color: c.ink)),
      ],
    ]);
  }

  Widget _groupCard(BuildContext context, AppColors c, Group g, double net, String symbol) {
    final shown = g.members.take(3).toList();
    return AppCard(
      onTap: () => context.push('/groups/${g.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
          child: Icon(LucideIcons.users, size: 20, color: c.paper),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.name, style: inter(size: FontSizes.base, weight: FontWeight.w500, color: c.ink)),
            const SizedBox(height: 2),
            Row(children: [
              Text('${g.members.length} member${g.members.length != 1 ? 's' : ''}', style: inter(size: FontSizes.xs, color: c.news)),
              if (net != 0) ...[
                Text(' · ', style: inter(size: FontSizes.xs, color: c.news)),
                NetAmount(net, symbol: symbol),
              ],
            ]),
          ]),
        ),
        SizedBox(
          width: 28.0 + 20 * ((shown.length + (g.members.length > 3 ? 1 : 0)) - 1).clamp(0, 3),
          height: 28,
          child: Stack(children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * 20,
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.paper, width: 2)),
                  child: Avatar(url: shown[i].photoURL, name: shown[i].displayName, size: 24),
                ),
              ),
            if (g.members.length > 3)
              Positioned(
                left: shown.length * 20,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: c.newsLight, border: Border.all(color: c.paper, width: 2)),
                  child: Text('+${g.members.length - 3}', style: inter(size: FontSizes.xs, weight: FontWeight.w700, color: c.ink)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
