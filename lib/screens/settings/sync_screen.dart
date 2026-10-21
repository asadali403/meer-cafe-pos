import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../services/sync_transport.dart';
import '../../utils/dates.dart';
import '../../widgets/common.dart';

/// Google Sheets configuration, status counts, Sync Now and error list (admin only).
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  late final _url = TextEditingController();
  late final _secret = TextEditingController();
  bool _enabled = false;
  bool _showSecret = false;
  bool _testing = false;
  List<Map<String, Object?>> _failed = [];
  List<Map<String, Object?>> _logs = [];

  @override
  void initState() {
    super.initState();
    final s = context.read<AppController>().settings;
    _url.text = s.syncUrl;
    _secret.text = s.syncSecret;
    _enabled = s.syncEnabled;
    _loadLists();
  }

  Future<void> _loadLists() async {
    final sync = context.read<AppController>().sync;
    if (sync == null) return;
    await sync.refreshCounts();
    final f = await sync.problemItems();
    final l = await sync.recentLogs();
    if (mounted) {
      setState(() {
        _failed = f;
        _logs = l;
      });
    }
  }

  String? _validate() {
    final url = _url.text.trim();
    if (_enabled && !url.startsWith('https://script.google.com/')) {
      return 'The Web App URL should start with https://script.google.com/';
    }
    if (_enabled && _secret.text.trim().length < 16) return 'The secret must be at least 16 characters.';
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) return showSnack(context, err, error: true);
    final app = context.read<AppController>();
    try {
      await app.saveSettings({
        'sync_url': _url.text.trim(),
        'sync_secret': _secret.text.trim(),
        'sync_enabled': _enabled ? '1' : '0',
      });
      if (mounted) showSnack(context, 'Sync settings saved.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _test() async {
    final url = _url.text.trim();
    if (!url.startsWith('https://')) return showSnack(context, 'Enter the Web App URL first.', error: true);
    setState(() => _testing = true);
    try {
      final msg = await AppsScriptTransport(url: url, secret: _secret.text.trim()).ping();
      if (mounted) showSnack(context, msg);
    } catch (e) {
      if (mounted) showSnack(context, 'Test failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _syncNow() async {
    final sync = context.read<AppController>().sync;
    if (sync == null) return;
    final msg = await sync.run(trigger: 'manual', force: true);
    if (mounted) showSnack(context, msg, error: msg.startsWith('Sync failed') || msg.contains('error'));
    _loadLists();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<AppController>().sync;
    return ListView(children: [
      PageHeader(
        title: 'Google Sheets Sync',
        subtitle: 'Bills are always saved on this laptop first. Sync uploads them when internet is available.',
        actions: [
          if (sync != null)
            ListenableBuilder(
              listenable: sync,
              builder: (_, _) => ElevatedButton.icon(
                onPressed: sync.running ? null : _syncNow,
                icon: sync.running
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: Text(sync.running ? 'Syncing...' : 'Sync Now'),
              ),
            ),
        ],
      ),
      if (sync != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ListenableBuilder(
            listenable: sync,
            builder: (_, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: StatCard(label: 'Pending', value: '${sync.counts.pending}', icon: Icons.schedule)),
                const SizedBox(width: 14),
                Expanded(child: StatCard(label: 'Failed (will retry)', value: '${sync.counts.failed}', icon: Icons.error_outline)),
                const SizedBox(width: 14),
                Expanded(child: StatCard(label: 'Synced', value: '${sync.counts.synced}', icon: Icons.cloud_done_outlined, highlight: true)),
              ]),
              const SizedBox(height: 10),
              Text(
                [
                  if (sync.lastRunAt != null) 'Last attempt: ${Dates.display(sync.lastRunAt!)}',
                  if (sync.lastMessage.isNotEmpty) sync.lastMessage,
                ].join('  ·  '),
                style: const TextStyle(color: MeerColors.muted),
              ),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(28),
        child: Wrap(spacing: 16, runSpacing: 16, children: [
          SizedBox(
            width: 560,
            child: SectionCard(
              title: 'Connection',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                  title: const Text('Enable automatic Google Sheets sync'),
                  subtitle: const Text('Runs at startup, every minute, and when the internet comes back.'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                      labelText: 'Apps Script Web App URL', hintText: 'https://script.google.com/macros/s/.../exec'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _secret,
                  obscureText: !_showSecret,
                  decoration: InputDecoration(
                    labelText: 'Sync secret (SYNC_SECRET from the Apps Script log)',
                    suffixIcon: IconButton(
                      icon: Icon(_showSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _showSecret = !_showSecret),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The secret is stored only in this laptop\'s local database and in your Google Apps Script properties. '
                  'It is never part of the app\'s source code. See docs\\GOOGLE_SHEETS_SETUP.md.',
                  style: TextStyle(color: MeerColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save')),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: const Icon(Icons.wifi_tethering),
                    label: Text(_testing ? 'Testing...' : 'Test connection'),
                  ),
                ]),
              ]),
            ),
          ),
          SizedBox(
            width: 560,
            child: SectionCard(
              title: 'Failed records (${_failed.length})',
              actions: [IconButton(onPressed: _loadLists, icon: const Icon(Icons.refresh))],
              child: _failed.isEmpty
                  ? const Text('No failed records.', style: TextStyle(color: MeerColors.muted))
                  : Column(children: [
                      for (final f in _failed.take(30))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.error_outline, color: MeerColors.danger),
                          title: Text('${f['entity_type']} · ${f['entity_id']}'),
                          subtitle: Text('${f['last_error'] ?? ''}\nAttempts: ${f['attempts']} · next retry ${Dates.display('${f['next_attempt_at']}')}'),
                        ),
                    ]),
            ),
          ),
          SizedBox(
            width: 1136,
            child: SectionCard(
              title: 'Sync log',
              child: SimpleTable(
                columns: const ['Started', 'Trigger', 'Sent', 'OK', 'Failed', 'Message'],
                rows: [
                  for (final l in _logs)
                    [
                      Dates.display('${l['started_at']}'),
                      '${l['trigger']}',
                      '${l['sent']}',
                      '${l['succeeded']}',
                      '${l['failed']}',
                      '${l['message']}',
                    ]
                ],
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}
