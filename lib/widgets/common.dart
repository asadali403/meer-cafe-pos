import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/bill.dart';
import '../utils/errors.dart';

class MeerLogo extends StatelessWidget {
  final double size;
  const MeerLogo({super.key, this.size = 96});
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/images/logo.png', width: size, height: size, filterQuality: FilterQuality.medium);
}

/// Page title row used at the top of each screen.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(subtitle!, style: const TextStyle(color: MeerColors.muted)),
                ),
            ]),
          ),
          Wrap(spacing: 10, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? hint;
  final bool highlight;
  const StatCard(
      {super.key, required this.label, required this.value, required this.icon, this.hint, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? Colors.white : MeerColors.black;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: highlight ? MeerColors.black : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: highlight ? MeerColors.black : MeerColors.border),
        gradient: highlight
            ? const LinearGradient(colors: [MeerColors.black, MeerColors.graphite], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: highlight ? MeerColors.gold : const Color(0xFFFBF3DA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: highlight ? MeerColors.black : MeerColors.goldDark),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: highlight ? MeerColors.goldLight : MeerColors.muted, fontSize: 13)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: fg)),
            ),
            if (hint != null)
              Text(hint!, style: TextStyle(fontSize: 12, color: highlight ? Colors.white70 : MeerColors.muted)),
          ]),
        ),
      ]),
    );
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final EdgeInsets padding;
  const SectionCard(
      {super.key, required this.title, required this.child, this.actions = const [], this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            ...actions,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final PaymentStatus status;
  const StatusBadge(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      PaymentStatus.paid => (const Color(0xFFE6F4EA), MeerColors.success),
      PaymentStatus.partial => (const Color(0xFFFFF4E0), MeerColors.warning),
      PaymentStatus.unpaid => (const Color(0xFFFDE8E8), MeerColors.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status.label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: MeerColors.border),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: MeerColors.muted)),
          ]),
        ),
      );
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? MeerColors.danger : MeerColors.charcoal,
      duration: Duration(seconds: error ? 6 : 3),
    ));
}

void showError(BuildContext context, Object e) => showSnack(context, friendlyError(e), error: true);

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        ElevatedButton(
          style: danger ? ElevatedButton.styleFrom(backgroundColor: MeerColors.danger, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Simple table for report data.
class SimpleTable extends StatelessWidget {
  final List<String> columns;
  final List<List<String>> rows;
  final Set<int> numeric;
  const SimpleTable({super.key, required this.columns, required this.rows, this.numeric = const {}});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const EmptyState(icon: Icons.inbox_outlined, text: 'No data for this period.');
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth),
          child: DataTable(
            headingRowHeight: 42,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 44,
            columns: [
              for (var i = 0; i < columns.length; i++) DataColumn(label: Text(columns[i]), numeric: numeric.contains(i)),
            ],
            rows: [
              for (final r in rows) DataRow(cells: [for (final v in r) DataCell(Text(v))]),
            ],
          ),
        ),
      ),
    );
  }
}
