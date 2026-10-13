import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporter.dart';
import 'models.dart';
import 'security.dart';

/// Settings, bookmarks, history, site permissions and saved tabs.
class AppState extends ChangeNotifier {
  AppState._(this._p);
  final SharedPreferences _p;

  static Future<AppState> load() async {
    final s = AppState._(await SharedPreferences.getInstance());
    s._read();
    return s;
  }

  static const int maxHistory = 2000;

  List<Bookmark> bookmarks = <Bookmark>[];
  List<HistoryEntry> history = <HistoryEntry>[];
  Map<String, Map<String, String>> sitePerms = <String, Map<String, String>>{};
  Set<String> jsBlocked = <String>{};
  Set<String> blockedSites = <String>{};
  String engineId = 'ddg';
  ThemeMode themeMode = ThemeMode.system;
  bool forceDarkPages = false;
  bool blockTrackers = true;
  bool httpsOnly = true;
  bool crashLogs = true;
  int textZoom = 100;
  List<Map<String, dynamic>> savedTabs = <Map<String, dynamic>>[];
  int savedCurrent = 0;
  List<Map<String, dynamic>> savedDownloads = <Map<String, dynamic>>[];

  SearchEngine get engine => searchEngines.firstWhere((e) => e.id == engineId,
      orElse: () => searchEngines.first);

  void _read() {
    bookmarks = _list('bookmarks').map(Bookmark.fromJson).toList();
    history = _list('history').map(HistoryEntry.fromJson).toList();
    final sp = _p.getString('sitePerms');
    if (sp != null) {
      try {
        final m = jsonDecode(sp) as Map<String, dynamic>;
        sitePerms = m.map((k, v) =>
            MapEntry(k, Map<String, String>.from(v as Map)));
      } catch (_) {}
    }
    jsBlocked = (_p.getStringList('jsBlocked') ?? const <String>[]).toSet();
    blockedSites =
        (_p.getStringList('blockedSites') ?? const <String>[]).toSet();
    engineId = _p.getString('engine') ?? 'ddg';
    final theme = _p.getString('theme');
    themeMode = ThemeMode.values
        .firstWhere((m) => m.name == theme, orElse: () => ThemeMode.system);
    forceDarkPages = _p.getBool('forceDarkPages') ?? false;
    blockTrackers = _p.getBool('blockTrackers') ?? true;
    httpsOnly = _p.getBool('httpsOnly') ?? true;
    crashLogs = _p.getBool('crashLogs') ?? true;
    textZoom = _p.getInt('textZoom') ?? 100;
    savedTabs = _list('tabs');
    savedCurrent = _p.getInt('currentTab') ?? 0;
    savedDownloads = _list('downloads');
    CrashReporter.enabled = crashLogs;
  }

