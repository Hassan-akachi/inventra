import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import 'schema.dart';

/// Overridden in main() with the opened database.
final databaseProvider = Provider<PowerSyncDatabase>(
  (ref) => throw UnimplementedError('databaseProvider is set in main()'),
);

/// Opens the on-device database. Works fully offline.
/// Cloud sync (Supabase + PowerSync) is connected in phase 4.
Future<PowerSyncDatabase> openDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final db = PowerSyncDatabase(
    schema: schema,
    path: p.join(dir.path, 'inventra.db'),
  );
  await db.initialize();
  return db;
}
