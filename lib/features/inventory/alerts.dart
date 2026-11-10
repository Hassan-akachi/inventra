import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../catalogue/item_status.dart';
import '../catalogue/items.dart';
import '../sales/sales.dart';
import '../settings/settings.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';
import '../account/membership.dart';

enum AlertKind {
  expired('Expired', Icons.dangerous_outlined),
  outOfStock('Out of stock', Icons.remove_shopping_cart_outlined),
  expiring('Expiring soon', Icons.event_busy_outlined),
  lowStock('Low in stock', Icons.trending_down),
  unpaid('Unpaid sales', Icons.money_off_outlined);

  const AlertKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AppAlert {
  const AppAlert(this.kind, this.title, this.detail, this.route);
  final AlertKind kind;
  final String title;
  final String detail;
  final String route;
}

/// Everything in the current shop that needs attention, worked out live.
final alertsProvider =
    Provider.family<AsyncValue<List<AppAlert>>, String>((ref, shopId) {
  final items = ref.watch(itemsForShopProvider(shopId));
  final unpaid = ref.watch(unpaidSalesProvider(shopId));
  final settings = ref.watch(settingsProvider);

  if (items.hasError) return AsyncValue.error(items.error!, items.stackTrace!);
  if (unpaid.hasError) return AsyncValue.error(unpaid.error!, unpaid.stackTrace!);
  if (!items.hasValue || !unpaid.hasValue) return const AsyncValue.loading();

  final alerts = <AppAlert>[];
  for (final i in items.value!) {
    if (i.discontinued) continue;
    final route = '/item/${i.id}';
    final days = daysToExpiry(i.expiryDate);
    switch (i.status) {
      case ItemStatus.expired:
        alerts.add(AppAlert(AlertKind.expired, i.name,
            'Expired ${formatDate(i.expiryDate)} · ${i.quantity} ${i.baseUnit} left', route));
      case ItemStatus.out:
        alerts.add(AppAlert(AlertKind.outOfStock, i.name, 'No ${i.baseUnit} left', route));
      case ItemStatus.low:
        alerts.add(AppAlert(AlertKind.lowStock, i.name,
            '${i.quantity} ${i.baseUnit} left (warning at ${i.lowStockLevel})', route));
      case ItemStatus.available:
      case ItemStatus.discontinued:
        break;
    }
    if (i.status != ItemStatus.expired &&
        days != null &&
        days <= settings.expiryWarningDays &&
        i.quantity > 0) {
      alerts.add(AppAlert(
        AlertKind.expiring,
        i.name,
        '${days == 0 ? 'Expires today' : 'Expires in $days day${days == 1 ? '' : 's'}'}'
        ' · ${i.quantity} ${i.baseUnit} left',
        route,
      ));
    }
  }

  final cutoff = DateTime.now().subtract(Duration(days: settings.unpaidAlertDays));
  for (final s in unpaid.value!) {
    final soldAt = DateTime.tryParse(s.soldAt);
    if (soldAt == null || soldAt.isAfter(cutoff)) continue;
    alerts.add(AppAlert(
      AlertKind.unpaid,
      '${s.customerName ?? 'No customer'} · ${s.receiptNo}',
      'Owes ${Money.format(s.balance, s.currency)} since ${formatDate(s.soldAt)}',
      '/sale/${s.id}',
    ));
  }

  alerts.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return AsyncValue.data(alerts);
});

/// Bell icon with a count, for app bars.
class AlertsButton extends ConsumerWidget {
  const AlertsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(activeShopProvider).valueOrNull;
    if (shop == null) return const SizedBox.shrink();
    final count = ref.watch(alertsProvider(shop.id)).valueOrNull?.length ?? 0;
    return IconButton(
      tooltip: 'Alerts',
      onPressed: () => context.push('/alerts'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(count > 0 ? Icons.notifications_active_outlined : Icons.notifications_none),
      ),
    );
  }
}

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(activeShopProvider).valueOrNull;
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alerts')),
        body: const EmptyState(icon: Icons.storefront_outlined, title: 'Add a shop first'),
      );
    }
    final alerts = ref.watch(alertsProvider(shop.id));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const ShopSwitcher()),
      body: AsyncBody(
        value: alerts,
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'All good',
              message: 'No low stock, expiring items or overdue payments.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final kind in AlertKind.values)
                if (list.any((a) => a.kind == kind))
                  SectionCard(
                    title: '${kind.label} (${list.where((a) => a.kind == kind).length})',
                    children: [
                      for (final a in list.where((a) => a.kind == kind))
                        ListTile(
                          dense: true,
                          leading: Icon(kind.icon,
                              color: kind == AlertKind.lowStock || kind == AlertKind.expiring
                                  ? const Color(0xFFE65100)
                                  : theme.colorScheme.error),
                          title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(a.detail),
                          trailing: (kind == AlertKind.lowStock || kind == AlertKind.outOfStock) &&
                                  ref.watch(permissionsProvider).canAdjustStock
                              ? TextButton(
                                  onPressed: () => context.push(
                                      '/restock?item=${a.route.substring('/item/'.length)}'),
                                  child: const Text('Restock'),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: () => context.push(a.route),
                        ),
                    ],
                  ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Expiry warnings start ${ref.watch(settingsProvider).expiryWarningDays} days ahead; '
                  'unpaid sales show after ${ref.watch(settingsProvider).unpaidAlertDays} days. '
                  'Change these in Settings.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
