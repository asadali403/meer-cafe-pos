import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../repositories/report_repository.dart';
import '../utils/money.dart';

/// CSV export (UTF-8 with BOM so Excel opens it correctly).
class ExportService {
  ExportService._();

  static String toCsv(ReportTable t) {
    String cell(Object? v) {
      final s = v?.toString() ?? '';
      if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
      return s;
    }

    final buf = StringBuffer()..writeln(t.columns.map(cell).join(','));
    for (final r in t.rows) {
      buf.writeln([
        for (var i = 0; i < r.length; i++)
          cell(t.moneyColumns.contains(i) && r[i] is int ? Money.plain(r[i] as int) : r[i]),
      ].join(','));
    }
    return buf.toString();
  }

  /// Asks where to save and writes the CSV. Returns the path, or null if cancelled.
  static Future<String?> saveCsv(String suggestedName, ReportTable t) async {
    final loc = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [XTypeGroup(label: 'CSV (Excel)', extensions: ['csv'])],
    );
    if (loc == null) return null;
    var path = loc.path;
    if (!path.toLowerCase().endsWith('.csv')) path = '$path.csv';
    await File(path).writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(toCsv(t))]);
    return path;
  }
}
