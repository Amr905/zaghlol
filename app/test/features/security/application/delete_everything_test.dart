// T-166: "Delete everything" against a real encrypted database in a temp
// directory, a fake key store and a fake native wipe. Synthetic data only.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/app_restart.dart';
import 'package:zaghlol/core/platform/widget_bridge_api.g.dart';
import 'package:zaghlol/features/security/application/delete_everything_providers.dart';
import 'package:zaghlol/features/settings/presentation/settings_ports.dart';
import 'package:zaghlol/features/widgets_bridge/application/widget_bridge.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/backend_state.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/backend/transport.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/features/gold/application/trusted_time.dart'
    show trustedTimeStateKey;
import 'package:zaghlol/features/security/application/delete_everything.dart';

import '../../../core/backend/backend_test_support.dart';
import '../../../core/db/db_open_harness.dart';
import '../../../support/fake_secret_store.dart';

final class _FakeNative implements NativeWipe {
  _FakeNative(this.log);
  final List<String> log;
  Object? failWith;
  int calls = 0;

  @override
  Future<void> wipeLocalData() async {
    calls++;
    log.add('native');
    final f = failWith;
    if (f != null) throw f;
  }
}

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

const _installId = '00000000-0000-4000-8000-0000000000aa';

final class _World {
  _World._(this.db, this.store, this.world);

  static Future<_World> open() async {
    final store = FakeSecretStore();
    final world = await DbWorld.create(store, tag: 't166');
    final db = openedDb(await world.open());
    return _World._(db, store, world);
  }

  final AppDatabase db;
  final FakeSecretStore store;
  final DbWorld world;
  final List<String> log = [];
  late final _FakeNative native = _FakeNative(log);
  final List<InstallCredentials> remoteCalls = [];
  Future<bool> Function(InstallCredentials)? remote;
  int rotations = 0;
  int signOuts = 0;

  WipeMarker get marker => WipeMarker.inDirectory(world.root);

  Future<void> seedSecrets() async {
    final dao = SecureStateDao(db);
    for (final e in {
      BackendStateKeys.installId: _installId,
      BackendStateKeys.installToken: fakeToken(7),
      BackendStateKeys.entitlementToken: 'aGVhZGVy.cGF5bG9hZA.c2ln',
      BackendStateKeys.accountToken: 'YWNjb3VudA.dG9rZW4.c2ln',
      trustedTimeStateKey: '{"hw":1}',
      'support_notice': '1',
    }.entries) {
      await dao.write(e.key, _b(e.value), at: 1);
    }
    await world.tempDir.create(recursive: true);
    await File('${world.tempDir.path}/export.enc').writeAsBytes([1, 2, 3]);
  }

  DeleteEverything wipe() => DeleteEverything(
    readInstall: () =>
        readInstallCredentials(SecureStateBackendStore(SecureStateDao(db))),
    deleteRemote: (c) {
      log.add('remote');
      remoteCalls.add(c);
      return remote?.call(c) ?? Future.value(true);
    },
    rotateSeatKeys: () async {
      log.add('seat');
      rotations++;
    },
    cancelJobs: () async => log.add('jobs'),
    closeDatabase: () async {
      log.add('close');
      await db.close();
    },
    secrets: store,
    files: world.files,
    tempDirectory: () async => world.tempDir,
    native: native,
    signOutLocal: () async {
      log.add('signout');
      signOuts++;
    },
    marker: marker,
    leaseTimeout: const Duration(seconds: 1),
  );

  Future<void> dispose() => world.dispose();
}

