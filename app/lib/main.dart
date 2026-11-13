import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/db_directory.dart';
import 'core/db/db_key_providers.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_providers.dart';
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
      child: const CaptureLifecycle(child: _LocalizedApp()),
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
  const ZaghlolApp({super.key, this.locale});

  /// null follows the device; the language setting supplies it (T-023).
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ZaghlolTheme.light,
      darkTheme: ZaghlolTheme.dark,
      home: const Scaffold(body: SizedBox.shrink()),
    );
  }
}

/// Feeds the language setting into [ZaghlolApp]: a change flips direction
/// live, no restart.
class _LocalizedApp extends ConsumerWidget {
  const _LocalizedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ZaghlolApp(locale: ref.watch(appLocaleProvider));
}
