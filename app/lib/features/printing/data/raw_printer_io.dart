import 'dart:io';

import 'raw_printer_stub.dart';
import 'windows_raw_printer.dart';

export 'raw_printer_stub.dart' show RawPrinter, UnsupportedRawPrinter;

class _WindowsRawPrinter implements RawPrinter {
  final WindowsRawPrinter _printer = WindowsRawPrinter();

  @override
  List<String> listPrinters() => _printer.listPrinters();

  @override
  String? defaultPrinter() => _printer.defaultPrinter();

  @override
  void send(String printerName, List<int> bytes) => _printer.send(printerName, bytes);
}

RawPrinter createRawPrinter() {
  if (Platform.isWindows) return _WindowsRawPrinter();
  return const UnsupportedRawPrinter();
}
