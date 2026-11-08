import 'failure.dart';

/// The outcome of an operation that can fail in an expected way.
///
/// Sealed: a `switch` over a [Result] must handle both [Ok] and [Err].
sealed class Result<T, F extends Failure> {
  const Result();

  /// A successful result carrying [value].
  const factory Result.ok(T value) = Ok<T, F>;

  /// A failed result carrying [failure].
  const factory Result.err(F failure) = Err<T, F>;

  bool get isOk => this is Ok<T, F>;

  bool get isErr => this is Err<T, F>;

  /// The value, or null on failure.
  T? get valueOrNull => switch (this) {
    Ok<T, F>(:final value) => value,
    Err<T, F>() => null,
  };

  /// The failure, or null on success.
  F? get failureOrNull => switch (this) {
    Ok<T, F>() => null,
    Err<T, F>(:final failure) => failure,
  };

  /// Transforms the value of a success; a failure passes through.
  Result<U, F> map<U>(U Function(T value) transform) => switch (this) {
    Ok<T, F>(:final value) => Ok<U, F>(transform(value)),
    Err<T, F>(:final failure) => Err<U, F>(failure),
  };

  /// Chains another fallible step after a success.
  Result<U, F> flatMap<U>(Result<U, F> Function(T) f) => switch (this) {
    Ok<T, F>(:final value) => f(value),
    Err<T, F>(:final failure) => Err<U, F>(failure),
  };

  /// Collapses the result into one value.
  R fold<R>(R Function(T) onOk, R Function(F) onErr) => switch (this) {
    Ok<T, F>(:final value) => onOk(value),
    Err<T, F>(:final failure) => onErr(failure),
  };
}

/// A successful [Result].
final class Ok<T, F extends Failure> extends Result<T, F> {
  const Ok(this.value);

  final T value;

  // Deliberately omits the value: it may be a balance or message text.
  @override
  String toString() => 'Ok';
}

/// A failed [Result].
final class Err<T, F extends Failure> extends Result<T, F> {
  const Err(this.failure);

  final F failure;

  @override
  String toString() => 'Err(${failure.code})';
}
