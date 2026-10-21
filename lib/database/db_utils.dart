/// First column of the first row as an int (e.g. `SELECT COUNT(*) ...`), or null.
int? firstIntValue(List<Map<String, Object?>> rows) {
  if (rows.isEmpty || rows.first.isEmpty) return null;
  final v = rows.first.values.first;
  return v is int ? v : (v is num ? v.toInt() : null);
}
