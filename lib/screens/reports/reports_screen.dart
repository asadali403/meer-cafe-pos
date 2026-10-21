import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../repositories/report_repository.dart';
import '../../services/export_service.dart';
import '../../utils/dates.dart';
import '../../utils/money.dart';
import '../../widgets/common.dart';

enum _Preset { today, thisWeek, thisMonth, last30, custom }

enum _Report {
  daily('Daily sales'),
  weekly('Weekly sales'),
  monthly('Monthly sales'),
  products('Product-wise'),
  cashiers('Cashier-wise'),
  methods('Payment methods'),
  payments('Payments collected'),
  paid('Paid bills'),
  partial('Partially paid'),
  unpaid('Unpaid bills'),
  outstanding('Outstanding balances'),
  personal('Personal food'),
  expenses('Expenses');

  final String label;
  const _Report(this.label);
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Preset _preset = _Preset.thisMonth;
  DateTimeRange? _custom;
  _Report _report = _Report.daily;
  SalesSummary? _summary;
  ReportTable? _table;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (String, String) get _range {
    final now = DateTime.now();
    final today = Dates.day(now);
    return switch (_preset) {
      _Preset.today => (today, today),
      _Preset.thisWeek => (Dates.day(Dates.startOfWeek(now)), today),
      _Preset.thisMonth => (Dates.day(Dates.startOfMonth(now)), today),
      _Preset.last30 => (Dates.day(now.subtract(const Duration(days: 29))), today),
      _Preset.custom => _custom == null ? (today, today) : (Dates.day(_custom!.start), Dates.day(_custom!.end)),
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final app = context.read<AppController>();
    final u = app.user!;
    final (from, to) = _range;
    try {
      final summary = await app.reports.summary(u, from, to);
      final r = app.reports;
      final table = await switch (_report) {
        _Report.daily => r.salesByPeriod(u, from, to, Grouping.day),
        _Report.weekly => r.salesByPeriod(u, from, to, Grouping.week),
        _Report.monthly => r.salesByPeriod(u, from, to, Grouping.month),
        _Report.products => r.productSales(u, from, to),
        _Report.cashiers => r.cashierSales(u, from, to),
        _Report.methods => r.paymentMethods(u, from, to),
        _Report.payments => r.paymentsCollected(u, from, to),
        _Report.paid => r.billsByStatus(u, from, to, status: 'paid'),
        _Report.partial => r.billsByStatus(u, from, to, status: 'partial'),
        _Report.unpaid => r.billsByStatus(u, from, to, status: 'unpaid'),
        _Report.outstanding => r.outstandingBalances(u),
        _Report.personal => r.nonSaleBills(u, from, to, 'personal'),
        _Report.expenses => r.nonSaleBills(u, from, to, 'expense'),
      };
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _table = table;
        _loading = false;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _export() async {
    final t = _table;
    if (t == null) return;
    final (from, to) = _range;
    final name = 'MeerCafe_${_report.name}_${from}_to_$to.csv';
    try {
      final path = await ExportService.saveCsv(name, t);
      if (path != null && mounted) showSnack(context, 'Exported to $path');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _range;
    final s = _summary;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Reports',
        subtitle: '${Dates.displayDay(from)} – ${Dates.displayDay(to)}  ·  Billed sales and cash collected are shown separately',
        actions: [
          OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.download_outlined), label: const Text('Export CSV / Excel')),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in _Preset.values)
            ChoiceChip(
              showCheckmark: false,
              selected: _preset == p,
              label: Text(switch (p) {
                _Preset.today => 'Today',
                _Preset.thisWeek => 'This week',
                _Preset.thisMonth => 'This month',
                _Preset.last30 => 'Last 30 days',
                _Preset.custom => 'Custom range...',
              }),
              onSelected: (_) async {
                if (p == _Preset.custom) {
                  final r = await showDateRangePicker(
                      context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
                  if (r == null) return;
                  _custom = r;
                }
                setState(() => _preset = p);
                _load();
              },
            ),
        ]),
      ),
      const SizedBox(height: 14),
      if (s != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(children: [
            Expanded(child: StatCard(label: 'Billed sales', value: Money.format(s.billed), icon: Icons.receipt_long, highlight: true, hint: '${s.bills} bills')),
            const SizedBox(width: 14),
            Expanded(child: StatCard(label: 'Payments collected', value: Money.format(s.collected), icon: Icons.payments_outlined, hint: 'Cash/card actually received')),
            const SizedBox(width: 14),
            Expanded(child: StatCard(label: 'Outstanding (these bills)', value: Money.format(s.outstanding), icon: Icons.hourglass_bottom, hint: '${s.partialBills} partial · ${s.unpaidBills} unpaid')),
            const SizedBox(width: 14),
            Expanded(child: StatCard(label: 'Discounts given', value: Money.format(s.discount), icon: Icons.local_offer_outlined)),
            const SizedBox(width: 14),
            Expanded(
                child: StatCard(
                    label: 'Personal food',
                    value: Money.format(s.personalTotal),
                    icon: Icons.restaurant,
                    hint: '${s.personalBills} voucher(s) · not sales')),
            const SizedBox(width: 14),
            Expanded(
                child: StatCard(
                    label: 'Expenses',
                    value: Money.format(s.expenseTotal),
                    icon: Icons.money_off,
                    hint: '${s.expenseBills} voucher(s)')),
          ]),
        ),
      const SizedBox(height: 14),
      SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          children: [
            for (final r in _Report.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  showCheckmark: false,
                  label: Text(r.label),
                  selected: _report == r,
                  onSelected: (_) {
                    setState(() => _report = r);
                    _load();
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Card(
            child: _loading || _table == null
                ? const Center(child: CircularProgressIndicator(color: MeerColors.gold))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: SimpleTable(
                      columns: _table!.columns,
                      numeric: _table!.moneyColumns,
                      rows: [
                        for (final r in _table!.rows)
                          [
                            for (var i = 0; i < r.length; i++)
                              _table!.moneyColumns.contains(i) && r[i] is int
                                  ? Money.format(r[i] as int)
                                  : '${r[i] ?? ''}'
                          ]
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ]);
  }
}
