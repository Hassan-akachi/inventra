import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.note,
    this.saleCount = 0,
    this.balance = 0,
    this.balanceCurrency = 'NGN',
    this.balanceCurrencyCount = 0,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? note;
  final int saleCount;

  /// Amount still owed across all unvoided sales (minor units).
  /// Shown in each sale's own currency; mixed-currency balances are rare.
  final int balance;
  final String balanceCurrency;
  final int balanceCurrencyCount;

  /// e.g. "₦12,000.00", or "several currencies" when debts are mixed.
  String get balanceLabel => balanceCurrencyCount > 1
      ? 'several currencies'
      : Money.format(balance, balanceCurrency);

  factory Customer.fromRow(Map<String, dynamic> r) => Customer(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        phone: r['phone'] as String?,
        email: r['email'] as String?,
        address: r['address'] as String?,
        note: r['note'] as String?,
        saleCount: (r['sale_count'] as int?) ?? 0,
        balance: (r['balance'] as num?)?.toInt() ?? 0,
        balanceCurrency: (r['balance_currency'] as String?) ?? 'NGN',
        balanceCurrencyCount: (r['balance_currency_count'] as int?) ?? 0,
      );
}

class CustomersRepository {
  CustomersRepository(this._db, this._session);
  final PowerSyncDatabase _db;
  final Session _session;

  static const _select = 'SELECT c.*, '
      '(SELECT COUNT(*) FROM sales s WHERE s.customer_id = c.id AND s.voided_at IS NULL AND s.deleted_at IS NULL) AS sale_count, '
      '(SELECT COALESCE(SUM(s.total - s.amount_paid), 0) FROM sales s WHERE s.customer_id = c.id AND s.voided_at IS NULL AND s.deleted_at IS NULL) AS balance, '
      '(SELECT MIN(s.currency) FROM sales s WHERE s.customer_id = c.id AND s.voided_at IS NULL AND s.deleted_at IS NULL AND s.total > s.amount_paid) AS balance_currency, '
      '(SELECT COUNT(DISTINCT s.currency) FROM sales s WHERE s.customer_id = c.id AND s.voided_at IS NULL AND s.deleted_at IS NULL AND s.total > s.amount_paid) AS balance_currency_count '
      'FROM customers c';

  Stream<List<Customer>> watchAll() => _db
      .watch(
        '$_select WHERE c.business_id = ? AND c.deleted_at IS NULL ORDER BY c.name COLLATE NOCASE',
        parameters: [_session.businessId],
      )
      .map((rs) => rs.map(Customer.fromRow).toList());

  Stream<Customer?> watchOne(String id) => _db
      .watch('$_select WHERE c.id = ? AND c.deleted_at IS NULL', parameters: [id])
      .map((rs) => rs.isEmpty ? null : Customer.fromRow(rs.first));

  Future<Customer?> getOne(String id) async {
    final row = await _db.getOptional('$_select WHERE c.id = ?', [id]);
    return row == null ? null : Customer.fromRow(row);
  }

  Future<String> save({
    String? id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? note,
  }) async {
    final now = nowIso();
    final values = [name.trim(), phone, email, address, note];
    if (id == null) {
      final newCustomerId = newId();
      await _db.execute(
        'INSERT INTO customers (name, phone, email, address, note, id, business_id, created_at, updated_at, updated_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [...values, newCustomerId, _session.businessId, now, now, _session.userId],
      );
      return newCustomerId;
    }
    await _db.execute(
      'UPDATE customers SET name = ?, phone = ?, email = ?, address = ?, note = ?, updated_at = ?, updated_by = ? WHERE id = ?',
      [...values, now, _session.userId, id],
    );
    return id;
  }

  /// Soft delete. Past sales keep their link for history.
  Future<void> delete(String id) async {
    final now = nowIso();
    await _db.execute(
      'UPDATE customers SET deleted_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
      [now, now, _session.userId, id],
    );
  }
}

final customersRepositoryProvider = Provider<CustomersRepository>((ref) =>
    CustomersRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)));

final customersProvider = StreamProvider<List<Customer>>(
    (ref) => ref.watch(customersRepositoryProvider).watchAll());

final customerProvider = StreamProvider.family<Customer?, String>(
    (ref, id) => ref.watch(customersRepositoryProvider).watchOne(id));
