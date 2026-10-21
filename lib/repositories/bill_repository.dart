import '../database/db_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/app_settings.dart';
import '../models/bill.dart';
import '../models/user.dart';
import '../services/billing_calculator.dart';
import '../utils/dates.dart';
import '../utils/errors.dart';
import '../utils/ids.dart';
import 'permissions.dart';
import 'sync_queue.dart';

/// A cart line as submitted by the billing screen. Only product id and quantity are
/// accepted: the unit price is always read from the database inside the transaction,
/// so a cashier can never change a price.
class CartLineInput {
  final int productId;
  final int quantity;
  const CartLineInput(this.productId, this.quantity);
}

/// A hand-typed bill line (e.g. "Gas cylinder", "Staff lunch"). Allowed for admins,
/// and for cashiers only when enabled in Settings.
class CustomLineInput {
  final String name;
  final int unitPrice; // paisa
  final int quantity;
  final bool kitchen;
  const CustomLineInput(this.name, this.unitPrice, this.quantity, {this.kitchen = false});
}

class BillFilter {
  final String? fromDate; // yyyy-MM-dd inclusive
  final String? toDate;
  final int? cashierId;
  final PaymentStatus? status;
  final BillType? type;
  final String search;
  final bool outstandingOnly;
  final int limit;
  const BillFilter({
    this.fromDate,
    this.toDate,
    this.cashierId,
    this.status,
    this.type,
    this.search = '',
    this.outstandingOnly = false,
    this.limit = 500,
  });
}

class BillRepository {
  final Database db;
  BillRepository(this.db);

  /// Test hook: runs inside the bill transaction just before it commits.
  @visibleForTesting
  Future<void> Function(Transaction txn)? beforeCommitHook;

  static String formatInvoice(String prefix, DateTime date, int seq) =>
      '$prefix-${Dates.compact(date)}-${seq.toString().padLeft(4, '0')}';

