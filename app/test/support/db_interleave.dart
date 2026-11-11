// FU-095 / T-075: a real, deterministic interleaving of two connections, with
// no hook into SQLite.
//
// Connection `blocker` opens a transaction and writes, so it holds the
// database write lock UNCOMMITTED. The `action` (on another connection) is
// started now and, being a write, waits in SQLite's busy handler (FU-094:
// up to 5 s). The harness proves the action is still pending, then commits
// the blocker. The action therefore runs its whole statement AFTER the
// blocker's write, but with everything it read earlier (ids, old values)
// stale, which is exactly the race "a user edit lands between a read and a
// write". Both connections must run in drift's background isolate; a
// foreground executor would block this isolate's event loop in the busy
// wait and the commit could never run.
//
// Not covered: the exact instruction-level interleaving of two statements
// that are both already running (SQLite offers no hook); the stress loops
// next to each use of this harness cover that statistically.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';

Future<T> interleaved<T>({
  required AppDatabase blocker,
  required Future<void> Function() blockerWrites,
  required Future<T> Function() action,
  Duration settle = const Duration(milliseconds: 300),
}) async {
  final locked = Completer<void>();
  final release = Completer<void>();
  final b = blocker.transaction(() async {
    await blockerWrites();
    locked.complete();
    await release.future;
  });
  // If the blocker's writes fail, surface that instead of hanging.
  unawaited(
    b.catchError((Object e) {
      if (!locked.isCompleted) locked.completeError(e);
    }),
  );
  await locked.future;
  var done = false;
  final a = action();
  unawaited(a.then((_) => done = true, onError: (Object _) => done = true));
  await Future<void>.delayed(settle);
  expect(
    done,
    isFalse,
    reason: 'the action must be waiting for the blocker\'s write lock',
  );
  release.complete();
  await b;
  return a;
}
