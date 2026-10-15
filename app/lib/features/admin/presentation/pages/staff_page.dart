import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/password_field.dart';
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
  String _query = '';
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
    return row.branchId ?? '—';
  }

  List<StaffMember> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows.where((row) {
      return row.name.toLowerCase().contains(q) ||
          row.email.toLowerCase().contains(q) ||
          PosRole.label(row.role).toLowerCase().contains(q) ||
          _branchName(row).toLowerCase().contains(q) ||
          row.id.toLowerCase().contains(q);
    }).toList();
  }

  String? get _actorRole {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return null;
    return auth.session.user.role;
  }

  bool _canEdit(StaffMember member) {
    final actor = _actorRole;
    if (actor == null) return false;
    return PosRole.canEditStaffRole(actor, member.role);
  }

  Future<void> _edit({StaffMember? member}) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    final actorRole = auth.session.user.role;
    final roles = PosRole.invitableBy(actorRole);
    if (roles.isEmpty) return;
    if (member != null && !PosRole.canEditStaffRole(actorRole, member.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You cannot view or edit a ${PosRole.label(member.role)}. '
            'Only staff below your role are available.',
          ),
        ),
      );
      return;
    }
    final name = TextEditingController(text: member?.name ?? '');
    final email = TextEditingController(text: member?.email ?? '');
    final password = TextEditingController();
    var role = member != null && roles.contains(member.role) ? member.role : roles.last;
    var branchId = member?.branchId ??
        widget.fixedBranchId ??
        context.read<BranchContextCubit>().state.selectedBranchId ??
        (_branches.isEmpty ? null : _branches.first.id);
    var active = member?.active ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(member == null ? 'Add staff' : 'Staff details'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (member != null) ...[
                        Text('User ID: ${member.id}', style: const TextStyle(fontSize: 12, color: kAdminMuted)),
                        const SizedBox(height: 12),
                      ],
                      TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
                      const SizedBox(height: 12),
                      TextField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email / login'),
                      ),
                      const SizedBox(height: 12),
                      PasswordField(
                        controller: password,
                        label: member == null ? 'Password' : 'New password (optional)',
                        helperText: member == null
                            ? 'They will sign in with this password'
                            : 'Leave blank to keep the current password. Enter a new one to reset it.',
                        autofillHints: const [AutofillHints.newPassword],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('staff-role-$role'),
                        initialValue: roles.contains(role) ? role : roles.first,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: [
                          for (final item in roles)
                            DropdownMenuItem(value: item, child: Text(PosRole.label(item))),
                        ],
                        onChanged: (value) {
                          if (value == null || !roles.contains(value)) return;
                          setLocal(() => role = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('staff-branch-$branchId'),
                        initialValue: branchId,
                        decoration: const InputDecoration(labelText: 'Primary branch'),
                        items: [
                          for (final branch in _branches.where((item) => item.active))
                            DropdownMenuItem(value: branch.id, child: Text('${branch.name} (${branch.code})')),
                        ],
                        onChanged: (value) => setLocal(() => branchId = value),
                      ),
                      if (member != null) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Active'),
                          subtitle: const Text('Inactive staff cannot use the POS'),
                          value: active,
                          onChanged: (value) => setLocal(() => active = value),
                        ),
                      ],
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
    if (saved != true) {
      name.dispose();
      email.dispose();
      password.dispose();
      return;
    }
    final assigned = branchId;
    if (assigned == null) {
      name.dispose();
      email.dispose();
      password.dispose();
      return;
    }
    try {
      if (member == null) {
        if (password.text.trim().isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Enter a password for the new staff member.')),
            );
          }
          return;
        }
        await sl<AdminRepository>().inviteStaff(
          name: name.text.trim(),
          email: email.text.trim(),
          password: password.text,
          role: role,
          branchId: assigned,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff member created.')));
      } else {
        final warning = await sl<AdminRepository>().updateStaff(
          id: member.id,
          name: name.text.trim(),
          email: email.text.trim(),
          role: role,
          branchId: assigned,
          active: active,
          newPassword: password.text.trim().isEmpty ? null : password.text,
          previousEmail: member.email,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(warning == null ? 'Staff details saved.' : 'Staff saved. $warning')),
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      name.dispose();
      email.dispose();
      password.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final actorRole = _actorRole;
    final canAdd = actorRole != null && PosRole.invitableBy(actorRole).isNotEmpty;
    final visible = _visible;
    return BlocListener<BranchContextCubit, BranchContextState>(
      listener: (_, __) {
        if (widget.fixedBranchId == null) _load();
      },
      child: PageFrame(
        title: 'Staff',
        subtitle: actorRole == PosRole.branchManager
            ? 'Managers can only view and edit employees (cashiers) — not admins or other managers.'
            : 'View and edit team members below your role — name, email, role, branch, and password.',
        actions: [
          if (canAdd)
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
                : Column(
                    children: [
                      TextField(
                        decoration: adminInputDecoration('Search name, email, role, branch', icon: Icons.search),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: AdminSurfaceCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              const AdminTableHeader(columns: ['Name / ID', 'Email', 'Role', 'Branch', 'Status', '']),
                              Expanded(
                                child: visible.isEmpty
                                    ? const Center(child: Text('No staff match this search.'))
                                    : ListView.separated(
                                        itemCount: visible.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1, color: kAdminBorder),
                                        itemBuilder: (context, index) {
                                          final row = visible[index];
                                          final editable = _canEdit(row);
                                          return InkWell(
                                            onTap: editable ? () => _edit(member: row) : null,
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
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(row.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                                              Text(
                                                                row.id,
                                                                style: const TextStyle(fontSize: 10, color: kAdminMuted),
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Expanded(child: Text(row.email, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                                  Expanded(child: Text(PosRole.label(row.role))),
                                                  Expanded(child: Text(_branchName(row), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                                  Expanded(
                                                    child: AdminStatusPill(
                                                      label: row.active ? 'Active' : 'Inactive',
                                                      tone: row.active ? AdminStatusTone.success : AdminStatusTone.neutral,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Align(
                                                      alignment: Alignment.centerRight,
                                                      child: editable
                                                          ? IconButton(
                                                              tooltip: 'Edit staff',
                                                              onPressed: () => _edit(member: row),
                                                              icon: const Icon(Icons.edit_outlined, size: 20),
                                                            )
                                                          : const SizedBox.shrink(),
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
                    ],
                  ),
      ),
    );
  }
}
