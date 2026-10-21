import '../models/user.dart';
import '../utils/errors.dart';

/// Role checks enforced in the data layer (not just hidden in the UI).
class Permissions {
  Permissions._();

  static void requireAdmin(AppUser? actor, [String action = 'perform this action']) {
    if (actor == null || !actor.active || actor.role != UserRole.admin) {
      throw PermissionDeniedException('Only an admin can $action.');
    }
  }

  static void requireUser(AppUser? actor) {
    if (actor == null || !actor.active) {
      throw PermissionDeniedException('Please sign in first.');
    }
  }
}
