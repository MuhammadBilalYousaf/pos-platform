import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../auth/domain/entities/session.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/admin_repository.dart';
import 'create_business_page.dart';
import 'platform_business_page.dart';

class PlatformShell extends StatelessWidget {
  const PlatformShell({super.key});

  @override
  Widget build(BuildContext context) {
    final session = (context.watch<AuthBloc>().state as AuthAuthenticated).session;
    return WorkbenchShell(
      title: Text('Super Admin · ${session.user.name}'),
      actions: [
        IconButton(
          onPressed: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
          icon: const Icon(Icons.logout),
        ),
      ],
      destinations: [
        WorkbenchDestination(
          icon: Icons.dashboard_outlined,
          label: 'Dashboard',
          builder: (_) => const _PlatformDashboard(),
        ),
        WorkbenchDestination(
          icon: Icons.storefront_outlined,
          label: 'Businesses',
          builder: (_) => const _BusinessesPage(),
        ),
        WorkbenchDestination(
          icon: Icons.add_business_outlined,
          label: 'New business',
          builder: (_) => const CreateBusinessPage(),
        ),
        WorkbenchDestination(
          icon: Icons.policy_outlined,
          label: 'Audit',
          builder: (_) => const _PlatformAuditPage(),
        ),
      ],
    );
  }
}

class _PlatformDashboard extends StatefulWidget {
  const _PlatformDashboard();
  @override
  State<_PlatformDashboard> createState() => _PlatformDashboardState();
}

class _PlatformDashboardState extends State<_PlatformDashboard> {
  int _count = 0;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    sl<AdminRepository>().listBusinesses().then((rows) {
      if (!mounted) return;
      setState(() {
        _count = rows.length;
        _active = rows.where((item) => item.isActive).length;
      });
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Super Admin',
      subtitle: 'Create businesses and their admins. You do not operate a store POS from this account.',
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _metric(context, 'Businesses', '$_count'),
          _metric(context, 'Active', '$_active'),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessesPage extends StatefulWidget {
  const _BusinessesPage();

  @override
  State<_BusinessesPage> createState() => _BusinessesPageState();
}

class _BusinessesPageState extends State<_BusinessesPage> {
  List<BusinessProfile> _rows = const [];
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
      final rows = await sl<AdminRepository>().listBusinesses();
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  @override
  Widget build(BuildContext context) {
    final visible = _rows.where((row) {
      if (_query.isEmpty) return true;
      return '${row.name} ${row.status} ${row.currencyCode}'.toLowerCase().contains(_query.toLowerCase());
    }).toList();
    return PageFrame(
      title: 'Businesses',
      subtitle: 'Open a store to view branches, staff, and status. Business admins run day-to-day POS.',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search businesses'),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: visible.isEmpty
                          ? const Center(child: Text('No businesses yet. Open New business to add the first store.'))
                          : ListView.separated(
                              itemCount: visible.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final business = visible[index];
                                return Card(
                                  child: ListTile(
                                    leading: const CircleAvatar(child: Icon(Icons.store)),
                                    title: Text(business.name),
                                    subtitle: Text('${business.currencyCode} · ${business.status}'),
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => PlatformBusinessPage(business: business),
                                        ),
                                      );
                                      await _load();
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _PlatformAuditPage extends StatefulWidget {
  const _PlatformAuditPage();
  @override
  State<_PlatformAuditPage> createState() => _PlatformAuditPageState();
}

class _PlatformAuditPageState extends State<_PlatformAuditPage> {
  List<Map<String, String>> _rows = const [];

  @override
  void initState() {
    super.initState();
    sl<AdminRepository>().listAudit(platform: true).then((rows) {
      if (mounted) setState(() => _rows = rows);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Audit',
      subtitle: 'Platform-level activity. Business POS activity stays inside each store.',
      child: ListView(
        children: [
          for (final row in _rows)
            ListTile(title: Text(row['action'] ?? ''), subtitle: Text('${row['detail']} · ${row['at']}')),
        ],
      ),
    );
  }
}
