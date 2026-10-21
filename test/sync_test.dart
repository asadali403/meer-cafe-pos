import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meer_cafe_pos/repositories/bill_repository.dart';
import 'package:meer_cafe_pos/services/sync_service.dart';
import 'package:meer_cafe_pos/services/sync_transport.dart';
import 'package:meer_cafe_pos/utils/ids.dart';

import 'helpers.dart';

/// In-memory imitation of the Apps Script endpoint: upsert by (sheet, id).
class FakeSheets implements SyncTransport {
  final Map<String, Map<String, Map<String, Object?>>> sheets = {};
  int appends = 0;
  int requests = 0;
  bool offline = false;
  Set<String> rejectKeys = {};

  int rows(String sheet) => sheets[sheet]?.length ?? 0;

  @override
  Future<Map<String, SyncResult>> send(List<SyncRecord> records) async {
    requests++;
    if (offline) throw SyncTransportException('No connection to Google Sheets');
    final out = <String, SyncResult>{};
    for (final r in records) {
      if (rejectKeys.contains(r.key)) {
        out[resultKey(r.sheet, r.key)] = const SyncResult.failed('quota');
        continue;
      }
      final sheet = sheets.putIfAbsent(r.sheet, () => {});
      if (!sheet.containsKey(r.key)) appends++;
      sheet[r.key] = r.row;
      out[resultKey(r.sheet, r.key)] = const SyncResult.ok();
    }
    return out;
  }
}

