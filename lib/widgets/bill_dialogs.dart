import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../app/theme.dart';
import '../models/bill.dart';
import '../services/billing_calculator.dart';
import '../services/print_service.dart';
import '../services/receipt_builder.dart';
import '../utils/money.dart';
import 'common.dart';

/// Prints a bill and reports the outcome. Never creates or changes bill data.
Future<PrintOutcome> printBillWithFeedback(BuildContext context, Bill bill, {bool reprint = false}) async {
  final app = context.read<AppController>();
  final out = await app.printer.printBill(bill, app.settings, reprint: reprint);
  if (context.mounted) showSnack(context, out.message, error: !out.ok);
  return out;
}

/// Prints the chef's kitchen ticket (food items only, no prices).
Future<PrintOutcome> printKitchenWithFeedback(BuildContext context, Bill bill, {bool reprint = false}) async {
  final app = context.read<AppController>();
  final out = await app.printer.printKitchenTicket(bill, app.settings, reprint: reprint);
  if (context.mounted) showSnack(context, out.message, error: !out.ok);
  return out;
}

/// Badge for bill type (only shown for non-sale bills) or payment status.
class BillBadge extends StatelessWidget {
  final Bill bill;
  const BillBadge(this.bill, {super.key});
  @override
  Widget build(BuildContext context) {
    if (bill.isSale) return StatusBadge(bill.paymentStatus);
    final personal = bill.billType == BillType.personal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: personal ? const Color(0xFFE8EEFB) : const Color(0xFFEDE7F6), borderRadius: BorderRadius.circular(20)),
      child: Text(personal ? 'PERSONAL FOOD' : 'EXPENSE',
          style: TextStyle(
              color: personal ? const Color(0xFF1E4FA8) : const Color(0xFF5E35B1),
              fontWeight: FontWeight.w700,
              fontSize: 12)),
    );
  }
}

