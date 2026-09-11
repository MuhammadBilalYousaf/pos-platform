import 'package:flutter/material.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/widgets/workbench.dart';
import '../../../products/domain/entities/catalog.dart';
import '../../../products/presentation/bloc/catalog_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/admin_repository.dart';

class CatalogAdminPage extends StatelessWidget {
  const CatalogAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Catalog',
      subtitle: 'Categories, variants, and add-ons belong to this business. Inactive items stay off the POS grid.',
      actions: [
        OutlinedButton(onPressed: () => _addCategory(context), child: const Text('Add category')),
        const SizedBox(width: 8),
        FilledButton(onPressed: () => _addProduct(context), child: const Text('Add product')),
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
          return ListView(
            children: [
              Text('Categories', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in catalog.categories)
                    InputChip(
                      label: Text(category.name),
                      onDeleted: () async {
                        await sl<AdminRepository>().deleteCategory(category.id);
                        if (context.mounted) context.read<CatalogCubit>().load(forceRefresh: true);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Products', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final product in catalog.products)
                Card(
                  child: ListTile(
                    title: Text(product.name),
                    subtitle: Text(
                      [
                        product.sku ?? product.id,
                        product.defaultOrFirstPrice,
                        product.productType,
                        if (!product.active) 'inactive',
                        if (product.variants.length > 1) '${product.variants.length} variants',
                        if (product.options.isNotEmpty) '${product.options.length} add-ons',
                      ].join(' · '),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await sl<AdminRepository>().deleteProduct(product.id);
                        if (context.mounted) context.read<CatalogCubit>().load(forceRefresh: true);
                      },
                    ),
                    onTap: () => _addProduct(context, product: product),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addCategory(BuildContext context) async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Category'),
        content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await sl<AdminRepository>().saveCategory(CatalogCategory(id: '', name: name.text.trim(), sortOrder: 0));
    if (context.mounted) context.read<CatalogCubit>().load(forceRefresh: true);
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
  _DraftRow({required this.name, required this.price, this.id = '', this.isDefault = false});
  final String id;
  final TextEditingController name;
  final TextEditingController price;
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
                    DropdownMenuItem(value: category.id, child: Text(category.name)),
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
                        width: 110,
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
