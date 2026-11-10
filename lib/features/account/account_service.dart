import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/db/database.dart';
import '../../core/local_settings.dart';
import '../../core/session.dart';

/// A business this account belongs to in the cloud.
class CloudBusiness {
  const CloudBusiness(this.id, this.name, this.role);
  final String id;
  final String name;
  final String role;
}

/// Sign-in and linking this phone to a business in the cloud.
class AccountService {
  AccountService(this._db, this._session);
  final PowerSyncDatabase _db;
  final Session _session;

  sb.SupabaseClient get _client => sb.Supabase.instance.client;
  LocalSettings get _settings => LocalSettings(_db);
  String get _uid => _client.auth.currentUser!.id;
  String get _email => _client.auth.currentUser?.email ?? 'Staff';

  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  /// Returns false when Supabase wants the email confirmed first.
  Future<bool> signUp(String email, String password) async {
    final res = await _client.auth.signUp(email: email.trim(), password: password);
    return res.session != null;
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<List<CloudBusiness>> myBusinesses() async {
    final rows = await _client.rpc('my_businesses') as List<dynamic>;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        CloudBusiness(r['business_id'] as String, (r['name'] as String?) ?? 'Business',
            (r['role'] as String?) ?? 'staff'),
    ];
  }

  /// True when this phone holds shops, items or sales.
  Future<bool> localHasData() async {
    final row = await _db.get(
      'SELECT (SELECT COUNT(*) FROM main_categories) + (SELECT COUNT(*) FROM items) '
      '+ (SELECT COUNT(*) FROM sales) AS n',
    );
    return ((row['n'] as int?) ?? 0) > 0;
  }

  /// Uses this phone's current business as the cloud business (owner's first phone).
  Future<void> createBusinessFromThisPhone(String name, String currency) async {
    await _client.rpc('create_business', params: {
      'p_id': _session.businessId,
      'p_name': name.trim(),
      'p_currency': currency,
      'p_display_name': _email,
    });
    await _db.execute(
      'UPDATE businesses SET name = ?, owner_id = ? WHERE id = ?',
      [name.trim(), _uid, _session.businessId],
    );
    await _settings.set('linked_user', _uid);
  }

  /// Links this phone's business when the account already owns it in the cloud.
  Future<void> linkThisPhone() => _settings.set('linked_user', _uid);

  Future<String> joinWithCode(String code) async {
    final id = await _client.rpc('join_business', params: {
      'p_code': code.trim().toUpperCase(),
      'p_display_name': _email,
    });
    return id as String;
  }

  /// Replaces everything on this phone with [businessId] from the cloud.
  Future<void> switchToBusiness(String businessId) async {
    await _db.disconnectAndClear();
    await _settings.set('business_id', businessId);
    await _settings.set('linked_user', _uid);
    await _settings.remove('current_shop');
  }
}

final accountServiceProvider = Provider<AccountService>((ref) =>
    AccountService(ref.watch(databaseProvider), ref.watch(sessionProvider)));

/// Readable message for auth and server errors.
String friendlyError(Object e) {
  if (e is sb.AuthException) return e.message;
  if (e is sb.PostgrestException) return e.message;
  final text = '$e';
  if (text.contains('SocketException') || text.contains('ClientException')) {
    return 'No internet connection. Connect and try again.';
  }
  return text;
}
