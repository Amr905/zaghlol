// FU-094: a writer on one connection must wait for a writer on another
// connection to the same encrypted file (up to the busy timeout), instead of
// failing with SQLITE_BUSY at once. The headless ingestion engine and the UI
// engine each hold a connection (T-008 / ADR-005, T-016 design note §5).
//
// Connection A (the lock holder) runs on its own isolate with a raw sqlite3
// connection opened with the app's open sequence; it takes the write lock,
// holds it with a blocking sleep on its own thread and commits. Connection B
// is the app's AppDatabase, with the background executor (drift's isolate)
// or the foreground executor (the test isolate itself). A never needs B's
// isolate to release its lock, so a blocked B cannot deadlock A.
//
// Keys are synthetic (support/synthetic_key.dart); nothing here prints a
// key, a statement or a row.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/daos/write_errors.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart';

import '../../support/fake_secret_store.dart';
import '../../support/synthetic_key.dart';
import 'db_open_harness.dart';

/// Short hold: B must wait and then succeed.
const _shortHold = Duration(milliseconds: 300);

/// Longer than [dbBusyTimeout]: B must give up with SQLITE_BUSY.
const _longHold = Duration(milliseconds: 6500);

const int _sqliteBusy = 5;

void main() {
  late DbWorld world;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    world = await DbWorld.create(FakeSecretStore(), tag: 'fu094');
  });

  tearDown(() => world.dispose());

  Future<AppDatabase> openB({required bool background}) async {
    final db = openedDb(
      await world.open(
        executor: background ? defaultDbExecutor : foregroundExecutor,
      ),
    );
    // The schema exists before A opens the file.
    await writeMeta(db, 'fu094_setup', '1');
    return db;
  }

  Future<void> writeB(AppDatabase db, {required bool inTransaction}) =>
      guardWrite(
        () => inTransaction
            ? db.transaction(() => writeMeta(db, 'fu094_b', 'b'))
            : writeMeta(db, 'fu094_b', 'b'),
      );

  for (final background in [true, false]) {
    final mode = background ? 'background' : 'foreground';
    for (final inTransaction in [true, false]) {
      final kind = inTransaction
          ? 'transaction (BEGIN IMMEDIATE)'
          : 'lone statement';

      test('$mode B, $kind: waits for A and succeeds', () async {
        final b = await openB(background: background);
        addTearDown(b.close);

        final holder = await _LockHolder.start(world.mainFile, _shortHold);
        final watch = Stopwatch()..start();
        await writeB(b, inTransaction: inTransaction);
        final waited = watch.elapsed;
        final held = await holder.done;

        // A really held the lock past B's start, and B waited for it.
        expect(held, greaterThanOrEqualTo(_shortHold));
        expect(waited, greaterThan(const Duration(milliseconds: 200)));
        expect(await metaValue(b, 'fu094_a'), 'a');
        expect(await metaValue(b, 'fu094_b'), 'b');
      });
    }
  }

  test('nothing in lib/ sets PRAGMA busy_timeout (it would replace the '
      'handler)', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final code = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (RegExp(r'busy_timeout\s*=').hasMatch(code)) hits.add(f.path);
    }
    expect(hits, isEmpty);
  });

  for (final (background, inTransaction) in [(true, true), (false, false)]) {
    final mode = background ? 'background' : 'foreground';
    final kind = inTransaction ? 'transaction' : 'lone statement';

    test('$mode B, $kind: A holds past the timeout, so B fails with '
        'DB_WRITE_FAILED (SQLITE_BUSY) after waiting', () async {
      final b = await openB(background: background);
      addTearDown(b.close);

      final holder = await _LockHolder.start(world.mainFile, _longHold);
      final watch = Stopwatch()..start();
      Object? error;
      try {
        await writeB(b, inTransaction: inTransaction);
      } on Object catch (e) {
        error = e;
      }
      final waited = watch.elapsed;
      await holder.done;

      expect(error, isA<DbWriteException>());
      final e = error! as DbWriteException;
      expect(e.code, DbWriteException.writeFailed);
      expect(e.sqliteCode, _sqliteBusy);
      expect(e.toString(), DbWriteException.writeFailed); // code only
      // It waited for (about) the whole timeout, not ~70 ms.
      expect(
        waited,
        greaterThanOrEqualTo(dbBusyTimeout - const Duration(milliseconds: 50)),
      );
      expect(waited, lessThan(_longHold));
      expect(await metaValue(b, 'fu094_b'), isNull);

      // Nothing is left half-open: B writes once A is gone.
      await writeB(b, inTransaction: inTransaction);
      expect(await metaValue(b, 'fu094_b'), 'b');
    }, timeout: const Timeout(Duration(seconds: 60)));
  }
}

/// Connection A on its own isolate: open with the app's sequence, take the
/// write lock, hold it for a fixed time with a blocking sleep, commit.
final class _LockHolder {
  _LockHolder._(this.done);

  /// Completes with how long A held the write lock.
  final Future<Duration> done;

  /// Returns once A holds the write lock.
  static Future<_LockHolder> start(File file, Duration hold) async {
    final port = ReceivePort();
    final errors = ReceivePort();
    await Isolate.spawn(_holdLock, (
      port.sendPort,
      file.path,
      hold.inMicroseconds,
    ), onError: errors.sendPort);
    final locked = Completer<void>();
    final done = Completer<Duration>();
    errors.listen((e) {
      final error = StateError('lock holder failed');
      if (!locked.isCompleted) locked.completeError(error);
      if (!done.isCompleted) done.completeError(error);
      errors.close();
      port.close();
    });
    port.listen((message) {
      if (message == 'locked') {
        locked.complete();
      } else if (message is int) {
        done.complete(Duration(microseconds: message));
        port.close();
        errors.close();
      }
    });
    await locked.future;
    return _LockHolder._(done.future);
  }
}

void _holdLock((SendPort, String, int) args) {
  final (reply, path, holdMicros) = args;
  final raw = sql.sqlite3.open(path);
  try {
    applyBusyTimeout(raw);
    applyEncryptedOpenSequence(raw, DbKeyMaterial.copyOf(syntheticKeyBytes()));
    raw.execute('BEGIN IMMEDIATE');
    raw.execute(
      "INSERT OR REPLACE INTO db_meta (key, value) VALUES ('fu094_a', 'a')",
    );
    final held = Stopwatch()..start();
    reply.send('locked');
    sleep(Duration(microseconds: holdMicros));
    raw.execute('COMMIT');
    reply.send(held.elapsedMicroseconds);
  } finally {
    raw.close();
  }
}
