import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets.dart';
import '../catalogue/categories.dart';
import '../catalogue/items.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';

/// Walk the shelves, type what you count, and save the differences
/// as stock corrections in one go.
class StockCountScreen extends ConsumerStatefulWidget {
  const StockCountScreen({super.key});

  @override
  ConsumerState<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends ConsumerState<StockCountScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, int> _counted = {};
  String _search = '';
  String? _categoryId;
  bool _uncountedOnly = false;
  bool _saving = false;

  TextEditingController _controllerFor(String itemId) =>
      _controllers.putIfAbsent(itemId, () {
        final c = TextEditingController(
            text: _counted.containsKey(itemId) ? '${_counted[itemId]}' : '');
        return c;
      });

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Clears the count, lets the rebuild allow popping, then leaves.
  void _leave() {
    if (!mounted) return;
    setState(_counted.clear);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop();
    });
  }

  Future<bool> _confirmLeave() async {
    if (_counted.isEmpty) return true;
    return confirmDialog(context,
        title: 'Discard this count?',
        message: '${_counted.length} counted items have not been saved.',
        action: 'Discard');
  }

  Future<void> _save(String shopId, List<Item> items) async {
    final byId = {for (final i in items) i.id: i};
    final diffs = _counted.entries
        .where((e) => byId[e.key] != null && byId[e.key]!.quantity != e.value)
        .toList();
    final ok = await confirmDialog(
      context,
      title: 'Save stock count?',
      message: '${_counted.length} items counted. '
          '${diffs.isEmpty ? 'All match the app.' : '${diffs.length} will be corrected to what you counted.'}',
      action: 'Save',
    );
    if (!ok) return;
    setState(() => _saving = true);
    final corrected =
        await ref.read(itemsRepositoryProvider).applyCount(shopId, Map.of(_counted));
    if (!mounted) return;
    showMessage(context,
        corrected == 0 ? 'Count saved: everything matched.' : 'Count saved: $corrected items corrected.');
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(activeShopProvider).valueOrNull;
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock count')),
        body: const EmptyState(icon: Icons.storefront_outlined, title: 'Add a shop first'),
      );
    }
    final items = ref.watch(itemsForShopProvider(shop.id));
    final cats = (ref.watch(categoriesForShopProvider(shop.id)).valueOrNull ?? const [])
        .where((c) => !c.archived)
        .toList();
    final theme = Theme.of(context);

    return PopScope(
      canPop: _counted.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave()) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const ShopSwitcher()),
        body: AsyncBody(
          value: items,
          builder: (all) {
            final active = all.where((i) => !i.discontinued).toList();
            final q = _search.trim().toLowerCase();
            final shown = active.where((i) {
              if (_categoryId != null && i.categoryId != _categoryId) return false;
              if (_uncountedOnly && _counted.containsKey(i.id)) return false;
              return q.isEmpty ||
                  i.name.toLowerCase().contains(q) ||
                  (i.barcode ?? '').contains(q);
            }).toList();
            final diffCount = _counted.entries.where((e) {
              final item = active.where((i) => i.id == e.key).firstOrNull;
              return item != null && item.quantity != e.value;
            }).length;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Find item',
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: const Text('Not counted yet'),
                          selected: _uncountedOnly,
                          onSelected: (v) => setState(() => _uncountedOnly = v),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: const Text('All categories'),
                          selected: _categoryId == null,
                          onSelected: (_) => setState(() => _categoryId = null),
                        ),
                      ),
                      for (final c in cats)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(c.name),
                            selected: _categoryId == c.id,
                            onSelected: (_) => setState(() => _categoryId = c.id),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const EmptyState(icon: Icons.search_off, title: 'No items here')
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final item = shown[i];
                            final counted = _counted[item.id];
                            final diff = counted == null ? null : counted - item.quantity;
                            return ListTile(
                              title: Text(item.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                diff == null
                                    ? 'App says ${item.quantity} ${item.baseUnit}'
                                    : diff == 0
                                        ? 'Matches'
                                        : 'App says ${item.quantity} · ${diff > 0 ? '+' : ''}$diff',
                                style: diff == null || diff == 0
                                    ? null
                                    : TextStyle(color: theme.colorScheme.error),
                              ),
                              trailing: SizedBox(
                                width: 96,
                                child: TextField(
                                  controller: _controllerFor(item.id),
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.end,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: const InputDecoration(hintText: 'Count'),
                                  onChanged: (v) => setState(() {
                                    final n = int.tryParse(v);
                                    if (n == null) {
                                      _counted.remove(item.id);
                                    } else {
                                      _counted[item.id] = n;
                                    }
                                  }),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Material(
                  color: theme.colorScheme.surfaceContainer,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_counted.length} of ${active.length} counted'
                              '${diffCount == 0 ? '' : ' · $diffCount differ'}',
                              maxLines: 2,
                            ),
                          ),
                          FilledButton(
                            onPressed: _counted.isEmpty || _saving
                                ? null
                                : () => _save(shop.id, active),
                            child: const Text('Save count'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
