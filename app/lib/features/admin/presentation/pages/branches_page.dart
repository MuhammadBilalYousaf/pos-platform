import 'package:flutter/material.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../auth/domain/entities/session.dart';
import '../../data/admin_repository.dart';
import 'staff_page.dart';

class BranchesPage extends StatefulWidget {
  const BranchesPage({super.key});

  @override
  State<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends State<BranchesPage> {
  List<BranchProfile> _rows = const [];
  String? _error;
  bool _loading = true;
  String? _staffFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await sl<AdminRepository>().listBranches();
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

  Future<void> _edit({BranchProfile? branch}) async {
    final name = TextEditingController(text: branch?.name ?? '');
    final code = TextEditingController(text: branch?.code ?? '');
    final address = TextEditingController(text: branch?.address ?? '');
    final phone = TextEditingController(text: branch?.phone ?? '');
    var active = branch?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(branch == null ? 'Branch' : 'Edit branch'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                  const SizedBox(height: 12),
                  TextField(controller: code, decoration: const InputDecoration(labelText: 'Code')),
                  const SizedBox(height: 12),
                  TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
                  const SizedBox(height: 12),
                  TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
                  if (branch != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: active,
                      onChanged: (value) => setLocal(() => active = value),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    if (branch == null) {
      await sl<AdminRepository>().createBranch(
        name: name.text.trim(),
        code: code.text.trim(),
        address: address.text.trim(),
        phone: phone.text.trim(),
      );
    } else {
      await sl<AdminRepository>().updateBranch(
        id: branch.id,
        name: name.text.trim(),
        code: code.text.trim(),
        address: address.text.trim(),
        phone: phone.text.trim(),
        active: active,
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_staffFor != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _staffFor = null),
                icon: const Icon(Icons.arrow_back),
                label: const Text('All branches'),
              ),
            ),
          ),
          Expanded(child: StaffPage(fixedBranchId: _staffFor)),
        ],
      );
    }
    return PageFrame(
      title: 'Branches',
      subtitle: 'Create locations, then assign managers and employees. Stock and tickets follow the branch.',
      actions: [
        FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Branch')),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  children: [
                    for (final row in _rows)
                      Card(
                        child: ListTile(
                          title: Text(row.name),
                          subtitle: Text('${row.code}${row.active ? '' : ' · inactive'}'),
                          trailing: TextButton(onPressed: () => setState(() => _staffFor = row.id), child: const Text('Staff')),
                          onTap: () => _edit(branch: row),
                        ),
                      ),
                  ],
                ),
    );
  }
}
