// T-340: the shared client of the LLM gateway (`POST /v1/ask/plan`,
// `POST /v1/categorise`; ask-llm §4.1, §5, llm-categorise §3; FR-LLM-02,
// FR-LLM-14, FR-LLM-51, FR-LCAT-02/14).
//
// Order of one call (design note in docs/04-tasks/tasks/T-340.md):
//   gate (no I/O on refusal): flag fresh ON → not paused → consent covers the
//   active terms → local quota snapshot not at 0 before `resetsAt`
//   → [12 s from here] install ID → bodyHash over the exact body without
//   `attestation` → device proof → same hash re-checked on the final request
//   → BackendClient (generated DTOs, operation-table headers) → quota
//   snapshot from the reply.
//
// What goes out is only what the OpenAPI lists: for Ask the masked question
// (`MaskResult.sentText`, never the raw text) and the language; for
// categorise the merchant names and the language; plus the consent terms, a
// fresh ULID `requestId` and the proof. No amounts, balances, SMS or account
// names are ever an input here.
//
// Nothing here logs. Errors carry codes (and, where the contract defines
// them, the quota numbers, the provider id or a retry delay), never text.

// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;
import 'package:zaghlol_parsing/zaghlol_parsing.dart' show MaskResult;

import '../../features/catalog_sync/application/sync_providers.dart'
    show backendClientProvider, clientPlatformProvider;
import '../backend/backend_client.dart';
import '../db/app_database_providers.dart';
import '../db/daos/llm_cat_queue_dao.dart';
import '../flags/feature_flags.dart';
import '../flags/flags_providers.dart';
import '../platform/pigeon_attestation.dart';
import '../settings/settings_providers.dart';
import 'llm_attestation.dart';
import 'llm_consent.dart';
import 'llm_feature.dart';
import 'llm_quota_snapshot.dart';

/// The answer language (`lang`).
enum LlmLang { ar, en }

/// The terms the user must have agreed to: the backend's active provider
/// (remote config) and the consent sheet's version.
final class LlmTerms {
  const LlmTerms({required this.provider, required this.v});
  final String provider;
  final int v;

  @override
  String toString() => 'LlmTerms($provider, v$v)';
}

/// Why the gate refused before anything was sent.
enum LlmBlockReason { flagOff, paused, noConsent, quotaExhausted }

/// Every failure of the gateway. Code only (plus contract numbers).
sealed class LlmGatewayException extends SafeException {
  LlmGatewayException(super.code);
}

/// The local gate refused: nothing was sent, no proof was made.
final class LlmBlocked extends LlmGatewayException {
  LlmBlocked(this.reason) : super('LLM_BLOCKED');
  final LlmBlockReason reason;
  @override
  String toString() => 'LlmBlocked(${reason.name})';
}

/// `403 LLM_QUOTA_EXHAUSTED`; [quota] is the backend's (also stored).
final class LlmQuotaExhausted extends LlmGatewayException {
  LlmQuotaExhausted(this.quota) : super('LLM_QUOTA_EXHAUSTED');
  final LlmQuotaSnapshot? quota;
}

/// `409 LLM_CONSENT_REQUIRED`; the stored consent was cleared. [providerId]
/// is the backend's active provider.
final class LlmConsentRequired extends LlmGatewayException {
  LlmConsentRequired(this.providerId) : super('LLM_CONSENT_REQUIRED');
  final String? providerId;
}

/// `503 LLM_SERVICE_PAUSED`; the feature is paused until the next sync.
final class LlmServicePaused extends LlmGatewayException {
  LlmServicePaused() : super('LLM_SERVICE_PAUSED');
}

/// `422 DEVICE_ATTESTATION_FAILED`. [hadAttestationObject]: the refused proof
/// already came from a new key (iOS), so another key won't help.
final class LlmAttestationFailed extends LlmGatewayException {
  LlmAttestationFailed({required this.hadAttestationObject})
    : super('LLM_ATTESTATION_FAILED');
  final bool hadAttestationObject;
}

/// No proof could be made on this phone (nothing was sent).
final class LlmAttestationUnavailable extends LlmGatewayException {
  LlmAttestationUnavailable(this.failure)
    : super('LLM_ATTESTATION_UNAVAILABLE');
  final AttestationFailure failure;
}

