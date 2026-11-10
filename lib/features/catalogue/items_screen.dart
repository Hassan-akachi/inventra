import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';
import '../shops/shops_screen.dart';
import 'categories.dart';
import 'item_status.dart';
import 'items.dart';
import '../account/membership.dart';

enum ItemSort {
  name('Name A–Z'),
  priceHigh('Price: high to low'),
  priceLow('Price: low to high'),
  quantityLow('Quantity: lowest first'),
  newest('Newest first');

  const ItemSort(this.label);
  final String label;
}

class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  String? _categoryId; // null = all
  ItemStatus? _status; // null = any
  ItemSort _sort = ItemSort.name;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scan(Shop shop) async {
    final code = await context.push<String>('/scan');
    if (code == null || !mounted) return;
    final id =
        await ref.read(itemsRepositoryProvider).findByBarcode(shop.id, code);
    if (!mounted) return;
    if (id != null) {
      context.push('/item/$id');
      return;
    }
    if (!ref.read(permissionsProvider).canEditItems) {
      showMessage(context, 'No item in ${shop.name} has barcode $code.');
      return;
    }
    final add = await confirmDialog(
      context,
      title: 'No item found',
      message: 'No item in ${shop.name} has barcode $code. Add a new item?',
      action: 'Add item',
    );
    if (add && mounted) {
      context.push('/item/new?barcode=${Uri.encodeQueryComponent(code)}');
    }
  }

  List<Item> _apply(List<Item> items) {
    final q = _search.trim().toLowerCase();
    final result = items.where((i) {
      if (_categoryId != null && i.categoryId != _categoryId) return false;
      if (_status != null && i.status != _status) return false;
      if (q.isEmpty) return true;
      return i.name.toLowerCase().contains(q) ||
          (i.barcode ?? '').contains(q) ||
          (i.description ?? '').toLowerCase().contains(q);
    }).toList();

    int byPrice(Item a, Item b) =>
        (a.sellingPrice ?? 0).compareTo(b.sellingPrice ?? 0);
    switch (_sort) {
      case ItemSort.name:
        result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case ItemSort.priceHigh:
        result.sort((a, b) => byPrice(b, a));
      case ItemSort.priceLow:
        result.sort(byPrice);
      case ItemSort.quantityLow:
        result.sort((a, b) => a.quantity.compareTo(b.quantity));
      case ItemSort.newest:
        result.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final shopValue = ref.watch(activeShopProvider);
    return shopValue.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (shop) {
        if (shop == null) return const _NoShopScaffold();
        return _buildForShop(context, shop);
      },
    );
  }

  Widget _buildForShop(BuildContext context, Shop shop) {
    final perms = ref.watch(permissionsProvider);
    final items = ref.watch(itemsForShopProvider(shop.id));
    final categories =
        ref.watch(categoriesForShopProvider(shop.id)).valueOrNull ?? const [];
    final activeCats = categories.where((c) => !c.archived).toList();
    if (_categoryId != null && !activeCats.any((c) => c.id == _categoryId)) {
      _categoryId = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: const ShopSwitcher(),
        actions: [
          IconButton(
            tooltip: 'Scan barcode',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _scan(shop),
          ),
          PopupMenuButton<String>(
            tooltip: 'Stock tools',
            onSelected: (route) => context.push(route),
            itemBuilder: (_) => [
              if (perms.canAdjustStock) ...const [
                PopupMenuItem(value: '/restock', child: Text('Receive stock')),
                PopupMenuItem(value: '/restocks', child: Text('Restock history')),
                PopupMenuItem(value: '/stock-count', child: Text('Count stock')),
              ],
              if (perms.canEditItems)
                const PopupMenuItem(value: '/categories', child: Text('Categories')),
              const PopupMenuItem(value: '/alerts', child: Text('Alerts')),
            ],
          ),
          PopupMenuButton<ItemSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => [
              for (final s in ItemSort.values)
                PopupMenuItem(value: s, child: Text(s.label)),
            ],
          ),
        ],
      ),
      floatingActionButton: !perms.canEditItems
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/item/new'),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search name or barcode',
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
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('All', _categoryId == null,
                    () => setState(() => _categoryId = null)),
                for (final c in activeCats)
                  _chip(c.name, _categoryId == c.id,
                      () => setState(() => _categoryId = c.id)),
                if (perms.canEditItems)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ActionChip(
                    avatar: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Categories'),
                    onPressed: () => context.push('/categories'),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('Any status', _status == null,
                    () => setState(() => _status = null)),
                for (final s in ItemStatus.values)
                  _chip(s.label, _status == s,
                      () => setState(() => _status = s)),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: items,
              builder: (all) {
                if (all.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No items in ${shop.name} yet',
                    message: 'Add items by hand or scan their barcodes.',
                    action: !perms.canEditItems ? null : FilledButton.icon(
                      onPressed: () => context.push('/item/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Add item'),
                    ),
                  );
                }
                final shown = _apply(all);
                if (shown.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_off,
                    title: 'No items match',
                    message: 'Try another search or filter.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _ItemTile(item: shown[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: ItemThumb(imagePath: item.imagePath),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            StatusChip(item.status),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                [
                  if (item.categoryName != null) item.categoryName!,
                  if (item.size != null) item.size!,
                ].join(' · '),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      // A single Text (not a Column) so large text sizes can't overflow the tile.
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: Money.format(item.sellingPrice, item.currency),
                style: theme.textTheme.titleSmall),
            TextSpan(
                text: '\n${item.quantity} ${item.baseUnit}',
                style: theme.textTheme.bodySmall),
          ]),
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onTap: () => context.push('/item/${item.id}'),
    );
  }
}

class _NoShopScaffold extends ConsumerWidget {
  const _NoShopScaffold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Items')),
      body: EmptyState(
        icon: Icons.storefront_outlined,
        title: 'Welcome to Inventra',
        message:
            'Start by adding your first shop — each shop keeps its own items and stock.',
        action: FilledButton.icon(
          onPressed: () => showShopDialog(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add your first shop'),
        ),
      ),
    );
  }
}
