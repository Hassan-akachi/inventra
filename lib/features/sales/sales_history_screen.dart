import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../customers/customers_screen.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';
import 'sales.dart';
import '../account/membership.dart';

enum _Period {
  today('Today', 0),
  week('7 days', 6),
  month('30 days', 29),
  all('All', -1);

  const _Period(this.label, this.daysBack);
  final String label;
  final int daysBack;

  String get fromIso => switch (this) {
        _Period.all => '0000',
        _Period.today => startOfTodayIso(),
        _ => daysAgoIso(daysBack),
      };
}

class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  _Period _period = _Period.today;
  PaymentStatus? _status;
  bool _showCancelled = false;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(activeShopProvider).valueOrNull;
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sales')),
        body: const EmptyState(icon: Icons.storefront_outlined, title: 'Add a shop first'),
      );
    }
    final query = (shopId: shop.id, fromIso: _period.fromIso);
    final sales = ref.watch(salesProvider(query));
    final summary = ref.watch(salesSummaryProvider(query)).valueOrNull;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const ShopSwitcher()),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                for (final p in _Period.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(p.label),
                      selected: _period == p,
                      onSelected: (_) => setState(() => _period = p),
                    ),
                  ),
              ],
            ),
          ),
          if (summary != null)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _Figure('Sales', '${summary.count}'),
                    _Figure('Total', Money.format(summary.total, shop.currency)),
                    if (ref.watch(permissionsProvider).canSeeCosts)
                      _Figure('Profit', Money.format(summary.profit, shop.currency)),
                    _Figure('Unpaid', Money.format(summary.owed, shop.currency),
                        color: summary.owed > 0 ? theme.colorScheme.error : null),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Receipt number or customer',
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                for (final s in PaymentStatus.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilterChip(
                      label: Text(s.label),
                      selected: _status == s,
                      onSelected: (v) => setState(() => _status = v ? s : null),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: const Text('Show cancelled'),
                    selected: _showCancelled,
                    onSelected: (v) => setState(() => _showCancelled = v),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: sales,
              builder: (list) {
                final q = _search.trim().toLowerCase();
                final shown = list.where((s) {
                  if (!_showCancelled && s.voided) return false;
                  if (_status != null && (s.voided || s.status != _status)) return false;
                  if (q.isEmpty) return true;
                  return s.receiptNo.toLowerCase().contains(q) ||
                      (s.customerName ?? '').toLowerCase().contains(q);
                }).toList();
                if (shown.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No sales here',
                    message: 'Try another period or filter.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => SaleTile(sale: shown[i], showCustomer: true),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}
