import 'dart:typed_data';

import '../data/printer_settings_store.dart';
import '../data/raw_printer.dart';

/// Customer (priced) vs kitchen (items only) ticket layout.
enum ReceiptKind { customer, kitchen }

/// What to send to the printer after a sale.
enum ReceiptPrintMode {
  both,
  kitchenOnly,
  customerOnly,
  none,
}

extension ReceiptPrintModeX on ReceiptPrintMode {
  String get label => switch (this) {
        ReceiptPrintMode.both => 'Both (kitchen + customer)',
        ReceiptPrintMode.kitchenOnly => 'Kitchen only',
        ReceiptPrintMode.customerOnly => 'Customer only',
        ReceiptPrintMode.none => 'No print',
      };
}

class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.isReturned = false,
    this.note,
  });

  final String name;
  final String quantity;
  final String unitPrice;
  final String lineTotal;
  /// True when this line is a refunded / returned portion.
  final bool isReturned;
  /// e.g. RETURNED, REFUNDED
  final String? note;
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
    this.refundTotal,
    this.originalTotal,
    this.kind = ReceiptKind.customer,
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
  /// Amount already refunded (money). When set, receipt shows original vs net.
  final String? refundTotal;
  /// Original sale total before refunds.
  final String? originalTotal;
  final ReceiptKind kind;

  bool get isKitchen => kind == ReceiptKind.kitchen;

  String get separator => '-' * columns;

  String get titleLine {
    if (isKitchen) return 'KITCHEN';
    final value = header?.trim() ?? '';
    return value.isEmpty ? businessName : value;
  }

  ReceiptData _withKind(ReceiptKind next) {
    if (kind == next) return this;
    return ReceiptData(
      businessName: businessName,
      branchName: branchName,
      address: address,
      phone: phone,
      orderNumber: orderNumber,
      cashierName: cashierName,
      createdAt: createdAt,
      lines: lines,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      paymentMethod: paymentMethod,
      footer: footer,
      header: header,
      paperWidthMm: paperWidthMm,
      showAddress: showAddress,
      showPhone: showPhone,
      orderType: orderType,
      customerName: customerName,
      tableNo: tableNo,
      tendered: tendered,
      change: change,
      refundTotal: refundTotal,
      originalTotal: originalTotal,
      kind: next,
    );
  }

  /// Same order data laid out as a kitchen ticket (no prices).
  ReceiptData asKitchen() => _withKind(ReceiptKind.kitchen);

  /// Same order data laid out as a customer receipt (with prices).
  ReceiptData asCustomer() => _withKind(ReceiptKind.customer);

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
    if (isKitchen) return _kitchenPreviewText();
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
      if (line.isReturned) {
        final tag = (line.note == null || line.note!.isEmpty) ? 'RETURNED' : line.note!;
        buffer.writeln('X ${line.quantity} x ${line.name} [$tag]');
        buffer.writeln('  ${line.unitPrice}    ${line.lineTotal}');
      } else {
        buffer.writeln('${line.quantity} x ${line.name}');
        buffer.writeln('  ${line.unitPrice}    ${line.lineTotal}');
      }
    }
    buffer
      ..writeln(separator)
      ..writeln(_moneyRow('Subtotal', subtotal))
      ..writeln(_moneyRow('Discount', discount))
      ..writeln(_moneyRow('Tax', tax));
    final refunded = refundTotal?.trim() ?? '';
    final original = originalTotal?.trim() ?? '';
    if (refunded.isNotEmpty && refunded != '0' && refunded != '0.00') {
      if (original.isNotEmpty) {
        buffer.writeln(_moneyRow('Original', original));
      }
      buffer.writeln(_moneyRow('Refunded', '-$refunded'));
      buffer.writeln(_moneyRow('NET TOTAL', total));
    } else {
      buffer.writeln(_moneyRow('TOTAL', total));
    }
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

  String _kitchenPreviewText() {
    final buffer = StringBuffer()
      ..writeln('*** KITCHEN ***')
      ..writeln(separator)
      ..writeln('Order: $orderNumber')
      ..writeln('Date: ${createdAt.toLocal()}');
    if (orderType != null && orderType!.isNotEmpty) {
      buffer.writeln('Type: ${_label(orderType!)}');
    }
    if (tableNo != null && tableNo!.isNotEmpty) {
      buffer.writeln('Table: $tableNo');
    }
    if (customerName != null && customerName!.isNotEmpty) {
      buffer.writeln('Customer: $customerName');
    }
    buffer.writeln(separator);
    for (final line in lines) {
      if (line.isReturned) continue;
      buffer.writeln('${line.quantity} x ${line.name}');
    }
    buffer.writeln(separator);
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
  String toString() =>
      'No thermal printer found. Plug in the USB printer, install its Windows driver, then tap Scan printers.';
}

