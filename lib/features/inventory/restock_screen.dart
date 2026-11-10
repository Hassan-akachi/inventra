import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../catalogue/items.dart';
import '../shops/shops.dart';
import '../suppliers/suppliers.dart';
import 'restocks.dart';

/// Record goods received from a supplier.
class RestockScreen extends ConsumerStatefulWidget {
  const RestockScreen({super.key, this.itemId});
  final String? itemId;

  @override
  ConsumerState<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends ConsumerState<RestockScreen> {
  final _form = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  final _note = TextEditingController();

  Item? _item;
  List<ItemUnit> _units = const [];
  ItemUnit? _unit; // null = base unit
  String? _supplierId;
  DateTime _received = DateTime.now();
  DateTime? _expiry;
  bool _updateCost = true;
  bool _updateExpiry = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final id = widget.itemId;
    if (id != null) {
      Future.microtask(() => _selectItem(id));
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _selectItem(String itemId) async {
    setState(() => _loading = true);
    final repo = ref.read(itemsRepositoryProvider);
    final item = await repo.getOne(itemId);
    final units = await repo.getUnits(itemId);
    final links = await ref.read(itemSuppliersProvider(itemId).future);
    if (!mounted) return;
    setState(() {
      _item = item;
      _units = units;
      _unit = null;
      _cost.text = Money.toInput(item?.costPrice);
      _supplierId = links.isEmpty ? null : links.first.supplierId;
      _loading = false;
    });
  }

  void _selectUnit(ItemUnit? unit) {
    final item = _item;
    setState(() {
      _unit = unit;
      final perPack = unit?.unitsPerPack ?? 1;
      if (item?.costPrice != null) {
        _cost.text = Money.toInput(item!.costPrice! * perPack);
      }
    });
  }

  Future<void> _pickItem() async {
    final shop = ref.read(activeShopProvider).valueOrNull;
    if (shop == null) return;
    final items = await ref.read(itemsForShopProvider(shop.id).future);
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Item>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemPicker(items: items),
    );
    if (chosen != null) await _selectItem(chosen.id);
  }

  Future<void> _pickDate({required bool expiry}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: expiry ? (_expiry ?? now.add(const Duration(days: 180))) : _received,
      firstDate: expiry ? DateTime(now.year - 1) : DateTime(now.year - 5),
      lastDate: expiry ? DateTime(now.year + 20) : now,
      helpText: expiry ? 'Expiry date of this batch' : 'Date received',
    );
    if (picked == null) return;
    setState(() {
      if (expiry) {
        _expiry = picked;
      } else {
        _received = picked;
      }
    });
  }

  Future<void> _save() async {
    final item = _item;
    if (item == null) {
      showMessage(context, 'Choose an item first.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(restocksRepositoryProvider).record(RestockDraft(
            shopId: item.shopId,
            itemId: item.id,
            currency: item.currency,
            unitId: _unit?.id,
            unitName: _unit?.name ?? item.baseUnit,
            unitsPerPack: _unit?.unitsPerPack ?? 1,
            quantity: int.parse(_qty.text.trim()),
            costPerUnit: Money.parse(_cost.text),
            supplierId: _supplierId,
            expiryDate: _expiry == null ? null : dateOnly(_expiry!),
            receivedAt: dateOnly(_received),
            note: emptyToNull(_note.text),
            updateItemCost: _updateCost,
            updateItemExpiry: _updateExpiry,
          ));
      if (!mounted) return;
      showMessage(context, 'Stock received');
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not save: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suppliers = ref.watch(suppliersProvider).valueOrNull ?? const <Supplier>[];
    final item = _item;
    final symbol = supportedCurrencies[item?.currency] ?? '';
    final perPack = _unit?.unitsPerPack ?? 1;
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    final cost = Money.parse(_cost.text);
    final baseName = item?.baseUnit ?? 'pieces';

    return Scaffold(
      appBar: AppBar(title: const Text('Receive stock')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                children: [
                  Card(
                    child: ListTile(
                      leading: ItemThumb(imagePath: item?.imagePath),
                      title: Text(item?.name ?? 'Choose item'),
                      subtitle: item == null
                          ? null
                          : Text('${item.quantity} ${item.baseUnit} in stock now'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: widget.itemId == null ? _pickItem : null,
                    ),
                  ),
                  if (item != null) ...[
                    const SizedBox(height: 16),
                    if (_units.isNotEmpty) ...[
                      Text('Received as', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(item.baseUnit),
                            selected: _unit == null,
                            onSelected: (_) => _selectUnit(null),
                          ),
                          for (final u in _units)
                            ChoiceChip(
                              label: Text('${u.name} (${u.unitsPerPack})'),
                              selected: _unit?.id == u.id,
                              onSelected: (_) => _selectUnit(u),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _qty,
                            autofocus: widget.itemId != null,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: 'Quantity (${_unit?.name ?? item.baseUnit})',
                              helperText: perPack > 1 && qty > 0
                                  ? '= ${qty * perPack} $baseName'
                                  : null,
                            ),
                            validator: (v) {
                              final n = int.tryParse(v?.trim() ?? '');
                              return (n == null || n <= 0) ? 'Enter a quantity' : null;
                            },
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _cost,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Cost per ${_unit?.name ?? item.baseUnit}',
                              prefixText: '$symbol ',
                              helperText: cost != null && qty > 0
                                  ? 'Total ${Money.format(cost * qty, item.currency)}'
                                  : null,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      value: suppliers.any((s) => s.id == _supplierId) ? _supplierId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('No supplier')),
                        for (final s in suppliers)
                          DropdownMenuItem<String?>(
                              value: s.id, child: Text(s.companyName)),
                      ],
                      onChanged: (v) => setState(() => _supplierId = v),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.today_outlined),
                      title: const Text('Date received'),
                      subtitle: Text(formatDate(dateOnly(_received))),
                      onTap: () => _pickDate(expiry: false),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Expiry date of this batch'),
                      subtitle: Text(_expiry == null ? 'None' : formatDate(dateOnly(_expiry!))),
                      trailing: _expiry == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _expiry = null),
                            ),
                      onTap: () => _pickDate(expiry: true),
                    ),
                    if (cost != null && item.costPrice != (cost / perPack).round())
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            'Update cost price to ${Money.format((cost / perPack).round(), item.currency)} per ${item.baseUnit}'),
                        subtitle: Text('Now ${Money.format(item.costPrice, item.currency)}'),
                        value: _updateCost,
                        onChanged: (v) => setState(() => _updateCost = v),
                      ),
                    if (_expiry != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Use this as the item's expiry date"),
                        subtitle: Text(
                            'Now ${formatDate(item.expiryDate)}. Expiry alerts use the item\'s date.'),
                        value: _updateExpiry,
                        onChanged: (v) => setState(() => _updateExpiry = v),
                      ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _note,
                      decoration: const InputDecoration(
                          labelText: 'Note (optional)', hintText: 'e.g. invoice number'),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.move_to_inbox_outlined),
                      label: const Text('Add to stock'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.items});
  final List<Item> items;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final shown = widget.items
        .where((i) =>
            q.isEmpty || i.name.toLowerCase().contains(q) || (i.barcode ?? '').contains(q))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Search items'),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final i in shown)
                    ListTile(
                      leading: ItemThumb(imagePath: i.imagePath, size: 40),
                      title: Text(i.name),
                      subtitle: Text('${i.quantity} ${i.baseUnit} in stock'),
                      onTap: () => Navigator.pop(context, i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
