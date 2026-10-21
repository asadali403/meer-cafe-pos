import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/app_settings.dart';
import '../models/bill.dart';
import '../utils/dates.dart';
import '../utils/money.dart';

/// Builds a real receipt document (not a screenshot) for thermal or standard printers.
class ReceiptBuilder {
  ReceiptBuilder._();

  static const _mm = PdfPageFormat.mm;

  static PdfPageFormat formatFor(PaperSize s) => switch (s) {
        PaperSize.mm58 => const PdfPageFormat(58 * _mm, double.infinity, marginAll: 2 * _mm),
        PaperSize.mm80 => const PdfPageFormat(80 * _mm, double.infinity, marginAll: 4 * _mm),
        PaperSize.a4 => PdfPageFormat.a4.copyWith(
            marginTop: 15 * _mm, marginBottom: 15 * _mm, marginLeft: 20 * _mm, marginRight: 20 * _mm),
      };

  static pw.Font? _regular, _bold, _italic;
  static Uint8List? _bundledLogo;

  static Future<void> _loadFonts() async {
    if (_regular != null) return;
    try {
      final dir = Platform.environment['WINDIR'] ?? r'C:\Windows';
      Future<pw.Font?> load(String f) async {
        final file = File('$dir\\Fonts\\$f');
        if (!await file.exists()) return null;
        return pw.Font.ttf((await file.readAsBytes()).buffer.asByteData());
      }

      _regular = await load('arial.ttf');
      _bold = await load('arialbd.ttf');
      _italic = await load('ariali.ttf');
    } catch (_) {
      // Fall back to the built-in PDF fonts.
    }
  }

  static Future<Uint8List?> _logo(AppSettings s) async {
    if (s.logoPath.isNotEmpty) {
      try {
        final f = File(s.logoPath);
        if (await f.exists()) return await f.readAsBytes();
      } catch (_) {}
    }
    try {
      _bundledLogo ??= (await rootBundle.load('assets/images/logo.png')).buffer.asUint8List();
    } catch (_) {}
    return _bundledLogo;
  }

  static Future<Uint8List> build(Bill bill, AppSettings s, {bool reprint = false, PaperSize? paper}) async {
    await _loadFonts();
    final size = paper ?? s.paper;
    final format = formatFor(size);
    final logoBytes = await _logo(s);
    final base = switch (size) { PaperSize.mm58 => 7.2, PaperSize.mm80 => 8.6, PaperSize.a4 => 10.0 };
    final doc = pw.Document(
      title: 'Receipt ${bill.invoiceNo}',
      author: s.cafeName,
      theme: (_regular != null)
          ? pw.ThemeData.withFont(base: _regular, bold: _bold ?? _regular, italic: _italic ?? _regular)
          : null,
    );

    pw.TextStyle st({double scale = 1, bool bold = false, bool italic = false}) => pw.TextStyle(
          fontSize: base * scale,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
        );

    pw.Widget divider() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Divider(height: 1, thickness: 0.6, borderStyle: pw.BorderStyle.dashed),
        );

