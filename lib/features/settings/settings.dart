import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/local_settings.dart';

class ThemeColorOption {
  const ThemeColorOption(this.name, this.color);
  final String name;
  final Color color;
}

const themeColors = <ThemeColorOption>[
  ThemeColorOption('Teal', Color(0xFF00897B)),
  ThemeColorOption('Blue', Color(0xFF1E64D9)),
  ThemeColorOption('Green', Color(0xFF2E7D32)),
  ThemeColorOption('Purple', Color(0xFF6A1B9A)),
  ThemeColorOption('Orange', Color(0xFFE65100)),
  ThemeColorOption('Red', Color(0xFFC62828)),
];

/// day | week | month — how often analytics snapshots are saved (phase 5).
enum AnalyticsPeriod { day, week, month }

class AppSettings {
  const AppSettings({
    this.textScale = 1.0,
    this.colorIndex = 0,
    this.darkMode = ThemeMode.system,
    this.analyticsPeriod = AnalyticsPeriod.month,
    this.lowStockDefault = 5,
    this.expiryWarningDays = 30,
    this.unpaidAlertDays = 7,
  });

  final double textScale;
  final int colorIndex;
  final ThemeMode darkMode;
  final AnalyticsPeriod analyticsPeriod;
  final int lowStockDefault;

  /// Warn about items expiring within this many days.
  final int expiryWarningDays;

  /// Warn about unpaid sales older than this many days.
  final int unpaidAlertDays;

  Color get seedColor =>
      themeColors[colorIndex.clamp(0, themeColors.length - 1)].color;

  factory AppSettings.fromMap(Map<String, String> m) => AppSettings(
        textScale: double.tryParse(m['text_scale'] ?? '') ?? 1.0,
        colorIndex: int.tryParse(m['color_index'] ?? '') ?? 0,
        darkMode: ThemeMode.values.firstWhere(
            (t) => t.name == m['theme_mode'],
            orElse: () => ThemeMode.system),
        analyticsPeriod: AnalyticsPeriod.values.firstWhere(
            (p) => p.name == m['analytics_period'],
            orElse: () => AnalyticsPeriod.month),
        lowStockDefault: int.tryParse(m['low_stock_default'] ?? '') ?? 5,
        expiryWarningDays: int.tryParse(m['expiry_warning_days'] ?? '') ?? 30,
        unpaidAlertDays: int.tryParse(m['unpaid_alert_days'] ?? '') ?? 7,
      );

  AppSettings copyWith({
    double? textScale,
    int? colorIndex,
    ThemeMode? darkMode,
    AnalyticsPeriod? analyticsPeriod,
    int? lowStockDefault,
    int? expiryWarningDays,
    int? unpaidAlertDays,
  }) =>
      AppSettings(
        textScale: textScale ?? this.textScale,
        colorIndex: colorIndex ?? this.colorIndex,
        darkMode: darkMode ?? this.darkMode,
        analyticsPeriod: analyticsPeriod ?? this.analyticsPeriod,
        lowStockDefault: lowStockDefault ?? this.lowStockDefault,
        expiryWarningDays: expiryWarningDays ?? this.expiryWarningDays,
        unpaidAlertDays: unpaidAlertDays ?? this.unpaidAlertDays,
      );
}

/// Loaded in main() before the first frame.
final initialSettingsProvider =
    Provider<AppSettings>((ref) => const AppSettings());

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  LocalSettings get _store => LocalSettings(ref.read(databaseProvider));

  Future<void> setTextScale(double v) async {
    state = state.copyWith(textScale: v);
    await _store.set('text_scale', v.toStringAsFixed(2));
  }

  Future<void> setColor(int index) async {
    state = state.copyWith(colorIndex: index);
    await _store.set('color_index', '$index');
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(darkMode: mode);
    await _store.set('theme_mode', mode.name);
  }

  Future<void> setAnalyticsPeriod(AnalyticsPeriod p) async {
    state = state.copyWith(analyticsPeriod: p);
    await _store.set('analytics_period', p.name);
  }

  Future<void> setExpiryWarningDays(int v) async {
    state = state.copyWith(expiryWarningDays: v);
    await _store.set('expiry_warning_days', '$v');
  }

  Future<void> setUnpaidAlertDays(int v) async {
    state = state.copyWith(unpaidAlertDays: v);
    await _store.set('unpaid_alert_days', '$v');
  }

  Future<void> setLowStockDefault(int v) async {
    state = state.copyWith(lowStockDefault: v);
    await _store.set('low_stock_default', '$v');
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
