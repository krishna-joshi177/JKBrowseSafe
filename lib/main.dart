import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'src/app_state.dart';
import 'src/browser_page.dart';
import 'src/constants.dart';
import 'src/crash_reporter.dart';
import 'src/download_manager.dart';

void main() {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await CrashReporter.init();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CrashReporter.record(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      CrashReporter.record(error, stack);
      return true;
    };
    final state = await AppState.load();
    final downloads = DownloadManager(state);
    runApp(JKBrowseSafeApp(state: state, downloads: downloads));
  }, (error, stack) => CrashReporter.record(error, stack));
}

class JKBrowseSafeApp extends StatelessWidget {
  const JKBrowseSafeApp(
      {super.key, required this.state, required this.downloads});
  final AppState state;
  final DownloadManager downloads;

  static ThemeData _theme(Brightness b) => ThemeData(
        colorSchemeSeed: const Color(0xFF1E6FD9),
        brightness: b,
        useMaterial3: true,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        themeMode: state.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: BrowserPage(state: state, downloads: downloads),
      ),
    );
  }
}
