import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/validation.dart';
import '../data/models.dart';
import '../providers/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui.dart';
import '../widgets/user_search.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _name = TextEditingController();
  final List<GroupMember> _members = [];
  bool _saving = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final user = ref.read(currentUserProvider)!;
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Group name is required');
    if (_members.length + 1 > groupMemberLimit) {
      return setState(() => _error = 'Groups are limited to $groupMemberLimit members, including you.');
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final self = GroupMember(userId: user.uid, displayName: user.displayName ?? '', email: user.email ?? '', photoURL: user.photoURL ?? '');
      final id = await ref.read(firestoreServiceProvider).createGroup(user.uid, name: _name.text.trim(), members: [self, ..._members]);
      if (mounted) context.go('/groups/$id');
    } catch (e) {
      debugPrint('$e');
      if (mounted) {
        setState(() {
          _error = 'Failed to create group. Try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider)!;
    final addedIds = [user.uid, ..._members.map((m) => m.userId)];

    return PageScroll(
      maxWidth: 512,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const PageTitle('New Group', size: FontSizes.x3l),
          const SizedBox(height: 4),
          Text('Name your group and add members', style: inter(size: FontSizes.sm, color: c.news)),
        ]),
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const CardTitle('Group Details'),
            const SizedBox(height: 30),
            const FieldLabel('Group Name'),
            const SizedBox(height: 4),
            AppInput(controller: _name, maxLength: 60, placeholder: 'e.g. Roommates, Bali Trip', semanticLabel: 'Group Name'),
            const SizedBox(height: 16),
            const FieldLabel('Add Members'),
            const SizedBox(height: 8),
            UserSearch(
              addedIds: addedIds,
              onAdd: (u) {
                if (!addedIds.contains(u.userId)) setState(() => _members.add(u.toMember()));
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Only people who already have a BudgetMate account can be found. Members see the group name, each '
              "other's name, email and photo, and all splits in the group. Only add people who agreed to it.",
              style: inter(size: FontSizes.xs, color: c.news),
            ),
            const SizedBox(height: 16),
            Text('MEMBERS (${_members.length + 1})', style: inter(size: FontSizes.xs, color: c.news, letterSpacing: 0.6)),
            const SizedBox(height: 8),
            MemberTile(name: user.displayName ?? '', email: user.email ?? '', photoURL: user.photoURL, you: true),
            for (var i = 0; i < _members.length; i++)
              MemberTile(
                name: _members[i].displayName,
                email: _members[i].email,
                photoURL: _members[i].photoURL,
                border: i != _members.length - 1,
                trailing: AppIconButton(
                  icon: LucideIcons.x,
                  iconSize: 16,
                  size: 32,
                  color: c.news,
                  tooltip: 'Remove ${_members[i].displayName.isNotEmpty ? _members[i].displayName : 'member'}',
                  onPressed: () => setState(() => _members.removeAt(i)),
                ),
              ),
            if (_error.isNotEmpty) ...[const SizedBox(height: 16), ErrorText(_error)],
            const SizedBox(height: 24),
            Row(spacing: 12, children: [
              Expanded(
                child: AppButton(onPressed: () => context.go('/groups'), label: 'Cancel', variant: ButtonVariant.outline, expand: true),
              ),
              Expanded(
                child: AppButton(
                  onPressed: _saving ? null : _create,
                  expand: true,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (_saving) ...[
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.paper)),
                      const SizedBox(width: 8),
                    ],
                    const Text('Create Group'),
                  ]),
                ),
              ),
            ]),
          ]),
        ),
      ],
    );
  }
}
