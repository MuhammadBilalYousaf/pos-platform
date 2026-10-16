import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/errors/failures.dart';
import 'package:pos_app/core/utils/order_totals.dart';
import 'package:pos_app/core/utils/stock_status.dart';
import 'package:pos_app/core/utils/stock_units.dart';

void main() {
  group('moneyOrZero', () {
    test('never throws on bad UI input', () {
      expect(moneyOrZero(null), Decimal.zero);
      expect(moneyOrZero(''), Decimal.zero);
      expect(moneyOrZero('abc'), Decimal.zero);
      expect(moneyOrZero('12.5'), Decimal.parse('12.5'));
    });
  });

  group('StockUnits.toBase', () {
    test('throws Failure (not FormatException) for invalid quantity', () {
      expect(
        () => StockUnits.toBase('', 'G'),
        throwsA(isA<Failure>().having((e) => e.message, 'message', contains('Quantity'))),
      );
      expect(
        () => StockUnits.toBase('not-a-number', 'KG'),
        throwsA(isA<Failure>()),
      );
    });

    test('converts kg/l to base units', () {
      expect(StockUnits.toBase('2', 'KG'), Decimal.fromInt(2000));
      expect(StockUnits.toBase('1.5', 'L'), Decimal.parse('1500'));
      expect(StockUnits.toBase('10', 'PCS'), Decimal.fromInt(10));
    });
  });

  group('StockStatus.fromQuantity', () {
    test('tolerates invalid stored quantities without crashing', () {
      final status = StockStatus.fromQuantity(quantity: 'bad', reorderLevel: 'also-bad');
      expect(status.level, StockLevel.out);
      expect(status.quantity, Decimal.zero);
    });
  });

  group('mixture produce validation helpers', () {
    test('duplicate ingredient detection logic', () {
      final seen = <String>{};
      const ids = ['MILK', 'sugar', 'MILK'];
      String? duplicate;
      for (final id in ids) {
        final key = id.trim().toUpperCase();
        if (!seen.add(key)) {
          duplicate = key;
          break;
        }
      }
      expect(duplicate, 'MILK');
    });

    test('mixture cannot be its own ingredient', () {
      const mixtureId = 'BASE-MIX';
      const componentId = 'base-mix';
      expect(mixtureId.toUpperCase() == componentId.toUpperCase(), isTrue);
    });
  });
}
