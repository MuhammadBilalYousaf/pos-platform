import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/password_field.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import '../../../auth/domain/entities/session.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/admin_repository.dart';

enum _SettingsTab { business, posTax, catalog, audit }

class SettingsEditorPage extends StatefulWidget {
  const SettingsEditorPage({super.key, required this.session});
  final Session session;

  @override
  State<SettingsEditorPage> createState() => _SettingsEditorPageState();
}

class _SettingsEditorPageState extends State<SettingsEditorPage> {
  _SettingsTab _tab = _SettingsTab.business;

  late final _name = TextEditingController(text: widget.session.business?.name ?? '');
  late final _currency = TextEditingController(text: widget.session.business?.currencyCode ?? 'PKR');
  late final _tax = TextEditingController(text: widget.session.business?.taxRate ?? '0');
  late final _primary = TextEditingController(text: widget.session.business?.primaryColor ?? '#1F6F4A');
  late final _secondary = TextEditingController(text: widget.session.business?.secondaryColor ?? '#F4EFE6');
  late final _address = TextEditingController(text: widget.session.business?.address ?? '');
  late final _phone = TextEditingController(text: widget.session.business?.phone ?? '');
  late final _tables = TextEditingController(
    text: (widget.session.business?.diningTables ?? const []).join(', '),
  );
  final _cancelPassword = TextEditingController();
  final _cancelPasswordConfirm = TextEditingController();
  late bool _requireOpenShift = widget.session.business?.requireOpenShift ?? false;
  late bool _diningTablesEnabled = widget.session.business?.diningTablesEnabled ?? false;
  bool _busy = false;
  bool _hasCancelPassword = false;

  @override
  void initState() {
    super.initState();
    _loadCancelPasswordState();
  }

