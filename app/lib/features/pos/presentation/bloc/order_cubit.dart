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
  const OrderCompleted({required this.message, required this.receipt, this.printed = true});
  final String message;
  final ReceiptData receipt;
  final bool printed;
  @override
  List<Object?> get props => [message, printed, receipt.orderNumber];
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
      lines: command.cart.lines
          .map(
            (line) => ReceiptLine(
              name: line.displayName,
              quantity: line.quantity.toString(),
              unitPrice: line.variant.price,
              lineTotal: command.cart.totals.lineTotals[command.cart.lines.indexOf(line)],
            ),
          )
          .toList(),
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

    var printed = true;
    Object? printError;
    try {
      await _printer.printReceipt(receipt);
    } catch (error) {
      printed = false;
      printError = error;
    }

    if (offline) {
      emit(
        OrderCompleted(
          receipt: receipt,
          message: printed
              ? 'Internet unavailable. Order saved offline.'
              : 'Internet unavailable. Order saved offline. Receipt preview is on screen.',
          printed: printed,
        ),
      );
      return;
    }

    emit(
      OrderCompleted(
        receipt: receipt,
        message: printed
            ? 'Order completed.'
            : 'Order saved. Receipt was not printed. ${printError ?? 'Choose a printer in Receipt Settings.'}',
        printed: printed,
      ),
    );
  }

  void acknowledge() => emit(const OrderIdle());

  Future<void> reprint(ReceiptData receipt) async {
    try {
      await _printer.printReceipt(receipt);
    } catch (_) {}
  }
}
