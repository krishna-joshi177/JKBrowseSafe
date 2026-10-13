import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_state.dart';
import 'download_manager.dart';

/// Lets the user clear each kind of browsing data separately.
Future<void> showClearDataDialog(
    BuildContext context, AppState state, DownloadManager downloads) async {
  var history = true;
  var cookies = false;
  var cache = true;
  var permissions = false;
  var downloadList = false;

  final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            title: const Text('Clear browsing data'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CheckboxListTile(
                  value: history,
                  onChanged: (v) => setD(() => history = v ?? false),
                  title: const Text('Browsing history'),
                ),
                CheckboxListTile(
                  value: cookies,
                  onChanged: (v) => setD(() => cookies = v ?? false),
                  title: const Text('Cookies and site data'),
                  subtitle: const Text('Signs you out of most sites'),
                ),
                CheckboxListTile(
                  value: cache,
                  onChanged: (v) => setD(() => cache = v ?? false),
                  title: const Text('Cached images and files'),
                ),
                CheckboxListTile(
                  value: permissions,
                  onChanged: (v) => setD(() => permissions = v ?? false),
                  title: const Text('Site permissions'),
                ),
                CheckboxListTile(
                  value: downloadList,
                  onChanged: (v) => setD(() => downloadList = v ?? false),
                  title: const Text('Download list'),
                  subtitle: const Text('Downloaded files are kept'),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Clear data')),
            ],
          ),
        ),
      ) ??
      false;
  if (!ok) return;

  if (history) state.clearHistory();
  if (cookies) {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {}
    if (Platform.isAndroid) {
      try {
        await WebStorageManager.instance().deleteAllData();
      } catch (_) {}
    }
  }
  if (cache) {
    try {
      await InAppWebViewController.clearAllCache();
    } catch (_) {}
  }
  if (permissions) state.clearSitePermissions();
  if (downloadList) downloads.clearFinished();

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected data cleared')));
  }
}
