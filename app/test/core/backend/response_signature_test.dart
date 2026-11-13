// T-141: the Dart verifier against the backend's own signature vectors
// (T-123, backend/tests/Zaghlol.Contract.Tests/vectors/response-signature-
// v1.json; synthetic keys, public JWKs only), plus the pinned-set rules.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/response_signature.dart';

import 'backend_test_support.dart';

const _vectors =
    '../backend/tests/Zaghlol.Contract.Tests/vectors/response-signature-v1.json';

Map<String, Object?> _doc() =>
    jsonDecode(File(_vectors).readAsStringSync()) as Map<String, Object?>;

List<ResponseKey> _keys(Map<String, Object?> doc) => [
  for (final k
      in ((doc['jwks']! as Map<String, Object?>)['keys']! as List<Object?>)
          .cast<Map<String, Object?>>())
    ResponseKey.fromJwk(
      kid: k['kid']! as String,
      x: k['x']! as String,
      y: k['y']! as String,
    ),
];

Uint8List _body(Object? b64u) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(b64u! as String)));

void main() {
  final doc = _doc();
  final verifier = ResponseSignatureVerifier(_keys(doc), allowDevKeys: true);

  group('backend vectors', () {
    for (final v in (doc['valid']! as List<Object?>).cast<Map<String, Object?>>()) {
      test('valid: ${v['name']}', () {
        expect(
          verifier.verify(_body(v['bodyB64u']), v['header']! as String),
          's0000t',
        );
      });
    }
    final invalid = (doc['invalid']! as List<Object?>)
        .cast<Map<String, Object?>>();
    test('there are invalid vectors (tampered body, unknown kid, e kid ...)', () {
      expect(invalid.length, greaterThanOrEqualTo(6));
    });
    for (final v in invalid) {
      test('rejected: ${v['name']}', () {
        expect(
          () => verifier.verify(_body(v['bodyB64u']), v['header']! as String),
          throwsA(isA<ResponseSignatureException>()),
        );
      });
    }
  });

  group('pinned key set', () {
    final key = TestSigningKey('s2026a');
    final other = TestSigningKey('s2026b', seed: 2);
    final body = Uint8List.fromList(utf8.encode('{"serverTime":"x"}'));

    test('a signature from a key outside the pinned set is refused', () {
      final v = ResponseSignatureVerifier([key.publicKey]);
      expect(v.verify(body, key.sign(body)), 's2026a');
      expect(
        () => v.verify(body, other.sign(body)),
        throwsA(isA<ResponseSignatureException>()),
      );
    });

    test('a missing header is refused', () {
      final v = ResponseSignatureVerifier([key.publicKey]);
      expect(
        () => v.verify(body, null),
        throwsA(isA<ResponseSignatureException>()),
      );
    });

    test('dev kids verify only when allowed (release refuses them)', () {
      final dev = TestSigningKey('s0000t', seed: 3);
      final sig = dev.sign(body);
      expect(
        () => ResponseSignatureVerifier([dev.publicKey]).verify(body, sig),
        throwsA(isA<ResponseSignatureException>()),
      );
      expect(
        ResponseSignatureVerifier([
          dev.publicKey,
        ], allowDevKeys: true).verify(body, sig),
        's0000t',
      );
    });

    test('the header is matched exactly (no trimming, no extra spaces)', () {
      final v = ResponseSignatureVerifier([key.publicKey]);
      final sig = key.sign(body);
      for (final bad in [
        ' $sig',
        '$sig ',
        sig.replaceFirst('; ', ';  '),
        sig.replaceFirst('alg=ES256', 'alg=es256'),
      ]) {
        expect(
          () => v.verify(body, bad),
          throwsA(isA<ResponseSignatureException>()),
        );
      }
    });

    test('an e (entitlement) kid never signs a header, even when pinned', () {
      final e = TestSigningKey('e2026a', seed: 4);
      expect(
        () => ResponseSignatureVerifier([e.publicKey]).verify(body, e.sign(body)),
        throwsA(isA<ResponseSignatureException>()),
      );
    });

    test('keys off the curve and duplicate kids are refused', () {
      expect(
        () => ResponseKey(kid: 's2026a', x: Uint8List(32), y: Uint8List(32)),
        throwsArgumentError,
      );
      expect(
        () => ResponseSignatureVerifier([key.publicKey, key.publicKey]),
        throwsArgumentError,
      );
    });
  });
}
