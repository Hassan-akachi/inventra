import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';

/// Common expense types; users can also type their own.
const expenseCategories = <String>[
  'Rent',
  'Salaries and wages',
  'Electricity and generator fuel',
  'Transport and delivery',
  'Water and utilities',
  'Phone and internet',
  'Shop supplies and packaging',
  'Repairs and maintenance',
  'Taxes, levies and permits',
  'Bank and POS charges',
  'Marketing',
  'Other',
];

class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.currency,
    required this.spentAt,
    this.shopId,
    this.shopName,
    this.note,
  });

  final String id;
  final String category;
  final int amount;
  final String currency;

  /// `yyyy-MM-dd`, local date the money was spent.
  final String spentAt;

  /// Null = a business-wide expense not tied to one shop.
  final String? shopId;
  final String? shopName;
  final String? note;

  factory Expense.fromRow(Map<String, dynamic> r) => Expense(
        id: r['id'] as String,
        category: (r['category'] as String?) ?? 'Other',
        amount: (r['amount'] as int?) ?? 0,
        currency: (r['currency'] as String?) ?? 'NGN',
        spentAt: (r['spent_at'] as String?) ?? '',
        shopId: r['main_category_id'] as String?,
        shopName: r['shop_name'] as String?,
        note: r['note'] as String?,
      );
}

/// Expenses query: [shopId] null = all shops (including business-wide ones).
/// Dates are `yyyy-MM-dd`, [to] exclusive.
typedef ExpenseQuery = ({String? shopId, String from, String to});

class ExpensesRepository {
  ExpensesRepository(this._db, this._session);
  final PowerSyncDatabase _db;
  final Session _session;

  (String, List<Object?>) _where(ExpenseQuery q) {
    var where = 'e.business_id = ? AND e.deleted_at IS NULL AND e.spent_at >= ? AND e.spent_at < ?';
    final params = <Object?>[_session.businessId, q.from, q.to];
    if (q.shopId != null) {
      // A shop's view includes its own expenses only.
      where += ' AND e.main_category_id = ?';
      params.add(q.shopId);
    }
    return (where, params);
  }

  Stream<List<Expense>> watch(ExpenseQuery q) {
    final (where, params) = _where(q);
    return _db
        .watch(
          'SELECT e.*, m.name AS shop_name FROM expenses e '
          'LEFT JOIN main_categories m ON m.id = e.main_category_id '
          'WHERE $where ORDER BY e.spent_at DESC, e.created_at DESC',
          parameters: params,
        )
        .map((rs) => rs.map(Expense.fromRow).toList());
  }

  /// category -> currency -> total, for reports.
  Future<Map<String, Map<String, int>>> totalsByCategory(ExpenseQuery q) async {
    final (where, params) = _where(q);
    final rows = await _db.getAll(
      'SELECT e.category, e.currency, SUM(e.amount) AS total FROM expenses e '
      'WHERE $where GROUP BY e.category, e.currency ORDER BY total DESC',
      params,
    );
    final out = <String, Map<String, int>>{};
    for (final r in rows) {
      final cat = (r['category'] as String?) ?? 'Other';
      final cur = (r['currency'] as String?) ?? 'NGN';
      out.putIfAbsent(cat, () => {})[cur] = (r['total'] as num?)?.toInt() ?? 0;
    }
    return out;
  }

  /// Categories used before, most used first (for suggestions).
  Future<List<String>> usedCategories() async {
    final rows = await _db.getAll(
      'SELECT category, COUNT(*) AS n FROM expenses WHERE business_id = ? AND deleted_at IS NULL '
      'GROUP BY category ORDER BY n DESC LIMIT 30',
      [_session.businessId],
    );
    return [for (final r in rows) (r['category'] as String?) ?? ''];
  }

  Future<void> save({
    String? id,
    required String? shopId,
    required String category,
    required int amount,
    required String currency,
    required String spentAt,
    String? note,
  }) async {
    final now = nowIso();
    if (id == null) {
      await _db.execute(
        'INSERT INTO expenses (id, business_id, main_category_id, category, amount, currency, note, spent_at, '
        'created_at, updated_at, updated_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [newId(), _session.businessId, shopId, category.trim(), amount, currency, note, spentAt,
         now, now, _session.userId],
      );
    } else {
      await _db.execute(
        'UPDATE expenses SET main_category_id = ?, category = ?, amount = ?, currency = ?, note = ?, '
        'spent_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
        [shopId, category.trim(), amount, currency, note, spentAt, now, _session.userId, id],
      );
    }
  }

  Future<void> delete(String id) async {
    final now = nowIso();
    await _db.execute(
      'UPDATE expenses SET deleted_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
      [now, now, _session.userId, id],
    );
  }
}

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) =>
    ExpensesRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)));

final expensesProvider = StreamProvider.family<List<Expense>, ExpenseQuery>(
    (ref, q) => ref.watch(expensesRepositoryProvider).watch(q));
