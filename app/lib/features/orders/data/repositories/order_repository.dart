import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
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
            'productType': cart.lines[index].product.productType,
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
      final recipesByProduct = _indexRecipes(recipeSnap.docs);
      final productsSnap = await businessRef.collection('products').get();
      final productsById = _indexProducts(productsSnap.docs);

      final itemsPreview = (payload['items'] as List<dynamic>).map(asStringKeyMap).toList();
      if (_itemsRequireStock(itemsPreview, productsById) &&
          _collectStockNeeds(
            items: itemsPreview,
            branchId: branchId,
            recipesByProduct: recipesByProduct,
            productsById: productsById,
          ).isEmpty) {
        throw const Failure(
          'These items need recipes or stock setup. Open Inventory → Recipes and link ingredients for each POS product.',
        );
      }

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
        final stockNeeds = _collectStockNeeds(
          items: items,
          branchId: branchId,
          recipesByProduct: recipesByProduct,
          productsById: productsById,
        );

        final stockResult = await _applyStockDeltaInTransaction(
          tx: tx,
          needs: stockNeeds,
          branchId: branchId,
          orderId: idempotencyKey,
          inventory: inventory,
          transactions: transactions,
          direction: _StockDirection.deduct,
          onError: (message) {
            localFailure = Failure(message);
            throw localFailure!;
          },
        );

        final record = {
          'id': idempotencyKey,
          'business_id': businessId,
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
          'stock_deducted': stockNeeds.isNotEmpty && stockResult.complete,
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
      final status = readString(data, ['status'], 'COMPLETED').toUpperCase();
      if (status == 'COMPLETED' || status == 'PARTIALLY_REFUNDED') {
        throw const Failure('Completed sales must be refunded, not cancelled.');
      }
      if (status == 'REFUNDED' || status == 'CANCELLED') {
        throw const Failure('This order is already closed.');
      }
      await ref.set({'status': 'CANCELLED'}, SetOptions(merge: true));
    } catch (error) {
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    }
  }

  Future<Map<String, dynamic>> refundOrder({
    required String orderId,
    required String amount,
    required String method,
    String? reason,
    bool restoreStock = true,
  }) async {
    if (!(_tenant.permissions.contains(PosPermissions.ordersRefund) ||
        _tenant.permissions.contains(PosPermissions.orderRefund))) {
      throw const Failure('You do not have permission to refund orders.');
    }
    Failure? localFailure;
    try {
      final db = _firestore.requireDb();
      final businessId = _tenant.requireBusinessId();
      final userId = _tenant.userId;
      final businessRef = db.collection('businesses').doc(businessId);
      final orderRef = businessRef.collection('orders').doc(orderId);
      final recipesCol = businessRef.collection('recipes');
      final inventory = businessRef.collection('inventory');
      final transactions = businessRef.collection('inventory_transactions');

      final recipeSnap = await recipesCol.get();
      final recipesByProduct = _indexRecipes(recipeSnap.docs);
      final productsSnap = await businessRef.collection('products').get();
      final productsById = _indexProducts(productsSnap.docs);

      final result = await db.runTransaction((tx) async {
        final orderSnap = await tx.get(orderRef);
        if (!orderSnap.exists) {
          localFailure = const Failure('Order was not found.');
          throw localFailure!;
        }
        final order = asStringKeyMap(orderSnap.data());
        final branchId = readString(order, ['branch_id', 'branchId']);
        if (!_tenant.matchesBranch(branchId)) {
          localFailure = const Failure('That order is not in your branch.');
          throw localFailure!;
        }
        final status = readString(order, ['status'], 'COMPLETED').toUpperCase();
        if (status != 'COMPLETED' && status != 'PARTIALLY_REFUNDED') {
          localFailure = Failure('Only completed sales can be refunded (status: $status).');
          throw localFailure!;
        }

        final orderTotal = money(readString(order, ['total'], '0'));
        final alreadyRefunded = money(readString(order, ['refund_total'], '0'));
        final refundAmount = parseMoneyInputOrThrow(amount, label: 'Refund amount');
        if (refundAmount <= Decimal.zero) {
          localFailure = const Failure('Refund amount must be greater than zero.');
          throw localFailure!;
        }
        final remaining = orderTotal - alreadyRefunded;
        if (remaining <= Decimal.zero) {
          localFailure = const Failure('This order is already fully refunded.');
          throw localFailure!;
        }
        if (refundAmount > remaining) {
          localFailure = Failure('Refund cannot exceed remaining ${moneyString(remaining)}.');
          throw localFailure!;
        }

        final newRefundTotal = alreadyRefunded + refundAmount;
        final isFullRefund = moneyString(newRefundTotal) == moneyString(orderTotal) ||
            newRefundTotal >= orderTotal;
        final newStatus = isFullRefund ? 'REFUNDED' : 'PARTIALLY_REFUNDED';
        final stockReversed = readBool(order, ['stock_reversed']);
        final shouldAttemptStockRestore = restoreStock && isFullRefund && !stockReversed;

        String? stockRestoreNote;
        var stockRestored = false;
        if (shouldAttemptStockRestore) {
          final restore = await _applyStockDeltaInTransaction(
            tx: tx,
            needs: _collectStockNeeds(
              items: readList(order, ['items']).map(asStringKeyMap).toList(),
              branchId: branchId,
              recipesByProduct: recipesByProduct,
              productsById: productsById,
            ),
            branchId: branchId,
            orderId: orderId,
            inventory: inventory,
            transactions: transactions,
            direction: _StockDirection.restore,
            onError: null,
            allowMissing: true,
          );
          stockRestored = restore.complete;
          stockRestoreNote = restore.note;
        }

        final refundId = const Uuid().v4();
        final refundRecord = {
          'id': refundId,
          'amount': moneyString(refundAmount),
          'method': method.toUpperCase(),
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          'restored_stock': stockRestored,
          if (stockRestoreNote != null && stockRestoreNote.isNotEmpty) 'stock_note': stockRestoreNote,
          'created_by': userId,
          'created_at': Timestamp.fromDate(DateTime.now().toUtc()),
        };

        final existingRefunds = _cloneRefundEntries(readList(order, ['refunds']).map(asStringKeyMap).toList());
        existingRefunds.add(refundRecord);

        final update = {
          'status': newStatus,
          'refund_total': moneyString(newRefundTotal),
          'refunds': existingRefunds,
          'refunded_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
          if (stockRestored) 'stock_reversed': true,
        };
        tx.set(orderRef, update, SetOptions(merge: true));

        return {
          ...order,
          ...update,
          'id': orderId,
          'last_refund': refundRecord,
        };
      });
      return result;
    } catch (error) {
      if (localFailure != null) throw localFailure!;
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    }
  }

  Map<String, Map<String, dynamic>> _indexRecipes(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final index = <String, Map<String, dynamic>>{};
    for (final doc in docs) {
      final data = asStringKeyMap(doc.data());
      index[doc.id] = data;
      final productId = readString(data, ['product_id', 'productId'], doc.id);
      if (productId.isNotEmpty) {
        index[productId] = data;
        index[productId.toUpperCase()] = data;
      }
      index[doc.id.toUpperCase()] = data;
    }
    return index;
  }

  Map<String, Map<String, dynamic>> _indexProducts(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final index = <String, Map<String, dynamic>>{};
    for (final doc in docs) {
      final data = asStringKeyMap(doc.data());
      data['id'] = readString(data, ['id'], doc.id);
      index[doc.id] = data;
      final id = readString(data, ['id'], doc.id);
      if (id.isNotEmpty) {
        index[id] = data;
        index[id.toUpperCase()] = data;
      }
      final sku = readString(data, ['sku']);
      if (sku.isNotEmpty) {
        index[sku] = data;
        index[sku.toUpperCase()] = data;
      }
    }
    return index;
  }

  Map<String, dynamic>? _recipeForProduct(String productId, Map<String, Map<String, dynamic>> recipesByProduct) {
    if (productId.isEmpty) return null;
    return recipesByProduct[productId] ??
        recipesByProduct[productId.toUpperCase()] ??
        recipesByProduct[productId.toLowerCase()];
  }

  Map<String, dynamic>? _productForLine(
    Map<String, dynamic> item,
    Map<String, Map<String, dynamic>> productsById,
  ) {
    final productId = readString(item, ['productId', 'product_id']);
    if (productId.isEmpty) return null;
    return productsById[productId] ??
        productsById[productId.toUpperCase()] ??
        productsById[productId.toLowerCase()];
  }

  bool _productTracksStock(Map<String, dynamic>? product, Map<String, dynamic> line) {
    if (readBool(line, ['tracks_inventory', 'tracksInventory'])) return true;
    if (product == null) {
      final type = readString(line, ['productType', 'product_type']).toUpperCase();
      return type == 'RECIPE';
    }
    if (readBool(product, ['tracks_inventory'])) return true;
    final type = readString(product, ['product_type', 'productType']).toUpperCase();
    return type == 'RECIPE';
  }

  bool _itemsRequireStock(
    List<Map<String, dynamic>> items,
    Map<String, Map<String, dynamic>> productsById,
  ) {
    for (final item in items) {
      if (_productTracksStock(_productForLine(item, productsById), item)) {
        return true;
      }
    }
    return false;
  }

  void _addStockNeed(
    Map<String, _StockNeed> needs,
    {
    required String branchId,
    required String ingredientId,
    required Decimal quantity,
    required String label,
  }) {
    final normalized = ingredientId.trim().toUpperCase();
    if (normalized.isEmpty || quantity <= Decimal.zero) return;
    final inventoryId = '${branchId}_$normalized';
    final existing = needs[inventoryId];
    needs[inventoryId] = _StockNeed(
      inventoryId: inventoryId,
      ingredientId: normalized,
      quantity: (existing?.quantity ?? Decimal.zero) + quantity,
      label: existing?.label ?? label,
    );
  }

  Map<String, _StockNeed> _collectStockNeeds({
    required List<Map<String, dynamic>> items,
    required String branchId,
    required Map<String, Map<String, dynamic>> recipesByProduct,
    required Map<String, Map<String, dynamic>> productsById,
  }) {
    final needs = <String, _StockNeed>{};
    for (final item in items) {
      final productId = readString(item, ['productId', 'product_id']);
      if (productId.isEmpty) continue;
      final qty = money(readString(item, ['quantity'], '1'));
      final product = _productForLine(item, productsById);
      final recipe = _recipeForProduct(productId, recipesByProduct);

      if (recipe != null) {
        for (final raw in readList(recipe, ['items'])) {
          final recipeItem = asStringKeyMap(raw);
          final ingredientId = readString(recipeItem, ['ingredient_id', 'ingredientId']);
          if (ingredientId.isEmpty) continue;
          final perUnit = money(readString(recipeItem, ['quantity_base', 'quantityBase'], '0'));
          _addStockNeed(
            needs,
            branchId: branchId,
            ingredientId: ingredientId,
            quantity: perUnit * qty,
            label: ingredientId,
          );
        }
        continue;
      }

      if (!_productTracksStock(product, item)) continue;

      // Finished-good fallback: one stock unit per item sold (SKU / product id).
      final sku = product == null ? productId : readString(product, ['sku'], productId);
      final fallbackId = sku.isNotEmpty ? sku : productId;
      _addStockNeed(
        needs,
        branchId: branchId,
        ingredientId: fallbackId,
        quantity: qty,
        label: product == null
            ? readString(item, ['productName', 'product_name'], productId)
            : readString(product, ['name'], readString(item, ['productName', 'product_name'], productId)),
      );
    }
    return needs;
  }

  List<Map<String, dynamic>> _cloneRefundEntries(List<Map<String, dynamic>> entries) {
    return [
      for (final entry in entries)
        {
          'id': readString(entry, ['id']),
          'amount': readString(entry, ['amount']),
          'method': readString(entry, ['method']),
          if (readString(entry, ['reason']).isNotEmpty) 'reason': readString(entry, ['reason']),
          'restored_stock': readBool(entry, ['restored_stock']),
          if (readString(entry, ['stock_note']).isNotEmpty) 'stock_note': readString(entry, ['stock_note']),
          'created_by': readString(entry, ['created_by', 'createdBy']),
          'created_at': entry['created_at'] is Timestamp
              ? entry['created_at']
              : Timestamp.fromDate(DateTime.now().toUtc()),
        },
    ];
  }

  Future<_StockApplyResult> _applyStockDeltaInTransaction({
    required Transaction tx,
    required Map<String, _StockNeed> needs,
    required String branchId,
    required String orderId,
    required CollectionReference<Map<String, dynamic>> inventory,
    required CollectionReference<Map<String, dynamic>> transactions,
    required _StockDirection direction,
    void Function(String message)? onError,
    bool allowMissing = false,
  }) async {
    if (needs.isEmpty) {
      return const _StockApplyResult(complete: true, note: 'No recipe stock linked to this order.');
    }

    final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final inventoryId in needs.keys) {
      stockSnaps[inventoryId] = await tx.get(inventory.doc(inventoryId));
    }

    final skipped = <String>[];
    for (final need in needs.values) {
      final stockSnap = stockSnaps[need.inventoryId];
        if (stockSnap == null || !stockSnap.exists) {
        if (allowMissing) {
          skipped.add(need.label);
          continue;
        }
        final message = 'Stock is missing for ${need.label}.';
        if (onError != null) {
          onError(message);
        } else {
          throw Failure(message);
        }
        return const _StockApplyResult(complete: false);
      }
      final stock = asStringKeyMap(stockSnap.data());
      final current = money(readString(stock, ['quantity_base', 'quantityBase'], '0'));
      final next = direction == _StockDirection.deduct ? current - need.quantity : current + need.quantity;
      if (next < Decimal.zero) {
        final name = readString(stock, ['ingredient_name', 'ingredientName'], need.label);
        final message = '$name is below available stock.';
        if (onError != null) {
          onError(message);
        } else {
          throw Failure(message);
        }
        return const _StockApplyResult(complete: false);
      }
      tx.update(inventory.doc(need.inventoryId), {'quantity_base': moneyString(next)});
      tx.set(transactions.doc(), {
        'branch_id': branchId,
        'inventory_id': need.inventoryId,
        'ingredient_id': need.ingredientId,
        'type': direction == _StockDirection.deduct ? 'SALE' : 'SALE_REVERSAL',
        'quantity_base': moneyString(need.quantity),
        'order_id': orderId,
        if (direction == _StockDirection.restore) 'reason': 'Refund',
        'created_at': FieldValue.serverTimestamp(),
      });
    }

    if (skipped.isNotEmpty) {
      return _StockApplyResult(
        complete: false,
        note: 'Stock not restored for: ${skipped.join(', ')}',
      );
    }
    return const _StockApplyResult(complete: true);
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

enum _StockDirection { deduct, restore }

class _StockNeed {
  const _StockNeed({
    required this.inventoryId,
    required this.ingredientId,
    required this.quantity,
    required this.label,
  });

  final String inventoryId;
  final String ingredientId;
  final Decimal quantity;
  final String label;
}

class _StockApplyResult {
  const _StockApplyResult({required this.complete, this.note});
  final bool complete;
  final String? note;
}

Box<dynamic> openPendingBox() => Hive.box(HiveBoxes.pendingOrders);
