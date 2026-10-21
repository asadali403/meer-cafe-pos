import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_controller.dart';
import '../../models/product.dart';
import '../../widgets/common.dart';

class CategoriesDialog extends StatefulWidget {
  const CategoriesDialog({super.key});
  @override
  State<CategoriesDialog> createState() => _CategoriesDialogState();
}

class _CategoriesDialogState extends State<CategoriesDialog> {
  List<Category> _cats = [];
  final _new = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await context.read<AppController>().products.categories(includeInactive: true);
    if (mounted) setState(() => _cats = cats);
  }

  Future<void> _try(Future<void> Function() f) async {
    try {
      await f();
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _rename(Category c) async {
    final ctl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || !mounted) return;
    final app = context.read<AppController>();
    await _try(() => app.products.updateCategory(app.user!, c.id, name: name, active: c.active));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppController>();
    return AlertDialog(
      title: const Text('Categories'),
      content: SizedBox(
        width: 540,
        height: 460,
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _new,
                decoration: const InputDecoration(hintText: 'New category name'),
                onSubmitted: (_) => _add(app),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: () => _add(app), child: const Text('Add')),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(children: [
              for (final c in _cats)
                ListTile(
                  title: Text(c.name),
                  subtitle: Text([
                    c.active ? 'Active' : 'Inactive — hidden from billing',
                    c.kitchen ? 'printed on kitchen ticket' : 'not sent to kitchen',
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(onPressed: () => _rename(c), icon: const Icon(Icons.edit_outlined), tooltip: 'Rename'),
                    Tooltip(
                      message: 'Send to kitchen (chef ticket)',
                      child: IconButton(
                        onPressed: () => _try(() => app.products.setCategoryKitchen(app.user!, c.id, !c.kitchen)),
                        icon: Icon(c.kitchen ? Icons.soup_kitchen : Icons.soup_kitchen_outlined,
                            color: c.kitchen ? const Color(0xFFA8862A) : Colors.black26),
                      ),
                    ),
                    Switch(
                      value: c.active,
                      onChanged: (v) => _try(() => app.products.updateCategory(app.user!, c.id, name: c.name, active: v)),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }

  Future<void> _add(AppController app) async {
    if (_new.text.trim().isEmpty) return;
    await _try(() async {
      await app.products.addCategory(app.user!, _new.text);
      _new.clear();
    });
  }
}
