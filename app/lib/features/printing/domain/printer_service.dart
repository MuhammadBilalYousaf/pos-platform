import 'dart:typed_data';

import '../data/printer_settings_store.dart';
import '../data/raw_printer.dart';

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

  String get separator => '-' * columns;

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
      buffer.writeln('Type: ${_label(orderType!)}');
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
      ..writeln(_moneyRow('Subtotal', subtotal))
      ..writeln(_moneyRow('Discount', discount))
      ..writeln(_moneyRow('Tax', tax))
      ..writeln(_moneyRow('TOTAL', total));
    if (tendered != null && tendered!.isNotEmpty) {
      buffer.writeln(_moneyRow('Tendered', tendered!));
    }
    if (change != null && change!.isNotEmpty) {
      buffer.writeln(_moneyRow('Change', change!));
    }
    if (footer != null && footer!.isNotEmpty) {
      buffer.writeln(footer);
    }
    return buffer.toString();
  }

  int get columns => paperWidthMm <= 58 ? 32 : 48;

  String _moneyRow(String label, String amount) {
    final width = columns;
    final gap = width - label.length - amount.length;
    if (gap < 1) return '$label $amount';
    return '$label${' ' * gap}$amount';
  }

  String _label(String value) => value.replaceAll('_', ' ');
}

class PrinterNotConfiguredException implements Exception {
  @override
  String toString() => 'No thermal printer selected. Choose one in Receipt Settings.';
}

abstract class PrinterService {
  Future<void> printReceipt(ReceiptData receipt);
  Future<List<String>> availablePrinters();
  String? get configuredPrinter;
  Future<void> configurePrinter(String? name);
}

class EscPosEncoder {
  Uint8List encode(ReceiptData receipt) {
    final bytes = <int>[
      0x1B, 0x40,
      0x1B, 0x74, 0x00,
      0x1B, 0x61, 0x01,
      0x1B, 0x45, 0x01,
      0x1D, 0x21, 0x11,
    ];
    void line(String text) {
      bytes.addAll(_latin1(text));
      bytes.add(0x0A);
    }

    line(receipt.titleLine);
    bytes.addAll([0x1D, 0x21, 0x00, 0x1B, 0x45, 0x00]);
    if (receipt.branchName.isNotEmpty) line(receipt.branchName);
    if (receipt.showAddress && receipt.address != null && receipt.address!.isNotEmpty) {
      line(receipt.address!);
    }
    if (receipt.showPhone && receipt.phone != null && receipt.phone!.isNotEmpty) {
      line(receipt.phone!);
    }
    bytes.addAll([0x1B, 0x61, 0x00]);
    line(receipt.separator);
    line('Order: ${receipt.orderNumber}');
    line('Date: ${_stamp(receipt.createdAt)}');
    line('Cashier: ${receipt.cashierName}');
    if (receipt.orderType != null && receipt.orderType!.isNotEmpty) {
      line('Type: ${receipt.orderType!.replaceAll('_', ' ')}');
    }
    if (receipt.customerName != null && receipt.customerName!.isNotEmpty) {
      line('Customer: ${receipt.customerName}');
    }
    if (receipt.tableNo != null && receipt.tableNo!.isNotEmpty) {
      line('Table: ${receipt.tableNo}');
    }
    line('Paid: ${receipt.paymentMethod}');
    line(receipt.separator);
    for (final item in receipt.lines) {
      line(_fit('${item.quantity} x ${item.name}', receipt.columns));
      line(receipt._moneyRow(item.unitPrice, item.lineTotal));
    }
    line(receipt.separator);
    line(receipt._moneyRow('Subtotal', receipt.subtotal));
    line(receipt._moneyRow('Discount', receipt.discount));
    line(receipt._moneyRow('Tax', receipt.tax));
    bytes.addAll([0x1B, 0x45, 0x01]);
    line(receipt._moneyRow('TOTAL', receipt.total));
    bytes.addAll([0x1B, 0x45, 0x00]);
    if (receipt.tendered != null && receipt.tendered!.isNotEmpty) {
      line(receipt._moneyRow('Tendered', receipt.tendered!));
    }
    if (receipt.change != null && receipt.change!.isNotEmpty) {
      line(receipt._moneyRow('Change', receipt.change!));
    }
    if (receipt.footer != null && receipt.footer!.trim().isNotEmpty) {
      line(receipt.separator);
      bytes.addAll([0x1B, 0x61, 0x01]);
      for (final part in receipt.footer!.split('\n')) {
        if (part.trim().isNotEmpty) line(part.trim());
      }
    }
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x41, 0x10]);
    return Uint8List.fromList(bytes);
  }

  List<int> _latin1(String text) {
    return text.runes.map((rune) => rune <= 0xFF ? rune : 0x3F).toList();
  }

  String _fit(String text, int width) {
    if (text.length <= width) return text;
    return text.substring(0, width);
  }

  String _stamp(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class ThermalPrinterService implements PrinterService {
  ThermalPrinterService(this._encoder, this._settings, {RawPrinter? transport})
      : _transport = transport ?? createRawPrinter();

  final EscPosEncoder _encoder;
  final PrinterSettingsStore _settings;
  final RawPrinter _transport;

  @override
  String? get configuredPrinter => _settings.selectedPrinter;

  @override
  Future<List<String>> availablePrinters() async => _transport.listPrinters();

  @override
  Future<void> configurePrinter(String? name) => _settings.save(name);

  @override
  Future<void> printReceipt(ReceiptData receipt) async {
    final printer = _settings.selectedPrinter ?? _transport.defaultPrinter();
    if (printer == null || printer.isEmpty) throw PrinterNotConfiguredException();
    _transport.send(printer, _encoder.encode(receipt));
  }
}