/// `429 RATE_LIMITED`.
final class LlmRateLimited extends LlmGatewayException {
  LlmRateLimited(this.retryAfter) : super('LLM_RATE_LIMITED');
  final Duration? retryAfter;
}

/// `502/503 UPSTREAM_UNAVAILABLE`, other 5xx, a malformed reply or an
/// install reset: try again later.
final class LlmUpstreamUnavailable extends LlmGatewayException {
  LlmUpstreamUnavailable(this.retryAfter) : super('LLM_UPSTREAM_UNAVAILABLE');
  final Duration? retryAfter;
}

/// `400 VALIDATION_FAILED / UNKNOWN_FIELD`, or a request the app refused to
/// build (a bug; nothing to retry).
final class LlmRequestRejected extends LlmGatewayException {
  LlmRequestRejected() : super('LLM_REQUEST_REJECTED');
}

final class LlmOffline extends LlmGatewayException {
  LlmOffline() : super('LLM_OFFLINE');
}

/// No reply within [LlmGatewayClient.timeout] (FR-LLM-51).
final class LlmTimeout extends LlmGatewayException {
  LlmTimeout() : super('LLM_TIMEOUT');
}

/// The caller's Stop. Whether the backend counted it is the backend's call.
final class LlmCancelled extends LlmGatewayException {
  LlmCancelled() : super('LLM_CANCELLED');
}

final class LlmGatewayClient {
  LlmGatewayClient({
    required BackendClient backend,
    required LlmProver prover,
    required LlmConsentStore consent,
    required LlmQuotaStore quota,
    required bool Function(FeatureFlag flag) isFlagOn,
    DateTime Function()? now,
    this.timeout = defaultTimeout,
  }) : _backend = backend,
       _prover = prover,
       _consent = consent,
       _quota = quota,
       _isFlagOn = isFlagOn,
       _now = now ?? DateTime.now;

  /// FR-LLM-51.
  static const Duration defaultTimeout = Duration(seconds: 12);

  final Duration timeout;
  final BackendClient _backend;
  final LlmProver _prover;
  final LlmConsentStore _consent;
  final LlmQuotaStore _quota;
  final bool Function(FeatureFlag) _isFlagOn;
  final DateTime Function() _now;

  static const LlmAttestation _placeholder = LlmDevProof(proof: 'unbound0');

  /// `POST /v1/ask/plan` with [masked]'s `sentText`. [stop] aborts it;
  /// [forceNewKey] (iOS) after a `422` whose proof had no attestation object.
  Future<AskPlanResponse> askPlan({
    required MaskResult masked,
    required LlmLang lang,
    required LlmTerms terms,
    AbortSignal? stop,
    bool forceNewKey = false,
  }) async {
    const f = LlmFeature.ask;
    final grant = await _gate(f, terms);
    final requestId = _backend.newIdempotencyKey().value;
    final q = masked.sentText;
    AskPlanRequest build(LlmAttestation a) => AskPlanRequest(
      planVersion: 1,
      requestId: requestId,
      q: q,
      lang: switch (lang) {
        LlmLang.ar => AskPlanRequestLang.ar,
        LlmLang.en => AskPlanRequestLang.en,
      },
      consent: LlmConsent(provider: grant.provider, v: grant.v),
      attestation: a,
    );
    return _exchange<AskPlanRequest, AskPlanResponse>(
      f,
      stop: stop,
      forceNewKey: forceNewKey,
      build: build,
      toJson: (r) => r.toJson(),
      proofOf: (r) => r.attestation,
      call: (r, abort) => _backend.askPlan(r, abort: abort),
      quotaOf: (r) => r.quota,
    );
  }

