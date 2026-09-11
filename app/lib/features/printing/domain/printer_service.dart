import 'dart:typed_data';

class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String name;
  final String quantity;
  final String unitPrice;
  final String lineTotal;
}

class ReceiptData {
  const ReceiptData({
    required this.businessName,
    required this.branchName,
    required this.orderNumber,
    required this.cashierName,
    required this.createdAt,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paymentMethod,
    this.address,
    this.phone,
    this.footer,
    this.header,
    this.paperWidthMm = 80,
    this.showAddress = true,
    this.showPhone = true,
    this.orderType,
    this.customerName,
    this.tableNo,
    this.tendered,
    this.change,
  });

  final String businessName;
  final String branchName;
  final String? address;
  final String? phone;
  final String orderNumber;
  final String cashierName;
  final DateTime createdAt;
  final List<ReceiptLine> lines;
  final String subtotal;
  final String discount;
  final String tax;
  final String total;
  final String paymentMethod;
  final String? footer;
  final String? header;
  final int paperWidthMm;
  final bool showAddress;
  final bool showPhone;
  final String? orderType;
  final String? customerName;
  final String? tableNo;
  final String? tendered;
  final String? change;

  String get separator => paperWidthMm <= 58 ? '----------------' : '--------------------------------';

  String get titleLine {
    final value = header?.trim() ?? '';
    return value.isEmpty ? businessName : value;
  }

  factory ReceiptData.sample({
    required String businessName,
    String branchName = 'Main branch',
    String? header,
    String? address,
    String? phone,
    String? footer,
    int paperWidthMm = 80,
    bool showAddress = true,
    bool showPhone = true,
  }) {
    return ReceiptData(
      businessName: businessName,
      branchName: branchName,
      header: header,
      address: address,
      phone: phone,
      footer: footer,
      paperWidthMm: paperWidthMm,
      showAddress: showAddress,
      showPhone: showPhone,
      orderNumber: 'ORD-1001',
      cashierName: 'Sample cashier',
      createdAt: DateTime.now(),
      lines: const [
        ReceiptLine(name: 'Sample item', quantity: '2', unitPrice: '250.00', lineTotal: '500.00'),
        ReceiptLine(name: 'Addon', quantity: '1', unitPrice: '50.00', lineTotal: '50.00'),
      ],
      subtotal: '550.00',
      discount: '0.00',
      tax: '0.00',
      total: '550.00',
      paymentMethod: 'CASH',
      tendered: '600.00',
      change: '50.00',
      orderType: 'dine_in',
    );
  }

  String toPreviewText() {
    final buffer = StringBuffer();
    buffer.writeln(titleLine);
    if (branchName.isNotEmpty) buffer.writeln(branchName);
    if (showAddress && address != null && address!.isNotEmpty) buffer.writeln(address);
    if (showPhone && phone != null && phone!.isNotEmpty) buffer.writeln(phone);
    buffer
      ..writeln(separator)
      ..writeln('Order: $orderNumber')
      ..writeln('Date: ${createdAt.toLocal()}')
      ..writeln('Cashier: $cashierName');
    if (orderType != null && orderType!.isNotEmpty) {
      buffer.writeln('Type: $orderType');
    }
    if (customerName != null && customerName!.isNotEmpty) {
      buffer.writeln('Customer: $customerName');
    }
    if (tableNo != null && tableNo!.isNotEmpty) {
      buffer.writeln('Table: $tableNo');
    }
    buffer
      ..writeln('Paid: $paymentMethod')
      ..writeln(separator);
    for (final line in lines) {
      buffer.writeln('${line.quantity} x ${line.name}');
      buffer.writeln('  ${line.unitPrice}    ${line.lineTotal}');
    }
    buffer
      ..writeln(separator)
      ..writeln('Subtotal     $subtotal')
      ..writeln('Discount     $discount')
      ..writeln('Tax          $tax')
      ..writeln('TOTAL        $total');
    if (tendered != null && tendered!.isNotEmpty) {
      buffer.writeln('Tendered     $tendered');
    }
    if (change != null && change!.isNotEmpty) {
      buffer.writeln('Change       $change');
    }
    if (footer != null && footer!.isNotEmpty) {
      buffer.writeln(footer);
    }
    return buffer.toString();
  }
}

abstract class PrinterService {
  Future<void> printReceipt(ReceiptData receipt);
}

class EscPosEncoder {
  Uint8List encode(ReceiptData receipt) {
    final bytes = <int>[
      0x1B, 0x40, // initialize
      0x1B, 0x61, 0x01, // center
    ];
    void line(String text) {
      bytes.addAll(text.codeUnits);
      bytes.addAll([0x0A]);
    }

    line(receipt.titleLine);
    if (receipt.branchName.isNotEmpty) {
      line(receipt.branchName);
    }
    if (receipt.showAddress && receipt.address != null && receipt.address!.isNotEmpty) {
      line(receipt.address!);
    }
    if (receipt.showPhone && receipt.phone != null && receipt.phone!.isNotEmpty) {
      line(receipt.phone!);
    }
    bytes.addAll([0x1B, 0x61, 0x00]);
    line(receipt.separator);
    line('Order: ${receipt.orderNumber}');
    line('Date: ${receipt.createdAt.toLocal()}');
    line('Cashier: ${receipt.cashierName}');
    line(receipt.separator);
    for (final item in receipt.lines) {
      line('${item.quantity} x ${item.name}');
      line('  ${item.unitPrice}    ${item.lineTotal}');
    }
    line(receipt.separator);
    line('Subtotal     ${receipt.subtotal}');
    line('Discount     ${receipt.discount}');
    line('Tax          ${receipt.tax}');
    line('TOTAL        ${receipt.total}');
    line('Paid         ${receipt.paymentMethod}');
    line(receipt.separator);
    if (receipt.footer != null && receipt.footer!.trim().isNotEmpty) {
      bytes.addAll([0x1B, 0x61, 0x01]);
      line(receipt.footer!);
    }
    bytes.addAll([0x0A, 0x0A, 0x1D, 0x56, 0x41, 0x10]);
    return Uint8List.fromList(bytes);
  }
}

class PreviewPrinterService implements PrinterService {
  PreviewPrinterService(this._encoder);
  final EscPosEncoder _encoder;
  Uint8List? lastBytes;

  @override
  Future<void> printReceipt(ReceiptData receipt) async {
    lastBytes = _encoder.encode(receipt);
  }
}
