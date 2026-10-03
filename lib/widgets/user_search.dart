import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Debounced people search over public profiles (web: components/UserSearch.jsx).
class UserSearch extends ConsumerStatefulWidget {
  const UserSearch({super.key, required this.addedIds, required this.onAdd});
  final List<String> addedIds;
  final ValueChanged<UserProfile> onAdd;

  @override
  ConsumerState<UserSearch> createState() => _UserSearchState();
}

class _UserSearchState extends ConsumerState<UserSearch> {
  String _query = '';
  List<UserProfile> _results = const [];
  bool _loading = false;
  Timer? _debounce;
  int _latest = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String value) async {
    final requestId = ++_latest;
    setState(() => _loading = true);
    try {
      final term = value.trim();
      final fs = ref.read(firestoreServiceProvider);
      // Stored emails are lowercase; names are matched as a case-sensitive prefix
      final (byEmail, byName) = await (fs.searchUsersByEmail(term.toLowerCase()), fs.searchUsersByName(term)).wait;
      if (requestId != _latest) return;
      final me = ref.read(uidProvider);
      final seen = <String>{};
      final merged = [...byEmail, ...byName]
          .where((u) => seen.add(u.userId))
          .where((u) => u.userId != me && (u.displayName.isNotEmpty || u.email.isNotEmpty))
          .toList();
      setState(() => _results = merged);
    } catch (_) {
      if (requestId == _latest) setState(() => _results = const []);
    } finally {
      if (requestId == _latest && mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (v.length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _query.length >= 2 ? _results : const <UserProfile>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Stack(alignment: Alignment.centerRight, children: [
        AppInput(
          onChanged: _onChanged,
          maxLength: 100,
          placeholder: 'Search by name or email…',
          keyboardType: TextInputType.emailAddress,
          semanticLabel: 'Search people by name or email',
        ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.news)),
          ),
      ]),
      if (list.isNotEmpty)
        Container(
          constraints: const BoxConstraints(maxHeight: 224),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: c.border)),
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: list.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
            itemBuilder: (_, i) {
              final u = list[i];
              final added = widget.addedIds.contains(u.userId);
              return Opacity(
                opacity: added ? 0.5 : 1,
                child: InkWell(
                  onTap: added ? null : () => widget.onAdd(u),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Avatar(url: u.photoURL, name: u.displayName.isNotEmpty ? u.displayName : u.email),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(u.displayName.isNotEmpty ? u.displayName : '—',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.ink)),
                          Text(u.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(size: FontSizes.xs, color: c.news)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      added
                          ? const Icon(LucideIcons.check, size: 16, color: AppColors.green500)
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.sm), border: Border.all(color: c.border)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(LucideIcons.plus, size: 12, color: c.ink.withValues(alpha: 0.7)),
                                const SizedBox(width: 4),
                                Text('Add', style: inter(size: FontSizes.xs, weight: FontWeight.w500, color: c.ink.withValues(alpha: 0.7))),
                              ]),
                            ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
    ]);
  }
}

/// Member row used in CreateGroup / GroupDetail.
class MemberTile extends StatelessWidget {
  const MemberTile({super.key, required this.name, required this.email, this.photoURL, this.you = false, this.trailing, this.border = true});
  final String name;
  final String email;
  final String? photoURL;
  final bool you;
  final Widget? trailing;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: border ? Border(bottom: BorderSide(color: c.border)) : null),
      child: Row(children: [
        Avatar(url: photoURL, name: name.isNotEmpty ? name : email),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: name),
                if (you) TextSpan(text: ' (You)', style: inter(size: FontSizes.sm, color: c.news)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: inter(size: FontSizes.sm, weight: FontWeight.w500, color: c.ink),
            ),
            Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: inter(size: FontSizes.xs, color: c.news)),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Small rounded pill (e.g. "Creator", "Pending", "Settled").
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.green = false, this.muted = false});
  final String text;
  final bool green;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = green ? const Color(0xFFDCFCE7) : c.ink.withValues(alpha: 0.1);
    final fg = green ? AppColors.green700 : (muted ? c.news : c.ink);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: inter(size: FontSizes.xs, color: fg)),
    );
  }
}
