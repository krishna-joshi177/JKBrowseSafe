import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../permissions.dart';

/// Per-site camera, microphone, location and notification controls.
/// If [origin] is given, only that site is shown.
class SiteSettingsPage extends StatelessWidget {
  const SiteSettingsPage({super.key, required this.state, this.origin});
  final AppState state;
  final String? origin;

  List<String> _keysFor(String site) {
    final keys = <String>[...basePermissionKeys];
    for (final k in state.sitePerms[site]?.keys ?? const <String>[]) {
      if (!keys.contains(k)) keys.add(k);
    }
    return keys;
  }

  Future<void> _resetAll(BuildContext context) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reset all site permissions?'),
            content: const Text('Sites will ask again next time.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Reset')),
            ],
          ),
        ) ??
        false;
    if (ok) state.clearSitePermissions();
  }

  Widget _permissionRow(String site, String key) {
    final unsupported = Platform.isAndroid && key == 'notifications';
    final value = unsupported ? 'block' : (state.sitePermission(site, key) ?? 'ask');
    return ListTile(
      leading: Icon(permissionIcon(key)),
      title: Text(permissionLabel(key)),
      subtitle: unsupported
          ? const Text('Websites cannot send notifications on Android')
          : null,
      trailing: DropdownButton<String>(
        value: value,
        onChanged: unsupported
            ? null
            : (v) => state.setSitePermission(site, key, v == 'ask' ? null : v),
        items: const [
          DropdownMenuItem(value: 'ask', child: Text('Ask')),
          DropdownMenuItem(value: 'allow', child: Text('Allow')),
          DropdownMenuItem(value: 'block', child: Text('Block')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final List<String> sites;
        if (origin != null) {
          sites = <String>[origin!];
        } else {
          sites = state.sitePerms.keys.toList()..sort();
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(origin == null ? 'Site settings' : 'Site permissions'),
            actions: [
              if (origin == null && sites.isNotEmpty)
                TextButton(
                    onPressed: () => _resetAll(context),
                    child: const Text('Reset all')),
            ],
          ),
          body: sites.isEmpty
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                      'Sites you allow or block will appear here.\n'
                      'Sites without a saved choice will ask you first.',
                      textAlign: TextAlign.center),
                ))
              : ListView(
                  children: [
                    for (final site in sites)
                      ExpansionTile(
                        initiallyExpanded: origin != null,
                        leading: const Icon(Icons.language),
                        title: Text(site,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        children: [
                          for (final k in _keysFor(site)) _permissionRow(site, k),
                          ListTile(
                            leading: const Icon(Icons.restart_alt),
                            title: const Text('Reset permissions for this site'),
                            onTap: () => state.removeSite(site),
                          ),
                        ],
                      ),
                  ],
                ),
        );
      },
    );
  }
}
