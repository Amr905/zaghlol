// T-144: entitlement token verification, install binding, trusted-time
// decision, offline cache, sign-out and support notice (backend-api §4.3
// "App rules"; SRS FR-GOLD-04/08, NFR-SEC-05/08).
//
// Gold comes only from a token that (1) verifies against the embedded
// entitlement (`e`) keys, (2) names this install (`sub`, exact string, R5-1),
// (3) has status active/grace, (4) is not `tampered` and (5) has
// `hw < graceUntil`. Anything else grants nothing. Nothing here logs a token,
// an ID or a nonce; mismatches only record a code (no fields).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_client.dart';
import '../../../core/backend/backend_state.dart';
import '../../../core/backend/response_signature.dart';
import '../../../core/db/daos/misc_daos.dart' show DiagLevel;
import '../../../core/logging/diag_code.dart';
import '../../../core/logging/diag_event.dart';
import '../../../core/logging/diag_logger.dart';
import 'gating.dart';
import 'time_anchor.dart';
import 'trusted_time.dart';

const int _secMs = 1000;
const int _maxTokenChars = 16384;
const int _iatSlackMs = 10 * 60 * 1000;

/// A cached token this old (by trusted time) is refreshed when online.
const Duration entitlementRefreshAge = Duration(hours: 12);

/// `secure_state` key of the support notice: `p` pending, `d` dismissed.
const String supportNoticeStateKey = 'entitlement_support_notice';

/// The embedded entitlement-key set of a release build. Empty until T-140
/// creates the production keys (FU-115): with no key nothing verifies, so no
/// token ever grants Gold (fail closed).
final List<ResponseKey> releaseEntitlementKeys = List.unmodifiable(
  <ResponseKey>[],
);

// ---- claims -----------------------------------------------------------------

final class EntitlementClaims {
  const EntitlementClaims({
    required this.sub,
    required this.acct,
    required this.plan,
    required this.status,
    required this.iat,
    required this.exp,
    required this.graceUntil,
    required this.nextMoveAt,
    required this.movedBy,
  });

  final String sub;
  final String? acct;

  /// `"none"` when the install holds no purchase (FU-116).
  final String plan;

  /// Wire value: active, grace, expired, refunded, moved, paused, none.
  final String status;

  /// Seconds since the epoch.
  final int iat;
  final int exp;
  final int graceUntil;

  /// Whole-hour UTC instant, or null (a value off the hour is dropped).
  final DateTime? nextMoveAt;
  final MovedBy? movedBy;

  int get iatMs => iat * _secMs;
  int get expMs => exp * _secMs;
  int get graceUntilMs => graceUntil * _secMs;

  @override
  String toString() => 'EntitlementClaims';
}

final class AccountClaims {
  const AccountClaims({
    required this.sub,
    required this.iid,
    required this.iat,
    required this.exp,
  });
  final String sub;
  final String iid;
  final int iat;
  final int exp;

  @override
  String toString() => 'AccountClaims';
}

Map<String, Object?>? _jws(String token, ResponseSignatureVerifier keys) {
  if (token.length > _maxTokenChars) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final header = jsonDecode(utf8.decode(_unb64(parts[0])));
    if (header is! Map || header['alg'] != 'ES256') return null;
    final kid = header['kid'];
    if (kid is! String) return null;
    for (final k in header.keys) {
      if (k != 'alg' && k != 'kid' && k != 'typ') return null;
    }
    final sig = _unb64(parts[2]);
    final ok = keys.verifyDetached(
      kid: kid,
      kidPrefix: 'e',
      message: Uint8List.fromList(ascii.encode('${parts[0]}.${parts[1]}')),
      signature: sig,
    );
    if (!ok) return null;
    final payload = jsonDecode(utf8.decode(_unb64(parts[1])));
    if (payload is! Map) return null;
    return {for (final e in payload.entries) e.key as String: e.value};
  } on Object {
    return null;
  }
}

Uint8List _unb64(String s) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s)) throw const FormatException();
  return Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));
}

