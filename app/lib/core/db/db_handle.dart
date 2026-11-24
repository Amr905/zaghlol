// T-238 fix round (batch-66 M-1): closing the SQLite handle of a drift
// database deterministically, without waiting on stream listeners.
//
// drift's `close()` closes its stream store first and waits for every
// `watch()` listener; a paused listener (Riverpod pauses off-screen
// providers) never lets it return, so the handle stayed open. Here the
// executor is closed directly; for the app's background executor the handle
// is known closed only when drift's isolate has exited (it closes the
// database, then kills itself), so [openEncryptedExecutor] registers an exit
// signal that [closeDbHandle] awaits.
//
// A close in flight is also recorded by file path: an open at the same path
// first waits for it ([awaitDbHandlesClosed]), so the close of an old
// connection (which deletes `-wal` / unlinks `-shm` by name) can never run
// after a new database opened there.
//
// Process-wide by design: a handle outlives the ProviderContainer that
// opened it (the in-process restart builds a new one). Paths stay in memory
// only and never leave this file.

import 'dart:async';
import 'dart:isolate';

import 'package:drift/drift.dart'
    show DatabaseConnection, DatabaseConnectionUser, QueryExecutor;

final Expando<Future<void>> _exitedOf = Expando('dbHandleExited');
final Expando<String> _pathOf = Expando('dbHandlePath');
final Expando<Future<void>> _closingOf = Expando('dbHandleClosing');
final Map<String, Set<Future<void>>> _pendingByPath = {};

/// The executor that [openEncryptedExecutor] built for [path]. [exited]
/// completes when the background isolate holding the handle has exited
/// (null: the handle lives in this isolate).
void trackDbHandle(
  QueryExecutor executor,
  String path, {
  Future<void>? exited,
}) {
  // A database built on a DatabaseConnection exposes its inner executor.
  final inner = executor is DatabaseConnection ? executor.executor : executor;
  _pathOf[inner] = path;
  if (exited != null) _exitedOf[inner] = exited;
}

/// An exit signal for a drift background isolate: pass [setup] as drift's
/// `isolateSetup`; [exited] completes when that isolate is gone. The port
/// never keeps this isolate alive.
final class IsolateExitSignal {
  IsolateExitSignal() {
    _port.keepIsolateAlive = false;
    _port.handler = (Object? _) {
      _port.close();
      if (!_done.isCompleted) _done.complete();
    };
  }

  final RawReceivePort _port = RawReceivePort();
  final Completer<void> _done = Completer<void>();

  Future<void> get exited => _done.future;

  /// Runs in the new isolate (captures the send port only).
  FutureOr<void> Function() get setup => _setupFor(_port.sendPort);

  static FutureOr<void> Function() _setupFor(SendPort port) =>
      () => Isolate.current.addOnExitListener(port);
}

/// Closes [db]'s SQLite handle and completes once it is closed. Never waits
/// on `watch()` listeners (paused or not); their streams are left to
/// `db.close()`, which then no longer touches the file. Idempotent: every
/// call returns the same future.
Future<void> closeDbHandle(DatabaseConnectionUser db) {
  final executor = db.executor;
  return _closingOf[executor] ??= _close(executor);
}

Future<void> _close(QueryExecutor executor) {
  final path = _pathOf[executor];
  final exited = _exitedOf[executor];
  final done = () async {
    await executor.close();
    // Background: the close request returns before the isolate has closed
    // the database; its exit is the proof.
    if (exited != null) await exited;
  }();
  if (path != null) {
    final set = _pendingByPath.putIfAbsent(path, () => {});
    // Leaves the set only once the handle is known closed. A failed close
    // stays pending (the handle may still be open) unless the isolate exits.
    final closed = exited ?? done;
    set.add(done);
    void drop(Object? _) {
      set.remove(done);
      if (set.isEmpty) _pendingByPath.remove(path);
    }

    closed.then(drop, onError: (Object _) {});
  }
  return done;
}

/// Waits until no handle on [path] is still closing. False when one is
/// still closing after [timeout] or its close failed: the caller must not
/// open the file then.
Future<bool> awaitDbHandlesClosed(
  String path, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final pending = _pendingByPath[path];
  if (pending == null || pending.isEmpty) return true;
  try {
    await Future.wait(pending.toList()).timeout(timeout);
  } on Object {
    // Timed out or failed; a handle exit may still have dropped it.
    final left = _pendingByPath[path];
    return left == null || left.isEmpty;
  }
  return true;
}
