import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase, SyncStatus;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../db/database.dart';
import '../session.dart';
import 'connector.dart';

/// Connects PowerSync while this phone is linked to the signed-in account.
class SyncManager {
  SyncManager(this._db, this._session);
  final PowerSyncDatabase _db;
  final Session _session;
  StreamSubscription<sb.AuthState>? _auth;

  void start() {
    if (_session.linked) {
      _db.connect(connector: SupabaseConnector(_db));
    } else {
      _db.disconnect();
    }
    _auth = sb.Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == sb.AuthChangeEvent.signedOut) _db.disconnect();
    });
  }

  void dispose() => _auth?.cancel();
}

final syncManagerProvider = Provider<SyncManager>((ref) {
  final manager = SyncManager(ref.watch(databaseProvider), ref.watch(sessionProvider));
  manager.start();
  ref.onDispose(manager.dispose);
  return manager;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final db = ref.watch(databaseProvider);
  return db.statusStream;
});

/// Changes made on this phone that have not reached the cloud yet.
final pendingUploadsProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .watch('SELECT COUNT(*) AS n FROM ps_crud')
      .map((rs) => (rs.first['n'] as int?) ?? 0);
});
