import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../models/bill.dart';
import '../../models/product.dart';
import '../../services/print_service.dart';
import '../../utils/money.dart';
import '../../widgets/bill_dialogs.dart';
import '../../widgets/common.dart';
import 'cart_controller.dart';

IconData categoryIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('tea') || n.contains('chai')) return Icons.emoji_food_beverage_outlined;
  if (n.contains('coffee')) return Icons.coffee_outlined;
  if (n.contains('burger')) return Icons.lunch_dining_outlined;
  if (n.contains('fries')) return Icons.fastfood_outlined;
  if (n.contains('drink') || n.contains('juice')) return Icons.local_drink_outlined;
  if (n.contains('snack')) return Icons.cookie_outlined;
  if (n.contains('dessert') || n.contains('cake')) return Icons.cake_outlined;
  return Icons.restaurant_menu;
}

/// Fast POS screen: product grid on the left, current bill on the right.
/// Supports customer sales, personal/staff food and (admin) expense vouchers,
/// plus hand-typed custom items.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  late final CartController cart;
  final _search = TextEditingController();
  final _received = TextEditingController();
  final _discount = TextEditingController();
  final _note = TextEditingController();
  final _searchFocus = FocusNode();
  List<Category> _categories = [];
  List<Product> _products = [];
  int? _categoryId;
  bool _loading = true;
  bool _saving = false;
  Bill? _lastBill;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    cart = CartController(roundingStep: app.settings.roundingStep)..addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    cart.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _canCustom {
    final app = context.read<AppController>();
    return app.user!.isAdmin || app.settings.cashierCustomItems;
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    try {
      final cats = await app.products.categories();
      final prods = await app.products.list(activeOnly: true, categoryId: _categoryId, search: _search.text);
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _products = prods;
        _loading = false;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _resetInputs() {
    _received.clear();
    _discount.clear();
    _note.clear();
  }

  Future<void> _complete() async {
    if (_saving) return; // guard against double clicks
    final app = context.read<AppController>();
    if (cart.isEmpty) return showSnack(context, 'Add at least one item.', error: true);
    if (cart.discountError != null) return showSnack(context, 'Fix the discount: ${cart.discountError}', error: true);
    final received = cart.received;
    if (received == null) return showSnack(context, 'Amount received is not a valid number.', error: true);
    final totals = cart.totals;
    if (cart.isSale && received < totals.total) {
      final ok = await confirm(
        context,
        received == 0 ? 'Pay later?' : 'Partial payment',
        'Amount received ${Money.format(received)} is less than the total ${Money.format(totals.total)}.\n\n'
            'The bill will be saved as ${received == 0 ? 'UNPAID' : 'PARTIALLY PAID'} with a balance due of '
            '${Money.format(totals.total - received)}.\n\n'
            'Later, open Bills → select the bill → "Mark as Paid".',
        ok: 'Save bill',
      );
      if (!ok || !mounted) return;
    }
    if (!cart.isSale) {
      final ok = await confirm(
        context,
        'Save ${cart.type.label}?',
        '${cart.type.label} of ${Money.format(totals.total)} will be recorded.\n'
            'It is NOT counted as a sale or as cash collected.',
        ok: 'Save',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final bill = await app.bills.completeBill(
        app.user!,
        billId: cart.billId,
        lines: cart.toInput(),
        customLines: cart.toCustomInput(),
        type: cart.type,
        settings: app.settings,
        discount: cart.discount ?? 0,
        amountReceived: received,
        method: cart.method,
        customerNote: cart.customerNote,
      );
      cart.clear(newBill: true);
      _resetInputs();
      setState(() => _lastBill = bill);
      app.sync?.run(trigger: 'bill'); // background; billing never waits for the internet
      final PrintOutcome? printed = await app.printer.printAfterSave(bill, app.settings);
      if (!mounted) return;
      await showDialog(context: context, builder: (_) => BillCompletedDialog(bill: bill, printOutcome: printed));
      _searchFocus.requestFocus();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addCustomItem() async {
    final r = await showDialog<_CustomItem>(
      context: context,
      builder: (_) => _CustomItemDialog(type: cart.type),
    );
    if (r != null) cart.addCustom(r.name, r.price, r.qty, kitchen: r.kitchen);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _complete,
        const SingleActivator(LogicalKeyboardKey.f2): () => _searchFocus.requestFocus(),
      },
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _productsPanel()),
        SizedBox(width: 440, child: _cartPanel()),
      ]),
    );
  }

  Widget _productsPanel() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
        child: Row(children: [
          const Text('New Bill', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(width: 24),
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search products or category (F2)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _load();
                        }),
              ),
              onChanged: (_) => _load(),
              onSubmitted: (_) {
                if (_products.length == 1) cart.add(_products.first);
              },
            ),
          ),
          const SizedBox(width: 8),
          if (_canCustom)
            OutlinedButton.icon(
              onPressed: _addCustomItem,
              icon: const Icon(Icons.edit_note),
              label: const Text('Custom Item'),
            ),
          IconButton(tooltip: 'Refresh products', onPressed: _load, icon: const Icon(Icons.refresh)),
        ]),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            _chip('All', null),
            for (final c in _categories) _chip(c.name, c.id),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: MeerColors.gold))
            : _products.isEmpty
                ? const EmptyState(
                    icon: Icons.coffee_outlined, text: 'No products found.\nAn admin can add products in Products.')
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200, mainAxisExtent: 150, crossAxisSpacing: 14, mainAxisSpacing: 14),
                    itemCount: _products.length,
                    itemBuilder: (_, i) => _productCard(_products[i]),
                  ),
      ),
    ]);
  }

  Widget _chip(String label, int? id) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _categoryId == id,
          showCheckmark: false,
          onSelected: (_) {
            setState(() => _categoryId = id);
            _load();
          },
        ),
      );

  Widget _productCard(Product p) {
    final qty = cart.quantityOf(p.id!);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => cart.add(p),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: qty > 0 ? MeerColors.gold : MeerColors.border, width: qty > 0 ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFBF3DA), borderRadius: BorderRadius.circular(10)),
                child: Icon(categoryIcon(p.categoryName), color: MeerColors.goldDark, size: 22),
              ),
              const Spacer(),
              if (qty > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: MeerColors.black, borderRadius: BorderRadius.circular(12)),
                  child: Text('x$qty', style: const TextStyle(color: MeerColors.gold, fontWeight: FontWeight.w800)),
                ),
            ]),
            const Spacer(),
            Text(p.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.2)),
            const SizedBox(height: 4),
            Text(Money.format(p.pricePaisa),
                style: const TextStyle(color: MeerColors.goldDark, fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ),
      ),
    );
  }

  Widget _typeSelector() {
    final isAdmin = context.read<AppController>().user!.isAdmin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: SegmentedButton<BillType>(
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? MeerColors.gold : Colors.white),
        ),
        segments: [
          const ButtonSegment(value: BillType.sale, label: Text('Customer Sale'), icon: Icon(Icons.person_outline)),
          const ButtonSegment(value: BillType.personal, label: Text('Personal Food'), icon: Icon(Icons.restaurant)),
          if (isAdmin)
            const ButtonSegment(value: BillType.expense, label: Text('Expense'), icon: Icon(Icons.payments_outlined)),
        ],
        selected: {cart.type},
        onSelectionChanged: (s) {
          if (!cart.isSale || s.first != BillType.sale) {
            _received.clear();
            _discount.clear();
          }
          cart.setType(s.first);
        },
      ),
    );
  }

  Widget _cartPanel() {
    final totals = cart.totals;
    final pay = cart.payment;
    final receivedInvalid = cart.received == null;
    final sale = cart.isSale;
    final noteLabel = switch (cart.type) {
      BillType.sale => 'Customer / table (optional)',
      BillType.personal => 'For whom? e.g. Owner, Chef (optional)',
      BillType.expense => 'Expense note, e.g. paid to (optional)',
    };
    final bottom = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _totalRow('Subtotal', Money.format(totals.subtotal)),
      if (sale) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Expanded(child: Text('Discount')),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _discount,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: '0',
                errorText: cart.discountError,
                errorStyle: const TextStyle(fontSize: 10, height: 0.8),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (v) => cart.update(() => cart.discountText = v),
            ),
          ),
          const SizedBox(width: 6),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('Rs')),
              ButtonSegment(value: true, label: Text('%')),
            ],
            selected: {cart.discountIsPercent},
            onSelectionChanged: (s) => cart.update(() => cart.discountIsPercent = s.first),
          ),
        ]),
        if (cart.discountIsPercent && (cart.discount ?? 0) > 0)
          Align(
            alignment: Alignment.centerRight,
            child: Text('= ${Money.format(cart.discount!)}', style: const TextStyle(color: MeerColors.muted, fontSize: 12)),
          ),
        if (totals.rounding != 0) ...[
          const SizedBox(height: 4),
          _totalRow('Cash rounding', '${totals.rounding > 0 ? '+' : '-'} ${Money.format(totals.rounding.abs())}'),
        ],
      ],
      const Divider(height: 18),
      Row(children: [
        Expanded(
            child: Text(sale ? 'GRAND TOTAL' : '${cart.type.short.toUpperCase()} TOTAL',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        Text(Money.format(totals.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26)),
      ]),
      if (!sale)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            cart.type == BillType.personal
                ? 'Personal / staff food — not counted as sales or cash collected.'
                : 'Expense voucher — money paid out, not a sale.',
            style: const TextStyle(color: MeerColors.warning, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      if (sale) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _received,
              decoration: InputDecoration(
                labelText: 'Amount received (Rs.)',
                errorText: receivedInvalid ? 'Invalid amount' : null,
              ),
              onChanged: (v) => cart.update(() => cart.receivedText = v),
              onSubmitted: (_) => _complete(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              initialValue: cart.method,
              key: ValueKey('method-${cart.billId}'),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Method'),
              items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => cart.update(() => cart.method = v ?? 'Cash'),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _quick('Exact', totals.total),
          for (final r in [500, 1000, 2000, 5000])
            if (r * 100 >= totals.total) _quick('Rs $r', r * 100),
          _quick('Pay Later', 0),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: pay.balanceDue > 0 ? const Color(0xFFFDE8E8) : const Color(0xFFE6F4EA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Expanded(
              child: Text(pay.balanceDue > 0 ? 'Balance due' : 'Change returned',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Text(Money.format(pay.balanceDue > 0 ? pay.balanceDue : pay.changeReturned),
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: pay.balanceDue > 0 ? MeerColors.danger : MeerColors.success)),
          ]),
        ),
      ],
      const SizedBox(height: 8),
      TextField(
        controller: _note,
        maxLength: 80,
        decoration: InputDecoration(labelText: noteLabel, counterText: '', isDense: true),
        onChanged: (v) => cart.customerNote = v,
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: PopupMenuButton<String>(
            enabled: _lastBill != null,
            tooltip: 'Print last bill',
            onSelected: (v) async {
              final app = context.read<AppController>();
              final fresh = await app.bills.getBill(_lastBill!.id);
              if (fresh == null || !mounted) return;
              if (v == 'both') {
                await printBothWithFeedback(context, fresh, reprint: fresh.printCount > 0);
              } else if (v == 'receipt') {
                await printBillWithFeedback(context, fresh, reprint: fresh.printCount > 0);
              } else {
                await printKitchenWithFeedback(context, fresh, reprint: true);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'both', child: Text('Both (chef + customer)')),
              PopupMenuItem(value: 'receipt', child: Text('Customer receipt')),
              PopupMenuItem(value: 'kitchen', child: Text('Kitchen ticket (chef)')),
            ],
            child: IgnorePointer(
              child: OutlinedButton.icon(
                onPressed: _lastBill == null ? null : () {},
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print'),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _saving || cart.isEmpty ? null : _complete,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle_outline),
            label: Text(_saving
                ? 'Saving...'
                : switch (cart.type) {
                    BillType.sale => 'Complete Bill (F9)',
                    BillType.personal => 'Save Personal (F9)',
                    BillType.expense => 'Save Expense (F9)',
                  }),
          ),
        ),
      ]),
      if (_lastBill != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Last: ${_lastBill!.invoiceNo} · ${Money.format(_lastBill!.total)}',
              textAlign: TextAlign.center, style: const TextStyle(color: MeerColors.muted, fontSize: 12)),
        ),
    ]);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: MeerColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
            color: MeerColors.black,
            child: Row(children: [
              const Icon(Icons.receipt_long, color: MeerColors.gold),
              const SizedBox(width: 10),
              const Text('Current Bill', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text('${cart.itemCount} item(s)', style: const TextStyle(color: MeerColors.goldLight)),
              const Spacer(),
              TextButton.icon(
                onPressed: cart.isEmpty
                    ? null
                    : () async {
                        if (await confirm(context, 'Clear bill?', 'Remove all items from the current bill?', ok: 'Clear')) {
                          cart.clear();
                          _resetInputs();
                        }
                      },
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear'),
              ),
            ]),
          ),
          _typeSelector(),
          Expanded(
            child: cart.isEmpty
                ? EmptyState(
                    icon: Icons.touch_app_outlined,
                    text: cart.type == BillType.expense
                        ? 'Use "Custom Item" to enter the expense\n(e.g. Gas cylinder — Rs 3,000).'
                        : 'Tap a product to add it to the bill.')
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                    itemBuilder: (_, i) => _cartLine(cart.lines[i]),
                  ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: c.maxHeight * 0.66),
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFCFBF7),
                border: Border(top: BorderSide(color: MeerColors.border)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: bottom,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _quick(String label, int paisa) => ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        onPressed: cart.isEmpty
            ? null
            : () {
                _received.text = Money.input(paisa);
                cart.update(() => cart.receivedText = _received.text);
              },
      );

  Widget _totalRow(String k, String v) => Row(children: [
        Expanded(child: Text(k)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);

  Widget _cartLine(CartLine l) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (l.isCustom)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFFBF3DA), borderRadius: BorderRadius.circular(6)),
                  child: const Text('custom', style: TextStyle(fontSize: 10, color: MeerColors.goldDark)),
                ),
            ]),
            Text('${Money.format(l.unitPrice)} each', style: const TextStyle(color: MeerColors.muted, fontSize: 12)),
          ]),
        ),
        _qtyButton(Icons.remove, () => cart.decrement(l.key)),
        SizedBox(
          width: 40,
          child: InkWell(
            onTap: () => _editQty(l),
            child: Text('${l.quantity}',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
        _qtyButton(Icons.add, () => cart.increment(l.key)),
        SizedBox(
          width: 96,
          child: Text(Money.format(l.lineTotal),
              textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        IconButton(
          tooltip: 'Remove item',
          onPressed: () => cart.remove(l.key),
          icon: const Icon(Icons.close, size: 18, color: MeerColors.danger),
        ),
      ]),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(border: Border.all(color: MeerColors.border), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16),
        ),
      );

  Future<void> _editQty(CartLine l) async {
    final c = TextEditingController(text: '${l.quantity}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quantity — ${l.name}'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (s) => Navigator.pop(ctx, int.tryParse(s)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)), child: const Text('OK')),
        ],
      ),
    );
    if (v != null) cart.setQuantity(l.key, v);
  }
}