    pw.Widget kv(String k, String v, {bool bold = false, double scale = 1}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(k, style: st(bold: bold, scale: scale))),
            pw.Text(v, style: st(bold: bold, scale: scale)),
          ]),
        );

    final settled = bill.balanceDue == 0;
    final statusLabel = switch (bill.billType) {
      BillType.sale => bill.paymentStatus.label,
      BillType.personal => 'PERSONAL - NOT A SALE',
      BillType.expense => 'EXPENSE',
    };

    final content = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (logoBytes != null)
          pw.Center(
            child: pw.Image(pw.MemoryImage(logoBytes),
                width: size == PaperSize.mm58 ? 18 * _mm : 24 * _mm, height: size == PaperSize.mm58 ? 18 * _mm : 24 * _mm),
          ),
        pw.SizedBox(height: 2),
        pw.Text(s.cafeName.toUpperCase(), textAlign: pw.TextAlign.center, style: st(scale: 1.6, bold: true)),
        if (s.showTagline && s.tagline.isNotEmpty)
          pw.Text(s.tagline, textAlign: pw.TextAlign.center, style: st(italic: true)),
        if (s.address.isNotEmpty) pw.Text(s.address, textAlign: pw.TextAlign.center, style: st(scale: 0.95)),
        if (s.phone.isNotEmpty) pw.Text('Phone: ${s.phone}', textAlign: pw.TextAlign.center, style: st(scale: 0.95)),
        divider(),
        if (!bill.isSale)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text(
                bill.billType == BillType.personal ? 'PERSONAL / STAFF FOOD' : 'EXPENSE VOUCHER',
                textAlign: pw.TextAlign.center,
                style: st(bold: true, scale: 1.2)),
          ),
        if (reprint)
          pw.Text('*** DUPLICATE COPY ***', textAlign: pw.TextAlign.center, style: st(bold: true)),
        kv(bill.isSale ? 'Invoice' : 'Voucher', bill.invoiceNo, bold: true),
        kv('Date', Dates.display(bill.createdAt)),
        kv(bill.isSale ? 'Cashier' : 'Entered by', bill.cashierName),
        if (bill.customerNote.isNotEmpty) kv(bill.isSale ? 'Customer' : 'Note', bill.customerNote),
        divider(),
        pw.Row(children: [
          pw.Expanded(child: pw.Text('ITEM', style: st(bold: true))),
          pw.Text('AMOUNT', style: st(bold: true)),
        ]),
        pw.SizedBox(height: 2),
        for (final it in bill.items)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.Text(it.productName, style: st(bold: true)),
              pw.Row(children: [
                pw.Expanded(
                    child: pw.Text('${it.quantity} x ${Money.format(it.unitPrice, symbol: false)}', style: st())),
                pw.Text(Money.format(it.lineTotal, symbol: false), style: st()),
              ]),
            ]),
          ),
        divider(),
        kv('Subtotal', Money.format(bill.subtotal)),
        if (bill.discount > 0) kv('Discount', '- ${Money.format(bill.discount)}'),
        if (bill.rounding != 0)
          kv('Rounding', '${bill.rounding > 0 ? '+' : '-'} ${Money.format(bill.rounding.abs())}'),
        pw.SizedBox(height: 2),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(width: 1), bottom: pw.BorderSide(width: 1))),
          child: kv(bill.isSale ? 'GRAND TOTAL' : 'TOTAL', Money.format(bill.total), bold: true, scale: 1.25),
        ),
        pw.SizedBox(height: 3),
        if (bill.isSale) ...[
          kv('Amount received', Money.format(bill.totalTendered)),
          if (settled) kv('Change returned', Money.format(bill.totalChange), bold: true),
          if (!settled) ...[
            kv('Amount paid', Money.format(bill.amountPaid)),
            kv('Balance due', Money.format(bill.balanceDue), bold: true),
          ],
          if (bill.payments.length > 1)
            for (final p in bill.payments)
              kv('  ${p.method} ${Dates.display(p.createdAt)}', Money.format(p.amount), scale: 0.85),
          if (bill.payments.length == 1) kv('Payment method', bill.payments.first.method),
        ],
        if (!bill.isSale) ...[
          pw.SizedBox(height: 10),
          pw.Text('Signature: ____________________', style: st()),
        ],
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2)),
            child: pw.Text(statusLabel, style: st(bold: true, scale: 1.2)),
          ),
        ),
        if (s.showQr) ...[
          pw.SizedBox(height: 5),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: 'MEERCAFE|${bill.invoiceNo}|${Money.plain(bill.total)}',
              width: size == PaperSize.mm58 ? 18 * _mm : 22 * _mm,
              height: size == PaperSize.mm58 ? 18 * _mm : 22 * _mm,
            ),
          ),
        ],
        pw.SizedBox(height: 5),
        if (bill.isSale) pw.Text(s.thankYou, textAlign: pw.TextAlign.center, style: st(bold: true)),
        pw.SizedBox(height: 2),
        pw.Text('Prices in Pakistani Rupees (PKR)', textAlign: pw.TextAlign.center, style: st(scale: 0.8)),
        pw.SizedBox(height: 6),
      ],
    );

    doc.addPage(pw.Page(
      pageFormat: format,
      build: (_) => size == PaperSize.a4
          ? pw.Align(alignment: pw.Alignment.topCenter, child: pw.SizedBox(width: 95 * _mm, child: content))
          : content,
    ));
    return doc.save();
  }

  /// Kitchen ticket (KOT) for the chef: only kitchen items and quantities, large text,
  /// no prices. Returns null when the bill has nothing for the kitchen.
  static Future<Uint8List?> buildKitchenTicket(Bill bill, AppSettings s, {bool reprint = false, PaperSize? paper}) async {
    final items = bill.kitchenItems;
    if (items.isEmpty) return null;
    await _loadFonts();
    final size = paper ?? s.paper;
    final base = switch (size) { PaperSize.mm58 => 8.5, PaperSize.mm80 => 10.0, PaperSize.a4 => 12.0 };
    final doc = pw.Document(
      title: 'Kitchen ${bill.invoiceNo}',
      theme: (_regular != null) ? pw.ThemeData.withFont(base: _regular, bold: _bold ?? _regular) : null,
    );
    pw.TextStyle st({double scale = 1, bool bold = false}) =>
        pw.TextStyle(fontSize: base * scale, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    pw.Widget line() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Divider(height: 1, thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
        );
    final content = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        color: PdfColors.black,
        child: pw.Text('KITCHEN ORDER', textAlign: pw.TextAlign.center,
            style: st(scale: 1.4, bold: true).copyWith(color: PdfColors.white)),
      ),
      if (reprint) pw.Text('*** REPRINT ***', textAlign: pw.TextAlign.center, style: st(bold: true)),
      if (bill.billType == BillType.personal)
        pw.Text('STAFF / PERSONAL FOOD', textAlign: pw.TextAlign.center, style: st(bold: true)),
      pw.SizedBox(height: 3),
      pw.Text(bill.invoiceNo, textAlign: pw.TextAlign.center, style: st(scale: 1.1, bold: true)),
      pw.Text('${Dates.display(bill.createdAt)}  ·  ${bill.cashierName}', textAlign: pw.TextAlign.center, style: st(scale: 0.85)),
      if (bill.customerNote.isNotEmpty)
        pw.Text(bill.customerNote, textAlign: pw.TextAlign.center, style: st(scale: 1.2, bold: true)),
      line(),
      for (final it in items)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: base * 3.2, child: pw.Text('${it.quantity} x', style: st(scale: 1.3, bold: true))),
            pw.Expanded(child: pw.Text(it.productName, style: st(scale: 1.3, bold: true))),
          ]),
        ),
      line(),
      pw.Text('Total items: ${items.fold<int>(0, (s, i) => s + i.quantity)}', textAlign: pw.TextAlign.center, style: st()),
      pw.SizedBox(height: 8),
    ]);
    doc.addPage(pw.Page(
      pageFormat: formatFor(size),
      build: (_) => size == PaperSize.a4
          ? pw.Align(alignment: pw.Alignment.topCenter, child: pw.SizedBox(width: 95 * _mm, child: content))
          : content,
    ));
    return doc.save();
  }
}
