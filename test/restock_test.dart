import 'package:flutter_test/flutter_test.dart';
import 'package:inventra/features/inventory/restocks.dart';

void main() {
  RestockDraft draft({int perPack = 1, int qty = 2, int? cost}) => RestockDraft(
        shopId: 's',
        itemId: 'i',
        currency: 'NGN',
        unitName: perPack == 1 ? 'bottle' : 'carton',
        unitsPerPack: perPack,
        quantity: qty,
        costPerUnit: cost,
        receivedAt: '2026-11-09',
      );

  test('cartons are converted to base units', () {
    final d = draft(perPack: 12, qty: 3, cost: 300000);
    expect(d.baseQuantity, 36);
    expect(d.totalCost, 900000);
    expect(d.costPerBase, 25000);
  });

  test('cost per base rounds to the nearest minor unit', () {
    expect(draft(perPack: 3, cost: 1000).costPerBase, 333);
  });

  test('no cost entered means no cost updates', () {
    final d = draft();
    expect(d.costPerBase, isNull);
    expect(d.totalCost, isNull);
  });
}
