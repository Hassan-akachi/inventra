import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../core/db/database.dart';
import '../core/local_settings.dart';
import '../core/session.dart';
import '../features/settings/settings.dart';
import '../features/shops/shops.dart';
import 'app.dart';

/// Loads the session and starts the app. [restart] reloads everything,
/// used after signing in, joining or switching business.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.db});
  final PowerSyncDatabase db;

  static void restart(BuildContext context) =>
      context.findAncestorStateOfType<_AppRootState>()?.restart();

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _Boot {
  const _Boot(this.session, this.stored);
  final Session session;
  final Map<String, String> stored;
}

class _AppRootState extends State<AppRoot> {
  Key _scopeKey = UniqueKey();
  late Future<_Boot> _boot = _load();

  Future<_Boot> _load() async {
    final session = await Session.load(widget.db);
    final stored = await LocalSettings(widget.db).all();
    return _Boot(session, stored);
  }

  void restart() => setState(() {
        _scopeKey = UniqueKey();
        _boot = _load();
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Boot>(
      future: _boot,
      builder: (context, snap) {
        if (snap.hasError) {
          return _BootScreen(message: 'Could not start Inventra:\n${snap.error}');
        }
        if (snap.connectionState != ConnectionState.done || !snap.hasData) {
          return const _BootScreen();
        }
        final boot = snap.data!;
        return ProviderScope(
          key: _scopeKey,
          overrides: [
            databaseProvider.overrideWithValue(widget.db),
            sessionProvider.overrideWithValue(boot.session),
            initialSettingsProvider
                .overrideWithValue(AppSettings.fromMap(boot.stored)),
            initialShopIdProvider.overrideWithValue(boot.stored['current_shop']),
          ],
          child: const InventraApp(),
        );
      },
    );
  }
}

/// Same look as the native splash, shown while the session loads.
class _BootScreen extends StatelessWidget {
  const _BootScreen({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF14213D),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/branding/splash_logo.png', width: 160, height: 160),
                const SizedBox(height: 24),
                if (message == null)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Color(0xFFF2B705)),
                  )
                else
                  Text(message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
