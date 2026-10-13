import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class SearchEngine {
  const SearchEngine(this.id, this.name, this.home, this.query);
  final String id;
  final String name;
  final String home;
  final String query;
  String searchUrl(String q) => query.replaceAll('%s', Uri.encodeComponent(q));
}

const List<SearchEngine> searchEngines = <SearchEngine>[
  SearchEngine('ddg', 'DuckDuckGo', 'https://duckduckgo.com',
      'https://duckduckgo.com/?q=%s'),
  SearchEngine('google', 'Google', 'https://www.google.com',
      'https://www.google.com/search?q=%s'),
  SearchEngine('bing', 'Bing', 'https://www.bing.com',
      'https://www.bing.com/search?q=%s'),
  SearchEngine('brave', 'Brave Search', 'https://search.brave.com',
      'https://search.brave.com/search?q=%s'),
  SearchEngine('startpage', 'Startpage', 'https://www.startpage.com',
      'https://www.startpage.com/do/search?q=%s'),
  SearchEngine('ecosia', 'Ecosia', 'https://www.ecosia.org',
      'https://www.ecosia.org/search?q=%s'),
];

enum TabErrorKind {
  none,
  offline,
  network,
  ssl,
  crashed,
  httpsUnavailable,
  dangerous,
}

class BrowserTab {
  BrowserTab({
    required this.url,
    this.title = 'New tab',
    this.incognito = false,
    this.windowId,
    this.openedByPage = false,
  });

  Key key = UniqueKey();
  String url;
  String title;
  final bool incognito;
  int? windowId;
  final bool openedByPage;

  /// The WebView is only created once a tab has been shown (saves memory).
  bool activated = false;
  double progress = 1;
  bool desktopMode = false;

  /// JavaScript state of this tab's WebView (changes per site).
  bool jsEnabled = true;

  /// Times of recent automatic (no tap) cross-site navigations.
  final List<DateTime> autoNavs = <DateTime>[];

  TabErrorKind error = TabErrorKind.none;
  String errorDetail = '';
  String? failedUrl;

  /// Original http:// URL when the HTTPS-only mode upgraded it.
  String? upgradedFrom;
  InAppWebViewController? controller;

  bool get secure =>
      url.startsWith('https://') || url.startsWith('about:') || url.isEmpty;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'url': url, 'title': title, 'desktop': desktopMode};

  static BrowserTab fromJson(Map<String, dynamic> j) => BrowserTab(
        url: (j['url'] as String?) ?? '',
        title: (j['title'] as String?) ?? 'New tab',
      )..desktopMode = j['desktop'] == true;
}

class Bookmark {
  Bookmark({required this.title, required this.url, DateTime? added})
      : added = added ?? DateTime.now();
  String title;
  String url;
  final DateTime added;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'url': url,
        'added': added.toIso8601String(),
      };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        title: (j['title'] as String?) ?? '',
        url: (j['url'] as String?) ?? '',
        added: DateTime.tryParse((j['added'] as String?) ?? ''),
      );
}

class HistoryEntry {
  HistoryEntry({required this.title, required this.url, required this.time});
  final String title;
  final String url;
  final DateTime time;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'url': url,
        'time': time.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        title: (j['title'] as String?) ?? '',
        url: (j['url'] as String?) ?? '',
        time: DateTime.tryParse((j['time'] as String?) ?? '') ?? DateTime.now(),
      );
}
