import 'package:meer_cafe_pos/database/db_utils.dart';
import 'package:meer_cafe_pos/database/app_database.dart';
import 'package:meer_cafe_pos/models/app_settings.dart';
import 'package:meer_cafe_pos/models/product.dart';
import 'package:meer_cafe_pos/models/user.dart';
import 'package:meer_cafe_pos/repositories/bill_repository.dart';
import 'package:meer_cafe_pos/repositories/product_repository.dart';
import 'package:meer_cafe_pos/repositories/settings_repository.dart';
import 'package:meer_cafe_pos/repositories/user_repository.dart';
import 'package:meer_cafe_pos/services/password_hasher.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fresh database + repositories + an admin and a cashier for each test.
class TestEnv {
  final AppDatabase database;
  final UserRepository users;
  final ProductRepository products;
  final BillRepository bills;
  final SettingsRepository settingsRepo;
  late AppUser admin;
  late AppUser cashier;
  late AppSettings settings;

  TestEnv._(this.database)
      : users = UserRepository(database.db, hasher: const PasswordHasher(iterations: 1000)),
        products = ProductRepository(database.db),
        bills = BillRepository(database.db),
        settingsRepo = SettingsRepository(database.db);

  Database get db => database.db;

  static Future<TestEnv> create({String path = inMemoryDatabasePath, bool seedUsers = true}) async {
    final env = TestEnv._(await AppDatabase.open(path));
    if (seedUsers) {
      env.admin = await env.users.createInitialAdmin('admin', 'Owner', 'secret123');
      final temp = await env.users.create(env.admin,
          username: 'ali', displayName: 'Ali', tempPassword: 'temp1234', role: UserRole.cashier);
      env.cashier = await env.users.changePassword(temp, 'temp1234', 'cashier123');
    }
    env.settings = await env.settingsRepo.load();
    return env;
  }

  Future<int> category(String name) async =>
      (await products.categories()).firstWhere((c) => c.name == name).id;

  Future<int> addProduct(String name, int rupees, {String category = 'Tea & Coffee'}) async =>
      products.save(admin, Product(name: name, categoryId: await this.category(category), pricePaisa: rupees * 100));

  Future<int> count(String table) async =>
      firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ?? 0;

  Future<void> close() => database.close();
}
