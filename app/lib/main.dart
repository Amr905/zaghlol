import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_navigation.dart';
import 'app/app_restart.dart';
import 'app/notification_taps.dart';
import 'app/onboarding_gate.dart';
import 'app/url_launcher_opener.dart';
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
import 'features/notifications/application/notification_providers.dart';
import 'features/security/application/delete_everything_providers.dart';
import 'features/widgets_bridge/application/widget_bridge.dart'
    show widgetBridgeWiringProvider;
import 'features/security/presentation/app_lock_gate.dart';
import 'ingestion/ingestion_runner.dart' show ensureDefaultRegistry;
import 'ingestion/ingestion_main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // FU-119: intl date symbols for ar/en before any date is formatted.
  await initDateFormatting();
  final dbDirectory = await resolveDbDirectory();
  // T-166: an unfinished "Delete everything" is completed before anything
  // opens the database.
  await _resumeWipe(dbDirectory);
  // SMS-TEMPLATES: the bundled registry is read once; the capture providers
  // and the scan service take it synchronously. A failure leaves capture off
  // (the providers see `INGEST_REGISTRY_MISSING`), never a crash.
  try {
    await ensureDefaultRegistry();
  } on Object {
    // Capture stays off for this launch.
  }
  // T-047: the UI engine's capture module (drain, Guard config, health) runs
  // in every build; it starts once the database opens.
  runApp(
    AppRestartScope(
      beforeStart: () => _resumeWipe(dbDirectory),
      builder: (context, restart) => ProviderScope(
        overrides: [
          // T-166: restart into first-launch state after Delete everything.
          appRestartProvider.overrideWithValue(restart),
          ...deleteEverythingWiringOverrides,
          dbDirectoryProvider.overrideWithValue(dbDirectory),
          // WIRE-NAV: the four tabs and every pushed route, wired.
          tabRootsProvider.overrideWithValue(wiredTabRoots),
          // T-143 / FU-115 / FU-138: backend client, entitlement service, sync.
          ...syncWiringOverrides,
          // T-145: seat keys and the purchase flow.
          ...goldWiringOverrides,
          // T-100: backup failure and reminder alerts through notifications.
          backupAlertSinkOverride,
          // NOTIF-GW: the real local-notification gateway, permission and taps.
          ...notificationWiringOverrides,
          // WIRE-NAV: paywall trigger, Gold sign-in, links, chart card opener.
          ...navigationWiringOverrides(rootNavigatorKey),
          // FU-195: external links open through url_launcher.
          externalUrlOpenerOverride,
          // T-086: new-card channel toggles become ignore rules (T-078).
          cardCapturePortProvider.overrideWith(
            (ref) => ref.watch(captureCardPortProvider),
          ),
        ],
        child: const CaptureLifecycle(
          child: SyncLifecycle(
            child: NotificationTapLifecycle(child: _LocalizedApp()),
          ),
        ),
      ),
    ),
  );
}

Future<void> _resumeWipe(Directory dbDirectory) async {
  try {
    await resumePendingWipe(dbDirectory);
  } on Object {
    // The marker stays; the next launch tries again.
  }
}

/// T-041: the headless ingestion engine's entrypoint (every build). The
/// IngestionWorker starts it by name in this (root) library; `vm:entry-point`
/// keeps it in AOT builds.
@pragma('vm:entry-point')
void ingestionMain() => runIngestionMain();

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
      builder: (context, child) => AppLockGate(
        child: OnboardingGate(child: child ?? const SizedBox.shrink()),
      ),
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
    // T-100: the weekly summary (when 7 days have passed) and the duplicate
    // check at start; again on every resume.
    unawaited(ref.read(alertsResumeProvider)());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(alertsResumeProvider)());
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
    // T-118: the home-screen widget follows the cycle overview.
    ref.watch(widgetBridgeWiringProvider);
    return ZaghlolApp(locale: ref.watch(appLocaleProvider));
  }
}
