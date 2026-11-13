// T-141: BackendClient, the only way the app talks to the backend
// (security-model §2, backend-api §1-§6).
//
// The data boundary (BR-SYNC-03) is built in:
// - Bodies are only ever built from the generated request DTOs
//   (generated/api_models.g.dart); there is no "send a map" API.
// - Headers are fixed by the generated operation table: `Zaghlol-App`,
//   `Zaghlol-Install` and the install token on install-scoped calls, the
//   account token only where the contract allows it, `Idempotency-Key` only
//   on the three idempotent operations, `Zaghlol-Time-Nonce` only on the six
//   anchoring ones. No `Accept-Language`.
// - iOS-only request members (`seatKeys`, App Attest proofs) can't leave an
//   Android build, and Android variants can't leave an iOS build.
// - Every 2xx of a signed operation is verified (response_signature.dart)
//   before a byte of it is decoded; unsigned or invalid bodies are dropped.
//
// Nothing here logs a body, header, token, key, nonce or URL. Diagnostics are
// registry codes plus the HTTP status (core/logging).

// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../db/daos/misc_daos.dart' show DiagLevel;
import '../logging/diag_code.dart';
import '../logging/diag_event.dart';
import '../logging/diag_field.dart';
import '../logging/diag_logger.dart';
import 'backend_failure.dart';
import 'backend_state.dart';
import 'generated/api_models.g.dart';
import 'ids.dart';
import 'response_signature.dart';
import 'transport.dart';

export 'backend_failure.dart';
export 'generated/api_models.g.dart';
export 'ids.dart' show IdempotencyKey, TimeNonce;

enum ClientPlatform { android, ios }

/// What the app says about itself (`Zaghlol-App`, `POST /v1/installs`):
/// platform and app version only (BR-SYNC-03).
final class ClientIdentity {
  /// Throws [ArgumentError] when the header would break the contract.
  ClientIdentity({
    required this.platform,
    required this.appVersion,
    required this.build,
  }) {
    final h = header;
    if (h.length > 64 ||
        !_appHeader.hasMatch(h) ||
        !_version.hasMatch(appVersion)) {
      throw ArgumentError('bad client identity');
    }
  }

  static final RegExp _appHeader = RegExp(r'^(android|ios)/\S+ \(\S+\)$');
  static final RegExp _version = RegExp(
    r'^\d{1,4}\.\d{1,4}\.\d{1,4}([-+][0-9A-Za-z.-]{1,32})?$',
  );

  final ClientPlatform platform;
  final String appVersion;
  final String build;

  String get header => '${platform.name}/$appVersion ($build)';
}

/// Where the backend is and which keys sign its answers.
final class BackendConfig {
  /// [baseUri] must be HTTPS, except a loopback/emulator host when
  /// [allowInsecureLocalhost] (debug builds against the local backend).
  BackendConfig({
    required this.baseUri,
    required this.verifier,
    bool allowInsecureLocalhost = false,
  }) {
    final local = const {'localhost', '127.0.0.1', '10.0.2.2'};
    final ok =
        baseUri.scheme == 'https' ||
        (allowInsecureLocalhost &&
            baseUri.scheme == 'http' &&
            local.contains(baseUri.host));
    if (!ok ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        baseUri.userInfo.isNotEmpty) {
      throw ArgumentError('bad base URI');
    }
  }

  final Uri baseUri;
  final ResponseSignatureVerifier verifier;
}

/// Events other modules react to.
sealed class BackendEvent {
  const BackendEvent();
}

/// R5-1: the server refused the install token, so the cached entitlement and
/// account tokens were deleted and a new install ID was registered. Local
/// data is kept. Consumers: T-144 (trusted state), T-179 ("own seat key
/// unusable" goes with the old install ID).
final class InstallReregistered extends BackendEvent {
  const InstallReregistered();
  @override
  String toString() => 'InstallReregistered';
}

/// A request body bound to its `Idempotency-Key` and operation (R3-6). Built
/// only by [BackendClient.prepareVerify] / [BackendClient.prepareSignIn], so
/// a key always travels with the exact bytes it was made for.
final class IdempotentBody {
  IdempotentBody._(this._operation, this.key, this._body);

