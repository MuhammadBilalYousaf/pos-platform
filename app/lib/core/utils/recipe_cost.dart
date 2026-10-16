import 'package:decimal/decimal.dart';
import '../../features/admin/data/admin_repository.dart';
import 'order_totals.dart';
import 'stock_units.dart';

class IngredientCostSnapshot {
  const IngredientCostSnapshot({
    required this.ingredientId,
    required this.name,
    required this.unitCostPerBase,
    required this.unit,
  });

  final String ingredientId;
  final String name;
  /// Cost per base unit (G / ML / PCS).
  final Decimal unitCostPerBase;
  final String unit;
}

class RecipeLineCost {
  const RecipeLineCost({
    required this.ingredientId,
    required this.ingredientName,
    required this.quantity,
    required this.unit,
    required this.lineCost,
    this.variantId,
  });

  final String ingredientId;
  final String ingredientName;
  final String quantity;
  final String unit;
  final Decimal lineCost;
  final String? variantId;
}

class RecipeCostBreakdown {
  const RecipeCostBreakdown({
    required this.productId,
    required this.productName,
    required this.lines,
    required this.totalCost,
    this.variantId,
    this.variantName,
    this.sellPrice,
  });

  final String productId;
  final String productName;
  final List<RecipeLineCost> lines;
  final Decimal totalCost;
  final String? variantId;
  final String? variantName;
  final Decimal? sellPrice;

  Decimal? get margin {
    if (sellPrice == null) return null;
    return sellPrice! - totalCost;
  }
}

/// Calculates recipe cost from current ingredient unit costs (for display / planning).
/// Historical order costs remain frozen on the order document and are not overwritten.
///
/// Never throws — invalid quantities are treated as zero so UI rebuilds stay safe in release.
class RecipeCostCalculator {
  static RecipeCostBreakdown forVariant({
    required ProductRecipe recipe,
    required Map<String, IngredientCostSnapshot> costsByIngredient,
    String? variantId,
    String? variantName,
    String? sellPrice,
    Decimal? sizeMultiplier,
  }) {
    final lines = <RecipeLineCost>[];
    var total = Decimal.zero;
    final factor = sizeMultiplier ?? Decimal.one;
    final multiplier = factor <= Decimal.zero ? Decimal.one : factor;

    for (final line in recipe.items) {
      final cost = costsByIngredient[line.ingredientId] ??
          costsByIngredient[line.ingredientId.toUpperCase()];
      final unit = line.unit.isEmpty ? (cost?.unit ?? 'PCS') : line.unit;
      var qtyText = line.quantity;
      var useMultiplier = true;
      if (variantId != null && line.variantQuantities.isNotEmpty) {
        final sized = line.variantQuantities[variantId] ?? line.variantQuantities[variantId.toUpperCase()];
        if (sized != null && sized.trim().isNotEmpty) {
          qtyText = sized.trim();
          useMultiplier = false;
        }
      }
      final qtyBase = _qtyBase(qtyText, unit) * (useMultiplier ? multiplier : Decimal.one);
      final unitCost = cost?.unitCostPerBase ?? Decimal.zero;
      final lineCost = qtyBase * unitCost;
      total += lineCost;
      lines.add(
        RecipeLineCost(
          ingredientId: line.ingredientId,
          ingredientName: cost?.name ?? line.ingredientId,
          quantity: qtyText,
          unit: unit,
          lineCost: lineCost,
          variantId: variantId,
        ),
      );
    }

    return RecipeCostBreakdown(
      productId: recipe.productId,
      productName: recipe.name,
      lines: lines,
      totalCost: total,
      variantId: variantId,
      variantName: variantName,
      sellPrice: sellPrice == null || sellPrice.isEmpty ? null : moneyOrZero(sellPrice),
    );
  }

  static Decimal _qtyBase(String quantity, String unit) {
    final parsed = parseMoneyInput(quantity);
    if (parsed == null || parsed <= Decimal.zero) return Decimal.zero;
    switch (StockUnits.normalize(unit)) {
      case 'KG':
      case 'L':
        return parsed * Decimal.fromInt(1000);
      default:
        return parsed;
    }
  }
}
