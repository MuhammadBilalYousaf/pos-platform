import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/firebase/tenant_context.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import '../../data/admin_repository.dart';
import '../bloc/branch_context_cubit.dart';

class SuppliersTab extends StatefulWidget {
  const SuppliersTab({
    super.key,
    this.standalone = false,
    this.searchQuery = '',
    this.onRegisterCreate,
  });

  final bool standalone;
  final String searchQuery;
  final ValueChanged<VoidCallback>? onRegisterCreate;

  @override
  State<SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends State<SuppliersTab> {
  List<Map<String, String>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRegisterCreate?.call(_add);
    });
  }

  @override
  void didUpdateWidget(covariant SuppliersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await sl<AdminRepository>().listNamed('suppliers');
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    await sl<AdminRepository>().saveNamed(collection: 'suppliers', name: name.text.trim(), extra: {'phone': phone.text.trim()});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kAdminAccent));
    }
    final q = widget.searchQuery.trim().toLowerCase();
    final visible = _rows.where((row) {
      if (q.isEmpty) return true;
      final hay = '${row['name']} ${row['subtitle']} ${row['phone']}'.toLowerCase();
      return hay.contains(q);
    }).toList();

    final table = Column(
      children: [
        const AdminTableHeader(columns: ['#', 'Supplier Name', 'Contact', 'Phone', 'Status', '']),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No suppliers yet.')),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: visible.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: kAdminBorder),
              itemBuilder: (context, index) {
                final row = visible[index];
                final name = row['name'] ?? '';
                final phone = row['phone'] ?? row['subtitle'] ?? '';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(flex: 1, child: Text('${index + 1}', style: const TextStyle(color: kAdminMuted))),
                      Expanded(flex: 3, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      Expanded(flex: 2, child: Text(name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 2, child: Text(phone, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 2, child: const AdminStatusPill(label: 'Active', tone: AdminStatusTone.success)),
                      Expanded(
                        flex: 1,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz, size: 20)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );

    if (widget.standalone) {
      return table;
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Supplier'),
            ),
          ),
        ),
        Expanded(child: table),
      ],
    );
  }
}

class PurchasesTab extends StatefulWidget {
  const PurchasesTab({
    super.key,
    this.standalone = false,
    this.onRegisterCreate,
  });

  final bool standalone;
  final ValueChanged<VoidCallback>? onRegisterCreate;

  @override
  State<PurchasesTab> createState() => _PurchasesTabState();
}

class _PurchasesTabState extends State<PurchasesTab> with SingleTickerProviderStateMixin {
  List<Map<String, String>> _rows = const [];
  late TabController _filterTabs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _filterTabs = TabController(length: 4, vsync: this);
    _filterTabs.addListener(() => setState(() {}));
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRegisterCreate?.call(_add);
    });
  }

  @override
  void dispose() {
    _filterTabs.dispose();
    super.dispose();
  }

  String _purchaseStatus(Map<String, String> row) {
    return (row['status'] ?? 'Received').trim();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await sl<AdminRepository>().listNamed('purchases');
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final ingredient = TextEditingController();
    final qty = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Purchase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: ingredient, decoration: const InputDecoration(labelText: 'Ingredient SKU')),
            const SizedBox(height: 12),
            TextField(controller: qty, decoration: const InputDecoration(labelText: 'Quantity received')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Receive')),
        ],
      ),
    );
    if (ok != true) return;
    final branchId = sl<TenantContext>().requireBranchId();
    final sku = ingredient.text.trim().toUpperCase();
    await sl<AdminRepository>().upsertIngredient(name: sku, sku: sku, quantity: '0', reorderLevel: '0');
    await sl<AdminRepository>().adjustStock(inventoryId: '${branchId}_$sku', delta: qty.text.trim(), reason: 'Purchase');
    await sl<AdminRepository>().saveNamed(
      collection: 'purchases',
      name: sku,
      extra: {
        'ingredient_id': sku,
        'quantity_base': qty.text.trim(),
        'branch_id': branchId,
        'status': 'Received',
      },
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filter = switch (_filterTabs.index) {
      1 => 'Pending',
      2 => 'Received',
      3 => 'Cancelled',
      _ => 'All',
    };
    final visible = _rows.where((row) {
      if (filter == 'All') return true;
      final st = _purchaseStatus(row);
      if (filter == 'Pending') return st.toLowerCase().contains('pending');
      if (filter == 'Received') return st.toLowerCase().contains('received') || st.isEmpty;
      if (filter == 'Cancelled') return st.toLowerCase().contains('cancel');
      return true;
    }).toList();

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator(color: kAdminAccent));
    } else {
      body = Column(
        children: [
          if (widget.standalone)
            TabBar(
              controller: _filterTabs,
              isScrollable: true,
              labelColor: kAdminAccent,
              unselectedLabelColor: kAdminMuted,
              indicatorColor: kAdminAccent,
              tabs: const [
                Tab(text: 'All Purchases'),
                Tab(text: 'Pending'),
                Tab(text: 'Received'),
                Tab(text: 'Cancelled'),
              ],
            ),
          const AdminTableHeader(columns: ['PO', 'Date', 'Supplier', 'Items', 'Total', 'Status', '']),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No purchases recorded yet.')),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: visible.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: kAdminBorder),
                itemBuilder: (context, index) {
                  final row = visible[index];
                  final name = row['name'] ?? '—';
                  final status = _purchaseStatus(row);
                  final tone = status.toLowerCase().contains('cancel')
                      ? AdminStatusTone.danger
                      : status.toLowerCase().contains('pending')
                          ? AdminStatusTone.warning
                          : AdminStatusTone.success;
                  final created = row['created_at'];
                  var dateLabel = row['subtitle'] ?? '—';
                  if (created != null && created.isNotEmpty) {
                    try {
                      dateLabel = DateFormat('MMM d, yyyy').format(DateTime.parse(created));
                    } catch (_) {}
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text('#${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700))),
                        Expanded(flex: 2, child: Text(dateLabel, style: const TextStyle(fontSize: 12))),
                        Expanded(flex: 2, child: Text('Supplier', style: const TextStyle(fontSize: 12))),
                        Expanded(child: Text('1', style: const TextStyle(fontSize: 12))),
                        Expanded(flex: 2, child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Expanded(flex: 2, child: AdminStatusPill(label: status, tone: tone)),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(onPressed: () {}, icon: const Icon(Icons.visibility_outlined, size: 20)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      );
    }

    return BlocListener<BranchContextCubit, BranchContextState>(
      listener: (_, __) => _load(),
      child: widget.standalone
          ? body
          : Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Receive')),
                  ),
                ),
                Expanded(child: body),
              ],
            ),
    );
  }
}

