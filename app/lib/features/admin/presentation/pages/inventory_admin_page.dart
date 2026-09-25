import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import '../../data/admin_repository.dart';
import '../bloc/branch_context_cubit.dart';

class InventoryAdminPage extends StatefulWidget {
  const InventoryAdminPage({super.key, this.embedded = false, this.onRegisterCreate});
  final bool embedded;
  final ValueChanged<VoidCallback>? onRegisterCreate;

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
    widget.onRegisterCreate?.call(_add);
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
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await sl<AdminRepository>().upsertIngredient(
        name: name.text.trim(),
        sku: sku.text.trim().isEmpty ? null : sku.text.trim(),
        quantity: qty.text.trim().isEmpty ? '0' : qty.text.trim(),
        reorderLevel: reorder.text.trim().isEmpty ? '0' : reorder.text.trim(),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
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
        ? const Center(child: CircularProgressIndicator(color: kAdminAccent))
        : _error != null
            ? Center(child: Text(_error!))
            : Column(
                children: [
                  if (!widget.embedded)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        style: adminPrimaryButtonStyle,
                        onPressed: _add,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Stock'),
                      ),
                    ),
                  if (!widget.embedded) const SizedBox(height: 12),
                  Expanded(
                    child: widget.embedded
                        ? _stockTable(flex: true)
                        : ListView(
                            children: [
                              _stockTable(flex: false),
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

  Widget _stockTable({required bool flex}) {
    if (_rows.isEmpty) {
      return const Center(child: Text('No stock items yet. Add ingredients to track inventory.'));
    }
    final list = ListView.separated(
      shrinkWrap: !flex,
      physics: flex ? null : const NeverScrollableScrollPhysics(),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: kAdminBorder),
      itemBuilder: (context, index) {
        final row = _rows[index];
        final qty = double.tryParse(row.quantity.replaceAll(',', '')) ?? 0;
        final reorder = double.tryParse(row.reorderLevel.replaceAll(',', '')) ?? 0;
        final low = qty <= reorder;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(child: Text('${index + 1}', style: const TextStyle(color: kAdminMuted))),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: kAdminAccentSoft, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.inventory_2_outlined, size: 18, color: kAdminAccent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
              Expanded(flex: 2, child: Text(row.sku ?? 'General', maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(child: const Text('PCS', style: TextStyle(fontSize: 12))),
              Expanded(child: Text(row.quantity, style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(child: Text(row.reorderLevel, style: const TextStyle(fontSize: 12))),
              Expanded(
                flex: 2,
                child: AdminStatusPill(
                  label: low ? 'Low Stock' : 'In Stock',
                  tone: low ? AdminStatusTone.danger : AdminStatusTone.success,
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(onPressed: () => _adjust(row), icon: const Icon(Icons.tune, size: 20)),
                ),
              ),
            ],
          ),
        );
      },
    );
    return Column(
      children: [
        const AdminTableHeader(columns: ['#', 'Item', 'Category', 'Unit', 'Current Stock', 'Min. Stock', 'Status', '']),
        if (flex) Expanded(child: list) else list,
      ],
    );
  }
}
