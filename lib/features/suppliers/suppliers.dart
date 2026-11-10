import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';

class Supplier {
  const Supplier({
    required this.id,
    required this.companyName,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.note,
    this.itemCount = 0,
  });

  final String id;
  final String companyName;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? note;
  final int itemCount;

  factory Supplier.fromRow(Map<String, dynamic> r) => Supplier(
        id: r['id'] as String,
        companyName: (r['company_name'] as String?) ?? '',
        contactName: r['contact_name'] as String?,
        phone: r['phone'] as String?,
        email: r['email'] as String?,
        address: r['address'] as String?,
        note: r['note'] as String?,
        itemCount: (r['item_count'] as int?) ?? 0,
      );
}

/// A supplier linked to an item, with the price they charge.
class ItemSupplier {
  const ItemSupplier({
    required this.linkId,
    required this.supplierId,
    required this.companyName,
    required this.currency,
    this.phone,
    this.supplyPrice,
    this.lastSuppliedAt,
  });

  final String linkId;
  final String supplierId;
  final String companyName;
  final String? phone;
  final int? supplyPrice;
  final String currency;
  final String? lastSuppliedAt;

  factory ItemSupplier.fromRow(Map<String, dynamic> r) => ItemSupplier(
        linkId: r['id'] as String,
        supplierId: (r['supplier_id'] as String?) ?? '',
        companyName: (r['company_name'] as String?) ?? '',
        phone: r['phone'] as String?,
        supplyPrice: r['supply_price'] as int?,
        currency: (r['currency'] as String?) ?? 'NGN',
        lastSuppliedAt: r['last_supplied_at'] as String?,
      );
}

class SuppliersRepository {
  SuppliersRepository(this._db, this._session);

  final PowerSyncDatabase _db;
  final Session _session;

  static const _select =
      'SELECT s.*, (SELECT COUNT(*) FROM item_suppliers l WHERE l.supplier_id = s.id AND l.deleted_at IS NULL) AS item_count '
      'FROM suppliers s';

  Stream<List<Supplier>> watchAll() => _db
      .watch(
        '$_select WHERE s.business_id = ? AND s.deleted_at IS NULL ORDER BY s.company_name COLLATE NOCASE',
        parameters: [_session.businessId],
      )
      .map((rs) => rs.map(Supplier.fromRow).toList());

  Future<Supplier?> getOne(String id) async {
    final row = await _db.getOptional('$_select WHERE s.id = ?', [id]);
    return row == null ? null : Supplier.fromRow(row);
  }

  Future<String> save({
    String? id,
    required String companyName,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? note,
  }) async {
    final now = nowIso();
    final values = [companyName.trim(), contactName, phone, email, address, note];
    if (id == null) {
      final newSupplierId = newId();
      await _db.execute(
        'INSERT INTO suppliers (company_name, contact_name, phone, email, address, note, id, business_id, created_at, updated_at, updated_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [...values, newSupplierId, _session.businessId, now, now, _session.userId],
      );
      return newSupplierId;
    }
    await _db.execute(
      'UPDATE suppliers SET company_name = ?, contact_name = ?, phone = ?, email = ?, address = ?, note = ?, '
      'updated_at = ?, updated_by = ? WHERE id = ?',
      [...values, now, _session.userId, id],
    );
    return id;
  }

  Future<void> delete(String id) async {
    final now = nowIso();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE item_suppliers SET deleted_at = ?, updated_at = ? WHERE supplier_id = ? AND deleted_at IS NULL',
        [now, now, id],
      );
      await tx.execute(
        'UPDATE suppliers SET deleted_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
        [now, now, _session.userId, id],
      );
    });
  }

  Stream<List<ItemSupplier>> watchForItem(String itemId) => _db
      .watch(
        'SELECT l.*, s.company_name, s.phone FROM item_suppliers l '
        'JOIN suppliers s ON s.id = l.supplier_id '
        'WHERE l.item_id = ? AND l.deleted_at IS NULL AND s.deleted_at IS NULL '
        'ORDER BY l.supply_price',
        parameters: [itemId],
      )
      .map((rs) => rs.map(ItemSupplier.fromRow).toList());

  /// Links a supplier to an item, or updates the price if already linked.
  Future<void> link({
    required String itemId,
    required String supplierId,
    required String currency,
    int? supplyPrice,
    String? lastSuppliedAt,
  }) async {
    final now = nowIso();
    await _db.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT id FROM item_suppliers WHERE item_id = ? AND supplier_id = ? AND deleted_at IS NULL',
        [itemId, supplierId],
      );
      if (existing == null) {
        await tx.execute(
          'INSERT INTO item_suppliers (id, business_id, item_id, supplier_id, supply_price, currency, last_supplied_at, created_at, updated_at, updated_by) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [newId(), _session.businessId, itemId, supplierId, supplyPrice, currency, lastSuppliedAt, now, now, _session.userId],
        );
      } else {
        await tx.execute(
          'UPDATE item_suppliers SET supply_price = ?, currency = ?, last_supplied_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
          [supplyPrice, currency, lastSuppliedAt, now, _session.userId, existing['id']],
        );
      }
    });
  }

  Future<void> unlink(String linkId) async {
    final now = nowIso();
    await _db.execute(
      'UPDATE item_suppliers SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, linkId],
    );
  }
}

final suppliersRepositoryProvider = Provider<SuppliersRepository>((ref) =>
    SuppliersRepository(
        ref.watch(databaseProvider), ref.watch(sessionProvider)));

final suppliersProvider = StreamProvider<List<Supplier>>(
    (ref) => ref.watch(suppliersRepositoryProvider).watchAll());

final itemSuppliersProvider =
    StreamProvider.family<List<ItemSupplier>, String>((ref, itemId) =>
        ref.watch(suppliersRepositoryProvider).watchForItem(itemId));
