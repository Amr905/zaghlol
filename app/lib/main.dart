import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/db_directory.dart';
import 'core/db/db_key_providers.dart';
import 'core/theme/app_theme.dart';
import 'features/capture/presentation/capture_lifecycle.dart';
import 'ingestion/ingestion_main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dbDirectory = await resolveDbDirectory();
  // T-047: the UI engine's capture module (drain, Guard config, health) runs
  // in every build; it starts once the database opens.
  runApp(
    ProviderScope(
      overrides: [dbDirectoryProvider.overrideWithValue(dbDirectory)],
      child: const CaptureLifecycle(child: ZaghlolApp()),
    ),
  );
}

/// T-041: the headless ingestion engine's entrypoint (every build). The
/// IngestionWorker starts it by name in this (root) library; `vm:entry-point`
/// keeps it in AOT builds.
@pragma('vm:entry-point')
void ingestionMain() => runIngestionMain();

/// Root widget. Placeholder until theming, routing and l10n land in later
/// tasks; it deliberately contains no user-facing strings.
class ZaghlolApp extends StatelessWidget {
  const ZaghlolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ZaghlolTheme.light,
      darkTheme: ZaghlolTheme.dark,
      home: const Scaffold(body: SizedBox.shrink()),
    );
  }
}
