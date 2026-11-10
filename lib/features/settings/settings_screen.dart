import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../business/business.dart';
import 'settings.dart';
import '../account/membership.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _Header('Business'),
          Builder(builder: (context) {
            final business = ref.watch(businessProvider).valueOrNull;
            final details = [business?.phone, business?.address]
                .whereType<String>()
                .join(' · ');
            return ListTile(
              leading: const Icon(Icons.store_mall_directory_outlined),
              title: Text(business?.name ?? 'My business'),
              subtitle: Text(
                details.isEmpty
                    ? 'Name, phone and address printed on receipts'
                    : details,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: ref.watch(permissionsProvider).isOwner
                  ? const Icon(Icons.edit_outlined)
                  : null,
              onTap: ref.watch(permissionsProvider).isOwner
                  ? () => showBusinessDialog(context, ref, business)
                  : null,
            );
          }),
          const Divider(),
          const _Header('Display'),
          ListTile(
            title: const Text('Text size'),
            subtitle: Slider(
              value: settings.textScale,
              min: 0.85,
              max: 1.5,
              divisions: 13,
              label: '${(settings.textScale * 100).round()}%',
              onChanged: notifier.setTextScale,
            ),
          ),
          ListTile(
            title: const Text('Colour'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < themeColors.length; i++)
                    Tooltip(
                      message: themeColors[i].name,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => notifier.setColor(i),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: themeColors[i].color,
                          child: settings.colorIndex == i
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 20)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ListTile(
            title: const Text('Theme'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {settings.darkMode},
                onSelectionChanged: (s) => notifier.setThemeMode(s.first),
              ),
            ),
          ),
          const Divider(),
          const _Header('Stock'),
          ListTile(
            title: const Text('Default low-stock level'),
            subtitle: const Text('Used for new items'),
            trailing: SizedBox(
              width: 140,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: settings.lowStockDefault > 0
                        ? () => notifier
                            .setLowStockDefault(settings.lowStockDefault - 1)
                        : null,
                  ),
                  Text('${settings.lowStockDefault}',
                      style: theme.textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () =>
                        notifier.setLowStockDefault(settings.lowStockDefault + 1),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            title: const Text('Warn about expiry'),
            subtitle: Text('${settings.expiryWarningDays} days before'),
            trailing: _Stepper(
              value: settings.expiryWarningDays,
              step: 7,
              min: 7,
              onChanged: notifier.setExpiryWarningDays,
            ),
          ),
          ListTile(
            title: const Text('Flag unpaid sales after'),
            subtitle: Text('${settings.unpaidAlertDays} days'),
            trailing: _Stepper(
              value: settings.unpaidAlertDays,
              step: 1,
              min: 0,
              onChanged: notifier.setUnpaidAlertDays,
            ),
          ),
          const Divider(),
          const _Header('Analytics'),
          ListTile(
            title: const Text('Save a sales summary every'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<AnalyticsPeriod>(
                segments: const [
                  ButtonSegment(value: AnalyticsPeriod.day, label: Text('Day')),
                  ButtonSegment(
                      value: AnalyticsPeriod.week, label: Text('Week')),
                  ButtonSegment(
                      value: AnalyticsPeriod.month, label: Text('Month')),
                ],
                selected: {settings.analyticsPeriod},
                onSelectionChanged: (s) =>
                    notifier.setAnalyticsPeriod(s.first),
              ),
            ),
          ),
          const Divider(),
          const _Header('About'),
          ListTile(
            title: const Text('Inventra 1.0.0'),
            subtitle: Text(
                'Data is stored on this phone and syncs when you sign in (More → Account and sync).\n'
                'Device code: ${ref.watch(sessionProvider).deviceCode}'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.step,
    required this.min,
    required this.onChanged,
  });

  final int value;
  final int step;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: value - step >= min ? () => onChanged(value - step) : null,
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () => onChanged(value + step),
        ),
      ],
    );
  }
}
