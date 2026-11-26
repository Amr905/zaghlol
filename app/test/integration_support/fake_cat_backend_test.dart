// T-363: the device test's fake backend (integration_test/support/
// fake_cat_backend.dart) speaks the contract: its answers parse with the
// app's own models, match backend/contracts/fixtures/categorise-responses-
// v1.json, the sync answer verifies under the pinned dev key, and the dev
// proof is checked against the body binding. Synthetic data; keys are made
// from formulas at run time.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:zaghlol/core/backend/backend_client.dart'
    show CategoriseResponse, InstallResponse, SyncResponse;
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/llm/llm_attestation.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';

import '../../integration_test/support/fake_cat_backend.dart';

final ECDomainParameters _p256 = ECDomainParameters('prime256v1');

Uint8List _be32(BigInt v) {
  final out = Uint8List(32);
  var rest = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest >>= 8;
  }
  return out;
}

const String _install = '0f1e2d3c-4b5a-4968-8776-655443322110';

void main() {
  late FakeCatBackend fake;
  late ResponseKey pinned;
  late String proofKey;
  late HttpClient http;

  setUp(() async {
    HttpOverrides.global = null; // flutter_test swaps in a fake client
    var d = BigInt.zero;
    for (var i = 0; i < 32; i++) {
      d = (d << 8) | BigInt.from((i * 37 + 11) & 0xff);
    }
    d = d % (_p256.n - BigInt.one) + BigInt.one;
    final q = (_p256.G * d)!;
    pinned = ResponseKey(
      kid: 's0000c',
      x: _be32(q.x!.toBigInteger()!),
      y: _be32(q.y!.toBigInteger()!),
    );
    proofKey = base64.encode([for (var i = 0; i < 32; i++) (i * 7 + 3) & 0xff]);
    fake = await FakeCatBackend.start(
      port: 0,
      kid: 's0000c',
      signingScalarB64Url: base64Url.encode(_be32(d)).replaceAll('=', ''),
      proofKeyB64: proofKey,
      providerId: 'e2e-test-provider',
      providerNameAr: 'مزود التجربة',
      providerNameEn: 'Test Provider',
    );
    http = HttpClient();
  });
  tearDown(() async {
    http.close(force: true);
    await fake.stop();
  });

  Future<(int, Map<String, Object?>, HttpClientResponse)> call(
    String path,
    Map<String, Object?>? body, {
    String? installId,
  }) async {
    final req = await http.postUrl(fake.baseUri.replace(path: path));
    req.headers.contentType = ContentType.json;
    if (installId != null) req.headers.set('zaghlol-install', installId);
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    return (res.statusCode, jsonDecode(text) as Map<String, Object?>, res);
  }

  Map<String, Object?> categoriseBody(
    List<String> merchants, {
    bool goodProof = true,
  }) {
    final base = <String, Object?>{
      'v': 1,
      'requestId': '01J9Z8Y7X6W5V4T3S2R1Q0P9N8',
      'lang': 'en',
      'merchants': merchants,
      'consent': {'provider': 'e2e-test-provider', 'v': 1},
    };
    final hash = llmBodyHash(LlmFeature.categorise, _install, jsonEncode(base));
    final proof = b64uNoPad(
      c.Hmac(c.sha256, base64.decode(proofKey)).convert(hash).bytes,
    );
    return {
      ...base,
      'attestation': {
        'type': 'dev',
        'proof': goodProof ? proof : proof.replaceFirst(RegExp('.'), '#'),
      },
    };
  }

  test(
    'install and sync answers parse; sync verifies under the dev key',
    () async {
      final (s1, b1, _) = await call('/v1/installs', {'installId': _install});
      expect(s1, 201);
      expect(InstallResponse.fromJson(b1).installToken, hasLength(43));

      final req = await http.postUrl(fake.baseUri.replace(path: '/v1/sync'));
      req.write(jsonEncode({'catalogVersion': 0, 'flagsVersion': 0}));
      final res = await req.close();
      final bytes = Uint8List.fromList(
        await res.fold<List<int>>([], (a, b) => a..addAll(b)),
      );
      expect(res.statusCode, 200);
      ResponseSignatureVerifier(
        [pinned],
        allowDevKeys: true,
      ).verify(bytes, res.headers.value('zaghlol-signature'));
      final sync = SyncResponse.fromJson(jsonDecode(utf8.decode(bytes)));
      expect(sync.flags!.values['llm_categorise'], isTrue);
      expect(sync.config!.values['llm.provider'], 'e2e-test-provider');
      expect(sync.config!.providerName!.en, 'Test Provider');
      expect(sync.config!.providerName!.ar, isNotEmpty);
      expect(fake.syncs, hasLength(1));
    },
  );

  test(
    'categorise: every contract result status, shaped as the fixture',
    () async {
      final fixture = jsonDecode(
        File('../backend/contracts/fixtures/categorise-responses-v1.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      for (final f in (fixture['ok']! as List).cast<Map<String, Object?>>()) {
        final want = (f['body']! as Map).cast<String, Object?>();
        final results = (want['results']! as List).cast<Map<String, Object?>>();
        fake.answers.clear();
        for (final r in results) {
          final status = r['status']! as String;
          final category = r['category'] as String?;
          final source = r['source'] as String?;
          fake.answers[r['merchant']! as String] = switch ((status, source)) {
            ('ok', 'llm') => CatAnswer.llm(
              category!,
              confidence: r['confidence']! as int,
            ),
            ('ok', 'cache') => CatAnswer.cache(
              category!,
              confidence: r['confidence']! as int,
            ),
            ('quota', _) => const CatAnswer.quota(),
            ('unknown', _) => const CatAnswer.noAnswer(),
            _ => const CatAnswer.noAnswer(),
          };
        }
        final merchants = [for (final r in results) r['merchant']! as String];
        final (code, got, _) = await call(
          '/v1/categorise',
          categoriseBody(merchants),
          installId: _install,
        );
        expect(code, 200, reason: f['name']! as String);
        CategoriseResponse.fromJson(got); // parses with the app's model
        expect(
          got.keys.toSet(),
          want.keys.toSet(),
          reason: '${f['name']} members',
        );
        // Only the statuses the device flow uses are compared result by result
        // (the others are served as "no answer" here).
        for (final r in results) {
          final status = r['status']! as String;
          if (status == 'ok' && r['source'] != 'catalog' || status == 'quota') {
            final mine = (got['results']! as List)
                .cast<Map<String, Object?>>()
                .firstWhere((m) => m['merchant'] == r['merchant']);
            expect(mine, r, reason: '${f['name']} result');
          }
        }
        expect(
          (got['quota']! as Map).keys.toSet(),
          (want['quota']! as Map).keys.toSet(),
        );
      }
    },
  );

  test(
    'scripted problems match the fixture bodies; a bad proof is 422',
    () async {
      final fixture = jsonDecode(
        File('../backend/contracts/fixtures/categorise-responses-v1.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      final problems = {
        for (final p
            in (fixture['problems']! as List).cast<Map<String, Object?>>())
          p['code']! as String: p,
      };
      for (final p in [
        CatProblem.consentRequired,
        CatProblem.servicePaused,
        CatProblem.attestationFailed,
      ]) {
        fake.nextProblem = p;
        final (code, got, res) = await call(
          '/v1/categorise',
          categoriseBody(['quiblexo']),
          installId: _install,
        );
        final want = problems[p.code]!;
        expect(code, want['status']);
        expect(got, want['body']);
        expect(res.headers.contentType?.subType, 'problem+json');
      }
      final (code, got, _) = await call(
        '/v1/categorise',
        categoriseBody(['quiblexo'], goodProof: false),
        installId: _install,
      );
      expect(code, 422);
      expect(got['code'], 'DEVICE_ATTESTATION_FAILED');
      expect(fake.categorise.last.attestationOk, isFalse);
      expect(fake.categorise.first.attestationOk, isTrue);
    },
  );
}
