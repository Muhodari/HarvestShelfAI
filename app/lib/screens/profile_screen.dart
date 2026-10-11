import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../app_services.dart';
import '../core/theme.dart';
import '../models/user.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/session.dart';
import '../services/export_service.dart';
import '../widgets/common.dart';
import 'change_pin_screen.dart';
import 'manage_users_screen.dart';

/// Account, research tools (researchers), data and about.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final session = SessionScope.of(context);
    final user = session.user!;
    final meta = Services.of(context).meta;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(t.profile)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                UserAvatar(user: user, radius: 30),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName, style: text.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        '@${user.username} · ${t.role(user.role)}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SectionLabel(t.account),
          _Group(
            children: [
              _Item(
                icon: Icons.edit_outlined,
                title: t.editName,
                onTap: () => _editName(context, user),
              ),
              _Item(
                icon: Icons.password_rounded,
                title: t.changePin,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChangePinScreen()),
                ),
              ),
              _Item(
                icon: Icons.translate_rounded,
                title: t.language,
                subtitle: LanguageScope.controllerOf(
                  context,
                ).language.nativeName,
                onTap: () => chooseLanguage(context),
              ),
            ],
          ),
          if (user.isResearcher) ...[
            SectionLabel(t.research),
            _Group(
              children: [
                _Item(
                  icon: Icons.group_outlined,
                  title: t.manageUsers,
                  subtitle: t.manageUsersSub,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ManageUsersScreen(),
                    ),
                  ),
                ),
                _Item(
                  icon: Icons.download_rounded,
                  title: t.exportLog,
                  subtitle: t.exportSub,
                  onTap: () => _export(context),
                ),
                _Item(
                  icon: Icons.memory_rounded,
                  title: t.model,
                  subtitle: t.modelSub(
                    meta.modelVersion,
                    meta.tConf,
                    meta.tSpoil,
                  ),
                ),
              ],
            ),
          ],
          SectionLabel(t.myData),
          _Group(
            children: [
              _Item(
                icon: Icons.delete_sweep_outlined,
                title: t.clearHistory,
                color: Brand.danger,
                onTap: () => _clear(context, user),
              ),
            ],
          ),
          SectionLabel(t.about),
          _Group(
            children: [
              _Item(
                icon: Icons.info_outline_rounded,
                title: t.appName,
                subtitle: '${t.worksOffline} ${t.disclaimer}',
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            key: const Key('logout'),
            style: TextButton.styleFrom(
              foregroundColor: Brand.danger,
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.logout_rounded),
            label: Text(t.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final t = AppText.of(context);
    final session = SessionScope.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.logoutQ),
        content: Text(t.logoutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.logout),
          ),
        ],
      ),
    );
    if (ok != true) return;
    navigator.popUntil((r) => r.isFirst);
    await session.logout();
  }

  Future<void> _editName(BuildContext context, AppUser user) async {
    final t = AppText.of(context);
    final session = SessionScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: user.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.editName),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: t.fullName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(t.save),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await session.auth.updateName(user, name);
      await session.refresh();
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(t.authError(e.error))));
    }
  }

  Future<void> _export(BuildContext context) async {
    final t = AppText.of(context);
    final services = Services.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await writeCsvExport(await services.scans.allForExport());
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(t.savedTo(file.path)),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(t.exportFailed(e))));
    }
  }

  Future<void> _clear(BuildContext context, AppUser user) async {
    final t = AppText.of(context);
    final services = Services.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.clearQ),
        content: Text(t.clearBody),
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
    if (ok != true) return;
    final paths = await services.scans.deleteForUser(user.id);
    await AppServices.deleteFiles(paths);
    services.triage.changes.value++;
    messenger.showSnackBar(
      SnackBar(content: Text(t.deletedScans(paths.length))),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(indent: 64),
          children[i],
        ],
      ],
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
    leading: Icon(icon, color: color ?? Brand.inkSoft, size: 22),
    minLeadingWidth: 28,
    title: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: color ?? Brand.ink,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
    trailing: onTap == null
        ? null
        : const Icon(Icons.chevron_right_rounded, color: Brand.inkSoft),
    onTap: onTap,
  );
}

/// Bottom sheet to switch between English and Kinyarwanda.
Future<void> chooseLanguage(BuildContext context) async {
  final controller = LanguageScope.controllerOf(context);
  final chosen = await showModalBottomSheet<AppLanguage>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in AppLanguage.values)
            ListTile(
              title: Text(
                l.nativeName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: l == controller.language
                  ? const Icon(Icons.check_rounded, color: Brand.green)
                  : null,
              onTap: () => Navigator.pop(ctx, l),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (chosen != null) await controller.set(chosen);
}
