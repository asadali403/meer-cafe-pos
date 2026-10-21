import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/app_settings.dart';
import '../utils/dates.dart';
import 'migrations.dart';

/// Thrown when the database file exists but fails its integrity check.
class DatabaseCorruptException implements Exception {
  final String path;
  final String detail;
  DatabaseCorruptException(this.path, this.detail);
  @override
  String toString() => 'Database integrity check failed: $detail';
}

/// Owns the SQLite connection. The database file lives in a persistent per-user
/// folder: `%APPDATA%\MeerCafePOS\data\meer_cafe.db` — never in the build folder.
class AppDatabase {
  final Database db;
  final String path;

  AppDatabase._(this.db, this.path);

  static bool _ffiReady = false;

  static void _initFfi() {
    if (_ffiReady) return;
    sqfliteFfiInit();
    _ffiReady = true;
  }

  /// Optional override (e.g. `MeerCafePOS.exe --data-dir=D:\TestData`) used for testing
  /// without touching the real cafe data.
  static String? dataDirOverride;

  /// `%APPDATA%\MeerCafePOS` (falls back to the platform app-support folder).
  static Future<Directory> appDataDir() async {
    if (dataDirOverride != null && dataDirOverride!.isNotEmpty) {
      final d = Directory(dataDirOverride!);
      await d.create(recursive: true);
      return d;
    }
    final appData = Platform.environment['APPDATA'];
    final base = (appData != null && appData.isNotEmpty)
        ? Directory(p.join(appData, 'MeerCafePOS'))
        : Directory(p.join((await getApplicationSupportDirectory()).path, 'MeerCafePOS'));
    await base.create(recursive: true);
    return base;
  }

  static Future<String> defaultPath() async {
    final dir = Directory(p.join((await appDataDir()).path, 'data'));
    await dir.create(recursive: true);
    return p.join(dir.path, 'meer_cafe.db');
  }

  static Future<Directory> backupDir() async {
    final dir = Directory(p.join((await appDataDir()).path, 'backups'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Opens (creating/migrating if needed) the database at [path].
  /// Pass `inMemoryDatabasePath` for tests.
  static Future<AppDatabase> open(String path, {bool checkIntegrity = true}) async {
    _initFfi();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        singleInstance: path != inMemoryDatabasePath,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA foreign_keys = ON');
          if (path != inMemoryDatabasePath) {
            await db.rawQuery('PRAGMA journal_mode = WAL');
            await db.rawQuery('PRAGMA synchronous = FULL');
          }
          await db.rawQuery('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, version) async {
          await _migrate(db, 0, version);
          await _seed(db);
        },
        onUpgrade: (db, oldV, newV) => _migrate(db, oldV, newV),
        onDowngrade: (db, oldV, newV) => throw StateError(
            'This database was created by a newer version of Meer Cafe POS (schema $oldV). '
            'Please install the newer version.'),
      ),
    );
    if (checkIntegrity && path != inMemoryDatabasePath) {
      final res = await db.rawQuery('PRAGMA quick_check');
      final msg = res.isEmpty ? 'no result' : res.first.values.first.toString();
      if (msg != 'ok') {
        await db.close();
        throw DatabaseCorruptException(path, msg);
      }
    }
    return AppDatabase._(db, path);
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from; v < to; v++) {
      final batch = db.batch();
      for (final sql in migrations[v]) {
        batch.execute(sql);
      }
      await batch.commit(noResult: true);
    }
  }

  /// Default categories and settings (no users and no passwords are seeded).
  static Future<void> _seed(Database db) async {
    final now = Dates.dbNow();
    const cats = ['Tea', 'Coffee', 'Burger', 'Fries', 'Drinks', 'Snacks', 'Other'];
    for (var i = 0; i < cats.length; i++) {
      await db.insert('categories', {
        'name': cats[i],
        'sort_order': i,
        'active': 1,
        'kitchen': cats[i] == 'Drinks' ? 0 : 1,
        'created_at': now,
        'updated_at': now,
      });
    }
    for (final e in AppSettings.defaults.entries) {
      await db.insert('settings', {'key': e.key, 'value': e.value, 'updated_at': now});
    }
  }

  Future<void> close() => db.close();

  /// Consistent hot copy of the live database (safe while the app is running).
  Future<void> backupTo(String targetFile) async {
    final f = File(targetFile);
    if (await f.exists()) await f.delete();
    await db.execute('VACUUM INTO ?', [targetFile]);
  }

  /// Checks that [file] is a readable Meer Cafe POS database.
  static Future<String?> validateBackup(String file) async {
    _initFfi();
    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(file,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final check = await db.rawQuery('PRAGMA integrity_check');
      if (check.isEmpty || check.first.values.first != 'ok') return 'Backup file failed integrity check.';
      final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toSet();
      for (final t in ['users', 'products', 'bills', 'bill_items', 'payments', 'settings']) {
        if (!tables.contains(t)) return 'This file is not a Meer Cafe POS backup (missing "$t").';
      }
      final v = (await db.rawQuery('PRAGMA user_version')).first.values.first as int;
      if (v > schemaVersion) return 'Backup was made by a newer app version.';
      return null;
    } catch (e) {
      return 'Could not open backup: $e';
    } finally {
      await db?.close();
    }
  }
}
