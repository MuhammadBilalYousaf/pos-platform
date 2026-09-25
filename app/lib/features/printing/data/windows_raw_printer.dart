import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WindowsRawPrinter {
  List<String> listPrinters() {
    final needed = calloc<DWORD>();
    final returned = calloc<DWORD>();
    try {
      EnumPrinters(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 4, nullptr, 0, needed, returned);
      if (needed.value == 0) return const [];
      final buffer = calloc<Uint8>(needed.value);
      try {
        final ok = EnumPrinters(
          PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS,
          nullptr,
          4,
          buffer,
          needed.value,
          needed,
          returned,
        );
        if (ok == 0) {
          throw StateError('Could not list printers (${GetLastError()})');
        }
        final names = <String>[];
        final count = returned.value;
        for (var i = 0; i < count; i++) {
          final info = (buffer.cast<PRINTER_INFO_4>() + i).ref;
          if (info.pPrinterName == nullptr) continue;
          final name = info.pPrinterName.toDartString();
          if (name.isNotEmpty) names.add(name);
        }
        names.sort();
        return names;
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(needed);
      calloc.free(returned);
    }
  }

  String? defaultPrinter() {
    final size = calloc<DWORD>();
    try {
      GetDefaultPrinter(Pointer<Utf16>.fromAddress(0), size);
      if (size.value == 0) return null;
      final buffer = calloc<Uint16>(size.value);
      try {
        if (GetDefaultPrinter(buffer.cast<Utf16>(), size) == 0) return null;
        final name = buffer.cast<Utf16>().toDartString().trim();
        return name.isEmpty ? null : name;
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(size);
    }
  }

  void send(String printerName, List<int> bytes) {
    final namePtr = printerName.toNativeUtf16();
    final printer = calloc<IntPtr>();
    final docName = 'POS Receipt'.toNativeUtf16();
    final dataType = 'RAW'.toNativeUtf16();
    final docInfo = calloc<DOC_INFO_1>();
    final written = calloc<DWORD>();
    final data = calloc<Uint8>(bytes.length);
    try {
      if (OpenPrinter(namePtr, printer, nullptr) == 0) {
        throw StateError('Could not open printer "$printerName" (${GetLastError()})');
      }
      docInfo.ref
        ..pDocName = docName
        ..pOutputFile = nullptr
        ..pDatatype = dataType;
      if (StartDocPrinter(printer.value, 1, docInfo) == 0) {
        throw StateError('Printer rejected the receipt job (${GetLastError()})');
      }
      try {
        if (StartPagePrinter(printer.value) == 0) {
          throw StateError('Could not start a printer page (${GetLastError()})');
        }
        for (var i = 0; i < bytes.length; i++) {
          data[i] = bytes[i];
        }
        if (WritePrinter(printer.value, data, bytes.length, written) == 0 || written.value != bytes.length) {
          throw StateError('Could not send receipt bytes (${GetLastError()})');
        }
        EndPagePrinter(printer.value);
      } finally {
        EndDocPrinter(printer.value);
      }
    } finally {
      if (printer.value != 0) ClosePrinter(printer.value);
      calloc.free(data);
      calloc.free(written);
      calloc.free(docInfo);
      calloc.free(docName);
      calloc.free(dataType);
      calloc.free(printer);
      calloc.free(namePtr);
    }
  }
}
