// WIRE-NAV: first-run flow and the late scan-results sheet.
//
// First run (no `setup_installed_on` yet): Welcome (S-01) -> Android setup
// (S-02) -> Scan results (S-06) -> the shell; iOS: Welcome -> iOS setup
// (S-03) -> the shell. "I already use Zaghlol"
// opens the restore flow (S-04). The flow has its own Navigator above the
// router, so nothing in it depends on the shell.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/routing/app_router.dart';
import '../core/routing/app_routes.dart';
import '../features/capture/domain/scan_plan.dart';
import '../features/home/application/home_cards.dart';
import '../features/onboarding/presentation/android_setup.dart';
import '../features/onboarding/presentation/welcome.dart';
import '../core/settings/settings_keys.dart';
import '../core/settings/settings_providers.dart';
import '../features/notifications/application/notification_providers.dart'
    show ensureNotificationPermission;
import 'app_navigation.dart';
import 'app_screens.dart';

/// Whether the first-run flow is still to be shown. A read error counts as
/// "not needed": the app must open rather than trap the user in onboarding.
final onboardingNeededProvider = FutureProvider<bool>((ref) async {
  try {
    final repo = await ref.watch(settingsRepositoryProvider.future);
    return await repo.get(Settings.setupInstalledOn) == null;
  } on Object {
    return false;
  }
}, name: 'onboardingNeededProvider');

class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({super.key, required this.child});

  /// The routed shell.
  final Widget child;

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  bool _finished = false;

  /// Marks the first run as done (Home's A-65 clock starts from it).
  Future<void> _finish([String? location]) async {
    try {
      await ref.read(setupInstalledOnProvider.future);
    } on Object {
      // Not being able to write the marker must not block the user.
    }
    if (!mounted) return;
    setState(() => _finished = true);
    // NOTIF-GW: the notification permission, asked once the user is in the
    // app (Android 13+ prompt, iOS authorization). Best effort.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ensureNotificationPermission(ref));
    });
    if (location != null) {
      // After the shell is on screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(ref.read(appRouterProvider).push<void>(location));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final needed = ref.watch(onboardingNeededProvider);
    if (_finished || needed.value == false) {
      return ScanResultsSheetTrigger(child: widget.child);
    }
    if (needed.isLoading) return const SizedBox.shrink();
    return _OnboardingFlow(onFinish: _finish);
  }
}

class _OnboardingFlow extends ConsumerWidget {
  const _OnboardingFlow({required this.onFinish});
  final Future<void> Function([String? location]) onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (ctx) => WelcomeScreen(
          onStart: () => _start(ctx, ref),
          onRestore: () => unawaited(
            openRestore(
              ctx,
              onRestored: ({required regrantDue}) => unawaited(onFinish()),
            ),
          ),
          onPrivacy: () => unawaited(ref.read(appScreensProvider).privacy(ctx)),
        ),
      ),
    );
  }

  void _start(BuildContext ctx, WidgetRef ref) {
    if (Theme.of(ctx).platform == TargetPlatform.iOS) {
      unawaited(
        pushScreen<void>(
          ctx,
          (setupCtx) => iosSetupScreen(
            setupCtx,
            onDone: () => unawaited(onFinish()),
            onSkipped: (slug) {
              unawaited(
                recordSetupSkip(ProviderScope.containerOf(setupCtx), slug),
              );
              unawaited(onFinish());
            },
          ),
        ),
      );
      return;
    }
    final screens = ref.read(appScreensProvider);
    unawaited(
      pushScreen<void>(
        ctx,
        (setupCtx) => screens.androidSetup(
          onDone: () => _scanResults(setupCtx, ref),
          onSkipped: (slug) {
            unawaited(
              recordSetupSkip(ProviderScope.containerOf(setupCtx), slug),
            );
            unawaited(onFinish());
          },
        ),
      ),
    );
  }

  void _scanResults(BuildContext ctx, WidgetRef ref) {
    final screens = ref.read(appScreensProvider);
    unawaited(
      pushScreen<void>(
        ctx,
        (resultsCtx) => screens.scanResults(
          onDone: () => unawaited(onFinish()),
          onOpenReview: () => unawaited(onFinish(AppRoutes.review)),
          onEditCard: (id) => unawaited(openEditCardById(resultsCtx, id)),
          onSetupCredit: (id) => unawaited(openEditCardById(resultsCtx, id)),
        ),
      ),
    );
  }
}

/// S-06 as a sheet: when the first-run scan finishes after the user is
/// already on Home (it started in the background), offer its results once.
class ScanResultsSheetTrigger extends ConsumerStatefulWidget {
  const ScanResultsSheetTrigger({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ScanResultsSheetTrigger> createState() => _TriggerState();
}

class _TriggerState extends ConsumerState<ScanResultsSheetTrigger> {
  StreamSubscription<ScanProgress>? _sub;
  bool _sawRunning = false;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(setupScanProvider, (_, next) {
      final scan = next.value;
      if (scan == null) return;
      unawaited(_sub?.cancel());
      _sawRunning = scan.current.phase == ScanPhase.running;
      _sub = scan.progress.listen(_onProgress);
    }, fireImmediately: true);
  }

  void _onProgress(ScanProgress p) {
    if (p.phase == ScanPhase.running) _sawRunning = true;
    if (p.phase != ScanPhase.done || !_sawRunning || _shown) return;
    _shown = true;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final screens = ref.read(appScreensProvider);
    unawaited(
      screens.scanResultsSheet(
        ctx,
        onDone: () {},
        onOpenReview: () =>
            unawaited(ref.read(appRouterProvider).push<void>(AppRoutes.review)),
        onEditCard: (id) => unawaited(openEditCardById(ctx, id)),
        onSetupCredit: (id) => unawaited(openEditCardById(ctx, id)),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
