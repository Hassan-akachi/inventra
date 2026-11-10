import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../account/account_service.dart';
import '../account/membership.dart';
import 'currency.dart';

/// Exchange rates used to combine totals across currencies.
class RatesScreen extends ConsumerStatefulWidget {
  const RatesScreen({super.key});

  @override
  ConsumerState<RatesScreen> createState() => _RatesScreenState();
}

class _RatesScreenState extends ConsumerState<RatesScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Quietly fetch today's rates if we haven't yet.
    Future.microtask(() => ref.read(ratesRepositoryProvider).refreshOnline().catchError((_) => false));
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await ref.read(ratesRepositoryProvider).refreshOnline(force: true);
      if (mounted) showMessage(context, 'Rates updated');
    } catch (e) {
      if (mounted) showMessage(context, 'Could not get rates: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setManual(String currency, Rates rates) async {
    final current = rates.perNgn[currency];
    final controller = TextEditingController(
        text: current == null || current == 0 ? '' : (1 / current).toStringAsFixed(2));
    final result = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text('Your rate for $currency'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How many naira for 1 $currency? Use this for the rate you actually '
                'buy or sell at (for example the parallel market).'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(prefixText: '1 $currency = ₦ '),
            ),
          ],
        ),
        actions: [
          if (rates.sources[currency] == 'manual')
            TextButton(
              onPressed: () => Navigator.pop(c, 0.0),
              child: const Text('Use online rate'),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, double.tryParse(controller.text.replaceAll(',', ''))),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result < 0) return;
    await ref.read(ratesRepositoryProvider).setManual(currency, result);
  }

  @override
  Widget build(BuildContext context) {
    final rates = ref.watch(ratesProvider).valueOrNull ?? Rates.empty;
    final reportCurrency = ref.watch(reportCurrencyProvider).valueOrNull ?? 'NGN';
    final isOwner = ref.watch(permissionsProvider).isOwner;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exchange rates'),
        actions: [
          IconButton(
            tooltip: 'Get today\'s rates',
            onPressed: _busy ? null : _refresh,
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Used only to add up sales made in different currencies. '
              'Each sale keeps its own currency and amount.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (isOwner)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CurrencyDropdown(
                value: reportCurrency,
                label: 'Show combined totals in',
                onChanged: (v) => ref.read(ratesRepositoryProvider).setReportCurrency(v),
              ),
            ),
          const SizedBox(height: 8),
          for (final c in supportedCurrencies.keys.where((c) => c != 'NGN'))
            ListTile(
              leading: CircleAvatar(child: Text(supportedCurrencies[c]!)),
              title: Text(rates.describe(c) ?? '1 $c = no rate yet'),
              subtitle: Text(rates.sources[c] == null
                  ? 'Tap refresh when online, or set your own'
                  : '${rates.sources[c] == 'manual' ? 'Your rate' : 'Online rate'} · ${formatDateTime(rates.asOf[c])}'),
              trailing: isOwner ? const Icon(Icons.edit_outlined) : null,
              onTap: isOwner ? () => _setManual(c, rates) : null,
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Online rates: ExchangeRate-API ($ratesSourceUrl), updated once a day. '
              'Your own rate replaces the online rate until you switch back.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