void main() {
  test('AC: after the wipe the next open finds no database, no key, no '
      'tokens and no trusted-time state (negative proof)', () async {
    final w = await _World.open();
    addTearDown(w.dispose);
    await w.seedSecrets();
    expect(w.store.stored, isNotNull);

    final report = await w.wipe().run();

    expect(report.complete, isTrue, reason: '$report');
    expect(await report.remote, isTrue);
    // Order: seat keys, jobs, close, then native; remote last.
    expect(w.log, ['seat', 'jobs', 'close', 'native', 'signout', 'remote']);
    // The key slots went (crypto-shred) under the lease, both slots.
    expect(w.store.stored, isNull);
    expect(w.store.slotsTouched, containsAll(SecretSlot.values));
    expect(w.store.leaseHeld, isFalse);
    // No database file, no temp file, no marker.
    expect(await w.world.files.anyExists(), isFalse);
    expect(w.world.tempDir.listSync(), isEmpty);
    expect(await w.marker.exists(), isFalse);
    // The backend got the pre-wipe credentials.
    expect(w.remoteCalls.single.installId, _installId);

    // "Reopen the app": the opener sees no key and no file and creates a
    // fresh database; secure_state is empty.
    final fresh = openedDb(await w.world.open(seed: 62));
    addTearDown(fresh.close);
    final dao = SecureStateDao(fresh);
    for (final k in [
      BackendStateKeys.installId,
      BackendStateKeys.installToken,
      BackendStateKeys.entitlementToken,
      BackendStateKeys.accountToken,
      trustedTimeStateKey,
      'support_notice',
    ]) {
      expect(await dao.read(k), isNull, reason: k);
    }
    final rows = await fresh
        .customSelect('SELECT count(*) AS n FROM secure_state')
        .getSingle();
    expect(rows.read<int>('n'), 0);
  });

  test(
    'AC: works offline — the local wipe never waits for the backend',
    () async {
      final w = await _World.open();
      addTearDown(w.dispose);
      await w.seedSecrets();
      final never = Completer<bool>();
      w.remote = (_) => never.future;

      final report = await w.wipe().run().timeout(const Duration(seconds: 10));

      expect(report.complete, isTrue);
      expect(w.store.stored, isNull);
      expect(await w.world.files.anyExists(), isFalse);
      var remoteDone = false;
      unawaited(report.remote.then((_) => remoteDone = true));
      await Future<void>.delayed(Duration.zero);
      expect(remoteDone, isFalse);
      never.complete(false);
    },
  );

  test('a failed remote delete is reported, not thrown', () async {
    final w = await _World.open();
    addTearDown(w.dispose);
    await w.seedSecrets();
    w.remote = (_) => Future.error(StateError('offline'));
    final report = await w.wipe().run();
    expect(report.complete, isTrue);
    expect(await report.remote, isFalse);
  });

  test('a failed native step keeps the marker; resume() finishes without '
      'calling the backend', () async {
    final w = await _World.open();
    addTearDown(w.dispose);
    await w.seedSecrets();
    w.native.failWith = Exception('IO_ERROR');

    final first = await w.wipe().run();
    expect(first.failed, [WipeSteps.native]);
    expect(await w.marker.exists(), isTrue);
    // The crypto-shred still happened.
    expect(w.store.stored, isNull);
    expect(await w.world.files.anyExists(), isFalse);

    w.native.failWith = null;
    w.remoteCalls.clear();
    final again = await w.wipe().resume();
    expect(again.complete, isTrue);
    expect(await again.remote, isFalse);
    expect(w.remoteCalls, isEmpty);
    expect(await w.marker.exists(), isFalse);
    expect(w.native.calls, 2);
  });

  test(
    'a key-store failure keeps the marker and still deletes the files',
    () async {
      final w = await _World.open();
      addTearDown(w.dispose);
      await w.seedSecrets();
      w.store.failDelete = SecretStoreErrorCode.storeFailed;
      final report = await w.wipe().run();
      expect(report.failed, contains(WipeSteps.keySlots));
      expect(w.store.leaseHeld, isFalse);
      expect(await w.world.files.anyExists(), isFalse);
      expect(await w.marker.exists(), isTrue);
    },
  );

  test('seat-key and sign-out failures never block the wipe', () async {
    final w = await _World.open();
    addTearDown(w.dispose);
    final wipe = DeleteEverything(
      readInstall: () async => null,
      deleteRemote: (_) async => true,
      rotateSeatKeys: () async => throw Exception('SEAT_KEY_UNAVAILABLE'),
      cancelJobs: () async {},
      closeDatabase: w.db.close,
      secrets: w.store,
      files: w.world.files,
      tempDirectory: () async => w.world.tempDir,
      native: w.native,
      signOutLocal: () async => throw StateError('not initialized'),
      marker: w.marker,
      leaseTimeout: const Duration(seconds: 1),
    );
    final report = await wipe.run();
    expect(report.complete, isTrue);
    expect(await report.remote, isFalse); // no install: no call
    expect(w.store.stored, isNull);
  });

  group('deleteInstallBestEffort', () {
    final creds = InstallCredentials(
      installId: _installId,
      installToken: fakeToken(9),
    );

    BackendClient clientOver(FakeTransport t, BackendStateStore s) =>
        BackendClient(
          config: BackendConfig(
            baseUri: Uri.parse('https://api.test.invalid'),
            verifier: ResponseSignatureVerifier([
              TestSigningKey('s2026a').publicKey,
            ]),
          ),
          identity: ClientIdentity(
            platform: ClientPlatform.android,
            appVersion: '1.2.3',
            build: '42',
          ),
          transport: t,
          store: s,
        );

    test('sends DELETE /v1/installs/me with the snapshot token only', () async {
      final t = FakeTransport(
        [],
        (r) async =>
            BackendResponse(status: 202, headers: {}, body: Uint8List(0)),
      );
      final ok = await deleteInstallBestEffort(
        creds,
        clientFor: (s) => clientOver(t, s),
        retryDelay: Duration.zero,
      );
      expect(ok, isTrue);
      final r = t.requests.single;
      expect(r.method, 'DELETE');
      expect(r.uri.path, '/v1/installs/me');
      expect(r.headers['zaghlol-install'], _installId);
      expect(r.headers['authorization'], 'Bearer ${fakeToken(9)}');
      expect(r.headers.containsKey('zaghlol-account'), isFalse);
    });

    test('offline: one retry, then gives up (false)', () async {
      final t = FakeTransport(
        [],
        (r) async =>
            throw const TransportException(TransportFailureKind.offline),
      );
      final ok = await deleteInstallBestEffort(
        creds,
        clientFor: (s) => clientOver(t, s),
        retryDelay: Duration.zero,
      );
      expect(ok, isFalse);
      expect(t.requests, hasLength(2));
    });

    test('a refused token is not retried and never re-registers', () async {
      final t = FakeTransport(
        [],
        (r) async => problem(401, 'INSTALL_TOKEN_INVALID'),
      );
      final ok = await deleteInstallBestEffort(
        creds,
        clientFor: (s) => clientOver(t, s),
        retryDelay: Duration.zero,
      );
      expect(ok, isFalse);
      expect(t.requests, hasLength(1));
      expect(t.requests.single.uri.path, '/v1/installs/me');
    });
  });

  group('wipeEverythingOverride (WIRE-2)', () {
    Future<(ProviderContainer, _Host, List<int>)> setUpWipe(_World w) async {
      final host = _Host();
      final restarts = <int>[];
      final c = ProviderContainer(
        overrides: [
          deleteEverythingProvider.overrideWithValue(w.wipe()),
          appRestartProvider.overrideWithValue(() => restarts.add(1)),
          widgetBridgeHostProvider.overrideWithValue(host),
          wipeEverythingOverride,
        ],
      );
      addTearDown(c.dispose);
      return (c, host, restarts);
    }

    test('success clears the widget snapshot, then restarts', () async {
      final w = await _World.open();
      addTearDown(w.dispose);
      final (c, host, restarts) = await setUpWipe(w);
      await c.read(wipeEverythingProvider)!();
      expect(host.clears, 1);
      expect(restarts, hasLength(1));
    });

    test('a wipe that stays incomplete throws, does not restart, still '
        'clears the widget', () async {
      final w = await _World.open();
      addTearDown(w.dispose);
      w.native.failWith = Exception('native down');
      final (c, host, restarts) = await setUpWipe(w);
      await expectLater(
        c.read(wipeEverythingProvider)!(),
        throwsA(isA<WipeIncomplete>()),
      );
      expect(restarts, isEmpty);
      expect(host.clears, 1);
    });
  });

  test('credentials never print', () {
    final c = InstallCredentials(installId: _installId, installToken: 'x');
    expect('$c', isNot(contains(_installId)));
  });
}

final class _Host extends WidgetBridgeHostApi {
  int clears = 0;

  @override
  Future<void> clear() async => clears++;
}
