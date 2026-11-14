// T-066 (FR-ING-I-07, EC-14): the iOS setup checker as a provider. It reads
// the newest automation capture and the first-run day, and derives the state
// with the pure `deriveIosSetupStatus`. Re-evaluated when a capture arrives
// and at every start / resume (the coordinator's foreground hook invalidates
// it), so a phone that stayed silent for 7 days nudges on the next open.

import 'package:flutter/foundation.dart' as f show defaultTargetPlatform;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import '../data/ios_capture_activity.dart';
import '../domain/ios_setup_checker.dart';

const int _dayMs = 24 * 60 * 60 * 1000;

/// True where the iOS capture path applies (tests override it).
final captureIosProvider = Provider<bool>(
  (ref) => f.defaultTargetPlatform == TargetPlatform.iOS,
  name: 'captureIosProvider',
);

final iosCaptureActivityProvider = FutureProvider<IosCaptureActivity>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftIosCaptureActivity(db);
}, name: 'iosCaptureActivityProvider');

/// Newest Shortcut / Apple Pay capture time (UTC epoch ms); null when none.
final iosLastCaptureAtProvider = StreamProvider<int?>((ref) async* {
  final activity = await ref.watch(iosCaptureActivityProvider.future);
  yield* activity.watchLastCaptureAtMs();
}, name: 'iosLastCaptureAtProvider');

final _installedOnProvider = settingProvider(Settings.setupInstalledOn);

/// When capture was first set up (UTC epoch ms; the start of the first-run
/// day), or null. `setup_installed_on` is the local civil day Home first ran:
/// its start in UTC is the local midnight. Shared with the Shortcut checker.
final iosSetupBaselineMsProvider = Provider<int?>((ref) {
  final installedOn = ref.watch(_installedOnProvider).value;
  if (installedOn == null) return null;
  final now = ref.watch(clockProvider)();
  return installedOn * _dayMs - now.timeZoneOffset.inMilliseconds;
}, name: 'iosSetupBaselineMsProvider');

/// The checker state. `unknown` off iOS and while the inputs load.
final iosSetupStatusProvider = Provider<IosSetupStatus>((ref) {
  if (!ref.watch(captureIosProvider)) return IosSetupStatus.unknown;
  final last = ref.watch(iosLastCaptureAtProvider);
  if (last.isLoading || last.hasError) return IosSetupStatus.unknown;
  final now = ref.watch(clockProvider)();
  return deriveIosSetupStatus(
    nowMs: now.toUtc().millisecondsSinceEpoch,
    lastCaptureAtMs: last.value,
    baselineAtMs: ref.watch(iosSetupBaselineMsProvider),
  );
}, name: 'iosSetupStatusProvider');
