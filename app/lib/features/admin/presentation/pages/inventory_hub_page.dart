import 'package:flutter/material.dart';
import '../../../../core/widgets/workbench.dart';
import 'inventory_admin_page.dart';
import 'inventory_ops_page.dart';
import 'recipes_page.dart';

class InventoryHubPage extends StatelessWidget {
  const InventoryHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 6,
      child: PageFrame(
        title: 'Inventory',
        subtitle: 'Stock, recipes, purchases, transfers, and waste follow the branch selector in the top bar.',
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'On hand'),
                Tab(text: 'Recipes'),
                Tab(text: 'Purchases'),
                Tab(text: 'Suppliers'),
                Tab(text: 'Transfers'),
                Tab(text: 'Waste'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  InventoryAdminPage(embedded: true),
                  RecipesTab(),
                  PurchasesTab(),
                  SuppliersTab(),
                  TransfersTab(),
                  WasteTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
