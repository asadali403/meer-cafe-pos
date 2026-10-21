import '../database/db_utils.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/user.dart';
import 'permissions.dart';

class SalesSummary {
  final int bills;
  final int billed; // total value of bills issued (after discount)
  final int discount;
  final int collected; // payments actually received in the period
  final int outstanding; // unpaid balance of bills issued in the period
  final int paidBills;
  final int partialBills;
  final int unpaidBills;
  final int personalTotal; // personal / staff food (not revenue)
  final int personalBills;
  final int expenseTotal; // expenses paid out (not revenue)
  final int expenseBills;
  const SalesSummary({
    this.personalTotal = 0,
    this.personalBills = 0,
    this.expenseTotal = 0,
    this.expenseBills = 0,
    required this.bills,
    required this.billed,
    required this.discount,
    required this.collected,
    required this.outstanding,
    required this.paidBills,
    required this.partialBills,
    required this.unpaidBills,
  });
}

/// Generic tabular report result (also used for CSV export).
class ReportTable {
  final List<String> columns;
  final List<List<Object?>> rows;

  /// Columns holding paisa values (formatted as money).
  final Set<int> moneyColumns;
  const ReportTable(this.columns, this.rows, {this.moneyColumns = const {}});
}

enum Grouping { day, week, month }

/// Read-only reporting queries (admin only). Billed sales and cash collected are
/// always reported separately; unpaid balances are never counted as collected.
class ReportRepository {
  final Database db;
  ReportRepository(this.db);

  Future<int> _int(String sql, [List<Object?> args = const []]) async =>
      firstIntValue(await db.rawQuery(sql, args)) ?? 0;

  Future<SalesSummary> summary(AppUser actor, String from, String to) async {
    Permissions.requireAdmin(actor, 'view reports');
    final r = (await db.rawQuery('''
      SELECT COUNT(*) AS bills, COALESCE(SUM(total),0) AS billed, COALESCE(SUM(discount),0) AS discount,
             COALESCE(SUM(balance_due),0) AS outstanding,
             COALESCE(SUM(payment_status='paid'),0) AS paid_bills,
             COALESCE(SUM(payment_status='partial'),0) AS partial_bills,
             COALESCE(SUM(payment_status='unpaid'),0) AS unpaid_bills
      FROM bills WHERE bill_type = 'sale' AND business_date BETWEEN ? AND ?''', [from, to])).first;
    final collected =
        await _int('SELECT COALESCE(SUM(amount),0) FROM payments WHERE business_date BETWEEN ? AND ?', [from, to]);
    final other = {
      for (final x in await db.rawQuery('''
        SELECT bill_type, COUNT(*) AS n, COALESCE(SUM(total),0) AS total FROM bills
        WHERE bill_type <> 'sale' AND business_date BETWEEN ? AND ? GROUP BY bill_type''', [from, to]))
        x['bill_type'] as String: x
    };
    return SalesSummary(
      personalTotal: (other['personal']?['total'] as int?) ?? 0,
      personalBills: (other['personal']?['n'] as int?) ?? 0,
      expenseTotal: (other['expense']?['total'] as int?) ?? 0,
      expenseBills: (other['expense']?['n'] as int?) ?? 0,
      bills: r['bills'] as int,
      billed: r['billed'] as int,
      discount: r['discount'] as int,
      collected: collected,
      outstanding: r['outstanding'] as int,
      paidBills: r['paid_bills'] as int,
      partialBills: r['partial_bills'] as int,
      unpaidBills: r['unpaid_bills'] as int,
    );
  }

  /// All outstanding customer balances, regardless of date.
  Future<int> totalOutstanding(AppUser actor) async {
    Permissions.requireAdmin(actor, 'view reports');
    return _int('SELECT COALESCE(SUM(balance_due),0) FROM bills WHERE balance_due > 0');
  }

  String _groupExpr(Grouping g, String col) => switch (g) {
        Grouping.day => col,
        Grouping.week => "date($col, '-' || ((CAST(strftime('%w', $col) AS INTEGER) + 6) % 7) || ' days')",
        Grouping.month => "strftime('%Y-%m', $col)",
      };

