import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../utils/errors.dart';
import 'auth_layout.dart';

/// Shown only when the database has no users. Creates the first admin account.
/// No default username/password exists anywhere in the app.
class FirstRunScreen extends StatefulWidget {
  const FirstRunScreen({super.key});
  @override
  State<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends State<FirstRunScreen> {
  final _user = TextEditingController(text: 'admin');
  final _name = TextEditingController(text: 'Administrator');
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _sample = true;
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    if (_pass.text != _pass2.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppController>();
    try {
      final admin = await app.users.createInitialAdmin(_user.text, _name.text, _pass.text);
      if (_sample) await app.products.loadMenu(admin);
      app.signIn(admin);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('First-time setup', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
                'Create the administrator account. Keep this password private — the admin controls prices, users and settings.',
                style: TextStyle(color: MeerColors.muted)),
            const SizedBox(height: 24),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'Admin username')),
            const SizedBox(height: 14),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Display name')),
            const SizedBox(height: 14),
            TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Password', helperText: 'At least 8 characters with letters and numbers')),
            const SizedBox(height: 14),
            TextField(
              controller: _pass2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _sample,
              onChanged: (v) => setState(() => _sample = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text("Load Meer's Cafe menu (all items, deals and prices — editable later)"),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: MeerColors.danger, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _busy ? null : _create,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create admin & continue'),
            ),
          ]),
        ),
      ),
    );
  }
}
