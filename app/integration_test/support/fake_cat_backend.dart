// T-363: a fake Zaghlol backend that runs inside a device test (loopback
// HTTP). It serves what the automatic-category flow needs and records every
// request it gets:
//   POST /v1/installs   -> 201 with a synthetic install token
//   POST /v1/sync       -> 200, signed with the run's dev signing key, with
//                          the flag `llm_categorise` ON and the signed
//                          `config` block (llm.provider + providerName)
//   POST /v1/categorise -> 200 per [answers] (ok/llm, ok/cache, unknown =
//                          "no answer", quota) or a scripted problem body
//                          (409, 503, ...). The attestation proof is
//                          verified exactly as the backend's Fake mode does
//                          (HMAC of the body binding with the run's key).
// Everything else answers 404.
//
// Shapes follow backend/contracts/fixtures/categorise-responses-v1.json; a
// host test (test/integration_support/fake_cat_backend_test.dart) pins them.
// No key literal lives here: the signing scalar and the proof key arrive as
// run-time values the CI script generates. Request bodies are kept for the
// test's assertions and are never printed. Synthetic data only.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:zaghlol/core/llm/llm_attestation.dart'
    show b64uNoPad, llmBodyHash;
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol_catalog/zaghlol_catalog.dart' show SeedSigner;

/// One answer of the fake for one merchant.
final class CatAnswer {
  const CatAnswer._(this.status, this.category, this.confidence, this.source);

  /// `ok` from the model.
  const CatAnswer.llm(String category, {int confidence = 88})
    : this._('ok', category, confidence, 'llm');

  /// `ok` from the server's cache.
  const CatAnswer.cache(String category, {int confidence = 90})
    : this._('ok', category, confidence, 'cache');

  /// "No answer": the server could not tell (wire status `unknown`).
  const CatAnswer.noAnswer() : this._('unknown', null, null, null);

  /// The monthly allowance is used up for this merchant.
  const CatAnswer.quota() : this._('quota', null, null, null);

  final String status;
  final String? category;
  final int? confidence;
  final String? source;

  Map<String, Object?> toResult(String merchant) => {
    'merchant': merchant,
    'status': status,
    'category': category,
    'confidence': confidence,
    'source': source,
  };
}

/// A problem answer (`application/problem+json`), shaped as in the contract
/// fixture's `problems`.
final class CatProblem {
  const CatProblem(this.status, this.code, this.slug, this.title, [this.extra]);

  final int status;
  final String code;
  final String slug;
  final String title;
  final Map<String, Object?>? extra;

  Map<String, Object?> toBody() => {
    'type': 'https://zaghlol.app/problems/$slug',
    'title': title,
    'status': status,
    'code': code,
    ...?extra,
  };

  static const consentRequired = CatProblem(
    409,
    'LLM_CONSENT_REQUIRED',
    'llm-consent-required',
    'Consent for the active provider is required.',
    {'providerId': 'openai-luna'},
  );
  static const servicePaused = CatProblem(
    503,
    'LLM_SERVICE_PAUSED',
    'llm-service-paused',
    'The helper is paused.',
  );
  static const attestationFailed = CatProblem(
    422,
    'DEVICE_ATTESTATION_FAILED',
    'device-attestation-failed',
    'Device attestation failed.',
  );
}

/// One recorded request: no header values, only what the assertions need.
final class RecordedRequest {
  RecordedRequest(this.method, this.path, this.bodyText, this.json);

  final String method;
  final String path;

  /// The raw body text (synthetic data in the tests; never printed).
  final String? bodyText;
  final Map<String, Object?>? json;

  /// Set for `/v1/categorise`: the proof verified against the binding.
  bool? attestationOk;

  @override
  String toString() => 'RecordedRequest($method $path)';
}

final class FakeCatBackend {
  FakeCatBackend._(this._server, this._cfg);

  final HttpServer _server;
  final _Config _cfg;
  final List<RecordedRequest> requests = [];
  final StreamController<void> _changed = StreamController.broadcast();

  /// Per merchant answers; a merchant not in the map gets "no answer".
  final Map<String, CatAnswer> answers = {};

  /// When set, the next `/v1/categorise` answers with this problem (once).
  CatProblem? nextProblem;

  /// The monthly allowance reported in every answer.
  int limit = 15;
  int used = 0;

  Uri get baseUri => Uri.parse('http://127.0.0.1:${_server.port}');
  List<RecordedRequest> get categorise => [
    for (final r in requests)
      if (r.path == '/v1/categorise') r,
  ];
  List<RecordedRequest> get syncs => [
    for (final r in requests)
      if (r.path == '/v1/sync') r,
  ];

