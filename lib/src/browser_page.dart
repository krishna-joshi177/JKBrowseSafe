import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'constants.dart';
import 'download_manager.dart';
import 'models.dart';
import 'pages/bookmarks_page.dart';
import 'pages/downloads_page.dart';
import 'pages/history_page.dart';
import 'pages/settings_page.dart';
import 'pages/site_settings_page.dart';
import 'permissions.dart';
import 'security.dart';
import 'threat_lists.dart';
import 'url_utils.dart';
import 'widgets/error_view.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, required this.state, required this.downloads});
  final AppState state;
  final DownloadManager downloads;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with WidgetsBindingObserver {
  AppState get s => widget.state;
  ThreatLists get lists => ThreatLists.instance;

  final List<BrowserTab> _tabs = <BrowserTab>[];
  int _current = 0;

  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  final TextEditingController _findCtrl = TextEditingController();
  bool _findOpen = false;
  int _findCount = 0;
  DateTime? _lastBack;
  String? _defaultUserAgent;
  bool _externalPromptOpen = false;
  int _appliedListsVersion = -1;

  /// Hosts the user chose to open over plain http (this session only).
  final Set<String> _httpAllowedHosts = <String>{};

  /// Dangerous hosts the user chose to visit anyway (this session only).
  final Set<String> _unsafeAllowedHosts = <String>{};

  BrowserTab get tab => _tabs[_current];

  // =====================================================================
  // Lifecycle
  // =====================================================================
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.addListener(_onStateChanged);
    lists.addListener(_onListsChanged);
    _appliedListsVersion = lists.version;
    for (final j in s.savedTabs) {
      final t = BrowserTab.fromJson(j);
      if (t.url.isNotEmpty) _tabs.add(t);
    }
    if (_tabs.isEmpty) _tabs.add(BrowserTab(url: s.engine.home));
    _current = math.max(0, math.min(s.savedCurrent, _tabs.length - 1));
    tab.activated = true;
    _address.text = tab.url;
    _addressFocus.addListener(_onAddressFocus);
    if (Platform.isAndroid) {
      InAppWebViewController.getDefaultUserAgent()
          .then((ua) => _defaultUserAgent = ua)
          .catchError((Object _) => '');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.removeListener(_onStateChanged);
    lists.removeListener(_onListsChanged);
    _address.dispose();
    _addressFocus.dispose();
    _findCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _persistTabs();
    if (state == AppLifecycleState.resumed) {
      unawaited(lists.updateIfStale());
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  /// New tracker list downloaded: give every open tab the new blocker.
  void _onListsChanged() {
    if (lists.version != _appliedListsVersion) {
      _appliedListsVersion = lists.version;
      unawaited(_applySettingsToAllTabs());
    }
  }

  void _onAddressFocus() {
    if (_addressFocus.hasFocus) {
      _address.selection =
          TextSelection(baseOffset: 0, extentOffset: _address.text.length);
    } else {
      _address.text = tab.url;
    }
    if (mounted) setState(() {});
  }

  void _syncAddress() {
    if (!_addressFocus.hasFocus) _address.text = tab.url;
  }

  void _persistTabs() {
    final normal = _tabs.where((t) => !t.incognito).toList();
    final idx = normal.indexOf(tab);
    s.saveTabs(normal.map((t) => t.toJson()).toList(), idx < 0 ? 0 : idx);
  }

  // =====================================================================
  // Helpers
  // =====================================================================
  void _toast(String msg, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg),
          action: action,
          behavior: SnackBarBehavior.floating));
  }

  Future<bool> _confirm(String title, String message,
      {String yes = 'OK', String no = 'Cancel', bool danger = false}) async {
    if (!mounted) return false;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: danger
            ? const Icon(Icons.warning_amber_rounded, color: Colors.orange)
            : null,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
        ],
      ),
    );
    return r ?? false;
  }

  /// HTTPS-only mode: upgrades http:// unless the user allowed the host.
  String _upgradeUrl(BrowserTab t, String url) {
    if (!s.httpsOnly || !url.toLowerCase().startsWith('http://')) return url;
    final host = hostOf(url);
    if (_httpAllowedHosts.contains(host)) return url;
    t.upgradedFrom = url;
    return 'https://${url.substring(7)}';
  }

  // =====================================================================
  // Safety checks
  // =====================================================================

  /// Phishing / malware lists, plus sites the user blocked.
  bool _isDangerous(String url) {
    final host = hostOf(url);
    if (host.isEmpty || _unsafeAllowedHosts.contains(host)) return false;
    return s.isUserBlocked(host) || lists.isThreat(url);
  }

  void _showDangerous(BrowserTab t, String url) {
    if (!mounted) return;
    final host = hostOf(url);
    setState(() {
      t.url = url;
      t.failedUrl = url;
      t.error = TabErrorKind.dangerous;
      t.errorDetail = s.isUserBlocked(host)
          ? 'You blocked this site. Unblock it in Settings > Blocked sites.'
          : 'Source: public phishing and malware lists.';
      t.progress = 1;
    });
    if (identical(t, tab)) _syncAddress();
  }

  void _continueUnsafe(BrowserTab t) {
    final url = t.failedUrl ?? t.url;
    final host = hostOf(url);
    if (s.isUserBlocked(host)) s.unblockSite(host);
    _unsafeAllowedHosts.add(host);
    setState(() => t.error = TabErrorKind.none);
    t.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  /// When HTTPS-only is off, asks before opening an http:// page.
  Future<bool> _confirmHttp(String url) async {
    if (!url.toLowerCase().startsWith('http://')) return true;
    final host = hostOf(url);
    if (host.isEmpty ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        _httpAllowedHosts.contains(host)) {
      return true;
    }
    final ok = await _confirm(
      'This site is not secure',
      "$host doesn't use HTTPS. Passwords, card numbers and messages you "
          'send can be seen or changed by others on the network.',
      yes: 'Continue anyway',
      no: 'Go back',
      danger: true,
    );
    if (ok) _httpAllowedHosts.add(host);
    return ok;
  }

  /// Turns JavaScript on/off for the tab to match the site's setting.
  /// Returns true if the setting changed.
  Future<bool> _syncJs(BrowserTab t, String url) async {
    final want = s.jsEnabledFor(hostOf(url));
    if (want == t.jsEnabled) return false;
    t.jsEnabled = want;
    try {
      await t.controller?.setSettings(settings: _settingsFor(t));
    } catch (_) {}
    return true;
  }

  // =====================================================================
  // Navigation
  // =====================================================================
  void _go(String input) {
    _load(tab, toUrl(input, s.engine));
    _addressFocus.unfocus();
  }

  Future<void> _load(BrowserTab t, String url) async {
    final target = _upgradeUrl(t, url);
    if (_isDangerous(target)) {
      _showDangerous(t, target);
      return;
    }
    if (!await _confirmHttp(target)) return;
    await _syncJs(t, target);
    if (!mounted) return;
    setState(() {
      t.error = TabErrorKind.none;
      t.url = target;
    });
    _syncAddress();
    await t.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
  }

  void _reload() {
    if (tab.error != TabErrorKind.none) {
      _retry(tab);
    } else {
      tab.controller?.reload();
    }
  }

  Future<NavigationActionPolicy> _shouldOverride(
      BrowserTab t, InAppWebViewController c, NavigationAction action) async {
    final uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.ALLOW;
    final url = uri.toString();
    final scheme = uri.scheme.toLowerCase();
    final isMain = action.isForMainFrame;
    final gesture = action.hasGesture;

    // Other apps: mailto:, tel:, intent:, market:, whatsapp:, upi: ...
    const internal = <String>{'http', 'https', 'about', 'data', 'blob', 'javascript'};
    if (!internal.contains(scheme)) {
      if (isMain) unawaited(_openExternal(url, userGesture: gesture != false));
      return NavigationActionPolicy.CANCEL;
    }

    // Pages may not open hidden data: pages as a whole page (phishing trick).
    if (isMain && scheme == 'data') {
      _toast('Blocked a page that tried to open a hidden "data:" address');
      return NavigationActionPolicy.CANCEL;
    }

    if (isMain && _isDangerous(url)) {
      _showDangerous(t, url);
      return NavigationActionPolicy.CANCEL;
    }

    if (s.blockTrackers && isTrackerUrl(url)) {
      return NavigationActionPolicy.CANCEL;
    }

    if (isMain && scheme == 'http') {
      if (s.httpsOnly) {
        final upgraded = _upgradeUrl(t, url);
        if (upgraded != url) {
          await _syncJs(t, upgraded);
          await c.loadUrl(urlRequest: URLRequest(url: WebUri(upgraded)));
          return NavigationActionPolicy.CANCEL;
        }
      } else if (!_httpAllowedHosts.contains(uri.host)) {
        unawaited(_load(t, url)); // asks first
        return NavigationActionPolicy.CANCEL;
      }
    }

    // Automatic redirect chains: block the 3rd cross-site jump within
    // 10 seconds that happened without a tap.
    if (isMain && (scheme == 'http' || scheme == 'https')) {
      if (gesture == true) {
        t.autoNavs.clear();
      } else if (gesture == false &&
          action.isRedirect != true &&
          t.url.startsWith('http')) {
        final from = registrableDomain(hostOf(t.url));
        final to = registrableDomain(uri.host);
        if (from.isNotEmpty && to != from) {
          final now = DateTime.now();
          t.autoNavs.removeWhere(
              (d) => now.difference(d) > const Duration(seconds: 10));
          t.autoNavs.add(now);
          if (t.autoNavs.length > 2) {
            _toast('Blocked an automatic redirect to ${uri.host}',
                action: SnackBarAction(
                    label: 'Allow',
                    onPressed: () {
                      t.autoNavs.clear();
                      _load(t, url);
                    }));
            return NavigationActionPolicy.CANCEL;
          }
        }
      }
    }

    // Per-site JavaScript: switch the setting before the new site loads.
    if (isMain && s.jsEnabledFor(uri.host) != t.jsEnabled) {
      await _syncJs(t, url);
      await c.loadUrl(urlRequest: URLRequest(url: uri));
      return NavigationActionPolicy.CANCEL;
    }

    // Offer to open Play Store links in the Play Store app.
    if (Platform.isAndroid &&
        isMain &&
        uri.host == 'play.google.com' &&
        uri.path.startsWith('/store/apps/details')) {
      final id = uri.queryParameters['id'];
      if (id != null &&
          await _confirm('Open in Play Store?',
              'This link can open in the Google Play Store app.',
              yes: 'Open app', no: 'Stay here')) {
        try {
          await launchUrl(Uri.parse('market://details?id=$id'),
              mode: LaunchMode.externalApplication);
          return NavigationActionPolicy.CANCEL;
        } catch (_) {}
      }
    }
    return NavigationActionPolicy.ALLOW;
  }

  String _appLabel(String scheme) => switch (scheme) {
        'mailto' => 'your email app',
        'tel' => 'the phone dialer',
        'sms' => 'your messages app',
        'market' => 'the Google Play Store',
        'upi' => 'a UPI payment app',
        'whatsapp' => 'WhatsApp',
        'tg' => 'Telegram',
        _ => 'another app ("$scheme:" link)',
      };

  /// Always asks before leaving the browser for another app.
  Future<void> _openExternal(String url, {bool userGesture = true}) async {
    if (_externalPromptOpen) return;
    Uri? target = Uri.tryParse(url);
    if (url.startsWith('intent:')) {
      final fallback =
          RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url)?.group(1);
      final pkg = RegExp(r'package=([^;]+)').firstMatch(url)?.group(1);
      if (fallback != null) {
        try {
          await _load(tab, Uri.decodeComponent(fallback));
          return;
        } catch (_) {}
      }
      target = pkg != null ? Uri.parse('market://details?id=$pkg') : null;
    }
    if (target == null) return;
    final scheme = target.scheme.toLowerCase();
    final site = hostOf(tab.url).isEmpty ? 'This page' : hostOf(tab.url);

    if (!userGesture) {
      _toast('Blocked $site from opening ${_appLabel(scheme)}',
          action: SnackBarAction(
              label: 'Allow', onPressed: () => _openExternal(url)));
      return;
    }

    _externalPromptOpen = true;
    final ok = await _confirm('Open another app?',
        '$site wants to open ${_appLabel(scheme)}.',
        yes: 'Open', no: 'Cancel');
    _externalPromptOpen = false;
    if (!ok) return;

    var launched = false;
    try {
      launched =
          await launchUrl(target, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!launched && scheme == 'market') {
      final id = target.queryParameters['id'];
      if (id != null) {
        await _load(tab, 'https://play.google.com/store/apps/details?id=$id');
        return;
      }
    }
    if (!launched) _toast('No app found to open this link');
  }

  // =====================================================================
  // Tabs
  // =====================================================================
  void _newTab({bool incognito = false, String? url}) {
    final t = BrowserTab(url: url ?? s.engine.home, incognito: incognito)
      ..activated = true;
    setState(() {
      _tabs.add(t);
      _current = _tabs.length - 1;
    });
    _address.text = t.url;
    _persistTabs();
    if (incognito) {
      _toast(Platform.isAndroid
          ? "Private tab: history isn't saved. On Android, opening a private "
              'tab may sign you out of sites in other tabs.'
          : "Private tab: history and cookies aren't saved.");
    }
  }

  void _switchTab(int i) {
    if (i < 0 || i >= _tabs.length) return;
    setState(() {
      _current = i;
      tab.activated = true;
    });
    _syncAddress();
    if (_findOpen) _closeFind();
    _persistTabs();
  }

  void _closeTab(int i) {
    if (i < 0 || i >= _tabs.length) return;
    setState(() {
      _tabs.removeAt(i);
      if (_tabs.isEmpty) {
        _tabs.add(BrowserTab(url: s.engine.home)..activated = true);
      }
      if (i < _current || _current >= _tabs.length) {
        _current = math.max(0, _current - 1);
      }
      _current = math.min(_current, _tabs.length - 1);
      tab.activated = true;
    });
    _syncAddress();
    _persistTabs();
  }

  void _closeAllTabs() {
    setState(() {
      _tabs
        ..clear()
        ..add(BrowserTab(url: s.engine.home)..activated = true);
      _current = 0;
    });
    _syncAddress();
    _persistTabs();
  }

  // =====================================================================
  // WebView
  // =====================================================================
  int _blockersVersion = -1;
  List<ContentBlocker> _blockerCache = <ContentBlocker>[];

  /// Built-in + downloaded tracker list, grouped into a few rules.
  List<ContentBlocker> get _blockers {
    if (_blockersVersion != lists.version) {
      _blockersVersion = lists.version;
      final domains = lists.trackerDomains.toList()..sort();
      _blockerCache = buildTrackerPatterns(domains)
          .map((p) => ContentBlocker(
                trigger: ContentBlockerTrigger(urlFilter: p),
                action:
                    ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
              ))
          .toList();
    }
    return _blockerCache;
  }

  InAppWebViewSettings _settingsFor(BrowserTab t) => InAppWebViewSettings(
        incognito: t.incognito,
        cacheEnabled: !t.incognito,
        javaScriptEnabled: t.jsEnabled,
        javaScriptCanOpenWindowsAutomatically: false, // pop-up blocker
        supportMultipleWindows: true, // target=_blank opens a new tab
        useShouldOverrideUrlLoading: true,
        useOnDownloadStart: true,
        useOnRenderProcessGone: true,
        safeBrowsingEnabled: true,
        thirdPartyCookiesEnabled: false,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
        geolocationEnabled: true,
        mediaPlaybackRequiresUserGesture: true,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,
        allowFileAccess: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        textZoom: s.textZoom,
        algorithmicDarkeningAllowed: s.forceDarkPages,
        userAgent: t.desktopMode ? kDesktopUserAgent : _defaultUserAgent,
        useWideViewPort: true,
        loadWithOverviewMode: t.desktopMode,
        contentBlockers: s.blockTrackers ? _blockers : <ContentBlocker>[],
      );

  Future<void> _applySettingsToAllTabs() async {
    for (final t in _tabs) {
      final c = t.controller;
      if (c == null) continue;
      try {
        await c.setSettings(settings: _settingsFor(t));
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Widget _tabView(BrowserTab t) {
    if (!t.activated) return const SizedBox.shrink();
    if (t.controller == null) t.jsEnabled = s.jsEnabledFor(hostOf(t.url));
    final startUrl = _upgradeUrl(t, t.url);
    final startBlocked = t.windowId == null && _isDangerous(startUrl);
    return Stack(fit: StackFit.expand, children: [
      InAppWebView(
        key: t.key,
        windowId: t.windowId,
        initialUrlRequest: t.windowId == null && !startBlocked
            ? URLRequest(url: WebUri(startUrl))
            : null,
        initialSettings: _settingsFor(t),
        onWebViewCreated: (c) {
          t.controller = c;
          if (startBlocked) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _showDangerous(t, startUrl));
          }
        },
        onLoadStart: (c, url) async {
          if (!mounted) return;
          final u = url?.toString() ?? '';
          // Backstop: also catches server redirects to dangerous sites.
          if (u.isNotEmpty && _isDangerous(u)) {
            try {
              await c.stopLoading();
            } catch (_) {}
            _showDangerous(t, u);
            return;
          }
          setState(() {
            if (u.isNotEmpty) t.url = u;
            t.progress = 0.05;
            if (t.error != TabErrorKind.crashed) t.error = TabErrorKind.none;
          });
          if (identical(t, tab)) _syncAddress();
          if (u.isNotEmpty && await _syncJs(t, u)) {
            try {
              await c.reload();
            } catch (_) {}
          }
        },
        onLoadStop: (c, url) async {
          String? title;
          try {
            title = await c.getTitle();
          } catch (_) {}
          if (!mounted) return;
          final u = url?.toString() ?? t.url;
          setState(() {
            t.progress = 1;
            t.url = u;
            if (title != null && title.isNotEmpty) t.title = title;
          });
          if (t.error == TabErrorKind.none) {
            if (u.startsWith('https://')) t.upgradedFrom = null;
            if (!t.incognito &&
                (u.startsWith('http://') || u.startsWith('https://'))) {
              s.addHistory(t.title, u);
            }
          }
          if (identical(t, tab)) _syncAddress();
          _persistTabs();
        },
        onUpdateVisitedHistory: (c, url, isReload) {
          if (url == null || !mounted) return;
          setState(() => t.url = url.toString());
          if (identical(t, tab)) _syncAddress();
        },
        onProgressChanged: (c, p) {
          if (mounted) setState(() => t.progress = p / 100);
        },
        onTitleChanged: (c, title) {
          if (mounted && title != null && title.isNotEmpty) {
            setState(() => t.title = title);
          }
        },
        shouldOverrideUrlLoading: (c, action) => _shouldOverride(t, c, action),
        onCreateWindow: (c, action) async {
          final url = action.request.url?.toString() ?? 'about:blank';
          if (s.blockTrackers && isTrackerUrl(url)) return false;
          if (_isDangerous(url)) {
            _toast('Blocked a pop-up to a dangerous site');
            return false;
          }
          // Pop-up blocker: new windows need a real tap or click.
          if (action.hasGesture == false) {
            _toast('Pop-up blocked',
                action: url.startsWith('http')
                    ? SnackBarAction(
                        label: 'Open',
                        onPressed: () =>
                            _newTab(url: url, incognito: t.incognito))
                    : null);
            return false;
          }
          final nt = BrowserTab(
            url: url,
            incognito: t.incognito,
            windowId: action.windowId,
            openedByPage: true,
          )..activated = true;
          setState(() {
            _tabs.add(nt);
            _current = _tabs.length - 1;
          });
          _syncAddress();
          return true;
        },
        onCloseWindow: (c) => _closeTab(_tabs.indexOf(t)),
        onEnterFullscreen: (c) {
          // Full screen hides the real address bar, so say which site it is.
          final host = hostOf(t.url).isEmpty ? 'This page' : hostOf(t.url);
          _toast('$host is now full screen. Press Back or Esc to exit.');
        },
        onDownloadStartRequest: (c, req) => _onDownload(t, req),
        onPermissionRequest: (c, req) => _onPermission(t, req),
        onGeolocationPermissionsShowPrompt: (c, origin) async {
          final allow = await _decide(t, originOf(origin), 'location') &&
              await _osPermission('location');
          return GeolocationPermissionShowPromptResponse(
              origin: origin, allow: allow, retain: false);
        },
        onReceivedError: (c, req, err) => _onError(t, req, err),
        // Invalid certificates are never ignored: the load is cancelled and
        // a warning page is shown. There is no "proceed anyway" button.
        onReceivedServerTrustAuthRequest: (c, challenge) async {
          final host = challenge.protectionSpace.host;
          if (mounted && host == hostOf(t.url)) {
            setState(() {
              t.error = TabErrorKind.ssl;
              t.failedUrl = t.url;
              t.errorDetail = 'Certificate check failed for $host.';
              t.progress = 1;
            });
          }
          return ServerTrustAuthResponse(
              action: ServerTrustAuthResponseAction.CANCEL);
        },
        onRenderProcessGone: (c, detail) {
          if (!mounted) return;
          setState(() {
            t.error = TabErrorKind.crashed;
            t.errorDetail = '';
            t.failedUrl = t.url;
            t.controller = null;
            t.windowId = null;
            t.key = UniqueKey(); // recreate the WebView
          });
        },
      ),
      if (t.error != TabErrorKind.none)
        Positioned.fill(
          child: ErrorView(
            kind: t.error,
            url: t.failedUrl ?? t.url,
            detail: t.errorDetail,
            onRetry: () => _retry(t),
            onBack: () => _backFromError(t),
            onContinueInsecure: switch (t.error) {
              TabErrorKind.httpsUnavailable => () => _continueInsecure(t),
              TabErrorKind.dangerous => () => _continueUnsafe(t),
              _ => null,
            },
          ),
        ),
    ]);
  }

  // =====================================================================
  // Errors / offline / crash
  // =====================================================================
  Future<void> _onError(
      BrowserTab t, WebResourceRequest req, WebResourceError err) async {
    if (req.isForMainFrame == false) return;
    if (t.error == TabErrorKind.dangerous) return;
    final text = '${err.type} ${err.description}';
    if (isCancelledError(text)) return;
    var kind = classifyError(text);
    if (t.upgradedFrom != null &&
        kind != TabErrorKind.offline &&
        kind != TabErrorKind.ssl &&
        hostOf(req.url.toString()) == hostOf(t.upgradedFrom!)) {
      kind = TabErrorKind.httpsUnavailable;
    }
    if (!mounted) return;
    setState(() {
      t.error = kind;
      t.errorDetail = err.description;
      t.failedUrl = req.url.toString();
      t.progress = 1;
    });
    // A failed DNS lookup can mean "offline" or just "wrong address".
    if (kind == TabErrorKind.offline && await hasInternet() && mounted) {
      setState(() => t.error = TabErrorKind.network);
    }
  }

  void _retry(BrowserTab t) {
    final url = t.failedUrl ?? t.url;
    if (_isDangerous(url)) {
      _showDangerous(t, url);
      return;
    }
    setState(() => t.error = TabErrorKind.none);
    t.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _backFromError(BrowserTab t) async {
    setState(() => t.error = TabErrorKind.none);
    final c = t.controller;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
    } else {
      await _load(t, s.engine.home);
    }
  }

  void _continueInsecure(BrowserTab t) {
    final from = t.upgradedFrom;
    if (from == null) return;
    _httpAllowedHosts.add(hostOf(from));
    t.upgradedFrom = null;
    setState(() {
      t.error = TabErrorKind.none;
      t.url = from;
    });
    t.controller?.loadUrl(urlRequest: URLRequest(url: WebUri(from)));
  }

  // =====================================================================
  // Downloads
  // =====================================================================
  Future<void> _onDownload(BrowserTab t, DownloadStartRequest r) async {
    final url = r.url.toString();
    if (url.startsWith('blob:')) {
      _toast("This kind of download isn't supported yet");
      return;
    }
    final name =
        fileNameFor(url, r.suggestedFilename, r.contentDisposition, r.mimeType);
    final host = hostOf(url).isEmpty ? 'this site' : hostOf(url);
    final verdict = checkDownload(name, url,
        fromDangerousSite: lists.isThreat(url) ||
            lists.isThreat(t.url) ||
            s.isUserBlocked(hostOf(url)));
    if (verdict.risk == DownloadRisk.block) {
      _toast('Blocked "$name" because ${verdict.reason}.');
      return;
    }
    final dangerous = verdict.risk == DownloadRisk.warn;
    final size = r.contentLength > 0 ? ' (${formatBytes(r.contentLength)})' : '';
    final ok = await _confirm(
      dangerous ? 'This file could harm your device' : 'Download file?',
      dangerous
          ? '"$name": ${verdict.reason}. Only download it if you trust $host.'
          : '$name$size',
      yes: dangerous ? 'Download anyway' : 'Download',
      danger: dangerous,
    );
    if (!ok) return;
    String? cookieHeader;
    try {
      final cookies = await CookieManager.instance().getCookies(url: r.url);
      cookieHeader = cookies.map((ck) => '${ck.name}=${ck.value}').join('; ');
    } catch (_) {}
    unawaited(widget.downloads.start(
      url: url,
      fileName: name,
      userAgent: r.userAgent,
      cookieHeader: cookieHeader,
    ));
    _toast('Downloading $name',
        action: SnackBarAction(label: 'View', onPressed: _openDownloads));
  }

  // =====================================================================
  // Permissions
  // =====================================================================
  Future<PermissionResponse?> _onPermission(
      BrowserTab t, PermissionRequest req) async {
    final origin = originOf(req.origin.toString());
    final granted = <PermissionResourceType>[];
    for (final r in req.resources) {
      final key = permissionKey(r);
      if (Platform.isAndroid && key == 'notifications') continue;
      if (await _decide(t, origin, key) && await _osPermission(key)) {
        granted.add(r);
      }
    }
    if (granted.isEmpty) {
      return PermissionResponse(
          resources: req.resources, action: PermissionResponseAction.DENY);
    }
    return PermissionResponse(
        resources: granted, action: PermissionResponseAction.GRANT);
  }

  /// Uses the saved per-site choice, or asks the user.
  Future<bool> _decide(BrowserTab t, String origin, String key) async {
    final saved = s.sitePermission(origin, key);
    if (saved == 'allow') return true;
    if (saved == 'block') return false;
    if (!mounted) return false;
    var remember = !t.incognito;
    final label = permissionLabel(key).toLowerCase();
    final allow = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setD) => AlertDialog(
              icon: Icon(permissionIcon(key)),
              title: Text('Allow $label?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$origin wants to use your $label.'),
                  if (!t.incognito)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: remember,
                      onChanged: (v) => setD(() => remember = v ?? false),
                      title: const Text('Remember my choice for this site'),
                    ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Block')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Allow')),
              ],
            ),
          ),
        ) ??
        false;
    if (remember && !t.incognito) {
      s.setSitePermission(origin, key, allow ? 'allow' : 'block');
    }
    return allow;
  }

  /// Android also needs the app-level permission.
  Future<bool> _osPermission(String key) async {
    if (!Platform.isAndroid) return true;
    final ph.Permission? p = switch (key) {
      'camera' => ph.Permission.camera,
      'microphone' => ph.Permission.microphone,
      'location' => ph.Permission.locationWhenInUse,
      _ => null,
    };
    if (p == null) return true;
    final status = await p.request();
    if (status == ph.PermissionStatus.granted ||
        status == ph.PermissionStatus.limited) {
      return true;
    }
    if (status == ph.PermissionStatus.permanentlyDenied) {
      _toast('Permission is turned off for JKBrowseSafe',
          action: SnackBarAction(
              label: 'Settings', onPressed: () => ph.openAppSettings()));
    }
    return false;
  }

  // =====================================================================
  // Find in page
  // =====================================================================
  void _openFind() {
    setState(() {
      _findOpen = true;
      _findCount = 0;
    });
  }

  void _closeFind() {
    tab.controller?.evaluateJavascript(
        source: 'window.getSelection && window.getSelection().removeAllRanges();');
    setState(() {
      _findOpen = false;
      _findCtrl.clear();
      _findCount = 0;
    });
  }

  Future<void> _find(String text,
      {bool backwards = false, bool reset = false}) async {
    final c = tab.controller;
    if (c == null) return;
    if (!tab.jsEnabled) {
      _toast('Find in page needs JavaScript, which is blocked on this site');
      return;
    }
    if (text.isEmpty) {
      await c.evaluateJavascript(
          source: 'window.getSelection && window.getSelection().removeAllRanges();');
      if (mounted) setState(() => _findCount = 0);
      return;
    }
    final q = jsonEncode(text);
    final js = '(function(q, back, reset){'
        'var body = document.body ? document.body.innerText.toLowerCase() : "";'
        'var s = q.toLowerCase(), n = 0, i = 0;'
        'while ((i = body.indexOf(s, i)) !== -1) { n++; i += s.length; }'
        'if (reset && window.getSelection) window.getSelection().removeAllRanges();'
        'if (window.find) window.find(q, false, back, true, false, false, false);'
        'return n;'
        '})($q, $backwards, $reset)';
    try {
      final res = await c.evaluateJavascript(source: js);
      final n = res is num ? res.toInt() : int.tryParse('$res') ?? 0;
      if (mounted) setState(() => _findCount = n);
    } catch (_) {}
  }

  // =====================================================================
  // Menu actions
  // =====================================================================
  Future<void> _openBookmarks() async {
    final url = await Navigator.push<String>(context,
        MaterialPageRoute<String>(builder: (_) => BookmarksPage(state: s)));
    if (url != null) await _load(tab, url);
  }

  Future<void> _openHistory() async {
    final url = await Navigator.push<String>(context,
        MaterialPageRoute<String>(builder: (_) => HistoryPage(state: s)));
    if (url != null) await _load(tab, url);
  }

  Future<void> _openDownloads() async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
            builder: (_) => DownloadsPage(downloads: widget.downloads)));
  }

  Future<void> _openSiteSettings(String origin) async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
            builder: (_) => SiteSettingsPage(state: s, origin: origin)));
  }

  Future<void> _openSettings() async {
    await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
            builder: (_) =>
                SettingsPage(state: s, downloads: widget.downloads)));
    for (final t in _tabs) {
      await _syncJs(t, t.url);
    }
    await _applySettingsToAllTabs();
  }

  Future<void> _share() async {
    final url = tab.url;
    if (Platform.isAndroid) {
      await Share.share(url, subject: tab.title);
    } else {
      await Clipboard.setData(ClipboardData(text: url));
      _toast('Link copied');
    }
  }

  Future<void> _toggleDesktop() async {
    final t = tab;
    setState(() => t.desktopMode = !t.desktopMode);
    final c = t.controller;
    if (c == null) return;
    try {
      await c.setSettings(settings: _settingsFor(t));
    } catch (_) {}
    await c.reload();
    _persistTabs();
  }

  /// Report the current site to public safety services, or block it here.
  Future<void> _reportUnsafe() async {
    final t = tab;
    final url = t.failedUrl != null && t.error == TabErrorKind.dangerous
        ? t.failedUrl!
        : t.url;
    final host = hostOf(url);
    if (host.isEmpty || !url.startsWith('http')) {
      _toast('Open a website first');
      return;
    }
    final enc = Uri.encodeComponent(url);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: const Text('Report unsafe site'),
            subtitle: Text(host),
          ),
          ListTile(
            leading: const Icon(Icons.phishing),
            title: const Text('Phishing or fake login page'),
            subtitle: const Text('Report to Google Safe Browsing'),
            onTap: () => Navigator.pop(ctx, 'phish'),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Malware or harmful download'),
            subtitle: const Text('Report to Google Safe Browsing'),
            onTap: () => Navigator.pop(ctx, 'malware'),
          ),
          ListTile(
            leading: const Icon(Icons.local_police_outlined),
            title: const Text('Online fraud (India)'),
            subtitle: const Text('National Cyber Crime Reporting Portal'),
            onTap: () => Navigator.pop(ctx, 'india'),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text('Block $host on this device'),
            onTap: () => Navigator.pop(ctx, 'block'),
          ),
        ]),
      ),
    );
    switch (choice) {
      case 'phish':
        _newTab(
            url: 'https://safebrowsing.google.com/safebrowsing/report_phish/?url=$enc',
            incognito: t.incognito);
      case 'malware':
        _newTab(
            url: 'https://safebrowsing.google.com/safebrowsing/report_badware/?url=$enc',
            incognito: t.incognito);
      case 'india':
        _newTab(url: 'https://cybercrime.gov.in/', incognito: t.incognito);
      case 'block':
        s.blockSite(host);
        _unsafeAllowedHosts.remove(host);
        try {
          await t.controller?.stopLoading();
        } catch (_) {}
        _showDangerous(t, url);
        _toast('$host is blocked on this device',
            action: SnackBarAction(
                label: 'Undo', onPressed: () => s.unblockSite(host)));
    }
  }

  void _showPageInfo() {
    final t = tab;
    final origin = originOf(t.url);
    final host = hostOf(t.url).isEmpty ? t.url : hostOf(t.url);
    final web = t.url.startsWith('http://') || t.url.startsWith('https://');
    final warning = suspiciousReason(t.url);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: Icon(t.secure ? Icons.lock : Icons.lock_open,
                    color: t.secure ? Colors.green : Colors.red),
                title: Text(host, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.secure
                    ? 'Connection is secure'
                    : "Connection is not secure. Don't enter passwords or "
                        'payment details on this site.'),
              ),
              if (warning != null)
                ListTile(
                  leading: const Icon(Icons.gpp_maybe, color: Colors.red),
                  title: const Text('Check this address carefully'),
                  subtitle: Text(warning),
                ),
              const Divider(),
              if (web)
                SwitchListTile(
                  secondary: const Icon(Icons.code),
                  title: const Text('JavaScript'),
                  subtitle: Text(s.jsEnabledFor(hostOf(t.url))
                      ? 'Allowed on this site'
                      : 'Blocked on this site (some pages may not work)'),
                  value: s.jsEnabledFor(hostOf(t.url)),
                  onChanged: (v) async {
                    s.setJsEnabled(hostOf(t.url), v);
                    setSheet(() {});
                    if (await _syncJs(t, t.url)) {
                      await t.controller?.reload();
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Permissions for this site'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openSiteSettings(origin);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cookie_outlined),
                title: const Text('Delete cookies for this site'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await CookieManager.instance().deleteCookies(url: WebUri(t.url));
                  } catch (_) {}
                  _toast('Cookies deleted for $host');
                },
              ),
              if (web)
                ListTile(
                  leading: const Icon(Icons.report_outlined),
                  title: const Text('Report unsafe site'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _reportUnsafe();
                  },
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(String v) async {
    switch (v) {
      case 'new':
        _newTab();
      case 'private':
        _newTab(incognito: true);
      case 'bookmarks':
        await _openBookmarks();
      case 'history':
        await _openHistory();
      case 'downloads':
        await _openDownloads();
      case 'find':
        _openFind();
      case 'share':
        await _share();
      case 'desktop':
        await _toggleDesktop();
      case 'site':
        await _openSiteSettings(originOf(tab.url));
      case 'report':
        await _reportUnsafe();
      case 'settings':
        await _openSettings();
    }
  }

  // =====================================================================
  // Android back button
  // =====================================================================
  Future<void> _handleBack() async {
    if (_findOpen) {
      _closeFind();
      return;
    }
    if (_addressFocus.hasFocus) {
      _addressFocus.unfocus();
      return;
    }
    final t = tab;
    if (t.error != TabErrorKind.none) {
      await _backFromError(t);
      return;
    }
    final c = t.controller;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
      return;
    }
    if (t.openedByPage && _tabs.length > 1) {
      _closeTab(_current);
      return;
    }
    final now = DateTime.now();
    if (_lastBack == null ||
        now.difference(_lastBack!) > const Duration(seconds: 2)) {
      _lastBack = now;
      _toast('Press back again to exit');
      return;
    }
    _persistTabs();
    await SystemNavigator.pop();
  }

  // =====================================================================
  // UI
  // =====================================================================
  PopupMenuItem<String> _item(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label),
        ]),
      );

  Widget _menuButton() => PopupMenuButton<String>(
        tooltip: 'Menu',
        icon: const Icon(Icons.more_vert),
        onSelected: _onMenu,
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          _item('new', Icons.add, 'New tab'),
          _item('private', Icons.visibility_off_outlined, 'New private tab'),
          const PopupMenuDivider(),
          _item('bookmarks', Icons.bookmarks_outlined, 'Bookmarks'),
          _item('history', Icons.history, 'History'),
          _item('downloads', Icons.download_outlined, 'Downloads'),
          const PopupMenuDivider(),
          _item('find', Icons.find_in_page_outlined, 'Find in page'),
          _item('share', Icons.share_outlined,
              Platform.isAndroid ? 'Share page' : 'Copy link'),
          if (Platform.isAndroid)
            CheckedPopupMenuItem<String>(
                value: 'desktop',
                checked: tab.desktopMode,
                child: const Text('Desktop site')),
          _item('site', Icons.tune, 'Site settings'),
          _item('report', Icons.report_outlined, 'Report unsafe site'),
          const PopupMenuDivider(),
          _item('settings', Icons.settings_outlined, 'Settings'),
        ],
      );

  Widget _addressField(ColorScheme scheme) {
    final t = tab;
    final bookmarked = s.isBookmarked(t.url);
    final lockIcon = t.incognito
        ? Icons.visibility_off
        : (t.secure ? Icons.lock : Icons.lock_open);
    final fill =
        t.incognito ? scheme.tertiaryContainer : scheme.surfaceContainerHighest;
    final field = TextField(
      controller: _address,
      focusNode: _addressFocus,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.go,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: _go,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: fill,
        hintText: 'Search ${s.engine.name} or type a URL',
        prefixIcon: IconButton(
          tooltip: t.secure
              ? 'Site information: secure'
              : 'Site information: not secure',
          icon: Icon(lockIcon,
              size: 18,
              color: t.incognito
                  ? null
                  : (t.secure ? Colors.green : scheme.error)),
          onPressed: _showPageInfo,
        ),
        suffixIcon: _addressFocus.hasFocus
            ? IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear, size: 20),
                onPressed: _address.clear)
            : IconButton(
                tooltip: bookmarked ? 'Remove bookmark' : 'Add bookmark',
                icon: Icon(bookmarked ? Icons.star : Icons.star_border,
                    size: 20),
                onPressed: () => s.toggleBookmark(t.title, t.url)),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
    final web = t.url.startsWith('http://') || t.url.startsWith('https://');
    if (_addressFocus.hasFocus || !web) return field;
    // When not editing, the app (never the web page) draws the real domain
    // in bold so look-alike addresses are easy to spot.
    return Stack(children: [
      field,
      Positioned(
        left: 48,
        right: 48,
        top: 2,
        bottom: 2,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _addressFocus.requestFocus(),
          child: Container(
            color: fill,
            alignment: Alignment.centerLeft,
            child: _DomainLabel(url: t.url),
          ),
        ),
      ),
    ]);
  }

  Widget _tabCountButton(ColorScheme scheme) => IconButton(
        tooltip: '${_tabs.length} open tabs',
        onPressed: _showTabs,
        icon: Container(
          constraints: const BoxConstraints(minWidth: 24),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
              border: Border.all(color: scheme.onSurface, width: 1.5),
              borderRadius: BorderRadius.circular(5)),
          child: Text('${_tabs.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      );

  Widget _toolbar(bool wide, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(children: [
          if (wide) ...[
            IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => tab.controller?.goBack()),
            IconButton(
                tooltip: 'Forward',
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => tab.controller?.goForward()),
            IconButton(
                tooltip: 'Home',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => _load(tab, s.engine.home)),
          ],
          IconButton(
            tooltip: tab.progress < 1 ? 'Stop loading' : 'Reload',
            icon: Icon(tab.progress < 1 ? Icons.close : Icons.refresh),
            onPressed: () {
              if (tab.progress < 1) {
                tab.controller?.stopLoading();
                setState(() => tab.progress = 1);
              } else {
                _reload();
              }
            },
          ),
          Expanded(child: _addressField(scheme)),
          if (wide)
            IconButton(
                tooltip: 'Downloads',
                icon: const Icon(Icons.download_outlined),
                onPressed: _openDownloads),
          if (!wide) _tabCountButton(scheme),
          _menuButton(),
        ]),
      );

  Widget _tabStrip(ColorScheme scheme) => Container(
        height: 40,
        color: scheme.surfaceContainerHighest,
        child: Row(children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (_, i) {
                final t = _tabs[i];
                final selected = i == _current;
                return Semantics(
                  selected: selected,
                  button: true,
                  label: 'Tab ${i + 1} of ${_tabs.length}: ${t.title}',
                  child: InkWell(
                    onTap: () => _switchTab(i),
                    child: Container(
                      width: 210,
                      padding: const EdgeInsets.only(left: 12, right: 2),
                      decoration: BoxDecoration(
                        color: selected ? scheme.surface : null,
                        border: Border(
                            right: BorderSide(color: scheme.outlineVariant)),
                      ),
                      child: Row(children: [
                        if (t.incognito)
                          const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.visibility_off, size: 14)),
                        if (t.progress < 1)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: SizedBox(
                                width: 12,
                                height: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        Expanded(
                            child: Text(t.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                        IconButton(
                            tooltip: 'Close tab',
                            iconSize: 16,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close),
                            onPressed: () => _closeTab(i)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
              tooltip: 'New tab',
              icon: const Icon(Icons.add),
              onPressed: () => _newTab()),
        ]),
      );

  void _showTabs() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Text('${_tabs.length} tabs',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _newTab(incognito: true);
                    },
                    icon: const Icon(Icons.visibility_off_outlined),
                    label: const Text('Private')),
                TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _newTab();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New tab')),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _tabs.length,
                itemBuilder: (_, i) {
                  final t = _tabs[i];
                  return ListTile(
                    selected: i == _current,
                    leading:
                        Icon(t.incognito ? Icons.visibility_off : Icons.public),
                    title: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        hostOf(t.url).isEmpty ? t.url : hostOf(t.url),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                        tooltip: 'Close tab',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _closeTab(i);
                          setSheet(() {});
                        }),
                    onTap: () {
                      Navigator.pop(ctx);
                      _switchTab(i);
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _closeAllTabs();
                  },
                  child: const Text('Close all tabs')),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _findBar() => Material(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _findCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                    hintText: 'Find in page', border: InputBorder.none),
                onChanged: (v) => _find(v, reset: true),
                onSubmitted: (v) => _find(v),
              ),
            ),
            if (_findCtrl.text.isNotEmpty)
              Text('$_findCount found',
                  semanticsLabel: '$_findCount matches found'),
            IconButton(
                tooltip: 'Previous match',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: () => _find(_findCtrl.text, backwards: true)),
            IconButton(
                tooltip: 'Next match',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: () => _find(_findCtrl.text)),
            IconButton(
                tooltip: 'Close find bar',
                icon: const Icon(Icons.close),
                onPressed: _closeFind),
          ]),
        ),
      );

  Widget _bottomBar() => BottomAppBar(
        height: 56,
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => tab.controller?.goBack()),
            IconButton(
                tooltip: 'Forward',
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => tab.controller?.goForward()),
            IconButton(
                tooltip: 'Home',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => _load(tab, s.engine.home)),
            IconButton(
                tooltip: 'Bookmarks',
                icon: const Icon(Icons.bookmarks_outlined),
                onPressed: _openBookmarks),
            IconButton(
                tooltip: 'New tab',
                icon: const Icon(Icons.add_box_outlined),
                onPressed: () => _newTab()),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Tablets (>= 600 dp wide) and Windows get the desktop layout.
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyT, control: true): () =>
              _newTab(),
          const SingleActivator(LogicalKeyboardKey.keyN,
              control: true, shift: true): () => _newTab(incognito: true),
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
              _closeTab(_current),
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
              _addressFocus.requestFocus(),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openFind,
          const SingleActivator(LogicalKeyboardKey.keyR, control: true):
              _reload,
          const SingleActivator(LogicalKeyboardKey.f5): _reload,
          const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
              s.toggleBookmark(tab.title, tab.url),
          const SingleActivator(LogicalKeyboardKey.keyH, control: true):
              _openHistory,
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true):
              _openDownloads,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              bottom: wide,
              child: Column(children: [
                if (wide) _tabStrip(scheme),
                _toolbar(wide, scheme),
                SizedBox(
                  height: 2,
                  child: tab.progress < 1
                      ? LinearProgressIndicator(
                          value: tab.progress,
                          semanticsLabel: 'Page loading')
                      : null,
                ),
                if (_findOpen) _findBar(),
                Expanded(
                  child: IndexedStack(
                    index: _current,
                    children: [
                      for (final t in _tabs)
                        KeyedSubtree(key: ObjectKey(t), child: _tabView(t)),
                    ],
                  ),
                ),
              ]),
            ),
            bottomNavigationBar: wide ? null : _bottomBar(),
          ),
        ),
      ),
    );
  }
}

