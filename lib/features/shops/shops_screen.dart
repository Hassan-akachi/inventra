import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import 'shops.dart';

class ShopsScreen extends ConsumerWidget {
  const ShopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(shopsProvider);
    final currentId = ref.watch(activeShopProvider).valueOrNull?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Shops')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showShopDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add shop'),
      ),
      body: AsyncBody(
        value: shops,
        builder: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.storefront_outlined,
              title: 'No shops yet',
              message: 'Add each place you keep stock, e.g. Shop 1, Home, Shop 2.',
              action: FilledButton.icon(
                onPressed: () => showShopDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add shop'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final shop in list)
                ListTile(
                  leading: CircleAvatar(
                    child: Text(supportedCurrencies[shop.currency] ?? '?'),
                  ),
                  title: Text(shop.name),
                  subtitle: Text([
                    shop.currency,
                    if (shop.isTemporary) 'Temporary',
                    if (shop.archived) 'Archived',
                  ].join(' · ')),
                  selected: shop.id == currentId,
                  trailing: _ShopMenu(shop: shop),
                  onTap: shop.archived
                      ? null
                      : () {
                          ref.read(currentShopIdProvider.notifier).select(shop.id);
                          context.pop();
                        },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ShopMenu extends ConsumerWidget {
  const _ShopMenu({required this.shop});
  final Shop shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(shopsRepositoryProvider);
    return PopupMenuButton<String>(
      onSelected: (action) async {
        switch (action) {
          case 'edit':
            await showShopDialog(context, ref, shop: shop);
          case 'archive':
            await repo.setArchived(shop.id, !shop.archived);
          case 'delete':
            final ok = await confirmDialog(context,
                title: 'Delete ${shop.name}?',
                message: 'This cannot be undone.');
            if (!ok) return;
            final deleted = await repo.delete(shop.id);
            if (!deleted && context.mounted) {
              showMessage(context,
                  'Remove or move this shop\'s items first, or archive the shop.');
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(
            value: 'archive',
            child: Text(shop.archived ? 'Unarchive' : 'Archive')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

/// Add or edit a shop.
Future<void> showShopDialog(BuildContext context, WidgetRef ref,
    {Shop? shop}) async {
  final name = TextEditingController(text: shop?.name ?? '');
  var currency = shop?.currency ?? 'NGN';
  var temporary = shop?.isTemporary ?? false;
  final formKey = GlobalKey<FormState>();

  final saved = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        scrollable: true,
        title: Text(shop == null ? 'New shop' : 'Edit shop'),
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
              const SizedBox(height: 16),
              CurrencyDropdown(
                value: currency,
                onChanged: (v) => setState(() => currency = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Temporary'),
                subtitle: const Text('e.g. a market stall or event'),
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

  if (saved != true) return;
  final repo = ref.read(shopsRepositoryProvider);
  if (shop == null) {
    final id = await repo.create(
        name: name.text, currency: currency, isTemporary: temporary);
    await ref.read(currentShopIdProvider.notifier).select(id);
  } else {
    await repo.update(shop.id,
        name: name.text, currency: currency, isTemporary: temporary);
  }
}
