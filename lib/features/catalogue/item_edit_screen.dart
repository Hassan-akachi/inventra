import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/session.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../settings/settings.dart';
import '../shops/shops.dart';
import 'categories.dart';
import 'categories_screen.dart';
import 'items.dart';

/// Add a new item ([itemId] null) or edit an existing one.
class ItemEditScreen extends ConsumerStatefulWidget {
  const ItemEditScreen({super.key, this.itemId, this.barcode});

  final String? itemId;

  /// Pre-filled when the user scanned an unknown barcode.
  final String? barcode;

  @override
  ConsumerState<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _UnitRow {
  _UnitRow({this.id, String name = '', String perPack = '', String price = '', String barcode = ''})
      : name = TextEditingController(text: name),
        perPack = TextEditingController(text: perPack),
        price = TextEditingController(text: price),
        barcode = TextEditingController(text: barcode);

  final String? id;
  final TextEditingController name;
  final TextEditingController perPack;
  final TextEditingController price;
  final TextEditingController barcode;

  void dispose() {
    name.dispose();
    perPack.dispose();
    price.dispose();
    barcode.dispose();
  }
}

class _ItemEditScreenState extends ConsumerState<ItemEditScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _description = TextEditingController();
  final _baseUnit = TextEditingController(text: 'piece');
  final _size = TextEditingController();
  final _cost = TextEditingController();
  final _selling = TextEditingController();
  final _lowStock = TextEditingController();
  final _opening = TextEditingController(text: '0');
  final _note = TextEditingController();
  final List<_UnitRow> _units = [];

  String? _shopId;
  String? _categoryId;
  String _currency = 'NGN';
  DateTime? _expiry;
  bool _discontinued = false;
  String? _imagePath;
  bool _loading = true;
  bool _saving = false;

