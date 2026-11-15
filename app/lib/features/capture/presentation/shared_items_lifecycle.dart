// T-161 / FU-211: picks up items other apps shared into Zaghlol (T-060 Android
// share target, T-065 iOS Share Extension) and routes them, when the app is
// open and unlocked:
//   text          -> parsed like a pasted message -> S-32 (confirm, never auto-save)
//   image         -> OCR -> S-32
//   pdf / csv     -> S-32 "not available" (PDF OCR and import belong to T-158)
// Events come from `ShareIntakeService` (started by the capture coordinator at
// start and on every resume). Content is read only after the app lock is open
// (T-103), held in memory, never logged, and the share is discarded when S-32
// closes. A refused share shows a short message; there is nothing to clean up.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/onboarding_gate.dart' show onboardingNeededProvider;
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/platform/share_intake_service.dart';
import '../../../core/routing/app_router.dart' show rootNavigatorKey;
import '../../security/domain/app_lock_controller.dart';
import '../application/capture_providers.dart';
import 'scan_confirm_screen.dart';

class SharedItemsLifecycle extends ConsumerStatefulWidget {
  const SharedItemsLifecycle({
    super.key,
    required this.child,
    this.navigatorKey,
  });

  final Widget child;

  /// The navigator S-32 opens on (the root one by default).
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  ConsumerState<SharedItemsLifecycle> createState() => _SharedItemsState();
}

class _SharedItemsState extends ConsumerState<SharedItemsLifecycle> {
  final Queue<ShareDescriptor> _queue = Queue<ShareDescriptor>();
  StreamSubscription<ShareIntakeEvent>? _sub;
  bool _busy = false;

  GlobalKey<NavigatorState> get _nav => widget.navigatorKey ?? rootNavigatorKey;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(captureShareIntakeProvider).events.listen(_onEvent);
    // Retry when the lock opens or onboarding ends.
    ref.listenManual<AppLockState>(
      appLockControllerProvider,
      (_, _) => unawaited(_drain()),
    );
    ref.listenManual<AsyncValue<bool>>(
      onboardingNeededProvider,
      (_, _) => unawaited(_drain()),
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _onEvent(ShareIntakeEvent e) {
    switch (e) {
      case ShareReceived(:final descriptor):
        _queue.add(descriptor);
        unawaited(_drain());
      case ShareRejected(:final reason):
        _showRefusal(reason);
    }
  }

  void _showRefusal(ShareRejectReason reason) {
    final ctx = _nav.currentContext;
    if (ctx == null) return;
    final l = AppLocalizations.of(ctx);
    final text = switch (reason) {
      ShareRejectReason.tooLarge => l.captureShareRefusedTooLarge,
      ShareRejectReason.unsupportedType => l.captureShareRefusedUnsupported,
      ShareRejectReason.unreadable => l.captureShareRefusedUnreadable,
      ShareRejectReason.empty => l.captureShareRefusedEmpty,
    };
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(text)));
  }

  bool get _ready =>
      !ref.read(appLockControllerProvider).locked &&
      ref.read(onboardingNeededProvider).value == false &&
      _nav.currentContext != null;

  Future<void> _drain() async {
    if (_busy) return;
    _busy = true;
    try {
      while (mounted && _queue.isNotEmpty && _ready) {
        final d = _queue.removeFirst();
        await _handle(d);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _handle(ShareDescriptor d) async {
    final service = ref.read(captureShareIntakeProvider);
    final ScanRequest? request;
    switch (d.kind) {
      case ShareKind.text:
        request = await _textRequest(service, d);
      case ShareKind.image:
        request = ScanImagePath(d.ocrPath);
      case ShareKind.pdf || ShareKind.csv:
        request = const ScanImagePath(null);
    }
    final ctx = _nav.currentContext;
    if (request != null && ctx != null && ctx.mounted) {
      await showScanScreen(ctx, request: request);
    }
    try {
      await service.discard(d.id);
    } on Object {
      // Nothing more to do: native purges stale shares after 24 hours.
    }
  }

  Future<ScanRequest?> _textRequest(
    ShareIntakeService service,
    ShareDescriptor d,
  ) async {
    try {
      final content = await service.read(d.id);
      final text = content.text;
      return text == null || text.isEmpty ? null : ScanSharedText(text);
    } on Object {
      return null; // IO_ERROR or SPOOL_DECRYPT_FAILED: the share is dropped
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
