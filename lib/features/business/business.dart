import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../core/db/database.dart';
import '../../core/session.dart';
import '../../core/utils.dart';

/// Business details printed on receipts.
class Business {
  const Business({
    required this.id,
    required this.name,
    this.ownerId,
    this.defaultCurrency = 'NGN',
    this.phone,
    this.address,
    this.receiptFooter,
  });

  final String id;
  final String name;
  final String? ownerId;
  final String defaultCurrency;
  final String? phone;
  final String? address;
  final String? receiptFooter;

  factory Business.fromRow(Map<String, dynamic> r) => Business(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'My business',
        ownerId: r['owner_id'] as String?,
        defaultCurrency: (r['default_currency'] as String?) ?? 'NGN',
        phone: r['phone'] as String?,
        address: r['address'] as String?,
        receiptFooter: r['receipt_footer'] as String?,
      );
}

class BusinessRepository {
  BusinessRepository(this._db, this._session);
  final PowerSyncDatabase _db;
  final Session _session;

  Stream<Business?> watch() => _db
      .watch('SELECT * FROM businesses WHERE id = ?',
          parameters: [_session.businessId])
      .map((rs) => rs.isEmpty ? null : Business.fromRow(rs.first));

  Future<void> update({
    required String name,
    String? phone,
    String? address,
    String? receiptFooter,
  }) async {
    await _db.execute(
      'UPDATE businesses SET name = ?, phone = ?, address = ?, receipt_footer = ?, updated_at = ? WHERE id = ?',
      [name.trim(), phone, address, receiptFooter, nowIso(), _session.businessId],
    );
  }
}

final businessRepositoryProvider = Provider<BusinessRepository>((ref) =>
    BusinessRepository(ref.watch(databaseProvider), ref.watch(sessionProvider)));

final businessProvider = StreamProvider<Business?>(
    (ref) => ref.watch(businessRepositoryProvider).watch());

/// Edit the business name, phone, address and receipt footer.
Future<void> showBusinessDialog(
    BuildContext context, WidgetRef ref, Business? business) async {
  final name = TextEditingController(text: business?.name ?? '');
  final phone = TextEditingController(text: business?.phone ?? '');
  final address = TextEditingController(text: business?.address ?? '');
  final footer = TextEditingController(
      text: business?.receiptFooter ?? 'Thank you for your patronage!');
  final formKey = GlobalKey<FormState>();

  final saved = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      scrollable: true,
      title: const Text('Business details'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: address,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: footer,
              maxLines: 2,
              decoration:
                  const InputDecoration(labelText: 'Message at the bottom of receipts'),
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
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (saved != true) return;
  await ref.read(businessRepositoryProvider).update(
        name: name.text,
        phone: emptyToNull(phone.text),
        address: emptyToNull(address.text),
        receiptFooter: emptyToNull(footer.text),
      );
}
