import 'package:flutter/material.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import '../../data/admin_repository.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  List<PosCustomer> _rows = const [];
  String? _error;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await sl<AdminRepository>().listCustomers();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
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
    final phone = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    await sl<AdminRepository>().saveCustomer(name: name.text.trim(), phone: phone.text.trim(), note: note.text.trim());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _rows.where((row) {
      if (_query.isEmpty) return true;
      final hay = '${row.name} ${row.phone} ${row.note}'.toLowerCase();
      return hay.contains(_query.toLowerCase());
    }).toList();

    return PageFrame(
      title: 'Customers',
      subtitle: 'Saved guests for takeaway and delivery tickets.',
      actions: [
        FilledButton.icon(
          style: adminPrimaryButtonStyle,
          onPressed: _add,
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Add Customer'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: kAdminAccent))
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    TextField(
                      decoration: adminInputDecoration('Search customers', icon: Icons.search),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: AdminSurfaceCard(
                        padding: EdgeInsets.zero,
                        child: visible.isEmpty
                            ? const Center(child: Text('No customers yet.'))
                            : Column(
                                children: [
                                  const AdminTableHeader(columns: ['#', 'Name', 'Phone', 'Notes', '']),
                                  Expanded(
                                    child: ListView.separated(
                                      itemCount: visible.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1, color: kAdminBorder),
                                      itemBuilder: (context, index) {
                                        final row = visible[index];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Row(
                                            children: [
                                              Expanded(child: Text('${index + 1}', style: const TextStyle(color: kAdminMuted))),
                                              Expanded(flex: 2, child: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                                              Expanded(flex: 2, child: Text(row.phone ?? '—')),
                                              Expanded(flex: 3, child: Text(row.note ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis)),
                                              Expanded(
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
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
