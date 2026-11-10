import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';
import 'item_status.dart';

class Item {
  const Item({
    required this.id,
    required this.shopId,
    required this.name,
    required this.currency,
    required this.baseUnit,
    required this.lowStockLevel,
    required this.discontinued,
    required this.quantity,
    this.categoryId,
    this.categoryName,
    this.barcode,
    this.description,
    this.costPrice,
    this.sellingPrice,
    this.size,
    this.expiryDate,
    this.imagePath,
    this.note,
    this.createdAt,
  });

  final String id;
  final String shopId;
  final String? categoryId;
  final String? categoryName;
  final String name;
  final String? barcode;
  final String? description;
  final String baseUnit;
  final String currency;
  final int? costPrice;
  final int? sellingPrice;
  final int lowStockLevel;
  final String? size;
  final bool discontinued;
  final String? expiryDate;
  final String? imagePath;
  final String? note;
  final String? createdAt;

  /// Current stock in base units = sum of all stock movements.
  final int quantity;

  ItemStatus get status => computeStatus(
        quantity: quantity,
        lowStockLevel: lowStockLevel,
        discontinued: discontinued,
        expiryDate: expiryDate,
      );

  factory Item.fromRow(Map<String, dynamic> r) => Item(
        id: r['id'] as String,
        shopId: (r['main_category_id'] as String?) ?? '',
        categoryId: r['item_category_id'] as String?,
        categoryName: r['category_name'] as String?,
        name: (r['name'] as String?) ?? '',
        barcode: r['barcode'] as String?,
        description: r['description'] as String?,
        baseUnit: (r['base_unit'] as String?) ?? 'piece',
        currency: (r['currency'] as String?) ?? 'NGN',
        costPrice: r['cost_price'] as int?,
        sellingPrice: r['selling_price'] as int?,
        lowStockLevel: (r['low_stock_level'] as int?) ?? 0,
        size: r['size'] as String?,
        discontinued: (r['discontinued'] as int? ?? 0) == 1,
        expiryDate: r['expiry_date'] as String?,
        imagePath: r['image_path'] as String?,
        note: r['note'] as String?,
        createdAt: r['created_at'] as String?,
        quantity: (r['quantity'] as num?)?.toInt() ?? 0,
      );
}

/// A bigger selling unit, e.g. Pack = 6 bottles, Dozen = 12.
class ItemUnit {
  const ItemUnit({
    required this.id,
    required this.itemId,
    required this.name,
    required this.unitsPerPack,
    this.sellingPrice,
    this.barcode,
  });

  final String id;
  final String itemId;
  final String name;
  final int unitsPerPack;
  final int? sellingPrice;
  final String? barcode;

  factory ItemUnit.fromRow(Map<String, dynamic> r) => ItemUnit(
        id: r['id'] as String,
        itemId: (r['item_id'] as String?) ?? '',
        name: (r['name'] as String?) ?? '',
        unitsPerPack: (r['units_per_pack'] as int?) ?? 1,
        sellingPrice: r['selling_price'] as int?,
        barcode: r['barcode'] as String?,
      );
}

class PriceChange {
  const PriceChange({
    required this.priceType,
    required this.changedAt,
    this.unitName,
    this.oldPrice,
    this.newPrice,
  });

  final String priceType; // cost | selling
  final String? unitName;
  final int? oldPrice;
  final int? newPrice;
  final String changedAt;

  factory PriceChange.fromRow(Map<String, dynamic> r) => PriceChange(
        priceType: (r['price_type'] as String?) ?? 'selling',
        unitName: r['unit_name'] as String?,
        oldPrice: r['old_price'] as int?,
        newPrice: r['new_price'] as int?,
        changedAt: (r['changed_at'] as String?) ?? '',
      );
}

class StockMovement {
  const StockMovement({
    required this.change,
    required this.reason,
    required this.createdAt,
    this.note,
  });

  final int change;
  final String reason;
  final String? note;
  final String createdAt;

  factory StockMovement.fromRow(Map<String, dynamic> r) => StockMovement(
        change: (r['change'] as int?) ?? 0,
        reason: (r['reason'] as String?) ?? '',
        note: r['note'] as String?,
        createdAt: (r['created_at'] as String?) ?? '',
      );
}

