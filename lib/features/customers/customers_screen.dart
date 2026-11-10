import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../sales/sales.dart';
import 'customers.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _search = '';
  bool _owingOnly = false;

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/customer/new'),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add customer'),
      ),
      body: AsyncBody(
        value: customers,
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.people_outline,
              title: 'No customers yet',
              message:
                  'Add customers to track what they buy and what they owe. You can also add one at checkout.',
            );
          }
          final q = _search.toLowerCase();
          final shown = list
              .where((c) => !_owingOnly || c.balance > 0)
              .where((c) =>
                  q.isEmpty ||
                  c.name.toLowerCase().contains(q) ||
                  (c.phone ?? '').contains(q))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search name or phone',
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilterChip(
                    label: const Text('Owing money'),
                    selected: _owingOnly,
                    onSelected: (v) => setState(() => _owingOnly = v),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final c in shown)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase()),
                        ),
                        title: Text(c.name),
                        subtitle: Text([
                          if (c.phone != null) c.phone!,
                          '${c.saleCount} purchase${c.saleCount == 1 ? '' : 's'}',
                        ].join(' · ')),
                        trailing: c.balance > 0
                            ? Text('Owes ${c.balanceLabel}',
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error))
                            : null,
                        onTap: () => context.push('/customer/${c.id}'),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerProvider(customerId));
    final sales = ref.watch(customerSalesProvider(customerId));
    final c = customer.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(c?.name ?? 'Customer'),
        actions: [
          if (c != null)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/customer/${c.id}/edit'),
            ),
        ],
      ),
      body: customer.isLoading
          ? const Center(child: CircularProgressIndicator())
          : c == null
              ? const EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'This customer was deleted')
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    SectionCard(
                      title: 'Details',
                      children: [
                        InfoRow('Phone', c.phone ?? '—'),
                        InfoRow('Email', c.email ?? '—'),
                        InfoRow('Address', c.address ?? '—'),
                        if (c.note != null) InfoRow('Note', c.note!),
                      ],
                    ),
                    AsyncBody(
                      value: sales,
                      builder: (list) {
                        final active = list.where((s) => !s.voided).toList();
                        // Totals per currency, since sales may be in different currencies.
                        final spent = <String, int>{};
                        final owed = <String, int>{};
                        for (final s in active) {
                          spent[s.currency] = (spent[s.currency] ?? 0) + s.total;
                          if (s.balance > 0) {
                            owed[s.currency] = (owed[s.currency] ?? 0) + s.balance;
                          }
                        }
                        String fmt(Map<String, int> m) => m.isEmpty
                            ? '—'
                            : m.entries
                                .map((e) => Money.format(e.value, e.key))
                                .join(' + ');
                        return Column(
                          children: [
                            SectionCard(
                              title: 'Summary',
                              children: [
                                InfoRow('Purchases', '${active.length}'),
                                InfoRow('Total spent', fmt(spent)),
                                InfoRow('Still owes', fmt(owed)),
                              ],
                            ),
                            SectionCard(
                              title: 'Purchase history',
                              children: [
                                if (list.isEmpty)
                                  const ListTile(
                                      dense: true, title: Text('No purchases yet')),
                                for (final s in list)
                                  SaleTile(sale: s),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
    );
  }
}

/// A sale row used in history lists.
class SaleTile extends StatelessWidget {
  const SaleTile({super.key, required this.sale, this.showCustomer = false});
  final Sale sale;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = sale.voided
        ? theme.colorScheme.outline
        : switch (sale.status) {
            PaymentStatus.paid => const Color(0xFF2E7D32),
            PaymentStatus.partial => const Color(0xFFE65100),
            PaymentStatus.unpaid => theme.colorScheme.error,
          };
    return ListTile(
      title: Text(
        [
          sale.receiptNo,
          if (showCustomer && sale.customerName != null) sale.customerName!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: sale.voided
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        '${formatDateTime(sale.soldAt)} · ${sale.itemCount} item${sale.itemCount == 1 ? '' : 's'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 130),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: Money.format(sale.total, sale.currency),
                style: theme.textTheme.titleSmall),
            TextSpan(
              text: '\n${sale.voided ? 'Cancelled' : sale.status.label}',
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ]),
          textAlign: TextAlign.end,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onTap: () => context.push('/sale/${sale.id}'),
    );
  }
}

class CustomerEditScreen extends ConsumerStatefulWidget {
  const CustomerEditScreen({super.key, this.customerId});
  final String? customerId;

  @override
  ConsumerState<CustomerEditScreen> createState() => _CustomerEditScreenState();
}

class _CustomerEditScreenState extends ConsumerState<CustomerEditScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  bool get _isNew => widget.customerId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_isNew) {
      final c = await ref.read(customersRepositoryProvider).getOne(widget.customerId!);
      if (c != null) {
        _name.text = c.name;
        _phone.text = c.phone ?? '';
        _email.text = c.email ?? '';
        _address.text = c.address ?? '';
        _note.text = c.note ?? '';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref.read(customersRepositoryProvider).save(
          id: widget.customerId,
          name: _name.text,
          phone: emptyToNull(_phone.text),
          email: emptyToNull(_email.text),
          address: emptyToNull(_address.text),
          note: emptyToNull(_note.text),
        );
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete customer?',
        message: 'Their past sales are kept. This cannot be undone.');
    if (!ok) return;
    await ref.read(customersRepositoryProvider).delete(widget.customerId!);
    if (mounted) context.go('/more');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New customer' : 'Edit customer'),
        actions: [
          if (!_isNew)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _note,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Note'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Bottom sheet to choose a customer, or add a new one quickly.
/// Returns the chosen customer, or null if cancelled.
Future<Customer?> pickCustomer(BuildContext context, WidgetRef ref) async {
  final all = await ref.read(customersProvider.future);
  if (!context.mounted) return null;
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => _CustomerPicker(all: all),
  );
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker({required this.all});
  final List<Customer> all;

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _search = '';

  Future<void> _quickAdd() async {
    final name = TextEditingController(text: _search);
    final phone = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('New customer'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(c, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(customersRepositoryProvider);
    final id = await repo.save(name: name.text, phone: emptyToNull(phone.text));
    final customer = await repo.getOne(id);
    if (mounted) Navigator.pop(context, customer);
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final shown = widget.all
        .where((c) =>
            q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            (c.phone ?? '').contains(q))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search or type a new name',
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: Text(_search.trim().isEmpty
                  ? 'Add new customer'
                  : 'Add "${_search.trim()}" as new customer'),
              onTap: _quickAdd,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final c in shown)
                    ListTile(
                      leading: CircleAvatar(
                          child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
                      title: Text(c.name),
                      subtitle: c.phone == null ? null : Text(c.phone!),
                      trailing: c.balance > 0
                          ? Text('Owes ${c.balanceLabel}',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))
                          : null,
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
