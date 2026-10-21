import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../utils/ids.dart';

/// One row to upsert into a worksheet, identified by [key] (column "id").
class SyncRecord {
  final int queueId;
  final int queueVersion;
  final String entityType;
  final String sheet;
  final String key;
  final Map<String, Object?> row;
  const SyncRecord({
    required this.queueId,
    required this.queueVersion,
    required this.entityType,
    required this.sheet,
    required this.key,
    required this.row,
  });

  Map<String, Object?> toJson() => {'sheet': sheet, 'key': key, 'row': row};
}

class SyncResult {
  final bool ok;
  final String? error;
  const SyncResult.ok() : ok = true, error = null;
  const SyncResult.failed(this.error) : ok = false;
}

class SyncTransportException implements Exception {
  final String message;
  SyncTransportException(this.message);
  @override
  String toString() => message;
}

abstract class SyncTransport {
  /// Upserts [records]; returns a result per `sheet/key`. Throws
  /// [SyncTransportException] when the whole request failed.
  Future<Map<String, SyncResult>> send(List<SyncRecord> records);
}

String resultKey(String sheet, String key) => '$sheet/$key';

/// Talks to the Google Apps Script web app in `google_apps_script/Code.gs`.
/// Each request is signed with HMAC-SHA256 using a shared secret that is entered
/// by the admin in Settings (never compiled into the app).
class AppsScriptTransport implements SyncTransport {
  final String url;
  final String secret;
  final http.Client client;
  final Duration timeout;

  AppsScriptTransport({
    required this.url,
    required this.secret,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : client = client ?? http.Client();

  static String sign(String secret, String payload) =>
      Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payload)).toString();

  @override
  Future<Map<String, SyncResult>> send(List<SyncRecord> records) async {
    final payload = jsonEncode({
      'v': 1,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'nonce': Ids.newId(),
      'records': records.map((r) => r.toJson()).toList(),
    });
    final body = jsonEncode({'payload': payload, 'sig': sign(secret, payload)});
    final json = await _post(body);
    if (json['ok'] != true) {
      throw SyncTransportException('Google Sheets rejected the request: ${json['error'] ?? 'unknown error'}');
    }
    final out = <String, SyncResult>{};
    for (final r in (json['results'] as List? ?? const [])) {
      final m = r as Map<String, dynamic>;
      out[resultKey('${m['sheet']}', '${m['key']}')] =
          m['ok'] == true ? const SyncResult.ok() : SyncResult.failed('${m['error'] ?? 'failed'}');
    }
    return out;
  }

  /// Simple connectivity/credential test (no data written).
  Future<String> ping() async {
    final payload = jsonEncode({'v': 1, 'ts': DateTime.now().millisecondsSinceEpoch, 'nonce': Ids.newId(), 'ping': true, 'records': []});
    final json = await _post(jsonEncode({'payload': payload, 'sig': sign(secret, payload)}));
    if (json['ok'] != true) throw SyncTransportException('${json['error'] ?? 'Ping failed'}');
    return 'Connected to "${json['spreadsheet'] ?? 'spreadsheet'}".';
  }

  Future<Map<String, dynamic>> _post(String body) async {
    try {
      final uri = Uri.parse(url);
      // Apps Script answers a POST with a redirect to the result URL, which must be fetched with GET.
      final req = http.Request('POST', uri)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = body;
      var resp = await http.Response.fromStream(await client.send(req).timeout(timeout)).timeout(timeout);
      var hops = 0;
      while ((resp.statusCode == 301 || resp.statusCode == 302 || resp.statusCode == 303 || resp.statusCode == 307) &&
          hops < 5) {
        final loc = resp.headers['location'];
        if (loc == null) break;
        resp = await client.get(uri.resolve(loc)).timeout(timeout);
        hops++;
      }
      if (resp.statusCode != 200) {
        throw SyncTransportException('Google Sheets endpoint returned HTTP ${resp.statusCode}.');
      }
      try {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } on FormatException {
        throw SyncTransportException(
            'Unexpected response from Google. Check the Web App URL and that access is set to "Anyone".');
      }
    } on TimeoutException {
      throw SyncTransportException('Google Sheets did not respond in time (offline?).');
    } on http.ClientException catch (e) {
      throw SyncTransportException('No connection to Google Sheets: ${e.message}');
    } on SyncTransportException {
      rethrow;
    } catch (e) {
      throw SyncTransportException('No connection to Google Sheets: $e');
    }
  }
}
