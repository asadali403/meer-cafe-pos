import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/app_settings.dart';
import '../repositories/report_repository.dart';
import '../repositories/sync_queue.dart';
import '../utils/dates.dart';
import '../utils/ids.dart';
import 'sync_transport.dart';

class SyncCounts {
  final int pending;
  final int failed;
  final int synced;
  const SyncCounts(this.pending, this.failed, this.synced);
  static const zero = SyncCounts(0, 0, 0);
}

/// Pushes the local sync queue to Google Sheets. SQLite stays the source of truth:
/// records are only marked synced after the server confirms each one, and local
/// records are never deleted.
class SyncService extends ChangeNotifier {
  final Database db;
  final Future<AppSettings> Function() loadSettings;
  final SyncTransport? Function(AppSettings settings) transportFor;
  final int batchSize;

  SyncService({
    required this.db,
    required this.loadSettings,
    SyncTransport? Function(AppSettings settings)? transportFor,
    this.batchSize = 50,
  }) : transportFor = transportFor ?? defaultTransport;

  static SyncTransport? defaultTransport(AppSettings s) =>
      s.syncConfigured ? AppsScriptTransport(url: s.syncUrl, secret: s.syncSecret) : null;

  SyncCounts counts = SyncCounts.zero;
  bool running = false;
  String lastMessage = '';
  String? lastRunAt;
  Timer? _timer;
  StreamSubscription<Object?>? _connSub;
  bool _disposed = false;

  static const sheets = {
    SyncEntity.product: 'Products',
    SyncEntity.bill: 'Bills',
    SyncEntity.billItem: 'BillItems',
    SyncEntity.payment: 'Payments',
    SyncEntity.dailySummary: 'DailySummary',
    SyncEntity.syncLog: 'SyncLog',
  };

  /// Starts automatic sync: on startup, every minute, and whenever connectivity changes.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => run(trigger: 'auto'));
    try {
      _connSub = Connectivity().onConnectivityChanged.listen((_) {
        Future.delayed(const Duration(seconds: 3), () => run(trigger: 'connectivity'));
      });
    } catch (_) {
      // Connectivity events are a bonus; the periodic timer still retries.
    }
    Future.delayed(const Duration(seconds: 4), () => run(trigger: 'startup'));
    refreshCounts();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<SyncCounts> refreshCounts() async {
    try {
      final rows = await db.rawQuery('SELECT status, COUNT(*) AS n FROM sync_queue GROUP BY status');
      final m = {for (final r in rows) r['status'] as String: r['n'] as int};
      counts = SyncCounts(m['pending'] ?? 0, m['failed'] ?? 0, m['synced'] ?? 0);
      _notify();
    } catch (_) {
      // Database may be closing (e.g. during restore).
    }
    return counts;
  }

  /// Runs one sync pass. [force] ignores retry back-off (used by "Sync Now").
  Future<String> run({String trigger = 'manual', bool force = false}) async {
    if (running || _disposed) return 'Sync already running.';
    final settings = await loadSettings();
    final transport = transportFor(settings);
    if (transport == null) {
      lastMessage = settings.syncEnabled
          ? 'Google Sheets sync is enabled but the URL or secret is missing/invalid.'
          : 'Google Sheets sync is turned off.';
      await refreshCounts();
      return lastMessage;
    }
    running = true;
    _notify();
    final startedAt = Dates.dbNow();
    var sent = 0, ok = 0, failed = 0, dataSent = 0;
    String? fatal;
    try {
      var cursor = 0; // each queue row is attempted at most once per run
      for (var round = 0; round < 40; round++) {
        final now = Dates.dbNow();
        final due = await db.rawQuery('''
          SELECT * FROM sync_queue WHERE status <> 'synced' AND id > ? ${force ? '' : 'AND next_attempt_at <= ?'}
          ORDER BY id LIMIT ?''', [cursor, if (!force) now, batchSize]);
        if (due.isEmpty) break;
        cursor = due.last['id'] as int;
        final records = <SyncRecord>[];
        for (final q in due) {
          final rec = await _build(q);
          if (rec == null) {
            await _markFailed(q, 'Local record not found');
            failed++;
          } else {
            records.add(rec);
          }
        }
        if (records.isEmpty) continue;
        sent += records.length;
        dataSent += records.where((r) => r.entityType != SyncEntity.syncLog).length;
        Map<String, SyncResult> results;
        try {
          results = await transport.send(records);
        } catch (e) {
          fatal = e.toString();
          for (final r in records) {
            await _markFailedById(r, fatal);
          }
          failed += records.length;
          break;
        }
        for (final r in records) {
          final res = results[resultKey(r.sheet, r.key)];
          if (res != null && res.ok) {
            await _markSynced(r);
            ok++;
          } else {
            await _markFailedById(r, res?.error ?? 'No confirmation from server');
            failed++;
          }
        }
        if (due.length < batchSize) break;
      }
      lastMessage = fatal != null
          ? 'Sync failed: $fatal'
          : sent == 0
              ? 'Everything is up to date.'
              : 'Synced $ok record(s)${failed > 0 ? ', $failed failed' : ''}.';
    } catch (e) {
      lastMessage = 'Sync error: $e';
    } finally {
      lastRunAt = Dates.dbNow();
      if (dataSent > 0 || (fatal != null && trigger == 'manual')) {
        await _writeLog(startedAt, trigger, sent, ok, failed, lastMessage);
      }
      running = false;
      await refreshCounts();
    }
    return lastMessage;
  }

