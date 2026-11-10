import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../catalogue/item_status.dart';
import '../catalogue/items.dart';
import '../inventory/alerts.dart';
import '../sales/sales.dart';
import '../settings/settings.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';
import '../account/membership.dart';

/// Phase 1 dashboard: stock overview for the current shop.
/// Sales figures are added in phase 2 and full reports in phase 5.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(activeShopProvider).valueOrNull;
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inventra')),
        body: EmptyState(
          icon: Icons.storefront_outlined,
          title: 'Welcome to Inventra',
          message: 'Add your first shop to get started.',
          action: FilledButton(
            onPressed: () => context.go('/items'),
            child: const Text('Get started'),
          ),
        ),
      );
    }
    final items = ref.watch(itemsForShopProvider(shop.id));
    final today = ref
            .watch(salesSummaryProvider(
                (shopId: shop.id, fromIso: startOfTodayIso())))
            .valueOrNull ??
        const SalesSummary();

    final expiryDays = ref.watch(settingsProvider).expiryWarningDays;
    final perms = ref.watch(permissionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const ShopSwitcher(),
        actions: const [AlertsButton()],
      ),
      body: AsyncBody(
        value: items,
        builder: (all) {
          final active = all.where((i) => !i.discontinued).toList();
          final low = active.where((i) => i.status == ItemStatus.low).toList();
          final out = active.where((i) => i.status == ItemStatus.out).toList();
          final expiring = active.where((i) {
            final d = daysToExpiry(i.expiryDate);
            return d != null && d <= expiryDays;
          }).toList()
            ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
          final stockValue = active.fold<int>(
              0,
              (sum, i) =>
                  sum + (i.quantity > 0 ? i.quantity * (i.costPrice ?? 0) : 0));
          final retailValue = active.fold<int>(
              0,
              (sum, i) =>
                  sum + (i.quantity > 0 ? i.quantity * (i.sellingPrice ?? 0) : 0));

          return ListView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            children: [
              _StatGrid(
                children: [
                  _Stat('Sales today', Money.format(today.total, shop.currency),
                      Icons.point_of_sale_outlined,
                      note: '${today.count} sale${today.count == 1 ? '' : 's'}',
                      onTap: () => context.push('/sales')),
                  if (perms.canSeeCosts)
                  _Stat('Profit today', Money.format(today.profit, shop.currency),
                      Icons.trending_up,
                      note: today.owed > 0
                          ? '${Money.format(today.owed, shop.currency)} unpaid'
                          : null),
                  _Stat('Items', '${active.length}', Icons.inventory_2_outlined),
                  _Stat('Low stock', '${low.length}', Icons.trending_down,
                      warn: low.isNotEmpty),
                  _Stat('Out of stock', '${out.length}', Icons.remove_shopping_cart_outlined,
                      warn: out.isNotEmpty),
                  _Stat('Expiring ≤ $expiryDays days', '${expiring.length}', Icons.event_busy_outlined,
                      warn: expiring.isNotEmpty),
                  if (perms.canSeeCosts)
                  _Stat('Stock value (cost)', Money.format(stockValue, shop.currency),
                      Icons.account_balance_wallet_outlined),
                  _Stat('Stock value (selling)', Money.format(retailValue, shop.currency),
                      Icons.sell_outlined),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => context.go('/sell'),
                      icon: const Icon(Icons.point_of_sale_outlined),
                      label: const Text('New sale'),
                    ),
                    if (perms.canAdjustStock)
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/restock'),
                      icon: const Icon(Icons.move_to_inbox_outlined),
                      label: const Text('Receive stock'),
                    ),
                    if (perms.canRecordExpenses)
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/expenses'),
                      icon: const Icon(Icons.receipt_outlined),
                      label: const Text('Expenses'),
                    ),
                    if (perms.canAdjustStock)
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/stock-count'),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Count stock'),
                    ),
                  ],
                ),
              ),
              if (out.isNotEmpty || low.isNotEmpty)
                SectionCard(
                  title: 'Needs restocking',
                  children: [
                    for (final i in [...out, ...low].take(10))
                      ListTile(
                        dense: true,
                        leading: ItemThumb(imagePath: i.imagePath, size: 36),
                        title: Text(i.name),
                        trailing: StatusChip(i.status),
                        subtitle: Text('${i.quantity} ${i.baseUnit} left'),
                        onTap: () => context.push('/item/${i.id}'),
                      ),
                  ],
                ),
              if (expiring.isNotEmpty)
                SectionCard(
                  title: 'Expiring soon',
                  children: [
                    for (final i in expiring.take(10))
                      ListTile(
                        dense: true,
                        leading: ItemThumb(imagePath: i.imagePath, size: 36),
                        title: Text(i.name),
                        subtitle: Text('Expiry ${formatDate(i.expiryDate)}'),
                        trailing: Text('${i.quantity} ${i.baseUnit}'),
                        onTap: () => context.push('/item/${i.id}'),
                      ),
                  ],
                ),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: () => context.push('/item/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add your first item'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Two cards per row whose height follows their content,
/// so bigger text sizes never overflow.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth > 600 ? 3 : 2;
      final width = c.maxWidth / columns;
      return Wrap(
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    });
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.icon,
      {this.warn = false, this.note, this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final bool warn;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warn ? theme.colorScheme.error : theme.colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.labelMedium,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (note != null)
              Text(note!,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      ),
    );
  }
}
