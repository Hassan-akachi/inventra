import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'local_settings.dart';
import 'utils.dart';

/// Placeholder user id for records made before signing in. The sync
/// connector swaps it for the real user id when uploading.
const localUserId = 'local-user';

/// Who and where the app is running for.
class Session {
  const Session({
    required this.businessId,
    required this.userId,
    required this.deviceCode,
    required this.imagesDir,
    this.email,
    this.linked = false,
  });

  final String businessId;

  /// Signed-in user id once this phone is linked to the cloud, else [localUserId].
  final String userId;
  final String? email;

  /// True when this phone's business is linked to the signed-in account and syncs.
  final bool linked;

  /// Short code used in receipt numbers so two offline phones never clash.
  final String deviceCode;

  /// Folder where item photos are kept on this phone.
  final String imagesDir;

  String imageFile(String name) => p.join(imagesDir, name);

  static Future<Session> load(PowerSyncDatabase db) async {
    final settings = LocalSettings(db);

    var businessId = await settings.get('business_id');
    if (businessId == null) {
      businessId = newId();
      final now = nowIso();
      await db.execute(
        'INSERT INTO businesses (id, name, owner_id, default_currency, report_currency, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [businessId, 'My business', localUserId, 'NGN', 'NGN', now, now],
      );
      await settings.set('business_id', businessId);
    }

    var deviceCode = await settings.get('device_code');
    if (deviceCode == null) {
      deviceCode = newId().replaceAll('-', '').substring(0, 4).toUpperCase();
      await settings.set('device_code', deviceCode);
    }

    final docs = await getApplicationDocumentsDirectory();
    final images = Directory(p.join(docs.path, 'images'));
    await images.create(recursive: true);

    final user = sb.Supabase.instance.client.auth.currentUser;
    final linkedUser = await settings.get('linked_user');
    final linked = user != null && linkedUser == user.id;

    return Session(
      businessId: businessId,
      userId: linked ? user!.id : localUserId,
      email: user?.email,
      linked: linked,
      deviceCode: deviceCode,
      imagesDir: images.path,
    );
  }
}

final sessionProvider = Provider<Session>(
  (ref) => throw UnimplementedError('sessionProvider is set in main()'),
);
