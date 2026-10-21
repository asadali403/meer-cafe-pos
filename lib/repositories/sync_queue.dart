import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/dates.dart';

/// Entity types placed on the Google Sheets sync queue.
class SyncEntity {
  SyncEntity._();
  static const product = 'product';
  static const bill = 'bill';
  static const billItem = 'bill_item';
  static const payment = 'payment';
  static const dailySummary = 'daily_summary';
  static const syncLog = 'sync_log';
}

/// Marks an entity as needing upload. Must be called inside the same transaction
/// that changed the entity so the queue can never miss a change.
/// Re-enqueuing an existing entity bumps its version instead of adding a duplicate.
Future<void> enqueueSync(DatabaseExecutor db, String type, String id) async {
  final now = Dates.dbNow();
  await db.rawInsert('''
    INSERT INTO sync_queue (entity_type, entity_id, status, version, attempts, next_attempt_at, created_at, updated_at)
    VALUES (?, ?, 'pending', 1, 0, ?, ?, ?)
    ON CONFLICT(entity_type, entity_id) DO UPDATE SET
      status = 'pending',
      version = version + 1,
      attempts = 0,
      last_error = NULL,
      next_attempt_at = excluded.next_attempt_at,
      updated_at = excluded.updated_at
  ''', [type, id, now, now, now]);
}
