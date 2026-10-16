import 'dart:io';

File? _file;
String? logPath;

Future<void> initFileLog() async {
  final dir = _resolveDir();
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  _file = File('${dir.path}${Platform.pathSeparator}pos_app_log.txt');
  await _file!.writeAsString(
    '\n===== POS start ${DateTime.now().toIso8601String()} =====\n'
    'exe: ${Platform.resolvedExecutable}\n',
    mode: FileMode.append,
    flush: true,
  );
  logPath = _file!.path;
  // ignore: avoid_print
  print('AppLog: ${_file!.path}');
}

Future<void> appendLine(String line) async {
  final file = _file;
  if (file == null) return;
  await file.writeAsString(line, mode: FileMode.append, flush: true);
}

Directory _resolveDir() {
  try {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory('$home${Platform.pathSeparator}Documents${Platform.pathSeparator}POS');
    }
  } catch (_) {}
  try {
    return File(Platform.resolvedExecutable).parent;
  } catch (_) {
    return Directory.current;
  }
}
