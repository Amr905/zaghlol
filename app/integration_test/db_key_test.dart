// T-015: the database key bootstrap on the real Keystore / Keychain (design
// note §9). Runs in db-platform.yml on the Android API 35 / API 26 emulators
// and the iOS simulator (after db_platform_test.dart), and on devices
// (T-171 checklist):
//   flutter test integration_test/db_key_test.dart --flavor devNoSms -d <id>
//
// AC1: first run creates the key, a new ProviderContainer reads the same key
//      and the database written with it reads back.
// AC2: an existing database with a deleted key (both platforms), a deleted
//      Keystore alias (Android) or a flipped blob byte (Android) is
//      KeyInvalidated, and nothing is written or touched.
// AC3: the fixed synthetic key (support/synthetic_key.dart; seeds 61 and 62)
//      is in no file of the app sandbox; the CI host greps the device logs
//      for the same needles (.github/scripts/db-key-log-scan.sh).
//
// Hygiene: keys are synthetic and never printed; assertions compare
// booleans, counts and enum values. The only output line is
// ZAGHLOL_KEY_SCAN (counts).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/core/db/db_file_set.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart';
import 'package:zaghlol/core/platform/pigeon_secret_store.dart';

import '../test/core/db/sqlite3mc_contract.dart' show ContractDb;
import '../test/support/synthetic_key.dart';

/// The app sandbox root: Directory.systemTemp is `<dataDir>/code_cache` on
/// Android and `<container>/tmp` on iOS (ADR-002).
Directory get _sandboxRoot => Directory.systemTemp.parent;

File get _androidBlob =>
    File('${_sandboxRoot.path}/no_backup/keys/db_key_v1.bin');

final List<List<int>> _needles = [
  ...keyNeedles(syntheticKeyBytes(61)),
  ...keyNeedles(syntheticKeyBytes(62)),
];

Map<String, Uint8List> _snapshot(Directory dir) => {
  for (final e in dir.listSync().whereType<File>())
    e.uri.pathSegments.last: e.readAsBytesSync(),
};

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameSnapshot(Map<String, Uint8List> a, Map<String, Uint8List> b) =>
    a.length == b.length &&
    a.keys.every((k) => b.containsKey(k) && _sameBytes(a[k]!, b[k]!));

final class _ScanResult {
  int files = 0;
  int bytes = 0;
  int unreadable = 0;
  int hits = 0;
}

