import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../account/membership.dart';
import '../business/business.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';
import 'currency.dart';
import 'export.dart';
import 'periods.dart';
import 'reports.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  PeriodKind _kind = PeriodKind.thisMonth;
  ReportRange? _custom;
  bool _allShops = false;
  bool _byQuantity = false;
  bool _busy = false;

  ReportRange get _range => rangeFor(_kind, custom: _custom);

  @override
  void initState() {
    super.initState();
    // Keep exchange rates fresh (at most once a day, silently offline).
    Future.microtask(() =>
        ref.read(ratesRepositoryProvider).refreshOnline().catchError((_) => false));
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: _custom == null
          ? null
          : DateTimeRange(
              start: _custom!.start, end: _custom!.end.subtract(const Duration(days: 1))),
    );
    if (picked == null) return;
    setState(() {
      _kind = PeriodKind.custom;
      _custom = ReportRange(picked.start,
          DateTime(picked.end.year, picked.end.month, picked.end.day + 1));
    });
  }

  Future<void> _export(String what, Shop? shop, Report? report) async {
    final perms = ref.read(permissionsProvider);
    final shopId = _allShops ? null : shop?.id;
    final label = _allShops ? 'all shops' : (shop?.name ?? 'shop');
    final exporter = Exporter(ref.read(databaseProvider), ref.read(sessionProvider).businessId,
        showCosts: perms.canSeeCosts);
    setState(() => _busy = true);
    try {
      switch (what) {
        case 'items':
          await exporter.items(shopId: shopId, label: label);
        case 'sales':
          await exporter.sales(shopId: shopId, range: _range, label: label);
        case 'lines':
          await exporter.saleLines(shopId: shopId, range: _range, label: label);
        case 'expenses':
          await exporter.expenses(shopId: shopId, range: _range, label: label);
        case 'pdf':
          if (report == null) return;
          final bytes = await buildReportPdf(
            report: report,
            businessName: ref.read(businessProvider).valueOrNull?.name ?? 'Inventra',
            scopeLabel: _allShops ? 'All shops' : (shop?.name ?? ''),
            showCosts: perms.canSeeCosts,
            rates: ref.read(ratesProvider).valueOrNull ?? Rates.empty,
            reportCurrency: ref.read(reportCurrencyProvider).valueOrNull ?? 'NGN',
          );
          await shareReportPdf(bytes, '$label ${dateOnly(_range.start)}');
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionsProvider);
    final shop = ref.watch(activeShopProvider).valueOrNull;

    if (!perms.canSeeCosts) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Reports are for the owner',
          message: 'Ask the owner to allow "See cost prices, profit and stock value" for you.',
        ),
      );
    }
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: const EmptyState(icon: Icons.storefront_outlined, title: 'Add a shop first'),
      );
    }

    final query = (shopId: _allShops ? null : shop.id, range: _range);
    final report = ref.watch(reportProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: _allShops ? const Text('All shops') : const ShopSwitcher(),
        actions: [
          IconButton(
            tooltip: 'Saved summaries',
            icon: const Icon(Icons.history),
            onPressed: () => context.push('/snapshots'),
          ),
          IconButton(
            tooltip: 'Exchange rates',
            icon: const Icon(Icons.currency_exchange),
            onPressed: () => context.push('/rates'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Export',
            icon: _busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            enabled: !_busy,
            onSelected: (v) => _export(v, shop, report.valueOrNull),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Report as PDF')),
              PopupMenuItem(value: 'sales', child: Text('Sales (CSV for Excel)')),
              PopupMenuItem(value: 'lines', child: Text('Items sold (CSV)')),
              PopupMenuItem(value: 'items', child: Text('Stock list (CSV)')),
              PopupMenuItem(value: 'expenses', child: Text('Expenses (CSV)')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(reportProvider(query)),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (perms.isOwner)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(shop.name, overflow: TextOverflow.ellipsis)),
                    const ButtonSegment(value: true, label: Text('All shops')),
                  ],
                  selected: {_allShops},
                  onSelectionChanged: (s) => setState(() => _allShops = s.first),
                ),
              ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final k in PeriodKind.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(k == PeriodKind.custom && _custom != null
                            ? _custom!.label
                            : k.label),
                        selected: _kind == k,
                        onSelected: (_) => k == PeriodKind.custom
                            ? _pickCustom()
                            : setState(() => _kind = k),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_range.label, style: Theme.of(context).textTheme.bodySmall),
            ),
            report.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not build the report: $e'),
              ),
              data: (r) => _ReportBody(
                report: r,
                byQuantity: _byQuantity,
                onToggleQuantity: (v) => setState(() => _byQuantity = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({
    required this.report,
    required this.byQuantity,
    required this.onToggleQuantity,
  });

  final Report report;
  final bool byQuantity;
  final ValueChanged<bool> onToggleQuantity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rates = ref.watch(ratesProvider).valueOrNull ?? Rates.empty;
    final reportCurrency = ref.watch(reportCurrencyProvider).valueOrNull ?? 'NGN';
    final currencies = {
      ...report.totals.keys,
      ...report.previous.keys,
      ...report.expenses.keys,
      ...report.previousExpenses.keys,
    };
    final multi = currencies.length > 1;
    // Chart and comparisons in one currency: the only one, or the report currency.
    final mainCurrency = multi ? reportCurrency : (currencies.firstOrNull ?? reportCurrency);

    int? inMain(Map<String, int> m) => multi ? rates.sumIn(m, mainCurrency) : m.values.fold<int>(0, (a, b) => a + b);
    final sales = inMain(report.map((t) => t.sales));
    final prevSales = inMain(report.map((t) => t.sales, prev: true));
    final profit = inMain(report.map((t) => t.profit));
    final prevProfit = inMain(report.map((t) => t.profit, prev: true));
    final unpaid = inMain(report.map((t) => t.unpaid));
    final discount = inMain(report.map((t) => t.discount));
    final spent = inMain(report.expenses);
    final net = inMain(report.netProfit());
    final prevNet = inMain(report.netProfit(prev: true));
    final hasExpenses = report.expenses.isNotEmpty || report.previousExpenses.isNotEmpty;
    final count = report.totals.values.fold<int>(0, (a, t) => a + t.count);
    final prevCount = report.previous.values.fold<int>(0, (a, t) => a + t.count);
    final missingRates = multi && sales == null;

    if (report.isEmpty && report.previous.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 32),
        child: EmptyState(
          icon: Icons.insights_outlined,
          title: 'No sales in this period',
          message: 'Pick another period, or make some sales first.',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (missingRates)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            color: theme.colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.currency_exchange),
              title: const Text('Sales are in more than one currency'),
              subtitle: const Text('Add exchange rates to see combined totals. Totals per currency are below.'),
              onTap: () => context.push('/rates'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _Tiles(children: [
            _Kpi('Sales', sales == null ? '—' : Money.format(sales, mainCurrency),
                change: sales == null || prevSales == null ? null : percentChange(sales, prevSales)),
            _Kpi('Profit', profit == null ? '—' : Money.format(profit, mainCurrency),
                change: profit == null || prevProfit == null ? null : percentChange(profit, prevProfit),
                note: () {
                  final m = sales == null || profit == null || sales == 0 ? null : profit / sales * 100;
                  return m == null ? null : '${m.toStringAsFixed(1)}% margin';
                }()),
            _Kpi('Number of sales', '$count', change: percentChange(count, prevCount),
                note: count == 0 || sales == null
                    ? null
                    : 'Average ${Money.format((sales / count).round(), mainCurrency)}'),
            _Kpi('Unpaid', unpaid == null ? '—' : Money.format(unpaid, mainCurrency),
                warn: (unpaid ?? 0) > 0,
                note: discount == null || discount == 0
                    ? null
                    : 'Discounts ${Money.format(discount, mainCurrency)}'),
            if (hasExpenses)
              _Kpi('Expenses', spent == null ? '—' : Money.format(spent, mainCurrency),
                  note: '${report.expenseCategories.length} type${report.expenseCategories.length == 1 ? '' : 's'}'),
            if (hasExpenses)
              _Kpi('Net profit', net == null ? '—' : Money.format(net, mainCurrency),
                  warn: (net ?? 0) < 0,
                  change: net == null || prevNet == null ? null : percentChange(net, prevNet),
                  note: 'Profit minus expenses'),
          ]),
        ),
        if (multi)
          SectionCard(
            title: 'By currency',
            children: [
              for (final c in currencies)
                ListTile(
                  dense: true,
                  title: Text(c),
                  subtitle: Text('${report.totals[c]?.count ?? 0} sales · profit '
                      '${Money.format(report.totals[c]?.profit ?? 0, c)}'),
                  trailing: Text(Money.format(report.totals[c]?.sales ?? 0, c),
                      style: theme.textTheme.titleSmall),
                ),
              if (!missingRates)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Combined in $mainCurrency using ${rates.sources.values.contains('manual') ? 'your rates and ' : ''}'
                    'daily rates from ExchangeRate-API ($ratesSourceUrl).',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        if (report.days.length > 1)
          SectionCard(
            title: 'Sales by day',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: _DayChart(
                  days: report.days,
                  valueOf: (d) => multi ? rates.sumIn(d.byCurrency, mainCurrency) ?? 0
                      : d.byCurrency.values.fold<int>(0, (a, b) => a + b),
                  currency: mainCurrency,
                ),
              ),
            ],
          ),
        if (report.items.isNotEmpty)
          SectionCard(
            title: 'Best sellers',
            trailing: SegmentedButton<bool>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Sales')),
                ButtonSegment(value: true, label: Text('Qty')),
              ],
              selected: {byQuantity},
              onSelectionChanged: (s) => onToggleQuantity(s.first),
            ),
            children: [
              ...() {
                final list = [...report.items];
                if (byQuantity) list.sort((a, b) => b.quantity.compareTo(a.quantity));
                final top = list.take(10).toList();
                final maxV = top.fold<int>(1, (m, i) => math.max(m, byQuantity ? i.quantity : i.revenue));
                return [
                  for (var n = 0; n < top.length; n++)
                    _BarRow(
                      rank: n + 1,
                      label: top[n].name,
                      value: byQuantity
                          ? '${top[n].quantity} ${top[n].baseUnit}'
                          : Money.format(top[n].revenue, top[n].currency),
                      sub: byQuantity
                          ? Money.format(top[n].revenue, top[n].currency)
                          : '${top[n].quantity} ${top[n].baseUnit} · profit ${Money.format(top[n].profit, top[n].currency)}',
                      fraction: (byQuantity ? top[n].quantity : top[n].revenue) / maxV,
                      onTap: () => context.push('/item/${top[n].itemId}'),
                    ),
                ];
              }(),
              if (report.items.length > 10)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('${report.items.length - 10} more items sold. Export "Items sold" for the full list.',
                      style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        if (report.categories.isNotEmpty)
          SectionCard(
            title: 'Sales by category',
            children: [
              ...() {
                final maxV = report.categories.fold<int>(1, (m, c) => math.max(m, c.amount));
                return [
                  for (final c in report.categories)
                    _BarRow(
                      label: c.label,
                      value: Money.format(c.amount, c.currency),
                      sub: '${c.count} units',
                      fraction: c.amount / maxV,
                    ),
                ];
              }(),
            ],
          ),
        if (report.payments.isNotEmpty)
          SectionCard(
            title: 'Money received',
            children: [
              for (final p in report.payments)
                ListTile(
                  dense: true,
                  leading: Icon(switch (p.label) {
                    'cash' => Icons.payments_outlined,
                    'transfer' => Icons.account_balance_outlined,
                    'pos' => Icons.credit_card,
                    _ => Icons.more_horiz,
                  }),
                  title: Text(switch (p.label) {
                    'cash' => 'Cash',
                    'transfer' => 'Transfer',
                    'pos' => 'POS',
                    _ => 'Other',
                  }),
                  subtitle: Text('${p.count} payment${p.count == 1 ? '' : 's'}'),
                  trailing: Text(Money.format(p.amount, p.currency),
                      style: theme.textTheme.titleSmall),
                ),
            ],
          ),
        if (report.expenseCategories.isNotEmpty)
          SectionCard(
            title: 'Expenses',
            trailing: TextButton(
              onPressed: () => context.push('/expenses'),
              child: const Text('Open'),
            ),
            children: [
              ...() {
                final maxV = report.expenseCategories.fold<int>(1, (m, c) => math.max(m, c.amount));
                return [
                  for (final c in report.expenseCategories)
                    _BarRow(
                      label: c.label,
                      value: Money.format(c.amount, c.currency),
                      sub: '${c.count} payment${c.count == 1 ? '' : 's'}',
                      fraction: c.amount / maxV,
                    ),
                ];
              }(),
            ],
          ),
        if (report.stock.isNotEmpty)
          SectionCard(
            title: 'Stock on hand now',
            children: [
              for (final s in report.stock) ...[
                InfoRow('Items', '${s.items} (${s.units} units in stock)'),
                InfoRow('Value at cost', Money.format(s.cost, s.currency)),
                InfoRow('Value at selling price', Money.format(s.retail, s.currency)),
                InfoRow('Possible profit', Money.format(s.retail - s.cost, s.currency)),
              ],
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Compared with ${report.range.previous.label}. Cancelled sales are left out. '
            'Item sales are before whole-sale discounts. '
            'A shop view counts that shop\'s expenses; "All shops" also counts whole-business expenses.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 600 ? 4 : 2;
      return Wrap(children: [
        for (final w in children) SizedBox(width: c.maxWidth / cols, child: w),
      ]);
    });
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, {this.change, this.note, this.warn = false});
  final String label;
  final String value;
  final double? change;
  final String? note;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = change;
    final up = (c ?? 0) >= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: warn ? theme.colorScheme.error : null)),
            ),
            if (c != null)
              Row(
                children: [
                  Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 14, color: up ? const Color(0xFF2E7D32) : theme.colorScheme.error),
                  Flexible(
                    child: Text(
                      '${c.abs().toStringAsFixed(c.abs() >= 100 ? 0 : 1)}% vs before',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: up ? const Color(0xFF2E7D32) : theme.colorScheme.error),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            if (note != null)
              Text(note!, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Simple vertical bars, one per day; tap a bar to see its value.
class _DayChart extends StatefulWidget {
  const _DayChart({required this.days, required this.valueOf, required this.currency});
  final List<DayTotal> days;
  final int Function(DayTotal d) valueOf;
  final String currency;

  @override
  State<_DayChart> createState() => _DayChartState();
}

class _DayChartState extends State<_DayChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = widget.days.map(widget.valueOf).toList();
    final maxV = values.fold<int>(1, math.max);
    final best = values.indexOf(maxV);
    final sel = _selected ?? best;
    final fmtDay = DateFormat(widget.days.length > 31 ? 'd MMM' : 'EEE d MMM');
    final labelEvery = (widget.days.length / 6).ceil().clamp(1, 1000).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sel >= 0 && sel < values.length
              ? '${fmtDay.format(widget.days[sel].day)}: ${Money.format(values[sel], widget.currency)}'
                  '${_selected == null && maxV > 1 ? '  (best day)' : ''}'
              : '',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selected = i),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: values.length > 40 ? 0.5 : 2),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: maxV == 0 ? 0 : math.max(values[i] / maxV, values[i] > 0 ? 0.02 : 0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: i == sel
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primary.withValues(alpha: 0.35),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: i % labelEvery == 0
                    ? Text(DateFormat('d/M').format(widget.days[i].day),
                        style: theme.textTheme.labelSmall, overflow: TextOverflow.visible, softWrap: false)
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.fraction,
    this.sub,
    this.rank,
    this.onTap,
  });

  final String label;
  final String value;
  final String? sub;
  final double fraction;
  final int? rank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (rank != null)
                  SizedBox(
                    width: 24,
                    child: Text('$rank', style: theme.textTheme.labelLarge),
                  ),
                Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Text(value, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction.clamp(0, 1).toDouble(),
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub!, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}
