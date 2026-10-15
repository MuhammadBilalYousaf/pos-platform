import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/utils/password_hash.dart';
import 'package:pos_app/core/utils/stock_status.dart';

void main() {
  group('StockStatus', () {
    test('classifies out / very low / low / ok', () {
      expect(StockStatus.fromQuantity(quantity: '0', reorderLevel: '10').level, StockLevel.out);
      expect(StockStatus.fromQuantity(quantity: '3', reorderLevel: '10').level, StockLevel.veryLow);
      expect(StockStatus.fromQuantity(quantity: '8', reorderLevel: '10').level, StockLevel.low);
      expect(StockStatus.fromQuantity(quantity: '20', reorderLevel: '10').level, StockLevel.ok);
    });
  });

  group('cancellation password hash', () {
    test('does not expose plaintext and matches only correct input', () {
      const businessId = 'biz_1';
      final hash = hashBusinessSecret('secret-pass', businessId: businessId);
      expect(hash.contains('secret-pass'), isFalse);
      expect(matchesBusinessSecret(input: 'secret-pass', storedHash: hash, businessId: businessId), isTrue);
      expect(matchesBusinessSecret(input: 'wrong', storedHash: hash, businessId: businessId), isFalse);
      expect(matchesBusinessSecret(input: 'secret-pass', storedHash: hash, businessId: 'other'), isFalse);
    });
  });
}
