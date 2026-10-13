import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../download_manager.dart';
import '../url_utils.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key, required this.downloads});
  final DownloadManager downloads;

  Future<void> _open(BuildContext context, DownloadItem d) async {
    final path = d.path;
    if (path == null || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File no longer exists')));
      return;
    }
    if (Platform.isAndroid) {
      await Share.shareXFiles(<XFile>[XFile(path)]);
    } else {
      await launchUrl(Uri.file(path));
    }
  }

  String _subtitle(DownloadItem d) {
    switch (d.status) {
      case DownloadStatus.running:
        final total = d.total;
        return total == null
            ? '${formatBytes(d.received)} downloaded'
            : '${formatBytes(d.received)} of ${formatBytes(total)}';
      case DownloadStatus.done:
        return '${formatBytes(d.received)} • Complete';
      case DownloadStatus.failed:
        return 'Failed: ${d.error ?? 'unknown error'}';
      case DownloadStatus.cancelled:
        return 'Cancelled';
    }
  }

  IconData _icon(DownloadStatus s) {
    switch (s) {
      case DownloadStatus.running:
        return Icons.downloading;
      case DownloadStatus.done:
        return Icons.insert_drive_file_outlined;
      case DownloadStatus.failed:
        return Icons.error_outline;
      case DownloadStatus.cancelled:
        return Icons.block;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final items = downloads.items;
        return Scaffold(
          appBar: AppBar(title: const Text('Downloads'), actions: [
            if (items.any((d) => d.status != DownloadStatus.running))
              TextButton(
                  onPressed: downloads.clearFinished,
                  child: const Text('Clear list')),
          ]),
          body: Column(children: [
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('No downloads yet'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = items[i];
                        final running = d.status == DownloadStatus.running;
                        return ListTile(
                          leading: Icon(_icon(d.status)),
                          title: Text(d.fileName,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (running)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: LinearProgressIndicator(
                                      value: d.fraction),
                                ),
                              Text(_subtitle(d),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                          onTap: d.status == DownloadStatus.done
                              ? () => _open(context, d)
                              : null,
                          trailing: running
                              ? IconButton(
                                  tooltip: 'Cancel download',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => downloads.cancel(d))
                              : PopupMenuButton<String>(
                                  tooltip: 'Download options',
                                  onSelected: (v) {
                                    if (v == 'open') _open(context, d);
                                    if (v == 'delete') downloads.deleteFile(d);
                                    if (v == 'remove') downloads.remove(d);
                                  },
                                  itemBuilder: (_) => [
                                    if (d.status == DownloadStatus.done)
                                      PopupMenuItem(
                                          value: 'open',
                                          child: Text(Platform.isAndroid
                                              ? 'Open with…'
                                              : 'Open')),
                                    if (d.status == DownloadStatus.done)
                                      const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete file')),
                                    const PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remove from list')),
                                  ],
                                ),
                        );
                      },
                    ),
            ),
            FutureBuilder<Directory>(
              future: DownloadManager.downloadDirectory(),
              builder: (context, snap) => snap.hasData
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('Files are saved to: ${snap.data!.path}',
                          style: Theme.of(context).textTheme.bodySmall),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        );
      },
    );
  }
}
