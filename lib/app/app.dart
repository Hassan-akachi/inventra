import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync/sync.dart';
import '../features/reports/snapshots.dart';
import '../features/settings/settings.dart';
import 'router.dart';
import 'theme.dart';

class InventraApp extends ConsumerWidget {
  const InventraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncManagerProvider); // starts cloud sync when this phone is linked
    ref.watch(snapshotRunnerProvider); // saves finished day/week/month summaries
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Inventra',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(settings.seedColor, Brightness.light),
      darkTheme: buildTheme(settings.seedColor, Brightness.dark),
      themeMode: settings.darkMode,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(settings.textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
