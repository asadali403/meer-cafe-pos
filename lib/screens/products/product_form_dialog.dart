import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../models/product.dart';
import '../../repositories/product_repository.dart';
import '../../utils/errors.dart';
import '../../utils/money.dart';

class ProductFormDialog extends StatefulWidget {
  final Product? product;
  final List<Category> categories;
  const ProductFormDialog({super.key, this.product, required this.categories});
  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _price = TextEditingController(text: widget.product == null ? '' : Money.input(widget.product!.pricePaisa));
  late final _desc = TextEditingController(text: widget.product?.description ?? '');
  late int? _categoryId = widget.product?.categoryId ?? (widget.categories.isEmpty ? null : widget.categories.first.id);
  late bool _active = widget.product?.active ?? true;
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final price = Money.parse(_price.text);
    if (price == null) return setState(() => _error = 'Enter a valid price, e.g. 250 or 250.50 (no negatives).');
    if (_categoryId == null) return setState(() => _error = 'Choose a category.');
    final p = Product(
      id: widget.product?.id,
      name: _name.text,
      categoryId: _categoryId!,
      pricePaisa: price,
      description: _desc.text,
      active: _active,
    );
    try {
      ProductRepository.validate(p);
    } catch (e) {
      return setState(() => _error = friendlyError(e));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppController>();
    try {
      await app.products.save(app.user!, p);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Add product' : 'Edit ${widget.product!.code}'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _name, autofocus: true, maxLength: 60, decoration: const InputDecoration(labelText: 'Product name *')),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Category *'),
            items: [for (final c in widget.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _price,
            decoration: const InputDecoration(labelText: 'Selling price (Rs.) *', prefixText: 'Rs. '),
          ),
          const SizedBox(height: 14),
          TextField(
              controller: _desc, maxLength: 200, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (optional)')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Active (visible to cashiers)'),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: MeerColors.danger, fontWeight: FontWeight.w600)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
