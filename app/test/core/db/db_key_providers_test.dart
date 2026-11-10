// T-015: the providers are stateless wiring (design note §6): no provider
// holds key bytes or an outcome; each obtain() asks the store again.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/core/db/db_file_set.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/db/key_bootstrap.dart';
import 'package:zaghlol/core/platform/pigeon_secret_store.dart';

import '../../support/fake_secret_store.dart';
import '../../support/synthetic_key.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zaghlol_t015_prov_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('defaults: Pigeon store and the secure generator', () {
    final c = ProviderContainer(
      overrides: [dbDirectoryProvider.overrideWithValue(dir)],
    );
    addTearDown(c.dispose);
    expect(c.read(secretStoreProvider), isA<PigeonSecretStore>());
    expect(c.read(keyGeneratorProvider), isA<SecureKeyGenerator>());
    expect(c.read(dbFileSetProvider).directory.path, dir.path);
    expect(c.read(keyBootstrapProvider), isA<KeyBootstrap>());
  });

  test('the database directory must be configured by T-016', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(() => c.read(dbFileSetProvider), throwsA(anything));
  });

  test('the bootstrap is stateless: every obtain asks the store', () async {
    final store = FakeSecretStore();
    final c = ProviderContainer(
      overrides: [
        dbDirectoryProvider.overrideWithValue(dir),
        secretStoreProvider.overrideWithValue(store),
        keyGeneratorProvider.overrideWithValue(FixedKeyGenerator()),
      ],
    );
    addTearDown(c.dispose);

    final first = await c.read(keyBootstrapProvider).obtain() as KeyCreated;
    File('${dir.path}/$dbFileName').writeAsBytesSync(const [1]);
    await first.lease.release();
    expect(await c.read(keyBootstrapProvider).obtain(), isA<KeyReady>());

    // The key disappears natively: the very next obtain sees it.
    store.forcedStatus = SecretStatus.unusable;
    expect(await c.read(keyBootstrapProvider).obtain(), isA<KeyInvalidated>());
    expect(store.calls.where((x) => x == 'read').length, 3);
  });
}
