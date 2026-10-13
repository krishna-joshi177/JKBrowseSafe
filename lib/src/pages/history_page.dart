import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';

/// Browsing history grouped by day. Returns the URL to open (or null).
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.state});
  final AppState state;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _q = '';

  String _two(int n) => n.toString().padLeft(2, '0');

  String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${day.year}-${_two(day.month)}-${_two(day.day)}';
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Clear all history?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Clear')),
            ],
          ),
        ) ??
        false;
    if (ok) widget.state.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final entries = widget.state.history
            .where((h) =>
                _q.isEmpty ||
                h.title.toLowerCase().contains(_q) ||
                h.url.toLowerCase().contains(_q))
            .toList();
        final rows = <Object>[];
        String? lastDay;
        for (final e in entries) {
          final d = _dayLabel(e.time);
          if (d != lastDay) {
            rows.add(d);
            lastDay = d;
          }
          rows.add(e);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('History'), actions: [
            if (widget.state.history.isNotEmpty)
              TextButton(onPressed: _clearAll, child: const Text('Clear all')),
          ]),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search history',
                    border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No history'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        if (r is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                            child: Text(r,
                                style: Theme.of(context).textTheme.titleSmall),
                          );
                        }
                        final h = r as HistoryEntry;
                        return ListTile(
                          leading: const Icon(Icons.public),
                          title: Text(h.title.isEmpty ? h.url : h.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${_two(h.time.hour)}:${_two(h.time.minute)}  ${h.url}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.pop(context, h.url),
                          trailing: IconButton(
                            tooltip: 'Remove from history',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => widget.state.removeHistory(h),
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
