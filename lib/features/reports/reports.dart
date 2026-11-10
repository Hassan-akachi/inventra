import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';
import 'periods.dart';

/// Totals of unvoided sales in one currency.
class Totals {
  const Totals({
    this.count = 0,
    this.sales = 0,
    this.cost = 0,
    this.discount = 0,
    this.paid = 0,
  });

  final int count;
  final int sales;
  final int cost;
  final int discount;
  final int paid;

  int get profit => sales - cost;
  int get unpaid => sales - paid;
  int get averageSale => count == 0 ? 0 : (sales / count).round();
  double? get marginPercent => sales == 0 ? null : profit / sales * 100;
}

class ItemSales {
  const ItemSales({
    required this.itemId,
    required this.name,
    required this.currency,
    required this.baseUnit,
    required this.quantity,
    required this.revenue,
    required this.cost,
  });

  final String itemId;
  final String name;
  final String currency;
  final String baseUnit;

  /// In base units.
  final int quantity;
  final int revenue;
  final int cost;
  int get profit => revenue - cost;
}

class AmountRow {
  const AmountRow(this.label, this.currency, this.amount, {this.count = 0});
  final String label;
  final String currency;
  final int amount;
  final int count;
}

class DayTotal {
  const DayTotal(this.day, this.byCurrency);
  final DateTime day;
  final Map<String, int> byCurrency;
}

class StockValue {
  const StockValue(this.currency, this.cost, this.retail, this.units, this.items);
  final String currency;
  final int cost;
  final int retail;
  final int units;
  final int items;
}

class Report {
  const Report({
    required this.range,
    required this.totals,
    required this.previous,
    required this.days,
    required this.items,
    required this.categories,
    required this.payments,
    required this.stock,
    this.expenses = const {},
    this.previousExpenses = const {},
    this.expenseCategories = const [],
  });

  final ReportRange range;

  /// currency -> totals for the period.
  final Map<String, Totals> totals;

  /// currency -> totals for the period before (for comparison).
  final Map<String, Totals> previous;
  final List<DayTotal> days;
  final List<ItemSales> items;
  final List<AmountRow> categories;
  final List<AmountRow> payments;
  final List<StockValue> stock;

  /// currency -> money spent on expenses in the period.
  final Map<String, int> expenses;
  final Map<String, int> previousExpenses;
  final List<AmountRow> expenseCategories;

  bool get isEmpty => totals.isEmpty && expenses.isEmpty;

  /// Profit after expenses, per currency.
  Map<String, int> netProfit({bool prev = false}) {
    final t = prev ? previous : totals;
    final e = prev ? previousExpenses : expenses;
    return {
      for (final c in {...t.keys, ...e.keys}) c: (t[c]?.profit ?? 0) - (e[c] ?? 0),
    };
  }
  Map<String, int> map(int Function(Totals t) f, {bool prev = false}) =>
      {for (final e in (prev ? previous : totals).entries) e.key: f(e.value)};
}

/// shopId null = all shops the user can see.
typedef ReportQuery = ({String? shopId, ReportRange range});

class ReportsRepository {
  ReportsRepository(this._db, this._session);
  final PowerSyncDatabase _db;
  final Session _session;

  /// Builds a filter on sales `s` for a shop and date range.
  (String, List<Object?>) _filter(String? shopId, ReportRange r, {String dateCol = 's.sold_at'}) {
    final where = StringBuffer(
        's.business_id = ? AND s.voided_at IS NULL AND s.deleted_at IS NULL AND $dateCol >= ? AND $dateCol < ?');
    final params = <Object?>[_session.businessId, r.fromIso, r.toIso];
    if (shopId != null) {
      where.write(' AND s.main_category_id = ?');
      params.add(shopId);
    }
    return (where.toString(), params);
  }

