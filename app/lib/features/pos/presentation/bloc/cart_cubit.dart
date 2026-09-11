import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../../../products/domain/entities/catalog.dart';
import '../../../../core/utils/json_read.dart';
import '../../../../core/utils/order_totals.dart';
import '../../../orders/data/repositories/held_ticket_repository.dart';

class CartLine extends Equatable {
  const CartLine({
    required this.key,
    required this.product,
    required this.variant,
    required this.quantity,
    this.options = const [],
    this.lineDiscount = '0',
    this.note,
  });

  final String key;
  final CatalogProduct product;
  final ProductVariant variant;
  final int quantity;
  final List<ProductOption> options;
  final String lineDiscount;
  final String? note;

  String get extraPrice {
    var total = Decimal.zero;
    for (final option in options) {
      total += money(option.extraPrice);
    }
    return moneyString(total);
  }

  String get displayName {
    final extras = [
      if (variant.name != 'Regular') variant.name,
      ...options.map((item) => item.name),
    ];
    if (extras.isEmpty) {
      return product.name;
    }
    return '${product.name} (${extras.join(', ')})';
  }

  CartLine copyWith({int? quantity, List<ProductOption>? options, String? lineDiscount, String? note}) {
    return CartLine(
      key: key,
      product: product,
      variant: variant,
      quantity: quantity ?? this.quantity,
      options: options ?? this.options,
      lineDiscount: lineDiscount ?? this.lineDiscount,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'product': product.toJson(),
        'variant': variant.toJson(),
        'quantity': quantity,
        'options': options.map((item) => item.toJson()).toList(),
        'lineDiscount': lineDiscount,
        'note': note,
      };

  factory CartLine.fromJson(Map<String, dynamic> json) {
    return CartLine(
      key: readString(json, ['key']),
      product: CatalogProduct.fromJson(asStringKeyMap(json['product'])),
      variant: ProductVariant.fromJson(asStringKeyMap(json['variant'])),
      quantity: readInt(json, ['quantity'], 1),
      options: readList(json, ['options']).map((item) => ProductOption.fromJson(asStringKeyMap(item))).toList(),
      lineDiscount: readString(json, ['lineDiscount'], '0'),
      note: pick(json, ['note'])?.toString(),
    );
  }

  @override
  List<Object?> get props => [key, product, variant, quantity, options, lineDiscount, note];
}

class CartState extends Equatable {
  const CartState({
    required this.lines,
    this.orderDiscount = '0.00',
    this.taxRate = '0',
    this.orderType = 'TAKEAWAY',
    this.customerName,
    this.customerPhone,
    this.tableNo,
    this.note,
    this.heldSnapshot = 0,
  });

  final List<CartLine> lines;
  final String orderDiscount;
  final String taxRate;
  final String orderType;
  final String? customerName;
  final String? customerPhone;
  final String? tableNo;
  final String? note;
  /// Bumped when held-ticket list changes so POS UI rebuilds recall count.
  final int heldSnapshot;

  OrderTotals get totals => calculateOrderTotals(
        lines: lines
            .map(
              (line) => OrderLineInput(
                quantity: line.quantity.toString(),
                unitPrice: line.variant.price,
                extraPrice: line.extraPrice,
                discountAmount: line.lineDiscount,
              ),
            )
            .toList(),
        orderDiscountAmount: orderDiscount,
        taxRate: taxRate,
      );

  bool get isEmpty => lines.isEmpty;

  CartState copyWith({
    List<CartLine>? lines,
    String? orderDiscount,
    String? taxRate,
    String? orderType,
    String? customerName,
    String? customerPhone,
    String? tableNo,
    String? note,
    bool clearCustomer = false,
    int? heldSnapshot,
  }) {
    return CartState(
      lines: lines ?? this.lines,
      orderDiscount: orderDiscount ?? this.orderDiscount,
      taxRate: taxRate ?? this.taxRate,
      orderType: orderType ?? this.orderType,
      customerName: clearCustomer ? null : (customerName ?? this.customerName),
      customerPhone: clearCustomer ? null : (customerPhone ?? this.customerPhone),
      tableNo: tableNo ?? this.tableNo,
      note: note ?? this.note,
      heldSnapshot: heldSnapshot ?? this.heldSnapshot,
    );
  }

  Map<String, dynamic> toJson() => {
        'lines': lines.map((item) => item.toJson()).toList(),
        'orderDiscount': orderDiscount,
        'taxRate': taxRate,
        'orderType': orderType,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'tableNo': tableNo,
        'note': note,
      };

  factory CartState.fromJson(Map<String, dynamic> json) {
    return CartState(
      lines: readList(json, ['lines']).map((item) => CartLine.fromJson(asStringKeyMap(item))).toList(),
      orderDiscount: readString(json, ['orderDiscount'], '0.00'),
      taxRate: readString(json, ['taxRate'], '0'),
      orderType: readString(json, ['orderType'], 'TAKEAWAY'),
      customerName: pick(json, ['customerName'])?.toString(),
      customerPhone: pick(json, ['customerPhone'])?.toString(),
      tableNo: pick(json, ['tableNo'])?.toString(),
      note: pick(json, ['note'])?.toString(),
    );
  }

  @override
  List<Object?> get props => [lines, orderDiscount, taxRate, orderType, customerName, customerPhone, tableNo, note, heldSnapshot];
}

class HeldTicket {
  HeldTicket({required this.id, required this.label, required this.cart, required this.heldAt});

