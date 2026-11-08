/// Typed failures returned by domain and data code (error-handling §1).
///
/// A failure never carries free text: only enums, integers and constant
/// codes. This keeps raw SMS, amounts and account numbers out of anything
/// that is logged or shown (NFR-SEC-03, CLAUDE.md §2.6).
library;

/// Root of the failure hierarchy. Sealed, so a `switch` over a [Failure]
/// must handle every area and the compiler flags a missing case.
sealed class Failure {
  const Failure();

  /// A stable, constant code for diagnostics. Never contains user data.
  String get code;

  @override
  String toString() => '$runtimeType($code)';
}

/// Why a message could not be parsed into a transaction.
enum ParseFailureReason { noTemplate, lowConfidence, malformedAmount, unknown }

/// A message could not be parsed. The raw message is kept for review
/// elsewhere (EC-08); it is never stored on the failure.
final class ParseFailure extends Failure {
  const ParseFailure(this.reason);

  final ParseFailureReason reason;

  @override
  String get code => 'PARSE_${_screaming(reason.name)}';
}

/// Which database operation failed.
enum DbFailureKind {
  openFailed,
  keyInvalidated,
  writeFailed,
  diskFull,
  migrationFailed,
  constraintViolation,
  unknown,
}

/// A database failure, wrapped at the data-layer boundary.
final class DbFailure extends Failure {
  const DbFailure(this.kind);

  final DbFailureKind kind;

  @override
  String get code => 'DB_${_screaming(kind.name)}';
}

/// Why a network call failed.
enum NetworkFailureKind { offline, timeout, server }

/// A network failure. [serverStatus] is set only for
/// [NetworkFailureKind.server].
final class NetworkFailure extends Failure {
  const NetworkFailure._(this.kind, [this.serverStatus]);

  const NetworkFailure.offline() : this._(NetworkFailureKind.offline);

  const NetworkFailure.timeout() : this._(NetworkFailureKind.timeout);

  const NetworkFailure.server(int status)
    : this._(NetworkFailureKind.server, status);

  final NetworkFailureKind kind;

  /// HTTP status code for a server failure, otherwise null.
  final int? serverStatus;

  @override
  String get code => switch (kind) {
    NetworkFailureKind.offline => 'NET_OFFLINE',
    NetworkFailureKind.timeout => 'NET_TIMEOUT',
    NetworkFailureKind.server => 'NET_SERVER_$serverStatus',
  };
}

/// A platform-channel or OS failure. [platformCode] must be a constant
/// code such as `SPOOL_DECRYPT_FAILED`, never a message.
final class PlatformFailure extends Failure {
  const PlatformFailure(this.platformCode);

  final String platformCode;

  @override
  String get code => 'PLATFORM_$platformCode';
}

/// Why a cryptographic operation failed.
enum CryptoFailureKind {
  keyUnavailable,
  decryptFailed,
  encryptFailed,
  signatureInvalid,
  unknown,
}

/// A cryptographic failure (keys, encryption, signature checks).
final class CryptoFailure extends Failure {
  const CryptoFailure(this.kind);

  final CryptoFailureKind kind;

  @override
  String get code => 'CRYPTO_${_screaming(kind.name)}';
}

/// Why a currency operation failed.
enum CurrencyFailureKind { mismatch, unknownCurrency, overflow }

/// A currency failure, e.g. mixing two currencies (BR-FX-02). It names a
/// kind only, never an amount.
final class CurrencyFailure extends Failure {
  const CurrencyFailure(this.kind);

  final CurrencyFailureKind kind;

  @override
  String get code => 'CURRENCY_${_screaming(kind.name)}';
}

/// Converts a lowerCamelCase enum name to UPPER_SNAKE_CASE.
String _screaming(String camel) {
  final spaced = camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}');
  return spaced.toUpperCase();
}