/// Null for any token that is not a signature-valid, well-formed entitlement
/// token. Install binding is the caller's job.
EntitlementClaims? parseEntitlementToken(
  String token,
  ResponseSignatureVerifier keys,
) {
  final m = _jws(token, keys);
  if (m == null) return null;
  final sub = m['sub'];
  final acct = m['acct'];
  final plan = m['plan'];
  final status = m['status'];
  final iat = m['iat'];
  final exp = m['exp'];
  final grace = m['graceUntil'];
  final nm = m['nextMoveAt'];
  final mb = m['movedBy'];
  if (m['iss'] != 'zaghlol' ||
      m['v'] != 1 ||
      sub is! String ||
      (acct != null && acct is! String) ||
      plan is! String ||
      status is! String ||
      iat is! int ||
      exp is! int ||
      grace is! int ||
      m['src'] is! List) {
    return null;
  }
  if (status == 'active' || status == 'grace') {
    // Lifetime rule (D-60): exp <= iat + 3 d, graceUntil = exp + 4 d at most.
    if (exp > iat + 3 * 86400 || grace > exp + 4 * 86400 || grace < exp) {
      return null;
    }
  }
  DateTime? next;
  if (nm is String) {
    final d = DateTime.tryParse(nm);
    if (d != null &&
        d.isUtc &&
        d.minute == 0 &&
        d.second == 0 &&
        d.millisecond == 0) {
      next = d;
    }
  }
  return EntitlementClaims(
    sub: sub,
    acct: acct as String?,
    plan: plan,
    status: status,
    iat: iat,
    exp: exp,
    graceUntil: grace,
    nextMoveAt: next,
    movedBy: mb == 'support'
        ? MovedBy.support
        : (mb == 'user' ? MovedBy.user : null),
  );
}

AccountClaims? parseAccountToken(String token, ResponseSignatureVerifier keys) {
  final m = _jws(token, keys);
  if (m == null) return null;
  final sub = m['sub'];
  final iid = m['iid'];
  final iat = m['iat'];
  final exp = m['exp'];
  if (sub is! String || iid is! String || iat is! int || exp is! int) {
    return null;
  }
  return AccountClaims(sub: sub, iid: iid, iat: iat, exp: exp);
}

// ---- bodies and ports -------------------------------------------------------

/// The parts of a signature-verified 200 body this service needs. Built only
/// from responses [BackendClient] already verified; unsigned bodies never
/// reach it.
final class SignedBody {
  const SignedBody({
    required this.serverTime,
    this.timeNonce,
    this.entitlementToken,
    this.accountToken,
    this.supportNotice,
  });

  factory SignedBody.fromEntitlement(EntitlementResponse r) => SignedBody(
    serverTime: r.serverTime,
    timeNonce: r.timeNonce,
    entitlementToken: r.entitlement.token,
    supportNotice: r.supportNotice,
  );

  factory SignedBody.fromSync(SyncResponse r) => SignedBody(
    serverTime: r.serverTime,
    timeNonce: r.timeNonce,
    entitlementToken: r.entitlement?.token,
    accountToken: r.accountToken,
    supportNotice: r.supportNotice,
  );

  factory SignedBody.fromSignIn(SignInResponse r) => SignedBody(
    serverTime: r.serverTime,
    timeNonce: r.timeNonce,
    entitlementToken: r.entitlement.token,
    accountToken: r.accountToken,
  );

  factory SignedBody.fromVerify(PurchaseVerifyResponse r) => SignedBody(
    serverTime: r.serverTime,
    timeNonce: r.timeNonce,
    entitlementToken: r.entitlement?.token,
  );

  factory SignedBody.fromRestore(PurchaseRestoreResponse r) => SignedBody(
    serverTime: r.serverTime,
    timeNonce: r.timeNonce,
    entitlementToken: r.entitlement?.token,
  );

  final String serverTime;
  final String? timeNonce;
  final String? entitlementToken;
  final String? accountToken;
  final SupportNotice? supportNotice;
}

