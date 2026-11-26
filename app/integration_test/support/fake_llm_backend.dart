// T-348: an in-process fake of the Zaghlol backend for the online-helper
// device test. A real `HttpServer` on the device's loopback; the app reaches
// it through `--dart-define=ZAGHLOL_API_BASE=http://127.0.0.1:<port>`.
//
// It serves what the helper needs and nothing else:
//   POST /v1/installs   an install token (not signed)
//   POST /v1/sync       a SIGNED answer with the flags block (`ask_llm` on)
//                       and the signed `config` block of the fixture
//                       `app/test/fixtures/llm/sync-config-provider-v1.json`
//   POST /v1/ask/plan   the next scripted reply, built from the fixture
//                       `backend/contracts/fixtures/ask-plan-responses-v1.json`
//   anything else       404 problem (the app treats it as "not available")
//
// The signing key is a throwaway made by the CI script at run time (the
// public half is pinned in the app build, the private scalar goes to this
// test); no key is committed. Requests are recorded: method, path, body
// text. Question text is never printed; callers read `requests` and assert.
// The dev proof of the attestation is verified like the backend's Fake mode
// does (HMAC of the body hash), so a wrong proof is a 422 and the test fails.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:zaghlol/core/llm/llm_attestation.dart'
    show b64uNoPad, llmBodyHash;
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol_catalog/zaghlol_catalog.dart' show SeedSigner;

/// One recorded request. [body] is the raw text (empty for none).
final class RecordedRequest {
  RecordedRequest(this.method, this.path, this.body, this.headers);
  final String method;
  final String path;
  final String body;
  final Map<String, String> headers;

  Map<String, Object?> get json => jsonDecode(body) as Map<String, Object?>;
}

/// What the next `POST /v1/ask/plan` answers.
sealed class AskReply {
  const AskReply();

  /// A 200 with the fixture plan named [name] (`ok[].name`), counted.
  const factory AskReply.plan(String name) = _PlanReply;

  /// The fixture problem body for [code] (`problems[].code`).
  const factory AskReply.problem(String code) = _ProblemReply;

  /// The provider is switched on the server (the next sync carries the
  /// `switched` config block), and this call answers 409.
  const factory AskReply.providerSwitched409() = _SwitchReply;
}

final class _PlanReply extends AskReply {
  const _PlanReply(this.name);
  final String name;
}

final class _ProblemReply extends AskReply {
  const _ProblemReply(this.code);
  final String code;
}

final class _SwitchReply extends AskReply {
  const _SwitchReply();
}

final class FakeLlmBackend {
  FakeLlmBackend._(
    this._server,
    this._signer,
    this._devProofKey,
    this._plans,
    this._problems,
    this._configs,
  );

