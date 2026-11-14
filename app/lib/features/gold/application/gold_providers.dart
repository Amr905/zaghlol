// T-145: wiring of the purchase and restore services. `goldWiringOverrides`
// goes into the root ProviderScope next to `syncWiringOverrides` (T-179's
// `seatKeyServiceProvider` throws until it is overridden here).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../../core/platform/pigeon_attestation.dart';
import '../../catalog_sync/application/sync_providers.dart';
import 'entitlement.dart';
import 'gold_ports.dart';
import 'gold_store.dart';
import 'purchase.dart';
import 'purchase_outbox.dart';
import 'restore.dart';
import 'seat_keys.dart';

/// Runs [PurchaseService.retryDue] at the scheduled time while the app is
/// alive. (The native wake-up for a closed app is a follow-up, see T-145.)
final class TimerPurchaseRetryScheduler implements PurchaseRetryScheduler {
  TimerPurchaseRetryScheduler(this._run, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final Future<void> Function() _run;
  final DateTime Function() _now;
  Timer? _timer;

  @override
  void scheduleAt(DateTime at) {
    _timer?.cancel();
    var d = at.difference(_now());
    if (d < const Duration(seconds: 1)) d = const Duration(seconds: 1);
    _timer = Timer(d, () => unawaited(_run()));
  }

  @override
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// T-179's provider, wired to this build's backend client.
final Override seatKeyServiceOverride = seatKeyServiceProvider.overrideWith((
  ref,
) {
  final client = ref.watch(backendClientProvider);
  final service = SeatKeyService(
    platform: ref.watch(clientPlatformProvider),
    store: ref.watch(backendStateStoreProvider),
    installId: client.installId,
  )..start(client.events);
  ref.onDispose(service.stop);
  return service;
});

final List<Override> goldWiringOverrides = [seatKeyServiceOverride];

final goldStoreProvider = Provider<GoldStore>((ref) {
  final s = InAppPurchaseGoldStore(platform: ref.watch(clientPlatformProvider));
  ref.onDispose(s.dispose);
  return s;
}, name: 'goldStoreProvider');

final goldBackendProvider = Provider<GoldBackend>(
  (ref) => BackendClientGoldBackend(ref.watch(backendClientProvider)),
  name: 'goldBackendProvider',
);

final seatProverProvider = Provider<SeatProver>(
  (ref) => SeatKeyServiceProver(ref.watch(seatKeyServiceProvider)),
  name: 'seatProverProvider',
);

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  late final PurchaseService service;
  service = PurchaseService(
    store: ref.watch(goldStoreProvider),
    backend: ref.watch(goldBackendProvider),
    entitlement: ref.watch(entitlementServiceProvider),
    seats: ref.watch(seatProverProvider),
    outbox: PurchaseOutbox(ref.watch(backendStateStoreProvider)),
    platform: ref.watch(clientPlatformProvider),
    scheduler: TimerPurchaseRetryScheduler(() => service.retryDue()),
  );
  ref.onDispose(service.stop);
  return service;
}, name: 'purchaseServiceProvider');

final restoreServiceProvider = Provider<RestoreService>(
  (ref) => RestoreService(
    store: ref.watch(goldStoreProvider),
    backend: ref.watch(goldBackendProvider),
    entitlement: ref.watch(entitlementServiceProvider),
    seats: ref.watch(seatProverProvider),
    attestation: ref.watch(attestationProvider),
    state: ref.watch(backendStateStoreProvider),
    platform: ref.watch(clientPlatformProvider),
  ),
  name: 'restoreServiceProvider',
);

/// T-166: whether "Delete everything" must warn that this install holds a
/// seat (D-55, EC-69), and when the seat could move.
final deleteEverythingWarningProvider = FutureProvider<DeleteEverythingWarning>(
  (ref) => deleteEverythingWarning(
    entitlement: ref.watch(entitlementServiceProvider),
    installId: ref.watch(backendClientProvider).installId,
  ),
  name: 'deleteEverythingWarningProvider',
);
