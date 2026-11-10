import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../app/root.dart';
import '../../core/db/database.dart';
import '../../core/local_settings.dart';
import '../../core/session.dart';
import '../../core/sync/sync.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';
import '../business/business.dart';
import 'account_service.dart';
import 'membership.dart';

/// Sign in, link this phone to a business, and see sync status.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _creating = false; // sign-up form instead of sign-in
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  /// Null = not checked yet. Filled after sign-in when the phone isn't linked.
  List<CloudBusiness>? _cloud;

  AccountService get _svc => ref.read(accountServiceProvider);
  sb.User? get _user => sb.Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    if (_user != null && !ref.read(sessionProvider).linked) {
      Future.microtask(_afterSignIn);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _restart() {
    if (!mounted) return;
    AppRoot.restart(context);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      if (_creating) {
        final signedIn = await _svc.signUp(_email.text, _password.text);
        if (!signedIn) {
          if (mounted) {
            setState(() => _error =
                'Check your email and tap the confirmation link, then sign in here.');
            setState(() => _creating = false);
          }
          return;
        }
      } else {
        await _svc.signIn(_email.text, _password.text);
      }
      await _afterSignIn();
    });
  }

  /// Decide what to do with this phone after signing in.
  Future<void> _afterSignIn() async {
    await _run(() async {
      final list = await _svc.myBusinesses();
      final localId = ref.read(sessionProvider).businessId;
      if (list.any((b) => b.id == localId)) {
        await _svc.linkThisPhone();
        _restart();
        return;
      }
      if (mounted) setState(() => _cloud = list);
    });
  }

  Future<void> _useCloudBusiness(String id, String name) async {
    if (await _svc.localHasData()) {
      if (!mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Replace this phone\'s data?',
        message: 'This phone has shops, items or sales that are not part of $name. '
            'They will be removed and $name will be downloaded from the cloud.',
        action: 'Replace',
      );
      if (!ok) return;
    }
    await _run(() async {
      await _svc.switchToBusiness(id);
      _restart();
    });
  }

  Future<void> _createBusiness() async {
    final business = ref.read(businessProvider).valueOrNull;
    final name = TextEditingController(
        text: business?.name == 'My business' ? '' : business?.name ?? '');
    var currency = business?.defaultCurrency ?? 'NGN';
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          scrollable: true,
          title: const Text('Create your business'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Everything already on this phone becomes part of this business and is backed up.'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Business name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                CurrencyDropdown(
                  value: currency,
                  label: 'Main currency',
                  onChanged: (v) => setState(() => currency = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(c, true);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _svc.createBusinessFromThisPhone(name.text, currency);
      _restart();
    });
  }

  Future<void> _join() async {
    final code = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: const Text('Join a business'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ask the owner for an invite code (Team → Invite staff).'),
            const SizedBox(height: 16),
            TextField(
              controller: code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Invite code'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, code.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (entered == null || entered.isEmpty) return;
    String? businessId;
    await _run(() async => businessId = await _svc.joinWithCode(entered));
    if (businessId != null) await _useCloudBusiness(businessId!, 'the business');
  }

  Future<void> _signOut() async {
    final pending = ref.read(pendingUploadsProvider).valueOrNull ?? 0;
    final ok = await confirmDialog(
      context,
      title: 'Sign out?',
      message: pending > 0
          ? '$pending changes have not been backed up yet. They stay on this phone and upload when you sign in again.'
          : 'Your data stays on this phone. Sign in again to sync.',
      action: 'Sign out',
    );
    if (!ok) return;
    await _run(() async {
      await _svc.signOut();
      _restart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('Account and sync')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: Image.asset('assets/branding/inventra_logo.png', width: 88, height: 88),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (user == null)
            _signInForm(context)
          else if (session.linked)
            _linkedView(context, user)
          else
            _setupView(context, user),
        ],
      ),
    );
  }

  Widget _signInForm(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_creating ? 'Create an account' : 'Sign in',
              style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Back up your data, use more than one phone, and add staff. '
            'Inventra keeps working without internet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter your email' : null,
          ),
          const SizedBox(height: 12),
        TextFormField(
          controller: _password,
          obscureText: _obscurePassword,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          validator: (v) =>
          (v == null || v.length < 6) ? 'At least 6 characters' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_creating ? 'Create account' : 'Sign in'),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _creating = !_creating),
            child: Text(_creating
                ? 'I already have an account'
                : 'New here? Create an account'),
          ),
        ],
      ),
    );
  }

  Widget _setupView(BuildContext context, sb.User user) {
    final theme = Theme.of(context);
    final cloud = _cloud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Signed in as ${user.email}', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (cloud == null)
          const SizedBox.shrink()
        else ...[
          if (cloud.isNotEmpty) ...[
            Text('Your businesses', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final b in cloud)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: Text(b.name),
                  subtitle: Text('${b.role == 'owner' ? 'Owner' : 'Staff'} · use on this phone'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _useCloudBusiness(b.id, b.name),
                ),
              ),
            const SizedBox(height: 16),
          ],
          Text(cloud.isEmpty ? 'Set up this phone' : 'Or', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('I own the business'),
              subtitle: const Text('Create it in the cloud from this phone\'s data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _createBusiness,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('I work for a business'),
              subtitle: const Text('Join with an invite code from the owner'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _join,
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextButton(
          onPressed: _busy ? null : _signOut,
          child: const Text('Sign out'),
        ),
      ],
    );
  }

  Widget _linkedView(BuildContext context, sb.User user) {
    final theme = Theme.of(context);
    final business = ref.watch(businessProvider).valueOrNull;
    final perms = ref.watch(permissionsProvider);
    final status = ref.watch(syncStatusProvider).valueOrNull;
    final pending = ref.watch(pendingUploadsProvider).valueOrNull ?? 0;

    final String statusText;
    final IconData statusIcon;
    final Color statusColor;
    if (status == null || !status.connected) {
      statusText = 'Offline — changes are saved on this phone and sync when you reconnect';
      statusIcon = Icons.cloud_off_outlined;
      statusColor = theme.colorScheme.outline;
    } else if (status.uploading || status.downloading || pending > 0) {
      statusText = 'Syncing…';
      statusIcon = Icons.cloud_sync_outlined;
      statusColor = theme.colorScheme.primary;
    } else {
      statusText = 'Up to date';
      statusIcon = Icons.cloud_done_outlined;
      statusColor = const Color(0xFF2E7D32);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(business?.name ?? 'Your business',
            textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        Text('${user.email} · ${perms.isOwner ? 'Owner' : 'Staff'}',
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(statusIcon, color: statusColor),
                title: Text(statusText),
                subtitle: Text([
                  if (status?.lastSyncedAt != null)
                    'Last synced ${formatDateTime(status!.lastSyncedAt!.toUtc().toIso8601String())}',
                  if (pending > 0) '$pending change${pending == 1 ? '' : 's'} waiting to upload',
                ].join('\n')),
              ),
              const _LastError(),
            ],
          ),
        ),
        if (perms.canManageTeam)
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Team'),
              subtitle: const Text('Invite staff, set their shops and permissions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/team'),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy ? null : _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}

/// Shows the last change the server refused, if any.
class _LastError extends ConsumerStatefulWidget {
  const _LastError();

  @override
  ConsumerState<_LastError> createState() => _LastErrorState();
}

class _LastErrorState extends ConsumerState<_LastError> {
  String? _value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await LocalSettings(ref.read(databaseProvider)).get('last_sync_error');
    if (mounted) setState(() => _value = v);
  }

  Future<void> _dismiss() async {
    await LocalSettings(ref.read(databaseProvider)).remove('last_sync_error');
    if (mounted) setState(() => _value = null);
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    if (v == null || v.isEmpty) return const SizedBox.shrink();
    final parts = v.split('|');
    return ListTile(
      dense: true,
      leading: Icon(Icons.warning_amber_outlined,
          color: Theme.of(context).colorScheme.error),
      title: const Text('A change was refused by the server'),
      subtitle: Text(parts.length >= 4 ? '${parts[1]}: ${parts.sublist(3).join('|')}' : v),
      trailing: IconButton(
        tooltip: 'Dismiss',
        icon: const Icon(Icons.close),
        onPressed: _dismiss,
      ),
    );
  }
}
