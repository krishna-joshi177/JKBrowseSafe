import 'package:flutter/material.dart';

import '../models.dart';
import '../url_utils.dart';

/// Friendly full-page error / offline / crash / danger screen.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.kind,
    required this.url,
    required this.detail,
    required this.onRetry,
    required this.onBack,
    this.onContinueInsecure,
  });

  final TabErrorKind kind;
  final String url;
  final String detail;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final VoidCallback? onContinueInsecure;

  @override
  Widget build(BuildContext context) {
    final host = hostOf(url).isEmpty ? 'This site' : hostOf(url);
    late final IconData icon;
    late final String title;
    late final String message;
    switch (kind) {
      case TabErrorKind.offline:
        icon = Icons.wifi_off;
        title = "You're offline";
        message = 'Check your Wi-Fi or mobile data, then try again.';
      case TabErrorKind.ssl:
        icon = Icons.gpp_bad_outlined;
        title = "Your connection isn't private";
        message = "$host's security certificate isn't valid or trusted. "
            'Someone might be trying to steal your information, so '
            'JKBrowseSafe blocked the page. This warning cannot be skipped.';
      case TabErrorKind.dangerous:
        icon = Icons.dangerous_outlined;
        title = 'Dangerous site blocked';
        message = '$host has been reported for phishing or malware. It may '
            'try to steal your passwords or harm your device.';
      case TabErrorKind.crashed:
        icon = Icons.sentiment_dissatisfied_outlined;
        title = 'This page crashed';
        message = 'Something went wrong while showing this page.';
      case TabErrorKind.httpsUnavailable:
        icon = Icons.lock_open;
        title = 'Secure connection not available';
        message = "$host doesn't support a secure (HTTPS) connection. If you "
            'continue, anything you send to this site can be seen by others.';
      case TabErrorKind.network:
      case TabErrorKind.none:
        icon = Icons.cloud_off;
        title = "This site can't be reached";
        message = '$host might be down, or the address might be wrong.';
    }

    final theme = Theme.of(context);
    final danger = kind == TabErrorKind.ssl || kind == TabErrorKind.dangerous;
    return Container(
      color: danger ? theme.colorScheme.errorContainer : theme.colorScheme.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    size: 56,
                    color: danger
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    semanticLabel: title),
                const SizedBox(height: 16),
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(message, style: theme.textTheme.bodyLarge),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(detail,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
                const SizedBox(height: 24),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  if (danger)
                    FilledButton(
                        onPressed: onBack, child: const Text('Back to safety'))
                  else
                    FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again')),
                  if (!danger)
                    OutlinedButton(
                        onPressed: onBack, child: const Text('Go back')),
                  if (onContinueInsecure != null)
                    TextButton(
                        onPressed: onContinueInsecure,
                        child: Text(kind == TabErrorKind.dangerous
                            ? 'Ignore warning and visit (unsafe)'
                            : 'Continue to site (not secure)')),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