  bool get _isNew => widget.itemId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_isNew) {
      final shop = ref.read(activeShopProvider).valueOrNull;
      _shopId = shop?.id;
      _currency = shop?.currency ?? 'NGN';
      _barcode.text = widget.barcode ?? '';
      _lowStock.text = '${ref.read(settingsProvider).lowStockDefault}';
    } else {
      final repo = ref.read(itemsRepositoryProvider);
      final item = await repo.getOne(widget.itemId!);
      final units = await repo.getUnits(widget.itemId!);
      if (item != null) {
        _shopId = item.shopId;
        _categoryId = item.categoryId;
        _name.text = item.name;
        _barcode.text = item.barcode ?? '';
        _description.text = item.description ?? '';
        _baseUnit.text = item.baseUnit;
        _size.text = item.size ?? '';
        _cost.text = Money.toInput(item.costPrice);
        _selling.text = Money.toInput(item.sellingPrice);
        _lowStock.text = '${item.lowStockLevel}';
        _note.text = item.note ?? '';
        _currency = item.currency;
        _expiry = item.expiryDate == null ? null : DateTime.tryParse(item.expiryDate!);
        _discontinued = item.discontinued;
        _imagePath = item.imagePath;
        for (final u in units) {
          _units.add(_UnitRow(
            id: u.id,
            name: u.name,
            perPack: '${u.unitsPerPack}',
            price: Money.toInput(u.sellingPrice),
            barcode: u.barcode ?? '',
          ));
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [
      _name, _barcode, _description, _baseUnit, _size, _cost, _selling,
      _lowStock, _opening, _note,
    ]) {
      c.dispose();
    }
    for (final u in _units) {
      u.dispose();
    }
    super.dispose();
  }

  Future<void> _scanInto(TextEditingController controller) async {
    final code = await context.push<String>('/scan');
    if (code != null && mounted) setState(() => controller.text = code);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 75, // keeps photos small for later cloud sync
    );
    if (picked == null) return;
    final session = ref.read(sessionProvider);
    final fileName = '${newId()}.jpg';
    await File(picked.path).copy(session.imageFile(fileName));
    if (mounted) setState(() => _imagePath = fileName);
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now.add(const Duration(days: 180)),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
      helpText: 'Expiry date',
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _newCategory() async {
    final shopId = _shopId;
    if (shopId == null) return;
    final id = await showCategoryDialog(context, ref, shopId: shopId);
    if (id != null && mounted) setState(() => _categoryId = id);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final shopId = _shopId;
    if (shopId == null) {
      showMessage(context, 'Add a shop first.');
      return;
    }
    setState(() => _saving = true);

    final draft = ItemDraft(
      id: widget.itemId,
      shopId: shopId,
      categoryId: _categoryId,
      name: _name.text,
      barcode: emptyToNull(_barcode.text),
      description: emptyToNull(_description.text),
      baseUnit: emptyToNull(_baseUnit.text) ?? 'piece',
      currency: _currency,
      costPrice: Money.parse(_cost.text),
      sellingPrice: Money.parse(_selling.text),
      lowStockLevel: parseInt(_lowStock.text) ?? 0,
      size: emptyToNull(_size.text),
      discontinued: _discontinued,
      expiryDate: _expiry == null ? null : dateOnly(_expiry!),
      imagePath: _imagePath,
      note: emptyToNull(_note.text),
      openingStock: _isNew ? (parseInt(_opening.text) ?? 0) : 0,
      units: [
        for (final u in _units)
          UnitDraft(
            id: u.id,
            name: u.name.text,
            unitsPerPack: parseInt(u.perPack.text) ?? 1,
            sellingPrice: Money.parse(u.price.text),
            barcode: emptyToNull(u.barcode.text),
          ),
      ],
    );

    try {
      final id = await ref.read(itemsRepositoryProvider).save(draft);
      if (!mounted) return;
      if (_isNew) {
        context.pushReplacement('/item/$id');
      } else {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not save: $e');
      }
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _money(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return Money.parse(v) == null ? 'Enter an amount' : null;
  }

  String? _wholeNumber(String? v, {bool allowNegative = false}) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    if (n == null || (!allowNegative && n < 0)) return 'Enter a whole number';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final shopId = _shopId;
    final categories = shopId == null
        ? const <ItemCategory>[]
        : (ref.watch(categoriesForShopProvider(shopId)).valueOrNull ?? const [])
            .where((c) => !c.archived || c.id == _categoryId)
            .toList();
    final symbol = supportedCurrencies[_currency] ?? '';
    final moneyKeyboard = const TextInputType.numberWithOptions(decimal: true);
    final digitsOnly = [FilteringTextInputFormatter.digitsOnly];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New item' : 'Edit item'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            // Photo
            Row(
              children: [
                ItemThumb(imagePath: _imagePath, size: 88),
                const SizedBox(width: 16),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Camera'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'),
                      ),
                      if (_imagePath != null)
                        TextButton(
                          onPressed: () => setState(() => _imagePath = null),
                          child: const Text('Remove photo'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Item name *'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _barcode,
              decoration: InputDecoration(
                labelText: 'Barcode',
                suffixIcon: IconButton(
                  tooltip: 'Scan',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () => _scanInto(_barcode),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: categories.any((c) => c.id == _categoryId)
                        ? _categoryId
                        : null,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('No category')),
                      for (final c in categories)
                        DropdownMenuItem<String?>(
                            value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
                IconButton(
                  tooltip: 'New category',
                  icon: const Icon(Icons.add),
                  onPressed: _newCategory,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),

            _sectionTitle(context, 'Prices'),
            CurrencyDropdown(
              value: _currency,
              onChanged: (v) => setState(() => _currency = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cost,
                    keyboardType: moneyKeyboard,
                    decoration: InputDecoration(
                        labelText: 'Cost price', prefixText: '$symbol '),
                    validator: _money,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _selling,
                    keyboardType: moneyKeyboard,
                    decoration: InputDecoration(
                        labelText: 'Selling price *', prefixText: '$symbol '),
                    validator: (v) => _required(v) ?? _money(v),
                  ),
                ),
              ],
            ),

            _sectionTitle(context, 'Stock'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _baseUnit,
                    decoration: const InputDecoration(
                      labelText: 'Sold by',
                      helperText: 'e.g. piece, bottle, sachet',
                    ),
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _size,
                    decoration: const InputDecoration(
                      labelText: 'Size',
                      helperText: 'e.g. 50cl, 500mg',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_isNew) ...[
                  Expanded(
                    child: TextFormField(
                      controller: _opening,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      decoration: const InputDecoration(
                          labelText: 'Quantity in stock now'),
                      validator: _wholeNumber,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: TextFormField(
                    controller: _lowStock,
                    keyboardType: TextInputType.number,
                    inputFormatters: digitsOnly,
                    decoration: const InputDecoration(
                        labelText: 'Low-stock warning at'),
                    validator: _wholeNumber,
                  ),
                ),
              ],
            ),
            if (!_isNew)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'To change the quantity, use "Adjust stock" on the item page so every change is recorded.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Expiry date'),
              subtitle: Text(_expiry == null
                  ? 'None'
                  : formatDate(dateOnly(_expiry!))),
              trailing: _expiry == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _expiry = null),
                    ),
              onTap: _pickExpiry,
            ),
            if (!_isNew)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Discontinued'),
                subtitle: const Text('No longer sold or restocked'),
                value: _discontinued,
                onChanged: (v) => setState(() => _discontinued = v),
              ),

            _sectionTitle(context, 'Packs and bulk prices'),
            Text(
              'Add bigger units this item is sold in, with their own price. '
              'Selling one deducts the right number of ${emptyToNull(_baseUnit.text) ?? 'pieces'}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (var i = 0; i < _units.length; i++) _unitCard(i, symbol),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _units.add(_UnitRow())),
                icon: const Icon(Icons.add),
                label: const Text('Add pack size'),
              ),
            ),

            _sectionTitle(context, 'Note'),
            TextFormField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_isNew ? 'Add item' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unitCard(int index, String symbol) {
    final u = _units[index];
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: u.name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Name', hintText: 'Pack, Dozen, Carton'),
                    validator: _required,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() {
                    _units.removeAt(index).dispose();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: u.perPack,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                          labelText:
                              'How many ${emptyToNull(_baseUnit.text) ?? 'pieces'}'),
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        return (n == null || n < 2) ? 'At least 2' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: u.price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Price', prefixText: '$symbol '),
                      validator: (v) => _required(v) ?? _money(v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextFormField(
                controller: u.barcode,
                decoration: InputDecoration(
                  labelText: 'Pack barcode (optional)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () => _scanInto(u.barcode),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 12),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
