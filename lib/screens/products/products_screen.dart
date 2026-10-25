import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../models/product.dart';
import '../../utils/dates.dart';
import '../../utils/money.dart';
import '../../widgets/common.dart';
import 'categories_dialog.dart';
import 'product_form_dialog.dart';

/// Admin-only product management (CRUD, activate/deactivate, categories).
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  List<Product> _products = [];
  List<Category> _categories = [];
  int? _categoryId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppController>();
    try {
      final cats = await app.products.categories(includeInactive: true);
      final prods = await app.products.list(categoryId: _categoryId, search: _search.text);
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

  Future<void> _edit([Product? p]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ProductFormDialog(product: p, categories: _categories.where((c) => c.active || c.id == p?.categoryId).toList()),
    );
    if (saved == true) {
      _load();
      if (mounted) showSnack(context, p == null ? 'Product added.' : 'Product updated.');
    }
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      _load();
      if (mounted) showSnack(context, ok);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(
        title: 'Products',
        subtitle: 'Menu items and prices. Price changes never alter old bills.',
        actions: [
          if (!_loading && _products.isEmpty && _search.text.isEmpty && _categoryId == null)
            OutlinedButton.icon(
              onPressed: () => _run(() async {
                await app.products.loadMenu(app.user!);
              }, "Meer's Cafe menu loaded."),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text("Load Meer's Cafe menu"),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              await showDialog(context: context, builder: (_) => const CategoriesDialog());
              _load();
            },
            icon: const Icon(Icons.category_outlined),
            label: const Text('Categories'),
          ),
          ElevatedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add product')),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(hintText: 'Search products', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => _load(),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<int?>(
            value: _categoryId,
            hint: const Text('All categories'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All categories')),
              for (final c in _categories)
                DropdownMenuItem(value: c.id, child: Text(c.active ? c.name : '${c.name} (inactive)')),
            ],
            onChanged: (v) {
              setState(() => _categoryId = v);
              _load();
            },
          ),
          const Spacer(),
          Text('${_products.length} product(s)', style: const TextStyle(color: MeerColors.muted)),
        ]),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: MeerColors.gold))
                : _products.isEmpty
                    ? const EmptyState(icon: Icons.coffee_outlined, text: 'No products yet. Click "Add product".')
                    : SingleChildScrollView(
                        child: LayoutBuilder(
                          builder: (context, c) => ConstrainedBox(
                            constraints: BoxConstraints(minWidth: c.maxWidth),
                            child: DataTable(
                              columnSpacing: 24,
                              columns: const [
                                DataColumn(label: Text('ID')),
                                DataColumn(label: Text('Product')),
                                DataColumn(label: Text('Category')),
                                DataColumn(label: Text('Price'), numeric: true),
                                DataColumn(label: Text('Active')),
                                DataColumn(label: Text('Updated')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: [for (final p in _products) _row(p)],
                            ),
                          ),
                        ),
                      ),
          ),
        ),
      ),
    ]);
  }

  DataRow _row(Product p) {
    final app = context.read<AppController>();
    return DataRow(cells: [
      DataCell(Text(p.code, style: const TextStyle(color: MeerColors.muted))),
      DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (p.description.isNotEmpty)
          Text(p.description, style: const TextStyle(color: MeerColors.muted, fontSize: 12), overflow: TextOverflow.ellipsis),
      ])),
      DataCell(Text(p.categoryName)),
      DataCell(Text(Money.format(p.pricePaisa), style: const TextStyle(fontWeight: FontWeight.w700))),
      DataCell(Switch(
        value: p.active,
        onChanged: (v) => _run(() => app.products.setActive(app.user!, p.id!, v), v ? 'Product activated.' : 'Product deactivated.'),
      )),
      DataCell(Text(Dates.display(p.updatedAt), style: const TextStyle(fontSize: 12))),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Edit', onPressed: () => _edit(p), icon: const Icon(Icons.edit_outlined)),
        IconButton(
          tooltip: 'Delete',
          onPressed: () async {
            if (await confirm(context, 'Delete product?',
                '"${p.name}" will be removed from the menu. Past bills keep their original name and price.',
                ok: 'Delete', danger: true)) {
              _run(() => app.products.delete(app.user!, p.id!), 'Product deleted.');
            }
          },
          icon: const Icon(Icons.delete_outline, color: MeerColors.danger),
        ),
      ])),
    ]);
  }
}