  /// [signKeyD] is the base64url 32-byte private scalar of the pinned dev key
  /// `s0000a`; [devProofKey] the standard-base64 attestation key; the three
  /// fixture texts are the JSON files' contents.
  static Future<FakeLlmBackend> start({
    required int port,
    required String signKeyD,
    required String devProofKey,
    required String askPlanFixture,
    required String syncConfigFixture,
  }) async {
    final d = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(signKeyD)),
    );
    final fx = jsonDecode(askPlanFixture) as Map<String, Object?>;
    final plans = <String, Map<String, Object?>>{
      for (final o in fx['ok']! as List)
        (o as Map<String, Object?>)['name']! as String: (o['body']! as Map)
            .cast<String, Object?>(),
    };
    final problems = <String, ({int status, Map<String, Object?> body})>{
      for (final o in fx['problems']! as List)
        (o as Map<String, Object?>)['code']! as String: (
          status: o['status']! as int,
          body: (o['body']! as Map).cast<String, Object?>(),
        ),
    };
    final blocks =
        (jsonDecode(syncConfigFixture) as Map<String, Object?>)['blocks']!
            as Map<String, Object?>;
    final configs = <String, Map<String, Object?>>{
      for (final e in blocks.entries)
        e.key: (e.value! as Map).cast<String, Object?>(),
    };
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final f = FakeLlmBackend._(
      server,
      SeedSigner(kid: 's0000a', d: d),
      devProofKey,
      plans,
      problems,
      configs,
    );
    f._port = server.port;
    unawaited(f._serve());
    return f;
  }

  HttpServer _server;
  final SeedSigner _signer;
  final String _devProofKey;
  final Map<String, Map<String, Object?>> _plans;
  final Map<String, ({int status, Map<String, Object?> body})> _problems;
  final Map<String, Map<String, Object?>> _configs;

  /// The bound port (for a server started on port 0).
  int get port => _port;
  late final int _port;

  final List<RecordedRequest> requests = [];
  final List<AskReply> _script = [];

  /// Which fixture config block the server serves now (`luna`, `switched`).
  String configVariant = 'luna';
  bool askLlmFlag = true;
  bool askLlmInvestFlag = true;

  /// The server's own quota for the ask feature.
  int quotaLimit = 5;
  int quotaUsed = 0;

  /// Dev-proof checks that passed / failed on `/v1/ask/plan`.
  int proofOk = 0;
  int proofBad = 0;
  int syncs = 0;

  String? _installToken;
  final Random _rng = Random.secure();

  List<RecordedRequest> get askRequests => [
    for (final r in requests)
      if (r.path == '/v1/ask/plan') r,
  ];

  /// Queues [replies] for the next ask calls, in order.
  void script(Iterable<AskReply> replies) => _script.addAll(replies);

  int get scriptLeft => _script.length;

  Future<void> close() => _server.close(force: true);

  /// Stops listening (a phone with no network: connections are refused).
  Future<void> goOffline() => _server.close(force: true);

  /// Listens again on the same port; recorded requests and the script stay.
  Future<void> goOnline() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
    unawaited(_serve());
  }

  // ---- server ---------------------------------------------------------------

  Future<void> _serve() async {
    final server = _server;
    await for (final req in server) {
      unawaited(_handle(req));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final bytes = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final body = utf8.decode(bytes);
      final headers = <String, String>{};
      req.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(','));
      final path = req.uri.path;
      requests.add(RecordedRequest(req.method, path, body, headers));
      if (req.method == 'POST' && path == '/v1/installs') {
        return await _installs(req);
      }
      if (req.method == 'POST' && path == '/v1/sync') {
        return await _sync(req);
      }
      if (req.method == 'POST' && path == '/v1/ask/plan') {
        return await _ask(req, body, headers);
      }
      return await _send(req, 404, _problem(404, 'NOT_FOUND'), problem: true);
    } on Object {
      try {
        await _send(req, 500, _problem(500, 'INTERNAL'), problem: true);
      } on Object {
        // The client went away.
      }
    }
  }

  Map<String, Object?> _problem(int status, String code) => {
    'type': 'about:blank',
    'title': 'x',
    'status': status,
    'code': code,
  };

  Future<void> _send(
    HttpRequest req,
    int status,
    Map<String, Object?> json, {
    bool sign = false,
    bool problem = false,
  }) async {
    final bytes = utf8.encode(jsonEncode(json));
    final res = req.response
      ..statusCode = status
      ..headers.set(
        'content-type',
        problem ? 'application/problem+json' : 'application/json',
      );
    if (sign) {
      res.headers.set(
        'zaghlol-signature',
        _signer.sign(Uint8List.fromList(bytes)),
      );
    }
    res.contentLength = bytes.length;
    res.add(bytes);
    await res.close();
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  Future<void> _installs(HttpRequest req) {
    final raw = List<int>.generate(32, (_) => _rng.nextInt(256));
    _installToken = base64Url.encode(raw).replaceAll('=', '');
    return _send(req, 201, {
      'installToken': _installToken,
      'serverTime': _now(),
    });
  }

  Future<void> _sync(HttpRequest req) {
    syncs++;
    final cfg = Map<String, Object?>.of(_configs[configVariant]!);
    return _send(req, 200, {
      'serverTime': _now(),
      'nextSyncNotBefore': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 24))
          .toIso8601String(),
      // Always sent, so every sync is a real one (not a "throttle").
      'flags': {
        'version': 1,
        'values': {'ask_llm': askLlmFlag, 'ask_llm_invest': askLlmInvestFlag},
      },
      'config': cfg,
    }, sign: true);
  }

  Map<String, Object?> _quota({int? used}) {
    final u = used ?? quotaUsed;
    return {
      'limit': quotaLimit,
      'used': u,
      'remaining': max(0, quotaLimit - u),
      'resetsAt': DateTime.now()
          .toUtc()
          .add(const Duration(days: 9))
          .toIso8601String()
          .replaceFirst(RegExp(r'\.\d+Z$'), 'Z'),
    };
  }

  Future<void> _ask(
    HttpRequest req,
    String body,
    Map<String, String> headers,
  ) async {
    // The dev proof, as the backend's Fake attestation mode checks it.
    final valid = _checkProof(body, headers['zaghlol-install']);
    if (!valid) {
      proofBad++;
      return _send(
        req,
        422,
        _problem(422, 'DEVICE_ATTESTATION_FAILED'),
        problem: true,
      );
    }
    proofOk++;
    if (_script.isEmpty) {
      return _send(req, 500, _problem(500, 'UNSCRIPTED'), problem: true);
    }
    final reply = _script.removeAt(0);
    switch (reply) {
      case _PlanReply(:final name):
        final base = Map<String, Object?>.of(_plans[name]!);
        quotaUsed++;
        base['serverTime'] = _now();
        base['counted'] = true;
        base['quota'] = _quota();
        return _send(req, 200, base);
      case _ProblemReply(:final code):
        final p = _problems[code]!;
        final b = Map<String, Object?>.of(p.body);
        if (b.containsKey('quota')) b['quota'] = _quota(used: quotaLimit);
        return _send(req, p.status, b, problem: true);
      case _SwitchReply():
        configVariant = 'switched';
        final p = _problems['LLM_CONSENT_REQUIRED']!;
        final b = Map<String, Object?>.of(p.body);
        b['providerId'] = _providerOf('switched');
        return _send(req, p.status, b, problem: true);
    }
  }

  String _providerOf(String variant) =>
      ((_configs[variant]!['values']! as Map)['llm.provider']!) as String;

  bool _checkProof(String body, String? installId) {
    try {
      if (installId == null) return false;
      final j = jsonDecode(body) as Map<String, Object?>;
      final att = j['attestation'];
      if (att is! Map || att['type'] != 'dev') return false;
      final hash = llmBodyHash(LlmFeature.ask, installId, body);
      final key = base64.decode(_devProofKey);
      final want = b64uNoPad(c.Hmac(c.sha256, key).convert(hash).bytes);
      return att['proof'] == want;
    } on Object {
      return false;
    }
  }
}