  /// Binds [port] on the loopback interface.
  ///
  /// [signingScalarB64Url] is the 32-byte private scalar (base64url) of the
  /// dev signing key [kid] whose public half the app pins; [proofKeyB64] is
  /// the standard-base64 proof key the app was built with (empty: the proof
  /// is not verified).
  static Future<FakeCatBackend> start({
    required int port,
    required String kid,
    required String signingScalarB64Url,
    required String proofKeyB64,
    required String providerId,
    required String providerNameAr,
    required String providerNameEn,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final f = FakeCatBackend._(
      server,
      _Config(
        SeedSigner(
          kid: kid,
          d: Uint8List.fromList(
            base64Url.decode(base64Url.normalize(signingScalarB64Url)),
          ),
        ),
        proofKeyB64.trim().isEmpty
            ? null
            : Uint8List.fromList(base64.decode(proofKeyB64.trim())),
        providerId,
        providerNameAr,
        providerNameEn,
      ),
    );
    unawaited(f._serve());
    return f;
  }

  Future<void> stop() async {
    await _server.close(force: true);
    await _changed.close();
  }

  /// Completes when [test] holds, polling on every request and every 200 ms.
  Future<bool> until(
    bool Function() test, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (test()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return test();
  }

  Future<void> _serve() async {
    await for (final req in _server) {
      try {
        await _handle(req);
      } on Object {
        try {
          req.response.statusCode = 500;
          await req.response.close();
        } on Object {
          // The client went away.
        }
      }
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final bytes = BytesBuilder();
    await for (final chunk in req) {
      bytes.add(chunk);
    }
    final raw = bytes.isEmpty ? null : utf8.decode(bytes.takeBytes());
    Map<String, Object?>? json;
    if (raw != null) {
      try {
        final v = jsonDecode(raw);
        if (v is Map<String, Object?>) json = v;
      } on FormatException {
        // Recorded as text only.
      }
    }
    final path = req.uri.path;
    final rec = RecordedRequest(req.method, path, raw, json);
    requests.add(rec);
    _changed.add(null);

    switch ((req.method, path)) {
      case ('POST', '/v1/installs'):
        await _reply(req, 201, {
          'installToken': _token(),
          'serverTime': _now(),
        });
      case ('POST', '/v1/sync'):
        await _sync(req, json);
      case ('POST', '/v1/categorise'):
        await _categorise(req, rec, raw, json);
      default:
        await _reply(req, 404, {
          'type': 'about:blank',
          'title': 'Not found',
          'status': 404,
          'code': 'NOT_FOUND',
        }, problem: true);
    }
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// 43 base64url characters, the install token's shape.
  static String _token() => base64Url
      .encode(List<int>.generate(32, (i) => (i * 11 + 5) & 0xff))
      .replaceAll('=', '');

  Future<void> _sync(HttpRequest req, Map<String, Object?>? asked) async {
    final cfgVersion = asked?['configVersion'];
    final flagsVersion = asked?['flagsVersion'];
    final upToDate = cfgVersion == 1 && flagsVersion == 1;
    final next = DateTime.now().toUtc().add(const Duration(hours: 6));
    await _reply(req, 200, {
      'serverTime': _now(),
      'nextSyncNotBefore': next.toIso8601String(),
      if (!upToDate) ...{
        'flags': {
          'version': 1,
          'values': {'llm_categorise': true},
        },
        'config': {
          'version': 1,
          'values': {'llm.provider': _cfg.providerId},
          'providerName': {'ar': _cfg.nameAr, 'en': _cfg.nameEn},
        },
      },
    }, sign: true);
  }

  Future<void> _categorise(
    HttpRequest req,
    RecordedRequest rec,
    String? raw,
    Map<String, Object?>? json,
  ) async {
    final installId = req.headers.value('zaghlol-install') ?? '';
    rec.attestationOk = _proofOk(installId, raw, json);
    final scripted = nextProblem;
    if (scripted != null) {
      nextProblem = null;
      await _reply(req, scripted.status, scripted.toBody(), problem: true);
      return;
    }
    if (rec.attestationOk != true) {
      await _reply(
        req,
        CatProblem.attestationFailed.status,
        CatProblem.attestationFailed.toBody(),
        problem: true,
      );
      return;
    }
    final merchants = (json?['merchants'] as List?)?.cast<String>() ?? [];
    final results = [
      for (final m in merchants)
        (answers[m] ?? const CatAnswer.noAnswer()).toResult(m),
    ];
    final counted = [
      for (final m in merchants)
        if (answers[m]?.source == 'llm') m,
    ].length;
    used += counted;
    await _reply(req, 200, {
      'serverTime': _now(),
      'counted': counted,
      'results': results,
      'quota': {
        'limit': limit,
        'used': used,
        'remaining': limit - used,
        'resetsAt': DateTime.now()
            .toUtc()
            .add(const Duration(days: 30))
            .toIso8601String(),
      },
    });
  }

  /// The Fake attestation mode of the backend: `{type: dev, proof}` with
  /// proof = b64url(HMAC-SHA256(key, bodyHash)).
  bool _proofOk(String installId, String? raw, Map<String, Object?>? json) {
    final att = json?['attestation'];
    if (att is! Map || att['type'] != 'dev' || att['proof'] is! String) {
      return false;
    }
    final key = _cfg.proofKey;
    if (key == null || raw == null) return true; // not verified in this run
    try {
      final hash = llmBodyHash(LlmFeature.categorise, installId, raw);
      final want = b64uNoPad(c.Hmac(c.sha256, key).convert(hash).bytes);
      return want == att['proof'];
    } on Object {
      return false;
    }
  }

  Future<void> _reply(
    HttpRequest req,
    int status,
    Map<String, Object?> body, {
    bool sign = false,
    bool problem = false,
  }) async {
    final out = Uint8List.fromList(utf8.encode(jsonEncode(body)));
    final res = req.response
      ..statusCode = status
      ..headers.contentType = ContentType(
        'application',
        problem ? 'problem+json' : 'json',
        charset: 'utf-8',
      );
    if (sign) res.headers.set('zaghlol-signature', _cfg.signer.sign(out));
    res.add(out);
    await res.close();
  }
}

final class _Config {
  _Config(
    this.signer,
    this.proofKey,
    this.providerId,
    this.nameAr,
    this.nameEn,
  );
  final SeedSigner signer;
  final Uint8List? proofKey;
  final String providerId;
  final String nameAr;
  final String nameEn;
}
