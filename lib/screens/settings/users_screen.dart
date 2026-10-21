import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../models/user.dart';
import '../../utils/dates.dart';
import '../../utils/errors.dart';
import '../../widgets/common.dart';

/// Admin-only user management. New/reset accounts must change password at next login.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    try {
      final u = await app.users.list(app.user!);
      if (mounted) setState(() => _users = u);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _add() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _UserDialog());
    if (ok == true) {
      _load();
      if (mounted) showSnack(context, 'User created. They must change the temporary password at first login.');
    }
  }

  Future<void> _edit(AppUser u) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _UserDialog(user: u));
    if (ok == true) _load();
  }

  Future<void> _reset(AppUser u) async {
    final ctl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Reset password — ${u.username}'),
        content: TextField(
          controller: ctl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Temporary password', helperText: 'User must change it at next login'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Reset')),
        ],
      ),
    );
    if (pw == null || !mounted) return;
    final app = context.read<AppController>();
    try {
      await app.users.resetPassword(app.user!, u.id, pw);
      if (mounted) showSnack(context, 'Password reset.');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Users',
        subtitle: 'Admin and cashier accounts',
        actions: [ElevatedButton.icon(onPressed: _add, icon: const Icon(Icons.person_add_alt), label: const Text('Add user'))],
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Card(
            child: ListView.separated(
              itemCount: _users.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (_, i) {
                final u = _users[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: u.isAdmin ? MeerColors.black : const Color(0xFFFBF3DA),
                    foregroundColor: u.isAdmin ? MeerColors.gold : MeerColors.black,
                    child: Icon(u.isAdmin ? Icons.admin_panel_settings_outlined : Icons.person_outline),
                  ),
                  title: Text('${u.displayName}  (${u.username})', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    u.role.label,
                    u.active ? 'Active' : 'Deactivated',
                    if (u.mustChangePassword) 'Must change password',
                    'Last login: ${u.lastLoginAt == null ? 'never' : Dates.display(u.lastLoginAt!)}',
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: () => _reset(u), child: const Text('Reset password')),
                    IconButton(onPressed: () => _edit(u), icon: const Icon(Icons.edit_outlined), tooltip: 'Edit'),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    ]);
  }
}

class _UserDialog extends StatefulWidget {
  final AppUser? user;
  const _UserDialog({this.user});
  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  late final _username = TextEditingController(text: widget.user?.username ?? '');
  late final _name = TextEditingController(text: widget.user?.displayName ?? '');
  final _pass = TextEditingController();
  late UserRole _role = widget.user?.role ?? UserRole.cashier;
  late bool _active = widget.user?.active ?? true;
  String? _error;

  Future<void> _save() async {
    final app = context.read<AppController>();
    try {
      if (widget.user == null) {
        await app.users.create(app.user!,
            username: _username.text, displayName: _name.text, tempPassword: _pass.text, role: _role);
      } else {
        await app.users.update(app.user!, widget.user!.id, displayName: _name.text, role: _role, active: _active);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.user == null;
    return AlertDialog(
      title: Text(isNew ? 'Add user' : 'Edit ${widget.user!.username}'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _username, enabled: isNew, decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Display name (printed on receipts)')),
          const SizedBox(height: 12),
          if (isNew) ...[
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Temporary password', helperText: 'Min 8 chars, letters and numbers'),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<UserRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
            onChanged: (v) => setState(() => _role = v ?? UserRole.cashier),
          ),
          if (!isNew)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Active'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: MeerColors.danger)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
