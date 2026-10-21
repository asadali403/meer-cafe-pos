import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../models/bill.dart';
import '../../repositories/bill_repository.dart';
import '../../utils/dates.dart';
import '../../utils/money.dart';
import '../../widgets/bill_dialogs.dart';
import '../../widgets/common.dart';

enum _Range { today, week, month, all, custom }

/// Bill history with details, reprint and additional payments.
/// Cashiers see only their own bills (enforced in the repository).
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  _Range _range = _Range.today;
  DateTimeRange? _custom;
  PaymentStatus? _status;
  BillType? _type;
  bool _outstanding = false;
  final _search = TextEditingController();
  List<Bill> _bills = [];
  Bill? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (String?, String?) _dates() {
    final now = DateTime.now();
    return switch (_range) {
      _Range.today => (Dates.day(now), Dates.day(now)),
      _Range.week => (Dates.day(now.subtract(const Duration(days: 6))), Dates.day(now)),
      _Range.month => (Dates.day(now.subtract(const Duration(days: 29))), Dates.day(now)),
      _Range.all => (null, null),
      _Range.custom => _custom == null ? (null, null) : (Dates.day(_custom!.start), Dates.day(_custom!.end)),
    };
  }

  Future<void> _load({String? keepSelected}) async {
    final app = context.read<AppController>();
    final (from, to) = _dates();
    try {
      final list = await app.bills.list(
          app.user!,
          BillFilter(
              fromDate: from,
              toDate: to,
              status: _status,
              type: _type,
              search: _search.text,
              outstandingOnly: _outstanding));
      Bill? sel;
      final selId = keepSelected ?? _selected?.id;
      if (selId != null) sel = await app.bills.getBill(selId);
      if (!mounted) return;
      setState(() {
        _bills = list;
        _selected = sel;
        _loading = false;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _select(Bill b) async {
    final full = await context.read<AppController>().bills.getBill(b.id);
    if (mounted) setState(() => _selected = full);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.read<AppController>().user!.isAdmin;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Bills',
        subtitle: isAdmin ? 'All bills, payments and reprints' : 'Your bills, payments and reprints',
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final r in _Range.values)
            ChoiceChip(
              label: Text(switch (r) {
                _Range.today => 'Today',
                _Range.week => 'Last 7 days',
                _Range.month => 'Last 30 days',
                _Range.all => 'All',
                _Range.custom => _custom == null || _range != _Range.custom
                    ? 'Custom...'
                    : '${Dates.displayDay(Dates.day(_custom!.start))} – ${Dates.displayDay(Dates.day(_custom!.end))}',
              }),
              selected: _range == r,
              showCheckmark: false,
              onSelected: (_) async {
                if (r == _Range.custom) {
                  final picked = await showDateRangePicker(
                      context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
                  if (picked == null) return;
                  _custom = picked;
                }
                setState(() => _range = r);
                _load();
              },
            ),
          const SizedBox(width: 12),
          DropdownButton<PaymentStatus?>(
            value: _status,
            hint: const Text('Any status'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Any status')),
              for (final s in PaymentStatus.values) DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) {
              setState(() => _status = v);
              _load();
            },
          ),
          DropdownButton<BillType?>(
            value: _type,
            hint: const Text('All types'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All types')),
              for (final t in BillType.values) DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            onChanged: (v) {
              setState(() => _type = v);
              _load();
            },
          ),
          FilterChip(
            label: const Text('Unpaid / balance due'),
            selected: _outstanding,
            onSelected: (v) {
              setState(() => _outstanding = v);
              _load();
            },
          ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(hintText: 'Invoice no. or note', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => _load(),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 5, child: Card(child: _list())),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: Card(child: _detail())),
          ]),
        ),
      ),
    ]);
  }

  Widget _list() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: MeerColors.gold));
    if (_bills.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, text: 'No bills found.');
    final total = _bills.where((b) => b.isSale).fold<int>(0, (s, b) => s + b.total);
    final paid = _bills.fold<int>(0, (s, b) => s + b.amountPaid);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Text('${_bills.length} bill(s)', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('Sales ${Money.format(total)}  ·  Paid ${Money.format(paid)}',
              style: const TextStyle(color: MeerColors.muted)),
        ]),
      ),
      const Divider(),
      Expanded(
        child: ListView.separated(
          itemCount: _bills.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (_, i) {
            final b = _bills[i];
            return ListTile(
              selected: _selected?.id == b.id,
              selectedTileColor: const Color(0xFFFBF3DA),
              onTap: () => _select(b),
              title: Text(b.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${Dates.display(b.createdAt)} · ${b.cashierName}${b.customerNote.isEmpty ? '' : ' · ${b.customerNote}'}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(Money.format(b.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                BillBadge(b),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _detail() {
    final b = _selected;
    if (b == null) return const EmptyState(icon: Icons.touch_app_outlined, text: 'Select a bill to see details.');
    Widget kv(String k, String v, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null))),
            Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: color)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Expanded(child: Text(b.invoiceNo, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        BillBadge(b),
      ]),
      if (b.balanceDue > 0)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
              child: Text('Balance due ${Money.format(b.balanceDue)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: MeerColors.danger, fontSize: 16)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final updated = await markBillPaid(context, b);
                if (updated != null) _load(keepSelected: updated.id);
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Mark as Paid'),
            ),
          ]),
        ),
      const SizedBox(height: 4),
      Text('${Dates.display(b.createdAt)} · Cashier: ${b.cashierName}', style: const TextStyle(color: MeerColors.muted)),
      if (b.customerNote.isNotEmpty) Text('Note: ${b.customerNote}', style: const TextStyle(color: MeerColors.muted)),
      Text('Printed ${b.printCount} time(s) · Sync: ${b.syncStatus}',
          style: const TextStyle(color: MeerColors.muted, fontSize: 12)),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ElevatedButton.icon(
          onPressed: () async {
            await printBillWithFeedback(context, b, reprint: b.printCount > 0);
            _load();
          },
          icon: const Icon(Icons.print_outlined),
          label: Text(b.printCount > 0 ? 'Reprint' : 'Print'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            await showReceiptPreview(context, b, reprint: b.printCount > 0);
            _load();
          },
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Preview'),
        ),
        if (b.kitchenItems.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => printKitchenWithFeedback(context, b, reprint: true),
            icon: const Icon(Icons.soup_kitchen_outlined),
            label: const Text('Kitchen Ticket'),
          ),
        if (b.balanceDue > 0)
          FilledButton.icon(
            onPressed: () async {
              final updated =
                  await showDialog<Bill>(context: context, builder: (_) => RecordPaymentDialog(bill: b));
              if (updated != null) {
                _load(keepSelected: updated.id);
                if (mounted) showSnack(context, 'Payment recorded. Status: ${updated.paymentStatus.label}');
              }
            },
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Part payment'),
          ),
      ]),
      const Divider(height: 32),
      const Text('Items', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final it in b.items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text('${it.productName}${it.isCustom ? '  (custom)' : ''}')),
            Text('${it.quantity} × ${Money.format(it.unitPrice, symbol: false)}',
                style: const TextStyle(color: MeerColors.muted)),
            SizedBox(width: 110, child: Text(Money.format(it.lineTotal), textAlign: TextAlign.right)),
          ]),
        ),
      const Divider(height: 24),
      kv('Subtotal', Money.format(b.subtotal)),
      if (b.discount > 0) kv('Discount', '- ${Money.format(b.discount)}'),
      if (b.rounding != 0) kv('Rounding', Money.format(b.rounding)),
      kv(b.isSale ? 'Grand total' : '${b.billType.label} total', Money.format(b.total), bold: true),
      if (!b.isSale)
        const Text('Not a sale — not counted in sales or cash collected.',
            style: TextStyle(color: MeerColors.warning, fontSize: 12)),
      if (b.isSale) ...[
        kv('Amount paid', Money.format(b.amountPaid)),
        kv('Balance due', Money.format(b.balanceDue), color: b.balanceDue > 0 ? MeerColors.danger : null),
        const Divider(height: 24),
        const Text('Payments', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
      ],
      if (b.isSale && b.payments.isEmpty)
        const Text('No payments recorded.', style: TextStyle(color: MeerColors.muted)),
      for (final p in b.payments)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(
              child: Text('${Dates.display(p.createdAt)} · ${p.method} · ${p.receivedByName}\n'
                  'Received ${Money.format(p.tendered)}, change ${Money.format(p.changeGiven)}'),
            ),
            Text(Money.format(p.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
    ]);
  }
}