  List<Map<String, dynamic>> _list(String key) {
    final raw = _p.getString(key);
    if (raw == null) return <Map<String, dynamic>>[];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  void _saveList(String key, List<Map<String, dynamic>> list) =>
      _p.setString(key, jsonEncode(list));

  // ---------------- Bookmarks ----------------
  bool isBookmarked(String url) => bookmarks.any((b) => b.url == url);

  void toggleBookmark(String title, String url) {
    if (!(url.startsWith('http://') || url.startsWith('https://'))) return;
    if (isBookmarked(url)) {
      bookmarks.removeWhere((b) => b.url == url);
    } else {
      bookmarks.insert(0, Bookmark(title: title, url: url));
    }
    _saveBookmarks();
  }

  void updateBookmark(Bookmark b, String title, String url) {
    b.title = title;
    b.url = url;
    _saveBookmarks();
  }

  void removeBookmark(Bookmark b) {
    bookmarks.remove(b);
    _saveBookmarks();
  }

  /// Adds bookmarks that are not already saved. Returns how many were added.
  int importBookmarks(List<Bookmark> items) {
    var added = 0;
    for (final b in items) {
      if (!isBookmarked(b.url)) {
        bookmarks.add(b);
        added++;
      }
    }
    _saveBookmarks();
    return added;
  }

  void _saveBookmarks() {
    _saveList('bookmarks', bookmarks.map((b) => b.toJson()).toList());
    notifyListeners();
  }

  // ---------------- History ----------------
  void addHistory(String title, String url) {
    if (history.isNotEmpty && history.first.url == url) history.removeAt(0);
    history.insert(
        0, HistoryEntry(title: title, url: url, time: DateTime.now()));
    if (history.length > maxHistory) {
      history = history.sublist(0, maxHistory);
    }
    _saveHistory();
  }

  void removeHistory(HistoryEntry e) {
    history.remove(e);
    _saveHistory();
  }

  void clearHistory() {
    history.clear();
    _saveHistory();
  }

  void _saveHistory() {
    _saveList('history', history.map((h) => h.toJson()).toList());
    notifyListeners();
  }

  // ---------------- Site permissions ----------------
  /// Returns 'allow', 'block' or null (ask).
  String? sitePermission(String origin, String key) => sitePerms[origin]?[key];

  void setSitePermission(String origin, String key, String? value) {
    final site = sitePerms.putIfAbsent(origin, () => <String, String>{});
    if (value == null) {
      site.remove(key);
    } else {
      site[key] = value;
    }
    if (site.isEmpty) sitePerms.remove(origin);
    _saveSitePerms();
  }

  void removeSite(String origin) {
    sitePerms.remove(origin);
    _saveSitePerms();
  }

  void clearSitePermissions() {
    sitePerms.clear();
    _saveSitePerms();
  }

  void _saveSitePerms() {
    _p.setString('sitePerms', jsonEncode(sitePerms));
    notifyListeners();
  }

  // ---------------- Per-site JavaScript ----------------
  /// JavaScript is allowed by default on every site.
  bool jsEnabledFor(String host) =>
      host.isEmpty || !jsBlocked.contains(host.toLowerCase());

  void setJsEnabled(String host, bool enabled) {
    final h = host.toLowerCase();
    if (h.isEmpty) return;
    if (enabled) {
      jsBlocked.remove(h);
    } else {
      jsBlocked.add(h);
    }
    _p.setStringList('jsBlocked', jsBlocked.toList());
    notifyListeners();
  }

  // ---------------- Sites blocked by the user ----------------
  bool isUserBlocked(String host) => hostInSet(blockedSites, host);

  void blockSite(String host) {
    final h = host.toLowerCase();
    if (h.isEmpty) return;
    blockedSites.add(h);
    _p.setStringList('blockedSites', blockedSites.toList());
    notifyListeners();
  }

  void unblockSite(String host) {
    blockedSites.remove(host.toLowerCase());
    _p.setStringList('blockedSites', blockedSites.toList());
    notifyListeners();
  }

  // ---------------- Settings ----------------
  void setEngine(String id) {
    engineId = id;
    _p.setString('engine', id);
    notifyListeners();
  }

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _p.setString('theme', m.name);
    notifyListeners();
  }

  void setForceDarkPages(bool v) {
    forceDarkPages = v;
    _p.setBool('forceDarkPages', v);
    notifyListeners();
  }

  void setBlockTrackers(bool v) {
    blockTrackers = v;
    _p.setBool('blockTrackers', v);
    notifyListeners();
  }

  void setHttpsOnly(bool v) {
    httpsOnly = v;
    _p.setBool('httpsOnly', v);
    notifyListeners();
  }

  void setCrashLogs(bool v) {
    crashLogs = v;
    CrashReporter.enabled = v;
    _p.setBool('crashLogs', v);
    notifyListeners();
  }

  void setTextZoom(int v) {
    textZoom = v;
    _p.setInt('textZoom', v);
    notifyListeners();
  }

  // ---------------- Tabs & downloads ----------------
  void saveTabs(List<Map<String, dynamic>> tabs, int current) {
    savedTabs = tabs;
    savedCurrent = current;
    _saveList('tabs', tabs);
    _p.setInt('currentTab', current);
  }

  void saveDownloads(List<Map<String, dynamic>> list) {
    savedDownloads = list;
    _saveList('downloads', list);
  }
}
