import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../config.dart';
import '../local_settings.dart';
import '../session.dart';

/// Connects the phone's PowerSync database to Supabase.
/// Downloads come from the PowerSync service; uploads go straight to Supabase.
class SupabaseConnector extends PowerSyncBackendConnector {
  SupabaseConnector(this._db);
  final PowerSyncDatabase _db;

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    var session = _client.auth.currentSession;
    if (session == null) return null;
    if (session.isExpired) {
      try {
        session = (await _client.auth.refreshSession()).session ?? session;
      } catch (_) {
        // Offline: PowerSync retries later.
      }
    }
    final s = session!;
    return PowerSyncCredentials(
      endpoint: AppConfig.powersyncUrl,
      token: s.accessToken,
      userId: s.user.id,
      expiresAt: s.expiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(s.expiresAt! * 1000),
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final tx = await database.getNextCrudTransaction();
    if (tx == null) return;
    final uid = _client.auth.currentUser?.id;
    CrudEntry? current;
    try {
      for (final op in tx.crud) {
        current = op;
        final table = _client.from(op.table);
        final data = _withRealUser(op.opData, uid);
        switch (op.op) {
          case UpdateType.put:
            await table.upsert({...?data, 'id': op.id});
          case UpdateType.patch:
            if (data != null && data.isNotEmpty) {
              await table.update(data).eq('id', op.id);
            }
          case UpdateType.delete:
            await table.delete().eq('id', op.id);
        }
      }
      await tx.complete();
    } on sb.PostgrestException catch (e) {
      if (_isPermanent(e)) {
        // The server will never accept this change (bad data or no permission).
        // Skip it so the rest of the queue can upload, and keep a note for the user.
        debugPrint('Inventra upload rejected: ${current?.table} ${current?.id}: ${e.message}');
        await LocalSettings(_db).set(
          'last_sync_error',
          '${DateTime.now().toIso8601String()}|${current?.table}|${e.code}|${e.message}',
        );
        await tx.complete();
      } else {
        rethrow; // network or server hiccup: PowerSync retries automatically
      }
    }
  }

  /// Records made before sign-in carry the placeholder user id; swap in the real one.
  static Map<String, dynamic>? _withRealUser(Map<String, dynamic>? data, String? uid) {
    if (data == null || uid == null) return data;
    return {
      for (final e in data.entries) e.key: e.value == localUserId ? uid : e.value,
    };
  }

  /// Postgres error classes that retrying can't fix:
  /// 22 = bad data, 23 = constraint, 42501 = row-level security, PGRST204 = unknown column.
  static bool _isPermanent(sb.PostgrestException e) {
    final code = e.code ?? '';
    return code.startsWith('22') ||
        code.startsWith('23') ||
        code == '42501' ||
        code == 'PGRST204';
  }
}
