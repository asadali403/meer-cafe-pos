import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../services/backup_service.dart';
import '../../utils/dates.dart';
import '../../widgets/common.dart';

/// Shown when the database cannot be opened or fails its integrity check.
/// Offers restoring from an automatic or chosen backup. The damaged file is kept.
class DatabaseErrorScreen extends StatefulWidget {
  const DatabaseErrorScreen({super.key});
  @override
  State<DatabaseErrorScreen> createState() => _DatabaseErrorScreenState();
}

class _DatabaseErrorScreenState extends State<DatabaseErrorScreen> {
  List<BackupInfo> _backups = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    BackupService.list().then((b) {
      if (mounted) setState(() => _backups = b);
    });
  }

  Future<void> _restore(String path) async {
    final ok = await confirm(context, 'Restore backup?',
        'The damaged database will be kept in the backups folder and replaced by:\n$path', ok: 'Restore');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AppController>().restoreWithoutOpenDatabase(path);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: MeerColors.danger, size: 36),
                  SizedBox(width: 12),
                  Text('Database problem', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 12),
                Text(app.errorMessage ?? 'Unknown error'),
                const SizedBox(height: 8),
                Text('Database file: ${app.dbPath ?? '-'}', style: const TextStyle(color: MeerColors.muted, fontSize: 12)),
                const SizedBox(height: 20),
                const Text('Restore from a backup:', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_backups.isEmpty) const Text('No automatic backups found.', style: TextStyle(color: MeerColors.muted)),
                for (final b in _backups.take(5))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.backup_outlined),
                    title: Text(b.name),
                    subtitle: Text(Dates.display(Dates.db(b.modified))),
                    trailing: TextButton(onPressed: _busy ? null : () => _restore(b.path), child: const Text('Restore')),
                  ),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final f = await openFile(acceptedTypeGroups: const [
                              XTypeGroup(label: 'Meer Cafe backup', extensions: ['db'])
                            ]);
                            if (f != null) await _restore(f.path);
                          },
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose backup file...'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => app.init(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
