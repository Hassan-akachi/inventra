import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../business/business.dart';
import 'receipt_pdf.dart';
import 'sales.dart';
import '../account/membership.dart';

/// Receipt view of one sale, with sharing, payments and cancel.
class SaleDetailScreen extends ConsumerStatefulWidget {
  const SaleDetailScreen({super.key, required this.saleId, this.justCompleted = false});
  final String saleId;
  final bool justCompleted;

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  bool _busy = false;

  Future<void> _withPdf(Future<void> Function(Uint8List bytes, String no) action) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final sale = await repo.getSale(widget.saleId);
      if (sale == null) return;
      final bytes = await buildReceiptPdf(
        business: await ref.read(businessProvider.future),
        sale: sale,
        lines: await repo.getLines(sale.id),
        payments: await repo.getPayments(sale.id),
      );
      await action(bytes, sale.receiptNo);
    } catch (e) {
      if (mounted) showMessage(context, 'Could not create the receipt: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _withPdf((b, no) => shareReceipt(b, no));
  Future<void> _print() => _withPdf((b, no) => printReceipt(b, no));

  Future<void> _recordPayment(Sale sale) async {
    var method = PaymentMethod.cash;
    final amount = TextEditingController(text: Money.toInput(sale.balance));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          scrollable: true,
          title: const Text('Record payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Balance: ${Money.format(sale.balance, sale.currency)}'),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount received',
                  prefixText: '${supportedCurrencies[sale.currency] ?? ''} ',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in PaymentMethod.values)
                    ChoiceChip(
                      label: Text(m.label),
                      selected: method == m,
                      onSelected: (_) => setState(() => method = m),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final value = Money.parse(amount.text) ?? 0;
    if (value <= 0) return;
    await ref.read(salesRepositoryProvider).addPayment(sale.id, value, method);
  }

  Future<void> _void(Sale sale) async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel this sale?',
      message:
          'The items go back into stock and the sale is marked cancelled. It stays in history.',
      action: 'Cancel sale',
    );
    if (ok) await ref.read(salesRepositoryProvider).voidSale(sale.id);
  }

  @override
  Widget build(BuildContext context) {
    final saleValue = ref.watch(saleProvider(widget.saleId));
    final sale = saleValue.valueOrNull;
    final lines = ref.watch(saleLinesProvider(widget.saleId)).valueOrNull ?? const [];
    final payments =
        ref.watch(salePaymentsProvider(widget.saleId)).valueOrNull ?? const [];
    final business = ref.watch(businessProvider).valueOrNull;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(sale?.receiptNo ?? 'Sale'),
        actions: [
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: _busy || sale == null ? null : _print,
          ),
          IconButton(
            tooltip: 'Share receipt',
            icon: const Icon(Icons.share_outlined),
            onPressed: _busy || sale == null ? null : _share,
          ),
        ],
      ),
      body: sale == null
          ? (saleValue.isLoading
              ? const Center(child: CircularProgressIndicator())
              : const EmptyState(icon: Icons.search_off, title: 'Sale not found'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (widget.justCompleted)
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('Sale completed',
                                    style: theme.textTheme.titleMedium),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: () => context.go('/sell'),
                                icon: const Icon(Icons.add_shopping_cart),
                                label: const Text('New sale'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _share,
                                icon: const Icon(Icons.share_outlined),
                                label: const Text('Share receipt'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                // Receipt
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(business?.name ?? '',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge),
                        if (sale.shopName != null)
                          Text(sale.shopName!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall),
                        const SizedBox(height: 12),
                        if (sale.voided)
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 8),
                            color: theme.colorScheme.errorContainer,
                            child: Text('Cancelled ${formatDateTime(sale.voidedAt)}',
                                textAlign: TextAlign.center),
                          ),
                        _Line('Date', formatDateTime(sale.soldAt)),
                        if (sale.customerName != null)
                          InkWell(
                            onTap: () => context.push('/customer/${sale.customerId}'),
                            child: _Line('Customer', sale.customerName!),
                          ),
                        const Divider(height: 24),
                        for (final l in lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(l.itemName),
                                      Text(
                                        '${l.quantity} ${l.unitName} × ${Money.format(l.unitPrice, sale.currency)}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(Money.format(l.lineTotal, sale.currency)),
                              ],
                            ),
                          ),
                        const Divider(height: 24),
                        _Line('Subtotal', Money.format(sale.subtotal, sale.currency)),
                        if (sale.discount > 0)
                          _Line('Discount', '− ${Money.format(sale.discount, sale.currency)}'),
                        _Line('Total', Money.format(sale.total, sale.currency), bold: true),
                        _Line('Paid', Money.format(sale.amountPaid, sale.currency)),
                        if (sale.balance > 0)
                          _Line('Balance due', Money.format(sale.balance, sale.currency),
                              color: theme.colorScheme.error, bold: true),
                        _Line('Status', sale.voided ? 'Cancelled' : sale.status.label),
                      ],
                    ),
                  ),
                ),

                SectionCard(
                  title: 'Payments',
                  trailing: sale.balance > 0 && !sale.voided
                      ? TextButton.icon(
                          onPressed: () => _recordPayment(sale),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Record payment'),
                        )
                      : null,
                  children: [
                    if (payments.isEmpty)
                      const ListTile(dense: true, title: Text('No payments yet')),
                    for (final p in payments)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(p.method.label),
                        subtitle: Text(formatDateTime(p.paidAt)),
                        trailing: Text(Money.format(p.amount, sale.currency)),
                      ),
                  ],
                ),

                if (!sale.voided && ref.watch(permissionsProvider).canVoidSales)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error),
                      onPressed: () => _void(sale),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel sale'),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    final style = base?.copyWith(
        fontWeight: bold ? FontWeight.w700 : null, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 8),
          Flexible(child: Text(value, style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