/// Reasons for a manual stock change, with their direction.
enum StockReason {
  returned('Returned by customer', 1),
  damaged('Damaged', -1),
  missing('Missing', -1),
  correction('Count correction', 0);

  const StockReason(this.label, this.sign);
  final String label;

  /// +1 adds, -1 removes, 0 = signed number entered by the user.
  final int sign;
}

String reasonLabel(String reason) => switch (reason) {
      'opening' => 'Opening stock',
      'sale' => 'Sale',
      'void' => 'Sale cancelled',
      'restock' => 'Restock',
      'returned' => 'Returned',
      'damaged' => 'Damaged',
      'missing' => 'Missing',
      'correction' => 'Correction',
      _ => reason,
    };

/// What the edit form hands to the repository.
class ItemDraft {
  ItemDraft({
    this.id,
    required this.shopId,
    this.categoryId,
    required this.name,
    this.barcode,
    this.description,
    required this.baseUnit,
    required this.currency,
    this.costPrice,
    this.sellingPrice,
    required this.lowStockLevel,
    this.size,
    this.discontinued = false,
    this.expiryDate,
    this.imagePath,
    this.note,
    this.openingStock = 0,
    this.units = const [],
  });

  final String? id;
  final String shopId;
  final String? categoryId;
  final String name;
  final String? barcode;
  final String? description;
  final String baseUnit;
  final String currency;
  final int? costPrice;
  final int? sellingPrice;
  final int lowStockLevel;
  final String? size;
  final bool discontinued;
  final String? expiryDate;
  final String? imagePath;
  final String? note;
  final int openingStock;
  final List<UnitDraft> units;
}

class UnitDraft {
  UnitDraft({
    this.id,
    required this.name,
    required this.unitsPerPack,
    this.sellingPrice,
    this.barcode,
  });

  final String? id;
  final String name;
  final int unitsPerPack;
  final int? sellingPrice;
  final String? barcode;
}

class ItemsRepository {
  ItemsRepository(this._db, this._session);

  final PowerSyncDatabase _db;
  final Session _session;

  static const _select =
      'SELECT i.*, c.name AS category_name, '
      'COALESCE((SELECT SUM(m.change) FROM stock_movements m WHERE m.item_id = i.id), 0) AS quantity '
      'FROM items i LEFT JOIN item_categories c ON c.id = i.item_category_id';

  Stream<List<Item>> watchForShop(String shopId) => _db
      .watch(
        '$_select WHERE i.main_category_id = ? AND i.deleted_at IS NULL '
        'ORDER BY i.name COLLATE NOCASE',
        parameters: [shopId],
      )
      .map((rs) => rs.map(Item.fromRow).toList());

  Stream<Item?> watchOne(String id) => _db
      .watch('$_select WHERE i.id = ? AND i.deleted_at IS NULL',
          parameters: [id])
      .map((rs) => rs.isEmpty ? null : Item.fromRow(rs.first));

  Future<Item?> getOne(String id) async {
    final row = await _db.getOptional(
        '$_select WHERE i.id = ? AND i.deleted_at IS NULL', [id]);
    return row == null ? null : Item.fromRow(row);
  }

  Stream<List<ItemUnit>> watchUnits(String itemId) => _db
      .watch(
        'SELECT * FROM item_units WHERE item_id = ? AND deleted_at IS NULL ORDER BY units_per_pack',
        parameters: [itemId],
      )
      .map((rs) => rs.map(ItemUnit.fromRow).toList());

  Future<List<ItemUnit>> getUnits(String itemId) async {
    final rs = await _db.getAll(
      'SELECT * FROM item_units WHERE item_id = ? AND deleted_at IS NULL ORDER BY units_per_pack',
      [itemId],
    );
    return rs.map(ItemUnit.fromRow).toList();
  }

  Stream<List<PriceChange>> watchPriceHistory(String itemId) => _db
      .watch(
        'SELECT h.*, u.name AS unit_name FROM price_history h '
        'LEFT JOIN item_units u ON u.id = h.unit_id '
        'WHERE h.item_id = ? ORDER BY h.changed_at DESC',
        parameters: [itemId],
      )
      .map((rs) => rs.map(PriceChange.fromRow).toList());