/// What the service needs of the backend client (a port, so tests need no
/// HTTP).
abstract interface class EntitlementBackend {
  Future<String?> installId();
  Stream<BackendEvent> get events;
  Future<EntitlementResponse> getEntitlement(TimeNonce nonce);
  Future<EntitlementResponse> signOut(TimeNonce nonce);
}

final class BackendClientEntitlementApi implements EntitlementBackend {
  BackendClientEntitlementApi(this._client);
  final BackendClient _client;

  @override
  Future<String?> installId() => _client.installId();
  @override
  Stream<BackendEvent> get events => _client.events;
  @override
  Future<EntitlementResponse> getEntitlement(TimeNonce nonce) =>
      _client.getEntitlement(timeNonce: nonce);
  @override
  Future<EntitlementResponse> signOut(TimeNonce nonce) =>
      _client.signOut(timeNonce: nonce);
}

/// Receives the service's conclusion.
abstract interface class EntitlementSink {
  void apply(EntitlementPhase phase, {MovedBy? movedBy});
}

/// Publishes to [EntitlementNotifier]: Gold only through `applyVerified`
/// (FU-123), which this is called for after every check passed.
final class NotifierEntitlementSink implements EntitlementSink {
  NotifierEntitlementSink(this._notifier);
  final EntitlementNotifier _notifier;

  @override
  void apply(EntitlementPhase phase, {MovedBy? movedBy}) {
    switch (phase) {
      case EntitlementPhase.active:
        _notifier.applyVerified(verified: true, status: 'active');
      case EntitlementPhase.grace:
        _notifier.applyVerified(verified: true, status: 'grace');
      default:
        _notifier.applyNonGold(phase, movedBy: movedBy);
    }
  }
}

// ---- the service ------------------------------------------------------------

final class EntitlementService {
  EntitlementService({
    required this._backend,
    required this._store,
    required this._time,
    required this._anchor,
    required this._keys,
    required this._sink,
    this._diag,
    this._tick = const Duration(seconds: 60),
  });

  final EntitlementBackend _backend;
  final BackendStateStore _store;
  final TrustedTime _time;
  final TimeAnchor _anchor;
  final ResponseSignatureVerifier _keys;
  final EntitlementSink _sink;
  final DiagLogger? _diag;
  final Duration _tick;

  Timer? _timer;
  StreamSubscription<BackendEvent>? _events;
  // In-memory copy of the last verified token (keyed by its exact text, so an
  // edit of the stored value is re-verified, never trusted from memory).
  String? _memoText;
  EntitlementClaims? _memoClaims;

  /// Loads, publishes `pendingVerification` while a cached token is being
  /// checked, evaluates, and starts the 60 s foreground tick.
  Future<void> start() async {
    _events ??= _backend.events.listen((e) {
      if (e is InstallReregistered) unawaited(_onReregistered());
    });
    if (await _store.read(BackendStateKeys.entitlementToken) != null) {
      _sink.apply(EntitlementPhase.pendingVerification);
    }
    await evaluate();
    _timer ??= Timer.periodic(_tick, (_) => unawaited(evaluate()));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _events?.cancel();
    _events = null;
  }

  /// App resume / background task entry: advance, evaluate, refresh if due.
  /// Offline and other typed backend failures are expected and returned as
  /// false; anything else propagates.
  Future<bool> onResume() async {
    await evaluate();
    try {
      await refreshIfDue();
      return true;
    } on BackendFailure {
      return false;
    }
  }

  Future<void> _onReregistered() async {
    _memoText = null;
    _memoClaims = null;
    _anchor.clear();
    await evaluate();
  }

  // ---- decision ----

