import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventra/features/catalogue/items.dart';
import 'package:inventra/features/sales/cart.dart';
import 'package:inventra/features/sales/sales.dart';

Item _item({
  String id = 'coke',
  String shopId = 'shop1',
  String currency = 'NGN',
  int price = 30000,
  int cost = 25000,
  int qty = 24,
}) =>
    Item(
      id: id,
      shopId: shopId,
      name: id,
      currency: currency,
      baseUnit: 'bottle',
      lowStockLevel: 5,
      discontinued: false,
      quantity: qty,
      sellingPrice: price,
      costPrice: cost,
    );

const _pack = ItemUnit(
    id: 'pack', itemId: 'coke', name: 'Pack', unitsPerPack: 6, sellingPrice: 170000);

void main() {
  late ProviderContainer container;
  late CartNotifier cart;

  setUp(() {
    container = ProviderContainer();
    cart = container.read(cartProvider.notifier);
  });
  tearDown(() => container.dispose());

  Cart state() => container.read(cartProvider);

  test('adding the same item twice increases quantity', () {
    cart.add(_item());
    cart.add(_item());
    expect(state().lines.length, 1);
    expect(state().lines.first.quantity, 2);
    expect(state().subtotal, 60000);
  });

  test('packs are separate lines and deduct base units', () {
    cart.add(_item());
    cart.add(_item(), unit: _pack);
    expect(state().lines.length, 2);
    final packLine = state().lines.firstWhere((l) => l.unitId == 'pack');
    expect(packLine.baseQuantity, 6);
    expect(packLine.unitCost, 25000 * 6);
    expect(state().subtotal, 30000 + 170000);
  });

  test('discounts never exceed the subtotal', () {
    cart.add(_item());
    cart.setDiscount(DiscountType.percent, 10);
    expect(state().total, 27000);
    cart.setDiscount(DiscountType.amount, 999999);
    expect(state().total, 0);
  });

  test('rejects mixing currencies or shops', () {
    cart.add(_item());
    expect(cart.add(_item(id: 'x', currency: 'USD')), isNotNull);
    expect(cart.add(_item(id: 'y', shopId: 'shop2')), isNotNull);
    expect(state().lines.length, 1);
  });

  test('flags lines over the stock on hand', () {
    cart.add(_item(qty: 5), unit: _pack);
    expect(state().overStockItemIds, {'coke'});
  });

  test('payment status', () {
    expect(paymentStatusFor(1000, 1000), PaymentStatus.paid);
    expect(paymentStatusFor(1000, 400), PaymentStatus.partial);
    expect(paymentStatusFor(1000, 0), PaymentStatus.unpaid);
  });
}
