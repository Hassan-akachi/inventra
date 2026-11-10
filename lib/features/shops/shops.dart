import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/local_settings.dart';
import '../../core/session.dart';
import '../../core/utils.dart';
import '../account/membership.dart';

/// A shop is a "main category" (Shop 1, Home, Shop 2…). Each has its own stock.
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.currency,
    required this.isTemporary,
    this.archivedAt,
  });

  final String id;
  final String name;
  final String currency;
  final bool isTemporary;
  final String? archivedAt;

  bool get archived => archivedAt != null;

  factory Shop.fromRow(Map<String, dynamic> r) => Shop(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        currency: (r['currency'] as String?) ?? 'NGN',
        isTemporary: (r['is_temporary'] as int? ?? 0) == 1,
        archivedAt: r['archived_at'] as String?,
      );
}

class ShopsRepository {
  ShopsRepository(this._db, this._session);

  final PowerSyncDatabase _db;
  final Session _session;

  Stream<List<Shop>> watchAll() => _db
      .watch(
        'SELECT * FROM main_categories WHERE business_id = ? AND deleted_at IS NULL '
        'ORDER BY name COLLATE NOCASE',
        parameters: [_session.businessId],
      )
      .map((rs) => rs.map(Shop.fromRow).toList());

  Future<String> create({
    required String name,
    required String currency,
    bool isTemporary = false,
  }) async {
    final id = newId();
    final now = nowIso();
    await _db.execute(
      'INSERT INTO main_categories (id, business_id, name, currency, is_temporary, created_at, updated_at, updated_by) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        _session.businessId,
        name.trim(),
        currency,
        isTemporary ? 1 : 0,
        now,
        now,
        _session.userId
      ],
    );
    return id;
  }

  Future<void> update(
    String id, {
    required String name,
    required String currency,
    required bool isTemporary,
  }) async {
    await _db.execute(
      'UPDATE main_categories SET name = ?, currency = ?, is_temporary = ?, updated_at = ?, updated_by = ? WHERE id = ?',
      [name.trim(), currency, isTemporary ? 1 : 0, nowIso(), _session.userId, id],
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    final now = nowIso();
    await _db.execute(
      'UPDATE main_categories SET archived_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
      [archived ? now : null, now, _session.userId, id],
    );
  }

  /// Returns false (and deletes nothing) when the shop still has items.
  Future<bool> delete(String id) async {
    final row = await _db.get(
      'SELECT COUNT(*) AS n FROM items WHERE main_category_id = ? AND deleted_at IS NULL',
      [id],
    );
    if ((row['n'] as int) > 0) return false;
    final now = nowIso();
    await _db.execute(
      'UPDATE main_categories SET deleted_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
      [now, now, _session.userId, id],
    );
    return true;
  }
}

final shopsRepositoryProvider = Provider<ShopsRepository>((ref) =>
    ShopsRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)));

final shopsProvider = StreamProvider<List<Shop>>(
    (ref) => ref.watch(shopsRepositoryProvider).watchAll());

/// Last shop used, loaded in main().
final initialShopIdProvider = Provider<String?>((ref) => null);

class CurrentShopNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(initialShopIdProvider);

  Future<void> select(String id) async {
    state = id;
    await LocalSettings(ref.read(databaseProvider)).set('current_shop', id);
  }
}

final currentShopIdProvider =
    NotifierProvider<CurrentShopNotifier, String?>(CurrentShopNotifier.new);

/// Shops this user may work in (staff can be limited to some shops).
final visibleShopsProvider = Provider<AsyncValue<List<Shop>>>((ref) {
  final perms = ref.watch(permissionsProvider);
  return ref
      .watch(shopsProvider)
      .whenData((list) => list.where((s) => perms.canUseShop(s.id)).toList());
});

/// The shop the app is working in: the selected one, or the first active shop.
/// Null when no active shop exists yet.
final activeShopProvider = Provider<AsyncValue<Shop?>>((ref) {
  final shops = ref.watch(visibleShopsProvider);
  final currentId = ref.watch(currentShopIdProvider);
  return shops.whenData((list) {
    final active = list.where((s) => !s.archived).toList();
    if (active.isEmpty) return null;
    return active.firstWhere((s) => s.id == currentId,
        orElse: () => active.first);
  });
});