  Future<void> _writeLog(String startedAt, String trigger, int sent, int ok, int failed, String msg) async {
    try {
      final id = Ids.newId();
      await db.transaction((txn) async {
        await txn.insert('sync_logs', {
          'id': id,
          'started_at': startedAt,
          'finished_at': Dates.dbNow(),
          'trigger': trigger,
          'sent': sent,
          'succeeded': ok,
          'failed': failed,
          'message': msg.length > 500 ? msg.substring(0, 500) : msg,
        });
        await enqueueSync(txn, SyncEntity.syncLog, id);
      });
    } catch (_) {}
  }

  Future<void> _markSynced(SyncRecord r) async {
    final now = Dates.dbNow();
    await db.transaction((txn) async {
      final n = await txn.rawUpdate('''
        UPDATE sync_queue SET status='synced', synced_at=?, attempts=attempts+1, last_error=NULL, updated_at=?
        WHERE id=? AND version=?''', [now, now, r.queueId, r.queueVersion]);
      // If the entity changed while uploading, the version moved on and it stays pending.
      if (n == 1 && r.entityType == SyncEntity.bill) {
        await txn.update('bills', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [r.key]);
      }
    });
  }

  Future<void> _markFailedById(SyncRecord r, String error) async {
    final rows = await db.query('sync_queue', where: 'id = ?', whereArgs: [r.queueId]);
    if (rows.isEmpty) return;
    if (rows.first['version'] != r.queueVersion) return; // changed meanwhile; stays pending
    await _markFailed(rows.first, error);
  }

