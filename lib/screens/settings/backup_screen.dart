import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../database/app_database.dart';
import '../../services/backup_service.dart';
import '../../utils/dates.dart';
import '../../widgets/common.dart';

/// Backup & restore (admin only).
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<BackupInfo> _backups = [];
  String _backupDir = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await AppDatabase.backupDir();
    final list = await BackupService.list();
    if (mounted) {
      setState(() {
        _backupDir = dir.path;
        _backups = list;
      });
    }
  }

  Future<void> _backupNow({bool chooseFolder = false}) async {
    final app = context.read<AppController>();
    String? folder = _backupDir;
    if (chooseFolder) {
      folder = await getDirectoryPath(confirmButtonText: 'Back up here');
      if (folder == null) return;
    }
    setState(() => _busy = true);
    try {
      final path = await app.backups.backupToFolder(folder);
      if (mounted) showSnack(context, 'Backup saved: $path');
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(String path) async {
    final ok = await confirm(
      context,
      'Restore this backup?',
      'All current data will be replaced by the backup:\n$path\n\n'
          'A copy of the current database is saved first (pre_restore_*.db). You will be signed out.',
      ok: 'Restore',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.read<AppController>().restoreFrom(path);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    return ListView(children: [
      PageHeader(
        title: 'Backup & Restore',
        subtitle: 'An automatic backup is made every day when the app starts (last 30 kept).',
        actions: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _backupNow(chooseFolder: true),
            icon: const Icon(Icons.usb_outlined),
            label: const Text('Back up to USB / folder...'),
          ),
          ElevatedButton.icon(
            onPressed: _busy ? null : _backupNow,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Back up now'),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: SectionCard(
          title: 'Locations',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText('Database: ${app.dbPath}'),
            const SizedBox(height: 4),
            SelectableText('Backups:  $_backupDir'),
            const SizedBox(height: 8),
            Row(children: [
              TextButton.icon(
                onPressed: () => Process.run('explorer.exe', [_backupDir]),
                icon: const Icon(Icons.folder_open),
                label: const Text('Open backups folder'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final f = await openFile(acceptedTypeGroups: const [
                    XTypeGroup(label: 'Meer Cafe backup', extensions: ['db'])
                  ]);
                  if (f != null) _restore(f.path);
                },
                icon: const Icon(Icons.restore),
                label: const Text('Restore from file...'),
              ),
            ]),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(28),
        child: SectionCard(
          title: 'Backups on this laptop',
          child: _backups.isEmpty
              ? const Text('No backups yet.', style: TextStyle(color: MeerColors.muted))
              : Column(children: [
                  for (final b in _backups)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(b.name),
                      subtitle: Text('${Dates.display(Dates.db(b.modified))} · ${(b.bytes / 1024).toStringAsFixed(0)} KB'),
                      trailing: TextButton(onPressed: () => _restore(b.path), child: const Text('Restore')),
                    ),
                ]),
        ),
      ),
    ]);
  }
}
