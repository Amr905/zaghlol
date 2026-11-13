// T-141: fakes for BackendClient tests. Synthetic keys and tokens only.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:zaghlol/core/backend/backend_state.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/backend/transport.dart';
import 'package:zaghlol_catalog/zaghlol_catalog.dart' show SeedSigner;

final ECDomainParameters _p256 = ECDomainParameters('prime256v1');

Uint8List _bytes(BigInt v) {
  final out = Uint8List(32);
  var rest = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest = rest >> 8;
  }
  return out;
}

/// A throwaway P-256 key pair that signs like the backend (T-123 header form).
final class TestSigningKey {
  factory TestSigningKey(String kid, {int seed = 1}) {
    final rng = Random(seed);
    var d = BigInt.zero;
    for (var i = 0; i < 32; i++) {
      d = (d << 8) | BigInt.from(rng.nextInt(256));
    }
    d = d % (_p256.n - BigInt.one) + BigInt.one;
    final q = (_p256.G * d)!;
    return TestSigningKey._(
      kid,
      SeedSigner(kid: kid, d: _bytes(d)),
      ResponseKey(
        kid: kid,
        x: _bytes(q.x!.toBigInteger()!),
        y: _bytes(q.y!.toBigInteger()!),
      ),
    );
  }

  TestSigningKey._(this.kid, this._signer, this.publicKey);

  final String kid;
  final SeedSigner _signer;
  final ResponseKey publicKey;

  String sign(Uint8List body) => _signer.sign(body);
}

/// An in-memory [BackendStateStore] that appends every mutation to [log].
final class FakeBackendStore implements BackendStateStore {
  FakeBackendStore(this.log);

  final List<String> log;
  final Map<String, Uint8List> values = {};

  String? text(String key) {
    final v = values[key];
    return v == null ? null : utf8.decode(v);
  }

  @override
  Future<Uint8List?> read(String key) async {
    final v = values[key];
    return v == null ? null : Uint8List.fromList(v);
  }

  @override
  Future<void> write(String key, Uint8List value) async {
    log.add('write $key');
    values[key] = Uint8List.fromList(value);
  }

  @override
  Future<bool> compareAndSet(
    String key, {
    required Uint8List? expected,
    required Uint8List next,
  }) async {
    final cur = values[key];
    final same = expected == null
        ? cur == null
        : cur != null && _eq(cur, expected);
    if (!same) return false;
    log.add('write $key');
    values[key] = Uint8List.fromList(next);
    return true;
  }

  @override
  Future<void> delete(String key) async {
    if (values.remove(key) != null) log.add('delete $key');
  }

  @override
  Future<bool> deleteIfEquals(String key, Uint8List expected) async {
    final cur = values[key];
    if (cur == null || !_eq(cur, expected)) return false;
    values.remove(key);
    log.add('delete $key');
    return true;
  }
}

bool _eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

typedef Handler = Future<BackendResponse> Function(BackendRequest request);

/// A scripted server: each request goes to [handler] and is appended to
/// [requests] and to the shared [log] (`send <METHOD> <path>`).
final class FakeTransport implements BackendTransport {
  FakeTransport(this.log, this.handler);

  final List<String> log;
  Handler handler;
  final List<BackendRequest> requests = [];

  @override
  Future<BackendResponse> send(BackendRequest request) {
    log.add('send ${request.method} ${request.uri.path}');
    requests.add(request);
    return handler(request);
  }
}

BackendResponse jsonResponse(
  int status,
  Object body, {
  TestSigningKey? signWith,
  String? signatureHeader,
}) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
  final sig = signatureHeader ?? signWith?.sign(bytes);
  return BackendResponse(
    status: status,
    headers: {
      'content-type': [
        status >= 400 ? 'application/problem+json' : 'application/json',
      ],
      if (sig != null) 'zaghlol-signature': [sig],
    },
    body: bytes,
  );
}

BackendResponse problem(int status, String code, {int? retryAfter}) =>
    jsonResponse(status, {
      'type': 'about:blank',
      'title': 'x',
      'status': status,
      'code': code,
      // ignore: use_null_aware_elements
      if (retryAfter != null) 'retryAfterSeconds': retryAfter,
    });

/// A synthetic 43-char install token.
String fakeToken(int n) => base64Url
    .encode(List<int>.generate(32, (i) => (i * 7 + n) & 0xff))
    .replaceAll('=', '');

Map<String, Object?> bodyJson(BackendRequest r) =>
    jsonDecode(utf8.decode(r.body!)) as Map<String, Object?>;

/// A [Random] that replays [bytes] for `nextInt(256)` and counts calls.
final class ScriptedRandom implements Random {
  ScriptedRandom(this.bytes);

  final List<int> bytes;
  int calls = 0;

  @override
  int nextInt(int max) {
    final v = bytes[calls % bytes.length] % max;
    calls++;
    return v;
  }

  @override
  bool nextBool() => throw UnsupportedError('unused');

  @override
  double nextDouble() => throw UnsupportedError('unused');
}
