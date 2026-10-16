import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/orders/presentation/pages/orders_page.dart';
import 'package:pos_app/features/printing/domain/printer_service.dart';

void main() {
  group('receiptFromOrder partial refund', () {
    test('marks refunded item and recalculates net totals', () {
      final receipt = receiptFromOrder(
        {
          'order_number': 'TURK-1024',
          'cashier_name': 'Admin',
          'order_type': 'TAKEAWAY',
          'status': 'PARTIALLY_REFUNDED',
          'subtotal': '950.00',
          'discount': '0.00',
          'tax': '0.00',
          'total': '950.00',
          'refund_total': '650.00',
          'items': [
            {
              'productName': 'Almounds',
              'quantity': '1',
              'unitPrice': '650',
              'lineTotal': '650.00',
              'refunded_quantity': '1.00',
              'returned_quantity': '1.00',
            },
            {
              'productName': 'Blueberry Sundae',
              'quantity': '1',
              'unitPrice': '300',
              'lineTotal': '300.00',
            },
          ],
          'payments': [
            {'method': 'CASH', 'tendered': '950.00', 'change': '0.00'},
          ],
        },
        businessName: 'TurknRoll',
        branchName: 'Parkview',
        address: 'Lahore',
      );

      expect(receipt.lines.length, 2);
      final returned = receipt.lines.firstWhere((l) => l.isReturned);
      final kept = receipt.lines.firstWhere((l) => !l.isReturned);

      expect(kept.name, 'Blueberry Sundae');
      expect(kept.lineTotal, '300.00');

      expect(returned.name, 'Almounds');
      expect(returned.note, 'RETURNED');
      expect(returned.lineTotal, '-650.00');

      expect(receipt.subtotal, '300.00');
      expect(receipt.total, '300.00');
      expect(receipt.originalTotal, '950.00');
      expect(receipt.refundTotal, '650.00');

      final preview = receipt.toPreviewText();
      expect(preview, contains('Almounds [RETURNED]'));
      expect(preview, contains('Blueberry Sundae'));
      expect(preview, contains('NET TOTAL'));
      expect(preview, contains('Original'));
      expect(preview, contains('Refunded'));
    });

    test('EscPosEncoder includes returned tag and net total', () {
      final receipt = ReceiptData(
        businessName: 'TurknRoll',
        branchName: 'Parkview',
        orderNumber: 'TURK-1024',
        cashierName: 'Admin',
        createdAt: DateTime(2026, 10, 16, 18, 18),
        lines: const [
          ReceiptLine(name: 'Blueberry Sundae', quantity: '1', unitPrice: '300', lineTotal: '300.00'),
          ReceiptLine(
            name: 'Almounds',
            quantity: '1.00',
            unitPrice: '650',
            lineTotal: '-650.00',
            isReturned: true,
            note: 'RETURNED',
          ),
        ],
        subtotal: '300.00',
        discount: '0.00',
        tax: '0.00',
        total: '300.00',
        paymentMethod: 'CASH',
        refundTotal: '650.00',
        originalTotal: '950.00',
      );

      final bytes = EscPosEncoder().encode(receipt);
      final asLatin1 = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
      expect(asLatin1, contains('RETURNED'));
      expect(asLatin1, contains('NET TOTAL'));
      expect(asLatin1, contains('Almounds'));
    });
  });
}
