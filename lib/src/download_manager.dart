import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';

enum DownloadStatus { running, done, failed, cancelled }

class DownloadItem {
  DownloadItem({required this.url, required this.fileName});
  final String url;
  String fileName;
  String? path;
  int received = 0;
  int? total;
  DownloadStatus status = DownloadStatus.running;
  String? error;
  bool cancelled = false;
  HttpClient? client;

  double? get fraction =>
      (total != null && total! > 0) ? received / total! : null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'fileName': fileName,
        'path': path,
        'size': received,
      };
}

class DownloadManager extends ChangeNotifier {
  DownloadManager(this._state) {
    for (final j in _state.savedDownloads) {
      final path = j['path'] as String?;
      if (path == null || !File(path).existsSync()) continue;
      items.add(DownloadItem(
          url: (j['url'] as String?) ?? '',
          fileName: (j['fileName'] as String?) ?? 'download')
        ..path = path
        ..received = (j['size'] as int?) ?? 0
        ..status = DownloadStatus.done);
    }
  }

  final AppState _state;
  final List<DownloadItem> items = <DownloadItem>[];

  /// Windows: the user's Downloads folder.
  /// Android: the app's own Downloads folder (no storage permission needed).
  static Future<Directory> downloadDirectory() async {
    Directory? d;
    try {
      d = await getDownloadsDirectory();
    } catch (_) {}
    if (d == null && Platform.isAndroid) {
      try {
        d = await getExternalStorageDirectory();
      } catch (_) {}
    }
    d ??= await getApplicationDocumentsDirectory();
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  String _uniquePath(Directory dir, String name) {
    final sep = Platform.pathSeparator;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var path = '${dir.path}$sep$name';
    var i = 1;
    while (File(path).existsSync()) {
      path = '${dir.path}$sep$base ($i)$ext';
      i++;
    }
    return path;
  }

  Future<void> start({
    required String url,
    required String fileName,
    String? userAgent,
    String? cookieHeader,
  }) async {
    final item = DownloadItem(url: url, fileName: fileName);
    items.insert(0, item);
    notifyListeners();
    try {
      final dir = await downloadDirectory();
      final path = _uniquePath(dir, fileName);
      item.path = path;
      item.fileName = path.split(Platform.pathSeparator).last;
      final uri = Uri.parse(url);

      if (uri.scheme == 'data') {
        final bytes = UriData.fromUri(uri).contentAsBytes();
        await File(path).writeAsBytes(bytes);
        item.received = bytes.length;
        item.total = bytes.length;
        item.status = DownloadStatus.done;
      } else {
        final client = HttpClient();
        item.client = client;
        final req = await client.getUrl(uri);
        if (userAgent != null && userAgent.isNotEmpty) {
          req.headers.set(HttpHeaders.userAgentHeader, userAgent);
        }
        if (cookieHeader != null && cookieHeader.isNotEmpty) {
          req.headers.set(HttpHeaders.cookieHeader, cookieHeader);
        }
        final res = await req.close();
        if (res.statusCode >= 400) {
          throw HttpException('Server returned ${res.statusCode}');
        }
        item.total = res.contentLength > 0 ? res.contentLength : null;
        final sink = File(path).openWrite();
        var last = DateTime.now();
        try {
          await for (final chunk in res) {
            if (item.cancelled) break;
            sink.add(chunk);
            item.received += chunk.length;
            if (DateTime.now().difference(last).inMilliseconds > 250) {
              last = DateTime.now();
              notifyListeners();
            }
          }
        } finally {
          await sink.close();
          client.close();
        }
        item.status =
            item.cancelled ? DownloadStatus.cancelled : DownloadStatus.done;
      }
    } catch (e) {
      if (!item.cancelled) {
        item.status = DownloadStatus.failed;
        item.error = e.toString();
      }
    }
    if (item.status != DownloadStatus.done && item.path != null) {
      try {
        await File(item.path!).delete();
      } catch (_) {}
    }
    item.client = null;
    _persist();
    notifyListeners();
  }

  void cancel(DownloadItem item) {
    item.cancelled = true;
    item.status = DownloadStatus.cancelled;
    item.client?.close(force: true);
    notifyListeners();
  }

  Future<void> deleteFile(DownloadItem item) async {
    if (item.path != null) {
      try {
        await File(item.path!).delete();
      } catch (_) {}
    }
    remove(item);
  }

  void remove(DownloadItem item) {
    items.remove(item);
    _persist();
    notifyListeners();
  }

  void clearFinished() {
    items.removeWhere((d) => d.status != DownloadStatus.running);
    _persist();
    notifyListeners();
  }

  void _persist() {
    _state.saveDownloads(items
        .where((d) => d.status == DownloadStatus.done)
        .take(200)
        .map((d) => d.toJson())
        .toList());
  }
}
