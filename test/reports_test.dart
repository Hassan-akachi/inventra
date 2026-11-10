import 'package:flutter_test/flutter_test.dart';
import 'package:inventra/features/reports/currency.dart';
import 'package:inventra/features/reports/export.dart';
import 'package:inventra/features/reports/periods.dart';
import 'package:inventra/features/reports/snapshots.dart';
import 'package:inventra/features/settings/settings.dart';

void main() {
  final wed = DateTime(2026, 11, 11, 15, 30); // a Wednesday

  group('periods', () {
    test('this week starts on Monday', () {
      final r = rangeFor(PeriodKind.thisWeek, now: wed);
      expect(r.start, DateTime(2026, 11, 9));
      expect(r.end, DateTime(2026, 11, 16));
    });

    test('previous month is the calendar month before', () {
      final r = rangeFor(PeriodKind.thisMonth, now: DateTime(2026, 3, 15));
      expect(r.previous.start, DateTime(2026, 2, 1));
      expect(r.previous.end, DateTime(2026, 3, 1));
    });

    test('last 30 days includes today and compares with the 30 before', () {
      final r = rangeFor(PeriodKind.last30, now: wed);
      expect(r.days, 30);
      expect(r.previous.days, 30);
      expect(r.previous.end, r.start);
    });

    test('percent change', () {
      expect(percentChange(150, 100), 50);
      expect(percentChange(50, 0), isNull);
    });
  });

  group('snapshot periods', () {
    test('week and month starts', () {
      expect(periodStartFor(AnalyticsPeriod.week, wed), DateTime(2026, 11, 9));
      expect(periodStartFor(AnalyticsPeriod.month, wed), DateTime(2026, 11, 1));
      expect(nextPeriodStart(AnalyticsPeriod.month, DateTime(2026, 12, 1)), DateTime(2027, 1, 1));
    });
  });

  group('rates', () {
    // 1 NGN = 0.0006 USD (≈ ₦1,666.67 per dollar), 1 NGN = 0.0005 GBP (₦2,000 per pound)
    const rates = Rates({'NGN': 1, 'USD': 0.0006, 'GBP': 0.0005}, {}, {});

    test('converts through naira', () {
      expect(rates.convert(166667, 'NGN', 'USD'), 100); // ₦1,666.67 -> $1.00
      expect(rates.convert(100, 'GBP', 'NGN'), 200000); // £1 -> ₦2,000
      expect(rates.convert(100, 'USD', 'USD'), 100);
    });

    test('missing rate gives null', () {
      expect(rates.convert(100, 'EUR', 'NGN'), isNull);
      expect(rates.sumIn({'NGN': 100, 'EUR': 5}, 'NGN'), isNull);
    });

    test('sums mixed currencies', () {
      expect(rates.sumIn({'NGN': 100000, 'GBP': 100}, 'NGN'), 300000);
    });
  });

  test('csv quotes cells with commas and quotes', () {
    final csv = toCsv(['A', 'B'], [
      ['Coke, 50cl', 'say "hi"'],
      [null, 3],
    ]);
    expect(csv, 'A,B\n"Coke, 50cl","say ""hi"""\n,3\n');
  });
}
