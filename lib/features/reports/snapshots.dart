import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';
import '../account/membership.dart';
import '../settings/settings.dart';
import 'periods.dart';
import 'reports.dart';

/// A saved summary of one finished day, week or month for a shop.
class Snapshot {
  const Snapshot({
    required this.periodType,
    required this.periodStart,
    required this.shopId,
    required this.currency,
    required this.totalSales,
    required this.totalCost,
    required this.itemsSold,
    this.stockValue,
    this.shopName,
  });

  final String periodType;
  final String periodStart; // yyyy-MM-dd, local
  final String shopId;
  final String? shopName;
  final String currency;
  final int totalSales;
  final int totalCost;
  final int itemsSold;
  final int? stockValue;
  int get profit => totalSales - totalCost;

  factory Snapshot.fromRow(Map<String, dynamic> r) => Snapshot(
        periodType: (r['period_type'] as String?) ?? 'day',
        periodStart: (r['period_start'] as String?) ?? '',
        shopId: (r['main_category_id'] as String?) ?? '',
        shopName: r['shop_name'] as String?,
        currency: (r['currency'] as String?) ?? 'NGN',
        totalSales: (r['total_sales'] as num?)?.toInt() ?? 0,
        totalCost: (r['total_cost'] as num?)?.toInt() ?? 0,
        itemsSold: (r['items_sold'] as num?)?.toInt() ?? 0,
        stockValue: (r['stock_value'] as num?)?.toInt(),
      );
}

/// Start of the period containing [d].
DateTime periodStartFor(AnalyticsPeriod p, DateTime d) => switch (p) {
      AnalyticsPeriod.day => DateTime(d.year, d.month, d.day),
      AnalyticsPeriod.week => DateTime(d.year, d.month, d.day - (d.weekday - 1)),
      AnalyticsPeriod.month => DateTime(d.year, d.month, 1),
    };

DateTime nextPeriodStart(AnalyticsPeriod p, DateTime start) => switch (p) {
      AnalyticsPeriod.day => DateTime(start.year, start.month, start.day + 1),
      AnalyticsPeriod.week => DateTime(start.year, start.month, start.day + 7),
      AnalyticsPeriod.month => DateTime(start.year, start.month + 1, 1),
    };

/// Saves a summary at the start of every day, week or month (the period chosen
/// in Settings) for every finished period since the last one. Runs on the
/// owner's phone when the app opens. Ids are derived from the period, so two
/// phones saving the same period write the same row.
class SnapshotService {
  SnapshotService(this._db, this._session, this._reports);
  final PowerSyncDatabase _db;
  final Session _session;
  final ReportsRepository _reports;
  static const _uuid = Uuid();

  String _idFor(String type, String start, String shopId, String currency) => _uuid.v5(
      Namespace.url.value, 'inventra:${_session.businessId}:$type:$start:$shopId:$currency');

