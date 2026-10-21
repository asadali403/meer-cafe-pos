import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../utils/errors.dart';
import '../../widgets/common.dart';
import 'auth_layout.dart';

/// Forced after an admin creates/resets an account; also reachable from the sidebar.
class ChangePasswordScreen extends StatefulWidget {
  final bool forced;
  const ChangePasswordScreen({super.key, this.forced = false});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_new.text != _new2.text) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppController>();
    try {
      final u = await app.users.changePassword(app.user!, _current.text, _new.text);
      if (widget.forced) {
        app.signIn(u);
      } else if (mounted) {
        showSnack(context, 'Password changed.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          const Text('Change password', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            widget.forced
                ? 'For security, please choose your own password before continuing.'
                : 'Choose a new password for your account.',
            style: const TextStyle(color: MeerColors.muted),
          ),
          const SizedBox(height: 24),
          TextField(
              controller: _current,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(labelText: widget.forced ? 'Temporary password' : 'Current password')),
          const SizedBox(height: 14),
          TextField(
              controller: _new,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'New password', helperText: 'At least 8 characters with letters and numbers')),
          const SizedBox(height: 14),
          TextField(
            controller: _new2,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm new password'),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: MeerColors.danger, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _busy ? null : _save, child: const Text('Save new password')),
          if (widget.forced)
            TextButton(onPressed: () => context.read<AppController>().signOut(), child: const Text('Sign out')),
        ]),
      ),
    );
    if (widget.forced) return AuthLayout(child: form);
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: form)),
    );
  }
}
