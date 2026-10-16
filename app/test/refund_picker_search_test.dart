import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/orders/presentation/refund_flows.dart';

void main() {
  group('refund picker helpers', () {
    final order = {
      'order_number': 'TURK-1024',
      'customer_name': 'Walk-in',
      'cashier_name': 'Admin',
      'order_type': 'TAKEAWAY',
      'status': 'PARTIALLY_REFUNDED',
      'total': '950.00',
      'refund_total': '650.00',
      'payments': [
        {'method': 'CASH'},
      ],
      'items': [
        {'productName': 'Almounds', 'quantity': '1'},
        {'productName': 'Blueberry Sundae', 'quantity': '1'},
      ],
    };

    test('isRefundableStatus accepts completed and partial', () {
      expect(isRefundableStatus('COMPLETED'), isTrue);
      expect(isRefundableStatus('PARTIALLY_REFUNDED'), isTrue);
      expect(isRefundableStatus('CANCELLED'), isFalse);
      expect(isRefundableStatus('REFUNDED'), isFalse);
    });

    test('orderMatchesQuery finds by item name', () {
      expect(orderMatchesQuery(order, 'almounds'), isTrue);
      expect(orderMatchesQuery(order, 'blueberry'), isTrue);
      expect(orderMatchesQuery(order, 'TURK-1024'), isTrue);
      expect(orderMatchesQuery(order, 'cash'), isTrue);
      expect(orderMatchesQuery(order, 'pizza'), isFalse);
    });

    test('orderItemsSummary lists quantities and names', () {
      expect(orderItemsSummary(order), contains('Almounds'));
      expect(orderItemsSummary(order), contains('Blueberry Sundae'));
    });
  });
}
