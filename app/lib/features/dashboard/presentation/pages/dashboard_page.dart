import 'package:flutter/material.dart';
import '../../data/dashboard_repository.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../admin/presentation/bloc/branch_context_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardSnapshot? _snapshot;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await sl<DashboardRepository>().today();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final snapshot = _snapshot!;
    final auth = context.watch<AuthBloc>().state;
    final name = auth is AuthAuthenticated ? auth.session.business?.name ?? 'Dashboard' : 'Dashboard';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: BlocListener<BranchContextCubit, BranchContextState>(
        listener: (_, __) {
          setState(() => _loading = true);
          _load();
        },
        child: ListView(
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: Theme.of(context).textTheme.headlineMedium)),
              IconButton(onPressed: () {
                setState(() => _loading = true);
                _load();
              }, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Today’s figures are for the signed-in business. Cashiers sell from POS; admins manage catalog, staff, and stock from the side menu.'),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _metric(context, 'Orders', snapshot.orderCount),
              _metric(context, 'Sales', snapshot.total),
              _metric(context, 'Average ticket', snapshot.averageTicket),
              _metric(context, 'Low stock items', snapshot.lowStockCount),
              _metric(context, 'Dine in', snapshot.dineInCount),
              _metric(context, 'Takeaway', snapshot.takeawayCount),
              _metric(context, 'Delivery', snapshot.deliveryCount),
            ],
          ),
          const SizedBox(height: 28),
          Text('Payment mix', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (snapshot.paymentMix.isEmpty)
            const Text('No payments yet today.')
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final row in snapshot.paymentMix)
                  Chip(label: Text('${row['label']} · ${row['total']}')),
              ],
            ),
          const SizedBox(height: 28),
          Text('Recent tickets', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (snapshot.recentOrders.isEmpty)
            const Text('No tickets yet today.')
          else
            for (final row in snapshot.recentOrders)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row['order_number'] ?? ''),
                subtitle: Text('${row['type']} · ${row['customer']}'),
                trailing: Text(row['total'] ?? ''),
              ),
        ],
        ),
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
              const SizedBox(height: 8),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
      ),
    );
  }
}