/// Shows the real site name: sub-domain dimmed, owner domain in bold,
/// plus "Not secure" and a warning icon for look-alike addresses.
class _DomainLabel extends StatelessWidget {
  const _DomainLabel({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final u = Uri.tryParse(url);
    final host = u?.host ?? '';
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(fontSize: 15, color: scheme.onSurface);
    if (u == null || host.isEmpty) {
      return Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: base);
    }
    final main = registrableDomain(host);
    final sub =
        host.length > main.length ? host.substring(0, host.length - main.length) : '';
    final risky = suspiciousReason(url) != null;
    final insecure = u.scheme == 'http';
    return Semantics(
      label: '${insecure ? 'Not secure. ' : ''}'
          '${risky ? 'Warning, check this address. ' : ''}'
          'Site $host. Tap to edit the address.',
      excludeSemantics: true,
      child: Row(children: [
        if (insecure)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text('Not secure',
                style: base.copyWith(
                    color: scheme.error, fontWeight: FontWeight.w600)),
          ),
        if (sub.isNotEmpty)
          Flexible(
            child: Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: base.copyWith(color: scheme.onSurfaceVariant)),
          ),
        Flexible(
          flex: 4,
          child: Text(main,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: base.copyWith(
                  fontWeight: FontWeight.bold,
                  color: risky ? scheme.error : scheme.onSurface)),
        ),
        if (risky)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.gpp_maybe, size: 16, color: scheme.error),
          ),
      ]),
    );
  }
}
