// T-166: wiring of "Delete everything" (design note in T-166.md). The
// Settings seam `wipeEverythingProvider` (T-162) is bound in main.dart by
// [wipeEverythingOverride]; [resumePendingWipe] runs at launch and before an
// in-process restart.

import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:google_sign_in/google_sign_in.dart';

import '../../../app/app_restart.dart';
import '../../../core/backend/backend_client.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/app_database_opener.dart' show DbOpenFailure;
import '../../../core/db/db_key_providers.dart';
import '../../../core/platform/seat_key_api.g.dart';
import '../../backup/application/schedule_providers.dart';
import '../../catalog_sync/application/sync_providers.dart';
import '../../widgets_bridge/application/widget_bridge.dart'
    show widgetSnapshotPublisherProvider;
import '../../gold/application/gold_providers.dart'
    show deleteEverythingWarningProvider;
import '../../settings/presentation/settings_ports.dart';
import '../data/pigeon_native_wipe.dart';
import 'delete_everything.dart';

/// The native part; tests override it.
final nativeWipeProvider = Provider<NativeWipe>(
  (ref) => PigeonNativeWipe(
    ios: ref.watch(clientPlatformProvider) == ClientPlatform.ios,
  ),
  name: 'nativeWipeProvider',
);

/// iOS: the own seat key becomes an earlier key (D-55, R4-8). Calls the host
/// directly: the Dart binding (`seat_key_install`) lives in the database
/// being deleted, and the next install's binding check rotates again if
/// this one failed. Android: nothing.
final seatKeyRotationProvider = Provider<Future<void> Function()>((ref) {
  final ios = ref.watch(clientPlatformProvider) == ClientPlatform.ios;
  return () async {
    if (!ios) return;
    try {
      await SeatKeyHostApi().rotateForNewInstall();
    } on PlatformException {
      // SEAT_KEY_UNAVAILABLE: covered by the next install's binding check.
    }
  };
}, name: 'seatKeyRotationProvider');

/// Drops the local Google sign-in session (Drive backup / account sign-in).
/// Best effort; tests override it.
final googleSessionSignOutProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => GoogleSignIn.instance.signOut(),
  name: 'googleSessionSignOutProvider',
);

/// The resume marker, next to the database directory (`<appSupport>`).
final wipeMarkerProvider = Provider<WipeMarker>(
  (ref) => WipeMarker.inDirectory(ref.watch(dbDirectoryProvider).parent),
  name: 'wipeMarkerProvider',
);

final deleteEverythingProvider = Provider<DeleteEverything>((ref) {
  // Read now, so the backend delete still has them after the restart has
  // disposed this container.
  final config = ref.watch(backendConfigProvider);
  final identity = ref.watch(clientIdentityProvider);
  final transport = ref.watch(backendTransportProvider);
  return DeleteEverything(
    readInstall: () =>
        readInstallCredentials(ref.read(backendStateStoreProvider)),
    deleteRemote: (c) => deleteInstallBestEffort(
      c,
      clientFor: (store) => BackendClient(
        config: config,
        identity: identity,
        transport: transport,
        store: store,
      ),
    ),
    rotateSeatKeys: ref.watch(seatKeyRotationProvider),
    cancelJobs: () => ref.read(backupWorkSchedulerProvider).cancel(),
    closeDatabase: () async {
      // Never opens the database just to close it (the launch resume).
      if (!ref.read(appDatabaseProvider.exists)) return;
      try {
        final db = await ref.read(appDatabaseProvider.future);
        await db.close();
      } on DbOpenFailure {
        // Not open: nothing to close.
      }
    },
    secrets: ref.watch(secretStoreProvider),
    files: ref.watch(dbFileSetProvider),
    tempDirectory: ref.watch(appTempDirectoryProvider),
    native: ref.watch(nativeWipeProvider),
    signOutLocal: ref.watch(googleSessionSignOutProvider),
    marker: ref.watch(wipeMarkerProvider),
  );
}, name: 'deleteEverythingProvider');

/// The local wipe still has failed steps after the retry.
final class WipeIncomplete implements Exception {
  const WipeIncomplete();

  @override
  String toString() => 'WipeIncomplete';
}

/// Binds Settings' "Delete everything" (T-162 seam): the wipe (retried once
/// when a local step failed), then the restart into first-launch state. The
/// backend delete keeps running in the background.
final Override wipeEverythingOverride = wipeEverythingProvider.overrideWith(
  (ref) => () async {
    final restart = ref.read(appRestartProvider);
    final wipe = ref.read(deleteEverythingProvider);
    // T-118: the widget's stored snapshot goes with everything else.
    final widget = ref.read(widgetSnapshotPublisherProvider);
    final report = await wipe.run();
    final done = report.complete || (await wipe.resume()).complete;
    await widget.clear();
    // T-166: a wipe that still has failed steps does not restart; the
    // marker stays and the next launch finishes it.
    if (!done) throw const WipeIncomplete();
    restart();
  },
);

/// EC-69: the dialog's seat warning comes from the cached entitlement (T-145).
final Override deleteSeatWarningOverride = deleteSeatWarningProvider
    .overrideWith((ref) => ref.watch(deleteEverythingWarningProvider.future));

/// Every "Delete everything" override of the root scope.
final List<Override> deleteEverythingWiringOverrides = [
  wipeEverythingOverride,
  deleteSeatWarningOverride,
];

/// Launch check: when a wipe did not finish, runs its local steps again
/// before anything opens the database. Uses its own short-lived container
/// over [dbDirectory].
Future<void> resumePendingWipe(Directory dbDirectory) async {
  final marker = WipeMarker.inDirectory(dbDirectory.parent);
  if (!await marker.exists()) return;
  final c = ProviderContainer(
    overrides: [dbDirectoryProvider.overrideWithValue(dbDirectory)],
  );
  try {
    await c.read(deleteEverythingProvider).resume();
  } finally {
    c.dispose();
  }
}
