import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'app/root.dart';
import 'core/config.dart';
import 'core/db/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Works offline: a saved sign-in is restored from the phone.
  await sb.Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseKey,
  );

  final db = await openDatabase();
  runApp(AppRoot(db: db));
}
