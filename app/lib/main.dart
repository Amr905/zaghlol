import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/db_directory.dart';
import 'core/db/db_key_providers.dart';
import 'core/l10n/date_format.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_providers.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/accounts/presentation/edit_card/edit_card_providers.dart'
    show cardCapturePortProvider;
import 'features/budget/application/cycle_app_wiring.dart';
import 'features/capture/presentation/capture_controls.dart'
    show captureCardPortProvider;
import 'features/capture/presentation/capture_lifecycle.dart';
import 'features/gold/application/gold_providers.dart';
import 'features/catalog_sync/application/sync_providers.dart';
import 'features/catalog_sync/presentation/sync_lifecycle.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/security/presentation/app_lock_gate.dart';
import 'ingestion/ingestion_main.dart';
import 'ingestion/ios_intent_spike.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // FU-119: intl date symbols for ar/en before any date is formatted.
  await initDateFormatting();
  final dbDirectory = await resolveDbDirectory();
  // T-047: the UI engine's capture module (drain, Guard config, health) runs
  // in every build; it starts once the database opens.
  runApp(
    ProviderScope(
      overrides: [
        dbDirectoryProvider.overrideWithValue(dbDirectory),
        // T-054: Home is the first tab.
        tabRootsProvider.overrideWithValue(
          TabRoots(home: (_) => const HomeScreen()),
        ),
        // T-143 / FU-115 / FU-138: backend client, entitlement service, sync.
        ...syncWiringOverrides,
        // T-145: seat keys and the purchase flow.
        ...goldWiringOverrides,
        // T-086: new-card channel toggles become ignore rules (T-078).
        cardCapturePortProvider.overrideWith(
          (ref) => ref.watch(captureCardPortProvider),
        ),
      ],
      child: const CaptureLifecycle(
        child: SyncLifecycle(child: _LocalizedApp()),
      ),
    ),
  );
}

/// T-041: the headless ingestion engine's entrypoint (every build). The
/// IngestionWorker starts it by name in this (root) library; `vm:entry-point`
/// keeps it in AOT builds.
@pragma('vm:entry-point')
void ingestionMain() => runIngestionMain();

/// T-009 spike: entrypoint of the iOS App Intent's headless engine.
@pragma('vm:entry-point')
void spikeIntentMain() => runIosIntentSpike();

@pragma('vm:entry-point')
void spikeIntentSilentMain() => runIosIntentSpikeSilent();

/// Root widget: themed, localized, routed through the T-024 shell. It holds
/// no user-facing strings itself.
class ZaghlolApp extends ConsumerWidget {
  const ZaghlolApp({super.key, this.locale});

  /// null follows the device; the language setting supplies it (T-023).
  final Locale? locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: ZaghlolTheme.light,
      darkTheme: ZaghlolTheme.dark,
      routerConfig: ref.watch(appRouterProvider),
      // T-103: app lock, privacy cover and secure window over the whole app.
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Feeds the language setting into [ZaghlolApp]: a change flips direction
/// live, no restart. It also keeps the cycle cache wiring alive and tells it
/// when the app returns to the foreground (T-052 / FU-110).
class _LocalizedApp extends ConsumerStatefulWidget {
  const _LocalizedApp();

  @override
  ConsumerState<_LocalizedApp> createState() => _LocalizedAppState();
}

class _LocalizedAppState extends ConsumerState<_LocalizedApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref
            .read(cycleResumeHandlerProvider)
            .onResume()
            .then<Object?>((_) => null)
            .catchError((Object _) => null),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cycleAppWiringProvider);
    return ZaghlolApp(locale: ref.watch(appLocaleProvider));
  }
}
