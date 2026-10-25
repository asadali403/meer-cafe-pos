import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../models/app_settings.dart';
import '../../models/bill.dart';
import '../../services/receipt_builder.dart';
import '../../utils/dates.dart';
import '../../widgets/common.dart';

/// Admin settings: cafe details, receipt, printer and billing rules.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Map<String, String> _v;
  final _ctl = <String, TextEditingController>{};
  List<Printer> _printers = [];
  bool _loadingPrinters = true;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppController>().settings;
    _v = {...AppSettings.defaults, ...s.values};
    for (final k in ['cafe_name', 'tagline', 'address', 'phone', 'thank_you', 'cashier_max_discount_pct', 'invoice_prefix']) {
      _ctl[k] = TextEditingController(text: _v[k]);
    }
    _refreshPrinters();
  }

  Future<void> _refreshPrinters() async {
    setState(() => _loadingPrinters = true);
    final p = await context.read<AppController>().printer.printers();
    if (mounted) {
      setState(() {
        _printers = p;
        _loadingPrinters = false;
      });
    }
  }

  Future<void> _save() async {
    for (final e in _ctl.entries) {
      _v[e.key] = e.value.text.trim();
    }
    final pct = int.tryParse(_v['cashier_max_discount_pct']!);
    if (pct == null || pct < 0 || pct > 100) return showSnack(context, 'Cashier discount limit must be 0-100.', error: true);
    if (_v['cafe_name']!.isEmpty) return showSnack(context, 'Cafe name is required.', error: true);
    if (!RegExp(r'^[A-Za-z]{1,6}$').hasMatch(_v['invoice_prefix']!)) {
      return showSnack(context, 'Invoice prefix must be 1-6 letters.', error: true);
    }
    final app = context.read<AppController>();
    try {
      // Sync keys are managed on the Sync screen.
      final values = Map.of(_v)..removeWhere((k, _) => k.startsWith('sync_'));
      await app.saveSettings(values);
      if (mounted) showSnack(context, 'Settings saved.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Bill _sampleBill() {
    final now = Dates.dbNow();
    return Bill(
      id: 'sample',
      invoiceNo: '${(_ctl['invoice_prefix']!.text.isEmpty ? 'MC' : _ctl['invoice_prefix']!.text).toUpperCase()}-${Dates.compact(DateTime.now())}-0001',
      businessDate: Dates.day(DateTime.now()),
      createdAt: now,
      cashierId: 0,
      cashierName: context.read<AppController>().user!.displayName,
      customerNote: '',
      subtotal: 107000,
      discount: 7000,
      rounding: 0,
      total: 100000,
      amountPaid: 100000,
      balanceDue: 0,
      paymentStatus: PaymentStatus.paid,
      printCount: 0,
      syncStatus: 'pending',
      items: const [
        BillItem(id: '1', billId: 'sample', lineNo: 1, productId: 1, productName: 'Cappuccino', categoryName: 'Coffee', quantity: 1, unitPrice: 45000, lineTotal: 45000),
        BillItem(id: '2', billId: 'sample', lineNo: 2, productId: 2, productName: 'Zinger Burger', categoryName: 'Burger', quantity: 1, unitPrice: 55000, lineTotal: 55000),
        BillItem(id: '3', billId: 'sample', lineNo: 3, productId: 3, productName: 'Mineral Water', categoryName: 'Drinks', quantity: 1, unitPrice: 7000, lineTotal: 7000),
      ],
      payments: [
        Payment(id: 'p', billId: 'sample', amount: 100000, tendered: 150000, changeGiven: 50000, method: 'Cash', receivedByName: '', createdAt: now, businessDate: Dates.day(DateTime.now())),
      ],
    );
  }

  Future<void> _testPrint() async {
    await _save();
    if (!mounted) return;
    final app = context.read<AppController>();
    // Same path as a real bill: kitchen ticket + customer receipt in one job.
    final out = await app.printer.printBoth(_sampleBill(), app.settings);
    if (mounted) showSnack(context, out.ok ? 'Test print sent: ${out.message}' : out.message, error: !out.ok);
  }

  Widget _field(String key, String label, {String? helper, int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
            controller: _ctl[key],
            maxLines: maxLines,
            decoration: InputDecoration(labelText: label, helperText: helper)),
      );

  Widget _switch(String key, String label, {String? subtitle}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _v[key] == '1',
        onChanged: (b) => setState(() => _v[key] = b ? '1' : '0'),
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle),
      );

  @override
  Widget build(BuildContext context) {
    final printerNames = _printers.map((p) => p.name).toList();
    final selectedPrinter = _v['printer_name']!;
    return ListView(children: [
      PageHeader(
        title: 'Settings',
        subtitle: 'Receipt, printer and billing rules',
        actions: [ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Save settings'))],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
        child: Wrap(spacing: 16, runSpacing: 16, children: [
          SizedBox(
            width: 520,
            child: SectionCard(
              title: 'Cafe & receipt details',
              child: Column(children: [
                _field('cafe_name', 'Cafe name'),
                _field('tagline', 'Tagline'),
                _switch('show_tagline', 'Show tagline on receipt'),
                _field('address', 'Address', maxLines: 2),
                _field('phone', 'Phone number'),
                _field('thank_you', 'Thank-you message'),
                _switch('show_qr', 'Print QR code with invoice reference'),
                Row(children: [
                  Expanded(
                    child: Text(
                      _v['logo_path']!.isEmpty ? 'Receipt logo: Meer Cafe default logo' : 'Receipt logo: ${_v['logo_path']}',
                      style: const TextStyle(color: MeerColors.muted),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final f = await openFile(acceptedTypeGroups: const [
                        XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg'])
                      ]);
                      if (f != null) setState(() => _v['logo_path'] = f.path);
                    },
                    child: const Text('Choose logo...'),
                  ),
                  if (_v['logo_path']!.isNotEmpty)
                    TextButton(onPressed: () => setState(() => _v['logo_path'] = ''), child: const Text('Use default')),
                ]),
              ]),
            ),
          ),
          SizedBox(
            width: 520,
            child: Column(children: [
              SectionCard(
                title: 'Printer',
                actions: [
                  IconButton(onPressed: _refreshPrinters, icon: const Icon(Icons.refresh), tooltip: 'Refresh printers'),
                ],
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_loadingPrinters) const LinearProgressIndicator(color: MeerColors.gold),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPrinter.isEmpty || printerNames.contains(selectedPrinter) ? selectedPrinter : '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Receipt printer'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Ask every time (Windows print dialog)')),
                      for (final p in _printers)
                        DropdownMenuItem(value: p.name, child: Text('${p.name}${p.isDefault ? '  (default)' : ''}')),
                    ],
                    onChanged: (v) => setState(() => _v['printer_name'] = v ?? ''),
                  ),
                  if (selectedPrinter.isNotEmpty && !printerNames.contains(selectedPrinter) && !_loadingPrinters)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Saved printer "$selectedPrinter" is not connected.',
                          style: const TextStyle(color: MeerColors.danger)),
                    ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _v['paper'],
                    decoration: const InputDecoration(labelText: 'Paper width'),
                    items: [for (final p in PaperSize.values) DropdownMenuItem(value: p.name, child: Text(p.label))],
                    onChanged: (v) => setState(() => _v['paper'] = v ?? 'mm80'),
                  ),
                  if (_v['paper'] != 'a4') ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _v['printer_mode'] == 'driver' ? 'driver' : 'thermal',
                      decoration: const InputDecoration(
                          labelText: 'Printer type',
                          helperText: 'Thermal = prints directly and cuts the paper after each slip.'),
                      items: const [
                        DropdownMenuItem(value: 'thermal', child: Text('Thermal receipt printer (recommended)')),
                        DropdownMenuItem(value: 'driver', child: Text('Use the Windows printer driver')),
                      ],
                      onChanged: (v) => setState(() => _v['printer_mode'] = v ?? 'thermal'),
                    ),
                  ],
                  _switch('auto_print', 'Print customer receipt automatically when a bill is completed'),
                  const Divider(height: 24),
                  _switch('kitchen_ticket', 'Print kitchen ticket for the chef',
                      subtitle: 'Food items + quantities only, no prices. Printed together with the customer '
                          'receipt in one job (one click). Choose categories in Products → Categories.'),
                  if (_v['kitchen_ticket'] == '1')
                    DropdownButtonFormField<String>(
                      initialValue: _v['kitchen_printer_name']!.isEmpty ||
                              printerNames.contains(_v['kitchen_printer_name'])
                          ? _v['kitchen_printer_name']
                          : '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Kitchen printer'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Same as receipt printer')),
                        for (final p in _printers) DropdownMenuItem(value: p.name, child: Text(p.name)),
                      ],
                      onChanged: (v) => setState(() => _v['kitchen_printer_name'] = v ?? ''),
                    ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 6),
                  Row(children: [
                    OutlinedButton.icon(onPressed: _testPrint, icon: const Icon(Icons.print_outlined), label: const Text('Save & test print')),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (c) => Dialog(
                          child: SizedBox(
                            width: 520,
                            height: MediaQuery.sizeOf(c).height * 0.85,
                            child: PdfPreview(
                              build: (_) => ReceiptBuilder.build(_sampleBill(),
                                  AppSettings({..._v, for (final e in _ctl.entries) e.key: e.value.text})),
                              canChangePageFormat: false,
                              canChangeOrientation: false,
                              canDebug: false,
                              allowSharing: false,
                            ),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Preview sample receipt'),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Billing rules',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DropdownButtonFormField<String>(
                    initialValue: _v['rounding_step'],
                    decoration: const InputDecoration(
                        labelText: 'Cash rounding',
                        helperText: 'When enabled, a separate "Rounding" line is shown on the bill and receipt.'),
                    items: const [
                      DropdownMenuItem(value: '0', child: Text('No rounding (exact total)')),
                      DropdownMenuItem(value: '100', child: Text('Round to nearest Rs. 1')),
                      DropdownMenuItem(value: '500', child: Text('Round to nearest Rs. 5')),
                      DropdownMenuItem(value: '1000', child: Text('Round to nearest Rs. 10')),
                    ],
                    onChanged: (v) => setState(() => _v['rounding_step'] = v ?? '0'),
                  ),
                  const SizedBox(height: 18),
                  _field('cashier_max_discount_pct', 'Maximum discount a cashier may give (%)',
                      helper: 'Admins can give any discount up to the subtotal.'),
                  _field('invoice_prefix', 'Invoice prefix',
                      helper: 'Sales: MC-20261009-0001 · Personal food: PF-… · Expenses: EX-…'),
                  _switch('cashier_custom_items', 'Allow cashiers to add custom items',
                      subtitle: 'Hand-typed name and price. Admins can always add custom items and expenses.'),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}
