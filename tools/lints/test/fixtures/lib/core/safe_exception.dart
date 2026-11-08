/// Stand-in for the real SafeException (T-014). Lives outside the parsing and
/// db layers, so the rule does not check it.
abstract class SafeException implements Exception {
  const SafeException(this.code);

  final String code;
}
