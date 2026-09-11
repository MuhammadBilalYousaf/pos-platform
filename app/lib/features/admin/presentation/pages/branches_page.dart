import 'package:flutter/material.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
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
      subtitle: 'Manage your business branches, locations, and assigned staff.',
      actions: [
        FilledButton.icon(
          style: adminPrimaryButtonStyle,
          onPressed: () => _edit(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('+ Add Branch'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: kAdminAccent))
          : _error != null
              ? Center(child: Text(_error!))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 1100 ? 3 : constraints.maxWidth >= 700 ? 2 : 1;
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.35,
                      ),
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return AdminSurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  ),
                                  AdminStatusPill(
                                    label: row.active ? 'Active' : 'Inactive',
                                    tone: row.active ? AdminStatusTone.success : AdminStatusTone.neutral,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(row.code, style: const TextStyle(color: kAdminMuted, fontSize: 12)),
                              if (row.address != null && row.address!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(row.address!, maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                              if (row.phone != null && row.phone!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(row.phone!, style: const TextStyle(color: kAdminMuted, fontSize: 12)),
                              ],
                              const Spacer(),
                              Row(
                                children: [
                                  TextButton(onPressed: () => setState(() => _staffFor = row.id), child: const Text('Staff')),
                                  const Spacer(),
                                  TextButton(onPressed: () => _edit(branch: row), child: const Text('Edit')),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
