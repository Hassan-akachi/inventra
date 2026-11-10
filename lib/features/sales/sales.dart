import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';
import 'cart.dart';

enum PaymentMethod {
  cash('Cash'),
  transfer('Transfer'),
  pos('POS'),
  other('Other');

  const PaymentMethod(this.label);
  final String label;

  static PaymentMethod parse(String? v) => PaymentMethod.values
      .firstWhere((m) => m.name == v, orElse: () => PaymentMethod.other);
}

enum PaymentStatus {
  paid('Paid'),
  partial('Part-paid'),
  unpaid('Unpaid');

  const PaymentStatus(this.label);
  final String label;

  static PaymentStatus parse(String? v) => PaymentStatus.values
      .firstWhere((s) => s.name == v, orElse: () => PaymentStatus.unpaid);
}

PaymentStatus paymentStatusFor(int total, int paid) {
  if (paid >= total) return PaymentStatus.paid;
  if (paid > 0) return PaymentStatus.partial;
  return PaymentStatus.unpaid;
}

class Sale {
  const Sale({
    required this.id,
    required this.receiptNo,
    required this.shopId,
    required this.currency,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.amountPaid,
    required this.status,
    required this.soldAt,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.shopName,
    this.voidedAt,
    this.note,
    this.itemCount = 0,
  });

  final String id;
  final String receiptNo;
  final String shopId;
  final String? shopName;
  final String currency;
  final int subtotal;
  final int discount;
  final int total;
  final int amountPaid;
  final PaymentStatus status;
  final String soldAt;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? voidedAt;
  final String? note;
  final int itemCount;

  bool get voided => voidedAt != null;
  int get balance => math.max(0, total - amountPaid);

  factory Sale.fromRow(Map<String, dynamic> r) => Sale(
        id: r['id'] as String,
        receiptNo: (r['receipt_no'] as String?) ?? '',
        shopId: (r['main_category_id'] as String?) ?? '',
        shopName: r['shop_name'] as String?,
        currency: (r['currency'] as String?) ?? 'NGN',
        subtotal: (r['subtotal'] as int?) ?? 0,
        discount: (r['discount'] as int?) ?? 0,
        total: (r['total'] as int?) ?? 0,
        amountPaid: (r['amount_paid'] as int?) ?? 0,
        status: PaymentStatus.parse(r['payment_status'] as String?),
        soldAt: (r['sold_at'] as String?) ?? '',
        customerId: r['customer_id'] as String?,
        customerName: r['customer_name'] as String?,
        customerPhone: r['customer_phone'] as String?,
        voidedAt: r['voided_at'] as String?,
        note: r['note'] as String?,
        itemCount: (r['item_count'] as num?)?.toInt() ?? 0,
      );
}

