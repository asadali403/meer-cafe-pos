import '../database/db_utils.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/product.dart';
import '../models/user.dart';
import '../utils/dates.dart';
import '../utils/errors.dart';
import 'permissions.dart';
import 'sync_queue.dart';

class ProductRepository {
  final Database db;
  ProductRepository(this.db);

  static const maxPricePaisa = 10000000 * 100; // Rs. 10 million

  // ---------------- Categories ----------------

  Future<List<Category>> categories({bool includeInactive = false}) async {
    final rows = await db.query('categories',
        where: includeInactive ? null : 'active = 1', orderBy: 'sort_order, name');
    return rows.map(Category.fromRow).toList();
  }

  Future<int> addCategory(AppUser actor, String name) async {
    Permissions.requireAdmin(actor, 'add categories');
    name = name.trim();
    if (name.isEmpty || name.length > 40) throw ValidationException('Category name must be 1-40 characters.');
    final dup = await db.query('categories', where: 'name = ?', whereArgs: [name]);
    if (dup.isNotEmpty) throw ValidationException('Category "$name" already exists.');
    final maxOrder =
        firstIntValue(await db.rawQuery('SELECT COALESCE(MAX(sort_order), 0) FROM categories')) ?? 0;
    final now = Dates.dbNow();
    return db.insert('categories',
        {'name': name, 'sort_order': maxOrder + 1, 'active': 1, 'created_at': now, 'updated_at': now});
  }