  Stream<List<StockMovement>> watchMovements(String itemId) => _db
      .watch(
        'SELECT * FROM stock_movements WHERE item_id = ? ORDER BY created_at DESC LIMIT 100',
        parameters: [itemId],
      )
      .map((rs) => rs.map(StockMovement.fromRow).toList());

  /// Finds an item in a shop by its own barcode or a pack barcode.
  Future<String?> findByBarcode(String shopId, String code) async {
    final row = await _db.getOptional(
      'SELECT i.id FROM items i '
      'LEFT JOIN item_units u ON u.item_id = i.id AND u.deleted_at IS NULL '
      'WHERE i.main_category_id = ? AND i.deleted_at IS NULL AND (i.barcode = ? OR u.barcode = ?) '
      'LIMIT 1',
      [shopId, code, code],
    );
    return row?['id'] as String?;
  }

  /// Matches a scanned code to an item, and to a pack when it is a pack barcode.
  Future<({String itemId, String? unitId})?> matchBarcode(
      String shopId, String code) async {
    final unit = await _db.getOptional(
      'SELECT u.id, u.item_id FROM item_units u JOIN items i ON i.id = u.item_id '
      'WHERE u.barcode = ? AND u.deleted_at IS NULL AND i.deleted_at IS NULL AND i.main_category_id = ? LIMIT 1',
      [code, shopId],
    );
    if (unit != null) {
      return (itemId: unit['item_id'] as String, unitId: unit['id'] as String?);
    }
    final item = await _db.getOptional(
      'SELECT id FROM items WHERE barcode = ? AND deleted_at IS NULL AND main_category_id = ? LIMIT 1',
      [code, shopId],
    );
    if (item == null) return null;
    return (itemId: item['id'] as String, unitId: null);
  }

  /// Creates or updates an item with its units. Logs price changes.
  Future<String> save(ItemDraft d) async {
    final now = nowIso();
    final user = _session.userId;
    final id = d.id ?? newId();

    await _db.writeTransaction((tx) async {
      Future<void> logPrice(
          String? unitId, String type, int? oldPrice, int? newPrice) async {
        if (oldPrice == newPrice) return;
        await tx.execute(
          'INSERT INTO price_history (id, business_id, item_id, unit_id, price_type, old_price, new_price, changed_at, changed_by) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [newId(), _session.businessId, id, unitId, type, oldPrice, newPrice, now, user],
        );
      }

      final fields = [
        d.categoryId,
        d.name.trim(),
        d.barcode,
        d.description,
        d.baseUnit,
        d.currency,
        d.costPrice,
        d.sellingPrice,
        d.lowStockLevel,
        d.size,
        d.discontinued ? 1 : 0,
        d.expiryDate,
        d.imagePath,
        d.note,
      ];

      if (d.id == null) {
        await tx.execute(
          'INSERT INTO items (item_category_id, name, barcode, description, base_unit, currency, cost_price, selling_price, '
          'low_stock_level, size, discontinued, expiry_date, image_path, note, '
          'id, business_id, main_category_id, created_at, updated_at, updated_by) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [...fields, id, _session.businessId, d.shopId, now, now, user],
        );
        if (d.openingStock != 0) {
          await tx.execute(
            'INSERT INTO stock_movements (id, business_id, main_category_id, item_id, change, reason, created_at, created_by) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [newId(), _session.businessId, d.shopId, id, d.openingStock, 'opening', now, user],
          );
        }
      } else {
        final old = await tx.get(
            'SELECT cost_price, selling_price FROM items WHERE id = ?', [id]);
        await tx.execute(
          'UPDATE items SET item_category_id = ?, name = ?, barcode = ?, description = ?, base_unit = ?, currency = ?, '
          'cost_price = ?, selling_price = ?, low_stock_level = ?, size = ?, discontinued = ?, expiry_date = ?, '
          'image_path = ?, note = ?, updated_at = ?, updated_by = ? WHERE id = ?',
          [...fields, now, user, id],
        );
        await logPrice(null, 'cost', old['cost_price'] as int?, d.costPrice);
        await logPrice(
            null, 'selling', old['selling_price'] as int?, d.sellingPrice);
      }

      // Units: remove the ones taken out of the form, update or add the rest.
      final existing = await tx.getAll(
        'SELECT id, selling_price FROM item_units WHERE item_id = ? AND deleted_at IS NULL',
        [id],
      );
      final oldPrices = {
        for (final r in existing) r['id'] as String: r['selling_price'] as int?,
      };
      final kept = d.units.map((u) => u.id).whereType<String>().toSet();
      for (final unitId in oldPrices.keys) {
        if (!kept.contains(unitId)) {
          await tx.execute(
            'UPDATE item_units SET deleted_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
            [now, now, user, unitId],
          );
        }
      }
      for (final u in d.units) {
        if (u.id == null || !oldPrices.containsKey(u.id)) {
          await tx.execute(
            'INSERT INTO item_units (id, business_id, item_id, name, barcode, units_per_pack, selling_price, created_at, updated_at, updated_by) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [newId(), _session.businessId, id, u.name.trim(), u.barcode, u.unitsPerPack, u.sellingPrice, now, now, user],
          );
        } else {
          await tx.execute(
            'UPDATE item_units SET name = ?, barcode = ?, units_per_pack = ?, selling_price = ?, updated_at = ?, updated_by = ? WHERE id = ?',
            [u.name.trim(), u.barcode, u.unitsPerPack, u.sellingPrice, now, user, u.id],
          );
          await logPrice(u.id, 'selling', oldPrices[u.id], u.sellingPrice);
        }
      }
    });
    return id;
  }

