import 'package:decimal/decimal.dart';

import '../errors/failures.dart';

Decimal money(String value) {
  final parsed = parseMoneyInput(value);
  if (parsed == null) {
    throw FormatException('Invalid amount: $value');
  }
  return parsed;
}

/// Safe parse for UI display paths — never throws.
Decimal moneyOrZero(String? value) => parseMoneyInput(value ?? '') ?? Decimal.zero;

/// Parses currency/quantity text (`10`, `+10`, `-2.5`). Returns null if invalid.
Decimal? parseMoneyInput(String raw) {
  var text = raw.trim().replaceAll(',', '');
  if (text.isEmpty) return null;
  if (text.startsWith('+')) {
    text = text.substring(1).trim();
    if (text.isEmpty) return null;
  }
  try {
    return Decimal.parse(text);
  } catch (_) {
    return null;
  }
}

Decimal parseMoneyInputOrThrow(String raw, {String label = 'Amount'}) {
  final parsed = parseMoneyInput(raw);
  if (parsed == null) {
    throw Failure('$label is not a valid number.');
  }
  return parsed;
}

String moneyString(Decimal value) => value.round(scale: 2).toStringAsFixed(2);

/// Resolves a discount entered as rupees or percent against [baseAmount].
/// Percent is of [baseAmount]; result is never negative and never above the base.
Decimal resolveDiscount({
  required Decimal baseAmount,
  required String value,
  required bool isPercent,
}) {
  final raw = moneyOrZero(value);
  if (raw <= Decimal.zero || baseAmount <= Decimal.zero) return Decimal.zero;
  Decimal amount;
  if (isPercent) {
    final capped = raw > Decimal.fromInt(100) ? Decimal.fromInt(100) : raw;
    amount = (baseAmount * capped / Decimal.fromInt(100)).toDecimal(scaleOnInfinitePrecision: 4);
  } else {
    amount = raw;
  }
  if (amount > baseAmount) amount = baseAmount;
  return amount.round(scale: 2);
}

String formatDiscountLabel({required String value, required bool isPercent}) {
  final trimmed = value.trim().isEmpty ? '0' : value.trim();
  if (isPercent) return '$trimmed%';
  return 'Rs. $trimmed';
}

class OrderLineInput {
  const OrderLineInput({
    required this.quantity,
    required this.unitPrice,
    this.extraPrice = '0',
    this.discountAmount = '0',
  });

  final String quantity;
  final String unitPrice;
  final String extraPrice;
  final String discountAmount;
}

class OrderTotals {
  const OrderTotals({
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.total,
    required this.lineTotals,
  });

  final String subtotal;
  final String discountAmount;
  final String taxAmount;
  final String total;
  final List<String> lineTotals;
}

OrderTotals calculateOrderTotals({
  required List<OrderLineInput> lines,
  String orderDiscountAmount = '0',
  String taxRate = '0',
}) {
  final lineTotals = <Decimal>[];
  for (final line in lines) {
    final qty = money(line.quantity);
    final unit = money(line.unitPrice) + money(line.extraPrice);
    final raw = unit * qty;
    final discounted = raw - money(line.discountAmount);
    lineTotals.add(discounted < Decimal.zero ? Decimal.zero : discounted);
  }
  final subtotal = lineTotals.fold(Decimal.zero, (sum, value) => sum + value);
  var discount = money(orderDiscountAmount);
  if (discount > subtotal) {
    discount = subtotal;
  }
  final taxable = subtotal - discount;
  final taxAmount = (taxable * money(taxRate)).round(scale: 2);
  final total = taxable + taxAmount;
  return OrderTotals(
    subtotal: moneyString(subtotal),
    discountAmount: moneyString(discount),
    taxAmount: moneyString(taxAmount),
    total: moneyString(total),
    lineTotals: lineTotals.map(moneyString).toList(),
  );
}
