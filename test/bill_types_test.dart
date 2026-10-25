import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meer_cafe_pos/database/app_database.dart';
import 'package:meer_cafe_pos/database/migrations.dart';
import 'package:meer_cafe_pos/models/app_settings.dart';
import 'package:meer_cafe_pos/models/bill.dart';
import 'package:meer_cafe_pos/models/user.dart';
import 'package:meer_cafe_pos/repositories/bill_repository.dart';
import 'package:meer_cafe_pos/repositories/report_repository.dart';
import 'package:meer_cafe_pos/services/receipt_builder.dart';
import 'package:meer_cafe_pos/utils/dates.dart';
import 'package:meer_cafe_pos/utils/errors.dart';
import 'package:meer_cafe_pos/utils/ids.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  late TestEnv env;
  late int burger, drink;
  final day = DateTime(2026, 10, 12, 13);
  final today = Dates.day(day);

  setUp(() async {
    env = await TestEnv.create();
    burger = await env.addProduct('Zinger', 550, category: 'Burger');
    drink = await env.addProduct('Cola', 150, category: 'Drinks');
  });
  tearDown(() async => env.close());

  Future<Bill> bill({
    BillType type = BillType.sale,
    List<CartLineInput>? lines,
    List<CustomLineInput> custom = const [],
    int received = 0,
    AppUser? actor,
    AppSettings? settings,
  }) =>
      env.bills.completeBill(actor ?? env.admin,
          billId: Ids.newId(),
          lines: lines ?? [CartLineInput(burger, 1)],
          customLines: custom,
          type: type,
          settings: settings ?? env.settings,
          amountReceived: received,
          now: day);

  test('pay later: unpaid bill can be marked as paid afterwards', () async {
    final b = await bill(received: 0);
    expect(b.paymentStatus, PaymentStatus.unpaid);
    expect(b.balanceDue, 55000);
    final paid = await env.bills.markPaid(env.admin, b.id, method: 'JazzCash');
    expect(paid.paymentStatus, PaymentStatus.paid);
    expect(paid.balanceDue, 0);
    expect(paid.payments.single.amount, 55000);
    expect(paid.payments.single.method, 'JazzCash');
    expect(() => env.bills.markPaid(env.admin, b.id), throwsA(isA<ValidationException>()));
  });

  test('personal food: own voucher number, no payment, kept out of sales', () async {
    await bill(received: 55000); // a real sale
    final pf = await bill(type: BillType.personal, received: 99999);
    expect(pf.invoiceNo, startsWith('PF-'));
    expect(pf.billType, BillType.personal);
    expect(pf.payments, isEmpty);
    expect(pf.balanceDue, 0);
    expect(pf.total, 55000);
    final s = await ReportRepository(env.db).summary(env.admin, today, today);
    expect(s.bills, 1);
    expect(s.billed, 55000);
    expect(s.collected, 55000);
    expect(s.personalTotal, 55000);
    expect(s.personalBills, 1);
    final outstanding = await ReportRepository(env.db).totalOutstanding(env.admin);
    expect(outstanding, 0);
  });

  test('expense: admin only, custom lines, EX voucher, excluded from sales', () async {
    final exp = await bill(
        type: BillType.expense, lines: [], custom: [const CustomLineInput('Gas cylinder', 300000, 1, kitchen: true)]);
    expect(exp.invoiceNo, startsWith('EX-'));
    expect(exp.total, 300000);
    expect(exp.items.single.isCustom, isTrue);
    expect(exp.items.single.productId, isNull);
    expect(exp.kitchenItems, isEmpty, reason: 'expenses never go to the kitchen');
    await expectLater(
        bill(type: BillType.expense, actor: env.cashier, lines: [], custom: [const CustomLineInput('Milk', 100, 1)]),
        throwsA(isA<PermissionDeniedException>()));
    final s = await ReportRepository(env.db).summary(env.admin, today, today);
    expect(s.billed, 0);
    expect(s.expenseTotal, 300000);
    final t = await ReportRepository(env.db).nonSaleBills(env.admin, today, today, 'expense');
    expect(t.rows.single[4], '1 x Gas cylinder');
  });

  test('custom items: admin yes, cashier only when allowed in settings', () async {
    final b = await bill(custom: [const CustomLineInput('Special Karahi', 180000, 2, kitchen: true)], received: 500000);
    expect(b.total, 55000 + 360000);
    expect(b.items.length, 2);
    await expectLater(
        bill(actor: env.cashier, custom: [const CustomLineInput('X', 100, 1)]),
        throwsA(isA<PermissionDeniedException>()));
    await env.settingsRepo.save(env.admin, {'cashier_custom_items': '1'});
    final allowed = await env.settingsRepo.load();
    final c = await bill(actor: env.cashier, settings: allowed, custom: [const CustomLineInput('Extra sauce', 5000, 1)]);
    expect(c.items.length, 2);
    await expectLater(bill(custom: [const CustomLineInput('', 100, 1)]), throwsA(isA<ValidationException>()));
    await expectLater(bill(custom: [const CustomLineInput('Neg', -1, 1)]), throwsA(isA<ValidationException>()));
  });

  test('kitchen ticket lists only kitchen items (drinks off by default), no prices', () async {
    final b = await bill(
        lines: [CartLineInput(burger, 2), CartLineInput(drink, 3)],
        custom: [const CustomLineInput('Service charge', 10000, 1)],
        received: 200000);
    expect(b.kitchenItems.map((i) => i.productName), ['Zinger']);
    final pdf = await ReceiptBuilder.buildKitchenTicket(b, env.settings);
    expect(pdf, isNotNull);
    final drinksOnly = await bill(lines: [CartLineInput(drink, 1)], received: 15000);
    expect(await ReceiptBuilder.buildKitchenTicket(drinksOnly, env.settings), isNull);
    final cats = await env.products.categories();
    await env.products.setCategoryKitchen(env.admin, cats.firstWhere((c) => c.name == 'Drinks').id, true);
    final now = await bill(lines: [CartLineInput(drink, 1)], received: 15000);
    expect(now.kitchenItems.length, 1);
  });

  test('one print job holds both slips: kitchen ticket + customer receipt', () async {
    int pages(List<int> pdf) => RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(pdf)).length;
    final food = await bill(lines: [CartLineInput(burger, 2), CartLineInput(drink, 1)], received: 200000);
    for (final paper in PaperSize.values) {
      expect(pages(await ReceiptBuilder.buildBoth(food, env.settings, paper: paper)), 2);
    }
    final drinksOnly = await bill(lines: [CartLineInput(drink, 1)], received: 15000);
    expect(pages(await ReceiptBuilder.buildBoth(drinksOnly, env.settings)), 1, reason: 'receipt only');
    expect(pages(await ReceiptBuilder.build(food, env.settings)), 1);
  });

  test('receipts render for every bill type', () async {
    for (final t in BillType.values) {
      final b = await bill(type: t, custom: [const CustomLineInput('Custom', 1000, 1)]);
      for (final paper in PaperSize.values) {
        expect((await ReceiptBuilder.build(b, env.settings, paper: paper)).length, greaterThan(500));
      }
    }
  });

  test('existing version-1 database upgrades to version 2 without losing bills', () async {
    final dir = await Directory.systemTemp.createTemp('meer_mig');
    final path = p.join(dir.path, 'old.db');
    sqfliteFfiInit();
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              for (final sql in migrations[0]) {
                await db.execute(sql);
              }
            }));
    final now = Dates.dbNow();
    await old.insert('users', {
      'username': 'admin', 'display_name': 'A', 'password_hash': 'x', 'role': 'admin',
      'created_at': now, 'updated_at': now,
    });
    await old.insert('categories', {'name': 'Drinks', 'created_at': now, 'updated_at': now});
    await old.insert('bills', {
      'id': 'old-bill', 'invoice_no': 'MC-20261001-0001', 'invoice_seq': 1, 'business_date': '2026-10-01',
      'created_at': now, 'updated_at': now, 'cashier_id': 1, 'cashier_name': 'A',
      'subtotal': 1000, 'total': 1000, 'amount_paid': 1000, 'payment_status': 'paid',
    });
    await old.close();

    final upgraded = await AppDatabase.open(path);
    expect((await upgraded.db.rawQuery('PRAGMA user_version')).first.values.first, schemaVersion);
    final b = (await upgraded.db.query('bills')).single;
    expect(b['bill_type'], 'sale');
    final cat = (await upgraded.db.query('categories')).single;
    expect(cat['kitchen'], 0);
    final full = await BillRepository(upgraded.db).getBill('old-bill');
    expect(full!.isSale, isTrue);
    await upgraded.close();
    await dir.delete(recursive: true);
  });
}
