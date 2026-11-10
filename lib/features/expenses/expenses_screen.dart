import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../account/membership.dart';
import '../reports/periods.dart';
import '../shops/shop_switcher.dart';
import '../shops/shops.dart';
import 'expenses.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  PeriodKind _kind = PeriodKind.thisMonth;
  bool _allShops = false;

  static const _kinds = [
    PeriodKind.today,
    PeriodKind.thisWeek,
    PeriodKind.thisMonth,
    PeriodKind.lastMonth,
    PeriodKind.thisYear,
  ];

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionsProvider);
    final shop = ref.watch(activeShopProvider).valueOrNull;
    final theme = Theme.of(context);

    if (!perms.canRecordExpenses) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expenses')),
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Expenses are for the owner',
          message: 'Ask the owner to allow "Record expenses" for you.',
        ),
      );
    }
    if (shop == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Expenses')),
        body: const EmptyState(icon: Icons.storefront_outlined, title: 'Add a shop first'),
      );
    }

    final range = rangeFor(_kind);
    final all = _allShops && perms.isOwner;
    final query = (
      shopId: all ? null : shop.id,
      from: dateOnly(range.start),
      to: dateOnly(range.end),
    );
    final expenses = ref.watch(expensesProvider(query));

    return Scaffold(
      appBar: AppBar(title: all ? const Text('All shops') : const ShopSwitcher()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showExpenseSheet(context, ref, shop: shop),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: Column(
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
                for (final k in _kinds)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: expenses,
              builder: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_outlined,
                    title: 'No expenses in ${_kind.label.toLowerCase()}',
                    message: 'Record rent, salaries, fuel and other costs to see your real profit in Reports.',
                  );
                }
                final totals = <String, int>{};
                final byCat = <String, Map<String, int>>{};
                for (final e in list) {
                  totals[e.currency] = (totals[e.currency] ?? 0) + e.amount;
                  final m = byCat.putIfAbsent(e.category, () => {});
                  m[e.currency] = (m[e.currency] ?? 0) + e.amount;
                }
                String fmt(Map<String, int> m) =>
                    m.entries.map((e) => Money.format(e.value, e.key)).join(' + ');
                return ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Spent · ${range.label}', style: theme.textTheme.labelMedium),
                            const SizedBox(height: 4),
                            Text(fmt(totals),
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            for (final c in byCat.entries)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(c.key, style: theme.textTheme.bodySmall)),
                                    Text(fmt(c.value), style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    for (final e in list)
                      ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.receipt_outlined, size: 20)),
                        title: Text(e.category),
                        subtitle: Text([
                          formatDate(e.spentAt),
                          if (all) e.shopName ?? 'Whole business',
                          if (!all && e.shopId == null) 'Whole business',
                          if (e.note != null) e.note!,
                        ].join(' · '),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Text(Money.format(e.amount, e.currency),
                            style: theme.textTheme.titleSmall),
                        onTap: () => showExpenseSheet(context, ref, shop: shop, expense: e),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Add or edit an expense.
Future<void> showExpenseSheet(BuildContext context, WidgetRef ref,
    {required Shop shop, Expense? expense}) async {
  final used = await ref.read(expensesRepositoryProvider).usedCategories();
  if (!context.mounted) return;
  final suggestions = {...used, ...expenseCategories}.where((c) => c.isNotEmpty).toList();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ExpenseForm(shop: shop, expense: expense, suggestions: suggestions),
  );
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm({required this.shop, required this.suggestions, this.expense});
  final Shop shop;
  final Expense? expense;
  final List<String> suggestions;

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _form = GlobalKey<FormState>();
  late final _category = TextEditingController(text: widget.expense?.category ?? '');
  late final _amount = TextEditingController(text: Money.toInput(widget.expense?.amount));
  late final _note = TextEditingController(text: widget.expense?.note ?? '');
  late String _currency = widget.expense?.currency ?? widget.shop.currency;
  late DateTime _date = DateTime.tryParse(widget.expense?.spentAt ?? '') ?? DateTime.now();
  late bool _wholeBusiness = widget.expense != null && widget.expense!.shopId == null;
  bool _saving = false;

  @override
  void dispose() {
    _category.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref.read(expensesRepositoryProvider).save(
          id: widget.expense?.id,
          shopId: _wholeBusiness ? null : (widget.expense?.shopId ?? widget.shop.id),
          category: _category.text,
          amount: Money.parse(_amount.text)!,
          currency: _currency,
          spentAt: dateOnly(_date),
          note: emptyToNull(_note.text),
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete this expense?', message: 'This cannot be undone.');
    if (!ok) return;
    await ref.read(expensesRepositoryProvider).delete(widget.expense!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = ref.watch(permissionsProvider).isOwner;
    final q = _category.text.trim().toLowerCase();
    final chips = widget.suggestions
        .where((c) => q.isEmpty || c.toLowerCase().contains(q))
        .take(12)
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(widget.expense == null ? 'New expense' : 'Edit expense',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _category,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'What was it for?'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter or pick a type' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in chips)
                    ActionChip(
                      label: Text(c),
                      onPressed: () => setState(() => _category.text = c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        prefixText: '${supportedCurrencies[_currency] ?? ''} ',
                      ),
                      validator: (v) {
                        final m = Money.parse(v ?? '');
                        return (m == null || m <= 0) ? 'Enter an amount' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      items: [
                        for (final c in supportedCurrencies.keys)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _currency = v ?? _currency),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Date'),
                subtitle: Text(formatDate(dateOnly(_date))),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(now.year - 5),
                    lastDate: now,
                  );
                  if (d != null) setState(() => _date = d);
                },
              ),
              if (isOwner)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('For the whole business'),
                  subtitle: Text(_wholeBusiness
                      ? 'Not tied to one shop (e.g. your salary, head-office rent)'
                      : 'Counted against ${widget.shop.name}'),
                  value: _wholeBusiness,
                  onChanged: (v) => setState(() => _wholeBusiness = v),
                ),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
              if (widget.expense != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  onPressed: _delete,
                  child: const Text('Delete'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