  Future<void> _loadCancelPasswordState() async {
    try {
      final has = await sl<AdminRepository>().hasOrderCancellationPassword();
      if (mounted) setState(() => _hasCancelPassword = has);
    } catch (_) {}
  }

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _tax.dispose();
    _primary.dispose();
    _secondary.dispose();
    _address.dispose();
    _phone.dispose();
    _tables.dispose();
    _cancelPassword.dispose();
    _cancelPasswordConfirm.dispose();
    super.dispose();
  }

  Future<void> _saveCancelPassword() async {
    if (_cancelPassword.text.trim() != _cancelPasswordConfirm.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancellation passwords do not match.')));
      return;
    }
    setState(() => _busy = true);
    try {
      await sl<AdminRepository>().setOrderCancellationPassword(_cancelPassword.text);
      _cancelPassword.clear();
      _cancelPasswordConfirm.clear();
      await _loadCancelPasswordState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancellation password saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        requireOpenShift: _requireOpenShift,
        diningTablesEnabled: _diningTablesEnabled,
        diningTables: BusinessProfile.parseDiningTableLabels(_tables.text),
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

  bool get _showSave => _tab == _SettingsTab.business || _tab == _SettingsTab.posTax;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Settings',
      subtitle: 'Business profile, POS rules, catalog helpers, and audit.',
      actions: [
        if (_showSave)
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
                children: [
                  _SettingsNavItem(
                    label: 'Business',
                    selected: _tab == _SettingsTab.business,
                    onTap: () => setState(() => _tab = _SettingsTab.business),
                  ),
                  _SettingsNavItem(
                    label: 'POS & tax',
                    selected: _tab == _SettingsTab.posTax,
                    onTap: () => setState(() => _tab = _SettingsTab.posTax),
                  ),
                  _SettingsNavItem(
                    label: 'Catalog helpers',
                    selected: _tab == _SettingsTab.catalog,
                    onTap: () => setState(() => _tab = _SettingsTab.catalog),
                  ),
                  _SettingsNavItem(
                    label: 'Audit',
                    selected: _tab == _SettingsTab.audit,
                    onTap: () => setState(() => _tab = _SettingsTab.audit),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: AdminSurfaceCard(
              child: switch (_tab) {
                _SettingsTab.business => _buildBusinessTab(),
                _SettingsTab.posTax => _buildPosTaxTab(),
                _SettingsTab.catalog => _buildCatalogTab(),
                _SettingsTab.audit => _buildAuditTab(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessTab() {
    return ListView(
      children: [
        Text('Business', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'Store identity shown on the app and receipts. Receipt layout/printer is under Receipt in the sidebar.',
          style: TextStyle(color: kAdminMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: adminInputDecoration('Business name')),
        const SizedBox(height: 12),
        TextField(controller: _address, decoration: adminInputDecoration('Address')),
        const SizedBox(height: 12),
        TextField(controller: _phone, decoration: adminInputDecoration('Phone')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextField(controller: _primary, decoration: adminInputDecoration('Primary color'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _secondary, decoration: adminInputDecoration('Secondary color'))),
          ],
        ),
      ],
    );
  }

  Widget _buildPosTaxTab() {
    return ListView(
      children: [
        Text('POS & tax', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'Tax, currency, shift rules, tables, and cancellation password for the POS.',
          style: TextStyle(color: kAdminMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: TextField(controller: _currency, decoration: adminInputDecoration('Currency'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _tax, decoration: adminInputDecoration('Tax rate (%)'))),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Require open shift before sale'),
          subtitle: const Text('POS blocks payment until a shift is started for the branch.'),
          value: _requireOpenShift,
          onChanged: (value) => setState(() => _requireOpenShift = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable dining tables'),
          subtitle: const Text(
            'Optional. Turn off for takeaway-only. When on, list tables or still type a custom token.',
          ),
          value: _diningTablesEnabled,
          onChanged: (value) => setState(() => _diningTablesEnabled = value),
        ),
        if (_diningTablesEnabled) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _tables,
            maxLines: 3,
            decoration: adminInputDecoration(
              'Tables (optional) — e.g. 1, 2, 3, Patio A',
            ).copyWith(
              helperText: 'Leave empty for free-text table/token only. Comma or new line separated.',
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Order cancellation password',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _hasCancelPassword
              ? 'A cancellation password is configured. Enter a new one below to change it. Stored as a hash — never shown again.'
              : 'Staff must enter this password before cancelling or item-refunding an order.',
          style: const TextStyle(color: kAdminMuted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        PasswordField(
          controller: _cancelPassword,
          label: 'New cancellation password',
          decoration: adminInputDecoration('New cancellation password'),
          autofillHints: const [],
        ),
        const SizedBox(height: 12),
        PasswordField(
          controller: _cancelPasswordConfirm,
          label: 'Confirm cancellation password',
          decoration: adminInputDecoration('Confirm cancellation password'),
          autofillHints: const [],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            style: adminOutlinedButtonStyle,
            onPressed: _busy ? null : _saveCancelPassword,
            child: const Text('Save cancellation password'),
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogTab() {
    return ListView(
      children: [
        Text('Catalog helpers', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'Named discounts appear in POS when you tap a line or open Ticket details → Order discount. '
          'Pick Rs or %, then save. Units are used in inventory/recipes.',
          style: TextStyle(color: kAdminMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Text('Discounts', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const _NamedList(collection: 'discounts', extraLabel: 'Value'),
        const SizedBox(height: 20),
        Text('Units', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const _NamedList(collection: 'units', extraLabel: 'Code'),
      ],
    );
  }

  Widget _buildAuditTab() {
    return ListView(
      children: [
        Text('Audit', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'Recent admin activity for this business.',
          style: TextStyle(color: kAdminMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _AuditList(),
      ],
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? kAdminAccentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
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
          ),
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
    var isPercent = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(widget.collection == 'discounts' ? 'Add discount' : 'Add unit'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                  const SizedBox(height: 12),
                  if (widget.collection == 'discounts') ...[
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Rs')),
                        ButtonSegment(value: true, label: Text('%')),
                      ],
                      selected: {isPercent},
                      onSelectionChanged: (next) => setLocal(() => isPercent = next.first),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: extra,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: isPercent ? 'Percent' : 'Amount (Rs)',
                        suffixText: isPercent ? '%' : 'Rs',
                      ),
                    ),
                  ] else
                    TextField(controller: extra, decoration: InputDecoration(labelText: widget.extraLabel)),
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
    final extras = <String, dynamic>{
      if (widget.collection == 'discounts') ...{
        'amount': extra.text.trim(),
        'type': isPercent ? 'PERCENT' : 'AMOUNT',
      },
      if (widget.collection == 'units') 'code': extra.text.trim(),
    };
    await sl<AdminRepository>().saveNamed(
      collection: widget.collection,
      name: name.text.trim(),
      extra: extras,
    );
    name.dispose();
    extra.dispose();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _add, child: const Text('Add'))),
        if (_rows.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Nothing added yet.', style: TextStyle(color: kAdminMuted)),
          )
        else
          for (final row in _rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row['name'] ?? ''),
              subtitle: Text(row['subtitle'] ?? ''),
            ),
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    sl<AdminRepository>().listAudit().then((rows) {
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: kAdminAccent)),
      );
    }
    if (_rows.isEmpty) return const Text('No activity recorded yet.');
    return Column(
      children: [
        for (final row in _rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row['action'] ?? ''),
            subtitle: Text('${row['detail']} · ${row['at']}'),
          ),
      ],
    );
  }
}
