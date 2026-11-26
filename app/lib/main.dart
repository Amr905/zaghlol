import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_navigation.dart';
import 'app/app_restart.dart';
import 'app/notification_taps.dart';
import 'app/onboarding_gate.dart';
import 'app/url_launcher_opener.dart';
import 'core/catalog/catalog_providers.dart';
import 'core/db/db_directory.dart';
import 'core/db/db_key_providers.dart';
import 'core/l10n/date_format.dart';
import 'core/logging/diag_code.dart';
import 'core/logging/diag_error_handlers.dart';
import 'core/logging/diag_logger.dart';
import 'core/logging/early_error_handlers.dart';
import 'core/l10n/font_licenses.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_providers.dart';
import 'core/platform/launch_theme.dart';
import 'core/routing/app_router.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/accounts/presentation/edit_card/edit_card_providers.dart'
    show cardCapturePortProvider;
import 'features/budget/application/cycle_app_wiring.dart';
import 'features/capture/presentation/capture_controls.dart'
    show captureCardPortProvider;
import 'features/capture/presentation/capture_lifecycle.dart';
import 'features/capture/presentation/shared_items_lifecycle.dart';
import 'features/gold/application/gold_providers.dart';
import 'features/catalog_sync/application/sync_providers.dart';
import 'features/catalog_sync/presentation/sync_lifecycle.dart';
import 'features/backup/application/schedule_providers.dart'
    show backupDueRunProvider;
import 'features/notifications/application/housekeeping_providers.dart';
import 'features/notifications/application/notification_providers.dart';
import 'features/mascot/presentation/rive_mascot.dart' show preloadRiveMascot;
import 'features/security/application/delete_everything_providers.dart';
import 'features/widgets_bridge/application/widget_bridge.dart'
    show widgetBridgeWiringProvider;
import 'features/security/presentation/app_lock_gate.dart';
import 'features/transactions/presentation/list/txn_list_providers.dart'
    show txnLookupsProvider;
import 'ingestion/ingestion_runner.dart' show ensureDefaultRegistry;
import 'ingestion/ingestion_main.dart';

Future<void> main() async {
  // L-2: first, before anything can fail or print (release builds): errors
  // become buffered codes and debugPrint is muted, even if the database never
  // opens. Debug builds keep the normal reporting.
  installEarlyErrorHandlers();
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
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
  // T-276: warm the mascot (native runtime, file decode, asset manifest) so the
  // first mascot and the first tap never hitch. FU-374: skipped when the
  // platform disables animations (reduce motion never mounts Rive).
  unawaited(preloadRiveMascot());
  // The ProviderScope is built inside the AppRestartScope builder below.
  // ignore: riverpod_lint/missing_provider_scope
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
          // T-161 / FU-211: shared text and images open S-32.
          child: SharedItemsLifecycle(
            child: SyncLifecycle(
              child: NotificationTapLifecycle(child: _LocalizedApp()),
            ),
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
  const ZaghlolApp({
    super.key,
    this.locale = const Locale('ar'),
    this.themeMode = ThemeMode.light,
  });

  /// Arabic by default; null follows the device. The language setting
  /// supplies it (T-023).
  final Locale? locale;

  /// Light by default (PO 2026-11-14); the theme setting supplies it.
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: ZaghlolTheme.light,
      darkTheme: ZaghlolTheme.dark,
      themeMode: themeMode,
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
    // T-224: native reads the theme choice before the first frame.
    ref.listenManual(appThemeModeProvider, (_, mode) {
      unawaited(ref.read(launchThemeWriterProvider)(mode));
    }, fireImmediately: true);
    // T-100: the weekly summary (when 7 days have passed) and the duplicate
    // check at start; again on every resume.
    unawaited(ref.read(resumeJobsProvider)(coldStart: true));
    // FU-168e: the periodic backup job's due mark (after the entitlement).
    unawaited(ref.read(backupDueRunProvider)());
    // FU-113: errors reach the diag log as codes once the database is open.
    unawaited(
      ref
          .read(diagLoggerProvider.future)
          .then<void>((logger) {
            installDiagErrorHandlers(logger, debugPassThrough: kDebugMode);
            return flushEarlyErrors(logger);
          })
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(resumeJobsProvider)());
      unawaited(ref.read(backupDueRunProvider)());
      unawaited(
        ref
            .read(cycleResumeHandlerProvider)
            .onResume()
            .catchError((Object error) async {
              // FU-126: a failed sweep leaves a code, never the error text.
              final logger = await ref.read(diagLoggerProvider.future);
              await logger.record(
                diagEventForError(DiagCodes.resumeFailed, error),
              );
            })
            .catchError((Object _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // FIX-device-flows: the bundled catalog seed (system categories,
    // merchants) loads on first launch. Nothing started it before, so a
    // fresh install had no categories and S-13 could never save. The
    // editor's lists are re-read once it is in.
    ref.listen(catalogSeedProvider, (_, next) {
      if (next.hasValue) ref.invalidate(txnLookupsProvider);
    });
    ref.watch(cycleAppWiringProvider);
    ref.watch(pendingAlertsWatcherProvider); // FU-267
    // T-118: the home-screen widget follows the cycle overview.
    ref.watch(widgetBridgeWiringProvider);
    return ZaghlolApp(
      locale: ref.watch(appLocaleProvider),
      themeMode: ref.watch(effectiveThemeModeProvider),
    );
  }
}