void main() {
  late TestEnv env;
  late FakeSheets server;
  late SyncService sync;
  late int latte;

  setUp(() async {
    env = await TestEnv.create();
    server = FakeSheets();
    await env.settingsRepo.save(env.admin, {
      'sync_enabled': '1',
      'sync_url': 'https://script.google.com/macros/s/test/exec',
      'sync_secret': 'x' * 32,
    });
    sync = SyncService(db: env.db, loadSettings: env.settingsRepo.load, transportFor: (_) => server, batchSize: 3);
    latte = await env.addProduct('Latte', 480);
  });
  tearDown(() async {
    sync.dispose();
    await env.close();
  });

  Future<String> sell({int received = 100000}) async => (await env.bills.completeBill(env.cashier,
          billId: Ids.newId(), lines: [CartLineInput(latte, 2)], settings: env.settings, amountReceived: received))
      .id;

  test('bills, items and payments appear exactly once', () async {
    await sell();
    await sell(received: 50000);
    await sync.run(force: true);
    expect(server.rows('Bills'), 2);
    expect(server.rows('BillItems'), 2);
    expect(server.rows('Payments'), 2);
    expect(server.rows('Products'), 1);
    expect(server.rows('DailySummary'), 1);
    await sync.run(force: true); // uploads the SyncLog row describing the first run
    expect(server.rows('SyncLog'), 1);
    final appendsBefore = server.appends;
    final requestsBefore = server.requests;
    await sync.run(force: true); // nothing new to send
    expect(server.appends, appendsBefore);
    expect(server.requests, requestsBefore);
    final c = await sync.refreshCounts();
    expect(c.pending, 0);
    expect(c.failed, 0);
  });

  test('offline: records stay queued, nothing marked synced, then retry succeeds once', () async {
    sync = SyncService(db: env.db, loadSettings: env.settingsRepo.load, transportFor: (_) => server);
    final billId = await sell();
    server.offline = true;
    final msg = await sync.run(force: true);
    expect(msg, startsWith('Sync failed'));
    expect(server.rows('Bills'), 0);
    var c = await sync.refreshCounts();
    expect(c.synced, 0);
    expect(c.failed, greaterThan(0));
    final bill = (await env.db.query('bills', where: 'id = ?', whereArgs: [billId])).first;
    expect(bill['sync_status'], 'failed');

    server.offline = false;
    await sync.run(force: true);
    await sync.run(force: true);
    expect(server.rows('Bills'), 1);
    expect(server.rows('BillItems'), 1);
    expect(server.rows('Payments'), 1);
    c = await sync.refreshCounts();
    expect(c.failed, 0);
    expect(c.pending, 0);
    final synced = (await env.db.query('bills', where: 'id = ?', whereArgs: [billId])).first;
    expect(synced['sync_status'], 'synced');
  });

  test('failed records wait for back-off unless Sync Now is used', () async {
    sync = SyncService(db: env.db, loadSettings: env.settingsRepo.load, transportFor: (_) => server);
    await sell();
    server.offline = true;
    await sync.run(force: true);
    server.offline = false;
    await sync.run(); // automatic run respects back-off
    expect(server.rows('Bills'), 0);
    await sync.run(force: true); // Sync Now
    expect(server.rows('Bills'), 1);
  });

  test('payment update re-syncs the same bill row (no duplicate)', () async {
    final billId = await sell(received: 50000);
    await sync.run(force: true);
    expect(server.sheets['Bills']![billId]!['payment_status'], 'PARTIALLY PAID');
    await env.bills.addPayment(env.cashier, billId, amountReceived: 46000);
    await sync.run(force: true);
    expect(server.rows('Bills'), 1);
    expect(server.sheets['Bills']![billId]!['payment_status'], 'PAID');
    expect(server.sheets['Bills']![billId]!['balance_due'], 0.0);
    expect(server.rows('Payments'), 2);
  });

  test('product price change updates the existing Products row', () async {
    await sync.run(force: true);
    final p = (await env.products.byId(latte))!;
    await env.products.save(env.admin, p.copyWith(pricePaisa: 50000));
    await sync.run(force: true);
    expect(server.rows('Products'), 1);
    expect(server.sheets['Products']!['$latte']!['price'], 500.0);
  });

  test('a per-record rejection leaves only that record failed', () async {
    final billId = await sell();
    server.rejectKeys = {billId};
    await sync.run(force: true);
    expect(server.rows('Bills'), 0);
    expect(server.rows('BillItems'), 1);
    final q = (await env.db.query('sync_queue', where: 'entity_id = ?', whereArgs: [billId])).first;
    expect(q['status'], 'failed');
    expect(q['last_error'], 'quota');
    server.rejectKeys = {};
    await sync.run(force: true);
    expect(server.rows('Bills'), 1);
  });

  test('local records are never deleted after sync', () async {
    await sell();
    await sync.run(force: true);
    expect(await env.count('bills'), 1);
    expect(await env.count('bill_items'), 1);
    expect(await env.count('payments'), 1);
  });

  test('sync turned off does nothing and reports why', () async {
    final off = SyncService(db: env.db, loadSettings: () async => env.settings); // defaults: disabled
    final msg = await off.run(force: true);
    expect(msg, contains('turned off'));
    off.dispose();
  });

  group('AppsScriptTransport', () {
    test('signs payload with HMAC-SHA256 and follows the Apps Script redirect', () async {
      const secret = 'super-secret-value-123';
      late Map<String, dynamic> envelope;
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          envelope = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response('', 302, headers: {'location': 'https://script.googleusercontent.com/echo?x=1'});
        }
        final payload = jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
        final results = [
          for (final r in payload['records'] as List) {'sheet': r['sheet'], 'key': r['key'], 'ok': true}
        ];
        return http.Response(jsonEncode({'ok': true, 'results': results}), 200);
      });
      final t = AppsScriptTransport(url: 'https://script.google.com/macros/s/abc/exec', secret: secret, client: client);
      final res = await t.send([
        const SyncRecord(queueId: 1, queueVersion: 1, entityType: 'bill', sheet: 'Bills', key: 'b1', row: {'total': 10.0}),
      ]);
      expect(res[resultKey('Bills', 'b1')]!.ok, isTrue);
      final expected = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(envelope['payload'] as String)).toString();
      expect(envelope['sig'], expected);
      expect(envelope['payload'], isNot(contains(secret)));
    });

    test('server rejection is reported as failure, not success', () async {
      final client = MockClient((_) async => http.Response(jsonEncode({'ok': false, 'error': 'Invalid signature'}), 200));
      final t = AppsScriptTransport(url: 'https://script.google.com/x/exec', secret: 'y' * 20, client: client);
      expect(
          () => t.send([const SyncRecord(queueId: 1, queueVersion: 1, entityType: 'bill', sheet: 'Bills', key: 'k', row: {})]),
          throwsA(isA<SyncTransportException>()));
    });

    test('HTML error page is not mistaken for success', () async {
      final client = MockClient((_) async => http.Response('<html>Sign in</html>', 200));
      final t = AppsScriptTransport(url: 'https://script.google.com/x/exec', secret: 'y' * 20, client: client);
      expect(() => t.ping(), throwsA(isA<SyncTransportException>()));
    });
  });
}
