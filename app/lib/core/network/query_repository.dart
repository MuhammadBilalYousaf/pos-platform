import 'package:decimal/decimal.dart';
import '../../../../core/firebase/firestore_host.dart';
import '../../../../core/firebase/tenant_context.dart';
import '../../../../core/utils/json_read.dart';
import '../../../../core/utils/order_totals.dart';

enum PosListKind { orders, inventory, productSales }

class QueryRepository {
  QueryRepository(this._firestore, this._tenant);

  final FirestoreHost _firestore;
  final TenantContext _tenant;

  Future<List<Map<String, dynamic>>> list(PosListKind kind) async {
    try {
      final db = _firestore.requireDb();
      final businessId = _tenant.requireBusinessId();
      final business = db.collection('businesses').doc(businessId);
      switch (kind) {
        case PosListKind.orders:
          final snap = await business.collection('orders').limit(100).get();
          return snap.docs.map((doc) {
            final data = asStringKeyMap(doc.data());
            data['id'] = doc.id;
            data['order_number'] = readString(data, ['order_number', 'orderNumber'], doc.id);
            data['total'] = readString(data, ['total'], '0');
            return data;
          }).toList();
        case PosListKind.inventory:
          final snap = await business.collection('inventory').get();
          return snap.docs.map((doc) {
            final data = asStringKeyMap(doc.data());
            data['id'] = doc.id;
            data['ingredient_name'] = readString(data, ['ingredient_name', 'ingredientName']);
            data['quantity_base'] = readString(data, ['quantity_base', 'quantityBase'], '0');
            return data;
          }).toList();
        case PosListKind.productSales:
          final snap = await business.collection('orders').limit(200).get();
          final totals = <String, Decimal>{};
          final names = <String, String>{};
          for (final doc in snap.docs) {
            final data = asStringKeyMap(doc.data());
            if (readString(data, ['status']) == 'CANCELLED') {
              continue;
            }
            for (final raw in readList(data, ['items'])) {
              final item = asStringKeyMap(raw);
              final productId = readString(item, ['productId', 'product_id']);
              names[productId] = readString(item, ['productName', 'product_name'], productId);
              totals[productId] = (totals[productId] ?? Decimal.zero) + money(readString(item, ['lineTotal', 'line_total'], '0'));
            }
          }
          return totals.entries
              .map(
                (entry) => {
                  'product_name': names[entry.key] ?? entry.key,
                  'total': moneyString(entry.value),
                },
              )
              .toList();
      }
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }
}
