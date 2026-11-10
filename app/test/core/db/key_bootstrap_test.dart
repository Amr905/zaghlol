// T-015: KeyBootstrap against FakeSecretStore and real temp directories
// (design note §3, §5, §9). Covers every cell of the §3 table, the lease, the
// winner semantics, the generator checks, zeroization and redaction.
//
// Key hygiene: keys are synthetic (support/synthetic_key.dart) and are never
// printed or used in a test name or `reason:`; assertions compare booleans.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/core/db/db_file_set.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart';

import '../../support/fake_secret_store.dart';
import '../../support/synthetic_key.dart';

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _allZero(List<int> bytes) => bytes.every((b) => b == 0);

/// Snapshot of every file in a directory (name → bytes).
Map<String, Uint8List> _snapshot(Directory dir) => {
  for (final e in dir.listSync().whereType<File>())
    e.uri.pathSegments.last: e.readAsBytesSync(),
};

bool _sameSnapshot(Map<String, Uint8List> a, Map<String, Uint8List> b) =>
    a.length == b.length &&
    a.keys.every((k) => b.containsKey(k) && _sameBytes(a[k]!, b[k]!));

class _ConstantRandom implements Random {
  @override
  int nextInt(int max) => 7;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

class _NullGenerator implements KeyGenerator {
  @override
  Uint8List? next() => null;
}

class _DegenerateGenerator implements KeyGenerator {
  @override
  Uint8List? next() => Uint8List(dbKeyLength)..fillRange(0, dbKeyLength, 9);
}

void main() {
  late Directory dir;
  late FakeSecretStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zaghlol_t015_');
    store = FakeSecretStore();
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  KeyBootstrap bootstrap({KeyGenerator? generator, Duration? leaseTimeout}) =>
      KeyBootstrap(
        store: store,
        files: DbFileSet(dir),
        generator: generator ?? FixedKeyGenerator(),
        leaseTimeout: leaseTimeout ?? const Duration(seconds: 2),
      );

  /// Writes a stand-in database file set (synthetic bytes).
  void writeDb({String name = dbFileName}) {
    File('${dir.path}/$name')
        .writeAsBytesSync(List<int>.generate(4096, (i) => (i * 31 + 7) & 0xFF));
  }

  group('§3 table: database absent', () {
    test('notFound → KeyCreated(firstRun), stored and held', () async {
      final outcome = await bootstrap().obtain();
      expect(outcome, isA<KeyCreated>());
      final created = outcome as KeyCreated;
      expect(created.reason, KeyCreatedReason.firstRun);
      expect(created.restoreNoticeDue, isFalse);
      expect(created.lease.isReleased, isFalse);
      expect(store.leaseHeld, isTrue);
      expect(
        _sameBytes(store.stored!, syntheticKeyBytes()),
        isTrue,
        reason: 'stored key is the generated candidate',
      );
      expect(created.key.toRawKeyHex().length, 64);
      expect(store.deleteCalls, 0);
      await created.lease.release();
      expect(store.leaseHeld, isFalse);
    });

    test('found → delete + create → KeyCreated(rotatedNoDb)', () async {
      store.stored = syntheticKeyBytes(1);
      final outcome = await bootstrap().obtain();
      expect(outcome, isA<KeyCreated>());
      final created = outcome as KeyCreated;
      expect(created.reason, KeyCreatedReason.rotatedNoDb);
      expect(
        store.calls.indexOf('delete') < store.calls.indexOf('create'),
        isTrue,
      );
      expect(_sameBytes(store.stored!, syntheticKeyBytes(61)), isTrue);
      expect(_sameBytes(store.stored!, syntheticKeyBytes(1)), isFalse);
      await created.lease.release();
    });

    test('unusable → delete + create → KeyCreated(rotatedNoDb)', () async {
      store
        ..stored = syntheticKeyBytes(1)
        ..forcedStatus = SecretStatus.unusable;
      final outcome = await bootstrap().obtain();
      expect(outcome, isA<KeyCreated>());
      expect((outcome as KeyCreated).reason, KeyCreatedReason.rotatedNoDb);
      expect(store.deleteCalls, 1);
      expect(store.createCalls, 1);
      await outcome.lease.release();
    });

    test(
      'unavailable → KeyUnavailable, nothing written, lease released',
      () async {
        store.forcedStatus = SecretStatus.unavailable;
        store.readAttempts = 4;
        final outcome = await bootstrap().obtain();
        expect(outcome, isA<KeyUnavailable>());
        expect(
          (outcome as KeyUnavailable).reason,
          KeyUnavailableReason.transient,
        );
        expect(outcome.attempts, 4);
        expect(store.writeCalls, 0);
        expect(store.leaseHeld, isFalse);
      },
    );
  });

  group('§3 table: database present (AC2)', () {
    test('found → KeyReady with the stored key, lease released', () async {
      writeDb();
      store.stored = syntheticKeyBytes(5);
      final outcome = await bootstrap().obtain();
      expect(outcome, isA<KeyReady>());
      final ready = outcome as KeyReady;
      expect(
        ready.key.sameKeyAs(DbKeyMaterial.copyOf(syntheticKeyBytes(5))),
        isTrue,
      );
      expect(store.writeCalls, 0);
      expect(store.leaseHeld, isFalse);
    });

    for (final name in dbFileNames) {
      test('notFound with "$name" present → KeyInvalidated(missing), '
          'no key written, no file touched', () async {
        writeDb(name: name);
        final before = _snapshot(dir);
        final outcome = await bootstrap().obtain();
        expect(outcome, isA<KeyInvalidated>());
        expect(
          (outcome as KeyInvalidated).reason,
          KeyInvalidatedReason.missing,
        );
        expect(store.writeCalls, 0);
        expect(store.stored, isNull);
        expect(_sameSnapshot(before, _snapshot(dir)), isTrue);
        expect(store.leaseHeld, isTrue, reason: 'caller holds the lease');
        await outcome.lease.release();
      });
    }

    test(
      'unusable → KeyInvalidated(unusable), nothing written, files unchanged',
      () async {
        writeDb();
        File('${dir.path}/$dbFileName-wal').writeAsBytesSync([1, 2, 3]);
        store
          ..stored = syntheticKeyBytes(1)
          ..forcedStatus = SecretStatus.unusable;
        final before = _snapshot(dir);
        final outcome = await bootstrap().obtain();
        expect(outcome, isA<KeyInvalidated>());
        expect(
          (outcome as KeyInvalidated).reason,
          KeyInvalidatedReason.unusable,
        );
        expect(store.writeCalls, 0);
        expect(_sameBytes(store.stored!, syntheticKeyBytes(1)), isTrue);
        expect(_sameSnapshot(before, _snapshot(dir)), isTrue);
        await outcome.lease.release();
      },
    );

    test(
      'unavailable → KeyUnavailable, nothing written, files unchanged',
      () async {
        writeDb();
        store
          ..stored = syntheticKeyBytes(1)
          ..forcedStatus = SecretStatus.unavailable;
        final before = _snapshot(dir);
        final outcome = await bootstrap().obtain();
        expect(outcome, isA<KeyUnavailable>());
        expect(store.writeCalls, 0);
        expect(_sameSnapshot(before, _snapshot(dir)), isTrue);
        expect(store.leaseHeld, isFalse);
      },
    );

    test(
      'an unreadable database directory is "can\'t tell", never "absent"',
      () async {
        final notADir = File('${dir.path}/not_a_dir')..writeAsStringSync('x');
        final b = KeyBootstrap(
          store: store,
          files: DbFileSet(Directory(notADir.path)),
          generator: FixedKeyGenerator(),
        );
        store.stored = syntheticKeyBytes(1);
        final outcome = await b.obtain();
        expect(outcome, isA<KeyUnavailable>());
        expect(store.writeCalls, 0);
        expect(store.leaseHeld, isFalse);
      },
    );
  });

  group('AC1: first run creates the key, the next run reads the same key', () {
    test('two bootstraps (two app launches) see one key', () async {
      final first = await bootstrap().obtain() as KeyCreated;
      writeDb(); // T-016 creates the database under the lease
      await first.lease.release();

      final second = await bootstrap(generator: SequenceKeyGenerator([99]))
          .obtain();
      expect(second, isA<KeyReady>());
      expect((second as KeyReady).key.sameKeyAs(first.key), isTrue);
      expect(store.createCalls, 1);
    });
  });

  group('lease', () {
    test('a held lease → KeyUnavailable(leaseTimeout), nothing read', () async {
      store.holdLease();
      final outcome = await bootstrap(
        leaseTimeout: const Duration(milliseconds: 50),
      ).obtain();
      expect(outcome, isA<KeyUnavailable>());
      expect(
        (outcome as KeyUnavailable).reason,
        KeyUnavailableReason.leaseTimeout,
      );
      expect(store.calls.contains('read'), isFalse);
    });

    test('a channel failure on acquire → KeyUnavailable(transient)', () async {
      store.failAcquire = SecretStoreErrorCode.unavailable;
      final outcome = await bootstrap().obtain();
      expect(outcome, isA<KeyUnavailable>());
      expect(
        (outcome as KeyUnavailable).reason,
        KeyUnavailableReason.transient,
      );
    });

    test('two concurrent first runs get one key (engines serialise)', () async {
      final b1 = bootstrap();
      final b2 = bootstrap(generator: SequenceKeyGenerator([7]));
      final f1 = b1.obtain();
      final f2 = b2.obtain();
      final o1 = await f1 as KeyCreated;
      expect(store.leaseHeld, isTrue);
      writeDb(); // engine 1 creates the database, then releases
      await o1.lease.release();
      final o2 = await f2;
      expect(o2, isA<KeyReady>());
      expect((o2 as KeyReady).key.sameKeyAs(o1.key), isTrue);
      expect(store.createCalls, 1);
    });

    test('createIfAbsent: an existing key wins over the candidate', () async {
      store.beforeCreate = () {
        store.stored ??= syntheticKeyBytes(
          3,
        ); // a racing writer got there first
      };
      final outcome = await bootstrap().obtain() as KeyCreated;
      expect(
        outcome.key.sameKeyAs(DbKeyMaterial.copyOf(syntheticKeyBytes(3))),
        isTrue,
      );
      await outcome.lease.release();
    });
  });

  group('failures never create a database key silently', () {
    test('no generator → KeyStoreFailed(generate), nothing written', () async {
      final outcome = await bootstrap(generator: _NullGenerator()).obtain();
      expect(outcome, isA<KeyStoreFailed>());
      expect((outcome as KeyStoreFailed).reason, KeyStoreFailedReason.generate);
      expect(store.writeCalls, 0);
      expect(store.leaseHeld, isFalse);
    });

    test('an all-equal candidate → KeyStoreFailed(generate)', () async {
      final outcome = await bootstrap(generator: _DegenerateGenerator())
          .obtain();
      expect(outcome, isA<KeyStoreFailed>());
      expect(store.createCalls, 0);
    });

    test(
      'store write failure → KeyStoreFailed(write), lease released',
      () async {
        store.failCreate = SecretStoreErrorCode.storeFailed;
        final outcome = await bootstrap().obtain();
        expect(outcome, isA<KeyStoreFailed>());
        expect((outcome as KeyStoreFailed).reason, KeyStoreFailedReason.write);
        expect(store.leaseHeld, isFalse);
      },
    );

    test('delete failure during rotation → KeyStoreFailed(write)', () async {
      store
        ..stored = syntheticKeyBytes(1)
        ..failDelete = SecretStoreErrorCode.storeFailed;
      final outcome = await bootstrap().obtain();
      expect(outcome, isA<KeyStoreFailed>());
      expect(store.createCalls, 0);
      expect(_sameBytes(store.stored!, syntheticKeyBytes(1)), isTrue);
    });

    test(
      'lease lost before the write → KeyUnavailable(leaseTimeout)',
      () async {
        store.failCreate = SecretStoreErrorCode.leaseTimeout;
        final outcome = await bootstrap().obtain();
        expect(outcome, isA<KeyUnavailable>());
        expect(
          (outcome as KeyUnavailable).reason,
          KeyUnavailableReason.leaseTimeout,
        );
      },
    );

    test(
      'a database file appearing before the write → no key written',
      () async {
        final gen = _CallbackGenerator(writeDb);
        store.stored = syntheticKeyBytes(1); // found + no db → rotation path
        final outcome = await bootstrap(generator: gen).obtain();
        expect(outcome, isA<KeyUnavailable>());
        expect(store.writeCalls, 0);
        expect(_sameBytes(store.stored!, syntheticKeyBytes(1)), isTrue);
      },
    );
  });

  group('reportRejected (T-016 SQLITE_NOTADB hook)', () {
    test('same key + database → KeyInvalidated(rejectedBySqlite)', () async {
      writeDb();
      store.stored = syntheticKeyBytes(5);
      final ready = await bootstrap().obtain() as KeyReady;
      final outcome = await bootstrap().reportRejected(ready.key);
      expect(outcome, isA<KeyInvalidated>());
      expect(
        (outcome as KeyInvalidated).reason,
        KeyInvalidatedReason.rejectedBySqlite,
      );
      expect(store.writeCalls, 0);
      await outcome.lease.release();
    });

    test(
      'key rotated by another engine meanwhile → KeyReady(new key)',
      () async {
        writeDb();
        final stale = DbKeyMaterial.copyOf(syntheticKeyBytes(5));
        store.stored = syntheticKeyBytes(6);
        final outcome = await bootstrap().reportRejected(stale);
        expect(outcome, isA<KeyReady>());
        expect(
          (outcome as KeyReady).key.sameKeyAs(
            DbKeyMaterial.copyOf(syntheticKeyBytes(6)),
          ),
          isTrue,
        );
        expect(store.leaseHeld, isFalse);
      },
    );
  });

  group('recreateAfterWipe (orphan path, D-50, Q2 notice)', () {
    test(
      'after the wipe → KeyCreated(afterWipe) with the restore notice',
      () async {
        writeDb();
        store
          ..stored = syntheticKeyBytes(1)
          ..forcedStatus = SecretStatus.unusable;
        final b = bootstrap();
        final invalid = await b.obtain() as KeyInvalidated;
        for (final f in DbFileSet(dir).files) {
          if (f.existsSync()) f.deleteSync();
        }
        final outcome = await b.recreateAfterWipe(invalid.lease);
        expect(outcome, isA<KeyCreated>());
        final created = outcome as KeyCreated;
        expect(created.reason, KeyCreatedReason.afterWipe);
        expect(created.restoreNoticeDue, isTrue);
        expect(_sameBytes(store.stored!, syntheticKeyBytes()), isTrue);
        expect(store.leaseHeld, isTrue);
        await created.lease.release();
      },
    );

    test('database files still present → KeyStoreFailed(wipeIncomplete), '
        'nothing written, lease still held', () async {
      writeDb();
      final b = bootstrap();
      final invalid = await b.obtain() as KeyInvalidated;
      final outcome = await b.recreateAfterWipe(invalid.lease);
      expect(outcome, isA<KeyStoreFailed>());
      expect(
        (outcome as KeyStoreFailed).reason,
        KeyStoreFailedReason.wipeIncomplete,
      );
      expect(store.writeCalls, 0);
      expect(store.leaseHeld, isTrue);
      await invalid.lease.release();
    });

    test('a released lease is a programming error', () async {
      writeDb();
      final b = bootstrap();
      final invalid = await b.obtain() as KeyInvalidated;
      await invalid.lease.release();
      expect(() => b.recreateAfterWipe(invalid.lease), throwsStateError);
    });
  });

  group('key material (design note §5)', () {
    test('candidate and read buffers are zeroed after use', () async {
      final gen = FixedKeyGenerator();
      final created = await bootstrap(generator: gen).obtain() as KeyCreated;
      expect(gen.handedOut.every(_allZero), isTrue);
      writeDb();
      await created.lease.release();
      await bootstrap().obtain();
      expect(store.handedOut, isNotEmpty);
      expect(store.handedOut.every(_allZero), isTrue);
    });

    test('zeroize wipes the bytes and blocks further use', () {
      final key = DbKeyMaterial.copyOf(syntheticKeyBytes());
      final twin = DbKeyMaterial.copyOf(syntheticKeyBytes());
      expect(key.sameKeyAs(twin), isTrue);
      key.zeroize();
      expect(key.isZeroized, isTrue);
      expect(() => key.toRawKeyHex(), throwsStateError);
      expect(key.sameKeyAs(twin), isFalse);
      key.zeroize(); // idempotent
    });

    test('copyOf copies, and refuses a wrong length', () {
      final src = syntheticKeyBytes();
      final key = DbKeyMaterial.copyOf(src);
      src.fillRange(0, src.length, 0);
      expect(key.sameKeyAs(DbKeyMaterial.copyOf(syntheticKeyBytes())), isTrue);
      expect(() => DbKeyMaterial.copyOf(Uint8List(31)), throwsArgumentError);
    });

    test('no value equality on key bytes', () {
      final a = DbKeyMaterial.copyOf(syntheticKeyBytes());
      final b = DbKeyMaterial.copyOf(syntheticKeyBytes());
      expect(a == b, isFalse);
      expect(a.sameKeyAs(b), isTrue);
    });

    test('toRawKeyHex is 64 lowercase hex characters', () {
      final hex = DbKeyMaterial.copyOf(syntheticKeyBytes()).toRawKeyHex();
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hex), isTrue);
    });
  });

  group('generator', () {
    test('SecureKeyGenerator gives 32 fresh, non-degenerate bytes', () {
      final g = SecureKeyGenerator();
      final a = g.next()!;
      final b = g.next()!;
      expect(a.length, dbKeyLength);
      expect(isDegenerateKey(a), isFalse);
      expect(_sameBytes(a, b), isFalse);
    });

    test('a constant generator is rejected', () {
      expect(SecureKeyGenerator(random: _ConstantRandom.new).next(), isNull);
    });

    test('no secure source → null', () {
      expect(
        SecureKeyGenerator(
          random: () => throw UnsupportedError('no secure source'),
        ).next(),
        isNull,
      );
    });

    test('isDegenerateKey', () {
      expect(isDegenerateKey(Uint8List(dbKeyLength)), isTrue);
      expect(isDegenerateKey(Uint8List(16)), isTrue);
      expect(isDegenerateKey(syntheticKeyBytes()), isFalse);
    });
  });

  group('AC3 (unit): nothing prints key material', () {
    test('toString of the key, every outcome and the store types', () async {
      final needles = keyNeedles(syntheticKeyBytes());
      final key = DbKeyMaterial.copyOf(syntheticKeyBytes());
      final created = await bootstrap().obtain() as KeyCreated;
      writeDb();
      await created.lease.release();
      final ready = await bootstrap().obtain() as KeyReady;
      final texts = <String>[
        key.toString(),
        created.toString(),
        created.key.toString(),
        created.lease.toString(),
        ready.toString(),
        ready.key.toString(),
        KeyInvalidated(KeyInvalidatedReason.missing, created.lease).toString(),
        const KeyUnavailable(KeyUnavailableReason.transient).toString(),
        const KeyStoreFailed(KeyStoreFailedReason.write).toString(),
        SecretRead(SecretStatus.found, value: syntheticKeyBytes()).toString(),
        const SecretStoreException(SecretStoreErrorCode.storeFailed).toString(),
        for (final o in [created, ready]) o.diagFields('android').toString(),
        '$key $ready $created',
      ];
      // Decimal list form too (Uint8List.toString()).
      final decimal = syntheticKeyBytes().toString();
      for (final t in texts) {
        expect(
          containsAnyNeedle(Uint8List.fromList(t.codeUnits), needles) ||
              t.contains(decimal.substring(1, 20)),
          isFalse,
        );
      }
      expect(key.toString(), 'DbKeyMaterial(<redacted>)');
    });

    test('diag codes and the only diag fields', () async {
      store.stored = syntheticKeyBytes(1);
      final rotated = await bootstrap().obtain() as KeyCreated;
      expect(rotated.diagCode, 'DB_KEY_ROTATED');
      expect(rotated.diagFields('ios').keys.toSet(), {
        'reason',
        'platform',
        'attempts',
      });
      await rotated.lease.release();
      expect(
        KeyInvalidated(KeyInvalidatedReason.unusable, rotated.lease).diagCode,
        'DB_KEY_INVALIDATED',
      );
      expect(
        const KeyUnavailable(KeyUnavailableReason.transient).diagCode,
        'DB_KEY_UNAVAILABLE',
      );
      expect(
        const KeyStoreFailed(KeyStoreFailedReason.generate).diagCode,
        'DB_KEY_STORE_FAILED',
      );
    });
  });
}

class _CallbackGenerator implements KeyGenerator {
  _CallbackGenerator(this.onNext);

  final void Function({String name}) onNext;

  @override
  Uint8List? next() {
    onNext();
    return syntheticKeyBytes();
  }
}
