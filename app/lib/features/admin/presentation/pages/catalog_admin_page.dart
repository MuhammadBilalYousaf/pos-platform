import 'package:flutter/material.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../../core/widgets/admin_ui_kit.dart';
import '../../../products/domain/entities/catalog.dart';
import '../../../products/presentation/bloc/catalog_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/admin_repository.dart';

class CatalogAdminPage extends StatelessWidget {
  const CatalogAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Products',
      subtitle: 'Manage your menu items, categories, variants, and add-ons.',
      actions: [
        OutlinedButton(
          style: adminOutlinedButtonStyle,
          onPressed: () => _bulkPrice(context),
          child: const Text('Bulk price'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          style: adminOutlinedButtonStyle,
          onPressed: () => _addCategory(context),
          child: const Text('Add category'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: adminPrimaryButtonStyle,
          onPressed: () => _addProduct(context),
          child: const Text('+ Add Product'),
        ),
      ],
      child: BlocBuilder<CatalogCubit, CatalogState>(
        builder: (context, state) {
          if (state.status == CatalogStatus.loading || state.status == CatalogStatus.initial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == CatalogStatus.failure) {
            return Center(child: Text(state.message ?? 'Unable to load catalog.'));
          }
          final catalog = state.catalog;
          if (catalog == null || (catalog.categories.isEmpty && catalog.products.isEmpty)) {
            return const Center(child: Text('No products yet. Add a category, then a product.'));
          }
          return AdminSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const AdminTableHeader(columns: ['Product', 'Category', 'Price', 'Status', '']),
                Expanded(
                  child: ListView.separated(
                    itemCount: catalog.products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: kAdminBorder),
                    itemBuilder: (context, index) {
                      final product = catalog.products[index];
                      String? categoryName;
                      for (final c in catalog.categories) {
                        if (c.id == product.categoryId) {
                          categoryName = c.name;
                          break;
                        }
                      }
                      return InkWell(
                        onTap: () => _addProduct(context, product: product),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: kAdminAccentSoft,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.icecream_outlined, color: kAdminAccent, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(child: Text(categoryName ?? '—')),
                              Expanded(child: Text('Rs. ${product.defaultOrFirstPrice}')),
                              Expanded(
                                child: AdminStatusPill(
                                  label: product.active ? 'Active' : 'Inactive',
                                  tone: product.active ? AdminStatusTone.success : AdminStatusTone.neutral,
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20),
                                    onPressed: () async {
                                      await sl<AdminRepository>().deleteProduct(product.id);
                                      if (context.mounted) context.read<CatalogCubit>().load(forceRefresh: true);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addCategory(BuildContext context) async {
    final catalog = context.read<CatalogCubit>().state.catalog;
    final name = TextEditingController();
    String? parentId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: parentId,
                decoration: const InputDecoration(labelText: 'Parent category'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('None (top level)')),
                  for (final category in (catalog?.categories ?? const <CatalogCategory>[]).where((item) => !item.isSubcategory))
                    DropdownMenuItem<String?>(value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) => setLocal(() => parentId = value),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await sl<AdminRepository>().saveCategory(
      CatalogCategory(id: '', name: name.text.trim(), sortOrder: 0, parentId: parentId),
    );
    if (context.mounted) context.read<CatalogCubit>().load(forceRefresh: true);
  }

  Future<void> _bulkPrice(BuildContext context) async {
    final catalog = context.read<CatalogCubit>().state.catalog;
    if (catalog == null || catalog.products.isEmpty) return;
    final price = TextEditingController();
    String? categoryId;
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final pool = catalog.products.where((product) {
            if (categoryId == null || categoryId!.isEmpty) return true;
            if (product.categoryId == categoryId) return true;
            return catalog.categories.any((item) => item.id == product.categoryId && item.parentId == categoryId);
          }).toList();
          return AlertDialog(
            title: const Text('Bulk price'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(labelText: 'Category or sub-category'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All products')),
                      for (final category in catalog.categories)
                        DropdownMenuItem<String?>(
                          value: category.id,
                          child: Text(category.isSubcategory ? '— ${category.name}' : category.name),
                        ),
                    ],
                    onChanged: (value) => setLocal(() {
                      categoryId = value;
                      selected
                        ..clear()
                        ..addAll(pool.where((product) {
                          if (value == null) return false;
                          if (product.categoryId == value) return true;
                          return catalog.categories.any((item) => item.id == product.categoryId && item.parentId == value);
                        }).map((product) => product.id));
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: price, decoration: const InputDecoration(labelText: 'New price')),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${selected.length} products will be updated. Every size on those products gets this price.'),
                  ),
                  SizedBox(
                    height: 180,
                    child: ListView(
                      children: [
                        for (final product in pool)
                          CheckboxListTile(
                            dense: true,
                            value: selected.contains(product.id),
                            title: Text(product.name),
                            onChanged: (value) => setLocal(() {
                              if (value == true) {
                                selected.add(product.id);
                              } else {
                                selected.remove(product.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    final count = await sl<AdminRepository>().applyBulkPrice(productIds: selected.toList(), price: price.text.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Updated $count products.')));
      context.read<CatalogCubit>().load(forceRefresh: true);
    }
  }

  Future<void> _addProduct(BuildContext context, {CatalogProduct? product}) async {
    final catalog = context.read<CatalogCubit>().state.catalog;
    if (catalog == null || catalog.categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a category first.')));
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ProductEditorDialog(catalog: catalog, product: product),
    );
    if (saved == true && context.mounted) {
      context.read<CatalogCubit>().load(forceRefresh: true);
    }
  }
}

extension on CatalogProduct {
  String get defaultOrFirstPrice {
    if (variants.isEmpty) return '0';
    return defaultVariant.price;
  }
}

class _DraftRow {
  _DraftRow({required this.name, required this.price, this.id = '', this.isDefault = false, String multiplier = '1'})
      : multiplier = TextEditingController(text: multiplier);
  final String id;
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController multiplier;
  bool isDefault;
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({required this.catalog, this.product});
  final PosCatalog catalog;
  final CatalogProduct? product;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late String _categoryId;
  late String _type;
  late bool _active;
  late List<_DraftRow> _variants;
  late List<_DraftRow> _options;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _sku = TextEditingController(text: product?.sku ?? '');
    _categoryId = product?.categoryId ?? widget.catalog.categories.first.id;
    _type = product?.productType ?? 'SIMPLE';
    _active = product?.active ?? true;
    _variants = [
      if (product != null && product.variants.isNotEmpty)
        for (final variant in product.variants)
          _DraftRow(
            id: variant.id,
            name: TextEditingController(text: variant.name),
            price: TextEditingController(text: variant.price),
            isDefault: variant.isDefault,
            multiplier: variant.recipeMultiplier,
          )
      else
        _DraftRow(name: TextEditingController(text: 'Regular'), price: TextEditingController(text: '0'), isDefault: true),
    ];
    _options = [
      if (product != null)
        for (final option in product.options)
          _DraftRow(
            id: option.id,
            name: TextEditingController(text: option.name),
            price: TextEditingController(text: option.extraPrice),
          ),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    for (final row in [..._variants, ..._options]) {
      row.name.dispose();
      row.price.dispose();
      row.multiplier.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Product' : 'Edit product'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(controller: _sku, decoration: const InputDecoration(labelText: 'SKU')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final category in widget.catalog.categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.isSubcategory ? '${category.name} (sub)' : category.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _categoryId = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'SIMPLE', child: Text('Simple')),
                  DropdownMenuItem(value: 'RECIPE', child: Text('Recipe / made to order')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active on POS'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('Variants', style: Theme.of(context).textTheme.titleSmall)),
                  TextButton(
                    onPressed: () => setState(() {
                      _variants.add(_DraftRow(name: TextEditingController(), price: TextEditingController(text: '0')));
                    }),
                    child: const Text('Add size'),
                  ),
                ],
              ),
              for (var index = 0; index < _variants.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(controller: _variants[index].name, decoration: const InputDecoration(labelText: 'Size')),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: TextField(controller: _variants[index].price, decoration: const InputDecoration(labelText: 'Price')),
                      ),
                      Checkbox(
                        value: _variants[index].isDefault,
                        onChanged: (value) {
                          setState(() {
                            for (final row in _variants) {
                              row.isDefault = false;
                            }
                            _variants[index].isDefault = value == true;
                          });
                        },
                      ),
                      if (_variants.length > 1)
                        IconButton(
                          onPressed: () => setState(() => _variants.removeAt(index)),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(child: Text('Add-ons', style: Theme.of(context).textTheme.titleSmall)),
                  TextButton(
                    onPressed: () => setState(() {
                      _options.add(_DraftRow(name: TextEditingController(), price: TextEditingController(text: '0')));
                    }),
                    child: const Text('Add option'),
                  ),
                ],
              ),
              for (var index = 0; index < _options.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(controller: _options[index].name, decoration: const InputDecoration(labelText: 'Add-on')),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: TextField(controller: _options[index].price, decoration: const InputDecoration(labelText: 'Extra')),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _options.removeAt(index)),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final variants = [
              for (final row in _variants)
                if (row.name.text.trim().isNotEmpty)
                  ProductVariant(
                    id: row.id,
                    name: row.name.text.trim(),
                    price: row.price.text.trim().isEmpty ? '0' : row.price.text.trim(),
                    isDefault: row.isDefault,
                    recipeMultiplier: row.multiplier.text.trim().isEmpty ? '1' : row.multiplier.text.trim(),
                  ),
            ];
            await sl<AdminRepository>().saveProduct(
              id: widget.product?.id,
              name: _name.text.trim(),
              sku: _sku.text.trim(),
              categoryId: _categoryId,
              price: variants.isEmpty ? '0' : variants.first.price,
              productType: _type,
              active: _active,
              variants: variants,
              options: [
                for (final row in _options)
                  if (row.name.text.trim().isNotEmpty)
                    ProductOption(
                      id: row.id,
                      name: row.name.text.trim(),
                      extraPrice: row.price.text.trim().isEmpty ? '0' : row.price.text.trim(),
                    ),
              ],
            );
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