  /// Saves the bill, all items and the initial payment in ONE transaction.
  /// [billId] is an idempotency key generated when the cart was started: calling this
  /// again with the same id (double click, retry) returns the existing bill instead of
  /// creating a duplicate.
  Future<Bill> completeBill(
    AppUser actor, {
    required String billId,
    required List<CartLineInput> lines,
    List<CustomLineInput> customLines = const [],
    BillType type = BillType.sale,
    required AppSettings settings,
    int discount = 0,
    required int amountReceived,
    String method = 'Cash',
    String customerNote = '',
    DateTime? now,
  }) async {
    Permissions.requireUser(actor);
    if (lines.isEmpty && customLines.isEmpty) throw ValidationException('The bill has no items.');
    if (!paymentMethods.contains(method)) throw ValidationException('Unknown payment method.');
    if (customerNote.length > 80) throw ValidationException('Note must be at most 80 characters.');
    if (type == BillType.expense) Permissions.requireAdmin(actor, 'record expenses');
    if (customLines.isNotEmpty && !actor.isAdmin && !settings.cashierCustomItems) {
      throw PermissionDeniedException('Only an admin can add custom items.');
    }
    for (final c in customLines) {
      final n = c.name.trim();
      if (n.isEmpty || n.length > 60) throw ValidationException('Custom item name must be 1-60 characters.');
      if (c.unitPrice < 0) throw ValidationException('Price cannot be negative.');
      if (c.unitPrice > 10000000 * 100) throw ValidationException('Price is too large.');
      if (c.quantity <= 0 || c.quantity > BillingCalculator.maxQuantity) {
        throw ValidationException('Quantity must be between 1 and ${BillingCalculator.maxQuantity}.');
      }
    }
    final isSale = type == BillType.sale;
    if (!isSale) {
      discount = 0; // personal food and expenses are recorded at full value, unpaid by customers
      amountReceived = 0;
    }
    final ts = now ?? DateTime.now();
    final createdAt = Dates.db(ts);
    final businessDate = Dates.day(ts);

    final bill = await db.transaction((txn) async {
      final existing = await txn.query('bills', columns: ['id'], where: 'id = ?', whereArgs: [billId]);
      if (existing.isNotEmpty) return null; // already saved – idempotent

      // Merge duplicate lines and load authoritative prices.
      final qty = <int, int>{};
      for (final l in lines) {
        if (l.quantity <= 0 || l.quantity > BillingCalculator.maxQuantity) {
          throw ValidationException('Quantity must be between 1 and ${BillingCalculator.maxQuantity}.');
        }
        qty[l.productId] = (qty[l.productId] ?? 0) + l.quantity;
      }
      final itemRows = <Map<String, Object?>>[];
      final calcLines = <CalcLine>[];
      var lineNo = 0;
      for (final e in qty.entries) {
        final rows = await txn.rawQuery('''
          SELECT p.id, p.name, p.price, p.active, p.deleted_at, c.name AS category_name, c.kitchen
          FROM products p JOIN categories c ON c.id = p.category_id WHERE p.id = ?''', [e.key]);
        if (rows.isEmpty || rows.first['deleted_at'] != null || rows.first['active'] != 1) {
          throw ValidationException('A product in the cart is no longer available. Please remove it.');
        }
        final r = rows.first;
        final price = r['price'] as int;
        if (e.value > BillingCalculator.maxQuantity) {
          throw ValidationException('Quantity must be at most ${BillingCalculator.maxQuantity}.');
        }
        calcLines.add(CalcLine(e.value, price));
        itemRows.add({
          'id': Ids.newId(),
          'bill_id': billId,
          'line_no': ++lineNo,
          'product_id': r['id'],
          'product_name': r['name'],
          'category_name': r['category_name'],
          'quantity': e.value,
          'unit_price': price,
          'line_total': e.value * price,
          'is_custom': 0,
          'kitchen': type == BillType.expense ? 0 : (r['kitchen'] as int? ?? 1),
        });
      }
      for (final c in customLines) {
        calcLines.add(CalcLine(c.quantity, c.unitPrice));
        itemRows.add({
          'id': Ids.newId(),
          'bill_id': billId,
          'line_no': ++lineNo,
          'product_id': null,
          'product_name': c.name.trim(),
          'category_name': type == BillType.expense ? 'Expense' : 'Custom',
          'quantity': c.quantity,
          'unit_price': c.unitPrice,
          'line_total': c.quantity * c.unitPrice,
          'is_custom': 1,
          'kitchen': type != BillType.expense && c.kitchen ? 1 : 0,
        });
      }

      final totals = BillingCalculator.totals(calcLines,
          discount: discount, roundingStep: isSale ? settings.roundingStep : 0);
      if (!actor.isAdmin && discount > 0) {
        final maxDiscount = BillingCalculator.percentDiscount(totals.subtotal, settings.cashierMaxDiscountPct * 100);
        if (discount > maxDiscount) {
          throw PermissionDeniedException(
              'Cashiers can give at most ${settings.cashierMaxDiscountPct}% discount. Ask an admin.');
        }
      }
      // Non-sale bills carry no customer balance and no payment.
      final pay = isSale
          ? BillingCalculator.payment(due: totals.total, received: amountReceived)
          : const PaymentOutcome(0, 0, 0);

      final seq = (firstIntValue(await txn.rawQuery(
                  'SELECT COALESCE(MAX(invoice_seq), 0) FROM bills WHERE business_date = ?', [businessDate])) ??
              0) +
          1;
      final prefix = switch (type) {
        BillType.sale => settings.invoicePrefix,
        BillType.personal => 'PF',
        BillType.expense => 'EX',
      };
      final invoiceNo = formatInvoice(prefix, ts, seq);

      await txn.insert('bills', {
        'id': billId,
        'invoice_no': invoiceNo,
        'invoice_seq': seq,
        'business_date': businessDate,
        'created_at': createdAt,
        'updated_at': createdAt,
        'cashier_id': actor.id,
        'cashier_name': actor.displayName,
        'customer_note': customerNote.trim(),
        'subtotal': totals.subtotal,
        'discount': totals.discount,
        'rounding': totals.rounding,
        'total': totals.total,
        'amount_paid': pay.applied,
        'balance_due': pay.balanceDue,
        'payment_status': isSale ? PaymentStatus.of(totals.total, pay.applied).dbValue : PaymentStatus.paid.dbValue,
        'sync_status': 'pending',
        'bill_type': type.name,
      });
      for (final item in itemRows) {
        await txn.insert('bill_items', item);
        await enqueueSync(txn, SyncEntity.billItem, item['id'] as String);
      }
      if (pay.applied > 0) {
        final paymentId = Ids.newId();
        await txn.insert('payments', {
          'id': paymentId,
          'bill_id': billId,
          'amount': pay.applied,
          'tendered': amountReceived,
          'change_given': pay.changeReturned,
          'method': method,
          'received_by_id': actor.id,
          'received_by_name': actor.displayName,
          'created_at': createdAt,
          'business_date': businessDate,
        });
        await enqueueSync(txn, SyncEntity.payment, paymentId);
      }
      await enqueueSync(txn, SyncEntity.bill, billId);
      await enqueueSync(txn, SyncEntity.dailySummary, businessDate);
      if (beforeCommitHook != null) await beforeCommitHook!(txn);
      return billId;
    });
    return (await getBill(bill ?? billId))!;
  }

