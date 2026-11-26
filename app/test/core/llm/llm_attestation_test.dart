// T-340 AC1 (negative proof 1) and AC2 (negative proof 2): the ask and
// categorise binding vectors (T-322) reproduced byte-exactly, the platform
// prover passes exactly those hashes to the attestation channel, and the dev
// proof can't exist outside a debug build. Synthetic values only.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as c;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/llm/llm_attestation.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol/core/platform/pigeon_attestation.dart';

import '../../features/gold/application/gold_test_support.dart'
    show FakeAttestHost;

const _rel = 'backend/tests/Zaghlol.Contract.Tests/vectors';

Map<String, dynamic> _vectors(String name) {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final f = File('${dir.path}/$_rel/$name');
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  fail('shared vector file $name not found');
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  const files = {
    LlmFeature.ask: 'ask-binding-v1.json',
    LlmFeature.categorise: 'cat-binding-v1.json',
  };

  group('AC1 binding vectors', () {
    for (final e in files.entries) {
      final feature = e.key;
      final v = _vectors(e.value);
      test('${feature.name}: prefixes match the vector file', () {
        expect(feature.bindingPrefix, v['prefix']);
        expect(feature.clientDataPrefix, v['clientDataPrefix']);
      });
      for (final c in (v['valid'] as List).cast<Map<String, dynamic>>()) {
        test('${feature.name} ${c['name']}: JCS, bodyHash, requestHash and '
            'clientDataHash are byte-exact', () {
          final body = c['body'] as Map<String, dynamic>;
          final jcs = llmCanonicalBody(body);
          expect(jcs, c['jcs']);
          expect(_hex(utf8.encode(jcs)), c['jcsHex']);
          // Hashing the full body (with attestation) and the body without it
          // gives the same bodyHash: the proof is never bound to itself.
          final h = llmBodyHash(
            feature,
            c['installId'] as String,
            jsonEncode(body),
          );
          final stripped = Map<String, dynamic>.of(body)..remove('attestation');
          expect(
            llmBodyHash(
              feature,
              c['installId'] as String,
              jsonEncode(stripped),
            ),
            h,
          );
          expect(_hex(h), c['bodyHashHex']);
          expect(b64uNoPad(h), c['requestHashB64u']);
          expect(_hex(llmClientDataHash(feature, h)), c['clientDataHashHex']);
        });
      }
    }

    test('the two features never share a hash for the same body', () {
      final c0 =
          (_vectors(files[LlmFeature.ask]!)['valid'] as List).first
              as Map<String, dynamic>;
      final id = c0['installId'] as String;
      final raw = jsonEncode(c0['body']);
      expect(
        llmBodyHash(LlmFeature.ask, id, raw),
        isNot(llmBodyHash(LlmFeature.categorise, id, raw)),
      );
    });

    test('a bad install ID, duplicate member or lone surrogate is refused', () {
      expect(
        () => llmBodyHash(LlmFeature.ask, 'not-a-uuid', '{}'),
        throwsA(isA<BindingException>()),
      );
      const id = '0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e78';
      expect(
        () => llmBodyHash(LlmFeature.ask, id, '{"q":"a","q":"b"}'),
        throwsA(isA<BindingException>()),
      );
      expect(
        () => llmBodyHash(LlmFeature.ask, id, '{"q":"\\ud800"}'),
        throwsA(isA<BindingException>()),
      );
    });
  });

  group('platform prover', () {
    final v = _vectors(files[LlmFeature.ask]!);
    final c0 = (v['valid'] as List).first as Map<String, dynamic>;
    final hash = Uint8List.fromList(
      llmBodyHash(
        LlmFeature.ask,
        c0['installId'] as String,
        jsonEncode(c0['body']),
      ),
    );

    test('Android: prepares once, attests exactly bodyHash, returns a Play '
        'Integrity proof', () async {
      final host = FakeAttestHost();
      final p = PlatformLlmProver(
        PigeonAttestation(api: host),
        ClientPlatform.android,
      );
      final a = await p.prove(LlmFeature.ask, hash);
      await p.prove(LlmFeature.ask, hash);
      expect(a, isA<LlmPlayIntegrityProof>());
      expect(host.calls, ['prepare', 'attest', 'attest']);
      expect(host.hashes.first, hash);
    });

    test('iOS: attests the clientDataHash, passes forceNewKey, maps the '
        'attestation object', () async {
      final host = FakeAttestHost()..type = 'app_attest';
      final p = PlatformLlmProver(
        PigeonAttestation(api: host),
        ClientPlatform.ios,
      );
      final a = await p.prove(LlmFeature.ask, hash, forceNewKey: true);
      expect(_hex(host.hashes.single), c0['clientDataHashHex']);
      expect(host.forced.single, isTrue);
      expect(a, isA<LlmAppAttestProof>());
      expect((a as LlmAppAttestProof).attestationObject, isNotNull);
    });

    test('a proof of the other platform\'s type fails closed', () async {
      final host = FakeAttestHost()..type = 'app_attest';
      final p = PlatformLlmProver(
        PigeonAttestation(api: host),
        ClientPlatform.android,
      );
      await expectLater(
        p.prove(LlmFeature.ask, hash),
        throwsA(isA<AttestationException>()),
      );
    });

    test('native errors arrive as code-only AttestationException', () async {
      final host = FakeAttestHost()
        ..attestErrors.add(PlatformException(code: 'ATTEST_TRANSIENT'));
      final p = PlatformLlmProver(
        PigeonAttestation(api: host),
        ClientPlatform.android,
      );
      await expectLater(
        p.prove(LlmFeature.ask, hash),
        throwsA(
          isA<AttestationException>().having(
            (e) => e.failure,
            'failure',
            AttestationFailure.transient,
          ),
        ),
      );
    });
  });

  group('AC2 dev proof is debug-only', () {
    final hash = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('debug: HMAC-SHA256 of bodyHash, unpadded base64url, fits the '
        'OpenAPI pattern', () async {
      final p = DevLlmProver('synthetic-dev-key', mode: BuildMode.debug);
      final a = await p.prove(LlmFeature.ask, hash) as LlmDevProof;
      final want = b64uNoPad(
        c.Hmac(c.sha256, utf8.encode('synthetic-dev-key')).convert(hash).bytes,
      );
      expect(a.proof, want);
      expect(a.toJson(), {'type': 'dev', 'proof': want});
    });

    test('negative proof 2: release and profile builds cannot make one, and '
        'the selector never picks it there', () {
      for (final mode in [BuildMode.release, BuildMode.profile]) {
        expect(
          () => DevLlmProver('synthetic-dev-key', mode: mode),
          throwsStateError,
        );
        expect(
          selectLlmProver(
            attestation: PigeonAttestation(api: FakeAttestHost()),
            platform: ClientPlatform.android,
            mode: mode,
            devKey: 'synthetic-dev-key',
          ),
          isA<PlatformLlmProver>(),
        );
      }
      expect(() => DevLlmProver('', mode: BuildMode.debug), throwsStateError);
      expect(
        selectLlmProver(
          attestation: PigeonAttestation(api: FakeAttestHost()),
          platform: ClientPlatform.ios,
          mode: BuildMode.debug,
          devKey: '',
        ),
        isA<PlatformLlmProver>(),
      );
    });

    test('no dev key is bundled: the only read of the define is gated by '
        'kReleaseMode, and no other file names it', () {
      final lib = Directory('lib');
      final hits = <String>[];
      for (final f in lib.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = f.readAsStringSync();
        if (s.contains('ZAGHLOL_LLM_DEV_KEY')) hits.add(f.path);
      }
      expect(hits, [endsWith('llm_attestation.dart')]);
      final src = File(hits.single)
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(
        src,
        contains(
          "const String llmDevKeyDefine = kReleaseMode ? '' : "
          "String.fromEnvironment('ZAGHLOL_LLM_DEV_KEY');",
        ),
      );
      // In this (debug/test) build the define is unset: empty.
      expect(llmDevKeyDefine, isEmpty);
    });
  });
}
