import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalogue/items.dart';

/// One line in the cart: an item sold by its base unit or by a pack.
class CartLine {
  const CartLine({
    required this.itemId,
    required this.name,
    required this.unitName,
    required this.unitsPerPack,
    required this.quantity,
    required this.unitPrice,
    required this.availableBase,
    this.unitId,
    this.unitCost,
    this.imagePath,
  });

  final String itemId;
  final String name;

  /// Null = the item's base unit.
  final String? unitId;
  final String unitName;
  final int unitsPerPack;
  final int quantity;

  /// Price of one [unitName], minor units.
  final int unitPrice;

  /// Cost of one [unitName], minor units (null if the item has no cost price).
  final int? unitCost;

  /// Stock of the item in base units when it was added.
  final int availableBase;
  final String? imagePath;

  String get key => '$itemId|${unitId ?? 'base'}';
  int get lineTotal => quantity * unitPrice;
  int get baseQuantity => quantity * unitsPerPack;

  CartLine copyWith({int? quantity, int? unitPrice}) => CartLine(
        itemId: itemId,
        name: name,
        unitId: unitId,
        unitName: unitName,
        unitsPerPack: unitsPerPack,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        unitCost: unitCost,
        availableBase: availableBase,
        imagePath: imagePath,
      );
}

enum DiscountType { amount, percent }

class Cart {
  const Cart({
    this.shopId,
    this.currency,
    this.lines = const [],
    this.discountType = DiscountType.amount,
    this.discountValue = 0,
    this.customerId,
    this.customerName,
    this.note,
  });

  final String? shopId;
  final String? currency;
  final List<CartLine> lines;
  final DiscountType discountType;

  /// Minor units when [discountType] is amount; whole percent otherwise.
  final int discountValue;
  final String? customerId;
  final String? customerName;
  final String? note;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (n, l) => n + l.quantity);
  int get subtotal => lines.fold(0, (n, l) => n + l.lineTotal);

  int get discount {
    final d = discountType == DiscountType.amount
        ? discountValue
        : (subtotal * discountValue / 100).round();
    return math.min(math.max(d, 0), subtotal);
  }

  int get total => subtotal - discount;

  /// Lines asking for more than the stock on hand when they were added.
  /// Stock for the same item is summed across its units.
  Set<String> get overStockItemIds {
    final wanted = <String, int>{};
    final available = <String, int>{};
    for (final l in lines) {
      wanted[l.itemId] = (wanted[l.itemId] ?? 0) + l.baseQuantity;
      available[l.itemId] = l.availableBase;
    }
    return {
      for (final id in wanted.keys)
        if (wanted[id]! > available[id]!) id,
    };
  }

  Cart copyWith({
    String? shopId,
    String? currency,
    List<CartLine>? lines,
    DiscountType? discountType,
    int? discountValue,
    String? customerId,
    String? customerName,
    bool clearCustomer = false,
    String? note,
  }) =>
      Cart(
        shopId: shopId ?? this.shopId,
        currency: currency ?? this.currency,
        lines: lines ?? this.lines,
        discountType: discountType ?? this.discountType,
        discountValue: discountValue ?? this.discountValue,
        customerId: clearCustomer ? null : (customerId ?? this.customerId),
        customerName: clearCustomer ? null : (customerName ?? this.customerName),
        note: note ?? this.note,
      );
}

class CartNotifier extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

  /// Adds one of [item] (or one [unit] pack). Returns an error message, or null.
  String? add(Item item, {ItemUnit? unit, int quantity = 1}) {
    if (!state.isEmpty && state.shopId != item.shopId) {
      return 'The cart has items from another shop. Finish or clear that sale first.';
    }
    if (!state.isEmpty && state.currency != item.currency) {
      return '${item.name} is priced in ${item.currency}, but this sale is in ${state.currency}. '
          'Finish this sale first.';
    }
    final price = unit?.sellingPrice ?? item.sellingPrice;
    if (price == null) return '${item.name} has no selling price yet.';

    final perPack = unit?.unitsPerPack ?? 1;
    final line = CartLine(
      itemId: item.id,
      name: item.name,
      unitId: unit?.id,
      unitName: unit?.name ?? item.baseUnit,
      unitsPerPack: perPack,
      quantity: quantity,
      unitPrice: price,
      unitCost: item.costPrice == null ? null : item.costPrice! * perPack,
      availableBase: item.quantity,
      imagePath: item.imagePath,
    );

    final lines = [...state.lines];
    final i = lines.indexWhere((l) => l.key == line.key);
    if (i >= 0) {
      lines[i] = lines[i].copyWith(quantity: lines[i].quantity + quantity);
    } else {
      lines.add(line);
    }
    state = state.copyWith(
        shopId: item.shopId, currency: item.currency, lines: lines);
    return null;
  }

  void setQuantity(String key, int quantity) {
    if (quantity <= 0) return remove(key);
    state = state.copyWith(lines: [
      for (final l in state.lines)
        l.key == key ? l.copyWith(quantity: quantity) : l,
    ]);
  }

  void setPrice(String key, int unitPrice) {
    state = state.copyWith(lines: [
      for (final l in state.lines)
        l.key == key ? l.copyWith(unitPrice: unitPrice) : l,
    ]);
  }

  void remove(String key) {
    final lines = state.lines.where((l) => l.key != key).toList();
    state = lines.isEmpty
        ? const Cart()
        : state.copyWith(lines: lines);
  }

  void setDiscount(DiscountType type, int value) {
    state = state.copyWith(discountType: type, discountValue: value);
  }

  void setCustomer(String? id, String? name) {
    state = id == null
        ? state.copyWith(clearCustomer: true)
        : state.copyWith(customerId: id, customerName: name);
  }

  void setNote(String note) => state = state.copyWith(note: note);

  void clear() => state = const Cart();
}

final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);