class SaleLine {
  const SaleLine({
    required this.itemId,
    required this.itemName,
    required this.unitName,
    required this.quantity,
    required this.baseQuantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String itemId;
  final String itemName;
  final String unitName;
  final int quantity;
  final int baseQuantity;
  final int unitPrice;
  final int lineTotal;

  factory SaleLine.fromRow(Map<String, dynamic> r) => SaleLine(
        itemId: (r['item_id'] as String?) ?? '',
        itemName: (r['item_name'] as String?) ?? '',
        unitName: (r['unit_name'] as String?) ?? '',
        quantity: (r['quantity'] as int?) ?? 0,
        baseQuantity: (r['base_quantity'] as int?) ?? 0,
        unitPrice: (r['unit_price'] as int?) ?? 0,
        lineTotal: (r['line_total'] as int?) ?? 0,
      );
}

class Payment {
  const Payment({
    required this.amount,
    required this.method,
    required this.paidAt,
  });

  final int amount;
  final PaymentMethod method;
  final String paidAt;

  factory Payment.fromRow(Map<String, dynamic> r) => Payment(
        amount: (r['amount'] as int?) ?? 0,
        method: PaymentMethod.parse(r['method'] as String?),
        paidAt: (r['paid_at'] as String?) ?? '',
      );
}

/// Totals for a period, used on Home and in sales history.
class SalesSummary {
  const SalesSummary({
    this.count = 0,
    this.total = 0,
    this.owed = 0,
    this.cost = 0,
  });

  final int count;
  final int total;
  final int owed;
  final int cost;

  int get profit => total - cost;

  factory SalesSummary.fromRow(Map<String, dynamic> r) => SalesSummary(
        count: (r['n'] as int?) ?? 0,
        total: (r['total'] as num?)?.toInt() ?? 0,
        owed: (r['owed'] as num?)?.toInt() ?? 0,
        cost: (r['cost'] as num?)?.toInt() ?? 0,
      );
}

/// Query key for a list of sales.
typedef SalesQuery = ({String shopId, String fromIso});

class SalesRepository {
  SalesRepository(this._db, this._session);
  final PowerSyncDatabase _db;
  final Session _session;

  static const _select = 'SELECT s.*, c.name AS customer_name, c.phone AS customer_phone, '
      'm.name AS shop_name, '
      '(SELECT COALESCE(SUM(si.quantity), 0) FROM sale_items si WHERE si.sale_id = s.id) AS item_count '
      'FROM sales s '
      'LEFT JOIN customers c ON c.id = s.customer_id '
      'LEFT JOIN main_categories m ON m.id = s.main_category_id';

  /// Completes the sale: writes the sale, its lines, the payment,
  /// and a stock movement per line, all in one transaction.
  Future<String> completeSale(
    Cart cart, {
    required int amountPaid,
    required PaymentMethod method,
  }) async {
    if (cart.isEmpty || cart.shopId == null) {
      throw StateError('The cart is empty');
    }
    final saleId = newId();
    final now = nowIso();
    final user = _session.userId;
    final biz = _session.businessId;
    final total = cart.total;
    final paid = math.min(math.max(amountPaid, 0), total);

    await _db.writeTransaction((tx) async {
      // Receipt number: device code + a counter kept on this phone.
      final seqRow = await tx.getOptional(
          "SELECT value FROM local_settings WHERE id = 'receipt_seq'");
      final seq = int.tryParse((seqRow?['value'] as String?) ?? '') ?? 0;
      final next = seq + 1;
      if (seqRow == null) {
        await tx.execute(
            "INSERT INTO local_settings (id, value) VALUES ('receipt_seq', ?)",
            ['$next']);
      } else {
        await tx.execute(
            "UPDATE local_settings SET value = ? WHERE id = 'receipt_seq'",
            ['$next']);
      }
      final receiptNo =
          'INV-${_session.deviceCode}-${next.toString().padLeft(5, '0')}';

      await tx.execute(
        'INSERT INTO sales (id, business_id, receipt_no, main_category_id, customer_id, currency, subtotal, discount, total, '
        'amount_paid, payment_status, sold_at, sold_by, note, created_at, updated_at, updated_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          saleId, biz, receiptNo, cart.shopId, cart.customerId, cart.currency,
          cart.subtotal, cart.discount, total, paid,
          paymentStatusFor(total, paid).name, now, user, cart.note, now, now, user,
        ],
      );

      for (final l in cart.lines) {
        await tx.execute(
          'INSERT INTO sale_items (id, business_id, sale_id, item_id, item_name, unit_id, unit_name, units_per_pack, '
          'quantity, base_quantity, unit_price, cost_price, line_total) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            newId(), biz, saleId, l.itemId, l.name, l.unitId, l.unitName, l.unitsPerPack,
            l.quantity, l.baseQuantity, l.unitPrice, l.unitCost, l.lineTotal,
          ],
        );
        await tx.execute(
          'INSERT INTO stock_movements (id, business_id, main_category_id, item_id, change, reason, ref_id, created_at, created_by) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [newId(), biz, cart.shopId, l.itemId, -l.baseQuantity, 'sale', saleId, now, user],
        );
      }

      if (paid > 0) {
        await tx.execute(
          'INSERT INTO payments (id, business_id, sale_id, amount, method, paid_at, received_by) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [newId(), biz, saleId, paid, method.name, now, user],
        );
      }
    });
    return saleId;
  }

  /// Records money received later for a part-paid or unpaid sale.
  Future<void> addPayment(String saleId, int amount, PaymentMethod method) async {
    final now = nowIso();
    await _db.writeTransaction((tx) async {
      final sale = await tx.get(
          'SELECT total, amount_paid FROM sales WHERE id = ?', [saleId]);
      final total = (sale['total'] as int?) ?? 0;
      final already = (sale['amount_paid'] as int?) ?? 0;
      final take = math.min(amount, math.max(0, total - already));
      if (take <= 0) return;
      await tx.execute(
        'INSERT INTO payments (id, business_id, sale_id, amount, method, paid_at, received_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [newId(), _session.businessId, saleId, take, method.name, now, _session.userId],
      );
      final newPaid = already + take;
      await tx.execute(
        'UPDATE sales SET amount_paid = ?, payment_status = ?, updated_at = ?, updated_by = ? WHERE id = ?',
        [newPaid, paymentStatusFor(total, newPaid).name, now, _session.userId, saleId],
      );
    });
  }

  /// Cancels a sale and puts its stock back.
  Future<void> voidSale(String saleId) async {
    final now = nowIso();
    final user = _session.userId;
    await _db.writeTransaction((tx) async {
      final sale = await tx.get(
          'SELECT main_category_id, voided_at FROM sales WHERE id = ?', [saleId]);
      if (sale['voided_at'] != null) return;
      final lines = await tx.getAll(
          'SELECT item_id, base_quantity FROM sale_items WHERE sale_id = ?', [saleId]);
      for (final l in lines) {
        await tx.execute(
          'INSERT INTO stock_movements (id, business_id, main_category_id, item_id, change, reason, ref_id, created_at, created_by) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [newId(), _session.businessId, sale['main_category_id'], l['item_id'], l['base_quantity'], 'void', saleId, now, user],
        );
      }
      await tx.execute(
        'UPDATE sales SET voided_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
        [now, now, user, saleId],
      );
    });
  }

