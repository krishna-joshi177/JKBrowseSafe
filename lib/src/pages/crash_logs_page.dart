import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../crash_reporter.dart';

class CrashLogsPage extends StatefulWidget {
  const CrashLogsPage({super.key});

  @override
  State<CrashLogsPage> createState() => _CrashLogsPageState();
}

class _CrashLogsPageState extends State<CrashLogsPage> {
  late Future<String> _log = CrashReporter.read();

  Future<void> _share(String text) async {
    if (Platform.isAndroid) {
      await Share.share(text, subject: 'JKBrowseSafe crash log');
    } else {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Crash log copied')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _log,
      builder: (context, snap) {
        final text = snap.data ?? '';
        return Scaffold(
          appBar: AppBar(title: const Text('Crash logs'), actions: [
            if (text.isNotEmpty)
              IconButton(
                  tooltip: Platform.isAndroid ? 'Share log' : 'Copy log',
                  icon: Icon(Platform.isAndroid ? Icons.share : Icons.copy),
                  onPressed: () => _share(text)),
            if (text.isNotEmpty)
              IconButton(
                  tooltip: 'Delete logs',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await CrashReporter.clear();
                    setState(() => _log = CrashReporter.read());
                  }),
          ]),
          body: text.isEmpty
              ? const Center(child: Text('No crashes recorded'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(text,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12)),
                ),
        );
      },
    );
  }
}
