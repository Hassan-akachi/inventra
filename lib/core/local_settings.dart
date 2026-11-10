import 'package:powersync/powersync.dart' show PowerSyncDatabase;

/// Key/value preferences stored only on this phone (never synced).
class LocalSettings {
  LocalSettings(this._db);
  final PowerSyncDatabase _db;

  Future<String?> get(String key) async {
    final row = await _db
        .getOptional('SELECT value FROM local_settings WHERE id = ?', [key]);
    return row?['value'] as String?;
  }

  Future<Map<String, String>> all() async {
    final rows = await _db.getAll('SELECT id, value FROM local_settings');
    return {
      for (final r in rows) r['id'] as String: (r['value'] as String?) ?? '',
    };
  }

  Future<void> set(String key, String value) async {
    // PowerSync tables are views, so upsert is done by hand.
    await _db.writeTransaction((tx) async {
      final existing = await tx
          .getOptional('SELECT id FROM local_settings WHERE id = ?', [key]);
      if (existing == null) {
        await tx.execute(
            'INSERT INTO local_settings (id, value) VALUES (?, ?)', [key, value]);
      } else {
        await tx.execute(
            'UPDATE local_settings SET value = ? WHERE id = ?', [value, key]);
      }
    });
  }

  Future<void> remove(String key) async {
    await _db.execute('DELETE FROM local_settings WHERE id = ?', [key]);
  }
}
