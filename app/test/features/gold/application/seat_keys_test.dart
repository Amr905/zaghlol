// T-179: SeatKeyService over a fake native side (a Dart model of the Keychain
// FIFO of SeatKeyStore.swift), the SeatKeyHostApi channel with a fake
// platform, R5-6, Android, and the no-logs rule. Synthetic keys only.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/platform/seat_key_api.g.dart';
import 'package:zaghlol/features/gold/application/seat_keys.dart';
import 'package:zaghlol/features/gold/domain/binding/request_binding.dart';

import '../../../core/backend/backend_test_support.dart';

const _idA = '0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77';
const _idB = '0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e78';
const _vectorRel = 'backend/tests/Zaghlol.Contract.Tests/vectors';

/// Models the native contract: own key fixed until rotated, FIFO of 5.
final class FakeNative implements SeatKeyHostApi {
  FakeNative({int seed = 1}) : _rnd = Random(seed);
  final Random _rnd;
  Uint8List? own;
  final List<Uint8List> earlier = []; // newest first
  int rotations = 0;
  int calls = 0;
  String? failWith;
  List<Uint8List>? overrideKeys;
  final List<Uint8List> signed = [];

  Uint8List _newKey() =>
      Uint8List.fromList([4, for (var i = 0; i < 64; i++) _rnd.nextInt(256)]);

  void _check() {
    calls++;
    final f = failWith;
    if (f != null) throw PlatformException(code: f);
  }

  List<Uint8List> _keys() {
    own ??= _newKey();
    return [own!, ...earlier.take(4)];
  }

  @override
  Future<List<Uint8List>> publicKeys() async {
    _check();
    return overrideKeys ?? _keys();
  }

  @override
  Future<List<SeatSignature>> sign(Uint8List message) async {
    _check();
    signed.add(message);
    return [
      for (final k in overrideKeys ?? _keys())
        SeatSignature(
          publicKey: k,
          signature: Uint8List(64)..fillRange(0, 64, 7),
        ),
    ];
  }

  @override
  Future<void> rotateForNewInstall() async {
    _check();
    rotations++;
    final o = own;
    if (o == null) return;
    earlier.insert(0, o);
    if (earlier.length > 4) earlier.removeLast();
    own = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class Setup {
  Setup({this.platform = ClientPlatform.ios, FakeNative? native})
    : native = native ?? FakeNative() {
    service = make();
  }
  final ClientPlatform platform;
  final FakeNative native;
  final store = FakeBackendStore([]);
  String? installId = _idA;
  late SeatKeyService service;

  SeatKeyService make() => SeatKeyService(
    platform: platform,
    store: store,
    installId: () async => installId,
    host: native,
  );
}

Uint8List _challenge() => Uint8List(32)..fillRange(0, 32, 9);

Map<String, dynamic> _vectors() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final f = File('${dir.path}/$_vectorRel/seat-proof-v1.json');
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  fail('seat-proof-v1.json not found');
}

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('install binding (element 0, R4-1(1))', () {
    test('element 0 is the same across launches of one install', () async {
      final s = Setup();
      final first = await s.service.publicKeys();
      final relaunch = await s.make().publicKeys();
      final proof = await s.make().prove(SeatOp.verify, _challenge());
      expect(first, hasLength(1));
      expect(relaunch.first, first.first);
      expect(proof.first.publicKey, first.first);
      expect(s.native.rotations, 1, reason: 'only the first use of an install');
    });

    test('a new install (reinstall / re-registration) moves the former own '
        'key to element 1', () async {
      final s = Setup();
      final a = (await s.service.publicKeys()).first;
      s.installId = _idB;
      final keys = await s.service.publicKeys();
      expect(keys, hasLength(2));
      expect(keys[0], isNot(a));
      expect(keys[1], a);
    });

    test('"Delete everything" rotates; the next install gets a new own key '
        'and the former one at element 1', () async {
      final s = Setup();
      final a = (await s.service.publicKeys()).first;
      expect(await s.service.rotateForNewInstall(), isTrue);
      s.store.values.clear(); // the wipe; the native keys stay (D-55)
      s.installId = _idB;
      final keys = await s.service.publicKeys();
      expect(keys[0], isNot(a));
      expect(keys[1], a);
      expect(keys, hasLength(2), reason: 'rotation is idempotent');
    });

    test('six installs keep five keys, newest first', () async {
      final s = Setup();
      final owns = <Uint8List>[];
      for (var i = 0; i < 6; i++) {
        s.installId = '0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e7$i';
        owns.add((await s.service.publicKeys()).first);
      }
      s.installId = _idA;
      final keys = await s.service.publicKeys();
      expect(keys, hasLength(5));
      expect(keys.sublist(1), owns.reversed.take(4).toList());
    });

    test('two concurrent first uses rotate once (one owner)', () async {
      final s = Setup();
      final r = await Future.wait([
        s.service.prove(SeatOp.restore, _challenge()),
        s.service.publicKeys(),
      ]);
      expect(s.native.rotations, 1);
      expect(
        (r[0] as List<SeatSignature>).first.publicKey,
        (r[1] as List).first,
      );
    });

    test('prove() signs exactly the T-183 message for this install', () async {
      final s = Setup();
      await s.service.prove(SeatOp.signin, _challenge());
      expect(
        s.native.signed.single,
        seatMessage(SeatOp.signin, _idA, _challenge()),
      );
    });

    test('no install ID yet: no keys, no native call', () async {
      final s = Setup()..installId = null;
      expect(await s.service.publicKeys(), isEmpty);
      expect(s.native.calls, 0);
    });
  });

