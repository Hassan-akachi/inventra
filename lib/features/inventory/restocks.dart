import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';

/// Goods received into a shop.
class Restock {
  const Restock({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.unitName,
    required this.quantity,
    required this.baseQuantity,
    required this.costPrice,
    required this.totalCost,
    required this.currency,
    required this.receivedAt,
    this.supplierId,
    this.supplierName,
    this.expiryDate,
    this.note,
  });

  final String id;
  final String itemId;
  final String itemName;
  final String unitName;
  final int quantity;
  final int baseQuantity;
  final int? costPrice;
  final int? totalCost;
  final String currency;
  final String receivedAt;
  final String? supplierId;
  final String? supplierName;
  final String? expiryDate;
  final String? note;

  factory Restock.fromRow(Map<String, dynamic> r) => Restock(
        id: r['id'] as String,
        itemId: (r['item_id'] as String?) ?? '',
        itemName: (r['item_name'] as String?) ?? '',
        unitName: (r['unit_name'] as String?) ?? '',
        quantity: (r['quantity'] as int?) ?? 0,
        baseQuantity: (r['base_quantity'] as int?) ?? 0,
        costPrice: r['cost_price'] as int?,
        totalCost: r['total_cost'] as int?,
        currency: (r['currency'] as String?) ?? 'NGN',
        receivedAt: (r['received_at'] as String?) ?? '',
        supplierId: r['supplier_id'] as String?,
        supplierName: r['supplier_name'] as String?,
        expiryDate: r['expiry_date'] as String?,
        note: r['note'] as String?,
      );
}

/// What the restock form hands to the repository.
class RestockDraft {
  RestockDraft({
    required this.shopId,
    required this.itemId,
    required this.currency,
    required this.unitName,
    required this.unitsPerPack,
    required this.quantity,
    required this.receivedAt,
    this.unitId,
    this.costPerUnit,
    this.supplierId,
    this.expiryDate,
    this.note,
    this.updateItemCost = true,
    this.updateItemExpiry = true,
  });

  final String shopId;
  final String itemId;
  final String currency;
  final String? unitId;
  final String unitName;
  final int unitsPerPack;
  final int quantity;

  /// Cost of one [unitName], minor units.
  final int? costPerUnit;
  final String? supplierId;
  final String? expiryDate;

  /// `yyyy-MM-dd`.
  final String receivedAt;
  final String? note;
  final bool updateItemCost;
  final bool updateItemExpiry;

  int get baseQuantity => quantity * unitsPerPack;
  int? get totalCost => costPerUnit == null ? null : costPerUnit! * quantity;

  /// Cost of one base unit, rounded to the nearest minor unit.
  int? get costPerBase =>
      costPerUnit == null ? null : (costPerUnit! / unitsPerPack).round();
}

class RestocksRepository {
  RestocksRepository(this._db, this._session);
  final PowerSyncDatabase _db;
  final Session _session;

  static const _select = 'SELECT r.*, i.name AS item_name, s.company_name AS supplier_name '
      'FROM restocks r '
      'LEFT JOIN items i ON i.id = r.item_id '
      'LEFT JOIN suppliers s ON s.id = r.supplier_id';

  /// Records goods received: restock row, stock movement, and optional
  /// updates to the item's cost and expiry and the supplier's price.
  Future<String> record(RestockDraft d) async {
    final id = newId();
    final now = nowIso();
    final user = _session.userId;
    final biz = _session.businessId;

    await _db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO restocks (id, business_id, main_category_id, supplier_id, item_id, unit_id, unit_name, units_per_pack, '
        'quantity, base_quantity, cost_price, total_cost, currency, expiry_date, received_at, note, created_at, updated_at, updated_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id, biz, d.shopId, d.supplierId, d.itemId, d.unitId, d.unitName, d.unitsPerPack,
          d.quantity, d.baseQuantity, d.costPerUnit, d.totalCost, d.currency, d.expiryDate,
          d.receivedAt, d.note, now, now, user,
        ],
      );

