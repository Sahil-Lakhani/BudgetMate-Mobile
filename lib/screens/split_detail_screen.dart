import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/currency.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/loading.dart';
import '../widgets/ui.dart';
import '../widgets/user_search.dart';

class SplitDetailScreen extends ConsumerStatefulWidget {
  const SplitDetailScreen({super.key, required this.groupId, required this.splitId});
  final String groupId;
  final String splitId;

  @override
  ConsumerState<SplitDetailScreen> createState() => _SplitDetailScreenState();
}

class _SplitDetailScreenState extends ConsumerState<SplitDetailScreen> {
  bool _settling = false;
  String _note = '';

  Future<void> _settle(GroupSplit split, String target) async {
    final uid = ref.read(uidProvider)!;
    setState(() {
      _settling = true;
      _note = '';
    });
    try {
      await ref.read(firestoreServiceProvider).settleSplit(widget.splitId, target);
      setState(() => _note = target == split.payerId
          ? 'Marked settled.'
          : uid == split.payerId
              ? 'Recorded — the share was added back to your budget as a refund.'
              : 'Recorded — your share was added to your expenses.');
    } catch (e) {
      debugPrint('$e');
      setState(() => _note = "Couldn't record the settlement. Try again.");
    } finally {
      if (mounted) setState(() => _settling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final splitAsync = ref.watch(splitProvider(widget.splitId));
    if (splitAsync.isLoading && !splitAsync.hasValue) {
      return const PageSkeleton(SkeletonKind.detail, label: 'Loading split…');
    }
    final split = splitAsync.value;
    if (split == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(mainAxisSize: MainAxisSize.min, spacing: 16, children: [
          Text("This split doesn't exist, or you don't have access to it.",
              textAlign: TextAlign.center, style: inter(size: FontSizes.base, color: c.news)),
          AppButton(onPressed: () => context.go('/groups/${widget.groupId}'), label: 'Back to group', variant: ButtonVariant.secondary, radius: Radii.md),
        ]),
      );
    }

    final uid = ref.watch(uidProvider)!;
    final symbol = currencySymbol(ref.watch(currencyProvider));
    final allSettled = split.participants.every((p) => p.settled);

    return PageScroll(
      maxWidth: 512,
      children: [
        Row(children: [
          AppIconButton(icon: LucideIcons.arrowLeft, tooltip: 'Back to group', onPressed: () => context.go('/groups/${widget.groupId}')),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageTitle(split.merchant, size: FontSizes.x3l),
              Text('${split.date} · Total: $symbol${split.totalAmount.toStringAsFixed(2)}', style: inter(size: FontSizes.sm, color: c.news)),
            ]),
          ),
        ]),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(children: [
                const Expanded(child: CardTitle('Shares')),
                Pill(allSettled ? 'Fully Settled' : 'Pending', green: allSettled, muted: !allSettled),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(children: [
                for (var i = 0; i < split.participants.length; i++) _row(c, split, split.participants[i], uid, symbol, i == split.participants.length - 1),
              ]),
            ),
          ]),
        ),
        if (_note.isNotEmpty)
          Text(_note, style: inter(size: FontSizes.sm, color: _note.startsWith("Couldn't") ? AppColors.red500 : AppColors.green600)),
      ],
    );
  }

  Widget _row(AppColors c, GroupSplit split, SplitParticipant p, String uid, String symbol, bool last) {
    final isMe = p.userId == uid;
    final isPayer = p.userId == split.payerId;
    // New splits mark the payer's share settled at creation; older ones can still be ticked
    final canSettle = (isMe || uid == split.payerId) && !p.settled;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        Avatar(url: p.photoURL, name: p.displayName),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: p.displayName),
                if (isMe) TextSpan(text: ' (you)', style: inter(size: FontSizes.sm, color: c.news)),
                if (isPayer) TextSpan(text: ' · payer', style: inter(size: FontSizes.sm, color: c.news)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.ink),
            ),
            const SizedBox(height: 2),
            Text('$symbol${p.amount.toStringAsFixed(2)}', style: inter(size: FontSizes.xs, color: c.ink)),
          ]),
        ),
        if (p.settled)
          const Icon(LucideIcons.circleCheck, size: 20, color: AppColors.green500)
        else if (canSettle)
          AppButton(
            onPressed: _settling ? null : () => _settle(split, p.userId),
            label: 'Mark Settled',
            variant: ButtonVariant.outline,
            size: ButtonSize.sm,
          )
        else
          const Pill('Pending', muted: true),
      ]),
    );
  }
}
