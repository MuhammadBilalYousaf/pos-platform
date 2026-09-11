import 'package:flutter/material.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import 'inventory_admin_page.dart';
import 'inventory_ops_page.dart';
import 'recipes_page.dart';

enum InventoryHubMode { full, purchasesOnly, suppliersOnly }

class InventoryHubPage extends StatelessWidget {
  const InventoryHubPage({
    super.key,
    this.initialTab = 0,
    this.mode = InventoryHubMode.full,
  });

  final int initialTab;
  final InventoryHubMode mode;

  InventoryHubMode _resolvedMode() {
    if (mode != InventoryHubMode.full) return mode;
    if (initialTab == 2) return InventoryHubMode.purchasesOnly;
    if (initialTab == 3) return InventoryHubMode.suppliersOnly;
    return InventoryHubMode.full;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolvedMode();
    switch (resolved) {
      case InventoryHubMode.purchasesOnly:
        return const _PurchasesStandalonePage();
      case InventoryHubMode.suppliersOnly:
        return const _SuppliersStandalonePage();
      case InventoryHubMode.full:
        return DefaultTabController(
          length: 6,
          initialIndex: initialTab.clamp(0, 5),
          child: PageFrame(
            title: 'Inventory',
            subtitle: 'Track and manage your stock, recipes, purchases, and waste.',
            actions: [
              FilledButton.icon(
                style: adminPrimaryButtonStyle,
                onPressed: () {},
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Stock'),
              ),
            ],
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  labelColor: kAdminAccent,
                  unselectedLabelColor: kAdminMuted,
                  indicatorColor: kAdminAccent,
                  tabs: const [
                    Tab(text: 'Current Stock'),
                    Tab(text: 'Recipes'),
                    Tab(text: 'Purchases'),
                    Tab(text: 'Suppliers'),
                    Tab(text: 'Transfers'),
                    Tab(text: 'Waste'),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: AdminSurfaceCard(
                    padding: EdgeInsets.zero,
                    child: TabBarView(
                      children: [
                        InventoryAdminPage(embedded: true),
                        RecipesTab(),
                        const PurchasesTab(),
                        const SuppliersTab(),
                        TransfersTab(),
                        WasteTab(),
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
}

class _PurchasesStandalonePage extends StatefulWidget {
  const _PurchasesStandalonePage();

  @override
  State<_PurchasesStandalonePage> createState() => _PurchasesStandalonePageState();
}

class _PurchasesStandalonePageState extends State<_PurchasesStandalonePage> {
  VoidCallback? _create;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Purchases',
      subtitle: 'Manage supplier purchases and stock receipts.',
      actions: [
        FilledButton.icon(
          style: adminPrimaryButtonStyle,
          onPressed: _create,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Purchase'),
        ),
      ],
      child: AdminSurfaceCard(
        padding: EdgeInsets.zero,
        child: PurchasesTab(
          standalone: true,
          onRegisterCreate: (fn) => setState(() => _create = fn),
        ),
      ),
    );
  }
}

class _SuppliersStandalonePage extends StatefulWidget {
  const _SuppliersStandalonePage();

  @override
  State<_SuppliersStandalonePage> createState() => _SuppliersStandalonePageState();
}

class _SuppliersStandalonePageState extends State<_SuppliersStandalonePage> {
  VoidCallback? _create;
  String _supplierQuery = '';

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Suppliers',
      subtitle: 'Manage your suppliers and vendor contacts.',
      actions: [
        FilledButton.icon(
          style: adminPrimaryButtonStyle,
          onPressed: _create,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Supplier'),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              decoration: adminInputDecoration('Search suppliers', icon: Icons.search),
              onChanged: (value) => setState(() => _supplierQuery = value),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AdminSurfaceCard(
              padding: EdgeInsets.zero,
              child: SuppliersTab(
                standalone: true,
                searchQuery: _supplierQuery,
                onRegisterCreate: (fn) => setState(() => _create = fn),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
