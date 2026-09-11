import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../auth/domain/entities/session.dart';
import '../../../auth/domain/permissions.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../pos/presentation/pages/pos_page.dart';
import '../../../sync/presentation/bloc/sync_cubit.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../admin/presentation/pages/staff_page.dart';
import '../../../admin/presentation/pages/catalog_admin_page.dart';
import '../../../admin/presentation/pages/branches_page.dart';
import '../../../admin/presentation/pages/receipt_editor_page.dart';
import '../../../admin/presentation/pages/settings_editor_page.dart';
import '../../../admin/presentation/pages/customers_page.dart';
import '../../../admin/presentation/pages/inventory_hub_page.dart';
import '../../../admin/presentation/pages/profile_page.dart';
import '../../../admin/presentation/widgets/branch_switcher.dart';
import '../../../orders/presentation/pages/orders_page.dart';
import 'dashboard_page.dart';
import 'reports_page.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      return const SizedBox.shrink();
    }
    final session = auth.session;
    final user = session.user;
    final destinations = <WorkbenchDestination>[
      if (!user.isCashier)
        WorkbenchDestination(
          icon: Icons.dashboard_outlined,
          label: 'Home',
          builder: (_) => const DashboardPage(),
        ),
      if (user.canRunPos)
        WorkbenchDestination(
          icon: Icons.point_of_sale,
          label: 'POS',
          builder: (_) => const PosShortcuts(child: PosPage()),
        ),
      if (user.can(PosPermissions.ordersRead))
        WorkbenchDestination(
          icon: Icons.receipt_long_outlined,
          label: 'Orders',
          builder: (_) => const OrdersPage(),
        ),
      if (user.canManageCatalog || user.can(PosPermissions.catalogWrite))
        WorkbenchDestination(
          icon: Icons.inventory_2_outlined,
          label: 'Products',
          builder: (_) => const CatalogAdminPage(),
        ),
      if (user.canManageInventory || user.can(PosPermissions.inventoryView) || user.can(PosPermissions.inventoryRead))
        WorkbenchDestination(
          icon: Icons.warehouse_outlined,
          label: 'Inventory',
          builder: (_) => const InventoryHubPage(),
        ),
      if (!user.isCashier && user.canRunPos)
        WorkbenchDestination(
          icon: Icons.people_outline,
          label: 'Customers',
          builder: (_) => const CustomersPage(),
        ),
      if (user.canViewReports)
        WorkbenchDestination(
          icon: Icons.bar_chart,
          label: 'Reports',
          builder: (_) => const ReportsPage(),
        ),
      if (user.canManageStaff)
        WorkbenchDestination(
          icon: Icons.group_outlined,
          label: 'Staff',
          builder: (_) => const StaffPage(),
        ),
      if (user.canManageBranches)
        WorkbenchDestination(
          icon: Icons.store_mall_directory_outlined,
          label: 'Branches',
          builder: (_) => const BranchesPage(),
        ),
      if (user.canManageSettings)
        WorkbenchDestination(
          icon: Icons.receipt_outlined,
          label: 'Receipt',
          builder: (_) => ReceiptEditorPage(session: session),
        ),
      if (user.canManageSettings)
        WorkbenchDestination(
          icon: Icons.settings_outlined,
          label: 'Settings',
          builder: (_) => SettingsEditorPage(session: session),
        ),
      if (user.isCashier)
        WorkbenchDestination(
          icon: Icons.person_outline,
          label: 'Profile',
          builder: (_) => ProfilePage(session: session),
        ),
    ];
    final sync = context.watch<SyncCubit>().state;
    final posIndex = destinations.indexWhere((item) => item.label == 'POS');
    return WorkbenchShell(
      title: SessionBanner(session: session),
      initialIndex: user.isCashier && posIndex >= 0 ? posIndex : 0,
      actions: [
        const BranchSwitcher(),
        if (!sync.online)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: Text('Offline')),
          ),
        if (sync.pendingCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: Text('Sync ${sync.pendingCount}')),
          ),
        IconButton(
          onPressed: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
          icon: const Icon(Icons.logout),
        ),
      ],
      destinations: destinations,
    );
  }
}

class SessionBanner extends StatelessWidget {
  const SessionBanner({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final business = session.business?.name ?? 'POS';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(business, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          '${session.user.name} · ${PosRole.label(session.user.role)}',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
