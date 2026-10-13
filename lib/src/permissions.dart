import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Base permissions shown for every site in Site settings.
const List<String> basePermissionKeys = <String>[
  'camera', 'microphone', 'location', 'notifications',
];

String permissionKey(PermissionResourceType r) {
  if (r == PermissionResourceType.CAMERA) return 'camera';
  if (r == PermissionResourceType.MICROPHONE) return 'microphone';
  final n = r.toString().toLowerCase();
  if (n.contains('location')) return 'location';
  if (n.contains('notification')) return 'notifications';
  if (n.contains('clipboard')) return 'clipboard';
  if (n.contains('protected')) return 'protected_media';
  if (n.contains('midi')) return 'midi';
  return 'other';
}

String permissionLabel(String key) {
  switch (key) {
    case 'camera':
      return 'Camera';
    case 'microphone':
      return 'Microphone';
    case 'location':
      return 'Location';
    case 'notifications':
      return 'Notifications';
    case 'clipboard':
      return 'Clipboard';
    case 'protected_media':
      return 'Protected content';
    case 'midi':
      return 'MIDI devices';
    default:
      return 'Other permissions';
  }
}

IconData permissionIcon(String key) {
  switch (key) {
    case 'camera':
      return Icons.videocam_outlined;
    case 'microphone':
      return Icons.mic_none;
    case 'location':
      return Icons.location_on_outlined;
    case 'notifications':
      return Icons.notifications_none;
    case 'clipboard':
      return Icons.content_paste;
    case 'protected_media':
      return Icons.lock_outline;
    case 'midi':
      return Icons.piano;
    default:
      return Icons.extension_outlined;
  }
}
