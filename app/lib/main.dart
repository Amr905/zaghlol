import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'ingestion/foreground_ingestion.dart';
import 'ingestion/ingestion_config.dart';
import 'ingestion/ingestion_main.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // T-041: foreground ingestion in devSms only (the build with a capture
  // source until T-040); T-047 wires it for every build behind its startup
  // gate. A compile-time constant, so other builds drop it.
  if (kIsSpikeBuild) startForegroundIngestion();
  runApp(const ZaghlolApp());
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
