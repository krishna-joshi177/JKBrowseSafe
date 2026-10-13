import 'package:flutter/material.dart';

import '../models.dart';
import '../url_utils.dart';

/// Friendly full-page error / offline / crash screen.
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
        message = "$host's security certificate isn't trusted. Someone might "
            'be trying to steal your information, so the page was blocked.';
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
    final isSsl = kind == TabErrorKind.ssl;

    return Container(
      color: theme.colorScheme.surface,
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
                    color: isSsl
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
                  if (isSsl)
                    FilledButton(
                        onPressed: onBack, child: const Text('Back to safety'))
                  else
                    FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again')),
                  if (!isSsl)
                    OutlinedButton(
                        onPressed: onBack, child: const Text('Go back')),
                  if (onContinueInsecure != null)
                    TextButton(
                        onPressed: onContinueInsecure,
                        child: const Text('Continue to site (not secure)')),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
