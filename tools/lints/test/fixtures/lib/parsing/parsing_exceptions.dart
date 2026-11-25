// Fixture for safe_exception_required in the parsing layer.
import '../core/safe_exception.dart';

// expect_lint: safe_exception_required
class BadImplementsException implements Exception {}

// expect_lint: safe_exception_required
class BadExtendsError extends Error {}

// expect_lint: safe_exception_required
class BadExtendsFormat extends FormatException {}

// Compliant below.
class GoodParseException extends SafeException {
  const GoodParseException() : super('PARSE');
}

class GoodIndirectException extends GoodParseException {
  const GoodIndirectException();
}

class NotAnException {}

void throwsDirectly(int x) {
  // expect_lint: safe_exception_required
  if (x == 1) throw FormatException('bad');
  if (x == 2) throw const GoodParseException();
}

// FU-033: enums and mixins that are exceptions.
// expect_lint: safe_exception_required
enum BadEnumException implements Exception { one }

// expect_lint: safe_exception_required
mixin BadMixinException implements Exception {}

enum NotThrowable { one }

void throwsMore(int x) {
  // expect_lint: safe_exception_required
  if (x == 1) throw TimeoutException('t');
}

// FU-033: SafeException codes must be UPPER_SNAKE_CASE string literals.
class CodeFromVariable extends SafeException {
  // expect_lint: safe_exception_required
  const CodeFromVariable(String c) : super(c);
}

class CodeInterpolated extends SafeException {
  // expect_lint: safe_exception_required
  CodeInterpolated(int n) : super('E_$n');
}

class CodeLowercase extends SafeException {
  // expect_lint: safe_exception_required
  const CodeLowercase() : super('lower_case');
}

class CodeGood extends SafeException {
  const CodeGood() : super('PARSE_FAILED');
}

SafeException make(String c) =>
    // expect_lint: safe_exception_required
    SafeException(c);