      await tx.execute(
        'INSERT INTO stock_movements (id, business_id, main_category_id, item_id, change, reason, ref_id, note, created_at, created_by) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [newId(), biz, d.shopId, d.itemId, d.baseQuantity, 'restock', id, d.note, now, user],
      );

      final item = await tx.get(
          'SELECT cost_price, expiry_date FROM items WHERE id = ?', [d.itemId]);

      final newCost = d.costPerBase;
      final oldCost = item['cost_price'] as int?;
      if (d.updateItemCost && newCost != null && newCost != oldCost) {
        await tx.execute(
          'UPDATE items SET cost_price = ?, updated_at = ?, updated_by = ? WHERE id = ?',
          [newCost, now, user, d.itemId],
        );
        await tx.execute(
          'INSERT INTO price_history (id, business_id, item_id, price_type, old_price, new_price, changed_at, changed_by) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [newId(), biz, d.itemId, 'cost', oldCost, newCost, now, user],
        );
      }

      if (d.updateItemExpiry && d.expiryDate != null) {
        await tx.execute(
          'UPDATE items SET expiry_date = ?, updated_at = ?, updated_by = ? WHERE id = ?',
          [d.expiryDate, now, user, d.itemId],
        );
      }

      final supplierId = d.supplierId;
      if (supplierId != null) {
        final link = await tx.getOptional(
          'SELECT id FROM item_suppliers WHERE item_id = ? AND supplier_id = ? AND deleted_at IS NULL',
          [d.itemId, supplierId],
        );
        if (link == null) {
          await tx.execute(
            'INSERT INTO item_suppliers (id, business_id, item_id, supplier_id, supply_price, currency, last_supplied_at, created_at, updated_at, updated_by) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [newId(), biz, d.itemId, supplierId, newCost, d.currency, d.receivedAt, now, now, user],
          );
        } else {
          await tx.execute(
            'UPDATE item_suppliers SET supply_price = COALESCE(?, supply_price), currency = ?, last_supplied_at = ?, '
            'updated_at = ?, updated_by = ? WHERE id = ?',
            [newCost, d.currency, d.receivedAt, now, user, link['id']],
          );
        }
      }
    });
    return id;
  }

  Stream<List<Restock>> watchForShop(String shopId) => _db
      .watch(
        '$_select WHERE r.main_category_id = ? AND r.deleted_at IS NULL '
        'ORDER BY r.received_at DESC, r.created_at DESC LIMIT 300',
        parameters: [shopId],
      )
      .map((rs) => rs.map(Restock.fromRow).toList());

  Stream<List<Restock>> watchForItem(String itemId) => _db
      .watch(
        '$_select WHERE r.item_id = ? AND r.deleted_at IS NULL '
        'ORDER BY r.received_at DESC, r.created_at DESC LIMIT 50',
        parameters: [itemId],
      )
      .map((rs) => rs.map(Restock.fromRow).toList());

  Stream<List<Restock>> watchForSupplier(String supplierId) => _db
      .watch(
        '$_select WHERE r.supplier_id = ? AND r.deleted_at IS NULL '
        'ORDER BY r.received_at DESC, r.created_at DESC LIMIT 100',
        parameters: [supplierId],
      )
      .map((rs) => rs.map(Restock.fromRow).toList());
}

final restocksRepositoryProvider = Provider<RestocksRepository>((ref) =>
    RestocksRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)));

final shopRestocksProvider = StreamProvider.family<List<Restock>, String>(
    (ref, shopId) => ref.watch(restocksRepositoryProvider).watchForShop(shopId));

final itemRestocksProvider = StreamProvider.family<List<Restock>, String>(
    (ref, itemId) => ref.watch(restocksRepositoryProvider).watchForItem(itemId));

final supplierRestocksProvider = StreamProvider.family<List<Restock>, String>(
    (ref, id) => ref.watch(restocksRepositoryProvider).watchForSupplier(id));
