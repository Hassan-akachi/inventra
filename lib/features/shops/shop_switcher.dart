import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../account/membership.dart';
import 'shops.dart';

/// App bar title showing the current shop; tap to switch.
class ShopSwitcher extends ConsumerWidget {
  const ShopSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(activeShopProvider).valueOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _open(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(shop?.name ?? 'Inventra',
                  overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final shops = ref.read(visibleShopsProvider).valueOrNull ?? const <Shop>[];
    final canManage = ref.read(permissionsProvider).canManageShops;
    final currentId = ref.read(activeShopProvider).valueOrNull?.id;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in shops.where((s) => !s.archived))
              ListTile(
                leading: Icon(s.id == currentId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(s.name),
                subtitle: Text(s.currency),
                onTap: () {
                  ref.read(currentShopIdProvider.notifier).select(s.id);
                  Navigator.pop(sheet);
                },
              ),
            if (canManage) const Divider(),
            if (canManage)
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Manage shops'),
              onTap: () {
                Navigator.pop(sheet);
                context.push('/shops');
              },
            ),
          ],
        ),
      ),
    );
  }
}
