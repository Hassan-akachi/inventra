import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';
import '../business/business.dart';

/// Things the owner can allow a staff member to do.
enum StaffPermission {
  editItems('edit_items', 'Add and edit items, categories and suppliers'),
  adjustStock('adjust_stock', 'Receive stock, adjust and count stock'),
  viewCosts('view_costs', 'See cost prices, profit and stock value'),
  recordExpenses('record_expenses', 'Record expenses');

  const StaffPermission(this.key, this.label);
  final String key;
  final String label;
}

class Member {
  const Member({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.role,
    required this.permissions,
    required this.shopIds,
  });

  final String id;
  final String userId;
  final String displayName;
  final String role;
  final Set<String> permissions;

  /// Empty = all shops.
  final Set<String> shopIds;

  bool get isOwner => role == 'owner';

  static Set<String> _list(Object? v) {
    if (v is! String || v.isEmpty) return {};
    try {
      return (jsonDecode(v) as List).map((e) => '$e').toSet();
    } catch (_) {
      return {};
    }
  }

  factory Member.fromRow(Map<String, dynamic> r) => Member(
        id: r['id'] as String,
        userId: (r['user_id'] as String?) ?? '',
        displayName: (r['display_name'] as String?) ?? 'Staff',
        role: (r['role'] as String?) ?? 'staff',
        permissions: _list(r['permissions']),
        shopIds: _list(r['shop_ids']),
      );
}

/// What the current user may do. Without an account the phone's user is the owner.
class Permissions {
  const Permissions({
    required this.isOwner,
    this.granted = const {},
    this.shopIds = const {},
  });

  static const owner = Permissions(isOwner: true);

  final bool isOwner;
  final Set<String> granted;
  final Set<String> shopIds;

  bool _has(StaffPermission p) => isOwner || granted.contains(p.key);
  bool get canEditItems => _has(StaffPermission.editItems);
  bool get canAdjustStock => _has(StaffPermission.adjustStock);
  bool get canSeeCosts => _has(StaffPermission.viewCosts);
  bool get canRecordExpenses => _has(StaffPermission.recordExpenses);
  bool get canVoidSales => isOwner;
  bool get canManageShops => isOwner;
  bool get canManageTeam => isOwner;
  bool canUseShop(String shopId) =>
      isOwner || shopIds.isEmpty || shopIds.contains(shopId);
}

class MembersRepository {
  MembersRepository(this._db, this._session);
  final PowerSyncDatabase _db;
  final Session _session;

  Stream<List<Member>> watchAll() => _db
      .watch(
        'SELECT * FROM members WHERE business_id = ? AND deleted_at IS NULL '
        "ORDER BY role = 'owner' DESC, display_name COLLATE NOCASE",
        parameters: [_session.businessId],
      )
      .map((rs) => rs.map(Member.fromRow).toList());

  Future<void> update(String id,
      {required Set<String> permissions, required Set<String> shopIds}) async {
    await _db.execute(
      'UPDATE members SET permissions = ?, shop_ids = ?, updated_at = ?, updated_by = ? WHERE id = ?',
      [jsonEncode(permissions.toList()), jsonEncode(shopIds.toList()), nowIso(), _session.userId, id],
    );
  }

  Future<void> remove(String id) async {
    final now = nowIso();
    await _db.execute(
      'UPDATE members SET deleted_at = ?, updated_at = ?, updated_by = ? WHERE id = ?',
      [now, now, _session.userId, id],
    );
  }
}

final membersRepositoryProvider = Provider<MembersRepository>((ref) =>
    MembersRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)));

final membersProvider = StreamProvider<List<Member>>(
    (ref) => ref.watch(membersRepositoryProvider).watchAll());

final permissionsProvider = Provider<Permissions>((ref) {
  final session = ref.watch(sessionProvider);
  if (!session.linked) return Permissions.owner;
  final business = ref.watch(businessProvider).valueOrNull;
  final ownerId = business?.ownerId;
  if (ownerId == session.userId || ownerId == localUserId) return Permissions.owner;
  final me = (ref.watch(membersProvider).valueOrNull ?? const <Member>[])
      .where((m) => m.userId == session.userId)
      .firstOrNull;
  if (me == null) {
    // Not synced yet: allow selling only until the member record arrives.
    return const Permissions(isOwner: false);
  }
  if (me.isOwner) return Permissions.owner;
  return Permissions(isOwner: false, granted: me.permissions, shopIds: me.shopIds);
});
