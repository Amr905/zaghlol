// T-183: typed failures of the request-binding library. Messages are fixed
// strings and never echo the input (self-check 3 / 5).

enum BindingFailure {
  /// Not well-formed JSON, or beyond the size / depth caps.
  malformedJson,

  /// A member name occurs twice in one object (at any depth).
  duplicateMember,

  /// An unpaired UTF-16 surrogate, raw or written as a \uXXXX escape.
  loneSurrogate,

  /// A number that has no finite ECMAScript representation.
  unsupportedNumber,

  /// installId is not a lower-case hyphenated UUID.
  invalidInstallId,

  /// An input byte string has the wrong length or encoding.
  invalidInput,
}

class BindingException implements Exception {
  const BindingException(this.failure);
  final BindingFailure failure;

  @override
  String toString() => 'BindingException(${failure.name})';
}
