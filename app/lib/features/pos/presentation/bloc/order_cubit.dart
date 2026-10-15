import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../orders/data/repositories/order_repository.dart';
import '../../../printing/domain/printer_service.dart';
import 'cart_cubit.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/firebase/firestore_host.dart';

class CompleteSale {
  const CompleteSale({
    required this.branchId,
    required this.cart,
    required this.paymentMethod,
    this.referenceNo,
    this.tendered,
    this.change,
    this.businessName,
    this.branchName,
    this.address,
    this.phone,
    this.cashierName,
    this.header,
    this.footer,
    this.paperWidthMm = 80,
    this.showAddress = true,
    this.showPhone = true,
    this.online = true,
  });

  final String branchId;
  final CartState cart;
  final String paymentMethod;
  final String? referenceNo;
  final String? tendered;
  final String? change;
  final String? businessName;
  final String? branchName;
  final String? address;
  final String? phone;
  final String? cashierName;
  final String? header;
  final String? footer;
  final int paperWidthMm;
  final bool showAddress;
  final bool showPhone;
  final bool online;
}

sealed class OrderState extends Equatable {
  const OrderState();
  @override
  List<Object?> get props => [];
}

class OrderIdle extends OrderState {
  const OrderIdle();
}

class OrderSubmitting extends OrderState {
  const OrderSubmitting();
}

class OrderCompleted extends OrderState {
  const OrderCompleted({
    required this.message,
    required this.receipt,
    this.stockWarnings = const [],
  });
  final String message;
  final ReceiptData receipt;
  final List<String> stockWarnings;
  @override
  List<Object?> get props => [message, receipt.orderNumber, stockWarnings];
}

class OrderPrintIssue extends OrderState {
  const OrderPrintIssue(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class OrderFailure extends OrderState {
  const OrderFailure(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class OrderCubit extends Cubit<OrderState> {
  OrderCubit(this._orders, this._printer) : super(const OrderIdle());

  final OrderRepository _orders;
  final PrinterService _printer;

  Future<void> complete(CompleteSale command) async {
    if (command.cart.isEmpty) {
      emit(const OrderFailure('Add items before taking payment.'));
      return;
    }
    emit(const OrderSubmitting());
    final idempotencyKey = const Uuid().v4();
    final payload = _orders.buildPayload(
      branchId: command.branchId,
      idempotencyKey: idempotencyKey,
      cart: command.cart,
      paymentMethod: command.paymentMethod,
      referenceNo: command.referenceNo,
      tendered: command.tendered,
      change: command.change,
      cashierName: command.cashierName,
    );
    Map<String, dynamic>? order;
    var offline = !command.online;
    try {
      order = await _orders.completeOnline(payload);
    } on Failure catch (error) {
      if (error.code == 'OFFLINE') {
        offline = true;
      } else {
        emit(OrderFailure(error.message));
        return;
      }
    } catch (error) {
      emit(OrderFailure(mapFirebaseFailure(error).message));
      return;
    }
    if (offline) {
      await _orders.enqueue(
        PendingOrder(idempotencyKey: idempotencyKey, payload: payload, status: 'PENDING_SYNC'),
      );
    }

    final receipt = ReceiptData(
      businessName: command.businessName ?? 'POS',
      branchName: command.branchName ?? '',
      address: command.address,
      phone: command.phone,
      orderNumber: order?['order_number'] as String? ?? order?['orderNumber'] as String? ?? 'OFFLINE',
      cashierName: command.cashierName ?? '',
      createdAt: DateTime.now(),
      lines: [
        for (var i = 0; i < command.cart.lines.length; i++)
          ReceiptLine(
            name: command.cart.lines[i].displayName,
            quantity: command.cart.lines[i].quantity.toString(),
            unitPrice: command.cart.lines[i].variant.price,
            lineTotal: command.cart.totals.lineTotals[i],
          ),
      ],
      subtotal: command.cart.totals.subtotal,
      discount: command.cart.totals.discountAmount,
      tax: command.cart.totals.taxAmount,
      total: command.cart.totals.total,
      paymentMethod: command.paymentMethod,
      header: command.header,
      footer: command.footer,
      paperWidthMm: command.paperWidthMm,
      showAddress: command.showAddress,
      showPhone: command.showPhone,
      orderType: command.cart.orderType,
      customerName: command.cart.customerName,
      tableNo: command.cart.tableNo,
      tendered: command.tendered,
      change: command.change,
    );

    final stockWarnings = (order?['stock_warnings'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];

    // Punch completes immediately; printing must not delay the sale UX.
    emit(
      OrderCompleted(
        receipt: receipt,
        stockWarnings: stockWarnings,
        message: offline
            ? 'Internet unavailable. Order saved offline.'
            : stockWarnings.isEmpty
                ? 'Order completed.'
                : 'Order completed with stock warnings.',
      ),
    );

    unawaited(() async {
      try {
        await _printer.printReceipt(receipt);
      } catch (error) {
        if (!isClosed) {
          emit(OrderPrintIssue('Order saved. Receipt was not printed. $error'));
        }
      }
    }());
  }

  void acknowledge() => emit(const OrderIdle());

  Future<void> reprint(ReceiptData receipt) async {
    try {
      await _printer.printReceipt(receipt);
    } catch (error) {
      if (!isClosed) {
        emit(OrderPrintIssue('Reprint failed. $error'));
      }
      rethrow;
    }
  }
}
