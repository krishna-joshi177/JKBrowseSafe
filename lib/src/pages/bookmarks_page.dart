import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../bookmark_io.dart';
import '../download_manager.dart';
import '../models.dart';

/// Lists bookmarks. Returns the URL to open (or null).
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key, required this.state});
  final AppState state;

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  String _q = '';

  void _snack(String msg, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _import() async {
    try {
      final group = XTypeGroup(
        label: 'Bookmarks',
        extensions: <String>['html', 'htm', 'json'],
        mimeTypes: <String>['text/html', 'application/json', 'text/plain'],
      );
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
      if (file == null) return;
      final text = await file.readAsString();
      final found = parseBookmarks(text);
      final added = widget.state.importBookmarks(found);
      _snack(found.isEmpty
          ? 'No bookmarks found in that file'
          : 'Imported $added new bookmark${added == 1 ? '' : 's'}');
    } catch (e) {
      _snack('Could not import: $e');
    }
  }

  Future<void> _export() async {
    try {
      final dir = await DownloadManager.downloadDirectory();
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${dir.path}${Platform.pathSeparator}'
          'jkbrowsesafe_bookmarks_$stamp.html');
      await file.writeAsString(exportBookmarksHtml(widget.state.bookmarks));
      if (Platform.isAndroid) {
        await Share.shareXFiles(<XFile>[XFile(file.path)],
            subject: 'JKBrowseSafe bookmarks');
      } else {
        _snack('Saved to ${file.path}',
            action: SnackBarAction(
                label: 'Open folder',
                onPressed: () => launchUrl(Uri.file(dir.path))));
      }
    } catch (e) {
      _snack('Could not export: $e');
    }
  }

  Future<void> _edit(Bookmark b) async {
    final title = TextEditingController(text: b.title);
    final url = TextEditingController(text: b.url);
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Edit bookmark'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'URL')),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save')),
            ],
          ),
        ) ??
        false;
    final newUrl = url.text.trim();
    if (ok) {
      if (newUrl.startsWith('http://') || newUrl.startsWith('https://')) {
        widget.state.updateBookmark(b, title.text.trim(), newUrl);
      } else {
        _snack('URL must start with http:// or https://');
      }
    }
    title.dispose();
    url.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final items = widget.state.bookmarks
            .where((b) =>
                _q.isEmpty ||
                b.title.toLowerCase().contains(_q) ||
                b.url.toLowerCase().contains(_q))
            .toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Bookmarks'), actions: [
            IconButton(
                tooltip: 'Import bookmarks',
                icon: const Icon(Icons.file_upload_outlined),
                onPressed: _import),
            IconButton(
                tooltip: 'Export bookmarks',
                icon: const Icon(Icons.file_download_outlined),
                onPressed: _export),
          ]),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search bookmarks',
                    border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'No bookmarks yet. Tap the star in the address bar '
                          'to add one, or import bookmarks from another browser.',
                          textAlign: TextAlign.center),
                    ))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final b = items[i];
                        return ListTile(
                          leading: const Icon(Icons.star_outline),
                          title: Text(b.title.isEmpty ? b.url : b.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(b.url,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.pop(context, b.url),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Bookmark options',
                            onSelected: (v) {
                              if (v == 'edit') _edit(b);
                              if (v == 'delete') widget.state.removeBookmark(b);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    );
  }
}