  /// Turns kitchen-ticket printing on/off for a category (e.g. off for canned drinks).
  Future<void> setCategoryKitchen(AppUser actor, int id, bool kitchen) async {
    Permissions.requireAdmin(actor, 'edit categories');
    await db.update('categories', {'kitchen': kitchen ? 1 : 0, 'updated_at': Dates.dbNow()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateCategory(AppUser actor, int id, {required String name, required bool active}) async {
    Permissions.requireAdmin(actor, 'edit categories');
    name = name.trim();
    if (name.isEmpty || name.length > 40) throw ValidationException('Category name must be 1-40 characters.');
    final dup = await db.query('categories', where: 'name = ? AND id <> ?', whereArgs: [name, id]);
    if (dup.isNotEmpty) throw ValidationException('Category "$name" already exists.');
    await db.transaction((txn) async {
      await txn.update('categories', {'name': name, 'active': active ? 1 : 0, 'updated_at': Dates.dbNow()},
          where: 'id = ?', whereArgs: [id]);
      // Category name appears on synced product rows.
      final ids = await txn.query('products', columns: ['id'], where: 'category_id = ?', whereArgs: [id]);
      for (final r in ids) {
        await enqueueSync(txn, SyncEntity.product, '${r['id']}');
      }
    });
  }

  // ---------------- Products ----------------

  static const _select = '''
    SELECT p.*, c.name AS category_name FROM products p
    JOIN categories c ON c.id = p.category_id
  ''';

  /// [activeOnly] = what cashiers see: active products in active categories.
  Future<List<Product>> list({bool activeOnly = false, int? categoryId, String search = ''}) async {
    final where = <String>['p.deleted_at IS NULL'];
    final args = <Object?>[];
    if (activeOnly) where.add('p.active = 1 AND c.active = 1');
    if (categoryId != null) {
      where.add('p.category_id = ?');
      args.add(categoryId);
    }
    final q = search.trim();
    if (q.isNotEmpty) {
      where.add('(p.name LIKE ? OR c.name LIKE ? OR p.description LIKE ?)');
      args.addAll(['%$q%', '%$q%', '%$q%']);
    }
    final rows = await db.rawQuery(
        '$_select WHERE ${where.join(' AND ')} ORDER BY c.sort_order, p.name COLLATE NOCASE', args);
    return rows.map(Product.fromRow).toList();
  }

  Future<Product?> byId(int id) async {
    final rows = await db.rawQuery('$_select WHERE p.id = ?', [id]);
    return rows.isEmpty ? null : Product.fromRow(rows.first);
  }

  static void validate(Product p) {
    final name = p.name.trim();
    if (name.isEmpty || name.length > 60) throw ValidationException('Product name must be 1-60 characters.');
    if (p.pricePaisa < 0) throw ValidationException('Price cannot be negative.');
    if (p.pricePaisa > maxPricePaisa) throw ValidationException('Price is too large.');
    if (p.description.length > 200) throw ValidationException('Description must be at most 200 characters.');
  }

  /// Insert or update a product (admin only). Returns the product id.
  Future<int> save(AppUser actor, Product p) async {
    Permissions.requireAdmin(actor, 'add or edit products and prices');
    validate(p);
    final cat = await db.query('categories', where: 'id = ?', whereArgs: [p.categoryId]);
    if (cat.isEmpty) throw ValidationException('Please choose a valid category.');
    final now = Dates.dbNow();
    return db.transaction((txn) async {
      final data = {
        'name': p.name.trim(),
        'category_id': p.categoryId,
        'price': p.pricePaisa,
        'description': p.description.trim(),
        'active': p.active ? 1 : 0,
        'updated_at': now,
      };
      int id;
      if (p.id == null) {
        id = await txn.insert('products', {...data, 'created_at': now});
      } else {
        id = p.id!;
        final n = await txn.update('products', data, where: 'id = ? AND deleted_at IS NULL', whereArgs: [id]);
        if (n == 0) throw ValidationException('Product no longer exists.');
      }
      await enqueueSync(txn, SyncEntity.product, '$id');
      return id;
    });
  }

  Future<void> setActive(AppUser actor, int id, bool active) async {
    Permissions.requireAdmin(actor, 'activate or deactivate products');
    await db.transaction((txn) async {
      await txn.update('products', {'active': active ? 1 : 0, 'updated_at': Dates.dbNow()},
          where: 'id = ?', whereArgs: [id]);
      await enqueueSync(txn, SyncEntity.product, '$id');
    });
  }

  /// Soft delete: hides the product everywhere but keeps old bills intact.
  Future<void> delete(AppUser actor, int id) async {
    Permissions.requireAdmin(actor, 'delete products');
    final now = Dates.dbNow();
    await db.transaction((txn) async {
      await txn.update('products', {'deleted_at': now, 'active': 0, 'updated_at': now},
          where: 'id = ?', whereArgs: [id]);
      await enqueueSync(txn, SyncEntity.product, '$id');
    });
  }

  /// Loads the bundled sample menu (admin only, only into an empty product list).
  Future<int> loadSampleMenu(AppUser actor) async {
    Permissions.requireAdmin(actor, 'load the sample menu');
    final existing = firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM products WHERE deleted_at IS NULL')) ??
        0;
    if (existing > 0) throw ValidationException('Sample menu can only be loaded when there are no products.');
    final cats = {for (final c in await categories(includeInactive: true)) c.name.toLowerCase(): c.id};
    var n = 0;
    for (final s in sampleMenu) {
      final catId = cats[s.$1.toLowerCase()] ?? cats['other']!;
      await save(actor, Product(name: s.$2, categoryId: catId, pricePaisa: s.$3 * 100, description: s.$4));
      n++;
    }
    return n;
  }
}

/// Sample cafe menu: (category, name, price in rupees, description).
const sampleMenu = <(String, String, int, String)>[
  ('Tea', 'Doodh Patti', 120, 'Strong milk tea'),
  ('Tea', 'Karak Chai', 150, 'Cardamom karak tea'),
  ('Tea', 'Green Tea', 100, 'Light and refreshing'),
  ('Tea', 'Kashmiri Chai', 250, 'Pink tea with nuts'),
  ('Coffee', 'Espresso', 300, 'Single shot'),
  ('Coffee', 'Americano', 350, ''),
  ('Coffee', 'Cappuccino', 450, ''),
  ('Coffee', 'Cafe Latte', 480, ''),
  ('Coffee', 'Iced Caramel Latte', 550, ''),
  ('Burger', 'Classic Beef Burger', 650, 'With cheese and fries sauce'),
  ('Burger', 'Zinger Burger', 550, 'Crispy chicken fillet'),
  ('Burger', 'Grilled Chicken Burger', 600, ''),
  ('Fries', 'Plain Fries', 250, 'Regular'),
  ('Fries', 'Masala Fries', 300, ''),
  ('Fries', 'Loaded Cheese Fries', 450, ''),
  ('Drinks', 'Mint Margarita', 350, ''),
  ('Drinks', 'Fresh Lime', 250, ''),
  ('Drinks', 'Soft Drink (Can)', 150, ''),
  ('Drinks', 'Mineral Water', 80, '500 ml'),
  ('Snacks', 'Club Sandwich', 550, ''),
  ('Snacks', 'Chicken Samosa (2 pcs)', 150, ''),
  ('Snacks', 'Brownie', 300, ''),
  ('Other', 'Extra Cheese', 100, 'Add-on'),
];