  final ApiOperation _operation;
  final IdempotencyKey key;
  final Uint8List _body;

  @override
  String toString() => 'IdempotentBody(${_operation.id})';
}

final class BackendClient {
  BackendClient({
    required BackendConfig config,
    required ClientIdentity identity,
    required BackendTransport transport,
    required BackendStateStore store,
    DiagLogger? diag,
    Random? random,
    DateTime Function()? now,
  }) : _config = config,
       _identity = identity,
       _transport = transport,
       _store = store,
       _diag = diag,
       _rng = random ?? Random.secure(),
       _now = now ?? DateTime.now;

  /// Registration rounds per [ensureInstalled] call (each `409 INSTALL_EXISTS`
  /// starts a new one with a new install ID).
  static const int maxRegistrationRounds = 3;

  final BackendConfig _config;
  final ClientIdentity _identity;
  final BackendTransport _transport;
  final BackendStateStore _store;
  final DiagLogger? _diag;
  final Random _rng;
  final DateTime Function() _now;
  final StreamController<BackendEvent> _events =
      StreamController<BackendEvent>.broadcast();
  Future<_Install>? _registering;

  Stream<BackendEvent> get events => _events.stream;

  /// The registered install ID (the support code), or null before the first
  /// registration.
  Future<String?> installId() async {
    final b = await _store.read(BackendStateKeys.installId);
    return b == null ? null : utf8.decode(b);
  }

  /// Registers this install if it has no token yet (lazy, backend-api §4.1)
  /// and returns the install ID. Throws [BackendFailure].
  Future<String> ensureInstalled() async => (await _install()).id;

  // ---- operations -----------------------------------------------------------

  Future<SyncResponse> sync(SyncRequest request, {TimeNonce? timeNonce}) async {
    final r = await _call(
      ApiOperations.sync,
      body: _encode(request.toJson),
      timeNonce: timeNonce,
    );
    final out = _decode(r, SyncResponse.fromJson);
    await _rotate(r, out.rotateInstallToken);
    return out;
  }

  /// The signed full catalog snapshot (`GET /v1/catalog/{version}/full`).
  Future<CatalogSnapshot> getFullCatalog(int version) async {
    if (version < 1) throw _clientBug();
    final r = await _call(
      ApiOperations.getFullCatalog,
      pathParams: {'version': '$version'},
    );
    return _decode(r, CatalogSnapshot.fromJson);
  }

  /// Binds [request] to an `Idempotency-Key`. Pass [reuseKey] only to resend
  /// the very same request (a retry); a new request gets a fresh key.
  IdempotentBody prepareVerify(
    PurchaseVerifyRequest request, {
    IdempotencyKey? reuseKey,
  }) {
    _checkPlatform(switch (request) {
      PurchaseVerifyAndroidRequest() => ClientPlatform.android,
      PurchaseVerifyIosRequest() => ClientPlatform.ios,
    });
    return IdempotentBody._(
      ApiOperations.verifyPurchase,
      reuseKey ?? newIdempotencyKey(),
      _encode(request.toJson),
    );
  }

  Future<PurchaseVerifyResponse> verifyPurchase(
    IdempotentBody body, {
    TimeNonce? timeNonce,
  }) async {
    if (body._operation != ApiOperations.verifyPurchase) throw _clientBug();
    final r = await _call(
      ApiOperations.verifyPurchase,
      body: body._body,
      idempotencyKey: body.key,
      timeNonce: timeNonce,
    );
    final out = _decode(r, PurchaseVerifyResponse.fromJson);
    await _rotate(r, out.rotateInstallToken);
    return out;
  }

  Future<PurchaseRestoreResponse> restorePurchases(
    PurchaseRestoreRequest request, {
    TimeNonce? timeNonce,
  }) async {
    _checkPlatform(switch (request) {
      PurchaseRestoreAndroidRequest() => ClientPlatform.android,
      PurchaseRestoreIosRequest() => ClientPlatform.ios,
    });
    final r = await _call(
      ApiOperations.restorePurchases,
      body: _encode(request.toJson),
      timeNonce: timeNonce,
    );
    final out = _decode(r, PurchaseRestoreResponse.fromJson);
    await _rotate(r, out.rotateInstallToken);
    return out;
  }

