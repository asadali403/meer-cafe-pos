import '../database/db_utils.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/user.dart';
import '../services/password_hasher.dart';
import '../utils/dates.dart';
import '../utils/errors.dart';
import 'permissions.dart';

class UserRepository {
  final Database db;
  final PasswordHasher hasher;
  UserRepository(this.db, {this.hasher = const PasswordHasher()});

  static const maxFailedAttempts = 5;
  static const lockMinutes = 5;

  Future<int> count() async =>
      firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM users')) ?? 0;

  Future<List<AppUser>> list(AppUser actor) async {
    Permissions.requireAdmin(actor, 'manage users');
    final rows = await db.query('users', orderBy: 'role, username');
    return rows.map(AppUser.fromRow).toList();
  }

  Future<AppUser?> byId(int id) async {
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : AppUser.fromRow(rows.first);
  }

  static String? validateUsername(String u) {
    if (!RegExp(r'^[A-Za-z0-9_.-]{3,30}$').hasMatch(u)) {
      return 'Username must be 3-30 letters, numbers, dot, dash or underscore.';
    }
    return null;
  }

  /// First-run: creates the very first admin. Refuses if any user exists.
  Future<AppUser> createInitialAdmin(String username, String displayName, String password) async {
    if (await count() > 0) {
      throw PermissionDeniedException('Initial setup has already been completed.');
    }
    return _insert(username, displayName, password, UserRole.admin, mustChange: false);
  }

  /// Admin creates a user with a temporary password; the user must change it at first login.
  Future<AppUser> create(AppUser actor,
      {required String username,
      required String displayName,
      required String tempPassword,
      required UserRole role}) async {
    Permissions.requireAdmin(actor, 'create users');
    return _insert(username, displayName, tempPassword, role, mustChange: true);
  }

  Future<AppUser> _insert(String username, String displayName, String password, UserRole role,
      {required bool mustChange}) async {
    username = username.trim();
    displayName = displayName.trim();
    final uErr = validateUsername(username);
    if (uErr != null) throw ValidationException(uErr);
    if (displayName.isEmpty) throw ValidationException('Display name is required.');
    final pErr = PasswordHasher.validatePolicy(password);
    if (pErr != null) throw ValidationException(pErr);
    final exists = await db.query('users', where: 'username = ?', whereArgs: [username]);
    if (exists.isNotEmpty) throw ValidationException('Username "$username" is already taken.');
    final now = Dates.dbNow();
    final id = await db.insert('users', {
      'username': username,
      'display_name': displayName,
      'password_hash': await hasher.hash(password),
      'role': role.name,
      'active': 1,
      'must_change_password': mustChange ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    });
    return (await byId(id))!;
  }

  /// Verifies credentials with lockout after repeated failures.
  Future<AppUser> authenticate(String username, String password) async {
    final rows = await db.query('users', where: 'username = ?', whereArgs: [username.trim()]);
    const generic = 'Incorrect username or password.';
    if (rows.isEmpty) {
      await hasher.hash(password); // similar timing for unknown users
      throw ValidationException(generic);
    }
    final row = rows.first;
    final id = row['id'] as int;
    final lockedUntil = row['locked_until'] as String?;
    if (lockedUntil != null && Dates.parseDb(lockedUntil).isAfter(DateTime.now())) {
      throw ValidationException('Too many failed attempts. Try again after ${Dates.display(lockedUntil)}.');
    }
    final ok = await hasher.verify(password, row['password_hash'] as String);
    if (!ok) {
      final attempts = (row['failed_attempts'] as int) + 1;
      final lock = attempts >= maxFailedAttempts
          ? Dates.db(DateTime.now().add(const Duration(minutes: lockMinutes)))
          : null;
      await db.update('users', {'failed_attempts': lock == null ? attempts : 0, 'locked_until': lock},
          where: 'id = ?', whereArgs: [id]);
      throw ValidationException(lock == null ? generic : 'Too many failed attempts. Account locked for $lockMinutes minutes.');
    }
    if ((row['active'] as int) != 1) throw ValidationException('This account has been deactivated.');
    await db.update('users', {'failed_attempts': 0, 'locked_until': null, 'last_login_at': Dates.dbNow()},
        where: 'id = ?', whereArgs: [id]);
    return (await byId(id))!;
  }

  Future<AppUser> changePassword(AppUser user, String current, String newPassword) async {
    final row = (await db.query('users', where: 'id = ?', whereArgs: [user.id])).first;
    if (!await hasher.verify(current, row['password_hash'] as String)) {
      throw ValidationException('Current password is incorrect.');
    }
    if (current == newPassword) throw ValidationException('New password must be different.');
    final pErr = PasswordHasher.validatePolicy(newPassword);
    if (pErr != null) throw ValidationException(pErr);
    await db.update(
        'users',
        {'password_hash': await hasher.hash(newPassword), 'must_change_password': 0, 'updated_at': Dates.dbNow()},
        where: 'id = ?',
        whereArgs: [user.id]);
    return (await byId(user.id))!;
  }

  Future<void> resetPassword(AppUser actor, int userId, String tempPassword) async {
    Permissions.requireAdmin(actor, 'reset passwords');
    final pErr = PasswordHasher.validatePolicy(tempPassword);
    if (pErr != null) throw ValidationException(pErr);
    await db.update(
        'users',
        {
          'password_hash': await hasher.hash(tempPassword),
          'must_change_password': 1,
          'failed_attempts': 0,
          'locked_until': null,
          'updated_at': Dates.dbNow(),
        },
        where: 'id = ?',
        whereArgs: [userId]);
  }

  Future<void> update(AppUser actor, int userId,
      {required String displayName, required UserRole role, required bool active}) async {
    Permissions.requireAdmin(actor, 'edit users');
    if (displayName.trim().isEmpty) throw ValidationException('Display name is required.');
    if (userId == actor.id && (!active || role != UserRole.admin)) {
      throw ValidationException('You cannot deactivate or demote your own account.');
    }
    if (role != UserRole.admin || !active) {
      final otherAdmins = firstIntValue(await db.rawQuery(
              "SELECT COUNT(*) FROM users WHERE role='admin' AND active=1 AND id <> ?", [userId])) ??
          0;
      final target = await byId(userId);
      if (target?.role == UserRole.admin && otherAdmins == 0) {
        throw ValidationException('At least one active admin is required.');
      }
    }
    await db.update(
        'users',
        {
          'display_name': displayName.trim(),
          'role': role.name,
          'active': active ? 1 : 0,
          'updated_at': Dates.dbNow(),
        },
        where: 'id = ?',
        whereArgs: [userId]);
  }
}
