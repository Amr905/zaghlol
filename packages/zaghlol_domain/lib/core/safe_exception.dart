/// An exception that never carries message text.
///
/// Exception messages from parsing and DB layers must not include data
/// (error-handling §3). A [SafeException] holds a constant [code] only, and
/// its [toString] prints that code and nothing else, so it is safe to log.
base class SafeException implements Exception {
  /// [code] must be UPPER_SNAKE_CASE, e.g. `SPOOL_DECRYPT_FAILED`. The
  /// shape check keeps free text, and so user data, out of the code.
  SafeException(this.code) {
    assert(_codePattern.hasMatch(code), 'code must be UPPER_SNAKE_CASE');
  }

  static final RegExp _codePattern = RegExp(r'^[A-Z][A-Z0-9_]{0,63}$');

  final String code;

  @override
  String toString() => code;
}
