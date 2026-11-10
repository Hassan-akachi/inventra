import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';
import 'restocks.dart';

/// History of goods received in the current shop.
class RestocksScreen extends ConsumerWidget {
  const RestocksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(activeShopProvider).valueOrNull;
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Restocks')),
        body: const EmptyState(icon: Icons.storefront_outlined, title: 'Add a shop first'),
      );
    }
    final restocks = ref.watch(shopRestocksProvider(shop.id));
    return Scaffold(
      appBar: AppBar(title: const ShopSwitcher()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/restock'),
        icon: const Icon(Icons.move_to_inbox_outlined),
        label: const Text('Receive stock'),
      ),
      body: AsyncBody(
        value: restocks,
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.move_to_inbox_outlined,
              title: 'No stock received yet',
              message: 'Record deliveries here so stock, cost prices and suppliers stay up to date.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => RestockTile(restock: list[i], showItem: true),
          );
        },
      ),
    );
  }
}

class RestockTile extends StatelessWidget {
  const RestockTile({super.key, required this.restock, this.showItem = false});
  final Restock restock;
  final bool showItem;

  @override
  Widget build(BuildContext context) {
    final r = restock;
    return ListTile(
      dense: !showItem,
      title: Text(
        showItem
            ? '${r.itemName} · +${r.quantity} ${r.unitName}'
            : '+${r.quantity} ${r.unitName}'
                '${r.baseQuantity != r.quantity ? ' (${r.baseQuantity})' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          formatDate(r.receivedAt),
          if (r.supplierName != null) r.supplierName!,
          if (r.expiryDate != null) 'exp. ${formatDate(r.expiryDate)}',
          if (r.note != null) r.note!,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: r.totalCost == null ? null : Text(Money.format(r.totalCost, r.currency)),
      onTap: showItem ? () => context.push('/item/${r.itemId}') : null,
    );
  }
}
