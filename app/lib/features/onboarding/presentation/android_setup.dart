// T-056: S-02 Android capture setup. Step 1 explains and asks for SMS (the
// explanation is the Play prominent disclosure and always precedes the system
// prompt); on grant the first-run scan starts and step 2 offers notification
// access while the scan runs. A denied or NoSms build shows the degraded
// variant. Skip hands the step slug to the caller (FR-ONB-11).
// Counts only: nothing here shows or logs a message body, sender or amount.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_banner.dart';
import '../../../core/ui/z_button.dart';
import '../../capture/application/capture_providers.dart';
import '../../capture/application/inbox_scan_service.dart';
import '../../capture/domain/scan_plan.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';

/// Setup step slugs recorded when the user skips (FR-ONB-11).
const String kSetupStepSms = 'android_sms';
const String kSetupStepNotifications = 'android_notif';

/// What the screen needs from the first-run scan.
abstract interface class SetupScan {
  ScanProgress get current;
  Stream<ScanProgress> get progress;
  Future<void> start();
}

final class _ServiceSetupScan implements SetupScan {
  _ServiceSetupScan(this._s);
  final InboxScanService _s;
  @override
  ScanProgress get current => _s.scanner.progress;
  @override
  Stream<ScanProgress> get progress => _s.progress;
  @override
  Future<void> start() async {
    await _s.startFirstRun();
  }
}

final setupScanProvider = FutureProvider<SetupScan?>((ref) async {
  final s = await ref.watch(inboxScanServiceProvider.future);
  return s == null ? null : _ServiceSetupScan(s);
}, name: 'setupScanProvider');

enum _Step { loading, sms, notif, degraded }

class AndroidSetupScreen extends ConsumerStatefulWidget {
  const AndroidSetupScreen({
    super.key,
    required this.onDone,
    this.onSkipped,
    this.onShareHow,
  });

  /// Setup finished (or the user chose "Continue"/"Not now") -> Home.
  final VoidCallback onDone;

  /// The user skipped [slug] (`android_sms`, `android_notif`); the caller
  /// records it for "Finish setup" and leaves to Home.
  final void Function(String slug)? onSkipped;

  /// "How?" next to share/paste in the degraded variant.
  final VoidCallback? onShareHow;

  @override
  ConsumerState<AndroidSetupScreen> createState() => _AndroidSetupState();
}

