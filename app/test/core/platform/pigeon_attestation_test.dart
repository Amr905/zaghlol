// T-178: PigeonAttestation over the real Pigeon channel with a fake platform
// side (a mock message handler using the generated codec). Proves the bytes
// the platform receives are exactly the binding library's hash for the
// shared vectors (R2-1, R4-1(3)), the error map, fail-closed proof checks and
// that nothing secret reaches errors or logs. All values are synthetic.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/attestation_api.g.dart';
import 'package:zaghlol/core/platform/pigeon_attestation.dart';
import 'package:zaghlol/features/gold/domain/binding/request_binding.dart';

const _rel = 'backend/tests/Zaghlol.Contract.Tests/vectors';
const _attestChannel = 'dev.flutter.pigeon.zaghlol.AttestationHostApi.attest';
const _prepareChannel = 'dev.flutter.pigeon.zaghlol.AttestationHostApi.prepare';
const _sentinel = 'SECRET-SENTINEL-T178';

Map<String, dynamic> _vectors(String name) {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final f = File('${dir.path}/$_rel/$name');
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  fail('shared vector file $name not found above ${Directory.current.path}');
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<Uint8List> _seatKeys(Map<String, dynamic> body) {
  final att = body['attestation'] as Map<String, dynamic>?;
  final keys = att?['seatKeys'] as List<dynamic>? ?? const [];
  return [
    for (final k in keys)
      base64Url.decode(
        base64Url.normalize((k as Map<String, dynamic>)['publicKey'] as String),
      ),
  ];
}

/// The fake platform side: decodes what Dart sent with the generated codec
/// and answers with a scripted reply.
class _FakePlatform {
  final List<Uint8List> hashes = [];
  final List<bool> force = [];
  int prepares = 0;

  /// A proof to return, or a [PlatformException] to answer with.
  Object reply = AttestationProof(type: 'play_integrity', token: 'tok');
  Object? prepareReply;

  void install() {
    const codec = AttestationHostApi.pigeonChannelCodec;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(_attestChannel, (ByteData? message) async {
      final args = codec.decodeMessage(message)! as List<Object?>;
      hashes.add(Uint8List.fromList(args[0]! as Uint8List));
      force.add(args[1]! as bool);
      return codec.encodeMessage(_envelope(reply));
    });
    messenger.setMockMessageHandler(_prepareChannel, (ByteData? _) async {
      prepares++;
      return codec.encodeMessage(_envelope(prepareReply));
    });
  }

  static List<Object?> _envelope(Object? r) => r is PlatformException
      ? <Object?>[r.code, r.message, r.details]
      : <Object?>[r];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlatform platform;
  setUp(() {
    platform = _FakePlatform()..install();
  });
  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler(_attestChannel, null);
    m.setMockMessageHandler(_prepareChannel, null);
  });

  group('R2-1: the platform receives exactly the binding hash', () {
    final restore = _vectors('restore-binding-v1.json');
    for (final v in (restore['valid'] as List).cast<Map<String, dynamic>>()) {
      test(v['name'] as String, () async {
        final body = v['body'] as Map<String, dynamic>;
        final bodyHash = restoreBodyHashFromJson(
          v['installId'] as String,
          jsonEncode(body),
        );
        expect(_hex(bodyHash), v['bodyHashHex']);
        final ios = body['platform'] == 'ios';
        // Android signs bodyHash; iOS signs the clientDataHash over the seat keys.
        final hash = ios
            ? restoreClientDataHash(bodyHash, _seatKeys(body))
            : bodyHash;
        if (ios) expect(_hex(hash), v['clientDataHashHex']);
        platform.reply = ios
            ? AttestationProof(type: 'app_attest', keyId: 'k', assertion: 'a')
            : AttestationProof(type: 'play_integrity', token: 't');

        await PigeonAttestation().attest(hash);

        expect(platform.hashes, hasLength(1));
        expect(_hex(platform.hashes.single), _hex(hash));
        if (!ios) {
          expect(
            base64Url.encode(platform.hashes.single).replaceAll('=', ''),
            v['requestHashB64u'],
          );
        }
      });
    }
  });

  test('forceNewKey is passed through; default is false', () async {
    final a = PigeonAttestation();
    await a.attest(Uint8List(32));
    await a.attest(Uint8List(32), forceNewKey: true);
    expect(platform.force, [false, true]);
  });

  test('a caller mutating its buffer after the call changes nothing sent', () {
    final hash = Uint8List.fromList(List.generate(32, (i) => i));
    final f = PigeonAttestation().attest(hash);
    hash.fillRange(0, 32, 0xFF);
    return f.then((_) {
      expect(platform.hashes.single, List.generate(32, (i) => i));
    });
  });

  test('proofs are returned field by field', () async {
    platform.reply = AttestationProof(
      type: 'app_attest',
      keyId: 'key',
      assertion: 'asr',
      attestationObject: 'obj',
    );
    final p = await PigeonAttestation().attest(Uint8List(32));
    expect(p.type, DeviceAttestationProof.appAttest);
    expect(p.keyId, 'key');
    expect(p.assertion, 'asr');
    expect(p.attestationObject, 'obj');
    expect(p.token, isNull);

    platform.reply = AttestationProof(type: 'play_integrity', token: 'tok');
    final q = await PigeonAttestation().attest(Uint8List(32));
    expect(q.type, DeviceAttestationProof.playIntegrity);
    expect(q.token, 'tok');
    expect(q.keyId, isNull);
  });

  test('a wrong-length hash never reaches the platform', () async {
    for (final n in [0, 31, 33, 64]) {
      expect(
        () => PigeonAttestation().attest(Uint8List(n)),
        throwsArgumentError,
      );
    }
    expect(platform.hashes, isEmpty);
  });

  test('error codes map to typed failures (platform-channels §6)', () async {
    const cases = {
      'ATTEST_TRANSIENT': AttestationFailure.transient,
      'ATTEST_PLAY_SERVICES_OUTDATED': AttestationFailure.playServicesOutdated,
      'ATTEST_UNAVAILABLE': AttestationFailure.unavailable,
      'SOMETHING_NEW': AttestationFailure.unavailable,
    };
    for (final e in cases.entries) {
      platform.reply = PlatformException(code: e.key);
      platform.prepareReply = PlatformException(code: e.key);
      await expectLater(
        PigeonAttestation().attest(Uint8List(32)),
        throwsA(
          isA<AttestationException>().having(
            (x) => x.failure,
            'failure',
            e.value,
          ),
        ),
      );
      await expectLater(
        PigeonAttestation().prepare(),
        throwsA(
          isA<AttestationException>().having(
            (x) => x.failure,
            'failure',
            e.value,
          ),
        ),
      );
    }
  });

  test('prepare succeeds through the channel', () async {
    await PigeonAttestation().prepare();
    expect(platform.prepares, 1);
  });

  test('malformed proofs fail closed', () async {
    final bad = [
      AttestationProof(type: 'play_integrity'),
      AttestationProof(type: 'play_integrity', token: ''),
      AttestationProof(type: 'app_attest', keyId: 'k'),
      AttestationProof(type: 'app_attest', assertion: 'a'),
      AttestationProof(type: 'app_attest', keyId: '', assertion: 'a'),
      AttestationProof(type: 'safetynet', token: 't'),
      AttestationProof(type: '', token: 't'),
    ];
    for (final p in bad) {
      platform.reply = p;
      await expectLater(
        PigeonAttestation().attest(Uint8List(32)),
        throwsA(
          isA<AttestationException>().having(
            (x) => x.failure,
            'failure',
            AttestationFailure.unavailable,
          ),
        ),
      );
    }
  });

  test('no channel registered is a code-only unavailable failure', () async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler(_attestChannel, null);
    await expectLater(
      PigeonAttestation().attest(Uint8List(32)),
      throwsA(
        isA<AttestationException>().having(
          (x) => x.failure,
          'failure',
          AttestationFailure.unavailable,
        ),
      ),
    );
  });

  // Log capture: no proof, token or key ID and no native message reaches
  // print / debugPrint, an exception text or the proof's toString.
  test('nothing secret is printed or put into errors', () async {
    final out = <String>[];
    final oldDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => out.add(m ?? '');
    try {
      await runZoned(
        () async {
          platform.reply = AttestationProof(
            type: 'app_attest',
            keyId: '$_sentinel-key',
            assertion: '$_sentinel-assertion',
            attestationObject: '$_sentinel-object',
          );
          final p = await PigeonAttestation().attest(Uint8List(32));
          out.add('$p');

          platform.reply = AttestationProof(
            type: 'play_integrity',
            token: '$_sentinel-token',
          );
          out.add('${await PigeonAttestation().attest(Uint8List(32))}');

          platform.reply = PlatformException(
            code: 'ATTEST_TRANSIENT',
            message: _sentinel,
            details: _sentinel,
          );
          try {
            await PigeonAttestation().attest(Uint8List(32));
          } on AttestationException catch (e) {
            out.add('$e');
          }
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => out.add(line),
        ),
      );
    } finally {
      debugPrint = oldDebugPrint;
    }
    expect(out, isNotEmpty);
    for (final line in out) {
      expect(line, isNot(contains(_sentinel)));
    }
  });
}
