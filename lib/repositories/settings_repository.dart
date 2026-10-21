import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/app_settings.dart';
import '../models/user.dart';
import '../utils/dates.dart';
import 'permissions.dart';

class SettingsRepository {
  final Database db;
  SettingsRepository(this.db);

  Future<AppSettings> load() async {
    final rows = await db.query('settings');
    return AppSettings({for (final r in rows) r['key'] as String: r['value'] as String});
  }

  /// Admin-only bulk update.
  Future<void> save(AppUser actor, Map<String, String> values) async {
    Permissions.requireAdmin(actor, 'change settings');
    final now = Dates.dbNow();
    await db.transaction((txn) async {
      for (final e in values.entries) {
        await txn.insert('settings', {'key': e.key, 'value': e.value, 'updated_at': now},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
