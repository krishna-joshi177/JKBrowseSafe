import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../clear_data.dart';
import '../constants.dart';
import '../download_manager.dart';
import '../models.dart';
import '../threat_lists.dart';
import 'crash_logs_page.dart';
import 'privacy_page.dart';
import 'site_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state, required this.downloads});
  final AppState state;
  final DownloadManager downloads;

  String _themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'Use device setting',
      };

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _when(DateTime? d) => d == null
      ? 'never'
      : '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

  Future<void> _pickEngine(BuildContext context) async {
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Search engine'),
        children: [
          for (final e in searchEngines)
            ListTile(
              leading: Icon(e.id == state.engineId
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(e.name),
              onTap: () => Navigator.pop(ctx, e.id),
            ),
        ],
      ),
    );
    if (id != null) state.setEngine(id);
  }

  Future<void> _pickTheme(BuildContext context) async {
    final m = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final mode in ThemeMode.values)
            ListTile(
              leading: Icon(mode == state.themeMode
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(_themeLabel(mode)),
              onTap: () => Navigator.pop(ctx, mode),
            ),
        ],
      ),
    );
    if (m != null) state.setThemeMode(m);
  }

  Future<void> _updateLists(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ThreatLists.instance.update();
    messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? 'Protection lists updated'
            : (ThreatLists.instance.lastError ?? 'Could not update lists'))));
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final lists = ThreatLists.instance;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[state, lists]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(children: [
          _header(context, 'General'),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search engine'),
            subtitle: Text(state.engine.name),
            onTap: () => _pickEngine(context),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(state.themeMode)),
            onTap: () => _pickTheme(context),
          ),
          if (Platform.isAndroid)
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark web pages'),
              subtitle: const Text(
                  'Darken websites when the app uses a dark theme (Android 13+)'),
              value: state.forceDarkPages,
              onChanged: state.setForceDarkPages,
            ),
          if (Platform.isAndroid)
            ListTile(
              leading: const Icon(Icons.format_size),
              title: Text('Page text size: ${state.textZoom}%'),
              subtitle: Slider(
                value: state.textZoom.toDouble(),
                min: 50,
                max: 200,
                divisions: 15,
                label: '${state.textZoom}%',
                semanticFormatterCallback: (v) => '${v.round()} percent',
                onChanged: (v) => state.setTextZoom(v.round()),
              ),
            ),
          _header(context, 'Privacy and security'),
          SwitchListTile(
            secondary: const Icon(Icons.shield_outlined),
            title: const Text('Block trackers and ads'),
            subtitle: const Text('Blocks known tracking and advertising sites'),
            value: state.blockTrackers,
            onChanged: state.setBlockTrackers,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.https_outlined),
            title: const Text('HTTPS-only mode'),
            subtitle: const Text('On: try a secure connection first. '
                'Off: warn before opening insecure (http) sites.'),
            value: state.httpsOnly,
            onChanged: state.setHttpsOnly,
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Protection lists'),
            subtitle: Text(lists.updating
                ? 'Updating…'
                : 'Trackers: ${lists.trackerCount} • Dangerous sites: '
                    '${lists.threatCount}\nUpdated: ${_when(lists.lastUpdated)} '
                    '(updates daily)'),
            isThreeLine: true,
            trailing: TextButton(
              onPressed: lists.updating ? null : () => _updateLists(context),
              child: const Text('Update now'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('JavaScript'),
            subtitle: Text(state.jsBlocked.isEmpty
                ? 'Allowed on all sites'
                : 'Allowed, except on ${state.jsBlocked.length} '
                    'site${state.jsBlocked.length == 1 ? '' : 's'}'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => HostListPage(
                          state: state,
                          title: 'JavaScript blocked on',
                          empty: 'JavaScript is allowed on all sites.\n'
                              'To block it on a site, tap the lock icon in '
                              'the address bar.',
                          hosts: () => state.jsBlocked.toList()..sort(),
                          onRemove: (h) => state.setJsEnabled(h, true),
                        ))),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Blocked sites'),
            subtitle: Text(state.blockedSites.isEmpty
                ? 'None'
                : '${state.blockedSites.length} '
                    'site${state.blockedSites.length == 1 ? '' : 's'}'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => HostListPage(
                          state: state,
                          title: 'Blocked sites',
                          empty: 'Sites you block with "Report unsafe site" '
                              'appear here.',
                          hosts: () => state.blockedSites.toList()..sort(),
                          onRemove: state.unblockSite,
                        ))),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Site settings'),
            subtitle: const Text('Camera, microphone, location, notifications'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => SiteSettingsPage(state: state))),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear browsing data'),
            subtitle: const Text(
                'History, cookies, cache, permissions — choose what to clear'),
            onTap: () => showClearDataDialog(context, state, downloads),
          ),
          _header(context, 'Diagnostics'),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report_outlined),
            title: const Text('Save crash logs on this device'),
            subtitle: const Text(
                'Web addresses are removed. Nothing is sent automatically.'),
            value: state.crashLogs,
            onChanged: state.setCrashLogs,
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('View crash logs'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const CrashLogsPage())),
          ),
          _header(context, 'About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text(appName),
            subtitle: Text('Version $appVersion'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            subtitle: const Text('What JKBrowseSafe does and does not collect'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const PrivacyPage())),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Open-source licenses'),
            onTap: () => showLicensePage(
                context: context,
                applicationName: appName,
                applicationVersion: appVersion),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

/// A simple list of site names with a remove button.
class HostListPage extends StatelessWidget {
  const HostListPage({
    super.key,
    required this.state,
    required this.title,
    required this.empty,
    required this.hosts,
    required this.onRemove,
  });

  final AppState state;
  final String title;
  final String empty;
  final List<String> Function() hosts;
  final void Function(String host) onRemove;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final list = hosts();
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: list.isEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(empty, textAlign: TextAlign.center),
                ))
              : ListView(children: [
                  for (final h in list)
                    ListTile(
                      leading: const Icon(Icons.language),
                      title: Text(h),
                      trailing: IconButton(
                        tooltip: 'Remove $h',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onRemove(h),
                      ),
                    ),
                ]),
        );
      },
    );
  }
}
