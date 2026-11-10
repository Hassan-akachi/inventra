import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../inventory/restocks.dart';
import '../inventory/restocks_screen.dart';
import '../suppliers/suppliers.dart';
import 'item_status.dart';
import 'items.dart';
import '../account/membership.dart';

class ItemDetailScreen extends ConsumerWidget {
  const ItemDetailScreen({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(itemProvider(itemId));
    if (!item.hasValue) {
      return Scaffold(appBar: AppBar(), body: AsyncBody(value: item, builder: (_) => const SizedBox()));
    }
    return AsyncBody(
      value: item,
      builder: (item) {
        if (item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.search_off, title: 'This item was deleted'),
          );
        }
        return _ItemDetail(item: item);
      },
    );
  }
}

class _ItemDetail extends ConsumerWidget {
  const _ItemDetail({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final units = ref.watch(itemUnitsProvider(item.id)).valueOrNull ?? const [];
    final suppliers =
        ref.watch(itemSuppliersProvider(item.id)).valueOrNull ?? const [];
    final prices = ref.watch(priceHistoryProvider(item.id)).valueOrNull ?? const [];
    final moves =
        ref.watch(stockMovementsProvider(item.id)).valueOrNull ?? const [];
    final restocks =
        ref.watch(itemRestocksProvider(item.id)).valueOrNull ?? const [];
    final cur = item.currency;
    final perms = ref.watch(permissionsProvider);
    final expiryDays = daysToExpiry(item.expiryDate);
    final margin = (item.sellingPrice != null && item.costPrice != null)
        ? item.sellingPrice! - item.costPrice!
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (perms.canEditItems)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/item/${item.id}/edit'),
          ),
          if (perms.isOwner)
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                final ok = await confirmDialog(context,
                    title: 'Delete ${item.name}?',
                    message: 'Its sales history will be kept.');
                if (!ok) return;
                await ref.read(itemsRepositoryProvider).delete(item.id);
                if (context.mounted) context.pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete item')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ItemThumb(imagePath: item.imagePath, size: 96),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusChip(item.status),
                      const SizedBox(height: 8),
                      Text(Money.format(item.sellingPrice, cur),
                          style: theme.textTheme.headlineSmall),
                      Text('${item.quantity} ${item.baseUnit} in stock',
                          style: theme.textTheme.titleMedium),
                      if (expiryDays != null && expiryDays <= 30)
                        Text(
                          expiryDays < 0
                              ? 'Expired ${-expiryDays} days ago'
                              : 'Expires in $expiryDays days',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (perms.canAdjustStock)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push('/restock?item=${item.id}'),
                    icon: const Icon(Icons.move_to_inbox_outlined),
                    label: const Text('Receive'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => showAdjustStockDialog(context, ref, item),
                    icon: const Icon(Icons.swap_vert),
                    label: const Text('Adjust'),
                  ),
                ),
              ],
            ),
          ),

          SectionCard(
            title: 'Details',
            children: [
              InfoRow('Category', item.categoryName ?? '—'),
              InfoRow('Barcode', item.barcode ?? '—'),
              InfoRow('Size', item.size ?? '—'),
              if (perms.canSeeCosts)
                InfoRow('Cost price', Money.format(item.costPrice, cur)),
              InfoRow('Selling price', Money.format(item.sellingPrice, cur)),
              if (margin != null && perms.canSeeCosts)
                InfoRow('Profit per ${item.baseUnit}', Money.format(margin, cur)),
              InfoRow('Low-stock at', '${item.lowStockLevel} ${item.baseUnit}'),
              InfoRow('Expiry date', formatDate(item.expiryDate)),
              InfoRow('Added', formatDate(item.createdAt)),
              if (item.description != null) InfoRow('Description', item.description!),
              if (item.note != null) InfoRow('Note', item.note!),
            ],
          ),

          if (units.isNotEmpty)
            SectionCard(
              title: 'Packs and bulk prices',
              children: [
                for (final u in units)
                  ListTile(
                    dense: true,
                    title: Text('${u.name} (${u.unitsPerPack} ${item.baseUnit})'),
                    subtitle: u.barcode == null ? null : Text('Barcode ${u.barcode}'),
                    trailing: Text(Money.format(u.sellingPrice, cur),
                        style: theme.textTheme.titleSmall),
                  ),
              ],
            ),

          SectionCard(
            title: 'Suppliers',
            trailing: TextButton.icon(
              onPressed: () => showLinkSupplierDialog(context, ref, item),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
            children: [
              if (suppliers.isEmpty)
                const ListTile(dense: true, title: Text('No supplier linked')),
              for (final s in suppliers)
                ListTile(
                  dense: true,
                  title: Text(s.companyName),
                  subtitle: Text([
                    if (s.phone != null) s.phone!,
                    if (s.lastSuppliedAt != null)
                      'Last supplied ${formatDate(s.lastSuppliedAt)}',
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(Money.format(s.supplyPrice, s.currency)),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.link_off, size: 20),
                        onPressed: () => ref
                            .read(suppliersRepositoryProvider)
                            .unlink(s.linkId),
                      ),
                    ],
                  ),
                  onTap: () => context.push('/supplier/${s.supplierId}'),
                ),
            ],
          ),

          if (restocks.isNotEmpty && perms.canSeeCosts)
            SectionCard(
              title: 'Deliveries received',
              children: [
                for (final r in restocks.take(10)) RestockTile(restock: r),
              ],
            ),

          SectionCard(
            title: 'Price history',
            children: [
              if (prices.isEmpty)
                const ListTile(dense: true, title: Text('No price changes yet')),
              for (final p in prices
                  .where((p) => perms.canSeeCosts || p.priceType != 'cost')
                  .take(20))
                ListTile(
                  dense: true,
                  title: Text(
                      '${p.priceType == 'cost' ? 'Cost' : 'Selling'} price'
                      '${p.unitName == null ? '' : ' · ${p.unitName}'}'),
                  subtitle: Text(formatDateTime(p.changedAt)),
                  trailing: Text(
                      '${Money.format(p.oldPrice, cur)} → ${Money.format(p.newPrice, cur)}'),
                ),
            ],
          ),

          SectionCard(
            title: 'Stock movements',
            children: [
              if (moves.isEmpty)
                const ListTile(dense: true, title: Text('No stock recorded yet')),
              for (final m in moves.take(30))
                ListTile(
                  dense: true,
                  title: Text(reasonLabel(m.reason)),
                  subtitle: Text([
                    formatDateTime(m.createdAt),
                    if (m.note != null) m.note!,
                  ].join(' · ')),
                  trailing: Text(
                    '${m.change > 0 ? '+' : ''}${m.change}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: m.change < 0
                          ? theme.colorScheme.error
                          : const Color(0xFF2E7D32),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showAdjustStockDialog(
    BuildContext context, WidgetRef ref, Item item) async {
  var reason = StockReason.correction;
  final qty = TextEditingController();
  final note = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final saved = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final signed = reason.sign == 0;
        return AlertDialog(
          scrollable: true,
          title: const Text('Adjust stock'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Now: ${item.quantity} ${item.baseUnit}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<StockReason>(
                  value: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items: [
                    for (final r in StockReason.values)
                      DropdownMenuItem(
                        value: r,
                        child: Text(
                            '${r.label}${r.sign > 0 ? ' (+)' : r.sign < 0 ? ' (−)' : ' (±)'}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => reason = v ?? reason),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: qty,
                  autofocus: true,
                  keyboardType:
                      TextInputType.numberWithOptions(signed: signed),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        signed ? RegExp(r'^-?\d*') : RegExp(r'^\d*')),
                  ],
                  decoration: InputDecoration(
                    labelText: signed
                        ? 'Change (e.g. -3 or 5)'
                        : 'Quantity (${item.baseUnit})',
                  ),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n == 0) return 'Enter a number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
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
        );
      },
    ),
  );

  if (saved != true) return;
  final n = int.parse(qty.text.trim());
  final change = reason.sign == 0 ? n : n.abs() * reason.sign;
  await ref.read(itemsRepositoryProvider).adjustStock(
        item: item,
        change: change,
        reason: reason.name,
        note: emptyToNull(note.text),
      );
}

Future<void> showLinkSupplierDialog(
    BuildContext context, WidgetRef ref, Item item) async {
  final all = await ref.read(suppliersProvider.future);
  if (!context.mounted) return;
  if (all.isEmpty) {
    final add = await confirmDialog(context,
        title: 'No suppliers yet',
        message: 'Add a supplier first, then link it to this item.',
        action: 'Add supplier');
    if (add && context.mounted) context.push('/supplier/new');
    return;
  }

  String supplierId = all.first.id;
  var currency = item.currency;
  final price = TextEditingController(text: Money.toInput(item.costPrice));
  DateTime? lastSupplied;
  final formKey = GlobalKey<FormState>();

  final saved = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        scrollable: true,
        title: const Text('Link supplier'),
        content: Form(
          key: formKey,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: supplierId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Supplier'),
                  items: [
                    for (final s in all)
                      DropdownMenuItem(value: s.id, child: Text(s.companyName)),
                  ],
                  onChanged: (v) => setState(() => supplierId = v ?? supplierId),
                ),
                const SizedBox(height: 12),
                CurrencyDropdown(
                  value: currency,
                  onChanged: (v) => setState(() => currency = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Their price per ${item.baseUnit}',
                    prefixText: '${supportedCurrencies[currency] ?? ''} ',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date acquired'),
                  subtitle: Text(lastSupplied == null
                      ? 'Not set'
                      : formatDate(dateOnly(lastSupplied!))),
                  trailing: const Icon(Icons.event_outlined),
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: c,
                      initialDate: lastSupplied ?? now,
                      firstDate: DateTime(now.year - 10),
                      lastDate: now,
                    );
                    if (d != null) setState(() => lastSupplied = d);
                  },
                ),
              ],
            ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  if (saved != true) return;
  await ref.read(suppliersRepositoryProvider).link(
        itemId: item.id,
        supplierId: supplierId,
        currency: currency,
        supplyPrice: Money.parse(price.text),
        lastSuppliedAt: lastSupplied == null ? null : dateOnly(lastSupplied!),
      );
}
