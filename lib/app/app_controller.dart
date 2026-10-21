import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/app_settings.dart';
import '../models/user.dart';
import '../repositories/bill_repository.dart';
import '../repositories/product_repository.dart';
import '../repositories/report_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/user_repository.dart';
import '../services/backup_service.dart';
import '../services/print_service.dart';
import '../services/sync_service.dart';

enum AppStage { loading, databaseError, firstRun, login, changePassword, home }

/// Root state: database connection, repositories, background sync and the signed-in user.
/// The session lives only in memory, so closing the app always signs out.
class AppController extends ChangeNotifier {
  AppStage stage = AppStage.loading;
  String? errorMessage;
  String? dbPath;

  AppDatabase? _database;
  late UserRepository users;
  late ProductRepository products;
  late BillRepository bills;
  late ReportRepository reports;
  late SettingsRepository settingsRepo;
  late PrintService printer;
  late BackupService backups;
  SyncService? sync;

  AppSettings settings = const AppSettings({});
  AppUser? user;

  AppDatabase get database => _database!;

  Future<void> init() async {
    stage = AppStage.loading;
    errorMessage = null;
    notifyListeners();
    try {
      dbPath ??= await AppDatabase.defaultPath();
      _database = await AppDatabase.open(dbPath!);
      final db = _database!.db;
      users = UserRepository(db);
      products = ProductRepository(db);
      bills = BillRepository(db);
      reports = ReportRepository(db);
      settingsRepo = SettingsRepository(db);
      printer = PrintService(bills);
      backups = BackupService(_database!);
      settings = await settingsRepo.load();
      sync = SyncService(db: db, loadSettings: settingsRepo.load)..start();
      stage = await users.count() == 0 ? AppStage.firstRun : AppStage.login;
      notifyListeners();
      // Daily safety copy; failures must never block billing.
      backups.autoBackup().catchError((_) => null);
    } catch (e) {
      errorMessage = e.toString();
      stage = AppStage.databaseError;
      notifyListeners();
    }
  }

  void signIn(AppUser u) {
    user = u;
    stage = u.mustChangePassword ? AppStage.changePassword : AppStage.home;
    notifyListeners();
  }

  void signOut() {
    user = null;
    stage = AppStage.login;
    notifyListeners();
  }

  Future<void> reloadSettings() async {
    settings = await settingsRepo.load();
    notifyListeners();
  }

  Future<void> saveSettings(Map<String, String> values) async {
    await settingsRepo.save(user!, values);
    await reloadSettings();
  }

  /// Closes the database, swaps in [backupFile] (keeping the old file), and restarts.
  Future<void> restoreFrom(String backupFile) async {
    final err = await AppDatabase.validateBackup(backupFile);
    if (err != null) throw Exception(err);
    await _shutdown();
    try {
      await BackupService.replaceDatabaseFile(dbPath!, backupFile);
    } finally {
      user = null;
      await init();
    }
  }

  /// Used from the database-error screen when the database cannot be opened.
  Future<void> restoreWithoutOpenDatabase(String backupFile) async {
    await _shutdown();
    dbPath ??= await AppDatabase.defaultPath();
    await BackupService.replaceDatabaseFile(dbPath!, backupFile, keepAs: 'damaged');
    await init();
  }

  /// Stops background sync and closes the database (used on restore and in tests).
  Future<void> shutdown() => _shutdown();

  Future<void> _shutdown() async {
    sync?.dispose();
    sync = null;
    try {
      await _database?.close();
    } catch (_) {}
    _database = null;
  }
}
