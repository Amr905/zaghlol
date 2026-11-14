// T-171: a scripted Zaghlol backend for the privacy contract test. It answers
// every app operation with a well-formed (and, where the contract says so,
// signed) body, so the app's real flows run to completion through the real
// BackendClient. All tokens and keys are synthetic.

import 'dart:convert';
import 'dart:typed_data';

import 'package:zaghlol/core/backend/transport.dart';

import '../../core/backend/backend_test_support.dart';

String isoMs(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

final class FakeZaghlolServer implements BackendTransport {
  FakeZaghlolServer({
    required this.nowMs,
    required this.entitlementToken,
    required this.accountToken,
  });

  /// The server clock (epoch ms).
  final int Function() nowMs;

  /// A signed entitlement JWS for [installId].
  final String Function(String installId) entitlementToken;

  /// A signed account JWS bound to [installId].
  final String Function(String installId) accountToken;

  /// Signs response bodies (the pinned `s` key of the client under test).
  final TestSigningKey responseKey = TestSigningKey('s2026a', seed: 3);

  /// Install IDs registered so far.
  final List<String> installs = [];
  int _tokens = 0;

  /// Operations answered with a problem instead (`METHOD path` → status).
  final Map<String, int> failWith = {};

  String get lastInstall => installs.last;

  @override
  Future<BackendResponse> send(BackendRequest r) async {
    final op = '${r.method} ${r.uri.path}';
    final fail = failWith[op];
    if (fail != null) return problem(fail, 'SERVICE_UNAVAILABLE');
    final nonce = r.headers['zaghlol-time-nonce'];
    final now = isoMs(nowMs());
    final iid = r.headers['zaghlol-install'];
    Map<String, Object?> ent() => {'token': entitlementToken(iid!)};

    BackendResponse signed(Map<String, Object?> body) =>
        jsonResponse(200, body, signWith: responseKey);

    switch (op) {
      case 'POST /v1/installs':
        final body = jsonDecode(utf8.decode(r.body!)) as Map<String, Object?>;
        installs.add(body['installId']! as String);
        return jsonResponse(201, {
          'installToken': fakeToken(++_tokens),
          'serverTime': now,
        });
      case 'DELETE /v1/installs/me':
        return BackendResponse(status: 202, headers: {}, body: Uint8List(0));
      case 'DELETE /v1/accounts/me':
        return BackendResponse(status: 204, headers: {}, body: Uint8List(0));
      case 'POST /v1/sync':
        return signed({
          'serverTime': now,
          'nextSyncNotBefore': isoMs(nowMs() + 24 * 3600 * 1000),
          'accepted': {'contributions': 0, 'bankRequests': 0},
          'timeNonce': nonce,
        });
      case 'POST /v1/purchases/verify':
        return signed({
          'status': 'active',
          'entitlement': ent(),
          'serverTime': now,
          'timeNonce': nonce,
        });
      case 'POST /v1/purchases/restore':
        return signed({
          'status': 'active',
          'restoredCount': 1,
          'entitlement': ent(),
          'serverTime': now,
          'timeNonce': nonce,
        });
      case 'GET /v1/entitlement':
      case 'POST /v1/accounts/signout':
        return signed({
          'entitlement': ent(),
          'serverTime': now,
          'timeNonce': nonce,
        });
      case 'POST /v1/accounts/signin':
        return signed({
          'accountId': 'acct-synthetic-1',
          'accountToken': accountToken(iid!),
          'entitlement': ent(),
          'linkedInstalls': 1,
          'serverTime': now,
          'timeNonce': nonce,
        });
    }
    return problem(404, 'NOT_FOUND');
  }
}
