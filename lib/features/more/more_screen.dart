import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/sync/sync.dart';
import '../account/membership.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final perms = ref.watch(permissionsProvider);
    final status = ref.watch(syncStatusProvider).valueOrNull;
    final pending = ref.watch(pendingUploadsProvider).valueOrNull ?? 0;

    final String syncText;
    if (!session.linked) {
      syncText = 'Not backed up — sign in to sync and add staff';
    } else if (status == null || !status.connected) {
      syncText = 'Offline${pending > 0 ? ' · $pending changes waiting' : ''}';
    } else {
      syncText = pending > 0 ? 'Syncing $pending changes…' : 'Backed up and in sync';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(session.linked
                ? (status?.connected ?? false
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined)
                : Icons.cloud_upload_outlined),
            title: Text(session.linked ? (session.email ?? 'Account') : 'Account and sync'),
            subtitle: Text(syncText),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/account'),
          ),
          if (session.linked && perms.canManageTeam)
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Team'),
              subtitle: const Text('Invite staff, shops and permissions'),
              onTap: () => context.push('/team'),
            ),
          const Divider(),
          if (perms.canManageShops)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Shops'),
              subtitle: const Text('Add, rename, set currency, archive'),
              onTap: () => context.push('/shops'),
            ),
          if (perms.canEditItems)
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Item categories'),
              subtitle: const Text('For the current shop'),
              onTap: () => context.push('/categories'),
            ),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: const Text('Suppliers'),
            onTap: () => context.push('/suppliers'),
          ),
          if (perms.canAdjustStock) ...[
            ListTile(
              leading: const Icon(Icons.move_to_inbox_outlined),
              title: const Text('Restocks'),
              subtitle: const Text('Goods received from suppliers'),
              onTap: () => context.push('/restocks'),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Stock count'),
              subtitle: const Text('Count shelves and fix differences'),
              onTap: () => context.push('/stock-count'),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Alerts'),
            subtitle: const Text('Low stock, expiry, unpaid sales'),
            onTap: () => context.push('/alerts'),
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Customers'),
            subtitle: const Text('Purchase history and money owed'),
            onTap: () => context.push('/customers'),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Sales history'),
            onTap: () => context.push('/sales'),
          ),
          if (perms.canSeeCosts)
            ListTile(
              leading: const Icon(Icons.currency_exchange),
              title: const Text('Exchange rates'),
              subtitle: const Text('For combined totals across currencies'),
              onTap: () => context.push('/rates'),
            ),
          if (perms.canRecordExpenses)
            ListTile(
              leading: const Icon(Icons.receipt_outlined),
              title: const Text('Expenses'),
              subtitle: const Text('Rent, salaries, fuel and other costs'),
              onTap: () => context.push('/expenses'),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            subtitle: const Text('Business details, text size, colour'),
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}
