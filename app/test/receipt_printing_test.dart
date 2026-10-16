import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pos_app/features/printing/data/printer_settings_store.dart';
import 'package:pos_app/features/printing/data/raw_printer_stub.dart';
import 'package:pos_app/features/printing/data/windows_raw_printer.dart';
import 'package:pos_app/features/printing/domain/printer_service.dart';

class _FakeRawPrinter implements RawPrinter {
  _FakeRawPrinter({this.printers = const [], this.warning});

  List<String> printers;
  String? warning;
  final sends = <({String printer, Uint8List bytes})>[];
  Object? sendError;

  @override
  List<String> listPrinters() => List<String>.from(printers);

  @override
  String? defaultPrinter() => printers.isEmpty ? null : printers.first;

  @override
  String? pluggedInWithoutDriver() => warning;

  @override
  void send(String printerName, List<int> bytes) {
    if (sendError != null) throw sendError!;
    sends.add((printer: printerName, bytes: Uint8List.fromList(bytes)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowsRawPrinter.comDevicePath', () {
    test('builds a real Win32 device path (not a raw-string literal)', () {
      expect(WindowsRawPrinter.comDevicePath('com3'), r'\\.\COM3');
      expect(WindowsRawPrinter.comDevicePath(' COM12 '), r'\\.\COM12');
      // Regression: previous code used r'\\.\${...}' and never interpolated.
      expect(WindowsRawPrinter.comDevicePath('COM1'), isNot(contains(r'${')));
    });
  });

  group('EscPosEncoder', () {
    late EscPosEncoder encoder;

    setUp(() => encoder = EscPosEncoder());

    test('emits ESC/POS init, receipt body, feed, and cut', () {
      final receipt = ReceiptData.sample(businessName: 'Turk N Roll');
      final bytes = encoder.encode(receipt);

      expect(bytes, isNotEmpty);
      // ESC @ initialize
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x40);
      // Contains business / order text
      final asLatin1 = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
      expect(asLatin1, contains('Turk N Roll'));
      expect(asLatin1, contains('ORD-1001'));
      expect(asLatin1, contains('TOTAL'));
      // GS V A n — partial cut near the end
      final cut = bytes.sublist(bytes.length - 4);
      expect(cut, [0x1D, 0x56, 0x41, 0x10]);
    });

    test('kitchen ticket has items, no prices, and its own cut', () {
      final kitchen = ReceiptData.sample(businessName: 'Turk N Roll').asKitchen();
      final bytes = encoder.encode(kitchen);
      final asLatin1 = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
      expect(asLatin1, contains('KITCHEN'));
      expect(asLatin1, contains('Sample item'));
      expect(asLatin1, isNot(contains('TOTAL')));
      expect(asLatin1, isNot(contains('250.00')));
      final cut = bytes.sublist(bytes.length - 4);
      expect(cut, [0x1D, 0x56, 0x41, 0x10]);
    });

    test('respects 58mm column width in money rows', () {
      final receipt = ReceiptData.sample(businessName: 'Cafe', paperWidthMm: 58);
      expect(receipt.columns, 32);
      final bytes = encoder.encode(receipt);
      expect(bytes.length, greaterThan(40));
    });
  });

  group('isVirtualPrinter', () {
    test('filters PDF / XPS / OneNote / Fax', () {
      expect(isVirtualPrinter('Microsoft Print to PDF'), isTrue);
      expect(isVirtualPrinter('Microsoft XPS Document Writer'), isTrue);
      expect(isVirtualPrinter('OneNote for Windows 10'), isTrue);
      expect(isVirtualPrinter('Fax'), isTrue);
      expect(isVirtualPrinter('XP-80C'), isFalse);
      expect(isVirtualPrinter('COM3'), isFalse);
      expect(isVirtualPrinter('EPSON TM-T20II'), isFalse);
    });
  });

  group('ThermalPrinterService', () {
    late Directory tempDir;
    late Box box;
    late PrinterSettingsStore settings;
    late _FakeRawPrinter transport;
    late ThermalPrinterService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_printer_test_');
      Hive.init(tempDir.path);
      box = await Hive.openBox('printer_settings_${DateTime.now().microsecondsSinceEpoch}');
      settings = PrinterSettingsStore(box);
      transport = _FakeRawPrinter();
      service = ThermalPrinterService(EscPosEncoder(), settings, transport: transport);
    });

