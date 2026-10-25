import 'dart:io';
import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../models/app_settings.dart';
import '../models/bill.dart';
import '../repositories/bill_repository.dart';
import 'escpos.dart';
import 'raw_printer.dart';
import 'receipt_builder.dart';

class PrintOutcome {
  final bool ok;
  final String message;
  const PrintOutcome(this.ok, this.message);
}

/// Prints customer receipts and kitchen tickets. Printing never touches bill data
/// except the print counter, so a failed print can always be retried without
/// creating a new bill.
class PrintService {
  final BillRepository bills;
  PrintService(this.bills);

  Future<List<Printer>> printers() async {
    try {
      return await Printing.listPrinters();
    } catch (_) {
      return const [];
    }
  }

  /// Sends [bytes] to [printerName], or shows the Windows print dialog when empty.
  /// Returns null on success, otherwise an error message.
  Future<String?> _send(Uint8List bytes, String printerName, String jobName, AppSettings settings) async {
    final format = ReceiptBuilder.formatFor(settings.paper);
    bool ok;
    if (printerName.isNotEmpty) {
      final matches = (await printers()).where((p) => p.name == printerName);
      if (matches.isEmpty) {
        return 'Printer "$printerName" was not found. Check that it is connected and switched on.';
      }
      final printer = matches.first;
      if (!printer.isAvailable) return 'Printer "${printer.name}" is not available. Check the cable/power.';
      if (settings.directThermal && Platform.isWindows) {
        // Thermal receipt printer: send ESC/POS directly, cutting after every slip.
        try {
          await RawPrinter.send(printerName, await EscPos.fromPdf(bytes, settings.paper), jobName: jobName);
          return null;
        } on RawPrinterException catch (e) {
          return e.message;
        }
      }
      ok = await Printing.directPrintPdf(printer: printer, name: jobName, format: format, onLayout: (_) async => bytes);
    } else {
      ok = await Printing.layoutPdf(name: jobName, format: format, onLayout: (_) async => bytes);
    }
    return ok ? null : 'Printing was cancelled or failed.';
  }

  Future<PrintOutcome> printBill(Bill bill, AppSettings settings, {bool reprint = false}) async {
    try {
      final bytes = await ReceiptBuilder.build(bill, settings, reprint: reprint);
      final err = await _send(bytes, settings.printerName, bill.invoiceNo, settings);
      if (err != null) return PrintOutcome(false, '$err The bill is saved — you can reprint it.');
      await bills.markPrinted(bill.id);
      return PrintOutcome(true, reprint ? 'Receipt reprinted.' : 'Receipt sent to printer.');
    } catch (e) {
      return PrintOutcome(false, 'Printing failed: $e. The bill is saved — you can reprint it from Bills.');
    }
  }

  /// Chef's copy: kitchen items only, no prices. Uses the kitchen printer if set.
  Future<PrintOutcome> printKitchenTicket(Bill bill, AppSettings settings, {bool reprint = false}) async {
    try {
      final bytes = await ReceiptBuilder.buildKitchenTicket(bill, settings, reprint: reprint);
      if (bytes == null) return const PrintOutcome(true, 'No kitchen items on this bill.');
      final printer = settings.kitchenPrinterName.isNotEmpty ? settings.kitchenPrinterName : settings.printerName;
      final err = await _send(bytes, printer, 'Kitchen ${bill.invoiceNo}', settings);
      if (err != null) return PrintOutcome(false, 'Kitchen ticket: $err You can reprint it from Bills.');
      return const PrintOutcome(true, 'Kitchen ticket sent.');
    } catch (e) {
      return PrintOutcome(false, 'Kitchen ticket failed: $e. You can reprint it from Bills.');
    }
  }

  /// Kitchen ticket + customer receipt as ONE print job (one print dialog / one click).
  /// Falls back to the receipt alone when the bill has no kitchen items.
  Future<PrintOutcome> printBoth(Bill bill, AppSettings settings, {bool reprint = false}) async {
    try {
      final bytes = await ReceiptBuilder.buildBoth(bill, settings, reprint: reprint);
      final err = await _send(bytes, settings.printerName, bill.invoiceNo, settings);
      if (err != null) return PrintOutcome(false, '$err The bill is saved — you can reprint it.');
      await bills.markPrinted(bill.id);
      return PrintOutcome(
          true,
          bill.kitchenItems.isEmpty
              ? 'Receipt sent to printer (no kitchen items).'
              : 'Kitchen ticket + customer receipt sent to printer.');
    } catch (e) {
      return PrintOutcome(false, 'Printing failed: $e. The bill is saved — you can reprint it from Bills.');
    }
  }

  /// After a bill is saved: kitchen ticket for the chef (if enabled and there are
  /// kitchen items) and the customer receipt (if auto-print is on). When both go to the
  /// same printer they are sent as one job, so only one print click is ever needed.
  Future<PrintOutcome?> printAfterSave(Bill bill, AppSettings settings) async {
    final kitchenWanted = settings.kitchenTicket && bill.kitchenItems.isNotEmpty;
    final samePrinter =
        settings.kitchenPrinterName.isEmpty || settings.kitchenPrinterName == settings.printerName;
    if (kitchenWanted && settings.autoPrint && samePrinter) return printBoth(bill, settings);

    final messages = <String>[];
    var ok = true;
    if (kitchenWanted) {
      final k = await printKitchenTicket(bill, settings);
      ok &= k.ok;
      messages.add(k.message);
    }
    if (settings.autoPrint) {
      final r = await printBill(bill, settings);
      ok &= r.ok;
      messages.add(r.message);
    }
    return messages.isEmpty ? null : PrintOutcome(ok, messages.join(' '));
  }
}