  Stream<List<Sale>> watchSales(SalesQuery q) => _db
      .watch(
        '$_select WHERE s.main_category_id = ? AND s.sold_at >= ? AND s.deleted_at IS NULL '
        'ORDER BY s.sold_at DESC LIMIT 500',
        parameters: [q.shopId, q.fromIso],
      )
      .map((rs) => rs.map(Sale.fromRow).toList());

  /// Unvoided sales that still have a balance, oldest first.
  Stream<List<Sale>> watchUnpaid(String shopId) => _db
      .watch(
        '$_select WHERE s.main_category_id = ? AND s.voided_at IS NULL AND s.deleted_at IS NULL '
        'AND s.total > s.amount_paid ORDER BY s.sold_at',
        parameters: [shopId],
      )
      .map((rs) => rs.map(Sale.fromRow).toList());

  Stream<List<Sale>> watchCustomerSales(String customerId) => _db
      .watch(
        '$_select WHERE s.customer_id = ? AND s.deleted_at IS NULL ORDER BY s.sold_at DESC',
        parameters: [customerId],
      )
      .map((rs) => rs.map(Sale.fromRow).toList());

  Stream<Sale?> watchSale(String id) => _db
      .watch('$_select WHERE s.id = ?', parameters: [id])
      .map((rs) => rs.isEmpty ? null : Sale.fromRow(rs.first));

  Future<Sale?> getSale(String id) async {
    final row = await _db.getOptional('$_select WHERE s.id = ?', [id]);
    return row == null ? null : Sale.fromRow(row);
  }

  Stream<List<SaleLine>> watchLines(String saleId) => _db
      .watch('SELECT * FROM sale_items WHERE sale_id = ? ORDER BY item_name',
          parameters: [saleId])
      .map((rs) => rs.map(SaleLine.fromRow).toList());

  Future<List<SaleLine>> getLines(String saleId) async {
    final rs = await _db.getAll(
        'SELECT * FROM sale_items WHERE sale_id = ? ORDER BY item_name', [saleId]);
    return rs.map(SaleLine.fromRow).toList();
  }

  Stream<List<Payment>> watchPayments(String saleId) => _db
      .watch('SELECT * FROM payments WHERE sale_id = ? ORDER BY paid_at',
          parameters: [saleId])
      .map((rs) => rs.map(Payment.fromRow).toList());

  Future<List<Payment>> getPayments(String saleId) async {
    final rs = await _db.getAll(
        'SELECT * FROM payments WHERE sale_id = ? ORDER BY paid_at', [saleId]);
    return rs.map(Payment.fromRow).toList();
  }

  /// Totals of unvoided sales in a shop since [fromIso].
  Stream<SalesSummary> watchSummary(SalesQuery q) => _db
      .watch(
        'SELECT COUNT(*) AS n, COALESCE(SUM(s.total), 0) AS total, '
        'COALESCE(SUM(s.total - s.amount_paid), 0) AS owed, '
        'COALESCE(SUM((SELECT SUM(COALESCE(si.cost_price, 0) * si.quantity) FROM sale_items si WHERE si.sale_id = s.id)), 0) AS cost '
        'FROM sales s WHERE s.main_category_id = ? AND s.sold_at >= ? '
        'AND s.voided_at IS NULL AND s.deleted_at IS NULL',
        parameters: [q.shopId, q.fromIso],
      )
      .map((rs) => rs.isEmpty ? const SalesSummary() : SalesSummary.fromRow(rs.first));
}

/// Start of today (local time) as a UTC ISO string, for `sold_at >= ?`.
String startOfTodayIso() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).toUtc().toIso8601String();
}

String daysAgoIso(int days) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - days).toUtc().toIso8601String();
}

final salesRepositoryProvider = Provider<SalesRepository>((ref) =>
    SalesRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)));

final salesProvider = StreamProvider.family<List<Sale>, SalesQuery>(
    (ref, q) => ref.watch(salesRepositoryProvider).watchSales(q));

final salesSummaryProvider = StreamProvider.family<SalesSummary, SalesQuery>(
    (ref, q) => ref.watch(salesRepositoryProvider).watchSummary(q));

final saleProvider = StreamProvider.family<Sale?, String>(
    (ref, id) => ref.watch(salesRepositoryProvider).watchSale(id));

final saleLinesProvider = StreamProvider.family<List<SaleLine>, String>(
    (ref, id) => ref.watch(salesRepositoryProvider).watchLines(id));

final salePaymentsProvider = StreamProvider.family<List<Payment>, String>(
    (ref, id) => ref.watch(salesRepositoryProvider).watchPayments(id));

final unpaidSalesProvider = StreamProvider.family<List<Sale>, String>(
    (ref, shopId) => ref.watch(salesRepositoryProvider).watchUnpaid(shopId));

final customerSalesProvider = StreamProvider.family<List<Sale>, String>(
    (ref, id) => ref.watch(salesRepositoryProvider).watchCustomerSales(id));
