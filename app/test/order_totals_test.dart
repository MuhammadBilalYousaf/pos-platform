import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/utils/order_totals.dart';

void main() {
  test('cart totals match the server decimal rules', () {
    final result = calculateOrderTotals(
      taxRate: '0.0500',
      orderDiscountAmount: '20',
      lines: const [
        OrderLineInput(quantity: '2', unitPrice: '250.00', extraPrice: '50.00'),
        OrderLineInput(quantity: '1', unitPrice: '80.00', discountAmount: '10'),
      ],
    );
    expect(result.lineTotals[0], '600.00');
    expect(result.lineTotals[1], '70.00');
    expect(result.subtotal, '670.00');
    expect(result.discountAmount, '20.00');
    expect(result.taxAmount, '32.50');
    expect(result.total, '682.50');
  });
}
