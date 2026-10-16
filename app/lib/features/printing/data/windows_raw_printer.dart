import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WindowsRawPrinter {
  List<String> listPrinters() {
    try {
      final needed = calloc<DWORD>();
      final returned = calloc<DWORD>();
      try {
        EnumPrinters(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 4, nullptr, 0, needed, returned);
        if (needed.value == 0) return listComPorts();
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
          if (ok == 0) return listComPorts();
          final names = <String>[];
          final count = returned.value;
          for (var i = 0; i < count; i++) {
            final info = (buffer.cast<PRINTER_INFO_4>() + i).ref;
            if (info.pPrinterName == nullptr) continue;
            final name = info.pPrinterName.toDartString();
            if (name.isNotEmpty) names.add(name);
          }
          names.sort();
          final ports = listComPorts();
          for (final port in ports) {
            if (!names.any((name) => name.toUpperCase() == port.toUpperCase())) {
              names.add(port);
            }
          }
          return names;
        } finally {
          calloc.free(buffer);
        }
      } finally {
        calloc.free(needed);
        calloc.free(returned);
      }
    } catch (_) {
      // Never crash the app from printer discovery (common in release).
      return listComPorts();
    }
  }

  List<String> listComPorts() {
    try {
      final result = Process.runSync('reg', [
        'query',
        r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM',
      ]);
      if (result.exitCode != 0) return const [];
      final ports = <String>{};
      final pattern = RegExp(r'\b(COM\d+)\b', caseSensitive: false);
      for (final match in pattern.allMatches('${result.stdout}')) {
        ports.add(match.group(1)!.toUpperCase());
      }
      final sorted = ports.toList()..sort();
      return sorted;
    } catch (_) {
      return const [];
    }
  }

  String? pluggedInWithoutDriver() {
    try {
      final result = Process.runSync(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          r"Get-PnpDevice -PresentOnly -Class Printer,USB | Where-Object { $_.Status -ne 'OK' -or $_.FriendlyName -match 'print|POS|thermal|receipt|Xprinter|Epson|Gprinter|Rongta|Unknown USB' } | ForEach-Object { $_.Status + '|' + $_.FriendlyName }",
        ],
      );
      if (result.exitCode != 0) return null;
      final lines = '${result.stdout}'.split('\n').map((line) => line.trim()).where((line) => line.contains('|'));
      final problems = <String>[];
      for (final line in lines) {
        final parts = line.split('|');
        final status = parts.first.toLowerCase();
        final name = parts.sublist(1).join('|').trim();
        if (name.isEmpty) continue;
        if (status == 'error' || status == 'unknown' || status == 'degraded') {
          problems.add(name);
        }
      }
      if (problems.isEmpty) return null;
      return 'Windows sees ${problems.join(', ')} but it is not ready (driver missing or USB error). '
          'Unplug/replug the printer, install its Windows driver (or Generic / Text Only), then Scan printers again.';
    } catch (_) {
      return null;
    }
  }

  String? defaultPrinter() {
    try {
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
    } catch (_) {
      return null;
    }
  }

  /// Device path for a Windows COM port (e.g. COM3 → \\.\COM3).
  static String comDevicePath(String printerName) {
    final port = printerName.trim().toUpperCase();
    return '\\\\.\\$port';
  }

  void send(String printerName, List<int> bytes) {
    if (bytes.isEmpty) {
      throw StateError('Receipt is empty — nothing to print.');
    }
    if (RegExp(r'^COM\d+$', caseSensitive: false).hasMatch(printerName.trim())) {
      _sendToPort(comDevicePath(printerName), bytes);
      return;
    }
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

  void _sendToPort(String path, List<int> bytes) {
    final namePtr = path.toNativeUtf16();
    final data = calloc<Uint8>(bytes.length);
    final written = calloc<DWORD>();
    try {
      final handle = CreateFile(
        namePtr,
        GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        0,
      );
      if (handle == 0 || handle == -1) {
        throw StateError('Could not open $path (${GetLastError()})');
      }
      try {
        for (var i = 0; i < bytes.length; i++) {
          data[i] = bytes[i];
        }
        if (WriteFile(handle, data, bytes.length, written, nullptr) == 0 || written.value != bytes.length) {
          throw StateError('Could not write the receipt to $path (${GetLastError()})');
        }
      } finally {
        CloseHandle(handle);
      }
    } finally {
      calloc.free(written);
      calloc.free(data);
      calloc.free(namePtr);
    }
  }
}
