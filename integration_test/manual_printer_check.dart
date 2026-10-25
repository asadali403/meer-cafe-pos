// Manual hardware check (prints real paper). Not part of the normal test run.
//   flutter test integration_test/manual_printer_check.dart -d windows
// Uses a temporary database, saves one sample bill with food + a drink, and sends
// the kitchen ticket + customer receipt to "Meer Receipt Printer" exactly like
// Complete Bill does. Result is written to %TEMP%\meer_printer_check.txt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meer_cafe_pos/app/app_controller.dart';
import 'package:meer_cafe_pos/database/app_database.dart';
import 'package:meer_cafe_pos/repositories/bill_repository.dart';
import 'package:meer_cafe_pos/utils/ids.dart';

const printerName = 'Meer Receipt Printer';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final log = File('${Directory.systemTemp.path}\\meer_printer_check.txt');

  testWidgets('print sample bill on the real printer', (t) async {
    log.writeAsStringSync('START ${DateTime.now()}\n');
    try {
      AppDatabase.dataDirOverride = (await Directory.systemTemp.createTemp('meer_print')).path;
      final app = AppController();
      await app.init();
      final admin = await app.users.createInitialAdmin('admin', 'Print Check', 'Check1234');
      await app.products.loadSampleMenu(admin);
      app.signIn(admin);
      await app.saveSettings({
        'printer_name': printerName,
        'paper': 'mm80',
        'printer_mode': 'thermal',
        'auto_print': '1',
        'kitchen_ticket': '1',
      });
      final printers = await app.printer.printers();
      log.writeAsStringSync('printers: ${printers.map((p) => '${p.name}(available=${p.isAvailable})').join(', ')}\n',
          mode: FileMode.append);
      final menu = await app.products.list(activeOnly: true);
      int id(String n) => menu.firstWhere((p) => p.name == n).id!;
      final bill = await app.bills.completeBill(admin,
          billId: Ids.newId(),
          lines: [CartLineInput(id('Zinger Burger'), 1), CartLineInput(id('Masala Fries'), 2), CartLineInput(id('Fresh Lime'), 1)],
          settings: app.settings,
          amountReceived: 200000,
          customerNote: 'Table 4 - PRINTER TEST');
      log.writeAsStringSync('bill ${bill.invoiceNo} total ${bill.total} kitchenItems ${bill.kitchenItems.length}\n',
          mode: FileMode.append);
      final out = await app.printer.printAfterSave(bill, app.settings);
      log.writeAsStringSync('RESULT ok=${out?.ok} message=${out?.message}\n', mode: FileMode.append);
      await app.shutdown();
    } catch (e, st) {
      log.writeAsStringSync('FAILED: $e\n$st\n', mode: FileMode.append);
    }
  });
}
