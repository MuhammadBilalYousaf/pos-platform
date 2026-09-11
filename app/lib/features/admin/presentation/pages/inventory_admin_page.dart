import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../data/admin_repository.dart';
import '../bloc/branch_context_cubit.dart';

class InventoryAdminPage extends StatefulWidget {
  const InventoryAdminPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<InventoryAdminPage> createState() => _InventoryAdminPageState();
}

class _InventoryAdminPageState extends State<InventoryAdminPage> {
  List<InventoryItem> _rows = const [];
  List<InventoryTransaction> _history = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await sl<AdminRepository>().listInventory();
      final history = await sl<AdminRepository>().listInventoryTransactions();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _history = history;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final sku = TextEditingController();
    final qty = TextEditingController(text: '0');
    final reorder = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ingredient / stock item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: sku, decoration: const InputDecoration(labelText: 'SKU (optional)')),
            const SizedBox(height: 12),
            TextField(controller: qty, decoration: const InputDecoration(labelText: 'Opening quantity')),
            const SizedBox(height: 12),
            TextField(controller: reorder, decoration: const InputDecoration(labelText: 'Reorder level')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    await sl<AdminRepository>().upsertIngredient(
      name: name.text.trim(),
      sku: sku.text.trim().isEmpty ? null : sku.text.trim(),
      quantity: qty.text.trim(),
      reorderLevel: reorder.text.trim(),
    );
    await _load();
  }

  Future<void> _adjust(InventoryItem item) async {
    final delta = TextEditingController();
    final reason = TextEditingController(text: 'Manual adjustment');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Adjust ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('On hand: ${item.quantity}'),
            const SizedBox(height: 12),
            TextField(controller: delta, decoration: const InputDecoration(labelText: 'Change (+10 or -2)')),
            const SizedBox(height: 12),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sl<AdminRepository>().adjustStock(
        inventoryId: item.id,
        delta: delta.text.trim(),
        reason: reason.text.trim(),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!))
            : ListView(
                children: [
                  if (!widget.embedded) ...[
                    Text('On hand', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Item')),
                  ),
                  for (final row in _rows)
                    Card(
                      child: ListTile(
                        title: Text(row.name),
                        subtitle: Text('Qty ${row.quantity} · reorder ${row.reorderLevel}${row.sku == null ? '' : ' · ${row.sku}'}'),
                        trailing: TextButton(onPressed: () => _adjust(row), child: const Text('Adjust')),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text('Stock history', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const Text('No stock movements yet.')
                  else
                    for (final row in _history)
                      ListTile(
                        title: Text('${row.type} · ${row.quantity}'),
                        subtitle: Text(
                          [
                            row.ingredientId ?? row.inventoryId ?? '',
                            if (row.reason != null && row.reason!.isNotEmpty) row.reason!,
                            if (row.orderId != null) 'order ${row.orderId}',
                            row.createdAt.toLocal().toString(),
                          ].where((item) => item.isNotEmpty).join(' · '),
                        ),
                      ),
                ],
              );
    final framed = widget.embedded
        ? body
        : PageFrame(
            title: 'Inventory',
            subtitle: 'Adjustments follow the selected branch. POS recipe sales deduct from this list.',
            child: body,
          );
    return BlocListener<BranchContextCubit, BranchContextState>(
      listener: (_, __) => _load(),
      child: framed,
    );
  }
}
