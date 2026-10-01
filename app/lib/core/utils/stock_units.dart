import 'package:decimal/decimal.dart';
import 'order_totals.dart';

/// Stock is stored in a base unit: pieces, grams, or milliliters.
class StockUnits {
  static const choices = ['PCS', 'G', 'KG', 'ML', 'L'];

  static String normalize(String? raw) {
    final value = (raw ?? 'PCS').trim().toUpperCase();
    if (value == 'QTY' || value == 'PIECE' || value == 'PIECES' || value == 'PC') return 'PCS';
    if (value == 'GRAM' || value == 'GRAMS') return 'G';
    if (value == 'KILOGRAM' || value == 'KILOGRAMS') return 'KG';
    if (value == 'MILLILITER' || value == 'MILLILITERS' || value == 'MLT') return 'ML';
    if (value == 'LITER' || value == 'LITRE' || value == 'LITERS' || value == 'LITRES') return 'L';
    return choices.contains(value) ? value : 'PCS';
  }

  static String baseOf(String unit) {
    switch (normalize(unit)) {
      case 'KG':
      case 'G':
        return 'G';
      case 'L':
      case 'ML':
        return 'ML';
      default:
        return 'PCS';
    }
  }

  static Decimal toBase(String quantity, String unit) {
    final qty = money(quantity);
    switch (normalize(unit)) {
      case 'KG':
        return qty * Decimal.fromInt(1000);
      case 'L':
        return qty * Decimal.fromInt(1000);
      default:
        return qty;
    }
  }

  static String fromBase(Decimal quantityBase, String displayUnit) {
    switch (normalize(displayUnit)) {
      case 'KG':
      case 'L':
        return moneyString((quantityBase / Decimal.fromInt(1000)).toDecimal(scaleOnInfinitePrecision: 4));
      default:
        return moneyString(quantityBase);
    }
  }
}