  Future<int> run(AnalyticsPeriod period) async {
    final shops = await _db.getAll(
      'SELECT id FROM main_categories WHERE business_id = ? AND deleted_at IS NULL',
      [_session.businessId],
    );
    final currentStart = periodStartFor(period, DateTime.now());
    var saved = 0;

    for (final shop in shops) {
      final shopId = shop['id'] as String;
      final last = await _db.getOptional(
        'SELECT MAX(period_start) AS p FROM analytics_snapshots '
        'WHERE business_id = ? AND main_category_id = ? AND period_type = ?',
        [_session.businessId, shopId, period.name],
      );
      DateTime start;
      final lastStart = DateTime.tryParse((last?['p'] as String?) ?? '');
      if (lastStart != null) {
        start = nextPeriodStart(period, lastStart);
      } else {
        final first = await _db.getOptional(
          'SELECT MIN(sold_at) AS t FROM sales WHERE main_category_id = ? AND deleted_at IS NULL',
          [shopId],
        );
        final t = DateTime.tryParse((first?['t'] as String?) ?? '')?.toLocal();
        if (t == null) continue; // no sales yet
        start = periodStartFor(period, t);
      }

      var guard = 0;
      while (start.isBefore(currentStart) && guard++ < 400) {
        final end = nextPeriodStart(period, start);
        final range = ReportRange(start, end);
        final totals = await _reports.totals(shopId, range);
        final itemsSold = await _db.get(
          'SELECT COALESCE(SUM(si.base_quantity), 0) AS n FROM sale_items si JOIN sales s ON s.id = si.sale_id '
          'WHERE s.main_category_id = ? AND s.voided_at IS NULL AND s.deleted_at IS NULL '
          'AND s.sold_at >= ? AND s.sold_at < ?',
          [shopId, range.fromIso, range.toIso],
        );
        final startText = dateOnly(start);
        // Always record the shop's currency, even for a period with no sales.
        final shopCurrency = await _db.get(
            'SELECT currency FROM main_categories WHERE id = ?', [shopId]);
        final currencies = {
          ...totals.keys,
          (shopCurrency['currency'] as String?) ?? 'NGN',
        };
        final isLatest = !nextPeriodStart(period, start).isBefore(currentStart);
        await _db.writeTransaction((tx) async {
          for (final c in currencies) {
            final id = _idFor(period.name, startText, shopId, c);
            final exists =
                await tx.getOptional('SELECT id FROM analytics_snapshots WHERE id = ?', [id]);
            if (exists != null) continue;
            final t = totals[c] ?? const Totals();
            int? stockValue;
            if (isLatest) {
              final v = await tx.get(
                'SELECT COALESCE(SUM(CASE WHEN q > 0 THEN q * COALESCE(cost_price, 0) ELSE 0 END), 0) AS v FROM ('
                'SELECT i.cost_price, COALESCE((SELECT SUM(m.change) FROM stock_movements m WHERE m.item_id = i.id), 0) AS q '
                'FROM items i WHERE i.main_category_id = ? AND i.currency = ? AND i.deleted_at IS NULL)',
                [shopId, c],
              );
              stockValue = (v['v'] as num?)?.toInt();
            }
            await tx.execute(
              'INSERT INTO analytics_snapshots (id, business_id, period_type, period_start, main_category_id, '
              'currency, total_sales, total_cost, profit, items_sold, stock_value, created_at) '
              'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [
                id, _session.businessId, period.name, startText, shopId, c, t.sales, t.cost,
                t.profit, (itemsSold['n'] as num?)?.toInt() ?? 0, stockValue, nowIso(),
              ],
            );
            saved++;
          }
        });
        start = end;
      }
    }
    return saved;
  }

  Stream<List<Snapshot>> watch(AnalyticsPeriod period, {String? shopId}) => _db
      .watch(
        'SELECT a.*, m.name AS shop_name FROM analytics_snapshots a '
        'LEFT JOIN main_categories m ON m.id = a.main_category_id '
        'WHERE a.business_id = ? AND a.period_type = ? '
        '${shopId == null ? '' : 'AND a.main_category_id = ? '}'
        'ORDER BY a.period_start DESC, m.name LIMIT 500',
        parameters: [_session.businessId, period.name, if (shopId != null) shopId],
      )
      .map((rs) => rs.map(Snapshot.fromRow).toList());
}

final snapshotServiceProvider = Provider<SnapshotService>((ref) => SnapshotService(
      ref.watch(databaseProvider),
      ref.watch(sessionProvider),
      ref.watch(reportsRepositoryProvider),
    ));

/// Runs once per app start on the owner's phone.
final snapshotRunnerProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(permissionsProvider).isOwner) return 0;
  final period = ref.read(settingsProvider).analyticsPeriod;
  try {
    return await ref.read(snapshotServiceProvider).run(period);
  } catch (_) {
    return 0; // never block the app on analytics
  }
});

final snapshotsProvider =
    StreamProvider.family<List<Snapshot>, ({AnalyticsPeriod period, String? shopId})>(
        (ref, q) => ref.watch(snapshotServiceProvider).watch(q.period, shopId: q.shopId));
