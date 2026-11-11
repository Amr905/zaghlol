// T-030: cross-implementation proof. The backend (T-123/T-125, .NET) signs
// and serialises; this package must verify and decode its bytes, so the app
// seed and the backend snapshot stay one format. Vectors are the backend
// contract-test files (synthetic keys, public JWKs only).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zaghlol_catalog/zaghlol_catalog.dart';

const _dir = '../../backend/tests/Zaghlol.Contract.Tests/vectors';

Map<String, Object?> _load(String name) =>
    jsonDecode(File('$_dir/$name').readAsStringSync()) as Map<String, Object?>;

List<SeedTrustedKey> _keys(Map<String, Object?> doc) => [
  for (final k
      in ((doc['jwks']! as Map<String, Object?>)['keys']! as List<Object?>)
          .cast<Map<String, Object?>>())
    SeedTrustedKey.fromJwk(
      kid: k['kid']! as String,
      x: k['x']! as String,
      y: k['y']! as String,
    ),
];

Uint8List _body(String b64u) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(b64u)));

void main() {
  test('a backend-signed catalog snapshot verifies and decodes', () {
    final doc = _load('catalog-snapshot-v1.json');
    final snap = doc['snapshot']! as Map<String, Object?>;
    final bytes = _body(snap['bodyB64u']! as String);
    final header = (snap['header'] ?? snap['signature']) as String?;
    expect(header, isNotNull, reason: 'snapshot header member');
    expect(
      verifySeedSignature(bytes, header!, _keys(doc), allowDevKeys: true),
      's0000t',
    );
    final seed = CatalogSeed.decode(bytes);
    expect(seed.version, 7);
    // The backend's own bytes are already in our canonical form.
    expect(seed.encode(), bytes);
  });

  test('every backend response-signature vector agrees with the verifier', () {
    final doc = _load('response-signature-v1.json');
    final keys = _keys(doc);
    for (final v
        in (doc['valid']! as List<Object?>).cast<Map<String, Object?>>()) {
      final bytes = _body(v['bodyB64u']! as String);
      expect(
        verifySeedSignature(
          bytes,
          v['header']! as String,
          keys,
          allowDevKeys: true,
        ),
        isNotEmpty,
        reason: v['name'] as String,
      );
    }
    final invalid = doc['invalid'];
    if (invalid is List<Object?>) {
      for (final v in invalid.cast<Map<String, Object?>>()) {
        final body = v['bodyB64u'];
        final header = v['header'];
        if (body is! String || header is! String) continue;
        expect(
          () => verifySeedSignature(
            _body(body),
            header,
            keys,
            allowDevKeys: true,
          ),
          throwsA(isA<CatalogSeedException>()),
          reason: v['name'] as String?,
        );
      }
    }
  });
}
