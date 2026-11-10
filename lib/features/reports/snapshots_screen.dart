import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../account/membership.dart';
import '../settings/settings.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';
import 'periods.dart';
import 'snapshots.dart';

/// Summaries saved automatically at the start of each day, week or month.
class SnapshotsScreen extends ConsumerStatefulWidget {
  const SnapshotsScreen({super.key});

  @override
  ConsumerState<SnapshotsScreen> createState() => _SnapshotsScreenState();
}

class _SnapshotsScreenState extends ConsumerState<SnapshotsScreen> {
  AnalyticsPeriod? _period;

  String _label(AnalyticsPeriod p, String start) {
    final d = DateTime.tryParse(start);
    if (d == null) return start;
    return switch (p) {
      AnalyticsPeriod.day => DateFormat('EEE d MMM yyyy').format(d),
      AnalyticsPeriod.week => 'Week of ${DateFormat('d MMM yyyy').format(d)}',
      AnalyticsPeriod.month => DateFormat('MMMM yyyy').format(d),
    };
  }

  @override
  Widget build(BuildContext context) {
    final period = _period ?? ref.watch(settingsProvider).analyticsPeriod;
    final shop = ref.watch(activeShopProvider).valueOrNull;
    final theme = Theme.of(context);
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saved summaries')),
        body: const EmptyState(icon: Icons.storefront_outlined, title: 'Add a shop first'),
      );
    }
    final snaps = ref.watch(snapshotsProvider((period: period, shopId: shop.id)));
    final runner = ref.watch(snapshotRunnerProvider);

    return Scaffold(
      appBar: AppBar(title: const ShopSwitcher()),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<AnalyticsPeriod>(
              segments: const [
                ButtonSegment(value: AnalyticsPeriod.day, label: Text('Days')),
                ButtonSegment(value: AnalyticsPeriod.week, label: Text('Weeks')),
                ButtonSegment(value: AnalyticsPeriod.month, label: Text('Months')),
              ],
              selected: {period},
              onSelectionChanged: (s) async {
                setState(() => _period = s.first);
                // Fill in this period type too, so switching shows data right away.
                if (ref.read(permissionsProvider).isOwner) {
                  await ref.read(snapshotServiceProvider).run(s.first).catchError((_) => 0);
                }
              },
            ),
          ),
          if (runner.isLoading) const LinearProgressIndicator(),
          Expanded(
            child: AsyncBody(
              value: snaps,
              builder: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.history,
                    title: 'No summaries yet',
                    message: 'A summary is saved for each finished period once you have sales. '
                        'Choose how often in Settings → Analytics.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = list[i];
                    // The next older row of the same currency is the previous period.
                    final prev = list.skip(i + 1).where((o) => o.currency == s.currency).firstOrNull;
                    final change = prev == null ? null : percentChange(s.totalSales, prev.totalSales);
                    return ListTile(
                      title: Text(_label(period, s.periodStart)),
                      subtitle: Text([
                        '${s.itemsSold} units sold',
                        'profit ${Money.format(s.profit, s.currency)}',
                        if (s.stockValue != null) 'stock ${Money.format(s.stockValue, s.currency)}',
                      ].join(' · ')),
                      trailing: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: Money.format(s.totalSales, s.currency),
                              style: theme.textTheme.titleSmall),
                          if (change != null)
                            TextSpan(
                              text: '\n${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(1)}%',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: change >= 0 ? const Color(0xFF2E7D32) : theme.colorScheme.error),
                            ),
                        ]),
                        textAlign: TextAlign.end,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