  Future<EntitlementResponse> getEntitlement({TimeNonce? timeNonce}) async {
    final r = await _call(ApiOperations.getEntitlement, timeNonce: timeNonce);
    final out = _decode(r, EntitlementResponse.fromJson);
    await _rotate(r, out.rotateInstallToken);
    return out;
  }

  /// Binds [request] to an `Idempotency-Key` (see [prepareVerify]).
  /// `seatKeys` is iOS-only (backend-api §4.6): an Android build refuses it.
  IdempotentBody prepareSignIn(
    SignInRequest request, {
    IdempotencyKey? reuseKey,
  }) {
    if (request.seatKeys != null) _checkPlatform(ClientPlatform.ios);
    return IdempotentBody._(
      ApiOperations.signIn,
      reuseKey ?? newIdempotencyKey(),
      _encode(request.toJson),
    );
  }

  Future<SignInResponse> signIn(
    IdempotentBody body, {
    TimeNonce? timeNonce,
  }) async {
    if (body._operation != ApiOperations.signIn) throw _clientBug();
    final r = await _call(
      ApiOperations.signIn,
      body: body._body,
      idempotencyKey: body.key,
      timeNonce: timeNonce,
    );
    return _decode(r, SignInResponse.fromJson);
  }

  Future<EntitlementResponse> signOut({TimeNonce? timeNonce}) async {
    final r = await _call(ApiOperations.signOut, timeNonce: timeNonce);
    final out = _decode(r, EntitlementResponse.fromJson);
    await _rotate(r, out.rotateInstallToken);
    return out;
  }

  Future<void> deleteAccount() async {
    await _call(ApiOperations.deleteAccount);
  }

  /// `DELETE /v1/installs/me` (Delete everything, T-166). Never registers:
  /// without a token there is nothing to delete, and a refused token is not
  /// replaced.
  Future<void> deleteInstall() async {
    if (await _currentInstall() == null) return;
    await _call(ApiOperations.deleteInstall);
  }

  /// A fresh key: a ULID whose 80 random bits come from the client's CSPRNG
  /// (`Random.secure()` unless a test injects one).
  IdempotencyKey newIdempotencyKey() => IdempotencyKey.generate(_rng, _now());

  // ---- request pipeline -----------------------------------------------------

