import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'constants.dart';

/// Privacy-respecting crash log.
/// - Stored only on this device; nothing is uploaded automatically.
/// - Web addresses, e-mail addresses and user folder names are removed.
/// - The user can view, share or delete the log from Settings.
class CrashReporter {
  static bool enabled = true;
  static File? _file;
  static const int _maxBytes = 200 * 1024;

  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}crash_log.txt');
    } catch (_) {
      _file = null;
    }
  }

  static String redact(String input) => input
      .replaceAll(
          RegExp(r"""(https?|wss?|ftp|file|blob|data|content):[^\s'")\]]+""",
              caseSensitive: false),
          '<url>')
      .replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '<email>')
      .replaceAllMapped(
          RegExp(r'([A-Za-z]:\\Users\\)[^\\\s]+', caseSensitive: false),
          (m) => '${m.group(1)}<user>')
      .replaceAll(RegExp(r'/home/[^/\s]+'), '/home/<user>');

  static Future<void> record(Object error, StackTrace? stack) async {
    final f = _file;
    if (!enabled || f == null) return;
    try {
      final entry = StringBuffer()
        ..writeln('--- ${DateTime.now().toUtc().toIso8601String()} | '
            '$appName $appVersion | ${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion}')
        ..writeln(redact(error.toString()))
        ..writeln(redact((stack ?? StackTrace.empty).toString()));
      if (await f.exists() && await f.length() > _maxBytes) {
        final old = await f.readAsString();
        await f.writeAsString(old.substring(old.length ~/ 2));
      }
      await f.writeAsString(entry.toString(), mode: FileMode.append);
    } catch (_) {
      // Never let crash logging crash the app.
    }
  }

  static Future<String> read() async {
    final f = _file;
    if (f == null || !await f.exists()) return '';
    return f.readAsString();
  }

  static Future<void> clear() async {
    final f = _file;
    if (f != null && await f.exists()) await f.delete();
  }
}
