import 'package:flutter_test/flutter_test.dart';
import 'package:safe_browser/src/bookmark_io.dart';
import 'package:safe_browser/src/models.dart';
import 'package:safe_browser/src/url_utils.dart';

void main() {
  final ddg = searchEngines.first;

  test('address bar turns domains into https URLs', () {
    expect(toUrl('example.com', ddg), 'https://example.com');
    expect(toUrl('example.com/a?b=1', ddg), 'https://example.com/a?b=1');
    expect(toUrl('localhost:8080', ddg), 'https://localhost:8080');
    expect(toUrl('https://x.org', ddg), 'https://x.org');
  });

  test('address bar turns text into a search', () {
    expect(toUrl('flutter tabs', ddg), 'https://duckduckgo.com/?q=flutter%20tabs');
    expect(toUrl('3.5', ddg), startsWith('https://duckduckgo.com/?q='));
  });

  test('tracker detection includes subdomains only', () {
    expect(isTrackerUrl('https://stats.g.doubleclick.net/x'), isTrue);
    expect(isTrackerUrl('https://notdoubleclick.net/x'), isFalse);
  });

  test('download file names are safe', () {
    expect(fileNameFor('https://a.com/f/report.pdf', null, null, null), 'report.pdf');
    expect(fileNameFor('https://a.com/x', null, 'attachment; filename="a:b.txt"', null), 'a_b.txt');
    expect(fileNameFor('https://a.com/', null, null, 'application/pdf'), 'download.pdf');
  });

  test('bookmarks survive export and import', () {
    final html = exportBookmarksHtml([Bookmark(title: 'A & B', url: 'https://a.com/?x=1&y=2')]);
    final back = parseBookmarks(html);
    expect(back.single.title, 'A & B');
    expect(back.single.url, 'https://a.com/?x=1&y=2');
    expect(parseBookmarks('<A HREF="javascript:alert(1)">x</A>'), isEmpty);
  });
}
