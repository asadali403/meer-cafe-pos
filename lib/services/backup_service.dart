import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../utils/dates.dart';

class BackupInfo {
  final String path;
  final DateTime modified;
  final int bytes;
  const BackupInfo(this.path, this.modified, this.bytes);
  String get name => p.basename(path);
}

/// Database backups. Uses `VACUUM INTO`, which produces a consistent copy even while
/// the app is running. Automatic daily backups are kept for [keepAutoBackups] days.
class BackupService {
  final AppDatabase database;
  BackupService(this.database);

  static const keepAutoBackups = 30;

  static String _stamp() => Dates.db(DateTime.now()).replaceAll(RegExp(r'[-: ]'), '');

  Future<String> backupToFolder(String folder) async {
    final target = p.join(folder, 'meer_cafe_backup_${_stamp()}.db');
    await database.backupTo(target);
    return target;
  }

  /// One automatic backup per day into %APPDATA%\MeerCafePOS\backups.
  Future<String?> autoBackup() async {
    final dir = await AppDatabase.backupDir();
    final today = Dates.compact(DateTime.now());
    final target = p.join(dir.path, 'auto_$today.db');
    if (await File(target).exists()) return null;
    await database.backupTo(target);
    final autos = (await list()).where((b) => b.name.startsWith('auto_')).toList();
    for (final old in autos.skip(keepAutoBackups)) {
      try {
        await File(old.path).delete();
      } catch (_) {}
    }
    return target;
  }

  static Future<List<BackupInfo>> list() async {
    final dir = await AppDatabase.backupDir();
    final files = <BackupInfo>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.db')) {
        final st = await e.stat();
        files.add(BackupInfo(e.path, st.modified, st.size));
      }
    }
    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  /// Replaces the database file at [dbPath] with [source]. The database must be closed.
  /// The previous file is kept as `pre_restore_*.db` in the backups folder.
  static Future<void> replaceDatabaseFile(String dbPath, String source, {String keepAs = 'pre_restore'}) async {
    final err = await AppDatabase.validateBackup(source);
    if (err != null) throw Exception(err);
    final dir = await AppDatabase.backupDir();
    final current = File(dbPath);
    if (await current.exists()) {
      await current.copy(p.join(dir.path, '${keepAs}_${_stamp()}.db'));
    }
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) await f.delete();
    }
    await File(source).copy(dbPath);
  }
}