    tearDown(() async {
      await box.clear();
      await box.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('printReceipt sends ESC/POS bytes to the selected thermal printer', () async {
      transport.printers = ['XP-80C', 'Microsoft Print to PDF'];
      await service.configurePrinter('XP-80C');

      await service.printReceipt(ReceiptData.sample(businessName: 'Demo Shop'));

      expect(transport.sends, hasLength(1));
      expect(transport.sends.single.printer, 'XP-80C');
      expect(transport.sends.single.bytes.first, 0x1B);
      expect(transport.sends.single.bytes[1], 0x40);
      final text = String.fromCharCodes(
        transport.sends.single.bytes.where((b) => b >= 32 && b < 127),
      );
      expect(text, contains('Demo Shop'));
    });

    test('printReceipt auto-selects the only non-virtual printer', () async {
      transport.printers = ['Microsoft Print to PDF', 'Rongta RP326', 'Fax'];

      await service.printReceipt(ReceiptData.sample(businessName: 'Auto'));

      expect(settings.selectedPrinter, 'Rongta RP326');
      expect(transport.sends.single.printer, 'Rongta RP326');
    });

    test('printForMode both sends kitchen then customer, each with a cut', () async {
      transport.printers = ['XP-80C'];
      await service.configurePrinter('XP-80C');

      await service.printForMode(
        ReceiptData.sample(businessName: 'Demo Shop'),
        ReceiptPrintMode.both,
      );

      expect(transport.sends, hasLength(2));
      final kitchenText = String.fromCharCodes(
        transport.sends[0].bytes.where((b) => b >= 32 && b < 127),
      );
      final customerText = String.fromCharCodes(
        transport.sends[1].bytes.where((b) => b >= 32 && b < 127),
      );
      expect(kitchenText, contains('KITCHEN'));
      expect(kitchenText, contains('Sample item'));
      expect(kitchenText, isNot(contains('TOTAL')));
      expect(kitchenText, isNot(contains('250.00')));
      expect(customerText, contains('Demo Shop'));
      expect(customerText, contains('TOTAL'));
      expect(customerText, contains('550.00'));
      expect(transport.sends[0].bytes.sublist(transport.sends[0].bytes.length - 4), [0x1D, 0x56, 0x41, 0x10]);
      expect(transport.sends[1].bytes.sublist(transport.sends[1].bytes.length - 4), [0x1D, 0x56, 0x41, 0x10]);
    });

    test('printForMode kitchenOnly sends one kitchen job with cut', () async {
      transport.printers = ['XP-80C'];
      await service.configurePrinter('XP-80C');

      await service.printForMode(
        ReceiptData.sample(businessName: 'Demo Shop'),
        ReceiptPrintMode.kitchenOnly,
      );

      expect(transport.sends, hasLength(1));
      final text = String.fromCharCodes(transport.sends.single.bytes.where((b) => b >= 32 && b < 127));
      expect(text, contains('KITCHEN'));
      expect(text, isNot(contains('TOTAL')));
      expect(transport.sends.single.bytes.sublist(transport.sends.single.bytes.length - 4), [0x1D, 0x56, 0x41, 0x10]);
    });

    test('printForMode customerOnly sends one priced customer job with cut', () async {
      transport.printers = ['XP-80C'];
      await service.configurePrinter('XP-80C');

      await service.printForMode(
        ReceiptData.sample(businessName: 'Demo Shop'),
        ReceiptPrintMode.customerOnly,
      );

      expect(transport.sends, hasLength(1));
      final text = String.fromCharCodes(transport.sends.single.bytes.where((b) => b >= 32 && b < 127));
      expect(text, contains('TOTAL'));
      expect(text, isNot(contains('KITCHEN')));
      expect(transport.sends.single.bytes.sublist(transport.sends.single.bytes.length - 4), [0x1D, 0x56, 0x41, 0x10]);
    });

    test('printForMode none sends nothing', () async {
      transport.printers = ['XP-80C'];
      await service.configurePrinter('XP-80C');

      await service.printForMode(
        ReceiptData.sample(businessName: 'Demo Shop'),
        ReceiptPrintMode.none,
      );

      expect(transport.sends, isEmpty);
    });

    test('printReceipt refuses when only virtual printers exist', () async {
      transport.printers = [
        'Microsoft Print to PDF',
        'Microsoft XPS Document Writer',
        'OneNote for Windows 10',
        'Fax',
      ];

      await expectLater(
        service.printReceipt(ReceiptData.sample(businessName: 'No HW')),
        throwsA(isA<PrinterNotConfiguredException>()),
      );
      expect(transport.sends, isEmpty);
    });

    test('printReceipt surfaces USB/driver warning when no printer configured', () async {
      transport.printers = const [];
      transport.warning = 'Windows sees Unknown USB Device (Port Reset Failed) but it is not ready.';

      await expectLater(
        service.printReceipt(ReceiptData.sample(businessName: 'USB fail')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Unknown USB Device'),
          ),
        ),
      );
    });

    test('configurePrinter rejects virtual printers', () async {
      await expectLater(
        service.configurePrinter('Microsoft Print to PDF'),
        throwsA(isA<StateError>()),
      );
      expect(settings.selectedPrinter, isNull);
    });

    test('printReceipt resolves printer name case-insensitively', () async {
      transport.printers = ['EPSON TM-T20II Receipt'];
      await settings.save('epson tm-t20ii receipt');

      await service.printReceipt(ReceiptData.sample(businessName: 'Case'));

      expect(transport.sends.single.printer, 'EPSON TM-T20II Receipt');
    });

    test('printReceipt ignores a saved virtual printer and requires a real one', () async {
      transport.printers = ['Microsoft Print to PDF', 'XP-58'];
      await box.put('thermal_printer_name', 'Microsoft Print to PDF');

      await service.printReceipt(ReceiptData.sample(businessName: 'Skip PDF'));

      expect(transport.sends.single.printer, 'XP-58');
    });

    test('send errors propagate to the caller', () async {
      transport.printers = ['XP-80C'];
      await service.configurePrinter('XP-80C');
      transport.sendError = StateError('Could not open printer "XP-80C" (5)');

      await expectLater(
        service.printReceipt(ReceiptData.sample(businessName: 'Fail')),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Could not open'))),
      );
    });
  });
}
