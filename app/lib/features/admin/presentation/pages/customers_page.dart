import 'package:flutter/material.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
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
    return PageFrame(
      title: 'Customers',
      subtitle: 'Saved guests for takeaway and delivery tickets. Use the name on POS ticket details.',
      actions: [FilledButton.icon(onPressed: _add, icon: const Icon(Icons.person_add_outlined), label: const Text('Customer'))],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _rows.isEmpty
                  ? const Center(child: Text('No customers yet. Add a guest or save one from POS ticket details.'))
                  : ListView(
                  children: [
                    for (final row in _rows)
                      Card(
                        child: ListTile(
                          title: Text(row.name),
                          subtitle: Text([row.phone, row.note].where((item) => item != null && item.isNotEmpty).join(' · ')),
                        ),
                      ),
                  ],
                ),
    );
  }
}
