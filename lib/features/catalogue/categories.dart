import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';

/// A group of items inside a shop, e.g. Drinks, Drugs, Supplements, Goods.
class ItemCategory {
  const ItemCategory({
    required this.id,
    required this.shopId,
    required this.name,
    required this.isTemporary,
    this.archivedAt,
    this.itemCount = 0,
  });

  final String id;
  final String shopId;
  final String name;
  final bool isTemporary;
  final String? archivedAt;
  final int itemCount;

  bool get archived => archivedAt != null;

  factory ItemCategory.fromRow(Map<String, dynamic> r) => ItemCategory(
        id: r['id'] as String,
        shopId: (r['main_category_id'] as String?) ?? '',
        name: (r['name'] as String?) ?? '',
        isTemporary: (r['is_temporary'] as int? ?? 0) == 1,
        archivedAt: r['archived_at'] as String?,
        itemCount: (r['item_count'] as int?) ?? 0,
      );
}

class CategoriesRepository {
  CategoriesRepository(this._db, this._session);

  final PowerSyncDatabase _db;
  final Session _session;

  Stream<List<ItemCategory>> watchForShop(String shopId) => _db
      .watch(
        'SELECT c.*, (SELECT COUNT(*) FROM items i WHERE i.item_category_id = c.id AND i.deleted_at IS NULL) AS item_count '
        'FROM item_categories c WHERE c.main_category_id = ? AND c.deleted_at IS NULL '
        'ORDER BY c.name COLLATE NOCASE',
        parameters: [shopId],
      )
      .map((rs) => rs.map(ItemCategory.fromRow).toList());

  Future<String> create(String shopId, String name,
      {bool isTemporary = false}) async {
    final id = newId();
    final now = nowIso();
    await _db.execute(
      'INSERT INTO item_categories (id, business_id, main_category_id, name, is_temporary, created_at, updated_at, updated_by) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        _session.businessId,
        shopId,
        name.trim(),
        isTemporary ? 1 : 0,
        now,
        now,
        _session.userId
      ],
    );
    return id;
  }

  Future<void> update(String id, String name, {required bool isTemporary}) async {
    await _db.execute(
      'UPDATE item_categories SET name = ?, is_temporary = ?, updated_at = ?, updated_by = ? WHERE id = ?',
      [name.trim(), isTemporary ? 1 : 0, nowIso(), _session.userId, id],
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    final now = nowIso();
    await _db.execute(
      'UPDATE item_categories SET archived_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
      [archived ? now : null, now, _session.userId, id],
    );
  }

  /// Deletes the category. Its items stay, without a category.
  Future<void> delete(String id) async {
    final now = nowIso();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE items SET item_category_id = NULL, updated_at = ?, updated_by = ? WHERE item_category_id = ?',
        [now, _session.userId, id],
      );
      await tx.execute(
        'UPDATE item_categories SET deleted_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
        [now, now, _session.userId, id],
      );
    });
  }
}

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) =>
    CategoriesRepository(
        ref.watch(databaseProvider), ref.watch(sessionProvider)));

final categoriesForShopProvider =
    StreamProvider.family<List<ItemCategory>, String>((ref, shopId) =>
        ref.watch(categoriesRepositoryProvider).watchForShop(shopId));
