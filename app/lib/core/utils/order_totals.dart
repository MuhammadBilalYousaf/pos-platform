import 'package:decimal/decimal.dart';

Decimal money(String value) => Decimal.parse(value);

String moneyString(Decimal value) => value.round(scale: 2).toStringAsFixed(2);

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