  /// `POST /v1/categorise` with [merchants] (already eligible, 1…20 unique).
  Future<CategoriseResponse> categorise({
    required List<String> merchants,
    required LlmLang lang,
    required LlmTerms terms,
    AbortSignal? stop,
    bool forceNewKey = false,
    String? requestId,
  }) async {
    const f = LlmFeature.categorise;
    final grant = await _gate(f, terms);
    final names = List<String>.unmodifiable(merchants);
    if (names.toSet().length != names.length) throw LlmRequestRejected();
    // T-358: a retry of the same batch inside the server's 2-minute window
    // passes the earlier [requestId] so the backend counts it once.
    final rid = requestId ?? _backend.newIdempotencyKey().value;
    CategoriseRequest build(LlmAttestation a) => CategoriseRequest(
      v: 1,
      requestId: rid,
      lang: switch (lang) {
        LlmLang.ar => CategoriseRequestLang.ar,
        LlmLang.en => CategoriseRequestLang.en,
      },
      merchants: names,
      consent: LlmConsent(provider: grant.provider, v: grant.v),
      attestation: a,
    );
    return _exchange<CategoriseRequest, CategoriseResponse>(
      f,
      stop: stop,
      forceNewKey: forceNewKey,
      build: build,
      toJson: (r) => r.toJson(),
      proofOf: (r) => r.attestation,
      call: (r, abort) => _backend.categorise(r, abort: abort),
      quotaOf: (r) => r.quota,
    );
  }

  /// The local gate. Throws [LlmBlocked]; reads only encrypted settings and
  /// the in-memory flags.
  Future<LlmConsentGrant> _gate(LlmFeature f, LlmTerms terms) async {
    if (!_isFlagOn(f.flag)) throw LlmBlocked(LlmBlockReason.flagOff);
    if (await _quota.isPaused(f)) throw LlmBlocked(LlmBlockReason.paused);
    final grant = await _consent.grantFor(f, terms.provider, terms.v);
    if (grant == null) throw LlmBlocked(LlmBlockReason.noConsent);
    if (await _quota.exhausted(f, _now())) {
      throw LlmBlocked(LlmBlockReason.quotaExhausted);
    }
    return grant;
  }

