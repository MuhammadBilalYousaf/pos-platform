import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../products/domain/entities/catalog.dart';
import '../../../products/presentation/bloc/catalog_cubit.dart';
import '../../data/admin_repository.dart';

class RecipesTab extends StatefulWidget {
  const RecipesTab({super.key});

  @override
  State<RecipesTab> createState() => _RecipesTabState();
}

class _RecipesTabState extends State<RecipesTab> {
  List<ProductRecipe> _recipes = const [];
  List<IngredientOption> _ingredients = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final catalog = context.read<CatalogCubit>();
    if (catalog.state.catalog == null) {
      catalog.load();
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final recipes = await sl<AdminRepository>().listRecipes();
      final ingredients = await sl<AdminRepository>().listIngredients();
      if (!mounted) return;
      setState(() {
        _recipes = recipes;
        _ingredients = ingredients;
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

  String _ingredientName(String id) {
    for (final item in _ingredients) {
      if (item.id == id) return item.name;
    }
    return id;
  }

  Future<void> _produce() async {
    final mixtures = _ingredients.where((item) => item.kind == 'MIXTURE').toList();
    final parts = _ingredients.where((item) => item.kind != 'MIXTURE').toList();
    if (mixtures.isEmpty || parts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a mixture stock item and the raw ingredients it is made from.')),
      );
      return;
    }
    var mixtureId = mixtures.first.id;
    final yieldQty = TextEditingController(text: '1');
    final componentQty = TextEditingController(text: '1');
    var componentId = parts.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Prepare mixture'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Raw ingredients are deducted. The mixture stock increases. Selling a product that uses the mixture does not deduct the raw ingredients again.'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mixtureId,
                decoration: const InputDecoration(labelText: 'Mixture'),
                items: [for (final item in mixtures) DropdownMenuItem(value: item.id, child: Text(item.name))],
                onChanged: (value) {
                  if (value != null) setLocal(() => mixtureId = value);
                },
              ),
              TextField(controller: yieldQty, decoration: const InputDecoration(labelText: 'Yield quantity')),
              DropdownButtonFormField<String>(
                initialValue: componentId,
                decoration: const InputDecoration(labelText: 'Ingredient used'),
                items: [for (final item in parts) DropdownMenuItem(value: item.id, child: Text('${item.name} (${item.unit})'))],
                onChanged: (value) {
                  if (value != null) setLocal(() => componentId = value);
                },
              ),
              TextField(controller: componentQty, decoration: const InputDecoration(labelText: 'Ingredient quantity')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Produce')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final mixture = mixtures.firstWhere((item) => item.id == mixtureId);
    final component = parts.firstWhere((item) => item.id == componentId);
    await sl<AdminRepository>().produceMixture(
      mixtureId: mixture.id,
      yieldQuantity: yieldQty.text.trim(),
      yieldUnit: mixture.unit,
      components: [
        RecipeLine(ingredientId: component.id, quantity: componentQty.text.trim(), unit: component.unit),
      ],
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mixture stock updated.')));
    }
  }

  Future<void> _edit({ProductRecipe? recipe}) async {
    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add ingredients under On hand first, then build the recipe.')),
      );
      return;
    }
    final catalog = context.read<CatalogCubit>().state.catalog;
    final products = catalog?.products.where((item) => item.active && item.variants.isNotEmpty).toList() ?? const <CatalogProduct>[];
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a POS product first. Recipes are for items sold on POS.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _RecipeEditorDialog(
        products: products,
        ingredients: _ingredients,
        recipe: recipe,
        onSave: (product, lines) async {
          await sl<AdminRepository>().saveRecipe(
            productId: product.id,
            productName: product.name,
            items: lines,
          );
          await _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _produce,
                icon: const Icon(Icons.blender_outlined),
                label: const Text('Prepare mixture'),
              ),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Recipe'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _recipes.isEmpty
              ? const Center(child: Text('No recipes yet. Choose a POS product, then pick the ingredients it consumes.'))
              : ListView(
                  children: [
                    for (final recipe in _recipes)
                      Card(
                        child: ListTile(
                          title: Text(recipe.name),
                          subtitle: Text(
                            recipe.items.map((item) => '${_ingredientName(item.ingredientId)} × ${item.quantity}').join(' · '),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await sl<AdminRepository>().deleteRecipe(recipe.id);
                              await _load();
                            },
                          ),
                          onTap: () => _edit(recipe: recipe),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _LineDraft {
  _LineDraft({
    this.ingredientId,
    this.optionId,
    Map<String, String> quantities = const {},
    String fallback = '1',
    List<ProductVariant> variants = const [],
  }) {
    final ids = variants.map((item) => item.id).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) {
      amountFor[''] = TextEditingController(text: quantities[''] ?? fallback);
      return;
    }
    for (final id in ids) {
      amountFor[id] = TextEditingController(text: quantities[id] ?? fallback);
    }
  }

  String? ingredientId;
  String? optionId;
  final Map<String, TextEditingController> amountFor = {};

  void dispose() {
    for (final controller in amountFor.values) {
      controller.dispose();
    }
  }
}

class _RecipeEditorDialog extends StatefulWidget {
  const _RecipeEditorDialog({
    required this.products,
    required this.ingredients,
    required this.onSave,
    this.recipe,
  });

  final List<CatalogProduct> products;
  final List<IngredientOption> ingredients;
  final ProductRecipe? recipe;
  final Future<void> Function(CatalogProduct product, List<RecipeLine> lines) onSave;

  @override
  State<_RecipeEditorDialog> createState() => _RecipeEditorDialogState();
}

class _RecipeEditorDialogState extends State<_RecipeEditorDialog> {
  late String _productId;
  late List<_LineDraft> _lines;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.recipe;
    final fallback = widget.products.first.id;
    final match = widget.products.any((item) => item.id == existing?.productId);
    _productId = match ? existing!.productId : fallback;
    _lines = [
      if (existing != null && existing.items.isNotEmpty)
        for (final item in existing.items)
          _LineDraft(
            ingredientId: item.ingredientId,
            optionId: item.optionId,
            quantities: item.variantQuantities,
            fallback: item.quantity,
            variants: _selectedProduct(match ? existing.productId : fallback).variants,
          )
      else
        _LineDraft(
          ingredientId: widget.ingredients.first.id,
          variants: _selectedProduct(match ? existing!.productId : fallback).variants,
        ),
    ];
  }

  CatalogProduct _selectedProduct(String id) {
    return widget.products.firstWhere((item) => item.id == id, orElse: () => widget.products.first);
  }

  String _unitFor(String? ingredientId) {
    for (final item in widget.ingredients) {
      if (item.id == ingredientId) return item.unit;
    }
    return 'PCS';
  }

  void _syncLinesToProduct(String productId) {
    final variants = _selectedProduct(productId).variants;
    for (final line in _lines) {
      final previous = {for (final entry in line.amountFor.entries) entry.key: entry.value.text};
      final fallback = previous.values.isEmpty ? '1' : previous.values.first;
      for (final controller in line.amountFor.values) {
        controller.dispose();
      }
      line.amountFor.clear();
      final ids = variants.map((item) => item.id).where((id) => id.isNotEmpty);
      if (ids.isEmpty) {
        line.amountFor[''] = TextEditingController(text: previous[''] ?? fallback);
      } else {
        for (final id in ids) {
          line.amountFor[id] = TextEditingController(text: previous[id] ?? fallback);
        }
      }
    }
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final used = _lines.map((item) => item.ingredientId).whereType<String>().toSet();
    return AlertDialog(
      title: Text(widget.recipe == null ? 'Recipe for a POS item' : 'Edit recipe'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'One recipe for the product. Each size has its own amount. The unit comes from the stock item, so a recipe cannot use a different unit.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _productId,
                decoration: const InputDecoration(labelText: 'POS product'),
                items: [
                  for (final product in widget.products)
                    DropdownMenuItem(value: product.id, child: Text(product.name)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _productId = value;
                    _syncLinesToProduct(value);
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('Ingredients', style: Theme.of(context).textTheme.titleSmall)),
                  TextButton(
                    onPressed: () {
                      final next = widget.ingredients.where((item) => !used.contains(item.id)).toList();
                      if (next.isEmpty) return;
                      setState(() => _lines.add(_LineDraft(ingredientId: next.first.id, variants: _selectedProduct(_productId).variants)));
                    },
                    child: const Text('Add ingredient'),
                  ),
                ],
              ),
              for (var index = 0; index < _lines.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('ing-$index-${_lines[index].ingredientId}'),
                          initialValue: _lines[index].ingredientId,
                          decoration: const InputDecoration(labelText: 'Ingredient'),
                          items: [
                            for (final item in widget.ingredients)
                              if (item.id == _lines[index].ingredientId || !used.contains(item.id))
                                DropdownMenuItem(value: item.id, child: Text(item.name)),
                          ],
                          onChanged: (value) => setState(() => _lines[index].ingredientId = value),
                        ),
                      ),
                      if (_lines.length > 1)
                        IconButton(
                          onPressed: () => setState(() => _lines.removeAt(index)),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                      ),
                      const SizedBox(height: 8),
                      for (final variant in _selectedProduct(_productId).variants)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: _lines[index].amountFor[variant.id],
                            decoration: InputDecoration(
                              labelText: '${variant.name} uses',
                              suffixText: _unitFor(_lines[index].ingredientId),
                            ),
                          ),
                        ),
                      DropdownButtonFormField<String?>(
                        initialValue: _lines[index].optionId,
                        decoration: const InputDecoration(labelText: 'Only when this add-on is selected'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Every sale')),
                          for (final option in widget.products.firstWhere((item) => item.id == _productId).options)
                            DropdownMenuItem<String?>(value: option.id, child: Text(option.name)),
                        ],
                        onChanged: (value) => setState(() => _lines[index].optionId = value),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  final product = _selectedProduct(_productId);
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  try {
                    await widget.onSave(
                      product,
                      [
                        for (final line in _lines)
                          if (line.ingredientId != null)
                            RecipeLine(
                              ingredientId: line.ingredientId!,
                              quantity: () {
                                final first = line.amountFor.values.map((item) => item.text.trim()).firstWhere((item) => item.isNotEmpty, orElse: () => '1');
                                return first;
                              }(),
                              optionId: line.optionId,
                              unit: _unitFor(line.ingredientId),
                              variantQuantities: {
                                for (final variant in product.variants)
                                  if ((line.amountFor[variant.id]?.text.trim() ?? '').isNotEmpty)
                                    variant.id: line.amountFor[variant.id]!.text.trim(),
                              },
                            ),
                      ],
                    );
                    if (context.mounted) Navigator.pop(context);
                  } catch (error) {
                    setState(() {
                      _busy = false;
                      _error = error.toString();
                    });
                  }
                },
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