  /// Records an additional payment against an outstanding balance.
  Future<Bill> addPayment(AppUser actor, String billId,
      {required int amountReceived, String method = 'Cash', DateTime? now}) async {
    Permissions.requireUser(actor);
    if (amountReceived <= 0) throw ValidationException('Enter the amount received.');
    if (!paymentMethods.contains(method)) throw ValidationException('Unknown payment method.');
    final ts = now ?? DateTime.now();
    await db.transaction((txn) async {
      final rows = await txn.query('bills', where: 'id = ?', whereArgs: [billId]);
      if (rows.isEmpty) throw ValidationException('Bill not found.');
      final b = rows.first;
      if (!actor.isAdmin && b['cashier_id'] != actor.id) {
        throw PermissionDeniedException('You can only take payments on your own bills.');
      }
      final due = b['balance_due'] as int;
      if (due <= 0) throw ValidationException('This bill is already fully paid.');
      final pay = BillingCalculator.payment(due: due, received: amountReceived);
      final paymentId = Ids.newId();
      final createdAt = Dates.db(ts);
      await txn.insert('payments', {
        'id': paymentId,
        'bill_id': billId,
        'amount': pay.applied,
        'tendered': amountReceived,
        'change_given': pay.changeReturned,
        'method': method,
        'received_by_id': actor.id,
        'received_by_name': actor.displayName,
        'created_at': createdAt,
        'business_date': Dates.day(ts),
      });
      final paid = (b['amount_paid'] as int) + pay.applied;
      final total = b['total'] as int;
      await txn.update(
          'bills',
          {
            'amount_paid': paid,
            'balance_due': total - paid,
            'payment_status': PaymentStatus.of(total, paid).dbValue,
            'updated_at': createdAt,
            'sync_status': 'pending',
          },
          where: 'id = ?',
          whereArgs: [billId]);
      await enqueueSync(txn, SyncEntity.payment, paymentId);
      await enqueueSync(txn, SyncEntity.bill, billId);
      await enqueueSync(txn, SyncEntity.dailySummary, b['business_date'] as String);
      await enqueueSync(txn, SyncEntity.dailySummary, Dates.day(ts));
    });
    return (await getBill(billId))!;
  }

  /// Marks an unpaid / partially paid bill as fully paid by recording the remaining balance.
  Future<Bill> markPaid(AppUser actor, String billId, {String method = 'Cash', DateTime? now}) async {
    final b = await getBill(billId);
    if (b == null) throw ValidationException('Bill not found.');
    if (b.balanceDue <= 0) throw ValidationException('This bill is already fully paid.');
    return addPayment(actor, billId, amountReceived: b.balanceDue, method: method, now: now);
  }

  /// Records that a receipt was printed. Never creates a bill.
  Future<void> markPrinted(String billId) async {
    await db.rawUpdate(
        'UPDATE bills SET print_count = print_count + 1, last_printed_at = ? WHERE id = ?', [Dates.dbNow(), billId]);
  }

  Future<Bill?> getBill(String id) async {
    final rows = await db.query('bills', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final items = await db.query('bill_items', where: 'bill_id = ?', whereArgs: [id], orderBy: 'line_no');
    final payments = await db.query('payments', where: 'bill_id = ?', whereArgs: [id], orderBy: 'created_at');
    return Bill.fromRow(rows.first,
        items: items.map(BillItem.fromRow).toList(), payments: payments.map(Payment.fromRow).toList());
  }

  /// Bill history. Cashiers only ever see their own bills.
  Future<List<Bill>> list(AppUser actor, BillFilter f) async {
    Permissions.requireUser(actor);
    final where = <String>[];
    final args = <Object?>[];
    final cashierId = actor.isAdmin ? f.cashierId : actor.id;
    if (cashierId != null) {
      where.add('cashier_id = ?');
      args.add(cashierId);
    }
    if (f.fromDate != null) {
      where.add('business_date >= ?');
      args.add(f.fromDate);
    }
    if (f.toDate != null) {
      where.add('business_date <= ?');
      args.add(f.toDate);
    }
    if (f.status != null) {
      where.add('payment_status = ?');
      args.add(f.status!.dbValue);
    }
    if (f.type != null) {
      where.add('bill_type = ?');
      args.add(f.type!.name);
    }
    if (f.outstandingOnly) where.add('balance_due > 0');
    if (f.search.trim().isNotEmpty) {
      where.add('(invoice_no LIKE ? OR customer_note LIKE ?)');
      args.addAll(['%${f.search.trim()}%', '%${f.search.trim()}%']);
    }
    final rows = await db.query('bills',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'created_at DESC, invoice_seq DESC',
        limit: f.limit);
    return rows.map((r) => Bill.fromRow(r)).toList();
  }
}
