import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'security.dart';
import 'url_utils.dart';

Set<String> _splitLines(String text) =>
    text.split('\n').where((l) => l.isNotEmpty).toSet();

/// Tracker, malware and phishing lists. Downloaded from public sources at
/// most once a day and kept on the device. Your browsing is never sent.
class ThreatLists extends ChangeNotifier {
  ThreatLists._();
  static final ThreatLists instance = ThreatLists._();

  static const String trackerSource =
      'https://raw.githubusercontent.com/disconnectme/disconnect-tracking-protection/master/services.json';
  static const String malwareSource =
      'https://urlhaus.abuse.ch/downloads/hostfile/';
  static const String phishingSource =
      'https://phishing.army/download/phishing_army_blocklist.txt';
  static const Duration maxAge = Duration(hours: 24);

  Set<String> _trackers = <String>{};
  Set<String> _threats = <String>{};
  DateTime? lastUpdated;
  bool updating = false;
  String? lastError;

  /// Increases whenever the lists change.
  int version = 0;
  Directory? _dir;

  int get trackerCount => trackerDomains.length;
  int get threatCount => _threats.length;
  bool get isStale =>
      lastUpdated == null || DateTime.now().difference(lastUpdated!) > maxAge;

  /// Built-in list plus the downloaded list.
  Set<String> get trackerDomains =>
      <String>{...trackerHosts, ..._trackers}..removeAll(neverBlockDomains);

  bool isThreat(String url) => hostInSet(_threats, hostOf(url));

  Future<void> init() async {
    try {
      _dir = await getApplicationSupportDirectory();
      final p = await SharedPreferences.getInstance();
      final ts = p.getInt('lists_updated');
      if (ts != null) lastUpdated = DateTime.fromMillisecondsSinceEpoch(ts);
      _trackers = await _readSet('trackers.txt');
      _threats = await _readSet('threats.txt');
      version++;
    } catch (_) {}
  }

  Future<void> updateIfStale() async {
    if (isStale) await update();
  }

  Future<bool> update() async {
    if (updating) return false;
    updating = true;
    lastError = null;
    notifyListeners();
    var ok = false;
    try {
      final texts = await Future.wait(<Future<String?>>[
        _download(trackerSource),
        _download(malwareSource),
        _download(phishingSource),
      ]);
      final t0 = texts[0];
      if (t0 != null) {
        final trackers = await compute(parseDisconnect, t0);
        if (trackers.length > 100) {
          _trackers = trackers;
          await _writeSet('trackers.txt', trackers);
          ok = true;
        }
      }
      final threats = <String>{};
      final t1 = texts[1];
      final t2 = texts[2];
      if (t1 != null) threats.addAll(await compute(parseHostList, t1));
      if (t2 != null) threats.addAll(await compute(parseHostList, t2));
      if (threats.length > 100) {
        _threats = threats;
        await _writeSet('threats.txt', threats);
        ok = true;
      }
      if (ok) {
        lastUpdated = DateTime.now();
        final p = await SharedPreferences.getInstance();
        await p.setInt('lists_updated', lastUpdated!.millisecondsSinceEpoch);
        version++;
      } else {
        lastError = 'Could not download the lists. Check your connection.';
      }
    } catch (_) {
      lastError = 'Update failed. Try again later.';
    } finally {
      updating = false;
      notifyListeners();
    }
    return ok;
  }

  File? _file(String name) {
    final d = _dir;
    return d == null ? null : File('${d.path}${Platform.pathSeparator}$name');
  }

  Future<Set<String>> _readSet(String name) async {
    final f = _file(name);
    if (f == null || !await f.exists()) return <String>{};
    return compute(_splitLines, await f.readAsString());
  }

  Future<void> _writeSet(String name, Set<String> set) async {
    final f = _file(name);
    if (f == null) return;
    await f.writeAsString(set.join('\n'));
  }

  static Future<String?> _download(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'JKBrowseSafe-lists');
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 60))) {
        bytes.add(chunk);
        if (bytes.length > 40 * 1024 * 1024) return null;
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
