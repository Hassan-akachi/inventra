import 'package:flutter_test/flutter_test.dart';
import 'package:inventra/core/utils.dart';
import 'package:inventra/features/catalogue/item_status.dart';

void main() {
  group('Money', () {
    test('parses to minor units', () {
      expect(Money.parse('1,250.50'), 125050);
      expect(Money.parse('₦ 300'), 30000);
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
    });

    test('round-trips through the input format', () {
      expect(Money.toInput(125050), '1250.50');
      expect(Money.parse(Money.toInput(99)), 99);
    });
  });

  group('computeStatus', () {
    final now = DateTime(2026, 11, 9);

    ItemStatus status({
      int qty = 10,
      int low = 5,
      bool discontinued = false,
      String? expiry,
    }) =>
        computeStatus(
          quantity: qty,
          lowStockLevel: low,
          discontinued: discontinued,
          expiryDate: expiry,
          now: now,
        );

    test('available', () => expect(status(), ItemStatus.available));
    test('low at the threshold', () => expect(status(qty: 5), ItemStatus.low));
    test('out at zero or below', () {
      expect(status(qty: 0), ItemStatus.out);
      expect(status(qty: -2), ItemStatus.out);
    });
    test('expired beats out of stock', () {
      expect(status(qty: 0, expiry: '2026-11-08'), ItemStatus.expired);
    });
    test('expiring today is not yet expired', () {
      expect(status(expiry: '2026-11-09'), ItemStatus.available);
    });
    test('discontinued beats everything', () {
      expect(status(qty: 0, expiry: '2020-01-01', discontinued: true),
          ItemStatus.discontinued);
    });
    test('days to expiry', () {
      expect(daysToExpiry('2026-11-19', now: now), 10);
      expect(daysToExpiry(null, now: now), isNull);
    });
  });
}
