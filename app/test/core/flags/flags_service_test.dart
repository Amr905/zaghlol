// T-025: feature flags, fail closed. Synthetic data only.

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/flags/feature_flags.dart';
import 'package:zaghlol/core/flags/flags_providers.dart';
import 'package:zaghlol/core/flags/flags_service.dart';

final class FakeStore implements FlagSnapshotStore {
  Uint8List? bytes;
  Object? readError;
  Object? writeError;
  int writes = 0;

  @override
  Future<Uint8List?> read() async {
    if (readError != null) throw readError!;
    return bytes;
  }

  @override
  Future<void> write(Uint8List b, {required int at}) async {
    if (writeError != null) throw writeError!;
    writes++;
    bytes = b;
  }
}

final class FakeRemote implements RemoteFlagsSource {
  FakeRemote(this.answer);
  RemoteFlags? answer;
  @override
  Future<RemoteFlags> fetch() async {
    final a = answer;
    if (a == null) throw const FlagsUnavailable();
    return a;
  }
}

RemoteFlags flags(int version, Map<String, Object?> values) =>
    RemoteFlags(version: version, values: values);

void main() {
  var now = DateTime.utc(2026, 11, 11, 12);
  late FakeStore store;
  late FlagsService service;

  FlagsService make({RemoteFlagsSource? remote}) =>
      FlagsService(store: store, clock: () => now, remote: remote);

  setUp(() {
    now = DateTime.utc(2026, 11, 11, 12);
    store = FakeStore();
    service = make();
  });

  tearDown(() => service.dispose());

  test('AC1: a never-synced app has every flag OFF', () async {
    await service.load();
    expect(service.current.status, FlagsStatus.neverSynced);
    for (final f in FeatureFlag.values) {
      expect(service.isOn(f), isFalse, reason: f.key);
    }
  });

  test('flag keys match the backend set', () {
    expect(
      [for (final f in FeatureFlag.values) f.key],
      ['zakah', 'smart_roi', 'roi_named_products'],
    );
    expect(FeatureFlag.fromKey('Zakah'), isNull);
  });

  test('apply stores, turns ON, and publishes the change', () async {
    await service.load();
    final seen = <FeatureFlagsState>[];
    final sub = service.changes.listen(seen.add);
    final r = await service.apply(
      flags(3, {'zakah': true, 'smart_roi': false}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(r, FlagsApplyResult.applied);
    expect(service.isOn(FeatureFlag.zakah), isTrue);
    expect(service.isOn(FeatureFlag.smartRoi), isFalse);
    expect(service.isOn(FeatureFlag.roiNamedProducts), isFalse); // missing
    expect(seen.single.version, 3);
    await sub.cancel();
  });

  test('AC2: a later change updates the state without a reload', () async {
    await service.load();
    await service.apply(flags(1, {'zakah': true}));
    final seen = <bool>[];
    final sub = service.changes.listen(
      (s) => seen.add(s.isOn(FeatureFlag.zakah)),
    );
    await service.apply(flags(2, {'zakah': false}));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [false]);
    expect(service.isOn(FeatureFlag.zakah), isFalse);
    await sub.cancel();
  });

  test('the snapshot survives a restart (new service, same store)', () async {
    await service.apply(flags(4, {'zakah': true}));
    final again = make();
    addTearDown(again.dispose);
    await again.load();
    expect(again.isOn(FeatureFlag.zakah), isTrue);
    expect(again.current.version, 4);
  });

  test(
    'unknown flags are ignored; non-bool values reject the whole answer',
    () async {
      await service.apply(flags(1, {'zakah': true, 'new_thing': true}));
      expect(service.isOn(FeatureFlag.zakah), isTrue);
      final before = store.writes;
      for (final bad in [
        flags(2, {'zakah': 'true'}),
        flags(2, {'zakah': 1}),
        flags(2, {'zakah': null}),
        flags(-1, {'zakah': true}),
        const RemoteFlags(version: '2', values: {'zakah': true}),
        const RemoteFlags(version: 2.5, values: {'zakah': true}),
        const RemoteFlags(version: 2, values: ['zakah']),
        const RemoteFlags(version: null, values: null),
        RemoteFlags(version: 2, values: {1: true}),
      ]) {
        expect(await service.apply(bad), FlagsApplyResult.rejected);
      }
      expect(store.writes, before);
      expect(service.isOn(FeatureFlag.zakah), isTrue); // unchanged
    },
  );

  test(
    'an older version is rejected (replay); an equal one is accepted',
    () async {
      await service.apply(flags(5, {'zakah': true}));
      expect(
        await service.apply(flags(4, {'zakah': false})),
        FlagsApplyResult.rejected,
      );
      expect(service.isOn(FeatureFlag.zakah), isTrue);
      expect(
        await service.apply(flags(5, {'zakah': false})),
        FlagsApplyResult.applied,
      );
      expect(service.isOn(FeatureFlag.zakah), isFalse);
    },
  );

  test(
    'stale: older than maxAge reads OFF; a new sync turns it back',
    () async {
      await service.apply(flags(1, {'zakah': true}));
      now = now.add(const Duration(days: 13, hours: 23));
      expect(service.isOn(FeatureFlag.zakah), isTrue);
      now = now.add(const Duration(hours: 1));
      expect(service.current.status, FlagsStatus.stale);
      expect(service.isOn(FeatureFlag.zakah), isFalse);
      await service.apply(flags(1, {'zakah': true}));
      expect(service.isOn(FeatureFlag.zakah), isTrue);
    },
  );

  test('stale publishes by itself when the age passes (timer)', () async {
    // Real timer with a tiny maxAge.
    final quick = FlagsService(
      store: store,
      clock: DateTime.now,
      maxAge: const Duration(milliseconds: 60),
    );
    addTearDown(quick.dispose);
    await quick.apply(flags(1, {'zakah': true}));
    final next = quick.changes.first;
    expect(
      (await next.timeout(const Duration(seconds: 2))).status,
      FlagsStatus.stale,
    );
  });

  test('a clock before the snapshot time reads OFF (unverifiable)', () async {
    await service.apply(flags(1, {'zakah': true}));
    now = now.subtract(const Duration(minutes: 4));
    expect(service.isOn(FeatureFlag.zakah), isTrue); // within tolerance
    now = now.subtract(const Duration(minutes: 2));
    expect(service.current.status, FlagsStatus.unverifiable);
    expect(service.isOn(FeatureFlag.zakah), isFalse);
  });

  group('unverifiable stored bytes read OFF and are not deleted', () {
    final cases = <String, Uint8List>{
      'not json': Uint8List.fromList([1, 2, 3]),
      'bad utf8': Uint8List.fromList([0xff, 0xfe]),
      'wrong shape': Uint8List.fromList(utf8.encode('[1]')),
      'wrong version tag': Uint8List.fromList(
        utf8.encode('{"v":2,"version":1,"at":1,"values":{"zakah":true}}'),
      ),
      'non-bool value': Uint8List.fromList(
        utf8.encode('{"v":1,"version":1,"at":1,"values":{"zakah":"yes"}}'),
      ),
      'too big': Uint8List(maxFlagsSnapshotBytes + 1),
    };
    for (final e in cases.entries) {
      test(e.key, () async {
        store.bytes = e.value;
        await service.load();
        expect(service.current.status, FlagsStatus.unverifiable);
        for (final f in FeatureFlag.values) {
          expect(service.isOn(f), isFalse);
        }
        expect(store.bytes, same(e.value));
        // A good sync recovers.
        await service.apply(flags(1, {'zakah': true}));
        expect(service.isOn(FeatureFlag.zakah), isTrue);
      });
    }
  });

  test(
    'a read error reads OFF; a write error propagates, state unchanged',
    () async {
      store.readError = Exception('x');
      await service.load();
      expect(service.current.status, FlagsStatus.unverifiable);
      store.readError = null;
      await service.load();
      store.writeError = StateError('disk');
      await expectLater(
        service.apply(flags(1, {'zakah': true})),
        throwsStateError,
      );
      expect(service.isOn(FeatureFlag.zakah), isFalse);
      // The failed write did not wedge the queue.
      store.writeError = null;
      expect(
        await service.apply(flags(1, {'zakah': true})),
        FlagsApplyResult.applied,
      );
    },
  );

  test('two syncs at once: serialized, the higher version wins', () async {
    await service.load();
    final results = await Future.wait([
      service.apply(flags(7, {'zakah': true})),
      service.apply(flags(6, {'zakah': false})),
    ]);
    expect(results, [FlagsApplyResult.applied, FlagsApplyResult.rejected]);
    expect(service.current.version, 7);
  });

  test('refresh: no source, unavailable source, good source', () async {
    expect(await service.refresh(), FlagsApplyResult.unavailable);
    final remote = FakeRemote(null);
    final s = make(remote: remote);
    addTearDown(s.dispose);
    expect(await s.refresh(), FlagsApplyResult.unavailable);
    expect(s.isOn(FeatureFlag.zakah), isFalse);
    remote.answer = flags(1, {'zakah': true});
    expect(await s.refresh(), FlagsApplyResult.applied);
    expect(s.isOn(FeatureFlag.zakah), isTrue);
  });

  test('the snapshot holds only flag data (no other content)', () async {
    await service.apply(flags(1, {'zakah': true}));
    final j = jsonDecode(utf8.decode(store.bytes!)) as Map;
    expect(j.keys.toSet(), {'v', 'version', 'at', 'values'});
  });

  test('SecureStateFlagStore round-trips on an in-memory database', () async {
    final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    final real = FlagsService(
      store: SecureStateFlagStore(SecureStateDao(db)),
      clock: () => now,
    );
    addTearDown(real.dispose);
    await real.load();
    expect(real.current.status, FlagsStatus.neverSynced);
    await real.apply(flags(2, {'smart_roi': true}));
    final again = FlagsService(
      store: SecureStateFlagStore(SecureStateDao(db)),
      clock: () => now,
    );
    addTearDown(again.dispose);
    await again.load();
    expect(again.isOn(FeatureFlag.smartRoi), isTrue);
    expect(again.isOn(FeatureFlag.zakah), isFalse);
  });

  group('providers', () {
    test('AC2: featureFlagProvider follows a sync, no restart', () async {
      await service.load();
      final container = ProviderContainer(
        overrides: [flagsServiceProvider.overrideWith((ref) async => service)],
      );
      addTearDown(container.dispose);
      final values = <bool>[];
      container.listen(
        featureFlagProvider(FeatureFlag.zakah),
        (_, n) => values.add(n),
        fireImmediately: true,
      );
      expect(values, [false]); // loading: OFF
      await container.read(featureFlagsProvider.future);
      await service.apply(flags(1, {'zakah': true}));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(featureFlagProvider(FeatureFlag.zakah)), isTrue);
      expect(values.last, isTrue);
      await service.apply(flags(2, {'zakah': false}));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(featureFlagProvider(FeatureFlag.zakah)), isFalse);
    });

    test('a failed service reads OFF', () async {
      final container = ProviderContainer(
        overrides: [
          flagsServiceProvider.overrideWith(
            (ref) async => throw StateError(''),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(featureFlagsProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(container.read(featureFlagProvider(FeatureFlag.zakah)), isFalse);
    });
  });
}
