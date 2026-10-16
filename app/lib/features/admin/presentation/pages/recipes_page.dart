import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../config/dependency_injection/injection.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/app_log.dart';
import '../../../../core/utils/order_totals.dart';
import '../../../../core/utils/recipe_cost.dart';
import '../../../../core/utils/stock_status.dart';
import '../../../../core/utils/stock_units.dart';
import '../../../../core/widgets/stock_item_picker.dart';
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

  String _recipeCostLabel(ProductRecipe recipe) {
    try {
      final costs = {
        for (final item in _ingredients)
          item.id: IngredientCostSnapshot(
            ingredientId: item.id,
            name: item.name,
            unitCostPerBase: moneyOrZero(item.unitCostPerBase),
            unit: item.unit,
          ),
      };
      final breakdown = RecipeCostCalculator.forVariant(
        recipe: recipe,
        costsByIngredient: costs,
      );
      return 'Recipe cost: Rs. ${moneyString(breakdown.totalCost)}';
    } catch (_) {
      return 'Recipe cost: unavailable';
    }
  }

  Future<void> _produce() async {
    final mixtures = _ingredients.where((item) => item.kind.toUpperCase() == 'MIXTURE').toList();
    final parts = _ingredients.where((item) => item.kind.toUpperCase() != 'MIXTURE').toList();
    if (mixtures.isEmpty || parts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a mixture stock item and the raw ingredients it is made from.')),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ProduceMixtureDialog(
        mixtures: mixtures,
        parts: parts,
        onProduced: () async {
          await _load();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mixture stock updated.')));
          }
        },
      ),
    );
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
                            [
                              recipe.items.map((item) => '${_ingredientName(item.ingredientId)} × ${item.quantity}').join(' · '),
                              _recipeCostLabel(recipe),
                            ].where((part) => part.isNotEmpty).join('\n'),
                          ),
                          isThreeLine: true,
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

class _ComponentDraft {
  _ComponentDraft({required this.ingredientId, required String quantity, required this.unit})
      : qty = TextEditingController(text: quantity);

  String ingredientId;
  String unit;
  final TextEditingController qty;

  void dispose() => qty.dispose();
}

class _ProduceMixtureDialog extends StatefulWidget {
  const _ProduceMixtureDialog({
    required this.mixtures,
    required this.parts,
    required this.onProduced,
  });

  final List<IngredientOption> mixtures;
  final List<IngredientOption> parts;
  final Future<void> Function() onProduced;

  @override
  State<_ProduceMixtureDialog> createState() => _ProduceMixtureDialogState();
}

