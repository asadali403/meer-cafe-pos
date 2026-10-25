import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meer_cafe_pos/models/bill.dart';
import 'package:meer_cafe_pos/models/meers_menu.dart';
import 'package:meer_cafe_pos/models/product.dart';
import 'package:meer_cafe_pos/models/user.dart';
import 'package:meer_cafe_pos/repositories/bill_repository.dart';
import 'package:meer_cafe_pos/utils/errors.dart';
import 'package:meer_cafe_pos/utils/ids.dart';
import 'package:path/path.dart' as p;

import 'helpers.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() async => env.close());

  group('Authentication & roles', () {
    test('passwords are hashed and verified; wrong password rejected', () async {
      final row = (await env.db.query('users', where: 'username = ?', whereArgs: ['admin'])).first;
      expect(row['password_hash'], startsWith('pbkdf2_sha256\$'));
      expect(row['password_hash'], isNot(contains('secret123')));
      expect((await env.users.authenticate('admin', 'secret123')).isAdmin, isTrue);
      expect(() => env.users.authenticate('admin', 'wrong-pass1'), throwsA(isA<ValidationException>()));
    });

    test('new cashier must change temporary password', () async {
      final u = await env.users.create(env.admin,
          username: 'sara', displayName: 'Sara', tempPassword: 'temp5678', role: UserRole.cashier);
      expect(u.mustChangePassword, isTrue);
      final changed = await env.users.changePassword(u, 'temp5678', 'newpass99');
      expect(changed.mustChangePassword, isFalse);
    });

    test('initial admin can only be created once', () async {
      expect(() => env.users.createInitialAdmin('x', 'X', 'abcdefg1'), throwsA(isA<PermissionDeniedException>()));
    });

    test('account locks after repeated failures', () async {
      for (var i = 0; i < 5; i++) {
        await expectLater(env.users.authenticate('ali', 'bad-pass$i'), throwsA(isA<ValidationException>()));
      }
      await expectLater(env.users.authenticate('ali', 'cashier123'), throwsA(isA<ValidationException>()));
    });

    test('cashier cannot change product prices or manage products/users/settings', () async {
      final id = await env.addProduct('Latte', 480);
      final prod = (await env.products.byId(id))!;
      expect(() => env.products.save(env.cashier, prod.copyWith(pricePaisa: 100)),
          throwsA(isA<PermissionDeniedException>()));
      expect(() => env.products.delete(env.cashier, id), throwsA(isA<PermissionDeniedException>()));
      expect(() => env.products.setActive(env.cashier, id, false), throwsA(isA<PermissionDeniedException>()));
      expect(() => env.products.addCategory(env.cashier, 'Cakes'), throwsA(isA<PermissionDeniedException>()));
      expect(() => env.users.list(env.cashier), throwsA(isA<PermissionDeniedException>()));
      expect(() => env.settingsRepo.save(env.cashier, {'cafe_name': 'X'}), throwsA(isA<PermissionDeniedException>()));
      expect((await env.products.byId(id))!.pricePaisa, 48000);
    });
  });

  group('Products', () {
    test('validation rejects negative price and empty name', () async {
      final cat = await env.category('Tea & Coffee');
      expect(() => env.products.save(env.admin, Product(name: 'X', categoryId: cat, pricePaisa: -1)),
          throwsA(isA<ValidationException>()));
      expect(() => env.products.save(env.admin, Product(name: '  ', categoryId: cat, pricePaisa: 100)),
          throwsA(isA<ValidationException>()));
    });

    test('inactive and deleted products are hidden from cashiers', () async {
      final a = await env.addProduct('A', 100);
      final b = await env.addProduct('B', 100);
      await env.addProduct('C', 100);
      await env.products.setActive(env.admin, a, false);
      await env.products.delete(env.admin, b);
      final visible = await env.products.list(activeOnly: true);
      expect(visible.map((p) => p.name), ['C']);
    });

    test('products persist after closing and reopening the database file', () async {
      final dir = await Directory.systemTemp.createTemp('meer_test');
      final path = p.join(dir.path, 'persist.db');
      var e = await TestEnv.create(path: path);
      await e.addProduct('Persistent Chai', 150, category: 'Tea & Coffee');
      await e.close();
      e = await TestEnv.create(path: path, seedUsers: false);
      final list = await e.products.list();
      expect(list.single.name, 'Persistent Chai');
      expect(list.single.pricePaisa, 15000);
      await e.close();
      await dir.delete(recursive: true);
    });
  });

  group('Bills', () {
    late int latte, burger;
    setUp(() async {
      latte = await env.addProduct('Latte', 480);
      burger = await env.addProduct('Burger', 650, category: 'Burgers');
    });

    Future<Bill> sell({String? id, int received = 300000, int discount = 0, DateTime? at}) =>
        env.bills.completeBill(env.cashier,
            billId: id ?? Ids.newId(),
            lines: [CartLineInput(latte, 2), CartLineInput(burger, 1)],
            settings: env.settings,
            discount: discount,
            amountReceived: received,
            now: at);

    test('bill, items and payment saved together with price snapshots', () async {
      final b = await sell(received: 200000);
      expect(b.subtotal, 161000);
      expect(b.total, 161000);
      expect(b.items.length, 2);
      expect(b.items.first.unitPrice, 48000);
      expect(b.payments.single.amount, 161000);
      expect(b.payments.single.tendered, 200000);
      expect(b.payments.single.changeGiven, 39000);
      expect(b.balanceDue, 0);
      expect(b.paymentStatus, PaymentStatus.paid);
    });

    test('partial payment leaves a balance and is not counted as collected', () async {
      final b = await sell(received: 100000);
      expect(b.amountPaid, 100000);
      expect(b.balanceDue, 61000);
      expect(b.paymentStatus, PaymentStatus.partial);
      final after = await env.bills.addPayment(env.cashier, b.id, amountReceived: 70000);
      expect(after.amountPaid, 161000);
      expect(after.balanceDue, 0);
      expect(after.paymentStatus, PaymentStatus.paid);
      expect(after.payments.length, 2);
      expect(after.payments.last.amount, 61000);
      expect(after.payments.last.changeGiven, 9000);
    });

    test('unpaid bill records no payment row', () async {
      final b = await sell(received: 0);
      expect(b.paymentStatus, PaymentStatus.unpaid);
      expect(b.payments, isEmpty);
      expect(await env.count('payments'), 0);
    });

    test('old bills keep their unit price after a price change', () async {
      final b = await sell();
      final prod = (await env.products.byId(latte))!;
      await env.products.save(env.admin, prod.copyWith(pricePaisa: 99900));
      final again = (await env.bills.getBill(b.id))!;
      expect(again.items.firstWhere((i) => i.productId == latte).unitPrice, 48000);
      expect(again.total, b.total);
    });

    test('same bill id twice (double click) creates only one bill', () async {
      final id = Ids.newId();
      final results = await Future.wait([sell(id: id), sell(id: id)]);
      final again = await sell(id: id);
      expect(results[0].invoiceNo, results[1].invoiceNo);
      expect(again.invoiceNo, results[0].invoiceNo);
      expect(await env.count('bills'), 1);
      expect(await env.count('bill_items'), 2);
      expect(await env.count('payments'), 1);
    });

    test('failed transaction saves nothing (bill, items, payments, queue)', () async {
      env.bills.beforeCommitHook = (_) async => throw StateError('simulated crash');
      await expectLater(sell(), throwsA(isA<StateError>()));
      env.bills.beforeCommitHook = null;
      expect(await env.count('bills'), 0);
      expect(await env.count('bill_items'), 0);
      expect(await env.count('payments'), 0);
      final q = await env.db.query('sync_queue', where: "entity_type <> 'product'");
      expect(q, isEmpty);
    });

    test('cashier discount limit enforced; admin may discount more', () async {
      // 10% of 1610 = 161
      await expectLater(sell(discount: 20000), throwsA(isA<PermissionDeniedException>()));
      final ok = await sell(discount: 16100);
      expect(ok.total, 161000 - 16100);
      final adminBill = await env.bills.completeBill(env.admin,
          billId: Ids.newId(),
          lines: [CartLineInput(latte, 1)],
          settings: env.settings,
          discount: 20000,
          amountReceived: 28000);
      expect(adminBill.total, 28000);
    });

    test('inactive product cannot be billed', () async {
      await env.products.setActive(env.admin, burger, false);
      await expectLater(sell(), throwsA(isA<ValidationException>()));
    });

    test('cashier sees only own bills', () async {
      await sell();
      await env.bills.completeBill(env.admin,
          billId: Ids.newId(), lines: [CartLineInput(latte, 1)], settings: env.settings, amountReceived: 48000);
      expect((await env.bills.list(env.cashier, const BillFilter())).length, 1);
      expect((await env.bills.list(env.admin, const BillFilter())).length, 2);
    });
  });

  group('Invoice numbers', () {
    late int tea;
    setUp(() async => tea = await env.addProduct('Chai', 120, category: 'Tea & Coffee'));

    Future<Bill> sellAt(DateTime t) => env.bills.completeBill(env.cashier,
        billId: Ids.newId(), lines: [CartLineInput(tea, 1)], settings: env.settings, amountReceived: 12000, now: t);

    test('sequential per day in MC-YYYYMMDD-NNNN format, restarting each day', () async {
      final d1 = DateTime(2026, 10, 9, 10);
      expect((await sellAt(d1)).invoiceNo, 'MC-20261009-0001');
      expect((await sellAt(d1.add(const Duration(minutes: 5)))).invoiceNo, 'MC-20261009-0002');
      expect((await sellAt(DateTime(2026, 10, 10, 9))).invoiceNo, 'MC-20261010-0001');
      expect((await sellAt(d1.add(const Duration(hours: 3)))).invoiceNo, 'MC-20261009-0003');
    });

    test('numbering continues after app restart (no collisions)', () async {
      final dir = await Directory.systemTemp.createTemp('meer_inv');
      final path = p.join(dir.path, 'inv.db');
      var e = await TestEnv.create(path: path);
      final pid = await e.addProduct('Chai', 120, category: 'Tea & Coffee');
      final t = DateTime(2026, 10, 9, 12);
      Future<Bill> s(TestEnv x, AppUser user) => x.bills.completeBill(user,
          billId: Ids.newId(), lines: [CartLineInput(pid, 1)], settings: x.settings, amountReceived: 12000, now: t);
      await s(e, e.cashier);
      await s(e, e.cashier);
      final cashier = e.cashier;
      await e.close();
      e = await TestEnv.create(path: path, seedUsers: false);
      final b3 = await s(e, cashier);
      expect(b3.invoiceNo, 'MC-20261009-0003');
      final all = await e.db.query('bills');
      expect(all.map((r) => r['invoice_no']).toSet().length, 3);
      await e.close();
      await dir.delete(recursive: true);
    });

    test('bills and payments survive reopening', () async {
      final dir = await Directory.systemTemp.createTemp('meer_bill');
      final path = p.join(dir.path, 'b.db');
      var e = await TestEnv.create(path: path);
      final pid = await e.addProduct('Chai', 120, category: 'Tea & Coffee');
      final b = await e.bills.completeBill(e.cashier,
          billId: Ids.newId(), lines: [CartLineInput(pid, 3)], settings: e.settings, amountReceived: 20000);
      await e.close();
      e = await TestEnv.create(path: path, seedUsers: false);
      final again = (await e.bills.getBill(b.id))!;
      expect(again.total, 36000);
      expect(again.items.single.quantity, 3);
      expect(again.payments.single.amount, 20000);
      expect(again.balanceDue, 16000);
      await e.close();
      await dir.delete(recursive: true);
    });
  });

  test('reprint only increments print counter', () async {
    final pid = await env.addProduct('Chai', 120, category: 'Tea & Coffee');
    final b = await env.bills.completeBill(env.cashier,
        billId: Ids.newId(), lines: [CartLineInput(pid, 1)], settings: env.settings, amountReceived: 12000);
    await env.bills.markPrinted(b.id);
    await env.bills.markPrinted(b.id);
    expect(await env.count('bills'), 1);
    expect((await env.bills.getBill(b.id))!.printCount, 2);
  });

  test("Meer's Cafe menu loads exactly, without duplicates on a second load", () async {
    final n = await env.products.loadMenu(env.admin);
    expect(n, meersMenu.length);
    expect(n, 64);
    expect(await env.products.loadMenu(env.admin), 0);
    final all = await env.products.list(activeOnly: true);
    expect(all.length, meersMenu.length);
    for (final m in meersMenu) {
      final p = all.singleWhere((x) => x.name == m.name, orElse: () => throw 'missing ${m.name}');
      expect(p.pricePaisa, m.rupees * 100, reason: m.name);
      expect(p.categoryName, m.category, reason: m.name);
    }
    int price(String name) => all.firstWhere((p) => p.name == name).pricePaisa ~/ 100;
    expect(price('Deal 1'), 649);
    expect(price('Deal 6'), 2100);
    expect(price('Full Broast'), 2300);
    expect(price('Cheese Lover (Large)'), 1399);
    expect(price('Crave Crown Pizza (Large)'), 1699);
    expect(price('Pizza Fries'), 750);
    expect(price('Tea'), 70);
    expect(() => env.products.loadMenu(env.cashier), throwsA(isA<PermissionDeniedException>()));
  });
}