  Future<Map<String, Totals>> totals(String? shopId, ReportRange r) async {
    final (where, params) = _filter(shopId, r);
    final rows = await _db.getAll(
      'SELECT s.currency, COUNT(*) AS n, COALESCE(SUM(s.total), 0) AS total, '
      'COALESCE(SUM(s.discount), 0) AS discount, COALESCE(SUM(s.amount_paid), 0) AS paid, '
      'COALESCE(SUM((SELECT SUM(COALESCE(si.cost_price, 0) * si.quantity) FROM sale_items si WHERE si.sale_id = s.id)), 0) AS cost '
      'FROM sales s WHERE $where GROUP BY s.currency',
      params,
    );
    return {
      for (final r in rows)
        (r['currency'] as String?) ?? 'NGN': Totals(
          count: (r['n'] as int?) ?? 0,
          sales: (r['total'] as num?)?.toInt() ?? 0,
          cost: (r['cost'] as num?)?.toInt() ?? 0,
          discount: (r['discount'] as num?)?.toInt() ?? 0,
          paid: (r['paid'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  /// Expenses in a range (by spent date), per currency. A shop view counts
  /// that shop's expenses; "all shops" also counts business-wide ones.
  Future<Map<String, int>> expenseTotals(String? shopId, ReportRange r) async {
    final rows = await _db.getAll(
      'SELECT currency, SUM(amount) AS total FROM expenses '
      'WHERE business_id = ? AND deleted_at IS NULL AND spent_at >= ? AND spent_at < ? '
      '${shopId == null ? '' : 'AND main_category_id = ? '}GROUP BY currency',
      [_session.businessId, dateOnly(r.start), dateOnly(r.end), if (shopId != null) shopId],
    );
    return {
      for (final x in rows) (x['currency'] as String?) ?? 'NGN': (x['total'] as num?)?.toInt() ?? 0,
    };
  }

  Future<Report> build(ReportQuery q) async {
    final r = q.range;
    final shopId = q.shopId;
    final (where, params) = _filter(shopId, r);

    // Daily totals, grouped by local date in Dart (stored times are UTC).
    final saleRows = await _db.getAll(
        'SELECT s.sold_at, s.total, s.currency FROM sales s WHERE $where', params);
    final byDay = <DateTime, Map<String, int>>{};
    for (var d = r.start; d.isBefore(r.end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (byDay.length > 400) break;
      byDay[d] = {};
    }
    for (final row in saleRows) {
      final t = DateTime.tryParse((row['sold_at'] as String?) ?? '')?.toLocal();
      if (t == null) continue;
      final key = DateTime(t.year, t.month, t.day);
      final m = byDay.putIfAbsent(key, () => {});
      final c = (row['currency'] as String?) ?? 'NGN';
      m[c] = (m[c] ?? 0) + ((row['total'] as int?) ?? 0);
    }
    final days = (byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => DayTotal(e.key, e.value))
        .toList();

    final itemRows = await _db.getAll(
      'SELECT si.item_id, MAX(si.item_name) AS name, s.currency, MAX(i.base_unit) AS base_unit, '
      'SUM(si.base_quantity) AS qty, SUM(si.line_total) AS revenue, '
      'SUM(COALESCE(si.cost_price, 0) * si.quantity) AS cost '
      'FROM sale_items si JOIN sales s ON s.id = si.sale_id '
      'LEFT JOIN items i ON i.id = si.item_id '
      'WHERE $where GROUP BY si.item_id, s.currency ORDER BY revenue DESC LIMIT 100',
      params,
    );
    final items = [
      for (final x in itemRows)
        ItemSales(
          itemId: (x['item_id'] as String?) ?? '',
          name: (x['name'] as String?) ?? '',
          currency: (x['currency'] as String?) ?? 'NGN',
          baseUnit: (x['base_unit'] as String?) ?? 'pcs',
          quantity: (x['qty'] as num?)?.toInt() ?? 0,
          revenue: (x['revenue'] as num?)?.toInt() ?? 0,
          cost: (x['cost'] as num?)?.toInt() ?? 0,
        ),
    ];

    final catRows = await _db.getAll(
      "SELECT COALESCE(c.name, 'No category') AS name, s.currency, SUM(si.line_total) AS revenue, "
      'SUM(si.base_quantity) AS qty '
      'FROM sale_items si JOIN sales s ON s.id = si.sale_id '
      'LEFT JOIN items i ON i.id = si.item_id '
      'LEFT JOIN item_categories c ON c.id = i.item_category_id '
      'WHERE $where GROUP BY 1, s.currency ORDER BY revenue DESC',
      params,
    );
    final categories = [
      for (final x in catRows)
        AmountRow((x['name'] as String?) ?? '', (x['currency'] as String?) ?? 'NGN',
            (x['revenue'] as num?)?.toInt() ?? 0,
            count: (x['qty'] as num?)?.toInt() ?? 0),
    ];

    final (pWhere, pParams) = _filter(shopId, r, dateCol: 'p.paid_at');
    final payRows = await _db.getAll(
      'SELECT p.method, s.currency, SUM(p.amount) AS amount, COUNT(*) AS n '
      'FROM payments p JOIN sales s ON s.id = p.sale_id '
      'WHERE $pWhere GROUP BY p.method, s.currency ORDER BY amount DESC',
      pParams,
    );
    final payments = [
      for (final x in payRows)
        AmountRow((x['method'] as String?) ?? 'other', (x['currency'] as String?) ?? 'NGN',
            (x['amount'] as num?)?.toInt() ?? 0,
            count: (x['n'] as int?) ?? 0),
    ];

    final stockParams = <Object?>[_session.businessId];
    var stockWhere = 'i.business_id = ? AND i.deleted_at IS NULL';
    if (shopId != null) {
      stockWhere += ' AND i.main_category_id = ?';
      stockParams.add(shopId);
    }
    final stockRows = await _db.getAll(
      'SELECT currency, SUM(CASE WHEN q > 0 THEN q * COALESCE(cost_price, 0) ELSE 0 END) AS cost, '
      'SUM(CASE WHEN q > 0 THEN q * COALESCE(selling_price, 0) ELSE 0 END) AS retail, '
      'SUM(CASE WHEN q > 0 THEN q ELSE 0 END) AS units, COUNT(*) AS n FROM ('
      'SELECT i.currency, i.cost_price, i.selling_price, '
      'COALESCE((SELECT SUM(m.change) FROM stock_movements m WHERE m.item_id = i.id), 0) AS q '
      'FROM items i WHERE $stockWhere) GROUP BY currency',
      stockParams,
    );
    final stock = [
      for (final x in stockRows)
        StockValue((x['currency'] as String?) ?? 'NGN', (x['cost'] as num?)?.toInt() ?? 0,
            (x['retail'] as num?)?.toInt() ?? 0, (x['units'] as num?)?.toInt() ?? 0,
            (x['n'] as int?) ?? 0),
    ];

    final expenseRows = await _db.getAll(
      'SELECT category, currency, SUM(amount) AS total, COUNT(*) AS n FROM expenses '
      'WHERE business_id = ? AND deleted_at IS NULL AND spent_at >= ? AND spent_at < ? '
      '${shopId == null ? '' : 'AND main_category_id = ? '}GROUP BY category, currency ORDER BY total DESC',
      [_session.businessId, dateOnly(r.start), dateOnly(r.end), if (shopId != null) shopId],
    );

    return Report(
      range: r,
      expenses: await expenseTotals(shopId, r),
      previousExpenses: await expenseTotals(shopId, r.previous),
      expenseCategories: [
        for (final x in expenseRows)
          AmountRow((x['category'] as String?) ?? 'Other', (x['currency'] as String?) ?? 'NGN',
              (x['total'] as num?)?.toInt() ?? 0,
              count: (x['n'] as int?) ?? 0),
      ],
      totals: await totals(shopId, r),
      previous: await totals(shopId, r.previous),
      days: days,
      items: items,
      categories: categories,
      payments: payments,
      stock: stock,
    );
  }

  /// Fires whenever sales or payments change, so reports refresh.
  Stream<int> watchChanges() => _db
      .watch('SELECT (SELECT COUNT(*) FROM sales) + (SELECT COUNT(*) FROM payments) '
          '+ (SELECT COUNT(*) FROM stock_movements) '
          "+ (SELECT COUNT(*) FROM expenses) + (SELECT COUNT(*) FROM expenses WHERE deleted_at IS NOT NULL) "
          "+ (SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE deleted_at IS NULL) AS n")
      .map((rs) => (rs.first['n'] as int?) ?? 0);
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) =>
    ReportsRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)));

final _changesProvider = StreamProvider<int>(
    (ref) => ref.watch(reportsRepositoryProvider).watchChanges());

final reportProvider = FutureProvider.autoDispose.family<Report, ReportQuery>((ref, q) {
  ref.watch(_changesProvider); // recompute when data changes
  return ref.watch(reportsRepositoryProvider).build(q);
});
