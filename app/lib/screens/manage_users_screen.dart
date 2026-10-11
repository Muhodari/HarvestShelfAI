import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../app_services.dart';
import '../core/theme.dart';
import '../models/user.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/session.dart';
import '../widgets/common.dart';

/// Researcher-only: list, add, change role, reset PIN, delete.
class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  late Future<List<(AppUser, int)>> _users;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _users = _load();
  }

  Future<List<(AppUser, int)>> _load() async {
    final session = SessionScope.of(context);
    final users = await session.auth.listUsers(session.user!);
    return [for (final u in users) (u, await session.auth.scanCount(u.id))];
  }

  void _reload() => setState(() => _users = _load());

  Future<void> _run(Future<void> Function() action, String done) async {
    final t = AppText.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final session = SessionScope.of(context);
    final navigator = Navigator.of(context);
    try {
      await action();
      await session.refresh();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      // A researcher who made themselves a seller can no longer manage users.
      if (session.user?.isResearcher != true) {
        navigator.pop();
        return;
      }
      _reload();
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(t.authError(e.error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final me = SessionScope.userOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.manageUsers)),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Brand.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(
          t.addUser,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        onPressed: _addUser,
      ),
      body: FutureBuilder<List<(AppUser, int)>>(
        future: _users,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.error_outline_rounded,
              title: t.couldNotLoadUsers,
              message: '${snap.error}',
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < users.length; i++) ...[
                      if (i > 0) const Divider(indent: 76),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: UserAvatar(user: users[i].$1),
                        title: Text(
                          users[i].$1.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          [
                            '@${users[i].$1.username}',
                            t.scansCount(users[i].$2),
                            if (users[i].$1.id == me.id) t.you,
                          ].join(' · '),
                        ),
                        trailing: RoleChip(role: users[i].$1.role),
                        onTap: () => _actions(users[i].$1, me),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                t.deletingNote,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _actions(AppUser u, AppUser me) async {
    final t = AppText.of(context);
    final auth = SessionScope.of(context).auth;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: UserAvatar(user: u, radius: 20),
              title: Text(
                u.displayName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('@${u.username}'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text(u.isResearcher ? t.makeSeller : t.makeResearcher),
              onTap: () => Navigator.pop(ctx, 'role'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset_rounded),
              title: Text(t.resetPin),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            if (u.id != me.id)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFB3261E),
                ),
                title: Text(
                  t.deleteAccountAndScans,
                  style: TextStyle(color: Color(0xFFB3261E)),
                ),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'role':
        final role = u.isResearcher ? UserRole.seller : UserRole.researcher;
        await _run(
          () => auth.setRole(me, u.id, role),
          t.roleChanged(u.firstName, role),
        );
      case 'pin':
        final pin = await _askPin(u);
        if (pin != null) {
          await _run(
            () => auth.resetPin(me, u.id, pin),
            t.pinResetFor(u.firstName),
          );
        }
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.deleteQ(u.displayName)),
            content: Text(t.deleteBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB3261E),
                  minimumSize: const Size(96, 44),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t.delete),
              ),
            ],
          ),
        );
        if (ok == true) {
          await _run(() async {
            await AppServices.deleteFiles(await auth.deleteUser(me, u.id));
          }, t.deletedUser(u.displayName));
        }
    }
  }

  Future<String?> _askPin(AppUser u) async {
    final t = AppText.of(context);
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.newPinFor(u.firstName)),
        content: Form(
          key: form,
          child: PinField(
            controller: controller,
            label: t.pin,
            validator: (v) => (AuthService.validatePin(v ?? '') == null
                ? null
                : t.authError(AuthService.validatePin(v ?? '')!)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(ctx, controller.text);
              }
            },
            child: Text(t.reset),
          ),
        ],
      ),
    );
  }

  Future<void> _addUser() async {
    final t = AppText.of(context);
    final session = SessionScope.of(context);
    final result =
        await showModalBottomSheet<(String, String, String, UserRole)>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const _AddUserSheet(),
        );
    if (result == null) return;
    final (name, username, pin, role) = result;
    await _run(
      () => session.auth.createUser(
        session.user!,
        displayName: name,
        username: username,
        pin: pin,
        role: role,
      ),
      t.addedUser(name),
    );
  }
}

class _AddUserSheet extends StatefulWidget {
  const _AddUserSheet();

  @override
  State<_AddUserSheet> createState() => _AddUserSheetState();
}

class _AddUserSheetState extends State<_AddUserSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _pin = TextEditingController();
  UserRole _role = UserRole.seller;

  @override
  void dispose() {
    for (final c in [_name, _username, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.addAUser, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t.name),
              validator: (v) => (AuthService.validateName(v ?? '') == null
                  ? null
                  : t.authError(AuthService.validateName(v ?? '')!)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: t.username,
                hintText: t.usernameHint,
              ),
              validator: (v) => (AuthService.validateUsername(v ?? '') == null
                  ? null
                  : t.authError(AuthService.validateUsername(v ?? '')!)),
            ),
            const SizedBox(height: 12),
            PinField(
              controller: _pin,
              label: t.startingPin,
              validator: (v) => (AuthService.validatePin(v ?? '') == null
                  ? null
                  : t.authError(AuthService.validatePin(v ?? '')!)),
            ),
            const SizedBox(height: 14),
            SegmentedButton<UserRole>(
              segments: [
                for (final r in UserRole.values)
                  ButtonSegment(value: r, label: Text(t.role(r))),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, (
                    _name.text,
                    _username.text,
                    _pin.text,
                    _role,
                  ));
                }
              },
              child: Text(t.addUser),
            ),
          ],
        ),
      ),
    );
  }
}
