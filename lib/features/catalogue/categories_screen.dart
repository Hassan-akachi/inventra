import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';
import 'categories.dart';
import '../account/membership.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(activeShopProvider).valueOrNull;
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Categories')),
        body: const EmptyState(
          icon: Icons.storefront_outlined,
          title: 'Add a shop first',
          message: 'Categories belong to a shop. Add one under More → Shops.',
        ),
      );
    }
    final cats = ref.watch(categoriesForShopProvider(shop.id));

    return Scaffold(
      appBar: AppBar(title: const ShopSwitcher()),
      floatingActionButton: !ref.watch(permissionsProvider).canEditItems
          ? null
          : FloatingActionButton.extended(
        onPressed: () => showCategoryDialog(context, ref, shopId: shop.id),
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
      body: AsyncBody(
        value: cats,
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.category_outlined,
              title: 'No categories yet',
              message: 'Group items, e.g. Drinks, Drugs, Supplements, Goods.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final c in list)
                ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: Text(c.name),
                  subtitle: Text([
                    '${c.itemCount} item${c.itemCount == 1 ? '' : 's'}',
                    if (c.isTemporary) 'Temporary',
                    if (c.archived) 'Archived',
                  ].join(' · ')),
                  trailing: ref.watch(permissionsProvider).canEditItems
                      ? _CategoryMenu(category: c)
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryMenu extends ConsumerWidget {
  const _CategoryMenu({required this.category});
  final ItemCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(categoriesRepositoryProvider);
    return PopupMenuButton<String>(
      onSelected: (action) async {
        switch (action) {
          case 'edit':
            await showCategoryDialog(context, ref,
                shopId: category.shopId, category: category);
          case 'archive':
            await repo.setArchived(category.id, !category.archived);
          case 'delete':
            final ok = await confirmDialog(
              context,
              title: 'Delete ${category.name}?',
              message: category.itemCount == 0
                  ? 'This cannot be undone.'
                  : 'Its ${category.itemCount} items will stay, without a category.',
            );
            if (ok) await repo.delete(category.id);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(
            value: 'archive',
            child: Text(category.archived ? 'Unarchive' : 'Archive')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

/// Add or edit a category. Returns the id of the created or edited category.
Future<String?> showCategoryDialog(BuildContext context, WidgetRef ref,
    {required String shopId, ItemCategory? category}) async {
  final name = TextEditingController(text: category?.name ?? '');
  var temporary = category?.isTemporary ?? false;
  final formKey = GlobalKey<FormState>();

  final saved = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        scrollable: true,
        title: Text(category == null ? 'New category' : 'Edit category'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Temporary'),
                subtitle: const Text('Archive or delete it when done'),
                value: temporary,
                onChanged: (v) => setState(() => temporary = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  if (saved != true) return null;
  final repo = ref.read(categoriesRepositoryProvider);
  if (category == null) {
    return repo.create(shopId, name.text, isTemporary: temporary);
  }
  await repo.update(category.id, name.text, isTemporary: temporary);
  return category.id;
}
