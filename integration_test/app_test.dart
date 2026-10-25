// End-to-end acceptance test that drives the real Windows app UI.
// Run:  flutter test integration_test -d windows
// Uses a temporary data folder, so real cafe data is never touched.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meer_cafe_pos/app/app.dart';
import 'package:meer_cafe_pos/app/app_controller.dart';
import 'package:meer_cafe_pos/database/app_database.dart';
import 'package:meer_cafe_pos/models/app_settings.dart';
import 'package:meer_cafe_pos/repositories/bill_repository.dart';
import 'package:meer_cafe_pos/services/receipt_builder.dart';
import 'package:meer_cafe_pos/utils/dates.dart';
import 'package:meer_cafe_pos/utils/errors.dart';
import 'package:provider/provider.dart';

Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $f');
}

Future<void> enter(WidgetTester t, String label, String text) async {
  final f = find.widgetWithText(TextField, label);
  expect(f, findsOneWidget, reason: 'field "$label"');
  await t.enterText(f, text);
  await t.pump();
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.tap(f.first);
  await t.pump(const Duration(milliseconds: 300));
}

/// Types [name] into the billing search box and taps its product card.
Future<void> addFromSearch(WidgetTester t, String name, {int times = 1}) async {
  final search = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search products or category (F2)');
  await t.enterText(search, name);
  await pumpUntil(t, find.text(name));
  for (var i = 0; i < times; i++) {
    await tap(t, find.text(name));
  }
  await t.enterText(search, '');
  await t.pump(const Duration(milliseconds: 300));
}

/// Progress log (the Flutter tool cannot always read a Windows app's console output).
final _log = File('${Directory.systemTemp.path}\\meer_it_log.txt');
void step(String s) => _log.writeAsStringSync('${DateTime.now().toIso8601String()} $s\n', mode: FileMode.append);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Meer Cafe POS acceptance flow', (t) async {
    _log.writeAsStringSync('START\n');
    try {
      await _flow(t);
      step('ALL PASSED');
    } catch (e, st) {
      step('FAILED: $e\n$st');
      rethrow;
    }
  });
}

