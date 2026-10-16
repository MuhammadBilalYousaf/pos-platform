import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/firebase/firestore_host.dart';
import '../../../../core/firebase/tenant_context.dart';
import '../../../../core/storage/hive_boxes.dart';
import '../../../../core/utils/json_read.dart';
import '../../../../core/utils/stock_units.dart';
import '../../../../core/utils/order_totals.dart';
import '../../../admin/data/admin_repository.dart';
import '../../../pos/presentation/bloc/cart_cubit.dart';
import '../../../auth/domain/permissions.dart';
import '../../../shifts/data/shift_repository.dart';

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
    final key = json['idempotencyKey'];
    final payload = json['payload'];
    final status = json['status'];
    if (key is! String || key.isEmpty || payload is! Map || status is! String) {
      throw const FormatException('Corrupt pending order entry');
    }
    return PendingOrder(
      idempotencyKey: key,
      payload: Map<String, dynamic>.from(payload),
      status: status,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  /// Soft-parse Hive row; returns null when the entry is corrupt.
  static PendingOrder? tryFromJson(Map<String, dynamic> json) {
    try {
      return PendingOrder.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

class OrderRepository {
  OrderRepository(this._firestore, this._tenant, this._pending, [this._shifts, this._admin]);

  final FirestoreHost _firestore;
  final TenantContext _tenant;
  final Box<dynamic> _pending;
  final ShiftRepository? _shifts;
  final AdminRepository? _admin;

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
      final setupWarnings = <String>[];
      if (_itemsRequireStock(itemsPreview, productsById) &&
          _collectStockNeeds(
            items: itemsPreview,
            branchId: branchId,
            recipesByProduct: recipesByProduct,
            productsById: productsById,
          ).isEmpty) {
        setupWarnings.add(
          'Some items have no recipe/stock link. Order will still be recorded. Open Inventory → Recipes to link ingredients.',
        );
      }

      final shiftMeta = await _resolveShiftMeta(branchId);

      // The Windows Firebase plugin crashes the app inside a transaction.
      // A normal batch write is the same sale without that native call.
      if (!kIsWeb && Platform.isWindows) {
        final result = await _commitSaleWithoutTransaction(
          db: db,
          businessRef: businessRef,
          orderRef: orderRef,
          inventory: inventory,
          transactions: transactions,
          payload: payload,
          businessId: businessId,
          userId: userId,
          branchId: branchId,
          idempotencyKey: idempotencyKey,
          recipesByProduct: recipesByProduct,
          productsById: productsById,
          shiftMeta: shiftMeta,
        );
        final warnings = [...setupWarnings, ...((result['stock_warnings'] as List?)?.map((e) => e.toString()) ?? const [])];
        if (warnings.isNotEmpty) result['stock_warnings'] = warnings;
        return result;
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
          allowShortage: true,
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
          'stock_deducted': stockNeeds.isNotEmpty,
          if (stockResult.warnings.isNotEmpty) 'stock_warnings': stockResult.warnings,
          if (shiftMeta != null) ...shiftMeta,
        };
        tx.set(orderRef, record, SetOptions(merge: false));
        tx.update(businessRef, {'orderSeq': seq});
        // Do not return FieldValue sentinels. The Windows release SDK crashes
        // when a transaction result still contains serverTimestamp().
        return {
          'id': idempotencyKey,
          'business_id': businessId,
          'order_number': orderNumber,
          'orderNumber': orderNumber,
          'branch_id': branchId,
          'status': 'COMPLETED',
          'total': payload['total'],
          if (stockResult.warnings.isNotEmpty) 'stock_warnings': stockResult.warnings,
        };
      });
      final warnings = [...setupWarnings, ...((result['stock_warnings'] as List?)?.map((e) => e.toString()) ?? const [])];
      if (warnings.isNotEmpty) result['stock_warnings'] = warnings;
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

  Future<Map<String, dynamic>?> _resolveShiftMeta(String branchId) async {
    try {
      final shift = await _shifts?.getActiveShift(branchId: branchId);
      if (shift == null) return null;
      return {
        'shift_id': shift.id,
        'business_day': shift.businessDay,
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _commitSaleWithoutTransaction({
    required FirebaseFirestore db,
    required DocumentReference<Map<String, dynamic>> businessRef,
    required DocumentReference<Map<String, dynamic>> orderRef,
    required CollectionReference<Map<String, dynamic>> inventory,
    required CollectionReference<Map<String, dynamic>> transactions,
    required Map<String, dynamic> payload,
    required String businessId,
    required String? userId,
    required String branchId,
    required String idempotencyKey,
    required Map<String, Map<String, dynamic>> recipesByProduct,
    required Map<String, Map<String, dynamic>> productsById,
    Map<String, dynamic>? shiftMeta,
  }) async {
    final existing = await orderRef.get();
    if (existing.exists) {
      final data = asStringKeyMap(existing.data());
      data['id'] = existing.id;
      data['orderNumber'] = readString(data, ['order_number', 'orderNumber']);
      return data;
    }

    final businessSnap = await businessRef.get();
    if (!businessSnap.exists) {
      throw const Failure('Business profile was not found.');
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

    final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final inventoryId in stockNeeds.keys) {
      stockSnaps[inventoryId] = await inventory.doc(inventoryId).get();
    }

    final batch = db.batch();
    final warnings = <String>[];
    for (final need in stockNeeds.values) {
      final stockSnap = stockSnaps[need.inventoryId];
      Decimal current = Decimal.zero;
      var name = need.label;
      if (stockSnap == null || !stockSnap.exists) {
        warnings.add('${need.label}: no inventory record (available 0). Order punched; stock went negative.');
        batch.set(inventory.doc(need.inventoryId), {
          'id': need.inventoryId,
          'branch_id': branchId,
          'ingredient_id': need.ingredientId,
          'ingredient_name': need.label,
          'quantity_base': moneyString(Decimal.zero - need.quantity),
          'unit': 'PCS',
          'reorder_level': '0',
        }, SetOptions(merge: true));
      } else {
        final stock = asStringKeyMap(stockSnap.data());
        current = money(readString(stock, ['quantity_base', 'quantityBase'], '0'));
        name = readString(stock, ['ingredient_name', 'ingredientName'], need.label);
        final next = current - need.quantity;
        if (next < Decimal.zero) {
          warnings.add(
            '$name: need ${moneyString(need.quantity)}, available ${moneyString(current)}. Order punched with shortage.',
          );
        }
        batch.update(inventory.doc(need.inventoryId), {'quantity_base': moneyString(next)});
      }
      batch.set(
        transactions.doc(const Uuid().v4()),
        {
          'branch_id': branchId,
          'inventory_id': need.inventoryId,
          'ingredient_id': need.ingredientId,
          'type': 'SALE',
          'quantity_base': moneyString(need.quantity),
          'order_id': idempotencyKey,
          if (current < need.quantity) 'shortage': true,
          'created_at': Timestamp.fromDate(DateTime.now().toUtc()),
        },
        SetOptions(merge: false),
      );
    }

    batch.set(
      orderRef,
      {
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
        'created_at': Timestamp.fromDate(DateTime.now().toUtc()),
        'idempotency_key': idempotencyKey,
        'stock_deducted': stockNeeds.isNotEmpty,
        if (warnings.isNotEmpty) 'stock_warnings': warnings,
        if (shiftMeta != null) ...shiftMeta,
      },
      SetOptions(merge: false),
    );
    batch.update(businessRef, {'orderSeq': seq});
    await batch.commit();
    return {
      'id': idempotencyKey,
      'business_id': businessId,
      'order_number': orderNumber,
      'orderNumber': orderNumber,
      'branch_id': branchId,
      'status': 'COMPLETED',
      'total': payload['total'],
      if (warnings.isNotEmpty) 'stock_warnings': warnings,
    };
  }

  Future<Map<String, dynamic>> _refundWithoutTransaction({
    required FirebaseFirestore db,
    required DocumentReference<Map<String, dynamic>> orderRef,
    required CollectionReference<Map<String, dynamic>> inventory,
    required CollectionReference<Map<String, dynamic>> transactions,
    required String orderId,
    required String amount,
    required String method,
    required String? reason,
    required bool restoreStock,
    required String? userId,
    required Map<String, Map<String, dynamic>> recipesByProduct,
    required Map<String, Map<String, dynamic>> productsById,
  }) async {
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw const Failure('Order was not found.');
    }
    final order = asStringKeyMap(orderSnap.data());
    final branchId = readString(order, ['branch_id', 'branchId']);
    if (!_tenant.matchesBranch(branchId)) {
      throw const Failure('That order is not in your branch.');
    }
    final status = readString(order, ['status'], 'COMPLETED').toUpperCase();
    if (status != 'COMPLETED' && status != 'PARTIALLY_REFUNDED') {
      throw Failure('Only completed sales can be refunded (status: $status).');
    }

    final orderTotal = money(readString(order, ['total'], '0'));
    final alreadyRefunded = money(readString(order, ['refund_total'], '0'));
    final refundAmount = parseMoneyInputOrThrow(amount, label: 'Refund amount');
    if (refundAmount <= Decimal.zero) {
      throw const Failure('Refund amount must be greater than zero.');
    }
    final remaining = orderTotal - alreadyRefunded;
    if (remaining <= Decimal.zero) {
      throw const Failure('This order is already fully refunded.');
    }
    if (refundAmount > remaining) {
      throw Failure('Refund cannot exceed remaining ${moneyString(remaining)}.');
    }

    final newRefundTotal = alreadyRefunded + refundAmount;
    final isFullRefund = moneyString(newRefundTotal) == moneyString(orderTotal) || newRefundTotal >= orderTotal;
    final newStatus = isFullRefund ? 'REFUNDED' : 'PARTIALLY_REFUNDED';
    final stockReversed = readBool(order, ['stock_reversed']);
    final shouldRestore = restoreStock && isFullRefund && !stockReversed;
    final needs = shouldRestore
        ? _collectStockNeeds(
            items: readList(order, ['items']).map(asStringKeyMap).toList(),
            branchId: branchId,
            recipesByProduct: recipesByProduct,
            productsById: productsById,
          )
        : <String, _StockNeed>{};

    final batch = db.batch();
    final skipped = <String>[];
    for (final need in needs.values) {
      final stockSnap = await inventory.doc(need.inventoryId).get();
      if (!stockSnap.exists) {
        skipped.add(need.label);
        continue;
      }
      final stock = asStringKeyMap(stockSnap.data());
      final next = money(readString(stock, ['quantity_base', 'quantityBase'], '0')) + need.quantity;
      batch.update(inventory.doc(need.inventoryId), {'quantity_base': moneyString(next)});
      batch.set(
        transactions.doc(const Uuid().v4()),
        {
          'branch_id': branchId,
          'inventory_id': need.inventoryId,
          'ingredient_id': need.ingredientId,
          'type': 'SALE_REVERSAL',
          'quantity_base': moneyString(need.quantity),
          'order_id': orderId,
          'reason': 'Refund',
          'created_at': Timestamp.fromDate(DateTime.now().toUtc()),
        },
        SetOptions(merge: false),
      );
    }

    final stockRestored = shouldRestore && skipped.isEmpty;
    final refundRecord = {
      'id': const Uuid().v4(),
      'amount': moneyString(refundAmount),
      'method': method.toUpperCase(),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      'restored_stock': stockRestored,
      if (skipped.isNotEmpty) 'stock_note': 'Stock not restored for: ${skipped.join(', ')}',
      'created_by': userId,
      'created_at': Timestamp.fromDate(DateTime.now().toUtc()),
    };
    final existingRefunds = _cloneRefundEntries(readList(order, ['refunds']).map(asStringKeyMap).toList());
    existingRefunds.add(refundRecord);
    batch.set(
      orderRef,
      {
        'status': newStatus,
        'refund_total': moneyString(newRefundTotal),
        'refunds': existingRefunds,
        'refunded_at': Timestamp.fromDate(DateTime.now().toUtc()),
        'updated_at': Timestamp.fromDate(DateTime.now().toUtc()),
        if (stockRestored) 'stock_reversed': true,
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    return {
      'id': orderId,
      'order_number': readString(order, ['order_number', 'orderNumber']),
      'status': newStatus,
      'refund_total': moneyString(newRefundTotal),
      'last_refund': refundRecord,
    };
  }

  Future<void> enqueue(PendingOrder order) {
    return _pending.put(order.idempotencyKey, order.toJson());
  }

  List<PendingOrder> pending() {
    final result = <PendingOrder>[];
    final corruptKeys = <dynamic>[];
    for (final key in _pending.keys) {
      final raw = _pending.get(key);
      if (raw is! Map) {
        corruptKeys.add(key);
        continue;
      }
      final order = PendingOrder.tryFromJson(Map<String, dynamic>.from(raw));
      if (order == null) {
        corruptKeys.add(key);
        continue;
      }
      result.add(order);
    }
    for (final key in corruptKeys) {
      _pending.delete(key);
    }
    return result;
  }

  Future<void> mark(String key, String status, {String? message}) async {
    final raw = _pending.get(key);
    if (raw is! Map) {
      return;
    }
    final order = PendingOrder.tryFromJson(Map<String, dynamic>.from(raw));
    if (order == null) {
      await _pending.delete(key);
      return;
    }
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
      if (status == 'REFUNDED' || status == 'CANCELLED') {
        throw const Failure('This order is already closed.');
      }
      if (status == 'COMPLETED' || status == 'PARTIALLY_REFUNDED') {
        throw const Failure('A completed sale is reversed with Cancel completed sale, which restores stock. Use Waste when the food was made and thrown away.');
      }
      final stockDeducted = readBool(data, ['stock_deducted']);
      await ref.set({
        'status': 'CANCELLED',
        'cancelled_at': FieldValue.serverTimestamp(),
        'cancelled_by': _tenant.userId,
        'stock_restored': false,
        'cancel_note': stockDeducted ? 'Stock was already deducted.' : 'Stock was not deducted because the sale was not completed.',
      }, SetOptions(merge: true));
    } catch (error) {
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    }
  }

  /// Voids a completed sale and puts recipe stock back when it was deducted.
  /// Does not record a cash refund. Use refund when money goes back to the customer.
  Future<void> cancelCompletedSale(String id) async {
    try {
      if (!(_tenant.permissions.contains(PosPermissions.orderCancel) ||
          _tenant.permissions.contains(PosPermissions.ordersRefund))) {
        throw const Failure('You cannot cancel completed sales.');
      }
      final businessId = _tenant.requireBusinessId();
      final db = _firestore.requireDb();
      final businessRef = db.collection('businesses').doc(businessId);
      final ref = businessRef.collection('orders').doc(id);
      final snap = await ref.get();
      if (!snap.exists) throw const Failure('Order was not found.');
      final data = asStringKeyMap(snap.data());
      if (!_tenant.matchesBranch(readString(data, ['branch_id', 'branchId']))) {
        throw const Failure('That order is not in your branch.');
      }
      final status = readString(data, ['status'], 'COMPLETED').toUpperCase();
      if (status != 'COMPLETED') {
        throw const Failure('Only a completed sale that has not been refunded can be voided this way.');
      }
      if (money(readString(data, ['refund_total'], '0')) > Decimal.zero) {
        throw const Failure('This sale already has a refund. Finish it with refund instead of voiding it.');
      }
      final branchId = readString(data, ['branch_id', 'branchId']);
      final stockDeducted = readBool(data, ['stock_deducted']);
      final alreadyReversed = readBool(data, ['stock_reversed']);
      if (stockDeducted && !alreadyReversed) {
        final recipesByProduct = _indexRecipes((await businessRef.collection('recipes').get()).docs);
        final productsById = _indexProducts((await businessRef.collection('products').get()).docs);
        final needs = _collectStockNeeds(
          items: readList(data, ['items']).map(asStringKeyMap).toList(),
          branchId: branchId,
          recipesByProduct: recipesByProduct,
          productsById: productsById,
        );
        final inventory = businessRef.collection('inventory');
        final transactions = businessRef.collection('inventory_transactions');
        final batch = db.batch();
        for (final need in needs.values) {
          final stockSnap = await inventory.doc(need.inventoryId).get();
          if (!stockSnap.exists) continue;
          final stock = asStringKeyMap(stockSnap.data());
          final current = money(readString(stock, ['quantity_base', 'quantityBase'], '0'));
          final next = current + need.quantity;
          batch.update(inventory.doc(need.inventoryId), {'quantity_base': moneyString(next)});
          batch.set(transactions.doc(const Uuid().v4()), {
            'branch_id': branchId,
            'inventory_id': need.inventoryId,
            'ingredient_id': need.ingredientId,
            'type': 'SALE_REVERSAL',
            'quantity_base': moneyString(need.quantity),
            'order_id': id,
            'reason': 'Completed sale cancelled',
            'created_by': _tenant.userId,
            'created_at': Timestamp.fromDate(DateTime.now().toUtc()),
          });
        }
        batch.set(ref, {
          'status': 'CANCELLED',
          'stock_reversed': true,
          'cancelled_at': Timestamp.fromDate(DateTime.now().toUtc()),
          'cancelled_by': _tenant.userId,
          'cancel_note': 'Completed sale voided and stock restored.',
        }, SetOptions(merge: true));
        await batch.commit();
        return;
      }
      await ref.set({
        'status': 'CANCELLED',
        'stock_reversed': alreadyReversed,
        'cancelled_at': FieldValue.serverTimestamp(),
        'cancelled_by': _tenant.userId,
        'cancel_note': 'Completed sale voided. Stock was not deducted, so nothing was restored.',
      }, SetOptions(merge: true));
    } catch (error) {
      if (error is Failure) rethrow;
      throw mapFirebaseFailure(error);
    }
  }

  /// Cancels a completed (or open) order after verifying the Business Admin cancellation password.
  /// [returnStock] and [refundMoney] are independent; either, both, or neither may be selected.
  Future<Map<String, dynamic>> cancelOrderAuthorized({
    required String orderId,
    required String cancellationPassword,
    required bool returnStock,
    required bool refundMoney,
    String? reason,
    String refundMethod = 'CASH',
  }) async {
    if (!(_tenant.permissions.contains(PosPermissions.orderCancel) ||
        _tenant.permissions.contains(PosPermissions.ordersRefund) ||
        _tenant.permissions.contains(PosPermissions.orderRefund))) {
      throw const Failure('You cannot cancel orders.');
    }
    final admin = _admin;
    if (admin == null) {
      throw const Failure('Cancellation password service is unavailable.');
    }
    await admin.verifyOrderCancellationPassword(cancellationPassword);

    final businessId = _tenant.requireBusinessId();
    final db = _firestore.requireDb();
    final businessRef = db.collection('businesses').doc(businessId);
    final orderRef = businessRef.collection('orders').doc(orderId);
    final snap = await orderRef.get();
    if (!snap.exists) throw const Failure('Order was not found.');
    final order = asStringKeyMap(snap.data());
    final branchId = readString(order, ['branch_id', 'branchId']);
    if (!_tenant.matchesBranch(branchId)) {
      throw const Failure('That order is not in your branch.');
    }
    final status = readString(order, ['status'], 'COMPLETED').toUpperCase();
    if (status == 'CANCELLED' || status == 'REFUNDED') {
      throw const Failure('This order is already closed.');
    }

    final recipesByProduct = _indexRecipes((await businessRef.collection('recipes').get()).docs);
    final productsById = _indexProducts((await businessRef.collection('products').get()).docs);
    final inventory = businessRef.collection('inventory');
    final transactions = businessRef.collection('inventory_transactions');
    final batch = db.batch();
    final now = Timestamp.fromDate(DateTime.now().toUtc());

    var stockReturned = false;
    String? stockNote;
    if (returnStock && readBool(order, ['stock_deducted']) && !readBool(order, ['stock_reversed'])) {
      final needs = _collectStockNeeds(
        items: readList(order, ['items']).map(asStringKeyMap).toList(),
        branchId: branchId,
        recipesByProduct: recipesByProduct,
        productsById: productsById,
      );
      final skipped = <String>[];
      for (final need in needs.values) {
        final stockSnap = await inventory.doc(need.inventoryId).get();
        if (!stockSnap.exists) {
          skipped.add(need.label);
          continue;
        }
        final stock = asStringKeyMap(stockSnap.data());
        final next = money(readString(stock, ['quantity_base', 'quantityBase'], '0')) + need.quantity;
        batch.update(inventory.doc(need.inventoryId), {'quantity_base': moneyString(next)});
        batch.set(transactions.doc(const Uuid().v4()), {
          'branch_id': branchId,
          'inventory_id': need.inventoryId,
          'ingredient_id': need.ingredientId,
          'type': 'SALE_REVERSAL',
          'quantity_base': moneyString(need.quantity),
          'order_id': orderId,
          'reason': 'Order cancelled',
          'created_by': _tenant.userId,
          'created_at': now,
        });
      }
      stockReturned = skipped.isEmpty && needs.isNotEmpty;
      if (skipped.isNotEmpty) stockNote = 'Stock not restored for: ${skipped.join(', ')}';
      if (needs.isEmpty) stockNote = 'No recipe stock was linked to restore.';
    }

    var refundAmount = Decimal.zero;
    final existingRefunds = _cloneRefundEntries(readList(order, ['refunds']).map(asStringKeyMap).toList());
    if (refundMoney) {
      final orderTotal = money(readString(order, ['total'], '0'));
      final already = money(readString(order, ['refund_total'], '0'));
      refundAmount = orderTotal - already;
      if (refundAmount < Decimal.zero) refundAmount = Decimal.zero;
      if (refundAmount > Decimal.zero) {
        existingRefunds.add({
          'id': const Uuid().v4(),
          'amount': moneyString(refundAmount),
          'method': refundMethod.toUpperCase(),
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
          'restored_stock': false,
          'from_cancellation': true,
          'created_by': _tenant.userId,
          'created_at': now,
        });
      }
    }

    final actions = <String>[
      if (returnStock) 'return_stock',
      if (refundMoney) 'refund_money',
      if (!returnStock && !refundMoney) 'neither',
    ];

    batch.set(orderRef, {
      'status': refundMoney && refundAmount > Decimal.zero ? 'REFUNDED' : 'CANCELLED',
      'cancelled_at': now,
      'cancelled_by': _tenant.userId,
      'cancel_reason': reason?.trim(),
      'cancel_actions': actions,
      'cancel_stock_returned': stockReturned,
      'cancel_money_refunded': refundMoney && refundAmount > Decimal.zero,
      if (refundMoney && refundAmount > Decimal.zero) 'refund_total': moneyString(money(readString(order, ['refund_total'], '0')) + refundAmount),
      if (refundMoney && refundAmount > Decimal.zero) 'refunds': existingRefunds,
      if (stockReturned) 'stock_reversed': true,
      if (stockNote != null) 'cancel_stock_note': stockNote,
      'cancel_audit': {
        'by': _tenant.userId,
        'at': now,
        'reason': reason?.trim(),
        'return_stock': returnStock,
        'stock_returned': stockReturned,
        'refund_money': refundMoney,
        'refund_amount': moneyString(refundAmount),
        'actions': actions,
      },
      'updated_at': now,
    }, SetOptions(merge: true));
    await batch.commit();
    return {
      'id': orderId,
      'status': refundMoney && refundAmount > Decimal.zero ? 'REFUNDED' : 'CANCELLED',
      'stock_returned': stockReturned,
      'money_refunded': refundMoney && refundAmount > Decimal.zero,
      'refund_amount': moneyString(refundAmount),
      if (stockNote != null) 'stock_note': stockNote,
    };
  }

  /// Refunds / returns selected line items. Tracks per-line refunded and returned quantities.
  Future<Map<String, dynamic>> refundOrderItems({
    required String orderId,
    required String cancellationPassword,
    required List<Map<String, dynamic>> selections,
    required String method,
    String? reason,
    bool refundMoney = true,
    bool returnStock = false,
  }) async {
    if (!(_tenant.permissions.contains(PosPermissions.ordersRefund) ||
        _tenant.permissions.contains(PosPermissions.orderRefund))) {
      throw const Failure('You do not have permission to refund orders.');
    }
    final admin = _admin;
    if (admin == null) {
      throw const Failure('Cancellation password service is unavailable.');
    }
    await admin.verifyOrderCancellationPassword(cancellationPassword);
    if (selections.isEmpty) {
      throw const Failure('Select at least one item.');
    }

    final businessId = _tenant.requireBusinessId();
    final db = _firestore.requireDb();
    final businessRef = db.collection('businesses').doc(businessId);
    final orderRef = businessRef.collection('orders').doc(orderId);
    final snap = await orderRef.get();
    if (!snap.exists) throw const Failure('Order was not found.');
    final order = asStringKeyMap(snap.data());
    final branchId = readString(order, ['branch_id', 'branchId']);
    if (!_tenant.matchesBranch(branchId)) {
      throw const Failure('That order is not in your branch.');
    }
    final status = readString(order, ['status'], 'COMPLETED').toUpperCase();
    if (status != 'COMPLETED' && status != 'PARTIALLY_REFUNDED') {
      throw Failure('Only completed sales can be item-refunded (status: $status).');
    }

    final items = readList(order, ['items']).map(asStringKeyMap).toList();
    var refundAmount = Decimal.zero;
    final affectedItems = <Map<String, dynamic>>[];
    final stockItems = <Map<String, dynamic>>[];

    for (final selection in selections) {
      final index = selection['index'] is int ? selection['index'] as int : int.tryParse('${selection['index']}') ?? -1;
      final qty = money('${selection['quantity'] ?? '0'}');
      if (index < 0 || index >= items.length) {
        throw const Failure('Invalid item selection.');
      }
      if (qty <= Decimal.zero) {
        throw const Failure('Refund quantity must be greater than zero.');
      }
      final item = Map<String, dynamic>.from(items[index]);
      final ordered = money(readString(item, ['quantity'], '1'));
      final alreadyRefunded = money(readString(item, ['refunded_quantity', 'refundedQuantity'], '0'));
      final remaining = ordered - alreadyRefunded;
      if (qty > remaining) {
        throw Failure(
          '${readString(item, ['productName', 'product_name'], 'Item')}: only ${moneyString(remaining)} left to refund.',
        );
      }
      final lineTotal = money(readString(item, ['lineTotal', 'line_total'], '0'));
      final unitShare = ordered > Decimal.zero
          ? (lineTotal / ordered).toDecimal(scaleOnInfinitePrecision: 4)
          : Decimal.zero;
      final itemRefund = unitShare * qty;
      if (refundMoney) refundAmount += itemRefund;

      item['refunded_quantity'] = moneyString(alreadyRefunded + qty);
      if (returnStock) {
        final alreadyReturned = money(readString(item, ['returned_quantity', 'returnedQuantity'], '0'));
        final returnRemaining = ordered - alreadyReturned;
        if (qty > returnRemaining) {
          throw Failure(
            '${readString(item, ['productName', 'product_name'], 'Item')}: only ${moneyString(returnRemaining)} left to return to stock.',
          );
        }
        item['returned_quantity'] = moneyString(alreadyReturned + qty);
        stockItems.add({
          ...item,
          'quantity': moneyString(qty),
        });
      }
      items[index] = item;
      affectedItems.add({
        'index': index,
        'product_id': readString(item, ['productId', 'product_id']),
        'product_name': readString(item, ['productName', 'product_name']),
        'quantity': moneyString(qty),
        'amount': moneyString(itemRefund),
        'return_stock': returnStock,
      });
    }

    final recipesByProduct = _indexRecipes((await businessRef.collection('recipes').get()).docs);
    final productsById = _indexProducts((await businessRef.collection('products').get()).docs);
    final batch = db.batch();
    final now = Timestamp.fromDate(DateTime.now().toUtc());
    var stockRestored = false;
    if (returnStock && stockItems.isNotEmpty) {
      final needs = _collectStockNeeds(
        items: stockItems,
        branchId: branchId,
        recipesByProduct: recipesByProduct,
        productsById: productsById,
      );
      final inventory = businessRef.collection('inventory');
      final transactions = businessRef.collection('inventory_transactions');
      for (final need in needs.values) {
        final stockSnap = await inventory.doc(need.inventoryId).get();
        if (!stockSnap.exists) continue;
        final stock = asStringKeyMap(stockSnap.data());
        final next = money(readString(stock, ['quantity_base', 'quantityBase'], '0')) + need.quantity;
        batch.update(inventory.doc(need.inventoryId), {'quantity_base': moneyString(next)});
        batch.set(transactions.doc(const Uuid().v4()), {
          'branch_id': branchId,
          'inventory_id': need.inventoryId,
          'ingredient_id': need.ingredientId,
          'type': 'SALE_REVERSAL',
          'quantity_base': moneyString(need.quantity),
          'order_id': orderId,
          'reason': 'Item return',
          'created_by': _tenant.userId,
          'created_at': now,
        });
        stockRestored = true;
      }
    }

    final alreadyRefunded = money(readString(order, ['refund_total'], '0'));
    final newRefundTotal = alreadyRefunded + (refundMoney ? refundAmount : Decimal.zero);
    final orderTotal = money(readString(order, ['total'], '0'));
    final isFull = newRefundTotal >= orderTotal;
    final newStatus = (!refundMoney || refundAmount <= Decimal.zero)
        ? status
        : (isFull ? 'REFUNDED' : 'PARTIALLY_REFUNDED');

    final refunds = _cloneRefundEntries(readList(order, ['refunds']).map(asStringKeyMap).toList());
    final entry = {
      'id': const Uuid().v4(),
      'amount': moneyString(refundMoney ? refundAmount : Decimal.zero),
      'method': method.toUpperCase(),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      'restored_stock': stockRestored,
      'item_level': true,
      'items': affectedItems,
      'created_by': _tenant.userId,
      'created_at': now,
    };
    refunds.add(entry);

    batch.set(orderRef, {
      'items': items,
      'status': newStatus,
      if (refundMoney && refundAmount > Decimal.zero) 'refund_total': moneyString(newRefundTotal),
      'refunds': refunds,
      'refunded_at': now,
      'updated_at': now,
      'item_refund_audit': FieldValue.arrayUnion([
        {
          'by': _tenant.userId,
          'at': now.toDate().toIso8601String(),
          'reason': reason?.trim(),
          'refund_money': refundMoney,
          'return_stock': returnStock,
          'refund_amount': moneyString(refundMoney ? refundAmount : Decimal.zero),
          'items': affectedItems,
        },
      ]),
    }, SetOptions(merge: true));
    await batch.commit();
    return {
      'id': orderId,
      'status': newStatus,
      'refund_total': moneyString(newRefundTotal),
      'last_refund': entry,
    };
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

      if (!kIsWeb && Platform.isWindows) {
        return await _refundWithoutTransaction(
          db: db,
          orderRef: orderRef,
          inventory: inventory,
          transactions: transactions,
          orderId: orderId,
          amount: amount,
          method: method,
          reason: reason,
          restoreStock: restoreStock,
          userId: userId,
          recipesByProduct: recipesByProduct,
          productsById: productsById,
        );
      }

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
          'id': orderId,
          'order_number': readString(order, ['order_number', 'orderNumber']),
          'status': newStatus,
          'refund_total': moneyString(newRefundTotal),
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
      final selectedOptions = readList(item, ['optionIds', 'option_ids']).map((value) => value.toString()).toSet();
      final variantId = readString(item, ['variantId', 'variant_id']);
      var multiplier = Decimal.one;
      if (product != null && variantId.isNotEmpty) {
        for (final raw in readList(product, ['variants'])) {
          final variant = asStringKeyMap(raw);
          if (readString(variant, ['id']) == variantId) {
            final factor = readString(variant, ['recipe_multiplier', 'recipeMultiplier'], '1');
            multiplier = money(factor.isEmpty ? '1' : factor);
            break;
          }
        }
      }
      if (multiplier <= Decimal.zero) multiplier = Decimal.one;

      if (recipe != null) {
        for (final raw in readList(recipe, ['items'])) {
          final recipeItem = asStringKeyMap(raw);
          final ingredientId = readString(recipeItem, ['ingredient_id', 'ingredientId']);
          if (ingredientId.isEmpty) continue;
          final optionId = readString(recipeItem, ['option_id', 'optionId']);
          if (optionId.isNotEmpty && !selectedOptions.contains(optionId)) continue;
          final unit = readString(recipeItem, ['unit'], 'PCS');
          final bySize = recipeItem['variant_quantities'];
          var sizeQty = '';
          if (bySize is Map && variantId.isNotEmpty) {
            final match = bySize[variantId] ?? bySize[variantId.toUpperCase()];
            if (match != null) sizeQty = match.toString();
          }
          final perUnit = StockUnits.toBase(
            sizeQty.isNotEmpty ? sizeQty : readString(recipeItem, ['quantity_base', 'quantityBase'], '0'),
            unit,
          );
          final scale = sizeQty.isNotEmpty ? Decimal.one : multiplier;
          _addStockNeed(
            needs,
            branchId: branchId,
            ingredientId: ingredientId,
            quantity: perUnit * qty * scale,
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
    bool allowShortage = false,
  }) async {
    if (needs.isEmpty) {
      return const _StockApplyResult(complete: true, note: 'No recipe stock linked to this order.');
    }

    final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final inventoryId in needs.keys) {
      stockSnaps[inventoryId] = await tx.get(inventory.doc(inventoryId));
    }

    final skipped = <String>[];
    final warnings = <String>[];
    for (final need in needs.values) {
      final stockSnap = stockSnaps[need.inventoryId];
      if (stockSnap == null || !stockSnap.exists) {
        if (allowShortage && direction == _StockDirection.deduct) {
          warnings.add('${need.label}: no inventory record (available 0). Order punched; stock went negative.');
          tx.set(inventory.doc(need.inventoryId), {
            'id': need.inventoryId,
            'branch_id': branchId,
            'ingredient_id': need.ingredientId,
            'ingredient_name': need.label,
            'quantity_base': moneyString(Decimal.zero - need.quantity),
            'unit': 'PCS',
            'reorder_level': '0',
          }, SetOptions(merge: true));
          tx.set(transactions.doc(const Uuid().v4()), {
            'branch_id': branchId,
            'inventory_id': need.inventoryId,
            'ingredient_id': need.ingredientId,
            'type': 'SALE',
            'quantity_base': moneyString(need.quantity),
            'order_id': orderId,
            'shortage': true,
            'created_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: false));
          continue;
        }
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
      if (next < Decimal.zero && !(allowShortage && direction == _StockDirection.deduct)) {
        final name = readString(stock, ['ingredient_name', 'ingredientName'], need.label);
        final message = '$name is below available stock.';
        if (onError != null) {
          onError(message);
        } else {
          throw Failure(message);
        }
        return const _StockApplyResult(complete: false);
      }
      if (next < Decimal.zero && allowShortage) {
        final name = readString(stock, ['ingredient_name', 'ingredientName'], need.label);
        warnings.add(
          '$name: need ${moneyString(need.quantity)}, available ${moneyString(current)}. Order punched with shortage.',
        );
      }
      tx.update(inventory.doc(need.inventoryId), {'quantity_base': moneyString(next)});
      tx.set(transactions.doc(const Uuid().v4()), {
        'branch_id': branchId,
        'inventory_id': need.inventoryId,
        'ingredient_id': need.ingredientId,
        'type': direction == _StockDirection.deduct ? 'SALE' : 'SALE_REVERSAL',
        'quantity_base': moneyString(need.quantity),
        'order_id': orderId,
        if (direction == _StockDirection.restore) 'reason': 'Refund',
        if (next < Decimal.zero) 'shortage': true,
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: false));
    }

    if (skipped.isNotEmpty) {
      return _StockApplyResult(
        complete: false,
        note: 'Stock not restored for: ${skipped.join(', ')}',
        warnings: warnings,
      );
    }
    return _StockApplyResult(complete: true, warnings: warnings);
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
  const _StockApplyResult({required this.complete, this.note, this.warnings = const []});
  final bool complete;
  final String? note;
  final List<String> warnings;
}

Box<dynamic> openPendingBox() => Hive.box(HiveBoxes.pendingOrders);
