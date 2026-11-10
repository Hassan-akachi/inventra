import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../catalogue/item_status.dart';
import '../catalogue/items.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';
import 'cart.dart';
import '../account/membership.dart';

/// Sell tab: find items by search or barcode and add them to the cart.
class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Adds [item]; asks which pack size when the item has packs.
  Future<void> _addItem(Item item, {String? unitId, bool fromScan = false}) async {
    if (item.status == ItemStatus.expired) {
      final ok = await confirmDialog(context,
          title: '${item.name} has expired',
          message: 'Expiry date ${formatDate(item.expiryDate)}. Sell it anyway?',
          action: 'Sell anyway');
      if (!ok || !mounted) return;
    }

    final units = await ref.read(itemsRepositoryProvider).getUnits(item.id);
    if (!mounted) return;
    ItemUnit? unit;
    if (unitId != null) {
      unit = units.where((u) => u.id == unitId).firstOrNull;
    } else if (units.isNotEmpty) {
      final choice = await _pickUnit(item, units);
      if (choice == null || !mounted) return;
      unit = choice.unit;
    }

    final error = ref.read(cartProvider.notifier).add(item, unit: unit);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final stockNote = item.quantity <= 0 ? ' (stock shows 0 — check your count)' : '';
    messenger.showSnackBar(SnackBar(
      content: Text('Added ${unit?.name ?? item.baseUnit} of ${item.name}$stockNote'),
      duration: const Duration(seconds: 2),
      action: fromScan
          ? SnackBarAction(label: 'Scan next', onPressed: () => _scan())
          : null,
    ));
  }

  Future<({ItemUnit? unit})?> _pickUnit(Item item, List<ItemUnit> units) {
    return showModalBottomSheet<({ItemUnit? unit})>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Sell ${item.name} by…',
                  style: Theme.of(sheet).textTheme.titleMedium),
            ),
            ListTile(
              title: Text('1 ${item.baseUnit}'),
              trailing: Text(Money.format(item.sellingPrice, item.currency)),
              onTap: () => Navigator.pop(sheet, (unit: null)),
            ),
            for (final u in units)
              ListTile(
                title: Text('1 ${u.name}'),
                subtitle: Text('${u.unitsPerPack} ${item.baseUnit}'),
                trailing: Text(Money.format(u.sellingPrice, item.currency)),
                onTap: () => Navigator.pop(sheet, (unit: u)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _scan() async {
    final shop = ref.read(activeShopProvider).valueOrNull;
    if (shop == null) return;
    final code = await context.push<String>('/scan');
    if (code == null || !mounted) return;
    final repo = ref.read(itemsRepositoryProvider);
    final match = await repo.matchBarcode(shop.id, code);
    if (!mounted) return;
    if (match == null && !ref.read(permissionsProvider).canEditItems) {
      showMessage(context, 'No item in ${shop.name} has barcode $code.');
      return;
    }
    if (match == null) {
      final add = await confirmDialog(context,
          title: 'Unknown barcode',
          message: 'No item in ${shop.name} has barcode $code. Add it as a new item?',
          action: 'Add item');
      if (add && mounted) {
        context.push('/item/new?barcode=${Uri.encodeQueryComponent(code)}');
      }
      return;
    }
    final item = await repo.getOne(match.itemId);
    if (item == null || !mounted) return;
    await _addItem(item, unitId: match.unitId, fromScan: true);
  }

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(activeShopProvider).valueOrNull;
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sell')),
        body: const EmptyState(
          icon: Icons.storefront_outlined,
          title: 'Add a shop first',
          message: 'Go to Items to add your first shop and its items.',
        ),
      );
    }

    final cart = ref.watch(cartProvider);
    final items = ref.watch(itemsForShopProvider(shop.id));
    final inCart = <String, int>{
      for (final l in cart.lines) l.itemId: 0,
    };
    for (final l in cart.lines) {
      inCart[l.itemId] = inCart[l.itemId]! + l.quantity;
    }
    final otherShop = !cart.isEmpty && cart.shopId != shop.id;

    return Scaffold(
      appBar: AppBar(
        title: const ShopSwitcher(),
        actions: [
          IconButton(
            tooltip: 'Sales history',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/sales'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Scan barcode',
        onPressed: _scan,
        child: const Icon(Icons.qr_code_scanner),
      ),
      bottomNavigationBar: cart.isEmpty ? null : _CartBar(cart: cart),
      body: Column(
        children: [
          if (otherShop)
            MaterialBanner(
              content: const Text(
                  'The cart has items from another shop. Switch back to finish that sale, or clear it.'),
              actions: [
                TextButton(
                  onPressed: () => ref.read(cartProvider.notifier).clear(),
                  child: const Text('Clear cart'),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search item to sell',
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: items,
              builder: (all) {
                final q = _search.trim().toLowerCase();
                final shown = all
                    .where((i) => !i.discontinued)
                    .where((i) =>
                        q.isEmpty ||
                        i.name.toLowerCase().contains(q) ||
                        (i.barcode ?? '').contains(q))
                    .toList();
                if (all.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No items to sell yet',
                    message: 'Add items in the Items tab first.',
                  );
                }
                if (shown.isEmpty) {
                  return const EmptyState(
                      icon: Icons.search_off, title: 'No items match');
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = shown[i];
                    final count = inCart[item.id];
                    return ListTile(
                      leading: Badge(
                        isLabelVisible: count != null,
                        label: Text('${count ?? ''}'),
                        child: ItemThumb(imagePath: item.imagePath),
                      ),
                      title: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${item.quantity} ${item.baseUnit} in stock'
                        '${item.status == ItemStatus.available ? '' : ' · ${item.status.label}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: item.status == ItemStatus.available
                            ? null
                            : TextStyle(
                                color: statusColor(item.status,
                                    Theme.of(context).colorScheme)),
                      ),
                      trailing: Text(
                        Money.format(item.sellingPrice, item.currency),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      onTap: () => _addItem(item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart});
  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: Money.format(cart.total, cart.currency ?? 'NGN'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text:
                          '\n${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'} in cart',
                      style: theme.textTheme.bodySmall,
                    ),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FilledButton.icon(
                onPressed: () => context.push('/cart'),
                icon: const Icon(Icons.shopping_cart_checkout),
                label: const Text('Checkout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
