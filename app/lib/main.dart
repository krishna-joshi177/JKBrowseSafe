import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SafeBrowseApp());
}

const String kHome = 'https://duckduckgo.com';
const String kSearch = 'https://duckduckgo.com/?q=';

/// Known ad/tracker domains blocked in every tab.
const List<String> kBlockedHosts = [
  'doubleclick.net', 'googlesyndication.com', 'google-analytics.com',
  'googletagmanager.com', 'adservice.google.com', 'facebook.net',
  'scorecardresearch.com', 'adnxs.com', 'taboola.com', 'outbrain.com',
  'criteo.com', 'hotjar.com', 'quantserve.com', 'amazon-adsystem.com',
];

class SafeBrowseApp extends StatelessWidget {
  const SafeBrowseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SafeBrowse',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
        darkTheme: ThemeData(
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.dark,
            useMaterial3: true),
        home: const BrowserPage(),
      );
}

class BrowserTab {
  BrowserTab({required this.url, this.incognito = false});
  final Key key = UniqueKey();
  String url;
  String title = 'New tab';
  double progress = 0;
  bool incognito;
  bool secure = true;
  InAppWebViewController? controller;
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final List<BrowserTab> _tabs = [BrowserTab(url: kHome)];
  int _current = 0;
  final _address = TextEditingController();
  List<Map<String, String>> _bookmarks = [];
  List<Map<String, String>> _history = [];
  int _blockedCount = 0;

  BrowserTab get tab => _tabs[_current];

  @override
  void initState() {
    super.initState();
    _loadData();
    _address.text = kHome;
  }

