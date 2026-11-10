import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../inventory/restocks.dart';
import '../inventory/restocks_screen.dart';
import 'suppliers.dart';
import '../account/membership.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Suppliers')),
      floatingActionButton: !ref.watch(permissionsProvider).canEditItems
          ? null
          : FloatingActionButton.extended(
        onPressed: () => context.push('/supplier/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add supplier'),
      ),
      body: AsyncBody(
        value: suppliers,
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'No suppliers yet',
              message: 'Add the companies you buy stock from.',
            );
          }
          final q = _search.toLowerCase();
          final shown = list
              .where((s) =>
                  q.isEmpty ||
                  s.companyName.toLowerCase().contains(q) ||
                  (s.contactName ?? '').toLowerCase().contains(q) ||
                  (s.phone ?? '').contains(q))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search suppliers',
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final s in shown)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(s.companyName.isEmpty
                              ? '?'
                              : s.companyName[0].toUpperCase()),
                        ),
                        title: Text(s.companyName),
                        subtitle: Text([
                          if (s.contactName != null) s.contactName!,
                          if (s.phone != null) s.phone!,
                          '${s.itemCount} item${s.itemCount == 1 ? '' : 's'}',
                        ].join(' · ')),
                        onTap: () => context.push('/supplier/${s.id}'),
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

class SupplierEditScreen extends ConsumerStatefulWidget {
  const SupplierEditScreen({super.key, this.supplierId});
  final String? supplierId;

  @override
  ConsumerState<SupplierEditScreen> createState() => _SupplierEditScreenState();
}

class _SupplierEditScreenState extends ConsumerState<SupplierEditScreen> {
  final _form = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  bool get _isNew => widget.supplierId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_isNew) {
      final s =
          await ref.read(suppliersRepositoryProvider).getOne(widget.supplierId!);
      if (s != null) {
        _company.text = s.companyName;
        _contact.text = s.contactName ?? '';
        _phone.text = s.phone ?? '';
        _email.text = s.email ?? '';
        _address.text = s.address ?? '';
        _note.text = s.note ?? '';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_company, _contact, _phone, _email, _address, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref.read(suppliersRepositoryProvider).save(
          id: widget.supplierId,
          companyName: _company.text,
          contactName: emptyToNull(_contact.text),
          phone: emptyToNull(_phone.text),
          email: emptyToNull(_email.text),
          address: emptyToNull(_address.text),
          note: emptyToNull(_note.text),
        );
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete supplier?',
        message: 'It will be removed from all items. This cannot be undone.');
    if (!ok) return;
    await ref.read(suppliersRepositoryProvider).delete(widget.supplierId!);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New supplier' : 'Edit supplier'),
        actions: [
          if (!_isNew)
            IconButton(
                icon: const Icon(Icons.delete_outline), onPressed: _delete),
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
                    controller: _company,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Company name *'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter the company name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contact,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Contact person'),
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
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty || t.contains('@')) return null;
                      return 'Enter a valid email';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Business address'),
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
                  if (!_isNew) _Deliveries(supplierId: widget.supplierId!),
                ],
              ),
            ),
    );
  }
}

class _Deliveries extends ConsumerWidget {
  const _Deliveries({required this.supplierId});
  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(supplierRestocksProvider(supplierId)).valueOrNull ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Deliveries from this supplier',
              style: Theme.of(context).textTheme.titleMedium),
          for (final r in list) RestockTile(restock: r, showItem: true),
        ],
      ),
    );
  }
}
