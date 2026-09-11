import 'package:flutter/material.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../data/admin_repository.dart';

class CreateBusinessPage extends StatefulWidget {
  const CreateBusinessPage({super.key});

  @override
  State<CreateBusinessPage> createState() => _CreateBusinessPageState();
}

class _CreateBusinessPageState extends State<CreateBusinessPage> {
  final _businessName = TextEditingController();
  final _slug = TextEditingController();
  final _currency = TextEditingController(text: 'PKR');
  final _tax = TextEditingController(text: '0');
  final _primary = TextEditingController(text: '#1F6F4A');
  final _secondary = TextEditingController(text: '#F4EFE6');
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _branchName = TextEditingController(text: 'Main Branch');
  final _branchCode = TextEditingController(text: 'MAIN');
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();
  bool _seed = false;
  bool _busy = false;

  @override
  void dispose() {
    _businessName.dispose();
    _slug.dispose();
    _currency.dispose();
    _tax.dispose();
    _primary.dispose();
    _secondary.dispose();
    _address.dispose();
    _phone.dispose();
    _branchName.dispose();
    _branchCode.dispose();
    _adminName.dispose();
    _adminEmail.dispose();
    _adminPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await sl<AdminRepository>().createBusiness(
        CreateBusinessRequest(
          businessName: _businessName.text.trim(),
          slug: _slug.text.trim(),
          currencyCode: _currency.text.trim(),
          taxRate: _tax.text.trim(),
          primaryColor: _primary.text.trim(),
          secondaryColor: _secondary.text.trim(),
          address: _address.text.trim(),
          phone: _phone.text.trim(),
          branchName: _branchName.text.trim(),
          branchCode: _branchCode.text.trim(),
          adminName: _adminName.text.trim(),
          adminEmail: _adminEmail.text.trim(),
          adminPassword: _adminPassword.text,
          seedSampleCatalog: _seed,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business created. Give the admin their email and password to sign in.')),
      );
      _businessName.clear();
      _slug.clear();
      _adminName.clear();
      _adminEmail.clear();
      _adminPassword.clear();
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
      title: 'New business',
      subtitle: 'Creates the store, first branch, and a Business Admin login. That admin then adds cashiers and products.',
      child: ListView(
        children: [
          _section(context, 'Store', [
            TextField(controller: _businessName, decoration: const InputDecoration(labelText: 'Business name')),
            TextField(controller: _slug, decoration: const InputDecoration(labelText: 'Slug (optional, used as id)')),
            Row(
              children: [
                Expanded(child: TextField(controller: _currency, decoration: const InputDecoration(labelText: 'Currency'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _tax, decoration: const InputDecoration(labelText: 'Tax rate e.g. 0.05'))),
              ],
            ),
            Row(
              children: [
                Expanded(child: TextField(controller: _primary, decoration: const InputDecoration(labelText: 'Primary color'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _secondary, decoration: const InputDecoration(labelText: 'Secondary color'))),
              ],
            ),
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
          ]),
          _section(context, 'First branch', [
            TextField(controller: _branchName, decoration: const InputDecoration(labelText: 'Branch name')),
            TextField(controller: _branchCode, decoration: const InputDecoration(labelText: 'Branch code')),
          ]),
          _section(context, 'Business admin', [
            TextField(controller: _adminName, decoration: const InputDecoration(labelText: 'Admin name')),
            TextField(controller: _adminEmail, decoration: const InputDecoration(labelText: 'Admin email')),
            TextField(controller: _adminPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Temporary password')),
          ]),
          SwitchListTile(
            value: _seed,
            onChanged: _busy ? null : (value) => setState(() => _seed = value),
            title: const Text('Seed a sample ice-cream catalog'),
            subtitle: const Text('Optional. Leave off for an empty menu the admin will build.'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_busy ? 'Creating…' : 'Create business'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
