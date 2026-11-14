// T-064 (FR-ING-I-07): the Shortcuts setup check and the one-tap install.
// Install in three steps: (1) the app opens the iCloud link, (2) the user
// taps "Add Shortcut" in Shortcuts, (3) the user turns on the automations
// the Shortcut offers (the OS needs that confirmation; nothing here can).
// The check then reads the per-automation last-run times and flags one that
// is silent for 7 days, reusing the T-066 rule.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../../core/platform/capture_api.g.dart';
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import '../data/ios_shortcut_setup_port.dart';
import '../domain/ios_shortcut_checker.dart';
import 'ios_setup_providers.dart';

/// The native times; tests override it with a fake.
final shortcutSetupPortProvider = Provider<ShortcutSetupPort>(
  (ref) => IosShortcutSetupPort(),
  name: 'shortcutSetupPortProvider',
);

/// The per-automation report. Null off iOS or when the host can't answer
/// (no App Group container): "cannot tell" is never shown as a failure.
final shortcutSetupReportProvider = FutureProvider<ShortcutSetupReport?>((
  ref,
) async {
  if (!ref.watch(captureIosProvider)) return null;
  final ShortcutSetupStatus s;
  try {
    s = await ref.watch(shortcutSetupPortProvider).status();
  } on Exception {
    return null;
  }
  final now = ref.watch(clockProvider)();
  return deriveShortcutSetupReport(
    nowMs: now.toUtc().millisecondsSinceEpoch,
    lastMessageIntentAtMs: s.lastMessageIntentAtMs,
    lastWalletIntentAtMs: s.lastWalletIntentAtMs,
    baselineAtMs: ref.watch(iosSetupBaselineMsProvider),
  );
}, name: 'shortcutSetupReportProvider');

/// Install step 1: opens the signed Shortcut's iCloud link.
final installShortcutProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => ref.read(externalUrlOpenerProvider)(
        Uri.parse(AppLinks.shortcutInstall),
      ),
  name: 'installShortcutProvider',
);