abstract class PrinterService {
  Future<void> printReceipt(ReceiptData receipt);

  /// Prints one or more tickets. Each ticket ends with its own paper cut.
  /// Kitchen is printed before customer when [mode] is [ReceiptPrintMode.both].
  Future<void> printForMode(ReceiptData customerReceipt, ReceiptPrintMode mode);

  Future<List<String>> availablePrinters();
  String? scanWarning();
  String? get configuredPrinter;
  Future<void> configurePrinter(String? name);
}

class EscPosEncoder {
  /// Partial cut after feed — each ticket is its own cut job.
  static const List<int> cutCommand = [0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x41, 0x10];

  Uint8List encode(ReceiptData receipt) {
    if (receipt.isKitchen) return _encodeKitchen(receipt);
    return _encodeCustomer(receipt);
  }

  Uint8List _encodeCustomer(ReceiptData receipt) {
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
      if (item.isReturned) {
        final tag = (item.note == null || item.note!.isEmpty) ? 'RETURNED' : item.note!;
        line(_fit('X ${item.quantity} x ${item.name} [$tag]', receipt.columns));
      } else {
        line(_fit('${item.quantity} x ${item.name}', receipt.columns));
      }
      line(receipt._moneyRow(item.unitPrice, item.lineTotal));
    }
    line(receipt.separator);
    line(receipt._moneyRow('Subtotal', receipt.subtotal));
    line(receipt._moneyRow('Discount', receipt.discount));
    line(receipt._moneyRow('Tax', receipt.tax));
    final refunded = receipt.refundTotal?.trim() ?? '';
    final original = receipt.originalTotal?.trim() ?? '';
    bytes.addAll([0x1B, 0x45, 0x01]);
    if (refunded.isNotEmpty && refunded != '0' && refunded != '0.00') {
      bytes.addAll([0x1B, 0x45, 0x00]);
      if (original.isNotEmpty) line(receipt._moneyRow('Original', original));
      line(receipt._moneyRow('Refunded', '-$refunded'));
      bytes.addAll([0x1B, 0x45, 0x01]);
      line(receipt._moneyRow('NET TOTAL', receipt.total));
    } else {
      line(receipt._moneyRow('TOTAL', receipt.total));
    }
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
    bytes.addAll(cutCommand);
    return Uint8List.fromList(bytes);
  }

  Uint8List _encodeKitchen(ReceiptData receipt) {
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

    line('*** KITCHEN ***');
    bytes.addAll([0x1D, 0x21, 0x00]);
    line(receipt.separator);
    bytes.addAll([0x1B, 0x61, 0x00, 0x1B, 0x45, 0x01]);
    line('Order: ${receipt.orderNumber}');
    bytes.addAll([0x1B, 0x45, 0x00]);
    line('Date: ${_stamp(receipt.createdAt)}');
    if (receipt.orderType != null && receipt.orderType!.isNotEmpty) {
      bytes.addAll([0x1B, 0x45, 0x01]);
      line('Type: ${receipt.orderType!.replaceAll('_', ' ')}');
      bytes.addAll([0x1B, 0x45, 0x00]);
    }
    if (receipt.tableNo != null && receipt.tableNo!.isNotEmpty) {
      bytes.addAll([0x1B, 0x45, 0x01, 0x1D, 0x21, 0x01]);
      line('Table: ${receipt.tableNo}');
      bytes.addAll([0x1D, 0x21, 0x00, 0x1B, 0x45, 0x00]);
    }
    if (receipt.customerName != null && receipt.customerName!.isNotEmpty) {
      line('Customer: ${receipt.customerName}');
    }
    line(receipt.separator);
    // Larger item lines for kitchen staff — no prices.
    bytes.addAll([0x1D, 0x21, 0x01, 0x1B, 0x45, 0x01]);
    for (final item in receipt.lines) {
      if (item.isReturned) continue;
      line(_fit('${item.quantity} x ${item.name}', receipt.columns));
      bytes.add(0x0A);
    }
    bytes.addAll([0x1D, 0x21, 0x00, 0x1B, 0x45, 0x00]);
    line(receipt.separator);
    bytes.addAll(cutCommand);
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
  Future<List<String>> availablePrinters() async {
    _invalidatePrinterCache();
    final printers = _transport.listPrinters();
    final saved = _settings.selectedPrinter;
    if (saved != null && printers.any((name) => name.toLowerCase() == saved.toLowerCase())) {
      return printers;
    }
    final preferred = printers.where((name) => !isVirtualPrinter(name)).toList();
    if (saved == null && preferred.length == 1) {
      await _settings.save(preferred.first);
    }
    return printers;
  }

  @override
  String? scanWarning() => _transport.pluggedInWithoutDriver();

  @override
  Future<void> configurePrinter(String? name) async {
    _invalidatePrinterCache();
    if (name != null && isVirtualPrinter(name)) {
      throw StateError(
        '"$name" is a virtual printer (PDF/XPS/OneNote). '
        'Choose the USB thermal receipt printer instead.',
      );
    }
    await _settings.save(name);
  }

  List<String>? _printerCache;
  DateTime? _printerCacheAt;

  void _invalidatePrinterCache() {
    _printerCache = null;
    _printerCacheAt = null;
  }

  List<String> _cachedPrinters() {
    final now = DateTime.now();
    if (_printerCache != null &&
        _printerCacheAt != null &&
        now.difference(_printerCacheAt!) < const Duration(seconds: 30)) {
      return _printerCache!;
    }
    _printerCache = _transport.listPrinters();
    _printerCacheAt = now;
    return _printerCache!;
  }

  String? _resolvePrinterName(String? configured, List<String> known) {
    if (configured == null || configured.trim().isEmpty) return null;
    for (final name in known) {
      if (name.toLowerCase() == configured.trim().toLowerCase()) return name;
    }
    return null;
  }

  String _requirePrinter() {
    final known = _cachedPrinters();
    var printer = _resolvePrinterName(_settings.selectedPrinter, known);
    if (printer != null && isVirtualPrinter(printer)) {
      printer = null;
    }
    if (printer == null) {
      final preferred = known.where((name) => !isVirtualPrinter(name)).toList();
      printer = preferred.length == 1 ? preferred.first : null;
    }
    if (printer == null || printer.isEmpty) {
      final warning = _transport.pluggedInWithoutDriver();
      if (warning != null) throw StateError(warning);
      throw PrinterNotConfiguredException();
    }
    return printer;
  }

  @override
  Future<void> printReceipt(ReceiptData receipt) async {
    final printer = _requirePrinter();
    if (_settings.selectedPrinter == null) {
      await _settings.save(printer);
    }
    final bytes = _encoder.encode(receipt);
    if (bytes.isEmpty) {
      throw StateError('Receipt encoding produced no data.');
    }
    _transport.send(printer, bytes);
  }

  @override
  Future<void> printForMode(ReceiptData customerReceipt, ReceiptPrintMode mode) async {
    if (mode == ReceiptPrintMode.none) return;

    final jobs = <ReceiptData>[];
    // Kitchen first, then customer — each job ends with its own cut.
    if (mode == ReceiptPrintMode.both || mode == ReceiptPrintMode.kitchenOnly) {
      jobs.add(customerReceipt.asKitchen());
    }
    if (mode == ReceiptPrintMode.both || mode == ReceiptPrintMode.customerOnly) {
      jobs.add(customerReceipt.asCustomer());
    }

    for (var i = 0; i < jobs.length; i++) {
      await printReceipt(jobs[i]);
      if (i < jobs.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }
  }
}

bool isVirtualPrinter(String name) {
  final value = name.toLowerCase();
  return value.contains('pdf') ||
      value.contains('xps') ||
      value.contains('onenote') ||
      value.contains('one note') ||
      value.contains('fax');
}
