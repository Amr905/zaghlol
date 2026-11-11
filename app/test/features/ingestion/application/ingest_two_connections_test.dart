// T-046 §10, §14: the UI and headless engines each hold a connection to the
// same encrypted file. Every dedupe and merge read runs inside the batch's
// BEGIN IMMEDIATE transaction, so the two writers serialize. Connection A is
// the world's database (drift's background isolate), B a second
// AppDatabase on its own background isolate; a third, raw connection on
// its own isolate holds the write lock for the busy test. Synthetic data.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart';
import 'package:zaghlol/features/ingestion/domain/body_hash.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';

import '../../../core/db/db_open_harness.dart' show keyOf;
import '../../../support/synthetic_key.dart';
import '../support/ingest_harness.dart';

void main() {
  late IngestWorld w;
  late AppDatabase other;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    w = await IngestWorld.open();
    other = AppDatabase(
      openEncryptedExecutor(
        w.edb.world.mainFile,
        keyOf(61),
        inBackground: true,
      ),
      validateSchema: false,
    );
  });

  tearDown(() async {
    await other.close();
    await w.close();
  });

  test('SMS on A and notification on B, 50 rounds with random delays → '
      'one transaction per payment', () async {
    final a = w.useCase(idPrefix: 'a');
    final b = w.useCase(on: other, idPrefix: 'b');
    final random = Random(46);
    for (var i = 0; i < 50; i++) {
      final amount = '${100 + i}.00';
      final rx = t0 + i * 3600000;
      final delayA = random.nextInt(4);
      final delayB = random.nextInt(4);
      await Future.wait([
        Future<void>.delayed(Duration(milliseconds: delayA), () async {
          await a([
            sms(
              'a$i',
              'ZBANK: Purchase EGP $amount at Synth Shop card *4321',
              rx: rx,
            ),
          ]);
        }),
        Future<void>.delayed(Duration(milliseconds: delayB), () async {
          await b([
            notif('b$i', 'Purchase EGP $amount at Synth Shop', rx: rx + 1500),
          ]);
        }),
      ]);
    }
    expect(await w.count('transactions'), 50);
    expect(await w.count('raw_messages'), 100);
    expect(
      await w.count(
        'transactions',
        'account_id IN (SELECT id FROM accounts '
            "WHERE last4 = '4321')",
      ),
      50,
      reason: 'every payment ends on the card account',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the same body via the spool (A) and an inbox scan (B) → one raw '
      'row', () async {
    final a = w.useCase(idPrefix: 'a');
    final b = w.useCase(on: other, idPrefix: 'b');
    const body = 'ZBANK: Purchase EGP 77.00 at Synth Shop card *4321';
    final results = await Future.wait([
      a([sms('s', body)]),
      b([
        IncomingMessage(
          deliveryId: 'i',
          channel: 'sms',
          source: zbankSms,
          body: body,
          receivedAtMs: t0 + 5,
          origin: MessageOrigin.inboxScan,
        ),
      ]),
    ]);
    expect(await w.count('raw_messages'), 1);
    expect(await w.count('transactions'), 1);
    final kinds = {
      for (final r in results)
        for (final o in r.outcomes.values) o.runtimeType,
    };
    expect(kinds, {IngestInserted, IngestDuplicate});
  });

  test('another connection holds the write lock past the busy timeout → '
      'IngestBatchFailed (transient), nothing stored; the next cycle '
      'succeeds', () async {
    final useCase = w.useCase();
    // The schema exists and both sides are warm.
    expect(await w.count('raw_messages'), 0);
    final holder = await _LockHolder.start(
      w.edb.world.mainFile,
      const Duration(milliseconds: 6500),
    );
    Object? error;
    try {
      await useCase([
        sms('s', 'ZBANK: Purchase EGP 5.00 at Synth Shop card *4321'),
      ]);
    } on Object catch (e) {
      error = e;
    }
    await holder.done;
    expect(error, isA<IngestBatchFailed>());
    expect((error! as IngestBatchFailed).code, 'DB_WRITE_FAILED');
    expect((error as IngestBatchFailed).isTransient, isTrue);
    expect(await w.count('raw_messages'), 0);
    final r = await useCase([
      sms('s', 'ZBANK: Purchase EGP 5.00 at Synth Shop card *4321'),
    ]);
    expect(r.outcomes['s'], isA<IngestInserted>());
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('an isolate killed inside its write transaction (raw row '
      'written, no COMMIT) → nothing of it survives; '
      're-delivery stores one transaction', () async {
    const body = 'ZBANK: Purchase EGP 9.00 at Synth Shop card *4321';
    final hash = bodyHashV1(
      senderKey: senderKeyOf('sms', zbankSms),
      body: body,
    );
    expect(await w.count('raw_messages'), 0);
    await _KilledWriter.run(w.edb.world.mainFile, hash);
    // The killed writer's lock is gone and its rows were rolled back.
    expect(await w.count('raw_messages'), 0);
    final useCase = w.useCase();
    final r = await useCase([sms('s', body)]);
    expect(r.outcomes['s'], isA<IngestInserted>());
    final again = await useCase([sms('s2', body)]);
    expect(again.outcomes['s2'], isA<IngestDuplicate>());
    expect(await w.count('raw_messages'), 1);
    expect(await w.count('transactions'), 1);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// A writer on its own isolate that takes the write lock, writes the raw
/// row the use case would write, and is then killed before its COMMIT.
abstract final class _KilledWriter {
  static Future<void> run(File file, String bodyHash) async {
    final port = ReceivePort();
    final exit = ReceivePort();
    final isolate = await Isolate.spawn(_writeAndWait, (
      port.sendPort,
      file.path,
      bodyHash,
    ), onExit: exit.sendPort);
    final first = await port.first;
    expect(first, 'written');
    isolate.kill(priority: Isolate.immediate);
    await exit.first;
  }
}

Future<void> _writeAndWait((SendPort, String, String) args) async {
  final (reply, path, bodyHash) = args;
  final raw = sql.sqlite3.open(path);
  applyBusyTimeout(raw);
  applyEncryptedOpenSequence(raw, DbKeyMaterial.copyOf(syntheticKeyBytes()));
  raw.execute('BEGIN IMMEDIATE');
  raw.execute(
    'INSERT INTO raw_messages (id, channel, sender, body, body_hash, '
    'received_at, parse_status, registry_version, created_at) '
    "VALUES ('killed', 'sms', ?, ?, ?, ?, 'parsed', 1, ?)",
    [zbankSms, 'ZBANK: synthetic', bodyHash, t0, t0],
  );
  reply.send('written');
  // Never commits, never closes: the isolate is killed here.
  await Completer<void>().future;
}

/// A raw connection on its own isolate: open with the app's sequence, take
/// the write lock, hold it with a blocking sleep, commit (FU-094 pattern).
final class _LockHolder {
  _LockHolder._(this.done);

  final Future<void> done;

  static Future<_LockHolder> start(File file, Duration hold) async {
    final port = ReceivePort();
    final errors = ReceivePort();
    await Isolate.spawn(_holdLock, (
      port.sendPort,
      file.path,
      hold.inMicroseconds,
    ), onError: errors.sendPort);
    final locked = Completer<void>();
    final done = Completer<void>();
    errors.listen((_) {
      final error = StateError('lock holder failed');
      if (!locked.isCompleted) locked.completeError(error);
      if (!done.isCompleted) done.completeError(error);
      errors.close();
      port.close();
    });
    port.listen((message) {
      if (message == 'locked') {
        locked.complete();
      } else if (message == 'done') {
        done.complete();
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
    reply.send('locked');
    sleep(Duration(microseconds: holdMicros));
    raw.execute('COMMIT');
    reply.send('done');
  } finally {
    raw.close();
  }
}