  /// Sales by day/week(Monday start)/month: billed vs collected.
  Future<ReportTable> salesByPeriod(AppUser actor, String from, String to, Grouping g) async {
    Permissions.requireAdmin(actor, 'view reports');
    final billRows = await db.rawQuery('''
      SELECT ${_groupExpr(g, 'business_date')} AS period, COUNT(*) AS bills, SUM(subtotal) AS gross,
             SUM(discount) AS discount, SUM(total) AS billed, SUM(balance_due) AS outstanding
      FROM bills WHERE bill_type = 'sale' AND business_date BETWEEN ? AND ? GROUP BY period''', [from, to]);
    final payRows = await db.rawQuery('''
      SELECT ${_groupExpr(g, 'business_date')} AS period, SUM(amount) AS collected
      FROM payments WHERE business_date BETWEEN ? AND ? GROUP BY period''', [from, to]);
    final map = <String, List<Object?>>{};
    for (final r in billRows) {
      map[r['period'] as String] = [r['period'], r['bills'], r['gross'], r['discount'], r['billed'], 0, r['outstanding']];
    }
    for (final r in payRows) {
      final row = map.putIfAbsent(r['period'] as String, () => [r['period'], 0, 0, 0, 0, 0, 0]);
      row[5] = r['collected'];
    }
    final keys = map.keys.toList()..sort();
    final label = switch (g) { Grouping.day => 'Date', Grouping.week => 'Week starting', Grouping.month => 'Month' };
    return ReportTable([label, 'Bills', 'Gross sales', 'Discount', 'Billed sales', 'Collected', 'Outstanding'],
        [for (final k in keys) map[k]!],
        moneyColumns: {2, 3, 4, 5, 6});
  }

  Future<ReportTable> productSales(AppUser actor, String from, String to) async {
    Permissions.requireAdmin(actor, 'view reports');
    final rows = await db.rawQuery('''
      SELECT i.product_name, i.category_name, SUM(i.quantity) AS qty, SUM(i.line_total) AS amount
      FROM bill_items i JOIN bills b ON b.id = i.bill_id
      WHERE b.bill_type = 'sale' AND b.business_date BETWEEN ? AND ?
      GROUP BY i.product_name, i.category_name ORDER BY amount DESC''', [from, to]);
    return ReportTable(['Product', 'Category', 'Qty sold', 'Gross amount'],
        [for (final r in rows) [r['product_name'], r['category_name'], r['qty'], r['amount']]],
        moneyColumns: {3});
  }

  Future<ReportTable> cashierSales(AppUser actor, String from, String to) async {
    Permissions.requireAdmin(actor, 'view reports');
    final bills = await db.rawQuery('''
      SELECT cashier_name, COUNT(*) AS bills, SUM(total) AS billed, SUM(balance_due) AS outstanding
      FROM bills WHERE bill_type = 'sale' AND business_date BETWEEN ? AND ? GROUP BY cashier_id, cashier_name''', [from, to]);
    final pays = await db.rawQuery('''
      SELECT received_by_name, SUM(amount) AS collected FROM payments
      WHERE business_date BETWEEN ? AND ? GROUP BY received_by_id, received_by_name''', [from, to]);
    final map = <String, List<Object?>>{};
    for (final r in bills) {
      map[r['cashier_name'] as String] = [r['cashier_name'], r['bills'], r['billed'], 0, r['outstanding']];
    }
    for (final r in pays) {
      final row = map.putIfAbsent(r['received_by_name'] as String, () => [r['received_by_name'], 0, 0, 0, 0]);
      row[3] = r['collected'];
    }
    return ReportTable(['Cashier', 'Bills', 'Billed sales', 'Collected', 'Outstanding'], map.values.toList(),
        moneyColumns: {2, 3, 4});
  }

  Future<ReportTable> paymentMethods(AppUser actor, String from, String to) async {
    Permissions.requireAdmin(actor, 'view reports');
    final rows = await db.rawQuery('''
      SELECT method, COUNT(*) AS n, SUM(amount) AS amount FROM payments
      WHERE business_date BETWEEN ? AND ? GROUP BY method ORDER BY amount DESC''', [from, to]);
    return ReportTable(['Payment method', 'Payments', 'Amount collected'],
        [for (final r in rows) [r['method'], r['n'], r['amount']]],
        moneyColumns: {2});
  }

  Future<ReportTable> paymentsCollected(AppUser actor, String from, String to) async {
    Permissions.requireAdmin(actor, 'view reports');
    final rows = await db.rawQuery('''
      SELECT p.created_at, b.invoice_no, p.method, p.received_by_name, p.tendered, p.change_given, p.amount
      FROM payments p JOIN bills b ON b.id = p.bill_id
      WHERE p.business_date BETWEEN ? AND ? ORDER BY p.created_at''', [from, to]);
    return ReportTable(['Time', 'Invoice', 'Method', 'Received by', 'Tendered', 'Change', 'Collected'],
        [for (final r in rows) r.values.toList()],
        moneyColumns: {4, 5, 6});
  }

