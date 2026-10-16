import 'package:flutter/foundation.dart';

import 'app_log_io.dart' if (dart.library.html) 'app_log_stub.dart' as impl;

/// Writes crash / error lines to a text file so release builds can be diagnosed.
///
/// Windows log path:
///   %USERPROFILE%\Documents\POS\pos_app_log.txt
/// Fallback: folder of pos_app.exe\pos_app_log.txt
///
/// On web, file logging is a no-op (console only).
class AppLog {
  AppLog._();

  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    if (kIsWeb) {
      _ready = true;
      return;
    }
    try {
      await impl.initFileLog();
      _ready = true;
    } catch (error) {
      debugPrint('AppLog.init failed: $error');
    }
  }

  static String? get path => impl.logPath;

  static Future<void> info(String message) => _write('INFO', message);

  static Future<void> error(String message, [Object? error, StackTrace? stack]) async {
    final buffer = StringBuffer(message);
    if (error != null) buffer.write('\n  error: $error');
    if (stack != null) buffer.write('\n  stack:\n$stack');
    await _write('ERROR', buffer.toString());
  }

  static Future<void> _write(String level, String message) async {
    final line = '[${DateTime.now().toIso8601String()}] $level  $message\n';
    // ignore: avoid_print
    print(line);
    if (kIsWeb) return;
    try {
      if (!_ready) await init();
      await impl.appendLine(line);
    } catch (_) {}
  }
}