  /// Records a manual stock change. [change] is signed, in base units.
  Future<void> adjustStock({
    required Item item,
    required int change,
    required String reason,
    String? note,
  }) async {
    await _db.execute(
      'INSERT INTO stock_movements (id, business_id, main_category_id, item_id, change, reason, note, created_at, created_by) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [newId(), _session.businessId, item.shopId, item.id, change, reason, note, nowIso(), _session.userId],
    );
  }

  /// Saves a physical stock count. [counted] maps item id -> quantity counted
  /// (base units). Writes a correction for each item whose current stock differs.
  /// Returns the number of items corrected.
  Future<int> applyCount(String shopId, Map<String, int> counted) async {
    final now = nowIso();
    var corrected = 0;
    await _db.writeTransaction((tx) async {
      for (final entry in counted.entries) {
        final row = await tx.get(
          'SELECT COALESCE(SUM(change), 0) AS qty FROM stock_movements WHERE item_id = ?',
          [entry.key],
        );
        final current = (row['qty'] as num?)?.toInt() ?? 0;
        final diff = entry.value - current;
        if (diff == 0) continue;
        corrected++;
        await tx.execute(
          'INSERT INTO stock_movements (id, business_id, main_category_id, item_id, change, reason, note, created_at, created_by) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [newId(), _session.businessId, shopId, entry.key, diff, 'correction',
           'Stock count: $current → ${entry.value}', now, _session.userId],
        );
      }
    });
    return corrected;
  }

  Future<void> delete(String id) async {
    final now = nowIso();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE items SET deleted_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
        [now, now, _session.userId, id],
      );
      await tx.execute(
        'UPDATE item_units SET deleted_at = ?, updated_at = ? WHERE item_id = ? AND deleted_at IS NULL',
        [now, now, id],
      );
      await tx.execute(
        'UPDATE item_suppliers SET deleted_at = ?, updated_at = ? WHERE item_id = ? AND deleted_at IS NULL',
        [now, now, id],
      );
    });
  }
}

final itemsRepositoryProvider = Provider<ItemsRepository>((ref) =>
    ItemsRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)));

final itemsForShopProvider = StreamProvider.family<List<Item>, String>(
    (ref, shopId) => ref.watch(itemsRepositoryProvider).watchForShop(shopId));

final itemProvider = StreamProvider.family<Item?, String>(
    (ref, id) => ref.watch(itemsRepositoryProvider).watchOne(id));

final itemUnitsProvider = StreamProvider.family<List<ItemUnit>, String>(
    (ref, id) => ref.watch(itemsRepositoryProvider).watchUnits(id));

final priceHistoryProvider = StreamProvider.family<List<PriceChange>, String>(
    (ref, id) => ref.watch(itemsRepositoryProvider).watchPriceHistory(id));

final stockMovementsProvider =
    StreamProvider.family<List<StockMovement>, String>(
        (ref, id) => ref.watch(itemsRepositoryProvider).watchMovements(id));