  Uint8List _encode(Map<String, Object?> Function() toJson) {
    final Map<String, Object?> json;
    try {
      json = toJson();
    } on ApiModelException {
      throw _clientBug();
    }
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  void _checkPlatform(ClientPlatform only) {
    if (_identity.platform != only) throw _clientBug();
  }

  BackendFailure _clientBug() => BackendFailure(BackendFailureKind.clientBug);

  Future<_Answer> _call(
    ApiOperation op, {
    Uint8List? body,
    Map<String, String> pathParams = const {},
    IdempotencyKey? idempotencyKey,
    TimeNonce? timeNonce,
  }) async {
    if (op.anchoring) {
      assert(
        timeNonce != null,
        'anchoring calls take a time nonce from the time-anchor service',
      );
      if (timeNonce == null) throw _clientBug();
    } else if (timeNonce != null) {
      throw _clientBug();
    }
    if (op.idempotent != (idempotencyKey != null)) throw _clientBug();
    if ((op.requestSchema != null) != (body != null)) throw _clientBug();

    final headers = <String, String>{
      'zaghlol-app': _identity.header,
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      if (idempotencyKey != null) 'idempotency-key': idempotencyKey.value,
      if (timeNonce != null) 'zaghlol-time-nonce': timeNonce.value,
    };
    String? sentToken;
    String? sentAccount;
    if (op.auth != ApiAuth.none) {
      final install = op == ApiOperations.deleteInstall
          ? await _currentInstall()
          : await _install();
      if (install == null) throw _clientBug();
      sentToken = install.token;
      headers['authorization'] = 'Bearer ${install.token}';
      headers['zaghlol-install'] = install.id;
      if (op.auth == ApiAuth.installAndAccount ||
          op.auth == ApiAuth.installWithOptionalAccount) {
        final acct = await _store.read(BackendStateKeys.accountToken);
        if (acct != null) {
          sentAccount = utf8.decode(acct);
          headers['zaghlol-account'] = sentAccount;
        } else if (op.auth == ApiAuth.installAndAccount) {
          throw BackendFailure(BackendFailureKind.notSignedIn);
        }
      }
    }

    var path = op.path;
    pathParams.forEach((k, v) => path = path.replaceAll('{$k}', v));
    if (path.contains('{')) throw _clientBug();
    final res = await _send(
      BackendRequest(
        method: op.method,
        uri: _config.baseUri.replace(path: path),
        headers: headers,
        body: body,
      ),
    );

    if (res.status == op.successStatus) {
      if (op.signed) {
        try {
          _config.verifier.verify(res.body, res.single('zaghlol-signature'));
        } on ResponseSignatureException {
          await _log(DiagCodes.backendBadSignature, res.status);
          throw BackendFailure(
            BackendFailureKind.badSignature,
            httpStatus: res.status,
          );
        }
      }
      return _Answer(res, sentToken);
    }
    if (res.status >= 200 && res.status < 400) {
      throw await _failed(
        BackendFailure(
          BackendFailureKind.malformedResponse,
          httpStatus: res.status,
        ),
      );
    }
    final failure = _problemOf(res);
    if (res.status == 401 && sentToken != null) {
      if (failure.problem == ProblemCode.installTokenInvalid &&
          op != ApiOperations.deleteInstall) {
        await _failed(failure);
        await _reregister(sentToken);
        throw BackendFailure(
          BackendFailureKind.installReset,
          httpStatus: 401,
          problem: ProblemCode.installTokenInvalid,
        );
      }
      if (failure.problem == ProblemCode.accountTokenExpired &&
          sentAccount != null) {
        await _store.deleteIfEquals(
          BackendStateKeys.accountToken,
          Uint8List.fromList(utf8.encode(sentAccount)),
        );
      }
    }
    throw await _failed(failure);
  }

  Future<BackendResponse> _send(BackendRequest request) async {
    try {
      return await _transport.send(request);
    } on TransportException catch (e) {
      throw await _failed(
        BackendFailure(switch (e.kind) {
          TransportFailureKind.offline => BackendFailureKind.offline,
          TransportFailureKind.timeout => BackendFailureKind.timeout,
          TransportFailureKind.tooLarge ||
          TransportFailureKind.protocol => BackendFailureKind.malformedResponse,
        }),
      );
    }
  }

  /// Maps an error answer (backend-api §6). A code this app version does not
  /// know, or a body that isn't a matching problem, is handled by the HTTP
  /// status class alone ([ProblemCode.unknown]).
  BackendFailure _problemOf(BackendResponse res) {
    var code = ProblemCode.unknown;
    Duration? retry;
    String? nextMove;
    try {
      final p = Problem.fromJson(
        jsonDecode(const Utf8Decoder().convert(res.body)),
      );
      if (p.status == res.status) {
        code = p.code;
        if (code == ProblemCode.moveCooldown) nextMove = p.nextMoveAt;
        if (p.retryAfterSeconds != null) {
          retry = Duration(seconds: min(p.retryAfterSeconds!, 86400));
        }
      }
    } on ApiModelException {
      // Not a problem body: the status class decides (above).
    } on FormatException {
      // Not JSON: the status class decides (above).
    }
    final h = res.single('retry-after');
    final secs = h == null ? null : int.tryParse(h);
    if (secs != null && secs >= 0) {
      retry = Duration(seconds: min(secs, 86400));
    }
    return BackendFailure(
      BackendFailureKind.problem,
      httpStatus: res.status,
      problem: code,
      retryAfter: retry,
      nextMoveAt: nextMove,
    );
  }

  T _decode<T>(_Answer a, T Function(Object? json) fromJson) {
    try {
      return fromJson(jsonDecode(const Utf8Decoder().convert(a.res.body)));
    } on ApiModelException {
      throw BackendFailure(
        BackendFailureKind.malformedResponse,
        httpStatus: a.res.status,
      );
    } on FormatException {
      throw BackendFailure(
        BackendFailureKind.malformedResponse,
        httpStatus: a.res.status,
      );
    }
  }

  /// Honours `rotateInstallToken` from a verified answer, only if the stored
  /// token is still the one this call sent (another actor may have moved on).
  Future<void> _rotate(_Answer a, String? next) async {
    final sent = a.sentToken;
    if (next == null || sent == null || next == sent) return;
    await _store.compareAndSet(
      BackendStateKeys.installToken,
      expected: Uint8List.fromList(utf8.encode(sent)),
      next: Uint8List.fromList(utf8.encode(next)),
    );
  }

  Future<BackendFailure> _failed(BackendFailure f) async {
    await _log(DiagCodes.backendCallFailed, f.httpStatus);
    return f;
  }

  Future<void> _log(DiagCode code, int? status) async {
    final d = _diag;
    if (d == null) return;
    await d.record(
      DiagEvent(
        level: DiagLevel.warn,
        code: code,
        fields: [if (status != null) DiagField.httpStatus(status)],
      ),
    );
  }

  // ---- install registration (backend-api §4.1, R3-6, R5-1) -----------------

  Future<_Install?> _currentInstall() async {
    final id = await _store.read(BackendStateKeys.installId);
    final token = await _store.read(BackendStateKeys.installToken);
    if (id == null || token == null) return null;
    return _Install(utf8.decode(id), utf8.decode(token));
  }

  /// Single-flight per client: concurrent callers share one registration.
  Future<_Install> _install() async {
    final current = await _currentInstall();
    if (current != null &&
        await _store.read(BackendStateKeys.reregistration) == null) {
      return current;
    }
    return _registering ??= _register().whenComplete(() => _registering = null);
  }

  Future<_Install> _register() async {
    final existing = await _currentInstall();
    if (existing != null) {
      // A re-registration stored its token but crashed before announcing it.
      await _announceReregistration();
      return existing;
    }
    for (var round = 0; round < maxRegistrationRounds; round++) {
      final reg = await _pendingRegistration();
      final res = await _send(
        BackendRequest(
          method: ApiOperations.registerInstall.method,
          uri: _config.baseUri.replace(
            path: ApiOperations.registerInstall.path,
          ),
          headers: {
            'zaghlol-app': _identity.header,
            'accept': 'application/json',
            'content-type': 'application/json',
            'idempotency-key': reg.key.value,
          },
          body: reg.body,
        ),
      );
      if (res.status == ApiOperations.registerInstall.successStatus) {
        final InstallResponse ok;
        try {
          ok = InstallResponse.fromJson(
            jsonDecode(const Utf8Decoder().convert(res.body)),
          );
        } on Object {
          // Keep the pending record: a retry with the same key and body gets
          // a fresh token (R3-6).
          throw await _failed(
            BackendFailure(
              BackendFailureKind.malformedResponse,
              httpStatus: res.status,
            ),
          );
        }
        // ID before token, so a stored token always has its ID.
        await _store.write(
          BackendStateKeys.installId,
          Uint8List.fromList(utf8.encode(reg.installId)),
        );
        await _store.write(
          BackendStateKeys.installToken,
          Uint8List.fromList(utf8.encode(ok.installToken)),
        );
        await _store.delete(BackendStateKeys.registration);
        await _announceReregistration();
        return _Install(reg.installId, ok.installToken);
      }
      final failure = _problemOf(res);
      if (res.status == 409 &&
          (failure.problem == ProblemCode.installExists ||
              failure.problem == ProblemCode.idempotencyKeyReused)) {
        // The ID is taken (or the 24 h replay window is over): start over
        // with a new install ID and a new key. Only our own record goes.
        await _store.deleteIfEquals(BackendStateKeys.registration, reg.stored);
        continue;
      }
      // Anything else keeps the pending record for the next attempt.
      throw await _failed(failure);
    }
    throw await _failed(
      BackendFailure(
        BackendFailureKind.problem,
        httpStatus: 409,
        problem: ProblemCode.installExists,
      ),
    );
  }

  Future<_Registration> _pendingRegistration() async {
    for (var i = 0; i < 2; i++) {
      final stored = await _store.read(BackendStateKeys.registration);
      if (stored != null) {
        final r = _Registration.parse(stored);
        if (r != null) return r;
        // Unreadable record: it holds no token, so replacing it loses nothing.
        await _store.deleteIfEquals(BackendStateKeys.registration, stored);
      }
      final installId = newInstallId(_rng);
      final body = _encode(
        InstallRequest(
          installId: installId,
          platform: switch (_identity.platform) {
            ClientPlatform.android => Platform.android,
            ClientPlatform.ios => Platform.ios,
          },
          appVersion: _identity.appVersion,
        ).toJson,
      );
      final bytes = _Registration(
        installId,
        newIdempotencyKey(),
        body,
      ).encode();
      if (await _store.compareAndSet(
        BackendStateKeys.registration,
        expected: null,
        next: bytes,
      )) {
        return _Registration.parse(bytes)!;
      }
      // Another actor stored one first: loop and use theirs.
    }
    throw await _failed(BackendFailure(BackendFailureKind.clientBug));
  }

  /// R5-1. Runs only on a strictly parsed `401 INSTALL_TOKEN_INVALID` for the
  /// token this call sent, and only while that token is still the stored one
  /// (a concurrent call may have re-registered already). Order: marker,
  /// entitlement token, account token, install token, install ID; then the
  /// new registration. A crash anywhere leaves either the old token (the
  /// next call gets the same 401 and resumes) or no token plus the marker.
  Future<void> _reregister(String sentToken) async {
    final current = await _currentInstall();
    if (current == null || current.token != sentToken) return;
    await _store.write(
      BackendStateKeys.reregistration,
      Uint8List.fromList([1]),
    );
    await _store.delete(BackendStateKeys.entitlementToken);
    await _store.delete(BackendStateKeys.accountToken);
    await _store.delete(BackendStateKeys.installToken);
    await _store.delete(BackendStateKeys.installId);
    try {
      await _install();
    } on BackendFailure {
      // Offline etc.: the marker stays and the next call finishes the job.
    }
  }

  Future<void> _announceReregistration() async {
    if (await _store.read(BackendStateKeys.reregistration) == null) return;
    await _log(DiagCodes.installReregistered, null);
    _events.add(const InstallReregistered());
    await _store.delete(BackendStateKeys.reregistration);
  }

  Future<void> dispose() => _events.close();
}

final class _Install {
  _Install(this.id, this.token);
  final String id;
  final String token;
  @override
  String toString() => '_Install';
}

final class _Answer {
  _Answer(this.res, this.sentToken);
  final BackendResponse res;
  final String? sentToken;
}

final class _Registration {
  _Registration(this.installId, this.key, this.body, {Uint8List? stored})
    : stored = stored ?? Uint8List(0);

  final String installId;
  final IdempotencyKey key;
  final Uint8List body;

  /// The exact stored bytes (for compare-and-delete).
  final Uint8List stored;

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'installId': installId,
        'key': key.value,
        'body': base64Url.encode(body),
      }),
    ),
  );

  static _Registration? parse(Uint8List bytes) {
    try {
      final m = jsonDecode(const Utf8Decoder().convert(bytes));
      if (m is! Map<String, Object?>) return null;
      final id = m['installId'];
      final key = m['key'];
      final body = m['body'];
      if (id is! String || key is! String || body is! String) return null;
      if (!isInstallId(id)) return null;
      return _Registration(
        id,
        IdempotencyKey.restore(key),
        Uint8List.fromList(base64Url.decode(body)),
        stored: bytes,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => '_Registration';
}
