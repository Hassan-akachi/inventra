import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';

/// Free daily rates, no key needed. Their terms ask for an attribution link,
/// shown wherever converted totals appear.
const ratesSourceUrl = 'https://www.exchangerate-api.com';
const _ratesEndpoint = 'https://open.er-api.com/v6/latest/NGN';

/// Exchange rates, all expressed as "1 NGN = x CUR".
class Rates {
  const Rates(this.perNgn, this.sources, this.asOf);

  final Map<String, double> perNgn;

  /// currency -> 'manual' | 'online'
  final Map<String, String> sources;

  /// currency -> when the rate was saved (ISO text)
  final Map<String, String> asOf;

  static const empty = Rates({'NGN': 1}, {}, {});

  bool has(String currency) => currency == 'NGN' || perNgn.containsKey(currency);

  /// Converts minor units between currencies, or null when a rate is missing.
  int? convert(int amount, String from, String to) {
    if (from == to) return amount;
    final f = from == 'NGN' ? 1.0 : perNgn[from];
    final t = to == 'NGN' ? 1.0 : perNgn[to];
    if (f == null || t == null || f == 0) return null;
    return (amount / f * t).round();
  }

  /// "1 USD = ₦1,650.00" style text, or null without a rate.
  String? describe(String currency) {
    final r = perNgn[currency];
    if (currency == 'NGN' || r == null || r == 0) return null;
    return '1 $currency = ${Money.format((100 / r).round(), 'NGN')}';
  }

  /// Sums an amount-per-currency map in [to]. Returns null if any rate is missing.
  int? sumIn(Map<String, int> amounts, String to) {
    var total = 0;
    for (final e in amounts.entries) {
      final v = convert(e.value, e.key, to);
      if (v == null) return null;
      total += v;
    }
    return total;
  }
}

class RatesRepository {
  RatesRepository(this._db, this._session);
  final PowerSyncDatabase _db;
  final Session _session;

  /// Latest rate per currency; a manual rate wins over an online one.
  Stream<Rates> watch() => _db
      .watch(
        'SELECT quote, rate, source, fetched_at FROM exchange_rates '
        "WHERE business_id = ? AND base = 'NGN' ORDER BY fetched_at",
        parameters: [_session.businessId],
      )
      .map((rs) {
    final online = <String, (double, String)>{};
    final manual = <String, (double, String)>{};
    for (final r in rs) {
      final q = r['quote'] as String?;
      final rate = (r['rate'] as num?)?.toDouble();
      if (q == null || rate == null) continue;
      final entry = (rate, (r['fetched_at'] as String?) ?? '');
      if (r['source'] == 'manual') {
        if (rate > 0) {
          manual[q] = entry;
        } else {
          manual.remove(q); // a 0 manual rate clears the override
        }
      } else {
        online[q] = entry;
      }
    }
    final per = <String, double>{'NGN': 1};
    final src = <String, String>{};
    final asOf = <String, String>{};
    for (final c in supportedCurrencies.keys) {
      final m = manual[c];
      final o = online[c];
      if (m != null) {
        per[c] = m.$1;
        src[c] = 'manual';
        asOf[c] = m.$2;
      } else if (o != null) {
        per[c] = o.$1;
        src[c] = 'online';
        asOf[c] = o.$2;
      }
    }
    return Rates(per, src, asOf);
  });

  Future<void> _insert(String quote, double rate, String source) async {
    await _db.execute(
      'INSERT INTO exchange_rates (id, business_id, base, quote, rate, source, fetched_at) '
      "VALUES (?, ?, 'NGN', ?, ?, ?, ?)",
      [newId(), _session.businessId, quote, rate, source, nowIso()],
    );
  }

  /// Saves "1 [currency] = [nairaPerUnit] NGN" as a manual rate.
  /// Pass 0 to go back to the online rate.
  Future<void> setManual(String currency, double nairaPerUnit) =>
      _insert(currency, nairaPerUnit == 0 ? 0 : 1 / nairaPerUnit, 'manual');

  /// Downloads today's rates unless already fetched in the last 20 hours.
  /// Returns true when new rates were saved.
  Future<bool> refreshOnline({bool force = false}) async {
    if (!force) {
      final last = await _db.getOptional(
        "SELECT MAX(fetched_at) AS t FROM exchange_rates WHERE business_id = ? AND source = 'online'",
        [_session.businessId],
      );
      final t = DateTime.tryParse((last?['t'] as String?) ?? '');
      if (t != null && DateTime.now().toUtc().difference(t).inHours < 20) return false;
    }
    final res = await http.get(Uri.parse(_ratesEndpoint)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Rates service returned ${res.statusCode}');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['result'] != 'success') throw Exception('Rates service: ${body['error-type']}');
    final rates = (body['rates'] as Map<String, dynamic>);
    await _db.writeTransaction((tx) async {
      final now = nowIso();
      for (final c in supportedCurrencies.keys) {
        if (c == 'NGN') continue;
        final r = (rates[c] as num?)?.toDouble();
        if (r == null) continue;
        await tx.execute(
          'INSERT INTO exchange_rates (id, business_id, base, quote, rate, source, fetched_at) '
          "VALUES (?, ?, 'NGN', ?, ?, 'online', ?)",
          [newId(), _session.businessId, c, r, now],
        );
      }
    });
    return true;
  }

  Future<void> setReportCurrency(String currency) async {
    await _db.execute(
      'UPDATE businesses SET report_currency = ?, updated_at = ? WHERE id = ?',
      [currency, nowIso(), _session.businessId],
    );
  }

  Stream<String> watchReportCurrency() => _db
      .watch('SELECT report_currency, default_currency FROM businesses WHERE id = ?',
          parameters: [_session.businessId])
      .map((rs) => rs.isEmpty
          ? 'NGN'
          : (rs.first['report_currency'] as String?) ??
              (rs.first['default_currency'] as String?) ??
              'NGN');
}

final ratesRepositoryProvider = Provider<RatesRepository>((ref) =>
    RatesRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)));

final ratesProvider = StreamProvider<Rates>(
    (ref) => ref.watch(ratesRepositoryProvider).watch());

final reportCurrencyProvider = StreamProvider<String>(
    (ref) => ref.watch(ratesRepositoryProvider).watchReportCurrency());