class _ProduceMixtureDialogState extends State<_ProduceMixtureDialog> {
  late String _mixtureId;
  late final TextEditingController _yieldQty;
  late List<_ComponentDraft> _components;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mixtureId = widget.mixtures.first.id;
    _yieldQty = TextEditingController(text: '1');
    final first = widget.parts.first;
    _components = [_ComponentDraft(ingredientId: first.id, quantity: '1', unit: first.unit)];
  }

  @override
  void dispose() {
    _yieldQty.dispose();
    for (final row in _components) {
      row.dispose();
    }
    super.dispose();
  }

  IngredientOption _mixture() {
    for (final item in widget.mixtures) {
      if (item.id == _mixtureId) return item;
    }
    return widget.mixtures.first;
  }

  Set<String> get _used => _components.map((row) => row.ingredientId).toSet();

  String? _onHandHelper(String ingredientId) {
    IngredientOption? match;
    for (final item in widget.parts) {
      if (item.id == ingredientId) {
        match = item;
        break;
      }
    }
    if (match == null) return null;
    try {
      final onHand = StockUnits.fromBase(moneyOrZero(match.onHandBase), match.unit);
      final status = StockStatus.fromQuantity(quantity: onHand, reorderLevel: match.reorderLevel);
      return 'On hand: $onHand ${match.unit}${status.isWarning ? ' · ${status.label}' : ''}';
    } catch (_) {
      return null;
    }
  }

  String? _validateBeforeSubmit() {
    if (widget.mixtures.isEmpty) {
      return 'No mixture stock item is available. Add one under Inventory first.';
    }
    if (widget.parts.isEmpty) {
      return 'No raw ingredients are available. Add ingredients under Inventory first.';
    }
    if (_mixtureId.trim().isEmpty) {
      return 'Choose a mixture to prepare.';
    }
    final yieldText = _yieldQty.text.trim();
    if (yieldText.isEmpty) {
      return 'Enter a yield quantity.';
    }
    if (parseMoneyInput(yieldText) == null) {
      return 'Yield quantity must be a valid number.';
    }
    if (moneyOrZero(yieldText) <= Decimal.zero) {
      return 'Yield must be greater than zero.';
    }
    if (_components.isEmpty) {
      return 'Add at least one ingredient.';
    }
    final seen = <String>{};
    for (var i = 0; i < _components.length; i++) {
      final row = _components[i];
      final id = row.ingredientId.trim();
      if (id.isEmpty) {
        return 'Ingredient ${i + 1}: choose a stock item.';
      }
      if (id.toUpperCase() == _mixtureId.trim().toUpperCase()) {
        return 'A mixture cannot use itself as an ingredient.';
      }
      if (!seen.add(id.toUpperCase())) {
        return 'Ingredient "$id" is listed more than once. Combine into one row.';
      }
      final qty = row.qty.text.trim();
      if (qty.isEmpty) {
        return 'Ingredient ${i + 1}: enter a quantity.';
      }
      if (parseMoneyInput(qty) == null) {
        return 'Ingredient ${i + 1}: quantity must be a valid number.';
      }
      if (moneyOrZero(qty) <= Decimal.zero) {
        return 'Ingredient ${i + 1}: quantity must be greater than zero.';
      }
    }
    return null;
  }

  String _friendlyError(Object error) {
    if (error is Failure) return error.message;
    final text = error.toString();
    if (text.contains('Select a branch')) {
      return 'Select a branch first, then try Produce Mixture again.';
    }
    if (text.contains('permission-denied') || text.contains('PERMISSION_DENIED')) {
      return 'You do not have permission to update stock for this branch.';
    }
    if (text.contains('unavailable') || text.contains('network')) {
      return 'Network problem while updating stock. Check internet and try again.';
    }
    // Strip noisy Exception: prefixes for the dialog.
    return text.replaceFirst(RegExp(r'^(Exception|Error|Failure):\s*'), '').trim();
  }

  Future<void> _submit() async {
    if (_busy || !mounted) return;

    final validationError = _validateBeforeSubmit();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    IngredientOption mixture;
    try {
      mixture = _mixture();
    } catch (_) {
      setState(() => _error = 'Choose a valid mixture before producing.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final yieldQty = _yieldQty.text.trim();
    final components = [
      for (final row in _components)
        RecipeLine(
          ingredientId: row.ingredientId.trim(),
          quantity: row.qty.text.trim(),
          unit: row.unit.isEmpty ? 'PCS' : row.unit,
        ),
    ];
    await AppLog.info(
      'Produce mixture start: mix=${mixture.id} yield=$yieldQty ${mixture.unit} '
      'components=${components.map((c) => '${c.ingredientId}:${c.quantity}${c.unit}').join(', ')}',
    );

    try {
      await sl<AdminRepository>().produceMixture(
        mixtureId: mixture.id,
        yieldQuantity: yieldQty,
        yieldUnit: mixture.unit.isEmpty ? 'PCS' : mixture.unit,
        components: components,
      );
      await AppLog.info('Produce mixture OK: ${mixture.id}');
      try {
        await widget.onProduced();
      } catch (error, stack) {
        await AppLog.error('Produce mixture refresh after success failed', error, stack);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stack) {
      await AppLog.error('Produce mixture FAILED', error, stack);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${_friendlyError(error)}\n\nDetails saved to:\n${AppLog.path ?? r'Documents\POS\pos_app_log.txt'}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mixture = _mixture();
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Prepare mixture'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add every ingredient used. Each is deducted from stock, then the yield is added to the mixture. Selling a product that uses the mixture does not deduct the raw ingredients again.',
                ),
                const SizedBox(height: 12),
                StockItemPicker(
                  items: widget.mixtures,
                  value: _mixtureId,
                  label: 'Mixture',
                  enabled: !_busy,
                  onChanged: (item) {
                    if (item != null) setState(() => _mixtureId = item.id);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _yieldQty,
                  enabled: !_busy,
                  decoration: InputDecoration(labelText: 'Yield quantity', suffixText: mixture.unit),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('Ingredients', style: Theme.of(context).textTheme.titleSmall)),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              final next = widget.parts.where((item) => !_used.contains(item.id)).toList();
                              if (next.isEmpty) {
                                setState(() => _error = 'All available ingredients are already listed.');
                                return;
                              }
                              setState(() {
                                _error = null;
                                _components.add(
                                  _ComponentDraft(ingredientId: next.first.id, quantity: '1', unit: next.first.unit),
                                );
                              });
                            },
                      child: const Text('Add ingredient'),
                    ),
                  ],
                ),
                for (var index = 0; index < _components.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: StockItemPicker(
                                items: widget.parts,
                                value: _components[index].ingredientId,
                                excludeIds: _used,
                                label: 'Ingredient ${index + 1}',
                                enabled: !_busy,
                                onChanged: (item) {
                                  if (item == null) return;
                                  setState(() {
                                    _components[index].ingredientId = item.id;
                                    _components[index].unit = item.unit;
                                  });
                                },
                              ),
                            ),
                            if (_components.length > 1)
                              IconButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _components.removeAt(index).dispose();
                                        }),
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        ),
                        TextField(
                          controller: _components[index].qty,
                          enabled: !_busy,
                          decoration: InputDecoration(
                            labelText: 'Quantity',
                            suffixText: _components[index].unit,
                            helperText: _onHandHelper(_components[index].ingredientId),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (_busy) return;
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            // Never use a null onPressed — validate and show errors instead of crashing.
            onPressed: () {
              if (_busy) return;
              unawaited(_submit());
            },
            child: Text(_busy ? 'Producing…' : 'Produce Mixture'),
          ),
        ],
      ),
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
                        child: StockItemPicker(
                          key: ValueKey('ing-$index-${_lines[index].ingredientId}'),
                          items: widget.ingredients,
                          value: _lines[index].ingredientId,
                          excludeIds: used,
                          label: 'Ingredient / stock',
                          onChanged: (item) => setState(() => _lines[index].ingredientId = item?.id),
                        ),
                      ),
                      if (_lines.length > 1)
                        IconButton(
                          onPressed: () => setState(() {
                            _lines.removeAt(index).dispose();
                          }),
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
                        key: ValueKey('opt-$index-${_lines[index].optionId}-$_productId'),
                        initialValue: _lines[index].optionId,
                        decoration: const InputDecoration(labelText: 'Only when this add-on is selected'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Every sale')),
                          for (final option in _selectedProduct(_productId).options)
                            DropdownMenuItem<String?>(value: option.id, child: Text(option.name)),
                        ],
                        onChanged: (value) => setState(() => _lines[index].optionId = value),
                      ),
                    ],
                  ),
                ),
              Builder(
                builder: (context) {
                  final product = _selectedProduct(_productId);
                  final draftLines = [
                    for (final line in _lines)
                      if (line.ingredientId != null)
                        RecipeLine(
                          ingredientId: line.ingredientId!,
                          quantity: line.amountFor.values.map((item) => item.text.trim()).firstWhere((item) => item.isNotEmpty, orElse: () => '1'),
                          optionId: line.optionId,
                          unit: _unitFor(line.ingredientId),
                          variantQuantities: {
                            for (final variant in product.variants)
                              if ((line.amountFor[variant.id]?.text.trim() ?? '').isNotEmpty)
                                variant.id: line.amountFor[variant.id]!.text.trim(),
                          },
                        ),
                  ];
                  final costs = {
                    for (final item in widget.ingredients)
                      item.id: IngredientCostSnapshot(
                        ingredientId: item.id,
                        name: item.name,
                        unitCostPerBase: moneyOrZero(item.unitCostPerBase),
                        unit: item.unit,
                      ),
                  };
                  final recipe = ProductRecipe(
                    id: product.id,
                    productId: product.id,
                    name: product.name,
                    items: draftLines,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text('Recipe cost by size', style: Theme.of(context).textTheme.titleSmall),
                      for (final variant in product.variants)
                        Builder(
                          builder: (context) {
                            try {
                              final breakdown = RecipeCostCalculator.forVariant(
                                recipe: recipe,
                                costsByIngredient: costs,
                                variantId: variant.id,
                                variantName: variant.name,
                                sellPrice: variant.price,
                              );
                              final margin = breakdown.margin;
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${variant.name}: cost Rs. ${moneyString(breakdown.totalCost)}'
                                  ' · sell Rs. ${variant.price}'
                                  '${margin == null ? '' : ' · margin Rs. ${moneyString(margin)}'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            } catch (_) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('${variant.name}: cost unavailable', style: const TextStyle(fontSize: 12)),
                              );
                            }
                          },
                        ),
                    ],
                  );
                },
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
