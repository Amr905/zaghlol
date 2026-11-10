// T-015: PigeonSecretStore maps the Pigeon results and drops every native
// message (platform-channels §6, FU-050).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/core/platform/pigeon_secret_store.dart';
import 'package:zaghlol/core/platform/secret_store_api.g.dart';

import '../../support/synthetic_key.dart';

class _FakeApi extends SecretStoreHostApi {
  Object? error;
  SecretReadMsg? readResult;
  final List<String> calls = [];

  Future<T> _answer<T>(String name, T value) async {
    calls.add(name);
    final e = error;
    if (e != null) throw e;
    return value;
  }

  @override
  Future<int> acquireBootstrapLease(int timeoutMs) =>
      _answer('acquire:$timeoutMs', 7);

  @override
  Future<void> releaseBootstrapLease(int lease) =>
      _answer('release:$lease', null);

  bool renewResult = true;

  @override
  Future<bool> renewBootstrapLease(int lease) =>
      _answer('renew:$lease', renewResult);

  @override
  Future<SecretReadMsg> read(SecretSlotMsg slot) =>
      _answer('read:${slot.name}', readResult!);

  @override
  Future<Uint8List> createIfAbsent(
    int lease,
    SecretSlotMsg slot,
    Uint8List candidate,
  ) => _answer(
    'create:$lease:${slot.name}',
    // Like the codec: an unmodifiable view.
    Uint8List.fromList(candidate).asUnmodifiableView(),
  );

  @override
  Future<void> delete(int lease, SecretSlotMsg slot) =>
      _answer('delete:$lease:${slot.name}', null);
}

void main() {
  late _FakeApi api;
  late PigeonSecretStore store;

  setUp(() {
    api = _FakeApi();
    store = PigeonSecretStore(api: api);
  });

  test('passes lease ids, slots and the timeout through', () async {
    final lease = await store.acquireBootstrapLease(
      const Duration(seconds: 10),
    );
    expect(lease.id, 7);
    await store.createIfAbsent(lease, SecretSlot.dbKey, syntheticKeyBytes());
    await store.delete(lease, SecretSlot.dbKey);
    await store.releaseBootstrapLease(lease);
    expect(api.calls, [
      'acquire:10000',
      'create:7:dbKey',
      'delete:7:dbKey',
      'release:7',
    ]);
  });

  test('maps every read status', () async {
    final cases = {
      SecretStatusMsg.notFound: SecretStatus.notFound,
      SecretStatusMsg.unusable: SecretStatus.unusable,
      SecretStatusMsg.unavailable: SecretStatus.unavailable,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      api.readResult = SecretReadMsg(status: key, attempts: 3);
      final r = await store.read(SecretSlot.dbKey);
      expect(r.status, value);
      expect(r.value, isNull);
      expect(r.attempts, 3);
    }
    api.readResult = SecretReadMsg(
      status: SecretStatusMsg.found,
      value: syntheticKeyBytes(),
      attempts: 1,
    );
    final found = await store.read(SecretSlot.dbKey);
    expect(found.status, SecretStatus.found);
    expect(found.value!.length, 32);
  });

  test('codec values are copied so the caller can zero them', () async {
    api.readResult = SecretReadMsg(
      status: SecretStatusMsg.found,
      value: syntheticKeyBytes().asUnmodifiableView(),
      attempts: 1,
    );
    final read = (await store.read(SecretSlot.dbKey)).value!;
    read.fillRange(0, read.length, 0);
    expect(read.every((b) => b == 0), isTrue);

    final created = await store.createIfAbsent(
      SecretStoreLease(1),
      SecretSlot.dbKey,
      syntheticKeyBytes(),
    );
    created.fillRange(0, created.length, 0);
    expect(created.every((b) => b == 0), isTrue);
  });

  test('found without a value is unavailable, never found', () async {
    api.readResult = SecretReadMsg(status: SecretStatusMsg.found, attempts: 1);
    expect(
      (await store.read(SecretSlot.dbKey)).status,
      SecretStatus.unavailable,
    );
  });

  test(
    'a failing read (e.g. no channel in this engine) is unavailable',
    () async {
      api.error = PlatformException(code: 'channel-error');
      final r = await store.read(SecretSlot.dbKey);
      expect(r.status, SecretStatus.unavailable);
      expect(r.attempts, 0);
    },
  );

  test('native error codes map to codes; messages are dropped', () async {
    const detail = 'native detail that must not cross';
    final cases = {
      'LEASE_TIMEOUT': SecretStoreErrorCode.leaseTimeout,
      'KEY_STORE_FAILED': SecretStoreErrorCode.storeFailed,
      'channel-error': SecretStoreErrorCode.unavailable,
      'SomethingElse': SecretStoreErrorCode.unavailable,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      api.error = PlatformException(
        code: key,
        message: detail,
        details: detail,
      );
      for (final call in <Future<Object?> Function()>[
        () => store.acquireBootstrapLease(const Duration(seconds: 1)),
        () => store.createIfAbsent(
          SecretStoreLease(1),
          SecretSlot.dbKey,
          syntheticKeyBytes(),
        ),
        () => store.delete(SecretStoreLease(1), SecretSlot.dbKey),
      ]) {
        try {
          await call();
          fail('expected SecretStoreException');
        } on SecretStoreException catch (e) {
          expect(e.code, value);
          expect(e.toString().contains(detail), isFalse);
        }
      }
    }
  });

  test('a non-platform error is unavailable', () async {
    api.error = StateError('x');
    await expectLater(
      store.acquireBootstrapLease(const Duration(seconds: 1)),
      throwsA(
        isA<SecretStoreException>().having(
          (e) => e.code,
          'code',
          SecretStoreErrorCode.unavailable,
        ),
      ),
    );
  });

  test('release never throws', () async {
    api.error = PlatformException(code: 'channel-error');
    await store.releaseBootstrapLease(SecretStoreLease(1));
  });

  // T-016 (S-2): renew passes the lease id through; any failure is "lapsed".
  test('renewBootstrapLease answers the native result', () async {
    expect(await store.renewBootstrapLease(SecretStoreLease(7)), isTrue);
    api.renewResult = false;
    expect(await store.renewBootstrapLease(SecretStoreLease(7)), isFalse);
    expect(api.calls, ['renew:7', 'renew:7']);
  });

  test('renewBootstrapLease never throws: a failure is false', () async {
    api.error = PlatformException(code: 'LEASE_TIMEOUT', message: 'detail');
    expect(await store.renewBootstrapLease(SecretStoreLease(7)), isFalse);
    api.error = StateError('channel not registered');
    expect(await store.renewBootstrapLease(SecretStoreLease(7)), isFalse);
  });
}