/// Walks [root] without following links and counts files holding a needle.
Future<_ScanResult> _scan(Directory root, List<List<int>> needles) async {
  final r = _ScanResult();
  await for (final e
      in root
          .list(recursive: true, followLinks: false)
          .handleError((Object _) => r.unreadable++)) {
    if (e is! File) continue;
    final Uint8List bytes;
    try {
      bytes = await e.readAsBytes();
    } on FileSystemException {
      r.unreadable++;
      continue;
    }
    r.files++;
    r.bytes += bytes.length;
    if (containsAnyNeedle(bytes, needles)) r.hits++;
  }
  return r;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final store = PigeonSecretStore();
  late Directory dir;

  Future<void> resetSlot() async {
    final lease = await store.acquireBootstrapLease(
      const Duration(seconds: 35),
    );
    try {
      await store.delete(lease, SecretSlot.dbKey);
    } finally {
      await store.releaseBootstrapLease(lease);
    }
  }

  ProviderContainer container(KeyGenerator generator) {
    final c = ProviderContainer(
      overrides: [
        dbDirectoryProvider.overrideWithValue(dir),
        keyGeneratorProvider.overrideWithValue(generator),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<KeyBootstrapOutcome> obtain([KeyGenerator? generator]) async {
    final outcome = await container(generator ?? FixedKeyGenerator(61))
        .read(keyBootstrapProvider)
        .obtain();
    switch (outcome) {
      case KeyCreated(:final lease) || KeyInvalidated(:final lease):
        addTearDown(lease.release);
      default:
        break;
    }
    return outcome;
  }

  File dbFile() => DbFileSet(dir).mainFile;

  Future<void> write(DbKeyMaterial key) async {
    final db = ContractDb(openEncryptedExecutor(dbFile(), key));
    try {
      await db.customStatement('CREATE TABLE IF NOT EXISTS s (v TEXT)');
      await db.customStatement("INSERT INTO s (v) VALUES ('t015')");
    } finally {
      await db.close();
    }
  }

  Future<int> count(DbKeyMaterial key) async {
    final db = ContractDb(openEncryptedExecutor(dbFile(), key));
    try {
      final rows = await db.customSelect('SELECT count(*) AS n FROM s').get();
      return rows.single.data['n'] as int;
    } finally {
      await db.close();
    }
  }

  /// First run: key created, database created under the lease, released.
  Future<void> firstRun() async {
    final created = await obtain() as KeyCreated;
    expect(created.reason, KeyCreatedReason.firstRun);
    await write(created.key);
    created.key.zeroize();
    await created.lease.release();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zaghlol_t015_it_');
    await resetSlot();
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
    await resetSlot();
  });

  test(
    'AC1: first run creates the key; the next run reads the same key',
    () async {
      final created = await obtain() as KeyCreated;
      expect(created.reason, KeyCreatedReason.firstRun);
      final firstKey = DbKeyMaterial.copyOf(syntheticKeyBytes(61));
      expect(created.key.sameKeyAs(firstKey), isTrue);
      await write(created.key);
      created.key.zeroize();
      await created.lease.release();

      // A new ProviderContainer = a new launch. A different generator proves
      // the key is read, not regenerated.
      final second = await obtain(FixedKeyGenerator(62));
      expect(second, isA<KeyReady>());
      final ready = second as KeyReady;
      expect(ready.key.sameKeyAs(firstKey), isTrue);
      expect(await count(ready.key), 1);
      ready.key.zeroize();
      if (Platform.isAndroid) {
        expect(_androidBlob.lengthSync(), 61);
      }
    },
  );

  test('AC2: database present, key deleted → KeyInvalidated(missing); '
      'nothing written; the orphan path recreates the key', () async {
    await firstRun();
    await resetSlot(); // iOS: the Keychain item; Android: blob + alias
    final before = _snapshot(dir);

    final outcome = await obtain();
    expect(outcome, isA<KeyInvalidated>());
    final invalid = outcome as KeyInvalidated;
    expect(invalid.reason, KeyInvalidatedReason.missing);
    expect(
      (await store.read(SecretSlot.dbKey)).status,
      SecretStatus.notFound,
      reason: 'no key was written',
    );
    expect(_sameSnapshot(before, _snapshot(dir)), isTrue);

    // T-016's orphan path: wipe under the lease, then recreate.
    for (final f in DbFileSet(dir).files) {
      if (f.existsSync()) f.deleteSync();
    }
    final recreated = await container(FixedKeyGenerator(62))
        .read(keyBootstrapProvider)
        .recreateAfterWipe(invalid.lease);
    expect(recreated, isA<KeyCreated>());
    final created = recreated as KeyCreated;
    expect(created.reason, KeyCreatedReason.afterWipe);
    expect(created.restoreNoticeDue, isTrue);
    await write(created.key);
    expect(await count(created.key), 1);
    created.key.zeroize();
    await created.lease.release();
  });

  test('AC2 (Android): Keystore alias deleted, blob kept → KeyInvalidated(unusable)', () async {
    await firstRun();
    final blob = _androidBlob.readAsBytesSync();
    await resetSlot(); // deletes blob and alias
    _androidBlob.writeAsBytesSync(blob, flush: true); // blob back, alias gone
    final before = _snapshot(dir);

    final outcome = await obtain();
    expect(outcome, isA<KeyInvalidated>());
    expect((outcome as KeyInvalidated).reason, KeyInvalidatedReason.unusable);
    expect(_sameBytes(_androidBlob.readAsBytesSync(), blob), isTrue);
    expect(_sameSnapshot(before, _snapshot(dir)), isTrue);
  }, skip: Platform.isAndroid ? false : 'Android Keystore only');

  test(
    'AC2 (Android): one blob byte flipped → KeyInvalidated(unusable)',
    () async {
      await firstRun();
      final blob = _androidBlob.readAsBytesSync();
      blob[20] ^= 0x01;
      _androidBlob.writeAsBytesSync(blob, flush: true);
      final before = _snapshot(dir);

      final outcome = await obtain();
      expect(outcome, isA<KeyInvalidated>());
      expect((outcome as KeyInvalidated).reason, KeyInvalidatedReason.unusable);
      expect(_sameBytes(_androidBlob.readAsBytesSync(), blob), isTrue);
      expect(_sameSnapshot(before, _snapshot(dir)), isTrue);
    },
    skip: Platform.isAndroid ? false : 'Android Keystore only',
  );

  test('T-016 hook: SQLITE_NOTADB with the stored key → '
      'KeyInvalidated(rejectedBySqlite)', () async {
    await firstRun();
    // Corrupt page 1 (the salt): indistinguishable from a wrong key.
    final bytes = dbFile().readAsBytesSync();
    bytes.fillRange(0, 16, 0x5A);
    dbFile().writeAsBytesSync(bytes, flush: true);

    final ready = await obtain() as KeyReady;
    Object? failure;
    try {
      await count(ready.key);
    } on Object catch (e) {
      failure = e;
    }
    final open = failure == null ? null : dbOpenExceptionOf(failure);
    expect(open?.isKeyRejected, isTrue);

    final outcome = await container(FixedKeyGenerator(61))
        .read(keyBootstrapProvider)
        .reportRejected(ready.key);
    expect(outcome, isA<KeyInvalidated>());
    final invalid = outcome as KeyInvalidated;
    addTearDown(invalid.lease.release);
    expect(invalid.reason, KeyInvalidatedReason.rejectedBySqlite);
    ready.key.zeroize();
  });

  test('AC3: no form of the key in any file of the sandbox', () async {
    await firstRun();
    final ready = await obtain() as KeyReady;
    expect(await count(ready.key), 1);
    ready.key.zeroize();

    final root = _sandboxRoot;
    final result = await _scan(root, _needles);
    // ignore: avoid_print
    print(
      'ZAGHLOL_KEY_SCAN ${jsonEncode({'files': result.files, 'bytes': result.bytes, 'unreadable': result.unreadable, 'hits': result.hits})}',
    );
    expect(result.files > 0, isTrue);
    expect(result.hits, 0);
    if (Platform.isAndroid) {
      expect(_androidBlob.existsSync(), isTrue, reason: 'blob was scanned');
    }

    // Positive control: the same scanner finds a planted needle.
    final control = File('${Directory.systemTemp.path}/t015_control.bin');
    try {
      control.writeAsBytesSync(_needles[1], flush: true);
      final planted = await _scan(root, _needles);
      expect(
        planted.hits,
        1,
        reason: 'control: scanner finds a planted needle',
      );
    } finally {
      if (control.existsSync()) control.deleteSync();
    }
  });
}
