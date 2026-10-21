import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../repositories/report_repository.dart';
import '../../utils/dates.dart';
import '../../utils/money.dart';
import '../../widgets/common.dart';

/// Admin overview for today.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  SalesSummary? _today;
  int _outstanding = 0;
  ReportTable? _products, _methods, _recent;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    final u = app.user!;
    final d = Dates.day(DateTime.now());
    try {
      final today = await app.reports.summary(u, d, d);
      final outstanding = await app.reports.totalOutstanding(u);
      final products = await app.reports.productSales(u, d, d);
      final methods = await app.reports.paymentMethods(u, d, d);
      final recent = await app.reports.recentBills(u, limit: 10);
      await app.sync?.refreshCounts();
      if (!mounted) return;
      setState(() {
        _today = today;
        _outstanding = outstanding;
        _products = products;
        _methods = methods;
        _recent = recent;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<List<String>> _fmt(ReportTable t, {int max = 1000}) => [
        for (final r in t.rows.take(max))
          [
            for (var i = 0; i < r.length; i++)
              t.moneyColumns.contains(i) && r[i] is int
                  ? Money.format(r[i] as int)
                  : i == 1 && t.columns[1] == 'Time'
                      ? Dates.display('${r[i]}')
                      : t.columns[i] == 'Status'
                          ? switch ('${r[i]}') {
                              'paid' => 'PAID',
                              'partial' => 'PARTIAL',
                              'personal' => 'PERSONAL',
                              'expense' => 'EXPENSE',
                              _ => 'UNPAID',
                            }
                          : '${r[i] ?? ''}'
          ]
      ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final t = _today;
    if (_error != null) return Center(child: Text(_error!));
    if (t == null) return const Center(child: CircularProgressIndicator(color: MeerColors.gold));
    final sync = app.sync;
    return ListView(children: [
      PageHeader(
        title: 'Dashboard',
        subtitle: 'Today · ${Dates.displayDay(Dates.day(DateTime.now()))}',
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 1200 ? 5 : (c.maxWidth > 800 ? 3 : 2);
          final w = (c.maxWidth - (cols - 1) * 16) / cols;
          final cards = [
            StatCard(label: "Today's billed sales", value: Money.format(t.billed), icon: Icons.trending_up, highlight: true,
                hint: 'Discounts ${Money.format(t.discount)}'),
            StatCard(label: 'Bills today', value: '${t.bills}', icon: Icons.receipt_long,
                hint: '${t.paidBills} paid · ${t.partialBills} partial · ${t.unpaidBills} unpaid'),
            StatCard(label: 'Cash collected today', value: Money.format(t.collected), icon: Icons.payments_outlined,
                hint: 'Actual payments received'),
            StatCard(label: 'Outstanding balances', value: Money.format(_outstanding), icon: Icons.hourglass_bottom,
                hint: 'All unpaid customer balances'),
            if (sync != null)
              ListenableBuilder(
                listenable: sync,
                builder: (_, _) => StatCard(
                  label: 'Pending Google Sheets sync',
                  value: '${sync.counts.pending + sync.counts.failed}',
                  icon: Icons.cloud_upload_outlined,
                  hint: sync.counts.failed > 0 ? '${sync.counts.failed} failed — see Sync' : 'Synced: ${sync.counts.synced}',
                ),
              ),
          ];
          return Wrap(spacing: 16, runSpacing: 16, children: [for (final card in cards) SizedBox(width: w, child: card)]);
        }),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 1000;
          final productCard = SectionCard(
            title: 'Product sales today',
            child: SimpleTable(columns: _products!.columns, rows: _fmt(_products!, max: 12), numeric: const {2, 3}),
          );
          final methodCard = SectionCard(
            title: 'Payment methods today',
            child: SimpleTable(columns: _methods!.columns, rows: _fmt(_methods!), numeric: const {1, 2}),
          );
          final recentCard = SectionCard(
            title: 'Recent transactions',
            child: SimpleTable(columns: _recent!.columns, rows: _fmt(_recent!), numeric: const {3, 4}),
          );
          if (!wide) {
            return Column(children: [productCard, const SizedBox(height: 16), methodCard, const SizedBox(height: 16), recentCard]);
          }
          return Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: productCard),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: methodCard),
            ]),
            const SizedBox(height: 16),
            recentCard,
          ]);
        }),
      ),
    ]);
  }
}
