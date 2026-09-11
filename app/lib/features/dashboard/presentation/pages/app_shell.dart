import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import '../../../admin/presentation/bloc/branch_context_cubit.dart';
import '../../../admin/presentation/widgets/branch_switcher.dart';
import '../../../orders/presentation/pages/orders_page.dart';
import '../widgets/business_shell.dart';
import 'dashboard_page.dart';
import 'reports_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = 0;
  }

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
      if (user.canManageInventory || user.can(PosPermissions.inventoryView))
        WorkbenchDestination(
          icon: Icons.shopping_cart_outlined,
          label: 'Purchases',
          builder: (_) => const InventoryHubPage(initialTab: 2),
        ),
      if (user.canManageInventory || user.can(PosPermissions.inventoryView))
        WorkbenchDestination(
          icon: Icons.local_shipping_outlined,
          label: 'Suppliers',
          builder: (_) => const InventoryHubPage(initialTab: 3),
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
    final initial = user.isCashier && posIndex >= 0 ? posIndex : 0;
    if (_index >= destinations.length) {
      _index = initial;
    }

    return BusinessWorkbenchShell(
      session: session,
      destinations: destinations,
      initialIndex: initial,
      selectedIndex: _index,
      onIndexChanged: (value) => setState(() => _index = value),
      onNewOrder: posIndex >= 0 ? () => setState(() => _index = posIndex) : null,
      onLogout: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
      headerActions: [
        const _HeaderBranchSwitcher(),
        if (!sync.online)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text('Offline', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
            ),
          ),
        if (sync.pendingCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text('Sync ${sync.pendingCount}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => context.read<AuthBloc>().add(const AuthLogoutRequested()),
          icon: const Icon(Icons.logout_rounded, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}

class _HeaderBranchSwitcher extends StatelessWidget {
  const _HeaderBranchSwitcher();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BranchContextCubit, BranchContextState>(
      builder: (context, state) {
        if (!state.showSwitcher) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const BranchSwitcher(),
        );
      },
    );
  }
}