  group('R5-6 own-key-unusable flag', () {
    test('suppresses seatKeys for this install and is gone after '
        'InstallReregistered', () async {
      final s = Setup();
      final events = StreamController<BackendEvent>.broadcast();
      s.service.start(events.stream);
      expect(await s.service.publicKeys(), hasLength(1));
      await s.service.markOwnKeyUnusable();
      expect(await s.service.ownKeyUnusable(), isTrue);
      final before = s.native.calls;
      expect(await s.service.publicKeys(), isEmpty);
      expect(await s.service.prove(SeatOp.restore, _challenge()), isEmpty);
      expect(s.native.calls, before, reason: 'suppressed before native');

      s.installId = _idB; // R5-1 re-registration
      events.add(const InstallReregistered());
      await pumpEventQueue();
      expect(s.store.values.containsKey(seatKeyUnusableStateKey), isFalse);
      expect(await s.service.ownKeyUnusable(), isFalse);
      expect(await s.service.publicKeys(), hasLength(2));
      await s.service.stop();
      await events.close();
    });

    test('a flag already set for the new install survives the event', () async {
      final s = Setup();
      final events = StreamController<BackendEvent>.broadcast();
      s.service.start(events.stream);
      s.installId = _idB;
      await s.service.markOwnKeyUnusable();
      events.add(const InstallReregistered());
      await pumpEventQueue();
      expect(await s.service.ownKeyUnusable(), isTrue);
      await s.service.stop();
      await events.close();
    });

    test('a flag of another install never suppresses', () async {
      final s = Setup();
      await s.service.markOwnKeyUnusable();
      s.installId = _idB;
      expect(await s.service.publicKeys(), isNotEmpty);
    });
  });

  group('failures give no keys', () {
    test(
      'SEAT_KEY_UNAVAILABLE: no keys and no install binding written',
      () async {
        final s = Setup();
        s.native.failWith = seatKeyUnavailableCode;
        expect(await s.service.publicKeys(), isEmpty);
        expect(await s.service.prove(SeatOp.verify, _challenge()), isEmpty);
        expect(s.store.values.containsKey(seatKeyInstallStateKey), isFalse);
        expect(await s.service.rotateForNewInstall(), isFalse);
        s.native.failWith = null;
        expect(await s.service.publicKeys(), hasLength(1));
      },
    );

    test('malformed native answers are dropped whole', () async {
      final good = Uint8List(65)..[0] = 4;
      final good2 = Uint8List(65)
        ..[0] = 4
        ..[1] = 1;
      for (final keys in <List<Uint8List>>[
        [Uint8List(65)], // not an uncompressed point
        [Uint8List(64)..[0] = 4],
        [good, good], // duplicate
        List.generate(
          6,
          (i) => Uint8List(65)
            ..[0] = 4
            ..[1] = i,
        ),
      ]) {
        final s = Setup();
        s.native.overrideKeys = keys;
        expect(await s.service.publicKeys(), isEmpty);
        expect(await s.service.prove(SeatOp.verify, _challenge()), isEmpty);
      }
      final s = Setup();
      s.native.overrideKeys = [good, good2];
      expect(await s.service.publicKeys(), hasLength(2));
    });
  });

  group('Android (D-55)', () {
    test('SeatKeyService returns no keys and never calls native', () async {
      final s = Setup(platform: ClientPlatform.android);
      expect(await s.service.publicKeys(), isEmpty);
      expect(await s.service.prove(SeatOp.verify, _challenge()), isEmpty);
      expect(await s.service.rotateForNewInstall(), isTrue);
      expect(s.native.calls, 0);
    });

    test('the Pigeon contract has no Kotlin output and no Kotlin source '
        'implements SeatKeyHostApi', () {
      final pigeon = File('pigeons/seat_key.dart').readAsStringSync();
      expect(pigeon, isNot(contains('kotlinOut:')));
      expect(pigeon, contains('swiftOut:'));
      final kt = Directory('android')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.kt'));
      for (final f in kt) {
        expect(
          f.readAsStringSync(),
          isNot(contains('SeatKey')),
          reason: f.path,
        );
      }
    });
  });