Future<void> _flow(WidgetTester t) async {
  {
    final dir = await Directory.systemTemp.createTemp('meer_it');
    AppDatabase.dataDirOverride = dir.path;

    var app = AppController();
    await app.init();
    await t.pumpWidget(ChangeNotifierProvider.value(value: app, child: const MeerCafeApp()));
    await pumpUntil(t, find.text('First-time setup'));

    step('First run');
    // --- First run: create admin, load sample menu ---
    await enter(t, 'Password', 'Admin1234');
    await enter(t, 'Confirm password', 'Admin1234');
    await tap(t, find.text('Create admin & continue'));
    await pumpUntil(t, find.text("Today's billed sales"));
    await app.saveSettings({'auto_print': '0'}); // no printer dialog during the automated test

    step('Admin adds a product');
    // --- Admin adds a product (acceptance 1) ---
    await tap(t, find.text('Products'));
    await pumpUntil(t, find.text('Add product'));
    await tap(t, find.text('Add product'));
    await pumpUntil(t, find.text('Product name *'));
    await enter(t, 'Product name *', 'Test Chai');
    await enter(t, 'Selling price (Rs.) *', '99');
    await tap(t, find.text('Save'));
    await pumpUntil(t, find.text('Test Chai'));

    step('Invalid price');
    // Invalid price is rejected
    await tap(t, find.text('Add product'));
    await pumpUntil(t, find.text('Product name *'));
    await enter(t, 'Product name *', 'Bad');
    await enter(t, 'Selling price (Rs.) *', '-5');
    await tap(t, find.text('Save'));
    await pumpUntil(t, find.textContaining('Enter a valid price'));
    await tap(t, find.text('Cancel'));

    step('Admin adds a cashier');
    // --- Admin adds a cashier ---
    await tap(t, find.text('Users'));
    await pumpUntil(t, find.text('Add user'));
    await tap(t, find.text('Add user'));
    await pumpUntil(t, find.text('Temporary password'));
    await enter(t, 'Username', 'cashier1');
    await enter(t, 'Display name (printed on receipts)', 'Cashier One');
    await enter(t, 'Temporary password', 'Temp1234');
    await tap(t, find.text('Save'));
    await pumpUntil(t, find.text('Cashier One  (cashier1)'));

    step('Cashier login');
    // --- Cashier login with forced password change ---
    app.signOut();
    await pumpUntil(t, find.text('Sign in'));
    await enter(t, 'Username', 'cashier1');
    await enter(t, 'Password', 'Temp1234');
    await tap(t, find.text('Sign in'));
    await pumpUntil(t, find.text('Save new password'));
    await enter(t, 'Temporary password', 'Temp1234');
    await enter(t, 'New password', 'Cash1234');
    await enter(t, 'Confirm new password', 'Cash1234');
    await tap(t, find.text('Save new password'));
    await pumpUntil(t, find.text('Current Bill'));

    step('Cashier permissions');
    // --- Cashier permissions (acceptance 10) ---
    expect(find.text('Products'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Dashboard'), findsNothing);
    final chai = (await app.products.list(search: 'Test Chai')).single;
    await expectLater(app.products.save(app.user!, chai.copyWith(pricePaisa: 1)), throwsA(isA<PermissionDeniedException>()));
    expect((await app.products.byId(chai.id!))!.pricePaisa, 9900);

    step('Bill with change');
    // --- Bill with change returned (acceptance 2 & 4), offline ---
    await addFromSearch(t, 'Test Chai', times: 2);
    await addFromSearch(t, 'Hot Wings');
    expect(find.text('Rs. 648.00'), findsWidgets); // 2 x 99 + 450
    await enter(t, 'Amount received (Rs.)', '1000');
    expect(find.text('Rs. 352.00'), findsOneWidget);
    await tap(t, find.text('Complete Bill (F9)'));
    await pumpUntil(t, find.text('Bill saved'));
    expect(find.text('Rs. 352.00'), findsWidgets);
    expect(find.text('PAID'), findsOneWidget);
    await tap(t, find.text('New Bill'));
    await t.pump(const Duration(milliseconds: 500));

    step('Bill with balance');
    // --- Bill with balance due (acceptance 5) ---
    await addFromSearch(t, 'Hot Wings');
    await enter(t, 'Amount received (Rs.)', '200');
    expect(find.text('Balance due'), findsOneWidget);
    expect(find.text('Rs. 250.00'), findsWidgets);
    await tap(t, find.text('Complete Bill (F9)'));
    await pumpUntil(t, find.text('Save bill'));
    await tap(t, find.text('Save bill'));
    await pumpUntil(t, find.text('Bill saved'));
    expect(find.text('PARTIALLY PAID'), findsOneWidget);
    await tap(t, find.text('New Bill'));
    await t.pump(const Duration(milliseconds: 500));

    step('Bills screen');
    // Bills screen shows both bills
    await tap(t, find.text('Bills'));
    final today = Dates.compact(DateTime.now());
    await pumpUntil(t, find.text('MC-$today-0001'));
    expect(find.text('MC-$today-0002'), findsOneWidget);

    step('Receipt document');
    // --- Receipt document renders for every paper size; reprint does not duplicate (acceptance 6) ---
    final bills = await app.bills.list(app.user!, const BillFilter());
    expect(bills.length, 2);
    for (final paper in PaperSize.values) {
      final full = (await app.bills.getBill(bills.first.id))!;
      final pdf = await ReceiptBuilder.build(full, app.settings, paper: paper);
      expect(pdf.length, greaterThan(1000));
    }
    await app.bills.markPrinted(bills.first.id);
    await app.bills.markPrinted(bills.first.id);
    expect((await app.bills.list(app.user!, const BillFilter())).length, 2);

    step('Google Sheets');
    // --- Google Sheets unreachable: billing still works (acceptance 8) ---
    final admin = await app.users.authenticate('admin', 'Admin1234');
    await app.settingsRepo.save(admin, {
      'sync_enabled': '1',
      'sync_url': 'https://127.0.0.1:9/exec',
      'sync_secret': 'integration-test-secret-1234',
    });
    final msg = await app.sync!.run(trigger: 'manual', force: true);
    expect(msg, startsWith('Sync failed'));
    final c = await app.sync!.refreshCounts();
    expect(c.synced, 0);
    expect(c.failed, greaterThan(0));
    final third = await app.bills.completeBill(app.user!,
        billId: 'it-offline-bill',
        lines: [CartLineInput(chai.id!, 1)],
        settings: app.settings,
        amountReceived: 9900);
    expect(third.invoiceNo, 'MC-$today-0003');

    step('Restart');
    // --- Restart: everything persists (acceptance 1 & 3) ---
    app.signOut();
    await t.pump();
    await app.shutdown();
    app = AppController();
    await app.init();
    await t.pumpWidget(ChangeNotifierProvider.value(value: app, child: const MeerCafeApp()));
    await pumpUntil(t, find.text('Sign in'));
    expect((await app.products.list(search: 'Test Chai')).single.pricePaisa, 9900);
    final adminAgain = await app.users.authenticate('admin', 'Admin1234');
    final all = await app.bills.list(adminAgain, const BillFilter());
    expect(all.length, 3);
    final partial = all.firstWhere((b) => b.invoiceNo.endsWith('0002'));
    final full = (await app.bills.getBill(partial.id))!;
    expect(full.balanceDue, 25000);
    expect(full.payments.single.amount, 20000);
    await app.shutdown();
  }
}