  final String id;
  final String label;
  final CartState cart;
  final DateTime heldAt;
}

class CartCubit extends Cubit<CartState> {
  CartCubit(this._heldBox, this._heldTickets) : super(const CartState(lines: [])) {
    refreshHeldTickets();
  }

  final Box<dynamic> _heldBox;
  final HeldTicketRepository _heldTickets;
  List<HeldTicket> _heldCache = const [];

  Future<void> refreshHeldTickets() async {
    try {
      _heldCache = await _heldTickets.list();
      _syncHiveFromRemote(_heldCache);
    } catch (_) {
      _heldCache = _readHeldFromHive();
    }
    emit(state.copyWith(heldSnapshot: state.heldSnapshot + 1));
  }

  void setTaxRate(String taxRate) => emit(state.copyWith(taxRate: taxRate));

  void setOrderType(String orderType) => emit(state.copyWith(orderType: orderType));

  void setCustomer({String? name, String? phone}) {
    emit(state.copyWith(customerName: name, customerPhone: phone));
  }

  void setTicketMeta({String? tableNo, String? note, String? discount}) {
    emit(state.copyWith(tableNo: tableNo, note: note, orderDiscount: discount ?? state.orderDiscount));
  }

  void addProduct(CatalogProduct product, {ProductVariant? variant, List<ProductOption> options = const []}) {
    if (product.variants.isEmpty) {
      return;
    }
    final selected = variant ?? product.defaultVariant;
    final signature = '${product.id}:${selected.id}:${options.map((item) => item.id).join(',')}';
    final existingIndex = state.lines.indexWhere(
      (line) => '${line.product.id}:${line.variant.id}:${line.options.map((item) => item.id).join(',')}' == signature,
    );
    if (existingIndex >= 0) {
      final lines = [...state.lines];
      lines[existingIndex] = lines[existingIndex].copyWith(quantity: lines[existingIndex].quantity + 1);
      emit(state.copyWith(lines: lines));
      return;
    }
    emit(
      state.copyWith(
        lines: [
          ...state.lines,
          CartLine(
            key: const Uuid().v4(),
            product: product,
            variant: selected,
            quantity: 1,
            options: options,
          ),
        ],
      ),
    );
  }

  void increment(String key) {
    emit(
      state.copyWith(
        lines: state.lines
            .map((line) => line.key == key ? line.copyWith(quantity: line.quantity + 1) : line)
            .toList(),
      ),
    );
  }

  void decrement(String key) {
    emit(
      state.copyWith(
        lines: state.lines
            .map((line) => line.key == key ? line.copyWith(quantity: line.quantity - 1) : line)
            .where((line) => line.quantity > 0)
            .toList(),
      ),
    );
  }

  void remove(String key) {
    emit(state.copyWith(lines: state.lines.where((line) => line.key != key).toList()));
  }

  void setLineDiscount(String key, String amount) {
    emit(
      state.copyWith(
        lines: state.lines.map((line) => line.key == key ? line.copyWith(lineDiscount: amount) : line).toList(),
      ),
    );
  }

  void setDiscount(String amount) => emit(state.copyWith(orderDiscount: amount));

  Future<void> holdTicket() async {
    if (state.isEmpty) {
      return;
    }
    final id = const Uuid().v4();
    final label = state.customerName?.trim().isNotEmpty == true
        ? state.customerName!
        : 'Ticket ${heldTickets.length + 1}';
    final ticket = HeldTicket(id: id, label: label, heldAt: DateTime.now(), cart: state);
    try {
      await _heldTickets.save(ticket);
    } catch (_) {
      await _heldBox.put(id, {
        'id': id,
        'label': label,
        'heldAt': ticket.heldAt.toIso8601String(),
        'cart': state.toJson(),
      });
    }
    await refreshHeldTickets();
    clear();
  }

  List<HeldTicket> get heldTickets => _heldCache;

  List<HeldTicket> _readHeldFromHive() {
    return _heldBox.values.whereType<Map>().map((raw) {
      final json = asStringKeyMap(raw);
      return HeldTicket(
        id: readString(json, ['id']),
        label: readString(json, ['label'], 'Held'),
        heldAt: DateTime.tryParse(readString(json, ['heldAt'])) ?? DateTime.now(),
        cart: CartState.fromJson(asStringKeyMap(json['cart'])),
      );
    }).toList()
      ..sort((a, b) => b.heldAt.compareTo(a.heldAt));
  }

  Future<void> _syncHiveFromRemote(List<HeldTicket> remote) async {
    await _heldBox.clear();
    for (final ticket in remote) {
      await _heldBox.put(ticket.id, {
        'id': ticket.id,
        'label': ticket.label,
        'heldAt': ticket.heldAt.toIso8601String(),
        'cart': ticket.cart.toJson(),
      });
    }
  }

  Future<void> recallTicket(String id) async {
    HeldTicket? ticket;
    for (final item in _heldCache) {
      if (item.id == id) {
        ticket = item;
        break;
      }
    }
    ticket ??= () {
      for (final item in _readHeldFromHive()) {
        if (item.id == id) return item;
      }
      return null;
    }();
    if (ticket == null) return;
    try {
      await _heldTickets.delete(id);
    } catch (_) {}
    await _heldBox.delete(id);
    await refreshHeldTickets();
    emit(ticket.cart.copyWith(taxRate: state.taxRate, heldSnapshot: state.heldSnapshot));
  }

  void clear() => emit(
        CartState(lines: const [], taxRate: state.taxRate, orderType: state.orderType),
      );
}