  Future<ReportTable> billsByStatus(AppUser actor, String from, String to, {String? status}) async {
    Permissions.requireAdmin(actor, 'view reports');
    final rows = await db.rawQuery('''
      SELECT invoice_no, created_at, cashier_name, customer_note, total, amount_paid, balance_due, payment_status
      FROM bills WHERE bill_type = 'sale' AND business_date BETWEEN ? AND ? ${status == null ? '' : 'AND payment_status = ?'}
      ORDER BY created_at''', [from, to, ?status]);
    return ReportTable(['Invoice', 'Time', 'Cashier', 'Customer note', 'Total', 'Paid', 'Balance', 'Status'],
        [
          for (final r in rows)
            [...r.values.take(7), switch (r['payment_status']) { 'paid' => 'PAID', 'partial' => 'PARTIALLY PAID', _ => 'UNPAID' }]
        ],
        moneyColumns: {4, 5, 6});
  }

  /// Personal/staff food or expense bills with their items (never part of sales).
  Future<ReportTable> nonSaleBills(AppUser actor, String from, String to, String type) async {
    Permissions.requireAdmin(actor, 'view reports');
    final rows = await db.rawQuery('''
      SELECT b.invoice_no, b.created_at, b.cashier_name, b.customer_note,
             (SELECT GROUP_CONCAT(i.quantity || ' x ' || i.product_name, ', ') FROM bill_items i WHERE i.bill_id = b.id) AS items,
             b.total
      FROM bills b WHERE b.bill_type = ? AND b.business_date BETWEEN ? AND ? ORDER BY b.created_at''',
        [type, from, to]);
    return ReportTable(['Voucher', 'Time', 'Entered by', 'Note', 'Items', 'Amount'],
        [for (final r in rows) r.values.toList()],
        moneyColumns: {5});
  }

  Future<ReportTable> outstandingBalances(AppUser actor) async {
    Permissions.requireAdmin(actor, 'view reports');
    final rows = await db.rawQuery('''
      SELECT invoice_no, created_at, cashier_name, customer_note, total, amount_paid, balance_due
      FROM bills WHERE balance_due > 0 ORDER BY created_at''');
    return ReportTable(['Invoice', 'Time', 'Cashier', 'Customer note', 'Total', 'Paid', 'Balance due'],
        [for (final r in rows) r.values.toList()],
        moneyColumns: {4, 5, 6});
  }

  Future<ReportTable> recentBills(AppUser actor, {int limit = 10}) async {
    Permissions.requireAdmin(actor, 'view reports');
    final rows = await db.rawQuery('''
      SELECT invoice_no, created_at, cashier_name, total, amount_paid,
             CASE WHEN bill_type = 'sale' THEN payment_status ELSE bill_type END AS payment_status
      FROM bills ORDER BY created_at DESC LIMIT ?''', [limit]);
    return ReportTable(['Invoice', 'Time', 'Cashier', 'Total', 'Paid', 'Status'],
        [for (final r in rows) r.values.toList()],
        moneyColumns: {3, 4});
  }

  /// Daily figures for one business date (used for the DailySummary sheet).
  Future<Map<String, Object?>> dailySummaryRow(String date) async {
    final b = (await db.rawQuery('''
      SELECT COUNT(*) AS bills, COALESCE(SUM(subtotal),0) AS gross, COALESCE(SUM(discount),0) AS discount,
             COALESCE(SUM(total),0) AS billed, COALESCE(SUM(balance_due),0) AS outstanding
      FROM bills WHERE bill_type = 'sale' AND business_date = ?''', [date])).first;
    final collected = await _int('SELECT COALESCE(SUM(amount),0) FROM payments WHERE business_date = ?', [date]);
    final payments = await _int('SELECT COUNT(*) FROM payments WHERE business_date = ?', [date]);
    final personal = await _int(
        "SELECT COALESCE(SUM(total),0) FROM bills WHERE bill_type = 'personal' AND business_date = ?", [date]);
    final expenses = await _int(
        "SELECT COALESCE(SUM(total),0) FROM bills WHERE bill_type = 'expense' AND business_date = ?", [date]);
    return {
      'personal': personal,
      'expenses': expenses,
      'date': date,
      'bills': b['bills'],
      'gross': b['gross'],
      'discount': b['discount'],
      'billed': b['billed'],
      'collected': collected,
      'payments': payments,
      'outstanding': b['outstanding'],
    };
  }
}
