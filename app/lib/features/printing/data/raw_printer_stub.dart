abstract class RawPrinter {
  List<String> listPrinters();
  String? defaultPrinter();
  String? pluggedInWithoutDriver();
  void send(String printerName, List<int> bytes);
}

class UnsupportedRawPrinter implements RawPrinter {
  const UnsupportedRawPrinter();

  @override
  List<String> listPrinters() => const [];

  @override
  String? defaultPrinter() => null;

  @override
  String? pluggedInWithoutDriver() => null;

  @override
  void send(String printerName, List<int> bytes) {
    throw UnsupportedError('Thermal printing is available on the Windows POS.');
  }
}

RawPrinter createRawPrinter() => const UnsupportedRawPrinter();