class _CustomItem {
  final String name;
  final int price;
  final int qty;
  final bool kitchen;
  const _CustomItem(this.name, this.price, this.qty, this.kitchen);
}

/// Hand-typed item: any name and price (e.g. "Special order", "Gas cylinder").
class _CustomItemDialog extends StatefulWidget {
  final BillType type;
  const _CustomItemDialog({required this.type});
  @override
  State<_CustomItemDialog> createState() => _CustomItemDialogState();
}

class _CustomItemDialogState extends State<_CustomItemDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController(text: '1');
  late bool _kitchen = widget.type != BillType.expense;
  String? _error;

  void _ok() {
    final name = _name.text.trim();
    final price = Money.parse(_price.text);
    final qty = int.tryParse(_qty.text.trim());
    if (name.isEmpty || name.length > 60) return setState(() => _error = 'Enter a name (up to 60 characters).');
    if (price == null) return setState(() => _error = 'Enter a valid amount, e.g. 350 or 350.50.');
    if (qty == null || qty < 1 || qty > 9999) return setState(() => _error = 'Quantity must be 1-9999.');
    Navigator.pop(context, _CustomItem(name, price, qty, _kitchen));
  }

  @override
  Widget build(BuildContext context) {
    final expense = widget.type == BillType.expense;
    return AlertDialog(
      title: Text(expense ? 'Add expense' : 'Add custom item'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(
                labelText: expense ? 'Expense (e.g. Gas cylinder, Milk, Salary)' : 'Item name (e.g. Special Karahi)'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Price / amount (Rs.)', prefixText: 'Rs. '),
                onSubmitted: (_) => _ok(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _qty,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Qty'),
                onSubmitted: (_) => _ok(),
              ),
            ),
          ]),
          if (!expense)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _kitchen,
              onChanged: (v) => setState(() => _kitchen = v ?? false),
              title: const Text('Send to kitchen (print on chef ticket)'),
            ),
          if (_error != null) Text(_error!, style: const TextStyle(color: MeerColors.danger)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _ok, child: const Text('Add')),
      ],
    );
  }
}
