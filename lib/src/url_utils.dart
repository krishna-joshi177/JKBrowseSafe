import 'dart:io';

import 'models.dart';

/// Known ad / tracker domains (and their subdomains).
const List<String> trackerHosts = <String>[
  'doubleclick.net', 'googlesyndication.com', 'google-analytics.com',
  'googletagmanager.com', 'googleadservices.com', 'adservice.google.com',
  'facebook.net', 'scorecardresearch.com', 'adnxs.com', 'taboola.com',
  'outbrain.com', 'criteo.com', 'criteo.net', 'hotjar.com', 'quantserve.com',
  'amazon-adsystem.com', 'moatads.com', 'pubmatic.com', 'rubiconproject.com',
  'openx.net', 'adsrvr.org', 'casalemedia.com', 'mixpanel.com',
  'branch.io', 'appsflyer.com', 'mc.yandex.ru',
];

bool isTrackerUrl(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  if (host.isEmpty) return false;
  return trackerHosts.any((d) => host == d || host.endsWith('.$d'));
}

/// File types that can run code or install software.
const Set<String> dangerousExtensions = <String>{
  'apk', 'xapk', 'apks', 'exe', 'msi', 'msix', 'appx', 'bat', 'cmd', 'com',
  'scr', 'ps1', 'vbs', 'js', 'jse', 'wsf', 'jar', 'dll', 'reg', 'lnk', 'hta',
};

final RegExp _hostLike = RegExp(
  r'^(localhost|[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}|\d{1,3}(\.\d{1,3}){3})(:\d+)?([/?#].*)?$',
  caseSensitive: false,
);

/// Turns address-bar text into a URL or a search.
String toUrl(String input, SearchEngine engine) {
  final t = input.trim();
  if (t.isEmpty) return engine.home;
  final lower = t.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('about:')) {
    return t;
  }
  if (!t.contains(' ') && _hostLike.hasMatch(t)) return 'https://$t';
  return engine.searchUrl(t);
}

String hostOf(String url) => Uri.tryParse(url)?.host ?? '';

String originOf(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return url;
  final port = u.hasPort ? ':${u.port}' : '';
  return '${u.scheme}://${u.host}$port';
}

TabErrorKind classifyError(String text) {
  final s = text.toUpperCase();
  const ssl = <String>['SSL', 'CERT'];
  const offline = <String>[
    'INTERNET_DISCONNECTED', 'NOT_CONNECTED_TO_INTERNET', 'HOST_LOOKUP',
    'NAME_NOT_RESOLVED', 'NETWORK_CHANGED', 'DISCONNECTED', 'ADDRESS_UNREACHABLE',
  ];
  if (ssl.any(s.contains)) return TabErrorKind.ssl;
  if (offline.any(s.contains)) return TabErrorKind.offline;
  return TabErrorKind.network;
}

bool isCancelledError(String text) {
  final s = text.toUpperCase();
  return s.contains('CANCEL') || s.contains('ABORTED');
}

Future<bool> hasInternet() async {
  try {
    final r = await InternetAddress.lookup('one.one.one.one')
        .timeout(const Duration(seconds: 3));
    return r.isNotEmpty;
  } catch (_) {
    return false;
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = <String>['KB', 'MB', 'GB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
}

const Map<String, String> _mimeExt = <String, String>{
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'video/mp4': 'mp4',
  'audio/mpeg': 'mp3',
  'application/zip': 'zip',
  'text/plain': 'txt',
  'text/csv': 'csv',
  'application/vnd.android.package-archive': 'apk',
};

/// Picks a safe file name for a download.
String fileNameFor(
    String url, String? suggested, String? contentDisposition, String? mime) {
  String? name = suggested;
  if ((name == null || name.isEmpty) && contentDisposition != null) {
    final m = RegExp(r'''filename\*?=(?:UTF-8'')?["']?([^"';]+)''',
            caseSensitive: false)
        .firstMatch(contentDisposition);
    if (m != null) {
      try {
        name = Uri.decodeComponent(m.group(1)!.trim());
      } catch (_) {
        name = m.group(1)!.trim();
      }
    }
  }
  if (name == null || name.isEmpty) {
    final segs = Uri.tryParse(url)?.pathSegments ?? <String>[];
    name = segs.isNotEmpty && segs.last.isNotEmpty ? segs.last : 'download';
    try {
      name = Uri.decodeComponent(name);
    } catch (_) {}
  }
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  if (name.isEmpty || name == '.' || name == '..') name = 'download';
  if (!name.contains('.') && mime != null) {
    final ext = _mimeExt[mime.split(';').first.trim().toLowerCase()];
    if (ext != null) name = '$name.$ext';
  }
  if (name.length > 120) {
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 && name.length - dot <= 10 ? name.substring(dot) : '';
    name = name.substring(0, 120 - ext.length) + ext;
  }
  return name;
}

String extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
}