  Future<void> _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _bookmarks = _decode(p.getString('bookmarks'));
      _history = _decode(p.getString('history'));
    });
  }

  List<Map<String, String>> _decode(String? s) => s == null
      ? []
      : (jsonDecode(s) as List).map((e) => Map<String, String>.from(e)).toList();

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('bookmarks', jsonEncode(_bookmarks));
    await p.setString('history', jsonEncode(_history.take(500).toList()));
  }

  String _toUrl(String input) {
    final t = input.trim();
    if (t.isEmpty) return kHome;
    if (t.startsWith('http://')) return t.replaceFirst('http://', 'https://');
    if (t.startsWith('https://')) return t;
    if (!t.contains(' ') && t.contains('.')) return 'https://$t';
    return '$kSearch${Uri.encodeComponent(t)}';
  }

  void _go(String input) {
    final url = _toUrl(input);
    tab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    FocusScope.of(context).unfocus();
  }

  bool _isBlocked(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return kBlockedHosts.any((d) => host == d || host.endsWith('.$d'));
  }

  void _newTab({bool incognito = false}) => setState(() {
        _tabs.add(BrowserTab(url: kHome, incognito: incognito));
        _current = _tabs.length - 1;
        _address.text = kHome;
      });

  void _closeTab(int i) => setState(() {
        if (_tabs.length == 1) {
          _tabs[0] = BrowserTab(url: kHome);
        } else {
          _tabs.removeAt(i);
        }
        _current = _current.clamp(0, _tabs.length - 1);
        _address.text = tab.url;
      });

  void _switchTab(int i) => setState(() {
        _current = i;
        _address.text = tab.url;
      });

  Widget _buildWebView(BrowserTab t) => InAppWebView(
        key: t.key,
        initialUrlRequest: URLRequest(url: WebUri(t.url)),
        initialSettings: InAppWebViewSettings(
          incognito: t.incognito,
          cacheEnabled: !t.incognito,
          javaScriptEnabled: true,
          useShouldOverrideUrlLoading: true,
          useShouldInterceptRequest: true,
          safeBrowsingEnabled: true,
          thirdPartyCookiesEnabled: false,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
          supportMultipleWindows: false,
          contentBlockers: kBlockedHosts
              .map((d) => ContentBlocker(
                    trigger: ContentBlockerTrigger(
                        urlFilter: '.*${d.replaceAll('.', r'\.')}/.*'),
                    action: ContentBlockerAction(
                        type: ContentBlockerActionType.BLOCK),
                  ))
              .toList(),
        ),
        onWebViewCreated: (c) => t.controller = c,
        onLoadStart: (c, url) => setState(() {
          t.url = url.toString();
          t.secure = url?.scheme == 'https';
          if (t == tab) _address.text = t.url;
        }),
        onLoadStop: (c, url) async {
          final title = await c.getTitle() ?? t.url;
          setState(() => t.title = title);
          if (!t.incognito && url != null) {
            _history.insert(0, {
              'title': title,
              'url': url.toString(),
              'time': DateTime.now().toIso8601String(),
            });
            _save();
          }
        },
        onProgressChanged: (c, p) => setState(() => t.progress = p / 100),
        onTitleChanged: (c, title) =>
            setState(() => t.title = title ?? t.title),
        shouldOverrideUrlLoading: (c, action) async {
          final url = action.request.url.toString();
          if (_isBlocked(url)) {
            setState(() => _blockedCount++);
            return NavigationActionPolicy.CANCEL;
          }
          if (url.startsWith('http://')) {
            c.loadUrl(
                urlRequest: URLRequest(
                    url: WebUri(url.replaceFirst('http://', 'https://'))));
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        shouldInterceptRequest: (c, req) async {
          if (_isBlocked(req.url.toString())) {
            _blockedCount++;
            return WebResourceResponse(data: null, statusCode: 403);
          }
          return null;
        },
        onPermissionRequest: (c, req) async {
          final ok = await _confirm('Permission request',
              '${req.origin} wants: ${req.resources.map((r) => r.toString()).join(', ')}');
          return PermissionResponse(
              resources: req.resources,
              action: ok
                  ? PermissionResponseAction.GRANT
                  : PermissionResponseAction.DENY);
        },
        onReceivedServerTrustAuthRequest: (c, challenge) async =>
            ServerTrustAuthResponse(
                action: ServerTrustAuthResponseAction.CANCEL),
      );

  Future<bool> _confirm(String title, String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Block')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Allow')),
          ],
        ),
      ) ??
      false;

  bool get _isBookmarked => _bookmarks.any((b) => b['url'] == tab.url);

  void _toggleBookmark() {
    setState(() {
      if (_isBookmarked) {
        _bookmarks.removeWhere((b) => b['url'] == tab.url);
      } else {
        _bookmarks.add({'title': tab.title, 'url': tab.url});
      }
    });
    _save();
  }

  Future<void> _clearData() async {
    await CookieManager.instance().deleteAllCookies();
    await InAppWebViewController.clearAllCache();
    setState(() => _history.clear());
    _save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Browsing data cleared')));
    }
  }

  void _showList(String title, List<Map<String, String>> items,
      {bool deletable = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(title,
                    style: Theme.of(context).textTheme.titleLarge)),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Nothing here yet'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: const Icon(Icons.public),
                        title: Text(items[i]['title'] ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(items[i]['url'] ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: deletable
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () {
                                  setSheet(() => items.removeAt(i));
                                  setState(() {});
                                  _save();
                                })
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          _go(items[i]['url']!);
                        },
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showTabs() {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => ListView(children: [
          for (int i = 0; i < _tabs.length; i++)
            ListTile(
              selected: i == _current,
              leading:
                  Icon(_tabs[i].incognito ? Icons.visibility_off : Icons.tab),
              title: Text(_tabs[i].title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_tabs[i].url,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _closeTab(i);
                    setSheet(() {});
                  }),
              onTap: () {
                _switchTab(i);
                Navigator.pop(context);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 700;
    final scheme = Theme.of(context).colorScheme;

    final addressBar = Expanded(
      child: TextField(
        controller: _address,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.go,
        onSubmitted: _go,
        onTap: () => _address.selection = TextSelection(
            baseOffset: 0, extentOffset: _address.text.length),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          hintText: 'Search or type a URL',
          prefixIcon: Icon(
              tab.incognito
                  ? Icons.visibility_off
                  : (tab.secure ? Icons.lock : Icons.lock_open),
              size: 18,
              color: tab.secure ? Colors.green : Colors.red),
          suffixIcon: IconButton(
              icon: Icon(_isBookmarked ? Icons.star : Icons.star_border,
                  size: 20),
              onPressed: _toggleBookmark),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none),
        ),
      ),
    );

    final menu = PopupMenuButton<String>(
      onSelected: (v) {
        switch (v) {
          case 'new':
            _newTab();
          case 'private':
            _newTab(incognito: true);
          case 'bookmarks':
            _showList('Bookmarks', _bookmarks, deletable: true);
          case 'history':
            _showList('History', _history, deletable: true);
          case 'clear':
            _clearData();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'new', child: Text('New tab')),
        const PopupMenuItem(value: 'private', child: Text('New private tab')),
        const PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
        const PopupMenuItem(value: 'history', child: Text('History')),
        const PopupMenuItem(value: 'clear', child: Text('Clear browsing data')),
        PopupMenuItem(
            enabled: false, child: Text('Trackers blocked: $_blockedCount')),
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          if (wide)
            Container(
              height: 40,
              color: scheme.surfaceContainerHighest,
              child: Row(children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _tabs.length,
                    itemBuilder: (_, i) => InkWell(
                      onTap: () => _switchTab(i),
                      child: Container(
                        width: 200,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        color: i == _current ? scheme.surface : null,
                        child: Row(children: [
                          if (_tabs[i].incognito)
                            const Icon(Icons.visibility_off, size: 14),
                          Expanded(
                              child: Text(' ${_tabs[i].title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                          InkWell(
                              onTap: () => _closeTab(i),
                              child: const Icon(Icons.close, size: 16)),
                        ]),
                      ),
                    ),
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.add), onPressed: () => _newTab()),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(children: [
              if (wide) ...[
                IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => tab.controller?.goBack()),
                IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => tab.controller?.goForward()),
              ],
              IconButton(
                  icon: Icon(tab.progress < 1 ? Icons.close : Icons.refresh),
                  onPressed: () => tab.progress < 1
                      ? tab.controller?.stopLoading()
                      : tab.controller?.reload()),
              addressBar,
              if (!wide)
                IconButton(
                  onPressed: _showTabs,
                  icon: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        border: Border.all(color: scheme.onSurface),
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('${_tabs.length}'),
                  ),
                ),
              menu,
            ]),
          ),
          if (tab.progress < 1) LinearProgressIndicator(value: tab.progress),
          Expanded(
            child: IndexedStack(
              index: _current,
              children: _tabs.map(_buildWebView).toList(),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: wide
          ? null
          : BottomAppBar(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => tab.controller?.goBack()),
                  IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => tab.controller?.goForward()),
                  IconButton(
                      icon: const Icon(Icons.home),
                      onPressed: () => _go(kHome)),
                  IconButton(
                      icon: const Icon(Icons.add_box_outlined),
                      onPressed: () => _newTab()),
                ],
              ),
            ),
    );
  }
}
