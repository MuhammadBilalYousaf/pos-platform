import 'package:flutter/material.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../auth/domain/entities/session.dart';
import '../../../auth/domain/permissions.dart';
import '../../data/admin_repository.dart';

class PlatformBusinessPage extends StatefulWidget {
  const PlatformBusinessPage({super.key, required this.business});
  final BusinessProfile business;

  @override
  State<PlatformBusinessPage> createState() => _PlatformBusinessPageState();
}

class _PlatformBusinessPageState extends State<PlatformBusinessPage> {
  late BusinessProfile _business;
  List<BranchProfile> _branches = const [];
  List<StaffMember> _staff = const [];

  @override
  void initState() {
    super.initState();
    _business = widget.business;
    _load();
  }

  Future<void> _load() async {
    final branches = await sl<AdminRepository>().listBranches(businessId: _business.id);
    final staff = await sl<AdminRepository>().listStaff(businessId: _business.id);
    if (!mounted) return;
    setState(() {
      _branches = branches;
      _staff = staff;
    });
  }

  Future<void> _status(String status) async {
    await sl<AdminRepository>().setBusinessStatus(businessId: _business.id, status: status);
    setState(() {
      _business = BusinessProfile(
        id: _business.id,
        name: _business.name,
        primaryColor: _business.primaryColor,
        secondaryColor: _business.secondaryColor,
        currencyCode: _business.currencyCode,
        taxRate: _business.taxRate,
        address: _business.address,
        phone: _business.phone,
        receiptHeader: _business.receiptHeader,
        receiptFooter: _business.receiptFooter,
        status: status,
      );
    });
  }

  Future<void> _edit() async {
    final name = TextEditingController(text: _business.name);
    final phone = TextEditingController(text: _business.phone ?? '');
    final address = TextEditingController(text: _business.address ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit business'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 12),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    await sl<AdminRepository>().saveBusinessProfile(
      CreateBusinessRequest(
        businessName: name.text.trim(),
        slug: _business.id,
        currencyCode: _business.currencyCode,
        taxRate: _business.taxRate,
        primaryColor: _business.primaryColor,
        secondaryColor: _business.secondaryColor,
        address: address.text.trim(),
        phone: phone.text.trim(),
        branchName: 'n/a',
        branchCode: 'n/a',
        adminName: 'n/a',
        adminEmail: 'n/a',
        adminPassword: 'n/a',
      ),
      businessId: _business.id,
    );
    setState(() {
      _business = BusinessProfile(
        id: _business.id,
        name: name.text.trim(),
        primaryColor: _business.primaryColor,
        secondaryColor: _business.secondaryColor,
        currencyCode: _business.currencyCode,
        taxRate: _business.taxRate,
        address: address.text.trim(),
        phone: phone.text.trim(),
        receiptHeader: _business.receiptHeader,
        receiptFooter: _business.receiptFooter,
        status: _business.status,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_business.name)),
      body: PageFrame(
        title: _business.name,
        subtitle: '${_business.currencyCode} · ${_business.status}',
        actions: [
          TextButton(onPressed: _edit, child: const Text('Edit')),
          if (_business.status != 'active') TextButton(onPressed: () => _status('active'), child: const Text('Activate')),
          if (_business.isActive) TextButton(onPressed: () => _status('inactive'), child: const Text('Deactivate')),
          if (_business.isActive) TextButton(onPressed: () => _status('suspended'), child: const Text('Suspend')),
        ],
        child: ListView(
          children: [
            Text('Branches', style: Theme.of(context).textTheme.titleMedium),
            for (final row in _branches)
              ListTile(title: Text(row.name), subtitle: Text('${row.code}${row.active ? '' : ' · inactive'}')),
            const SizedBox(height: 16),
            Text('Staff', style: Theme.of(context).textTheme.titleMedium),
            for (final row in _staff)
              ListTile(title: Text(row.name), subtitle: Text('${row.email} · ${PosRole.label(row.role)}')),
          ],
        ),
      ),
    );
  }
}
