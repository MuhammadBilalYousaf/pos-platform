import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:hive/hive.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/firebase/firestore_host.dart';
import '../../../../core/firebase/tenant_context.dart';
import '../../../../core/storage/hive_boxes.dart';
import '../../../../core/utils/json_read.dart';
import '../../../../core/utils/order_totals.dart';
import '../../../pos/presentation/bloc/cart_cubit.dart';
import '../../../auth/domain/permissions.dart';

class PendingOrder {
  PendingOrder({
    required this.idempotencyKey,
    required this.payload,
    required this.status,
    this.errorMessage,
  });

  final String idempotencyKey;
  final Map<String, dynamic> payload;
  String status;
  String? errorMessage;

  Map<String, dynamic> toJson() => {
        'idempotencyKey': idempotencyKey,
        'payload': payload,
        'status': status,
        'errorMessage': errorMessage,
      };

  factory PendingOrder.fromJson(Map<String, dynamic> json) {
    return PendingOrder(
      idempotencyKey: json['idempotencyKey'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      status: json['status'] as String,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

class OrderRepository {
  OrderRepository(this._firestore, this._tenant, this._pending);

  final FirestoreHost _firestore;
  final TenantContext _tenant;
  final Box<dynamic> _pending;

  Map<String, dynamic> buildPayload({
    required String branchId,
    required String idempotencyKey,
    required CartState cart,
    required String paymentMethod,
    String? referenceNo,
    String? tendered,
    String? change,
    String? cashierName,
  }) {
    final totals = cart.totals;
    return {
      'branchId': branchId,
      'idempotencyKey': idempotencyKey,
      'discountAmount': cart.orderDiscount,
      'subtotal': totals.subtotal,
      'taxAmount': totals.taxAmount,
      'total': totals.total,
      'orderType': cart.orderType,
      'customerName': cart.customerName,
      'customerPhone': cart.customerPhone,
      'tableNo': cart.tableNo,
      'note': cart.note,
      if (cashierName != null) 'cashierName': cashierName,
      'items': [
        for (var index = 0; index < cart.lines.length; index++)
          {
            'productId': cart.lines[index].product.id,
            'productName': cart.lines[index].displayName,
            'variantId': cart.lines[index].variant.id,
            'quantity': cart.lines[index].quantity.toString(),
            'unitPrice': cart.lines[index].variant.price,
            'extraPrice': cart.lines[index].extraPrice,
            'lineDiscount': cart.lines[index].lineDiscount,
            'lineTotal': totals.lineTotals[index],
            'optionIds': cart.lines[index].options.map((item) => item.id).toList(),
          },
      ],
      'payments': [
        {
          'method': paymentMethod,
          'amount': totals.total,
          if (referenceNo != null) 'referenceNo': referenceNo,
          if (tendered != null) 'tendered': tendered,
          if (change != null) 'change': change,
        },
      ],
    };
  }

  Future<Map<String, dynamic>> completeOnline(Map<String, dynamic> payload) async {
    // Captured before Firestore web wraps thrown errors into "converted Future".
    Failure? localFailure;
    try {
      final db = _firestore.requireDb();
      final businessId = _tenant.requireBusinessId();
      final userId = _tenant.userId;
      final branchId = payload['branchId'] as String?;
      if (branchId == null || branchId.isEmpty) {
        throw const Failure('Select a branch before taking payment.');
      }
      if (!_tenant.canAccessBranch(branchId)) {
        throw const Failure('You cannot sell from that branch.');
      }
      final businessRef = db.collection('businesses').doc(businessId);
      final orders = businessRef.collection('orders');
      final recipes = businessRef.collection('recipes');
      final inventory = businessRef.collection('inventory');
      final transactions = businessRef.collection('inventory_transactions');
      final idempotencyKey = payload['idempotencyKey'] as String;
      final orderRef = orders.doc(idempotencyKey);
      final recipeSnap = await recipes.get();
      final recipesByProduct = <String, Map<String, dynamic>>{
        for (final doc in recipeSnap.docs) doc.id: asStringKeyMap(doc.data()),
      };

      final result = await db.runTransaction((tx) async {
        final existing = await tx.get(orderRef);
        if (existing.exists) {
          final data = asStringKeyMap(existing.data());
          data['id'] = existing.id;
          return data;
        }

        final businessSnap = await tx.get(businessRef);
        if (!businessSnap.exists) {
          localFailure = const Failure('Business profile was not found.');
          throw localFailure!;
        }
        final businessData = asStringKeyMap(businessSnap.data());
        final seq = readInt(businessData, ['orderSeq'], 1000) + 1;
        final prefix = readString(businessData, ['slug'], 'ORD').toUpperCase();
        final shortPrefix = prefix.length <= 4 ? prefix : prefix.substring(0, 4);
        final orderNumber = '$shortPrefix-$seq';
        final items = (payload['items'] as List<dynamic>).map(asStringKeyMap).toList();
        final neededByStock = <String, Decimal>{};
        final ingredientByStock = <String, String>{};

        for (final item in items) {
          final productId = readString(item, ['productId']);
          final recipe = recipesByProduct[productId];
          if (recipe == null) {
            continue;
          }
          final qty = money(readString(item, ['quantity'], '1'));
          for (final raw in readList(recipe, ['items'])) {
            final recipeItem = asStringKeyMap(raw);
            final ingredientId = readString(recipeItem, ['ingredient_id', 'ingredientId']);
            if (ingredientId.isEmpty) {
              continue;
            }
            final inventoryId = '${branchId}_$ingredientId';
            final needed = money(readString(recipeItem, ['quantity_base', 'quantityBase'], '0')) * qty;
            neededByStock[inventoryId] = (neededByStock[inventoryId] ?? Decimal.zero) + needed;
            ingredientByStock[inventoryId] = ingredientId;
          }
        }

        final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final inventoryId in neededByStock.keys) {
          stockSnaps[inventoryId] = await tx.get(inventory.doc(inventoryId));
        }

        for (final entry in neededByStock.entries) {
          final stockSnap = stockSnaps[entry.key];
          if (stockSnap == null || !stockSnap.exists) {
            localFailure = Failure('Stock is missing for ${ingredientByStock[entry.key]}.');
            throw localFailure!;
          }
          final stock = asStringKeyMap(stockSnap.data());
          final current = money(readString(stock, ['quantity_base', 'quantityBase'], '0'));
          final next = current - entry.value;
          if (next < Decimal.zero) {
            localFailure = Failure(
              '${readString(stock, ['ingredient_name', 'ingredientName'], ingredientByStock[entry.key] ?? '')} is below available stock.',
            );
            throw localFailure!;
          }
          tx.update(inventory.doc(entry.key), {'quantity_base': moneyString(next)});
          tx.set(transactions.doc(), {
            'branch_id': branchId,
            'ingredient_id': ingredientByStock[entry.key],
            'type': 'SALE',
            'quantity_base': moneyString(entry.value),
            'order_id': idempotencyKey,
            'created_at': FieldValue.serverTimestamp(),
          });
        }

        final record = {
          'id': idempotencyKey,
          'order_number': orderNumber,
          'branch_id': branchId,
          'status': 'COMPLETED',
          'order_type': payload['orderType'] ?? 'TAKEAWAY',
          'customer_name': payload['customerName'],
          'customer_phone': payload['customerPhone'],
          'table_no': payload['tableNo'],
          'note': payload['note'],
          'cashier_name': payload['cashierName'],
          'subtotal': payload['subtotal'],
          'tax': payload['taxAmount'],
          'discount': payload['discountAmount'],
          'total': payload['total'],
          'items': items,
          'payments': payload['payments'],
          'created_by': userId,
          'created_at': FieldValue.serverTimestamp(),
          'idempotency_key': idempotencyKey,
        };
        tx.set(orderRef, record);
        tx.update(businessRef, {'orderSeq': seq});
        return {
          ...record,
          'orderNumber': orderNumber,
        };
      });
      return result;
    } catch (error) {
      if (localFailure != null) {
        throw localFailure!;
      }
      if (error is Failure) {
        rethrow;
      }
      throw mapFirebaseFailure(error);
    }
  }

  Future<void> enqueue(PendingOrder order) {
    return _pending.put(order.idempotencyKey, order.toJson());
  }

  List<PendingOrder> pending() {
    return _pending.values
        .whereType<Map>()
        .map((item) => PendingOrder.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> mark(String key, String status, {String? message}) async {
    final raw = _pending.get(key);
    if (raw is! Map) {
      return;
    }
    final order = PendingOrder.fromJson(Map<String, dynamic>.from(raw));
    order.status = status;
    order.errorMessage = message;
    if (status == 'SYNCED') {
      await _pending.delete(key);
      return;
    }
    await _pending.put(key, order.toJson());
  }

  Future<Map<String, dynamic>> syncPending() async {
    final queued = pending().where((item) => item.status != 'SYNCED').toList();
    if (queued.isEmpty) {
      return {'results': <dynamic>[]};
    }
    final results = <Map<String, dynamic>>[];
    for (final order in queued) {
      await mark(order.idempotencyKey, 'SYNCING');
      try {
        await completeOnline(order.payload);
        await mark(order.idempotencyKey, 'SYNCED');
        results.add({'idempotencyKey': order.idempotencyKey, 'status': 'SYNCED'});
      } on Failure catch (error) {
        await mark(order.idempotencyKey, 'SYNC_FAILED', message: error.message);
        results.add({
          'idempotencyKey': order.idempotencyKey,
          'status': 'SYNC_FAILED',
          'message': error.message,
        });
        if (error.code == 'OFFLINE') {
          rethrow;
        }
      }
    }
    return {'results': results};
  }

  Future<void> cancelOrder(String id) async {
    try {
      if (!(_tenant.permissions.contains(PosPermissions.orderCancel) ||
          _tenant.permissions.contains(PosPermissions.ordersRefund))) {
        throw const Failure('You cannot cancel orders.');
      }
      final businessId = _tenant.requireBusinessId();
      final ref = _firestore.requireDb().collection('businesses').doc(businessId).collection('orders').doc(id);
      final snap = await ref.get();
      if (!snap.exists) throw const Failure('Order was not found.');
      final data = asStringKeyMap(snap.data());
      if (!_tenant.matchesBranch(readString(data, ['branch_id', 'branchId']))) {
        throw const Failure('That order is not in your branch.');
      }
      await ref.set({'status': 'CANCELLED'}, SetOptions(merge: true));
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<List<Map<String, dynamic>>> listOrders() async {
    try {
      final businessId = _tenant.requireBusinessId();
      final col = _firestore.requireDb().collection('businesses').doc(businessId).collection('orders');
      final Query<Map<String, dynamic>> query;
      if (_tenant.selectedBranchId != null) {
        query = col.where('branch_id', isEqualTo: _tenant.selectedBranchId);
      } else if (!_tenant.allowAllBranches) {
        final ids = _tenant.allowedBranchIds;
        if (ids.isEmpty) return [];
        query = ids.length == 1 ? col.where('branch_id', isEqualTo: ids.first) : col.where('branch_id', whereIn: ids.take(30).toList());
      } else {
        query = col;
      }
      final snap = await query.limit(200).get();
      final rows = snap.docs.map((doc) {
        final data = asStringKeyMap(doc.data());
        data['id'] = doc.id;
        data['order_number'] = readString(data, ['order_number', 'orderNumber'], doc.id);
        return data;
      }).toList();
      rows.sort((a, b) {
        final aAt = a['created_at'];
        final bAt = b['created_at'];
        if (aAt is Timestamp && bAt is Timestamp) {
          return bAt.compareTo(aAt);
        }
        return readString(b, ['order_number']).compareTo(readString(a, ['order_number']));
      });
      return rows.where((row) => _tenant.matchesBranch(readString(row, ['branch_id', 'branchId']))).toList();
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }

  Future<Map<String, dynamic>> getOrder(String id) async {
    try {
      final businessId = _tenant.requireBusinessId();
      final snap = await _firestore.requireDb().collection('businesses').doc(businessId).collection('orders').doc(id).get();
      if (!snap.exists) {
        throw const Failure('Order was not found.');
      }
      final data = asStringKeyMap(snap.data());
      data['id'] = snap.id;
      return data;
    } catch (error) {
      throw mapFirebaseFailure(error);
    }
  }
}

Box<dynamic> openPendingBox() => Hive.box(HiveBoxes.pendingOrders);
