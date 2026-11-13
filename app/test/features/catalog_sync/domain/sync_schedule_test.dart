// T-143: throttle and back-off rules (pure).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/catalog_sync/domain/sync_schedule.dart';

const int h = 3600000;

void main() {
  SyncState after({int wall = 1000 * h, int server = 500 * h}) => SyncState(
    serverMs: server,
    wallAtServerMs: wall,
    nextNotBeforeServerMs: server + 24 * h,
  );

  test('never synced is due', () => expect(SyncState.empty.isDue(0), isTrue));

  test('not due inside the server window, due after it', () {
    final s = after();
    expect(s.isDue(1000 * h + 23 * h), isFalse);
    expect(s.isDue(1000 * h + 24 * h), isTrue);
  });

  test('a wall clock moved backwards is due (server throttles anyway)', () {
    expect(after().isDue(900 * h), isTrue);
  });

  test('back-off: at most one attempt an hour, doubling to 8 h', () {
    expect(syncBackoff(1), const Duration(hours: 1));
    expect(syncBackoff(2), const Duration(hours: 2));
    expect(syncBackoff(3), const Duration(hours: 4));
    expect(syncBackoff(4), const Duration(hours: 8));
    expect(syncBackoff(40), const Duration(hours: 8));
    expect(syncBackoff(0), const Duration(hours: 1));
  });

  test('Retry-After wins when longer, capped at a day', () {
    expect(
      syncBackoff(1, retryAfter: const Duration(hours: 3)),
      const Duration(hours: 3),
    );
    expect(
      syncBackoff(1, retryAfter: const Duration(days: 9)),
      const Duration(days: 1),
    );
  });

  test('retry-not-before blocks, then releases; absurd values ignored', () {
    final s = SyncState(retryNotBeforeWallMs: 100 * h);
    expect(s.isDue(99 * h + 1), isFalse);
    expect(s.isDue(100 * h), isTrue);
    // clock moved back by a year: not trusted
    expect(SyncState(retryNotBeforeWallMs: 9000 * h).isDue(100 * h), isTrue);
  });

  test('encode/decode round trip; junk reads as empty', () {
    final s = const SyncState(
      lastOkWallMs: 1,
      serverMs: 2,
      wallAtServerMs: 3,
      nextNotBeforeServerMs: 4,
      failures: 5,
      retryNotBeforeWallMs: 6,
      pendingFullVersion: 7,
    );
    final d = SyncState.decode(s.encode());
    expect(
      [
        d.lastOkWallMs,
        d.serverMs,
        d.wallAtServerMs,
        d.nextNotBeforeServerMs,
        d.failures,
        d.retryNotBeforeWallMs,
        d.pendingFullVersion,
      ],
      [1, 2, 3, 4, 5, 6, 7],
    );
    expect(SyncState.decode(null).failures, 0);
    expect(SyncState.decode(Uint8List.fromList([1, 2, 3])).serverMs, isNull);
  });
}
