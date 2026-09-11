import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import '../../../auth/domain/entities/session.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/admin_repository.dart';

class SettingsEditorPage extends StatefulWidget {
  const SettingsEditorPage({super.key, required this.session});
  final Session session;

  @override
  State<SettingsEditorPage> createState() => _SettingsEditorPageState();
}

class _SettingsEditorPageState extends State<SettingsEditorPage> {
  late final _name = TextEditingController(text: widget.session.business?.name ?? '');
  late final _currency = TextEditingController(text: widget.session.business?.currencyCode ?? 'PKR');
  late final _tax = TextEditingController(text: widget.session.business?.taxRate ?? '0');
  late final _primary = TextEditingController(text: widget.session.business?.primaryColor ?? '#1F6F4A');
  late final _secondary = TextEditingController(text: widget.session.business?.secondaryColor ?? '#F4EFE6');
  late final _address = TextEditingController(text: widget.session.business?.address ?? '');
  late final _phone = TextEditingController(text: widget.session.business?.phone ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _tax.dispose();
    _primary.dispose();
    _secondary.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await sl<AdminRepository>().saveBusiness(
        name: _name.text.trim(),
        currencyCode: _currency.text.trim(),
        taxRate: _tax.text.trim(),
        primaryColor: _primary.text.trim(),
        secondaryColor: _secondary.text.trim(),
        address: _address.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      context.read<AuthBloc>().add(const AuthRefreshRequested());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Settings',
      subtitle: 'Configure your business settings, tax, currency, and catalog helpers.',
      actions: [
        FilledButton(
          style: adminPrimaryButtonStyle,
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save Changes'),
        ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: AdminSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _SettingsNavItem(label: 'Business Profile', selected: true),
                  _SettingsNavItem(label: 'Tax & Currency'),
                  _SettingsNavItem(label: 'Receipt Settings'),
                  _SettingsNavItem(label: 'Discounts & Units'),
                  _SettingsNavItem(label: 'Audit Log'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: AdminSurfaceCard(
              child: ListView(
                children: [
                  Text('Business Profile', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  TextField(controller: _name, decoration: adminInputDecoration('Business name')),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _currency, decoration: adminInputDecoration('Currency'))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: _tax, decoration: adminInputDecoration('Tax rate'))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _primary, decoration: adminInputDecoration('Primary color'))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: _secondary, decoration: adminInputDecoration('Secondary color'))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _address, decoration: adminInputDecoration('Address')),
                  const SizedBox(height: 12),
                  TextField(controller: _phone, decoration: adminInputDecoration('Phone')),
                  const SizedBox(height: 24),
                  const Text('Receipt header, footer, and paper size are edited under Receipt in the sidebar.'),
                  const SizedBox(height: 24),
                  Text('Discounts', style: Theme.of(context).textTheme.titleMedium),
                  const _NamedList(collection: 'discounts', extraLabel: 'Amount'),
                  const SizedBox(height: 16),
                  Text('Units', style: Theme.of(context).textTheme.titleMedium),
                  const _NamedList(collection: 'units', extraLabel: 'Code'),
                  const SizedBox(height: 16),
                  Text('Audit', style: Theme.of(context).textTheme.titleMedium),
                  _AuditList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({required this.label, this.selected = false});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? kAdminAccentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: selected ? Border.all(color: kAdminAccent.withValues(alpha: 0.25)) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? kAdminAccent : const Color(0xFF334155),
        ),
      ),
    );
  }
}

class _NamedList extends StatefulWidget {
  const _NamedList({required this.collection, required this.extraLabel});
  final String collection;
  final String extraLabel;

  @override
  State<_NamedList> createState() => _NamedListState();
}

class _NamedListState extends State<_NamedList> {
  List<Map<String, String>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await sl<AdminRepository>().listNamed(widget.collection);
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final extra = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.collection),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name / id')),
            const SizedBox(height: 12),
            TextField(controller: extra, decoration: InputDecoration(labelText: widget.extraLabel)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final extras = <String, dynamic>{
      if (widget.collection == 'discounts') 'amount': extra.text.trim(),
      if (widget.collection == 'units') 'code': extra.text.trim(),
    };
    await sl<AdminRepository>().saveNamed(
      collection: widget.collection,
      name: name.text.trim(),
      extra: extras,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _add, child: const Text('Add'))),
        for (final row in _rows) ListTile(contentPadding: EdgeInsets.zero, title: Text(row['name'] ?? ''), subtitle: Text(row['subtitle'] ?? '')),
      ],
    );
  }
}

class _AuditList extends StatefulWidget {
  @override
  State<_AuditList> createState() => _AuditListState();
}

class _AuditListState extends State<_AuditList> {
  List<Map<String, String>> _rows = const [];

  @override
  void initState() {
    super.initState();
    sl<AdminRepository>().listAudit().then((rows) {
      if (mounted) setState(() => _rows = rows);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) return const Text('No activity recorded yet.');
    return Column(
      children: [
        for (final row in _rows) ListTile(contentPadding: EdgeInsets.zero, title: Text(row['action'] ?? ''), subtitle: Text('${row['detail']} · ${row['at']}')),
      ],
    );
  }
}