/// One-click: records the remaining balance so the bill becomes PAID.
Future<Bill?> markBillPaid(BuildContext context, Bill bill) async {
  var method = 'Cash';
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text('Mark ${bill.invoiceNo} as paid?'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Customer pays the remaining ${Money.format(bill.balanceDue)} now.',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (bill.customerNote.isNotEmpty) Text('Customer: ${bill.customerNote}'),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setS(() => method = v ?? 'Cash'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.check),
            label: const Text('Mark as Paid'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  final app = context.read<AppController>();
  try {
    final b = await app.bills.markPaid(app.user!, bill.id, method: method);
    app.sync?.run(trigger: 'payment');
    if (context.mounted) showSnack(context, '${b.invoiceNo} is now PAID.');
    return b;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

Future<void> showReceiptPreview(BuildContext context, Bill bill, {bool reprint = false}) {
  final app = context.read<AppController>();
  return showDialog(
    context: context,
    builder: (c) => Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(c).height * 0.88,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(children: [
              Expanded(
                  child: Text('Receipt ${bill.invoiceNo}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
              IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
            ]),
          ),
          Expanded(
            child: PdfPreview(
              build: (_) => ReceiptBuilder.build(bill, app.settings, reprint: reprint),
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              allowSharing: false,
              pdfFileName: '${bill.invoiceNo}.pdf',
              onPrinted: (_) => app.bills.markPrinted(bill.id),
            ),
          ),
        ]),
      ),
    ),
  );
}

/// Shown after a bill is saved.
class BillCompletedDialog extends StatefulWidget {
  final Bill bill;
  final PrintOutcome? printOutcome;
  const BillCompletedDialog({super.key, required this.bill, this.printOutcome});
  @override
  State<BillCompletedDialog> createState() => _BillCompletedDialogState();
}

class _BillCompletedDialogState extends State<BillCompletedDialog> {
  PrintOutcome? _print;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _print = widget.printOutcome;
  }

  Future<void> _doPrint() async {
    setState(() => _printing = true);
    final app = context.read<AppController>();
    final out = await app.printer.printBill(widget.bill, app.settings, reprint: _print?.ok == true);
    if (mounted) {
      setState(() {
        _print = out;
        _printing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    final settled = b.balanceDue == 0;
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircleAvatar(
            radius: 32,
            backgroundColor: MeerColors.gold,
            child: Icon(Icons.check_rounded, size: 40, color: MeerColors.black),
          ),
          const SizedBox(height: 12),
          Text(b.isSale ? 'Bill saved' : '${b.billType.label} saved',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(b.invoiceNo, style: const TextStyle(color: MeerColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          if (b.isSale) ...[
            _row('Grand total', Money.format(b.total)),
            _row('Amount received', Money.format(b.totalTendered)),
            const Divider(height: 20),
            if (settled)
              _row('Change to return', Money.format(b.totalChange), big: true, color: MeerColors.success)
            else
              _row('Balance due', Money.format(b.balanceDue), big: true, color: MeerColors.danger),
            if (!settled)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('When the customer pays later: Bills → select this bill → Mark as Paid.',
                    style: TextStyle(color: MeerColors.muted, fontSize: 12)),
              ),
          ] else
            _row('Total', Money.format(b.total), big: true),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: BillBadge(b)),
          if (_print != null) ...[
            const SizedBox(height: 14),
            Row(children: [
              Icon(_print!.ok ? Icons.print : Icons.print_disabled,
                  color: _print!.ok ? MeerColors.success : MeerColors.danger, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_print!.message,
                      style: TextStyle(color: _print!.ok ? MeerColors.success : MeerColors.danger, fontSize: 13))),
            ]),
          ],
        ]),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      actions: [
        TextButton.icon(
          onPressed: () => showReceiptPreview(context, b),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
        if (b.kitchenItems.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => printKitchenWithFeedback(context, b,
                reprint: context.read<AppController>().settings.kitchenTicket),
            icon: const Icon(Icons.soup_kitchen_outlined),
            label: const Text('Kitchen Ticket'),
          ),
        OutlinedButton.icon(
          onPressed: _printing ? null : _doPrint,
          icon: _printing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.print_outlined),
          label: Text(_print?.ok == true ? 'Reprint' : 'Print Receipt'),
        ),
        ElevatedButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('New Bill'),
        ),
      ],
    );
  }

  Widget _row(String k, String v, {bool big = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: big ? 17 : 15, fontWeight: big ? FontWeight.w700 : null))),
          Text(v, style: TextStyle(fontSize: big ? 24 : 15, fontWeight: FontWeight.w800, color: color)),
        ]),
      );
}

/// Records an additional payment against a bill with a balance due.
class RecordPaymentDialog extends StatefulWidget {
  final Bill bill;
  const RecordPaymentDialog({super.key, required this.bill});
  @override
  State<RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<RecordPaymentDialog> {
  late final _amount = TextEditingController(text: Money.input(widget.bill.balanceDue));
  String _method = 'Cash';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final due = widget.bill.balanceDue;
    final received = Money.parse(_amount.text);
    final out = received == null ? null : BillingCalculator.payment(due: due, received: received);
    return AlertDialog(
      title: Text('Record payment — ${widget.bill.invoiceNo}'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Balance due: ${Money.format(due)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            decoration: InputDecoration(
                labelText: 'Amount received (Rs.)', errorText: received == null ? 'Enter a valid amount' : null),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
            onChanged: (v) => setState(() => _method = v ?? 'Cash'),
          ),
          const SizedBox(height: 16),
          if (out != null) ...[
            Text('Change to return: ${Money.format(out.changeReturned)}'),
            Text('Remaining balance: ${Money.format(out.balanceDue)}'),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy || received == null || received <= 0
              ? null
              : () async {
                  setState(() => _busy = true);
                  final app = context.read<AppController>();
                  try {
                    final b = await app.bills
                        .addPayment(app.user!, widget.bill.id, amountReceived: received, method: _method);
                    app.sync?.run(trigger: 'payment');
                    if (context.mounted) Navigator.pop(context, b);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                    setState(() => _busy = false);
                  }
                },
          child: const Text('Save payment'),
        ),
      ],
    );
  }
}
