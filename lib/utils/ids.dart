import 'package:uuid/uuid.dart';

class Ids {
  Ids._();
  static const _uuid = Uuid();

  /// Random globally-unique id (UUID v4) used for bills, bill items and payments.
  static String newId() => _uuid.v4();
}
