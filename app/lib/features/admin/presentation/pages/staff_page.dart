import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import '../../../auth/domain/entities/session.dart';
import '../../../auth/domain/permissions.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/admin_repository.dart';
import '../bloc/branch_context_cubit.dart';

class StaffPage extends StatefulWidget {
  const StaffPage({super.key, this.fixedBranchId});
  final String? fixedBranchId;

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  List<StaffMember> _rows = const [];
  List<BranchProfile> _branches = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await sl<AdminRepository>().listStaff(branchId: widget.fixedBranchId);
      final branches = await sl<AdminRepository>().listBranches();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _branches = branches;
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

  String _branchName(StaffMember row) {
    for (final branch in _branches) {
      if (branch.id == row.branchId) return branch.name;
    }
    return row.branchId ?? '';
  }

  Future<void> _edit({StaffMember? member}) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    final roles = PosRole.invitableBy(auth.session.user.role);
    if (roles.isEmpty) return;
    final name = TextEditingController(text: member?.name ?? '');
    final email = TextEditingController(text: member?.email ?? '');
    final password = TextEditingController();
    var role = member?.role ?? roles.last;
    var branchId = member?.branchId ?? widget.fixedBranchId ?? context.read<BranchContextCubit>().state.selectedBranchId ?? (_branches.isEmpty ? null : _branches.first.id);
    var active = member?.active ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(member == null ? 'Invite staff' : 'Edit staff'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                      if (member == null) ...[
                        const SizedBox(height: 12),
                        TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                        const SizedBox(height: 12),
                        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Temporary password')),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: roles.contains(role) ? role : roles.first,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: [
                          for (final item in roles) DropdownMenuItem(value: item, child: Text(PosRole.label(item))),
                        ],
                        onChanged: (value) {
                          if (value != null) setLocal(() => role = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: branchId,
                        decoration: const InputDecoration(labelText: 'Branch'),
                        items: [
                          for (final branch in _branches.where((item) => item.active))
                            DropdownMenuItem(value: branch.id, child: Text(branch.name)),
                        ],
                        onChanged: (value) => setLocal(() => branchId = value),
                      ),
                      if (member != null)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Active'),
                          value: active,
                          onChanged: (value) => setLocal(() => active = value),
                        ),
                    ],
                  ),
                ),
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
    if (saved != true) return;
    final assigned = branchId;
    if (assigned == null) return;
    try {
      if (member == null) {
        await sl<AdminRepository>().inviteStaff(
          name: name.text.trim(),
          email: email.text.trim(),
          password: password.text,
          role: role,
          branchId: assigned,
        );
      } else {
        await sl<AdminRepository>().updateStaff(
          id: member.id,
          name: name.text.trim(),
          role: role,
          branchId: assigned,
          active: active,
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<BranchContextCubit, BranchContextState>(
      listener: (_, __) {
        if (widget.fixedBranchId == null) _load();
      },
      child: PageFrame(
        title: 'Staff',
        subtitle: 'Manage your team members, roles, and branch assignments.',
        actions: [
          FilledButton.icon(
            style: adminPrimaryButtonStyle,
            onPressed: () => _edit(),
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('+ Add Staff'),
          ),
        ],
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kAdminAccent))
            : _error != null
                ? Center(child: Text(_error!))
                : AdminSurfaceCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        const AdminTableHeader(columns: ['Name', 'Role', 'Branch', 'Status', '']),
                        Expanded(
                          child: ListView.separated(
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: kAdminBorder),
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              return InkWell(
                                onTap: () => _edit(member: row),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: kAdminAccentSoft,
                                              child: Text(
                                                row.name.isEmpty ? '?' : row.name.substring(0, 1).toUpperCase(),
                                                style: const TextStyle(color: kAdminAccent, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(child: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                                          ],
                                        ),
                                      ),
                                      Expanded(child: Text(PosRole.label(row.role))),
                                      Expanded(child: Text(_branchName(row))),
                                      Expanded(
                                        child: AdminStatusPill(
                                          label: row.active ? 'Active' : 'Inactive',
                                          tone: row.active ? AdminStatusTone.success : AdminStatusTone.neutral,
                                        ),
                                      ),
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: IconButton(onPressed: () => _edit(member: row), icon: const Icon(Icons.edit_outlined, size: 20)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
