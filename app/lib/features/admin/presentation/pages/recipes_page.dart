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
          child: FilledButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Recipe'),
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
  _LineDraft({this.ingredientId, String quantity = '1'}) : quantity = TextEditingController(text: quantity);
  String? ingredientId;
  final TextEditingController quantity;
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
        for (final item in existing.items) _LineDraft(ingredientId: item.ingredientId, quantity: item.quantity)
      else
        _LineDraft(ingredientId: widget.ingredients.first.id),
    ];
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.quantity.dispose();
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
              const Text('This recipe is deducted from stock each time that product is sold.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _productId,
                decoration: const InputDecoration(labelText: 'POS product'),
                items: [
                  for (final product in widget.products)
                    DropdownMenuItem(value: product.id, child: Text(product.name)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _productId = value);
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
                      setState(() => _lines.add(_LineDraft(ingredientId: next.first.id)));
                    },
                    child: const Text('Add ingredient'),
                  ),
                ],
              ),
              for (var index = 0; index < _lines.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
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
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _lines[index].quantity,
                          decoration: const InputDecoration(labelText: 'Qty used'),
                        ),
                      ),
                      if (_lines.length > 1)
                        IconButton(
                          onPressed: () => setState(() => _lines.removeAt(index)),
                          icon: const Icon(Icons.close),
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
                  final product = widget.products.firstWhere((item) => item.id == _productId);
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
                              quantity: line.quantity.text.trim().isEmpty ? '1' : line.quantity.text.trim(),
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