class TransfersTab extends StatefulWidget {
  const TransfersTab({super.key});
  @override
  State<TransfersTab> createState() => _TransfersTabState();
}

class _TransfersTabState extends State<TransfersTab> {
  List<Map<String, String>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await sl<AdminRepository>().listNamed('stock_transfers');
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _add() async {
    final branches = context.read<BranchContextCubit>().state.branches;
    if (branches.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Need at least two branches to transfer.')));
      return;
    }
    final sku = TextEditingController();
    final qty = TextEditingController();
    var from = branches.first.id;
    var to = branches[1].id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Stock transfer'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: from,
                    decoration: const InputDecoration(labelText: 'From'),
                    items: [for (final branch in branches) DropdownMenuItem(value: branch.id, child: Text(branch.name))],
                    onChanged: (value) {
                      if (value != null) setLocal(() => from = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: to,
                    decoration: const InputDecoration(labelText: 'To'),
                    items: [for (final branch in branches) DropdownMenuItem(value: branch.id, child: Text(branch.name))],
                    onChanged: (value) {
                      if (value != null) setLocal(() => to = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: sku, decoration: const InputDecoration(labelText: 'Ingredient SKU')),
                  const SizedBox(height: 12),
                  TextField(controller: qty, decoration: const InputDecoration(labelText: 'Quantity')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Transfer')),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    await sl<AdminRepository>().transferStock(
      ingredientId: sku.text.trim().toUpperCase(),
      fromBranchId: from,
      toBranchId: to,
      quantity: qty.text.trim(),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _add, icon: const Icon(Icons.swap_horiz), label: const Text('Transfer'))),
        Expanded(
          child: ListView(
            children: [
              for (final row in _rows) ListTile(title: Text(row['name'] ?? '')),
            ],
          ),
        ),
      ],
    );
  }
}

class WasteTab extends StatefulWidget {
  const WasteTab({super.key});
  @override
  State<WasteTab> createState() => _WasteTabState();
}

class _WasteTabState extends State<WasteTab> {
  List<Map<String, String>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await sl<AdminRepository>().listNamed('waste');
    if (!mounted) return;
    setState(() => _rows = rows);
  }

  Future<void> _add() async {
    final sku = TextEditingController();
    final qty = TextEditingController();
    final reason = TextEditingController(text: 'Waste');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Waste / write-off'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: sku, decoration: const InputDecoration(labelText: 'Ingredient SKU')),
            const SizedBox(height: 12),
            TextField(controller: qty, decoration: const InputDecoration(labelText: 'Quantity')),
            const SizedBox(height: 12),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
        ],
      ),
    );
    if (ok != true) return;
    await sl<AdminRepository>().recordWaste(ingredientId: sku.text.trim().toUpperCase(), quantity: qty.text.trim(), reason: reason.text.trim());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<BranchContextCubit, BranchContextState>(
      listener: (_, __) => _load(),
      child: Column(
        children: [
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _add, icon: const Icon(Icons.remove_circle_outline), label: const Text('Waste'))),
          Expanded(
            child: ListView(
              children: [
                for (final row in _rows) ListTile(title: Text(row['name'] ?? ''), subtitle: Text(row['subtitle'] ?? '')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
