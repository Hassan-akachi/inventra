import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../customers/customers_screen.dart';
import 'cart.dart';
import 'sales.dart';

/// Review the cart, pick a customer and payment, then complete the sale.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _received = TextEditingController();
  bool _receivedEdited = false;
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _received.text = Money.toInput(ref.read(cartProvider).total);
  }

  @override
  void dispose() {
    _received.dispose();
    super.dispose();
  }

  int _amountReceived(Cart cart) =>
      _receivedEdited ? (Money.parse(_received.text) ?? 0) : cart.total;

  Future<void> _editPrice(CartLine line, String currency) async {
    final controller = TextEditingController(text: Money.toInput(line.unitPrice));
    final value = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text('Price of 1 ${line.unitName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              prefixText: '${supportedCurrencies[currency] ?? ''} ',
              helperText: 'Changes this sale only'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, Money.parse(controller.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (value != null) ref.read(cartProvider.notifier).setPrice(line.key, value);
  }

  Future<void> _editQuantity(CartLine line) async {
    final controller = TextEditingController(text: '${line.quantity}');
    final value = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text('Quantity (${line.unitName})'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, int.tryParse(controller.text)),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (value != null) {
      ref.read(cartProvider.notifier).setQuantity(line.key, value);
    }
  }

  Future<void> _editDiscount(Cart cart) async {
    var type = cart.discountType;
    final controller = TextEditingController(
      text: cart.discountValue == 0
          ? ''
          : type == DiscountType.amount
              ? Money.toInput(cart.discountValue)
              : '${cart.discountValue}',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          scrollable: true,
          title: const Text('Discount'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<DiscountType>(
                segments: [
                  ButtonSegment(
                      value: DiscountType.amount,
                      label: Text(supportedCurrencies[cart.currency] ?? 'Amount')),
                  const ButtonSegment(value: DiscountType.percent, label: Text('%')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setState(() {
                  type = s.first;
                  controller.clear();
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: type == DiscountType.amount ? 'Amount off' : 'Percent off',
                  suffixText: type == DiscountType.percent ? '%' : null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final value = type == DiscountType.amount
        ? (Money.parse(controller.text) ?? 0)
        : (int.tryParse(controller.text.trim()) ?? 0).clamp(0, 100).toInt();
    ref.read(cartProvider.notifier).setDiscount(type, value);
  }

  Future<void> _pickCustomer() async {
    final c = await pickCustomer(context, ref);
    if (c != null) ref.read(cartProvider.notifier).setCustomer(c.id, c.name);
  }

  Future<void> _complete(Cart cart) async {
    final received = _amountReceived(cart);
    if (received < cart.total && cart.customerId == null) {
      showMessage(context, 'Choose a customer for sales not fully paid, so the balance can be tracked.');
      return;
    }
    setState(() => _saving = true);
    final cartNotifier = ref.read(cartProvider.notifier);
    try {
      final id = await ref
          .read(salesRepositoryProvider)
          .completeSale(cart, amountPaid: received, method: _method);
      if (mounted) context.pushReplacement('/sale/$id?done=1');
      cartNotifier.clear();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, 'Could not complete the sale: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(cartProvider.notifier);
    // Keep "amount received" equal to the total until the user types their own.
    ref.listen<Cart>(cartProvider, (_, next) {
      if (!_receivedEdited) _received.text = Money.toInput(next.total);
    });

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart')),
        body: EmptyState(
          icon: Icons.shopping_cart_outlined,
          title: 'The cart is empty',
          action: FilledButton(
              onPressed: () => context.pop(), child: const Text('Back to Sell')),
        ),
      );
    }

    final currency = cart.currency ?? 'NGN';
    String money(int v) => Money.format(v, currency);
    final overStock = cart.overStockItemIds;
    final received = _amountReceived(cart);
    final change = received - cart.total;

    return Scaffold(
      appBar: AppBar(
        title: Text('Cart · ${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}'),
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await confirmDialog(context,
                  title: 'Clear cart?',
                  message: 'All items will be removed.',
                  action: 'Clear');
              if (ok) {
                notifier.clear();
                if (context.mounted) context.pop();
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          for (final line in cart.lines)
            Dismissible(
              key: ValueKey(line.key),
              direction: DismissDirection.endToStart,
              background: Container(
                color: theme.colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) => notifier.remove(line.key),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ItemThumb(imagePath: line.imagePath, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.name, style: theme.textTheme.titleSmall),
                          InkWell(
                            onTap: () => _editPrice(line, currency),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '${money(line.unitPrice)} per ${line.unitName}  ✎',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ),
                          if (overStock.contains(line.itemId))
                            Text(
                              'Only ${line.availableBase} in stock',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.error),
                            ),
                          const SizedBox(height: 4),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              IconButton.outlined(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(line.quantity == 1
                                    ? Icons.delete_outline
                                    : Icons.remove),
                                onPressed: () => notifier.setQuantity(
                                    line.key, line.quantity - 1),
                              ),
                              InkWell(
                                onTap: () => _editQuantity(line),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Text('${line.quantity}',
                                      style: theme.textTheme.titleMedium),
                                ),
                              ),
                              IconButton.outlined(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.add),
                                onPressed: () => notifier.setQuantity(
                                    line.key, line.quantity + 1),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(money(line.lineTotal), style: theme.textTheme.titleSmall),
                  ],
                ),
              ),
            ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(cart.customerName ?? 'Add customer (optional)'),
            subtitle: cart.customerName == null
                ? const Text('Needed if the sale is not fully paid')
                : null,
            trailing: cart.customerId == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => notifier.setCustomer(null, null),
                  ),
            onTap: _pickCustomer,
          ),
          ListTile(
            leading: const Icon(Icons.local_offer_outlined),
            title: Text(cart.discount == 0
                ? 'Add discount'
                : cart.discountType == DiscountType.percent
                    ? 'Discount ${cart.discountValue}%'
                    : 'Discount'),
            trailing: Text(cart.discount == 0 ? '' : '− ${money(cart.discount)}'),
            onTap: () => _editDiscount(cart),
          ),
          const Divider(),

          _TotalRow('Subtotal', money(cart.subtotal)),
          if (cart.discount > 0) _TotalRow('Discount', '− ${money(cart.discount)}'),
          _TotalRow('Total', money(cart.total), bold: true),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Payment', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _received,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount received',
                prefixText: '${supportedCurrencies[currency] ?? ''} ',
              ),
              onChanged: (_) => setState(() => _receivedEdited = true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _receivedEdited = false;
                    _received.text = Money.toInput(cart.total);
                  }),
                  child: const Text('Paid in full'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _receivedEdited = true;
                    _received.text = '0';
                  }),
                  child: const Text('Nothing paid (credit)'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: change >= 0
                ? Text(
                    change == 0 ? 'Paid in full' : 'Change to give: ${money(change)}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                  )
                : Text(
                    '${received == 0 ? 'Unpaid' : 'Part-paid'} · balance ${money(-change)}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.error, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saving ? null : () => _complete(cart),
            child: Text('Complete sale · ${money(cart.total)}'),
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
