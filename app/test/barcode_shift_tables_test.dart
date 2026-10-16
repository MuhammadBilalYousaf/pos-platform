import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/auth/domain/entities/session.dart';
import 'package:pos_app/features/products/domain/entities/catalog.dart';
import 'package:pos_app/features/products/presentation/bloc/catalog_cubit.dart';
import 'package:pos_app/features/shifts/data/shift_repository.dart';

void main() {
  group('barcode lookup', () {
    test('finds product by SKU and variant SKU', () {
      final state = CatalogState(
        catalog: PosCatalog(
          categories: const [],
          products: [
            CatalogProduct(
              id: 'p1',
              categoryId: 'c1',
              name: 'Almounds',
              productType: 'SIMPLE',
              sku: 'ALM-001',
              variants: const [
                ProductVariant(id: 'v1', name: 'Regular', price: '650', isDefault: true, sku: 'ALM-REG'),
              ],
              options: const [],
            ),
          ],
        ),
      );

      expect(state.findByBarcode('alm-001')?.product.name, 'Almounds');
      expect(state.findByBarcode('ALM-REG')?.variant?.id, 'v1');
      expect(state.findByBarcode('missing'), isNull);
    });
  });

  group('dining tables', () {
    test('parse labels from comma and newline lists', () {
      expect(BusinessProfile.parseDiningTableLabels('1, 2, Patio A'), ['1', '2', 'Patio A']);
      expect(BusinessProfile.parseDiningTableLabels('1\n2\n3'), ['1', '2', '3']);
      expect(BusinessProfile.parseDiningTableLabels('  '), isEmpty);
    });

    test('hasTableMap only when enabled with labels', () {
      const off = BusinessProfile(
        id: 'b',
        name: 'Cafe',
        primaryColor: '#000',
        secondaryColor: '#fff',
        currencyCode: 'PKR',
        taxRate: '0',
        diningTablesEnabled: false,
        diningTables: ['1', '2'],
      );
      const onEmpty = BusinessProfile(
        id: 'b',
        name: 'Cafe',
        primaryColor: '#000',
        secondaryColor: '#fff',
        currencyCode: 'PKR',
        taxRate: '0',
        diningTablesEnabled: true,
        diningTables: [],
      );
      const onMapped = BusinessProfile(
        id: 'b',
        name: 'Cafe',
        primaryColor: '#000',
        secondaryColor: '#fff',
        currencyCode: 'PKR',
        taxRate: '0',
        diningTablesEnabled: true,
        diningTables: ['1', '2'],
      );
      expect(off.hasTableMap, isFalse);
      expect(onEmpty.hasTableMap, isFalse);
      expect(onMapped.hasTableMap, isTrue);
    });
  });

  group('shift cash variance', () {
    test('varianceFor is counted minus expected', () {
      final summary = ShiftSummary(
        shift: PosShift(
          id: 's1',
          branchId: 'br1',
          businessDay: '2026-10-16',
          startedAt: DateTime(2026, 10, 16, 9),
          startedBy: 'u1',
          openingCash: '1000.00',
        ),
        orderCount: 2,
        salesTotal: '500.00',
        refundTotal: '50.00',
        cancelCount: 0,
        cashSalesTotal: '400.00',
        cashRefundTotal: '50.00',
        expectedCash: '1350.00',
      );
      expect(summary.varianceFor('1350.00'), '0.00');
      expect(summary.varianceFor('1400.00'), '50.00');
      expect(summary.varianceFor('1300.00'), '-50.00');
    });
  });
}