  /// Advances trusted time and decides. Call before every Gold check.
  Future<EntitlementPhase> evaluate() async {
    final ts = await _time.advance();
    final installId = await _backend.installId();
    final claims = await _cachedClaims();
    var phase = EntitlementPhase.free;
    MovedBy? movedBy;
    if (claims != null && installId != null && claims.sub == installId) {
      switch (claims.status) {
        case 'moved':
          phase = EntitlementPhase.moved;
          movedBy = claims.movedBy ?? MovedBy.user;
        case 'paused':
          phase = EntitlementPhase.paused;
        case 'active' || 'grace':
          if (ts.hw >= claims.graceUntilMs) {
            phase = EntitlementPhase.free;
          } else if (ts.tampered) {
            phase = EntitlementPhase.tampered;
          } else if (claims.acct != null &&
              !await _accountCovers(claims.acct!, installId, ts.hw)) {
            phase = EntitlementPhase.paused;
          } else {
            phase = (claims.status == 'grace' || ts.hw >= claims.expMs)
                ? EntitlementPhase.grace
                : EntitlementPhase.active;
          }
        default:
          phase = EntitlementPhase.free;
      }
    }
    _sink.apply(phase, movedBy: movedBy);
    return phase;
  }

  /// The verified claims of the cached token (for the UI: `nextMoveAt`,
  /// `plan`), or null. Not install-bound: [evaluate] does that.
  Future<EntitlementClaims?> cachedClaims() => _cachedClaims();

  Future<EntitlementClaims?> _cachedClaims() async {
    final b = await _store.read(BackendStateKeys.entitlementToken);
    if (b == null) return null;
    final String text;
    try {
      text = utf8.decode(b);
    } on FormatException {
      return null;
    }
    if (text == _memoText) return _memoClaims;
    final c = parseEntitlementToken(text, _keys);
    _memoText = text;
    _memoClaims = c;
    return c;
  }

  Future<AccountClaims?> _cachedAccount() async {
    final b = await _store.read(BackendStateKeys.accountToken);
    if (b == null) return null;
    try {
      return parseAccountToken(utf8.decode(b), _keys);
    } on FormatException {
      return null;
    }
  }

  Future<bool> _accountCovers(String acct, String installId, int hw) async {
    final a = await _cachedAccount();
    return a != null &&
        a.iid == installId &&
        a.sub == acct &&
        a.exp * _secMs > hw;
  }

  // ---- refresh and sign-out ----

  /// `GET /v1/entitlement` when a cached token is >= 12 h old by trusted time
  /// (or unreadable), or trusted time is `tampered` (only a fresh echo clears
  /// it). Throws [BackendFailure] when the call fails.
  Future<bool> refreshIfDue() async {
    final ts = await _time.advance();
    final has = await _store.read(BackendStateKeys.entitlementToken) != null;
    if (!has && !ts.tampered) return false;
    final c = await _cachedClaims();
    final due =
        ts.tampered ||
        c == null ||
        ts.hw - c.iatMs >= entitlementRefreshAge.inMilliseconds;
    if (!due) return false;
    await _anchor.run(
      _backend.getEntitlement,
      onResponse: (r) => handleBody(SignedBody.fromEntitlement(r)),
    );
    return true;
  }

  /// D-61(c): the cached entitlement token (and the account token) go at
  /// once, whether or not the call succeeds; the 200's token is stored after
  /// the binding check. Throws [BackendFailure] when the call fails.
  Future<void> signOut() async {
    await _store.delete(BackendStateKeys.entitlementToken);
    await _store.delete(BackendStateKeys.accountToken);
    _memoText = null;
    _memoClaims = null;
    _sink.apply(EntitlementPhase.free);
    await _anchor.run(
      _backend.signOut,
      onResponse: (r) => handleBody(SignedBody.fromEntitlement(r)),
    );
  }

  /// Runs an anchoring [request] of another operation (sync, verify, restore,
  /// sign-in) through the serialized anchor and applies its body.
  Future<T> anchored<T>(
    Future<T> Function(TimeNonce nonce) request,
    SignedBody Function(T response) toBody,
  ) => _anchor.run(request, onResponse: (r) => handleBody(toBody(r)));

  // ---- support notice (R4-7(2), R5-7) ----