  Future<void> _markFailed(Map<String, Object?> q, String error) async {
    final attempts = (q['attempts'] as int) + 1;
    final delay = Duration(seconds: min(1800, 30 * pow(2, min(attempts - 1, 6)).toInt()));
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.update(
          'sync_queue',
          {
            'status': 'failed',
            'attempts': attempts,
            'last_error': error.length > 500 ? error.substring(0, 500) : error,
            'next_attempt_at': Dates.db(now.add(delay)),
            'updated_at': Dates.db(now),
          },
          where: 'id = ? AND version = ?',
          whereArgs: [q['id'], q['version']]);
      if (q['entity_type'] == SyncEntity.bill) {
        await txn.update('bills', {'sync_status': 'failed'}, where: 'id = ?', whereArgs: [q['entity_id']]);
      }
    });
  }

  static double _rs(Object? paisa) => ((paisa as int?) ?? 0) / 100.0;

  /// Builds the current snapshot of an entity as a worksheet row.
  Future<SyncRecord?> _build(Map<String, Object?> q) async {
    final type = q['entity_type'] as String;
    final id = q['entity_id'] as String;
    final sheet = sheets[type];
    if (sheet == null) return null;
    Map<String, Object?>? row;
    switch (type) {
      case SyncEntity.product:
        final r = await db.rawQuery('''
          SELECT p.*, c.name AS category_name FROM products p JOIN categories c ON c.id = p.category_id
          WHERE p.id = ?''', [int.tryParse(id) ?? -1]);
        if (r.isNotEmpty) {
          final p = r.first;
          row = {
            'id': id,
            'name': p['name'],
            'category': p['category_name'],
            'price': _rs(p['price']),
            'description': p['description'],
            'active': p['active'] == 1 ? 'YES' : 'NO',
            'deleted': p['deleted_at'] == null ? 'NO' : 'YES',
            'created_at': p['created_at'],
            'updated_at': p['updated_at'],
          };
        }
      case SyncEntity.bill:
        final r = await db.query('bills', where: 'id = ?', whereArgs: [id]);
        if (r.isNotEmpty) {
          final b = r.first;
          row = {
            'id': id,
            'invoice_no': b['invoice_no'],
            'bill_type': switch (b['bill_type']) {
              'personal' => 'PERSONAL FOOD',
              'expense' => 'EXPENSE',
              _ => 'SALE',
            },
            'business_date': b['business_date'],
            'created_at': b['created_at'],
            'cashier': b['cashier_name'],
            'customer_note': b['customer_note'],
            'subtotal': _rs(b['subtotal']),
            'discount': _rs(b['discount']),
            'rounding': _rs(b['rounding']),
            'total': _rs(b['total']),
            'amount_paid': _rs(b['amount_paid']),
            'balance_due': _rs(b['balance_due']),
            'payment_status': switch (b['payment_status']) {
              'paid' => 'PAID',
              'partial' => 'PARTIALLY PAID',
              _ => 'UNPAID',
            },
            'updated_at': b['updated_at'],
          };
        }
      case SyncEntity.billItem:
        final r = await db.rawQuery('''
          SELECT i.*, b.invoice_no FROM bill_items i JOIN bills b ON b.id = i.bill_id WHERE i.id = ?''', [id]);
        if (r.isNotEmpty) {
          final i = r.first;
          row = {
            'id': id,
            'bill_id': i['bill_id'],
            'invoice_no': i['invoice_no'],
            'line_no': i['line_no'],
            'product_id': i['product_id'] ?? '',
            'product_name': i['product_name'],
            'category': i['category_name'],
            'quantity': i['quantity'],
            'unit_price': _rs(i['unit_price']),
            'line_total': _rs(i['line_total']),
            'custom_item': i['is_custom'] == 1 ? 'YES' : 'NO',
          };
        }
      case SyncEntity.payment:
        final r = await db.rawQuery('''
          SELECT p.*, b.invoice_no FROM payments p JOIN bills b ON b.id = p.bill_id WHERE p.id = ?''', [id]);
        if (r.isNotEmpty) {
          final p = r.first;
          row = {
            'id': id,
            'bill_id': p['bill_id'],
            'invoice_no': p['invoice_no'],
            'created_at': p['created_at'],
            'business_date': p['business_date'],
            'method': p['method'],
            'amount': _rs(p['amount']),
            'tendered': _rs(p['tendered']),
            'change_given': _rs(p['change_given']),
            'received_by': p['received_by_name'],
          };
        }
      case SyncEntity.dailySummary:
        final s = await ReportRepository(db).dailySummaryRow(id);
        row = {
          'id': id,
          'bills': s['bills'],
          'gross_sales': _rs(s['gross']),
          'discount': _rs(s['discount']),
          'billed_sales': _rs(s['billed']),
          'collected': _rs(s['collected']),
          'payments': s['payments'],
          'outstanding': _rs(s['outstanding']),
          'personal_food': _rs(s['personal']),
          'expenses': _rs(s['expenses']),
          'updated_at': Dates.dbNow(),
        };
      case SyncEntity.syncLog:
        final r = await db.query('sync_logs', where: 'id = ?', whereArgs: [id]);
        if (r.isNotEmpty) {
          row = {...r.first};
        }
    }
    if (row == null) return null;
    return SyncRecord(
      queueId: q['id'] as int,
      queueVersion: q['version'] as int,
      entityType: type,
      sheet: sheet,
      key: id,
      row: row,
    );
  }

  /// Recent queue entries with errors (for the admin Sync screen).
  Future<List<Map<String, Object?>>> problemItems({int limit = 100}) => db.query('sync_queue',
      where: "status = 'failed'", orderBy: 'updated_at DESC', limit: limit);

  Future<List<Map<String, Object?>>> recentLogs({int limit = 30}) =>
      db.query('sync_logs', orderBy: 'started_at DESC', limit: limit);
}
