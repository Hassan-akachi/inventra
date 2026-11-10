import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/session.dart';
import '../../core/widgets.dart';
import '../shops/shops.dart';
import 'account_service.dart';
import 'membership.dart';

/// Owner-only: invite staff and choose their shops and permissions.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsProvider);
    final session = ref.watch(sessionProvider);
    if (!session.linked || !perms.canManageTeam) {
      return Scaffold(
        appBar: AppBar(title: const Text('Team')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Only the owner can manage the team',
          message: 'Sign in as the owner under More → Account and sync.',
        ),
      );
    }
    final members = ref.watch(membersProvider);
    final shops = ref.watch(shopsProvider).valueOrNull ?? const <Shop>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _invite(context, ref, shops),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Invite staff'),
      ),
      body: AsyncBody(
        value: members,
        builder: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            for (final m in list)
              ListTile(
                leading: CircleAvatar(
                  child: Icon(m.isOwner ? Icons.star_outline : Icons.person_outline),
                ),
                title: Text(m.displayName),
                subtitle: Text(m.isOwner
                    ? 'Owner · everything'
                    : [
                        m.shopIds.isEmpty
                            ? 'All shops'
                            : shops
                                .where((s) => m.shopIds.contains(s.id))
                                .map((s) => s.name)
                                .join(', '),
                        '${m.permissions.length} extra permission${m.permissions.length == 1 ? '' : 's'}',
                      ].join(' · ')),
                trailing: m.isOwner ? null : const Icon(Icons.chevron_right),
                onTap: m.isOwner ? null : () => _edit(context, ref, m, shops),
              ),
            if (list.length <= 1)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Invite staff with a code. They install Inventra, create an account, '
                  'choose "I work for a business" and type the code.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref, List<Shop> shops) async {
    final result = await showModalBottomSheet<({Set<String> perms, Set<String> shops})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AccessSheet(
        title: 'Invite staff',
        action: 'Create invite code',
        shops: shops,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      final code = await sb.Supabase.instance.client.rpc('create_invite', params: {
        'p_business': ref.read(sessionProvider).businessId,
        'p_permissions': jsonEncode(result.perms.toList()),
        'p_shop_ids': jsonEncode(result.shops.toList()),
      }) as String;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Invite code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(code,
                  style: Theme.of(c).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700, letterSpacing: 6)),
              const SizedBox(height: 12),
              const Text(
                  'Share this code with your staff member. It works once and expires in 7 days.',
                  textAlign: TextAlign.center),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(
                    text: 'Join my business on Inventra with invite code $code'));
                Navigator.pop(c);
              },
              child: const Text('Copy message'),
            ),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Member m, List<Shop> shops) async {
    final result = await showModalBottomSheet<({Set<String> perms, Set<String> shops})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AccessSheet(
        title: m.displayName,
        action: 'Save',
        shops: shops,
        initialPerms: m.permissions,
        initialShops: m.shopIds,
        onRemove: () async {
          final ok = await confirmDialog(context,
              title: 'Remove ${m.displayName}?',
              message: 'They will stop syncing this business. Sales they made stay.',
              action: 'Remove');
          if (ok) await ref.read(membersRepositoryProvider).remove(m.id);
          return ok;
        },
      ),
    );
    if (result == null) return;
    await ref
        .read(membersRepositoryProvider)
        .update(m.id, permissions: result.perms, shopIds: result.shops);
  }
}

class _AccessSheet extends StatefulWidget {
  const _AccessSheet({
    required this.title,
    required this.action,
    required this.shops,
    this.initialPerms = const {},
    this.initialShops = const {},
    this.onRemove,
  });

  final String title;
  final String action;
  final List<Shop> shops;
  final Set<String> initialPerms;
  final Set<String> initialShops;
  final Future<bool> Function()? onRemove;

  @override
  State<_AccessSheet> createState() => _AccessSheetState();
}

class _AccessSheetState extends State<_AccessSheet> {
  late final Set<String> _perms = {...widget.initialPerms};
  late final Set<String> _shops = {...widget.initialShops};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.shops.where((s) => !s.archived).toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Shops they can use', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Leave all unticked for every shop.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in active)
                  FilterChip(
                    label: Text(s.name),
                    selected: _shops.contains(s.id),
                    onSelected: (v) => setState(() => v ? _shops.add(s.id) : _shops.remove(s.id)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('They can always sell and see stock. Also allow:',
                style: theme.textTheme.titleSmall),
            for (final p in StaffPermission.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.label),
                value: _perms.contains(p.key),
                onChanged: (v) => setState(() => v == true ? _perms.add(p.key) : _perms.remove(p.key)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, (perms: _perms, shops: _shops)),
              child: Text(widget.action),
            ),
            if (widget.onRemove != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: () async {
                  final removed = await widget.onRemove!();
                  if (removed && context.mounted) Navigator.pop(context);
                },
                child: const Text('Remove from team'),
              ),
          ],
        ),
      ),
    );
  }
}