  group('no logs (D-62)', () {
    test(
      'keys, signatures and native error text never print or echo',
      () async {
        final printed = <String>[];
        await runZoned(
          () async {
            final s = Setup();
            final keys = await s.service.publicKeys();
            final proofs = await s.service.prove(SeatOp.restore, _challenge());
            await s.service.markOwnKeyUnusable();
            s.native.failWith = seatKeyUnavailableCode;
            s.installId = _idB;
            await s.service.publicKeys();
            final secrets = [
              for (final k in keys) base64Url.encode(k),
              for (final k in keys) _hex(k),
              for (final p in proofs) base64Url.encode(p.signature),
            ];
            final all = [
              ...printed,
              s.service.toString(),
              ...proofs.map((p) => p.toString()),
            ].join('\n');
            for (final x in secrets) {
              expect(all.contains(x), isFalse);
            }
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => printed.add(line),
          ),
        );
        expect(printed, isEmpty);
      },
    );

    test('seat-key sources contain no logging call', () {
      final dart = File('lib/features/gold/application/seat_keys.dart');
      expect(
        RegExp(
          r'\b(print|debugPrint|log|developer\.log|dump)\(|\b(stdout|stderr)\b',
        ).hasMatch(dart.readAsStringSync()),
        isFalse,
      );
      for (final f in [
        'ios/Runner/Platform/Keys/SeatKeyStore.swift',
        'ios/Runner/Platform/Keys/SeatKeyHost.swift',
      ]) {
        expect(
          File(f).readAsStringSync(),
          isNot(matches(RegExp(r'\b(print|NSLog|os_log|debugPrint|Logger)\('))),
          reason: f,
        );
      }
    });
  });

  group('channel with a fake platform', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = binding.defaultBinaryMessenger;
    const prefix = 'dev.flutter.pigeon.zaghlol.SeatKeyHostApi';
    const codec = SeatKeyHostApi.pigeonChannelCodec;
    tearDown(() {
      for (final m in ['publicKeys', 'sign', 'rotateForNewInstall']) {
        messenger.setMockMessageHandler('$prefix.$m', null);
      }
    });

    test('the vector message reaches native byte for byte and the answer '
        'decodes', () async {
      final v = (_vectors()['valid'] as List).first as Map<String, dynamic>;
      final pk = base64Url.decode(
        base64Url.normalize(v['publicKey'] as String),
      );
      final sig = base64Url.decode(
        base64Url.normalize(v['signature'] as String),
      );
      Uint8List? received;
      messenger.setMockMessageHandler('$prefix.rotateForNewInstall', (_) async {
        return codec.encodeMessage(<Object?>[null]);
      });
      messenger.setMockMessageHandler('$prefix.sign', (ByteData? m) async {
        received = (codec.decodeMessage(m)! as List)[0] as Uint8List;
        return codec.encodeMessage([
          [SeatSignature(publicKey: pk, signature: sig)],
        ]);
      });
      final service = SeatKeyService(
        platform: ClientPlatform.ios,
        store: FakeBackendStore([]),
        installId: () async => v['installId'] as String,
      );
      final challenge = Uint8List.fromList([
        for (var i = 0; i < 64; i += 2)
          int.parse(
            (v['challengeHex'] as String).substring(i, i + 2),
            radix: 16,
          ),
      ]);
      final out = await service.prove(SeatOp.restore, challenge);
      expect(_hex(received!), v['messageHex']);
      expect(out.single.publicKey, pk);
      expect(out.single.signature, sig);
      expect(out.single.publicKey, hasLength(65));
      expect(out.single.signature, hasLength(64));
    });

    test('SEAT_KEY_UNAVAILABLE over the channel gives no keys', () async {
      messenger.setMockMessageHandler('$prefix.rotateForNewInstall', (_) async {
        return codec.encodeMessage(<Object?>[null]);
      });
      messenger.setMockMessageHandler('$prefix.publicKeys', (_) async {
        return codec.encodeMessage([seatKeyUnavailableCode, null, null]);
      });
      final service = SeatKeyService(
        platform: ClientPlatform.ios,
        store: FakeBackendStore([]),
        installId: () async => _idA,
      );
      expect(await service.publicKeys(), isEmpty);
    });

    test('the Swift test vector constants match seat-proof-v1.json', () {
      final v = _vectors()['valid'] as List;
      final restore = v.firstWhere((e) => e['name'] == 'restore') as Map;
      final lowS = v.firstWhere((e) => e['name'] == 'restore-low-s') as Map;
      final swift = File('ios/RunnerTests/SeatKeyTests.swift')
          .readAsStringSync();
      expect(swift, contains('"${restore['messageHex']}"'));
      expect(swift, contains('"${lowS['publicKey']}"'));
      expect(swift, contains('"${lowS['signature']}"'));
    });
  });
}