class _AndroidSetupState extends ConsumerState<AndroidSetupScreen>
    with WidgetsBindingObserver {
  _Step _step = _Step.loading;
  bool _noSms = false;
  bool _denied = false;
  bool _notifOn = false;
  bool _busy = false;
  bool _openedNotif = false;
  ScanProgress _progress = ScanProgress.initial;
  StreamSubscription<ScanProgress>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedNotif) {
      unawaited(_refreshNotif());
    }
  }

  Future<void> _init() async {
    try {
      final c = await ref.read(captureHostPortProvider).getCapabilities();
      if (!mounted) return;
      _notifOn = c.notificationAccess;
      if (!c.smsFlavor) {
        setState(() {
          _noSms = true;
          _step = _Step.degraded;
        });
      } else if (c.smsGranted) {
        await _listenScan(start: false);
        if (mounted) setState(() => _step = _Step.notif);
      } else {
        setState(() => _step = _Step.sms);
      }
    } on Object {
      if (mounted) setState(() => _step = _Step.sms);
    }
  }

  Future<void> _refreshNotif() async {
    try {
      final c = await ref.read(captureHostPortProvider).getCapabilities();
      if (mounted) setState(() => _notifOn = c.notificationAccess);
    } on Object {
      // Keep the last known state.
    }
  }

  Future<void> _listenScan({required bool start}) async {
    final scan = await ref.read(setupScanProvider.future);
    if (scan == null || !mounted) return;
    _progress = scan.current;
    _sub = scan.progress.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
    if (start) {
      unawaited(scan.start().then<void>((_) {}, onError: (Object _) {}));
    }
  }

  Future<void> _allowSms() async {
    if (_busy) return;
    setState(() => _busy = true);
    var granted = false;
    try {
      granted = await ref.read(captureHostPortProvider).requestSmsPermission();
    } on Object {
      // NOT_AVAILABLE (NoSms build) or a platform failure: degraded.
    }
    if (!mounted) return;
    if (granted) {
      await _refreshNotif();
      await _listenScan(start: true);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _denied = false;
        _step = _Step.notif;
      });
    } else {
      setState(() {
        _busy = false;
        _denied = true;
        _step = _Step.degraded;
      });
    }
  }

  Future<void> _openNotif() async {
    _openedNotif = true;
    try {
      await ref.read(captureHostPortProvider).openNotificationAccessSettings();
    } on Object {
      // The user can still enable it later from Settings.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final body = switch (_step) {
      _Step.loading => const Center(child: CircularProgressIndicator()),
      _Step.sms => _smsStep(l, c),
      _Step.notif => _notifStep(l, c),
      _Step.degraded => _degradedStep(l, c),
    };
    final stepNo = _step == _Step.notif ? 2 : 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                ZSpacing.screen,
                ZSpacing.sm,
                ZSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.onboardingAndroidSetupStep(
                        _digits('$stepNo'),
                        _digits('2'),
                      ),
                      style: ZType.label.copyWith(color: c.textMuted),
                    ),
                  ),
                  if (_step != _Step.loading && _step != _Step.degraded)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: ZSpacing.minTarget,
                        minWidth: ZSpacing.minTarget,
                      ),
                      child: TextButton(
                        key: const ValueKey('setup-skip'),
                        onPressed: () {
                          widget.onSkipped?.call(
                            _step == _Step.sms
                                ? kSetupStepSms
                                : kSetupStepNotifications,
                          );
                          if (widget.onSkipped == null) widget.onDone();
                        },
                        child: Text(l.commonActionSkip),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _digits(String s) {
    final lang = Localizations.localeOf(context).languageCode;
    return ref.read(digitsModeProvider(lang)).render(s);
  }

  Widget _bullet(String text, ZColors c) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline, color: c.primary, size: 20),
        const SizedBox(width: ZSpacing.sm),
        Expanded(
          child: Text(text, style: ZType.body.copyWith(color: c.text)),
        ),
      ],
    ),
  );

  Widget _mascot(ZaghlolMoment m) => Center(
    child: ExcludeSemantics(child: ZaghlolAvatar(moment: m, size: 120)),
  );

  Widget _smsStep(AppLocalizations l, ZColors c) => Column(
    key: const ValueKey('setup-sms'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _mascot(ZaghlolMoment.tourGuide),
      const SizedBox(height: ZSpacing.lg),
      Text(
        l.onboardingAndroidSetupSmsTitle,
        style: ZType.headline.copyWith(color: c.text),
      ),
      const SizedBox(height: ZSpacing.sm),
      Text(
        l.onboardingAndroidSetupSmsSubtitle,
        style: ZType.body.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: ZSpacing.lg),
      _bullet(l.onboardingAndroidSetupSmsPointSenders, c),
      _bullet(l.onboardingAndroidSetupSmsPointPersonal, c),
      _bullet(l.onboardingAndroidSetupSmsPointOnPhone, c),
      const SizedBox(height: ZSpacing.lg),
      ZButton(
        key: const ValueKey('setup-sms-allow'),
        label: l.onboardingAndroidSetupSmsAllow,
        loading: _busy,
        expand: true,
        onPressed: _allowSms,
      ),
    ],
  );

  Widget _scanCard(AppLocalizations l, ZColors c) {
    const months = kDefaultScanDepthMonths;
    final count = _progress.imported;
    final running =
        _progress.phase == ScanPhase.running ||
        _progress.phase == ScanPhase.idle;
    final summary = l.onboardingAndroidSetupScanCount(count, _digits('$count'));
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const ValueKey('setup-scan'),
        padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
        decoration: BoxDecoration(
          color: c.primaryContainer,
          borderRadius: BorderRadius.circular(ZRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: c.primary, size: 20),
                const SizedBox(width: ZSpacing.sm),
                Expanded(
                  child: Text(
                    l.onboardingAndroidSetupSmsGranted,
                    style: ZType.label.copyWith(color: c.onPrimaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              l.onboardingAndroidSetupScanTitle,
              style: ZType.label.copyWith(color: c.onPrimaryContainer),
            ),
            if (running) ...[
              const SizedBox(height: ZSpacing.sm),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: ZSpacing.sm),
            Text(
              summary,
              style: ZType.body.copyWith(color: c.onPrimaryContainer),
            ),
            if (_progress.institutions > 0)
              Text(
                '${l.onboardingAndroidSetupScanBanks} '
                '${_digits('${_progress.institutions}')}',
                style: ZType.body.copyWith(color: c.onPrimaryContainer),
              ),
            Text(
              l.onboardingAndroidSetupScanDepth(
                l.commonPeriodLastMonths(months, _digits('$months')),
              ),
              style: ZType.caption.copyWith(color: c.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notifStep(AppLocalizations l, ZColors c) => Column(
    key: const ValueKey('setup-notif'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _scanCard(l, c),
      const SizedBox(height: ZSpacing.xl),
      Text(
        l.onboardingAndroidSetupNotifTitle,
        style: ZType.headline.copyWith(color: c.text),
      ),
      const SizedBox(height: ZSpacing.sm),
      Text(
        l.onboardingAndroidSetupNotifBody,
        style: ZType.body.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: ZSpacing.md),
      // Prominent disclosure, shown before the system screen.
      Text(
        l.onboardingAndroidSetupNotifPrivacy,
        style: ZType.body.copyWith(color: c.text),
      ),
      const SizedBox(height: ZSpacing.sm),
      Text(
        l.onboardingAndroidSetupNotifOsHint,
        style: ZType.caption.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: ZSpacing.lg),
      if (_notifOn)
        Semantics(
          liveRegion: true,
          child: Text(
            l.onboardingAndroidSetupNotifGranted,
            key: const ValueKey('setup-notif-granted'),
            style: ZType.label.copyWith(color: c.primary),
          ),
        )
      else ...[
        ZButton(
          key: const ValueKey('setup-notif-turn-on'),
          label: l.onboardingAndroidSetupNotifTurnOn,
          expand: true,
          onPressed: _openNotif,
        ),
        if (_openedNotif)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Text(
              l.onboardingAndroidSetupNotifStillOff,
              style: ZType.caption.copyWith(color: c.textMuted),
            ),
          ),
      ],
      const SizedBox(height: ZSpacing.sm),
      ZButton(
        key: const ValueKey('setup-notif-done'),
        label: _notifOn ? l.commonActionContinue : l.commonActionNotNow,
        variant: ZButtonVariant.secondary,
        expand: true,
        onPressed: widget.onDone,
      ),
    ],
  );

  Widget _degradedRow(String label, ZColors c, {Widget? action}) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: ZType.body.copyWith(color: c.text)),
          ),
          ?action,
        ],
      ),
    ),
  );

  Widget _degradedStep(AppLocalizations l, ZColors c) => Column(
    key: const ValueKey('setup-degraded'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _mascot(ZaghlolMoment.oops),
      const SizedBox(height: ZSpacing.lg),
      ZBanner(
        tone: ZBannerTone.warning,
        message: _noSms
            ? l.onboardingAndroidSetupPlayUnavailable
            : l.onboardingAndroidSetupDegradedTitle,
      ),
      const SizedBox(height: ZSpacing.md),
      Text(
        l.onboardingAndroidSetupDegradedBody,
        style: ZType.body.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: ZSpacing.sm),
      _degradedRow(
        l.onboardingAndroidSetupDegradedNotif,
        c,
        action: _notifOn
            ? Text(
                l.onboardingAndroidSetupNotifGranted,
                style: ZType.label.copyWith(color: c.primary),
              )
            : TextButton(
                key: const ValueKey('setup-degraded-notif'),
                onPressed: _openNotif,
                child: Text(l.onboardingAndroidSetupDegradedNotifOn),
              ),
      ),
      if (!_notifOn)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
          child: Text(
            l.onboardingAndroidSetupNotifPrivacy,
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
        ),
      _degradedRow(
        l.onboardingAndroidSetupDegradedShare,
        c,
        action: widget.onShareHow == null
            ? null
            : TextButton(
                key: const ValueKey('setup-degraded-share'),
                onPressed: widget.onShareHow,
                child: Text(l.onboardingAndroidSetupDegradedShareHow),
              ),
      ),
      _degradedRow(l.onboardingAndroidSetupDegradedManual, c),
      if (_denied && !_noSms) ...[
        Text(
          l.onboardingAndroidSetupDegradedSettingsHint,
          style: ZType.caption.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: ZSpacing.sm),
        ZButton(
          key: const ValueKey('setup-degraded-retry'),
          label: l.onboardingAndroidSetupDegradedRetry,
          variant: ZButtonVariant.secondary,
          expand: true,
          onPressed: () => setState(() {
            _step = _Step.sms;
          }),
        ),
        const SizedBox(height: ZSpacing.sm),
      ],
      const SizedBox(height: ZSpacing.md),
      ZButton(
        key: const ValueKey('setup-degraded-continue'),
        label: l.commonActionContinue,
        expand: true,
        onPressed: () {
          widget.onSkipped?.call(kSetupStepSms);
          widget.onDone();
        },
      ),
    ],
  );
}