  Future<bool> hasPendingSupportNotice() async {
    final b = await _store.read(supportNoticeStateKey);
    return b != null && b.length == 1 && b[0] == 0x70;
  }

  /// The user dismissed the notice. A repeat while it is dismissed is
  /// ignored; the dismissed marker is dropped only when the server stops
  /// sending it.
  Future<void> dismissSupportNotice() async {
    if (await hasPendingSupportNotice()) {
      await _store.write(supportNoticeStateKey, Uint8List.fromList([0x64]));
    }
  }

  // ---- applying a signed body ----

  /// Applies a signature-verified body (R4-2 time rules, R5-1 binding).
  Future<void> handleBody(SignedBody b) async {
    final reading = await _time.sample();
    await _time.advance(reading);
    final serverMs = DateTime.tryParse(b.serverTime)
        ?.toUtc()
        .millisecondsSinceEpoch;
    if (serverMs == null) return;
    final installId = await _backend.installId();
    var bindingOk = installId != null;

    AccountClaims? account;
    if (b.accountToken != null) {
      final c = parseAccountToken(b.accountToken!, _keys);
      if (c == null) {
        bindingOk = false;
      } else if (installId == null || c.iid != installId) {
        bindingOk = false;
        await _count(DiagCodes.accountIidMismatch);
      } else {
        account = c;
      }
    }
    EntitlementClaims? token;
    if (b.entitlementToken != null) {
      final c = parseEntitlementToken(b.entitlementToken!, _keys);
      if (c == null) {
        bindingOk = false;
      } else if (installId == null || c.sub != installId) {
        bindingOk = false;
        await _count(DiagCodes.entitlementSubMismatch);
      } else {
        token = c;
      }
    }

    final fresh = bindingOk && _anchor.isFreshEcho(b.timeNonce, reading);
    final TrustedTimeState ts;
    if (fresh) {
      ts = await _time.reanchor(serverTimeMs: serverMs, reading: reading);
      _anchor.consume();
    } else {
      ts = await _time.raise(serverTimeMs: serverMs, reading: reading);
    }

    if (token != null && token.iatMs > ts.hw + _iatSlackMs) token = null;
    if (token != null && !fresh) {
      await _time.raise(
        serverTimeMs: serverMs,
        iatMs: token.iatMs,
        reading: reading,
      );
    }

    if (account != null && account.exp * _secMs > ts.hw) {
      final cached = await _cachedAccount();
      if (cached == null || cached.iat <= account.iat) {
        await _store.write(
          BackendStateKeys.accountToken,
          Uint8List.fromList(utf8.encode(b.accountToken!)),
        );
      }
    }

    if (token != null) {
      final cached = await _cachedClaims();
      // An older signed token (a replay) never replaces a newer one.
      final stored = cached == null || cached.iat <= token.iat;
      if (stored) {
        await _store.write(
          BackendStateKeys.entitlementToken,
          Uint8List.fromList(utf8.encode(b.entitlementToken!)),
        );
        await _storeNotice(b.supportNotice);
      }
    }
    await evaluate();
  }

  Future<void> _storeNotice(SupportNotice? n) async {
    final cur = await _store.read(supportNoticeStateKey);
    if (n == SupportNotice.goldLinkedBySupport) {
      if (cur == null) {
        await _store.write(supportNoticeStateKey, Uint8List.fromList([0x70]));
      }
      // pending or dismissed: a repeat, ignored.
    } else if (n == null && cur != null && cur[0] == 0x64) {
      await _store.delete(supportNoticeStateKey);
    }
  }

  Future<void> _count(DiagCode code) async {
    final d = _diag;
    if (d == null) return;
    await d.record(DiagEvent(level: DiagLevel.warn, code: code));
  }
}

/// Must be overridden where the backend client is wired (T-143): the release
/// key set is empty until T-140, so an unwired app is Free.
final entitlementServiceProvider = Provider<EntitlementService>(
  (ref) => throw UnimplementedError('entitlementServiceProvider not wired'),
);
