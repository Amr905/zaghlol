// T-047: the port T-048 implements (historical inbox scan). T-047 calls it
// after each drain when live SMS is active; the request itself
// (`capture.catchup.*`) is in the encrypted settings.

abstract interface class CatchUpScheduler {
  /// Asks the scan to look at the stored catch-up request now. Must be
  /// cheap and idempotent: it is called after every drain cycle.
  Future<void> requestIfPending();
}

/// Records calls; the production binding until T-048.
final class RecordingCatchUpScheduler implements CatchUpScheduler {
  int calls = 0;

  @override
  Future<void> requestIfPending() async => calls++;
}