  Future<Res> _exchange<Req, Res>(
    LlmFeature f, {
    required AbortSignal? stop,
    required bool forceNewKey,
    required Req Function(LlmAttestation) build,
    required Map<String, Object?> Function(Req) toJson,
    required LlmAttestation Function(Req) proofOf,
    required Future<Res> Function(Req, AbortSignal) call,
    required LlmQuota Function(Res) quotaOf,
  }) async {
    final abort = AbortSignal();
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      abort.abort();
    });
    if (stop != null) {
      if (stop.aborted) abort.abort();
      unawaited(stop.whenAborted.then((_) => abort.abort()));
    }
    LlmGatewayException ended() => timedOut ? LlmTimeout() : LlmCancelled();

    Future<Res> work() async {
      final String installId;
      try {
        installId = await _backend.ensureInstalled();
      } on BackendFailure catch (e) {
        throw await _mapFailure(f, e, abort, hadObject: false);
      }
      if (abort.aborted) throw ended();

      final Uint8List bodyHash;
      try {
        bodyHash = _hash(f, installId, toJson(build(_placeholder)));
      } on BindingException {
        throw LlmRequestRejected();
      } on ApiModelException {
        throw LlmRequestRejected();
      }

      final LlmAttestation proof;
      try {
        proof = await _prover.prove(f, bodyHash, forceNewKey: forceNewKey);
      } on AttestationException catch (e) {
        throw LlmAttestationUnavailable(e.failure);
      } on BindingException {
        throw LlmRequestRejected();
      }
      if (abort.aborted) throw ended();

      final request = build(proof);
      try {
        final again = _hash(f, installId, toJson(request));
        if (!_same(again, bodyHash)) throw LlmRequestRejected();
      } on BindingException {
        throw LlmRequestRejected();
      } on ApiModelException {
        throw LlmRequestRejected();
      }

      final hadObject =
          proofOf(request) is LlmAppAttestProof &&
          (proofOf(request) as LlmAppAttestProof).attestationObject != null;
      final Res res;
      try {
        res = await call(request, abort);
      } on BackendFailure catch (e) {
        throw await _mapFailure(f, e, abort, hadObject: hadObject);
      }
      // A reply that lost the race with Stop or the timeout is dropped.
      if (abort.aborted) throw ended();
      await _quota.record(f, quotaOf(res));
      return res;
    }

    try {
      return await Future.any([
        work(),
        abort.whenAborted.then<Res>((_) => throw ended()),
      ]);
    } finally {
      timer.cancel();
      abort.abort(); // Releases the transport and the stop listener.
    }
  }

  static Uint8List _hash(
    LlmFeature f,
    String installId,
    Map<String, Object?> body,
  ) => llmBodyHash(f, installId, jsonEncode(body));

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  /// §4.1 error table. Side effects (snapshot, consent, pause) only when the
  /// answer arrived before Stop or the timeout.
  Future<LlmGatewayException> _mapFailure(
    LlmFeature f,
    BackendFailure e,
    AbortSignal abort, {
    required bool hadObject,
  }) async {
    switch (e.kind) {
      case BackendFailureKind.cancelled:
        return LlmCancelled();
      case BackendFailureKind.offline:
        return LlmOffline();
      case BackendFailureKind.timeout:
        return LlmTimeout();
      case BackendFailureKind.notSignedIn:
      case BackendFailureKind.clientBug:
        return LlmRequestRejected();
      case BackendFailureKind.badSignature:
      case BackendFailureKind.malformedResponse:
      case BackendFailureKind.installReset:
        return LlmUpstreamUnavailable(e.retryAfter);
      case BackendFailureKind.problem:
        break;
    }
    final live = !abort.aborted;
    switch (e.problem) {
      case ProblemCode.llmQuotaExhausted:
        final q = e.llmQuota;
        if (q != null && live) await _quota.record(f, q);
        return LlmQuotaExhausted(
          q == null ? null : LlmQuotaSnapshot.fromWire(q),
        );
      case ProblemCode.llmConsentRequired:
        if (live) await _consent.clear(f);
        return LlmConsentRequired(e.providerId);
      case ProblemCode.llmServicePaused:
        if (live) await _quota.pause(f);
        return LlmServicePaused();
      case ProblemCode.deviceAttestationFailed:
        return LlmAttestationFailed(hadAttestationObject: hadObject);
      case ProblemCode.rateLimited:
        return LlmRateLimited(e.retryAfter);
      case ProblemCode.upstreamUnavailable:
        return LlmUpstreamUnavailable(e.retryAfter);
      case ProblemCode.validationFailed:
      case ProblemCode.unknownField:
        return LlmRequestRejected();
      default:
        final s = e.httpStatus ?? 0;
        if (s == 429) return LlmRateLimited(e.retryAfter);
        if (s >= 500) return LlmUpstreamUnavailable(e.retryAfter);
        return LlmRequestRejected();
    }
  }

  @override
  String toString() => 'LlmGatewayClient';
}

/// The consent store over the encrypted settings.
final llmConsentStoreProvider = FutureProvider<LlmConsentStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return LlmConsentStore(
    await ref.watch(settingsRepositoryProvider.future),
    onCleared: (f) async {
      if (f == LlmFeature.categorise) await LlmCatQueueDao(db).clear();
    },
  );
}, name: 'llmConsentStoreProvider');

/// The quota snapshot and pause store over the encrypted settings.
final llmQuotaStoreProvider = FutureProvider<LlmQuotaStore>(
  (ref) async =>
      LlmQuotaStore(await ref.watch(settingsRepositoryProvider.future)),
  name: 'llmQuotaStoreProvider',
);

/// The prover for this build (dev only in debug with a dev key).
final llmProverProvider = Provider<LlmProver>(
  (ref) => selectLlmProver(
    attestation: ref.watch(attestationProvider),
    platform: ref.watch(clientPlatformProvider),
  ),
  name: 'llmProverProvider',
);

final llmGatewayClientProvider = FutureProvider<LlmGatewayClient>((ref) async {
  final flags = await ref.watch(flagsServiceProvider.future);
  return LlmGatewayClient(
    backend: ref.watch(backendClientProvider),
    prover: ref.watch(llmProverProvider),
    consent: await ref.watch(llmConsentStoreProvider.future),
    quota: await ref.watch(llmQuotaStoreProvider.future),
    isFlagOn: flags.isOn,
  );
}, name: 'llmGatewayClientProvider');
