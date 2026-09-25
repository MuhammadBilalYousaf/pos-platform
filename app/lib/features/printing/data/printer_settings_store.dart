import 'package:hive/hive.dart';

class PrinterSettingsStore {
  PrinterSettingsStore(this._box);

  static const _key = 'thermal_printer_name';

  final Box _box;

  String? get selectedPrinter {
    final value = _box.get(_key);
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> save(String? printerName) async {
    final name = printerName?.trim() ?? '';
    if (name.isEmpty) {
      await _box.delete(_key);
      return;
    }
    await _box.put(_key, name);
  }
}
