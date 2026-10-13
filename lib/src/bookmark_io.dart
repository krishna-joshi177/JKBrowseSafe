import 'dart:convert';

import 'models.dart';

/// Exports bookmarks in the Netscape HTML format used by
/// Chrome, Edge, Brave and Firefox.
String exportBookmarksHtml(List<Bookmark> bookmarks) {
  const esc = HtmlEscape();
  final b = StringBuffer()
    ..writeln('<!DOCTYPE NETSCAPE-Bookmark-file-1>')
    ..writeln('<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">')
    ..writeln('<TITLE>Bookmarks</TITLE>')
    ..writeln('<H1>Bookmarks</H1>')
    ..writeln('<DL><p>');
  for (final bm in bookmarks) {
    final secs = bm.added.millisecondsSinceEpoch ~/ 1000;
    b.writeln('    <DT><A HREF="${esc.convert(bm.url)}" ADD_DATE="$secs">'
        '${esc.convert(bm.title)}</A>');
  }
  b.writeln('</DL><p>');
  return b.toString();
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&#x2F;', '/')
    .replaceAll('&#47;', '/');

bool _isWebUrl(String u) => u.startsWith('http://') || u.startsWith('https://');

/// Reads Netscape HTML (from any major browser) or a JSON list of
/// {"title": ..., "url": ...}. Only http/https links are imported.
List<Bookmark> parseBookmarks(String text) {
  final out = <Bookmark>[];
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('[')) {
    try {
      for (final e in (jsonDecode(trimmed) as List).whereType<Map>()) {
        final url = '${e['url'] ?? ''}'.trim();
        if (_isWebUrl(url)) {
          out.add(Bookmark(title: '${e['title'] ?? url}', url: url));
        }
      }
    } catch (_) {}
    return out;
  }
  final re = RegExp(r'<A\s[^>]*?HREF\s*=\s*"([^"]*)"[^>]*>(.*?)</A>',
      caseSensitive: false, dotAll: true);
  for (final m in re.allMatches(text)) {
    final url = _unescape(m.group(1)!.trim());
    final title =
        _unescape(m.group(2)!.replaceAll(RegExp(r'<[^>]*>'), '').trim());
    if (_isWebUrl(url)) {
      out.add(Bookmark(title: title.isEmpty ? url : title, url: url));
    }
  }
  return out;
}
