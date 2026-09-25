import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import '../../../auth/domain/entities/session.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../printing/domain/printer_service.dart';
import '../../data/admin_repository.dart';

class ReceiptEditorPage extends StatefulWidget {
  const ReceiptEditorPage({super.key, required this.session});
  final Session session;

  @override
  State<ReceiptEditorPage> createState() => _ReceiptEditorPageState();
}

class _ReceiptEditorPageState extends State<ReceiptEditorPage> {
  late final TextEditingController _header;
  late final TextEditingController _footer;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late int _paperWidthMm;
  late bool _showAddress;
  late bool _showPhone;
  bool _busy = false;
  bool _printing = false;
  List<String> _printers = const [];
  String? _printer;

  @override
  void initState() {
    super.initState();
    final business = widget.session.business;
    _header = TextEditingController(text: business?.receiptHeader ?? business?.name ?? '');
    _footer = TextEditingController(text: business?.receiptFooter ?? 'Thank you');
    _address = TextEditingController(text: business?.address ?? '');
    _phone = TextEditingController(text: business?.phone ?? '');
    _paperWidthMm = business?.receiptPaperWidthMm ?? 80;
    _showAddress = business?.receiptShowAddress ?? true;
    _showPhone = business?.receiptShowPhone ?? true;
    for (final controller in [_header, _footer, _address, _phone]) {
      controller.addListener(() => setState(() {}));
    }
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    final service = sl<PrinterService>();
    final printers = await service.availablePrinters();
    if (!mounted) return;
    setState(() {
      _printers = printers;
      _printer = service.configuredPrinter;
    });
  }

  Future<void> _selectPrinter(String? name) async {
    await sl<PrinterService>().configurePrinter(name);
    if (!mounted) return;
    setState(() => _printer = name);
  }

  Future<void> _testPrint() async {
    setState(() => _printing = true);
    try {
      await sl<PrinterService>().printReceipt(_preview);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Test receipt sent to the printer.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  ReceiptData get _preview {
    final session = _session;
    return ReceiptData.sample(
      businessName: session.business?.name ?? 'Business',
      branchName: session.branch?.name ?? (session.accessibleBranches.isEmpty ? 'Main branch' : session.accessibleBranches.first.name),
      header: _header.text,
      footer: _footer.text,
      address: _address.text,
      phone: _phone.text,
      paperWidthMm: _paperWidthMm,
      showAddress: _showAddress,
      showPhone: _showPhone,
    );
  }

  Session get _session {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.session : widget.session;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await sl<AdminRepository>().saveReceipt(
        receiptHeader: _header.text.trim(),
        receiptFooter: _footer.text.trim(),
        paperWidthMm: _paperWidthMm,
        showAddress: _showAddress,
        showPhone: _showPhone,
        address: _address.text.trim(),
        phone: _phone.text.trim(),
      );
      if (!mounted) return;
      context.read<AuthBloc>().add(const AuthRefreshRequested());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt saved. New sales will use this layout.')),
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
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final form = AdminSurfaceCard(
      child: ListView(
        children: [
          Text(
            'This is what customers see after a sale.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kAdminMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _header,
            maxLines: 2,
            decoration: adminInputDecoration('Header (shown at top)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            maxLines: 2,
            decoration: adminInputDecoration('Address on receipt'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            decoration: adminInputDecoration('Phone on receipt'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _footer,
            maxLines: 3,
            decoration: adminInputDecoration('Footer message'),
          ),
          const SizedBox(height: 16),
          Text('Paper width', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 58, label: Text('58 mm')),
              ButtonSegment(value: 80, label: Text('80 mm')),
            ],
            selected: {_paperWidthMm <= 58 ? 58 : 80},
            onSelectionChanged: (value) => setState(() => _paperWidthMm = value.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show address'),
            value: _showAddress,
            onChanged: (value) => setState(() => _showAddress = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show phone'),
            value: _showPhone,
            onChanged: (value) => setState(() => _showPhone = value),
          ),
          const SizedBox(height: 8),
          Text('Thermal printer', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: adminInputDecoration('Windows printer'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _printers.contains(_printer) ? _printer : null,
                hint: const Text('Select installed printer'),
                items: [
                  for (final name in _printers) DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: _selectPrinter,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _printing || _printer == null ? null : _testPrint,
              child: Text(_printing ? 'Printing…' : 'Print test receipt'),
            ),
          ),
          if (_printers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Install the thermal printer in Windows, then reopen this page.'),
            ),
        ],
      ),
    );
    final preview = _ReceiptSlip(receipt: _preview);
    return PageFrame(
      title: 'Receipt Settings',
      subtitle: 'Configure the customer slip shown after each sale.',
      actions: [
        FilledButton(
          style: adminPrimaryButtonStyle,
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save Changes'),
        ),
      ],
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: form),
                const SizedBox(width: 28),
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(child: preview),
                ),
              ],
            )
          : ListView(
              children: [
                SizedBox(height: 480, child: form),
                const SizedBox(height: 20),
                preview,
              ],
            ),
    );
  }
}

class _ReceiptSlip extends StatelessWidget {
  const _ReceiptSlip({required this.receipt});
  final ReceiptData receipt;

  @override
  Widget build(BuildContext context) {
    final width = receipt.paperWidthMm <= 58 ? 280.0 : 360.0;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF7),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              receipt.paperWidthMm <= 58 ? '58 mm preview' : '80 mm preview',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 10),
            SelectableText(
              receipt.toPreviewText(),
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 13,
                height: 1.35,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
