import 'package:flutter_test/flutter_test.dart';
import 'package:inventra/features/reports/periods.dart';
import 'package:inventra/features/reports/reports.dart';

void main() {
  test('net profit subtracts expenses per currency', () {
    final r = Report(
      range: rangeFor(PeriodKind.thisMonth, now: DateTime(2026, 11, 10)),
      totals: const {'NGN': Totals(count: 3, sales: 100000, cost: 60000)},
      previous: const {},
      days: const [],
      items: const [],
      categories: const [],
      payments: const [],
      stock: const [],
      expenses: const {'NGN': 15000, 'USD': 500},
    );
    expect(r.netProfit(), {'NGN': 25000, 'USD': -500});
    expect(r.isEmpty, isFalse);
  });
}
