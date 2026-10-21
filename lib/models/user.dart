enum UserRole {
  admin,
  cashier;

  String get label => this == UserRole.admin ? 'Admin' : 'Cashier';
  static UserRole parse(String s) => s == 'admin' ? UserRole.admin : UserRole.cashier;
}

class AppUser {
  final int id;
  final String username;
  final String displayName;
  final UserRole role;
  final bool active;
  final bool mustChangePassword;
  final String createdAt;
  final String? lastLoginAt;

  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.active,
    required this.mustChangePassword,
    required this.createdAt,
    this.lastLoginAt,
  });

  bool get isAdmin => role == UserRole.admin;

  factory AppUser.fromRow(Map<String, Object?> r) => AppUser(
        id: r['id'] as int,
        username: r['username'] as String,
        displayName: r['display_name'] as String,
        role: UserRole.parse(r['role'] as String),
        active: (r['active'] as int) == 1,
        mustChangePassword: (r['must_change_password'] as int) == 1,
        createdAt: r['created_at'] as String,
        lastLoginAt: r['last_login_at'] as String?,
      );
}
