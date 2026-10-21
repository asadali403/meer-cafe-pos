/// Thrown when the signed-in user's role does not allow an operation.
class PermissionDeniedException implements Exception {
  final String message;
  PermissionDeniedException([this.message = 'You do not have permission to do this.']);
  @override
  String toString() => message;
}

/// Thrown for invalid user input or broken business rules.
class ValidationException implements Exception {
  final String message;
  ValidationException(this.message);
  @override
  String toString() => message;
}

/// Converts any error into a short message suitable for a snackbar.
String friendlyError(Object e) {
  if (e is PermissionDeniedException || e is ValidationException) return e.toString();
  final text = e.toString();
  if (text.contains('UNIQUE constraint failed')) {
    return 'That value already exists. Please use a different one.';
  }
  if (text.contains('database is locked')) {
    return 'The database is busy. Please try again.';
  }
  if (text.contains('SqfliteFfiException') || text.contains('DatabaseException')) {
    return 'A database error occurred. Nothing was saved. ($text)';
  }
  return text.replaceFirst('Exception: ', '');
}
