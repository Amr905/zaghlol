// T-141: the typed failure of every BackendClient call (error-handling §1,
// backend-api §6). Code, kind, HTTP status and problem code only: never a
// body, header, token, key or URL.

import 'package:zaghlol_domain/zaghlol_domain.dart'
    show NetworkFailure, SafeException;

import 'generated/api_models.g.dart' show ProblemCode;

enum BackendFailureKind {
  /// No connection (DNS, socket, TLS setup).
  offline,

  /// No complete answer in time.
  timeout,

  /// A signed operation's 2xx had no valid `Zaghlol-Signature` from a pinned
  /// key. The body was dropped.
  badSignature,

  /// The answer did not match the contract (status, JSON, schema, size).
  malformedResponse,

  /// A problem+json error ([BackendFailure.problem], [BackendFailure.httpStatus]).
  problem,

  /// `401 INSTALL_TOKEN_INVALID`: the cached entitlement and account tokens
  /// were deleted and a new install is (being) registered (R5-1). Retry the
  /// call.
  installReset,

  /// The operation needs the account token and none is stored.
  notSignedIn,

  /// The app built a request the contract forbids (nothing was sent).
  clientBug,
}

final class BackendFailure extends SafeException {
  BackendFailure(this.kind, {this.httpStatus, this.problem, this.retryAfter})
    : super(_codeOf(kind));

  final BackendFailureKind kind;

  /// The HTTP status for [BackendFailureKind.problem] (and malformed answers).
  final int? httpStatus;

  /// The problem code; [ProblemCode.unknown] for a code this app version does
  /// not know, which is then handled by its HTTP status class (§6).
  final ProblemCode? problem;

  /// From `Retry-After` or `retryAfterSeconds` (capped at one day).
  final Duration? retryAfter;

  /// Whether a later retry can succeed without an app change.
  bool get retryable => switch (kind) {
    BackendFailureKind.offline ||
    BackendFailureKind.timeout ||
    BackendFailureKind.badSignature ||
    BackendFailureKind.malformedResponse ||
    BackendFailureKind.installReset => true,
    BackendFailureKind.notSignedIn || BackendFailureKind.clientBug => false,
    BackendFailureKind.problem =>
      httpStatus == 429 || (httpStatus != null && httpStatus! >= 500),
  };

  /// The domain-level failure for layers that only need the network class.
  NetworkFailure toNetworkFailure() => switch (kind) {
    BackendFailureKind.offline => const NetworkFailure.offline(),
    BackendFailureKind.timeout => const NetworkFailure.timeout(),
    _ => NetworkFailure.server(httpStatus ?? 0),
  };

  static String _codeOf(BackendFailureKind k) => switch (k) {
    BackendFailureKind.offline => 'BACKEND_OFFLINE',
    BackendFailureKind.timeout => 'BACKEND_TIMEOUT',
    BackendFailureKind.badSignature => 'BACKEND_BAD_SIGNATURE',
    BackendFailureKind.malformedResponse => 'BACKEND_MALFORMED_RESPONSE',
    BackendFailureKind.problem => 'BACKEND_PROBLEM',
    BackendFailureKind.installReset => 'BACKEND_INSTALL_RESET',
    BackendFailureKind.notSignedIn => 'BACKEND_NOT_SIGNED_IN',
    BackendFailureKind.clientBug => 'BACKEND_CLIENT_BUG',
  };

  @override
  String toString() =>
      'BackendFailure(${kind.name}'
      '${httpStatus == null ? '' : ', $httpStatus'}'
      '${problem == null ? '' : ', ${problem!.name}'})';
}
