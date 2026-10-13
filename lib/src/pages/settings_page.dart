import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../clear_data.dart';
import '../constants.dart';
import '../download_manager.dart';
import '../models.dart';
import 'crash_logs_page.dart';
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
    return ListenableBuilder(
      listenable: state,
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
            subtitle: const Text(
                'Use secure connections and warn before loading insecure sites'),
            value: state.httpsOnly,
            onChanged: state.setHttpsOnly,
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
