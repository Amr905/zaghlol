// SMS-device: the "Fix" button of capture settings (`common_action_fix`). It
// had no action in the shipped shell (CaptureSettingsScreen was built without
// `onFix`), so a user who skipped or denied the SMS step in onboarding had no
// way to turn live SMS on again: the app read nothing. Nothing here logs.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/capture_health.dart';
import 'capture_providers.dart';

/// Opens the permission flow of [channel]: the SMS prompt (then the
/// first-run scan of the inbox, the same one onboarding runs), or the system
/// "Notification access" list. Best effort: a failure leaves the row as it was.
Future<void> fixCapturePermission(WidgetRef ref, CaptureChannel channel) async {
  final host = ref.read(captureHostPortProvider);
  try {
    switch (channel) {
      case CaptureChannel.smsLive:
        final granted = await host.requestSmsPermission();
        final coordinator = await ref.read(captureCoordinatorProvider.future);
        await coordinator?.onResumed();
        if (granted) {
          final scan = await ref.read(inboxScanServiceProvider.future);
          if (scan != null) {
            unawaited(
              scan.startFirstRun().then<void>((_) {}, onError: (Object _) {}),
            );
          }
        }
      case CaptureChannel.notifications:
        await host.openNotificationAccessSettings();
      case CaptureChannel.sharePaste:
      case CaptureChannel.manual:
        break;
    }
  } on Object {
    // The health row keeps showing the problem; the user can try again.
  }
}
