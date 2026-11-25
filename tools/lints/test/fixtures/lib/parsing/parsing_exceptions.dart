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

// FU-309: a static const only counts when its value is UPPER_SNAKE.
class StaticConstGood extends SafeException {
  const StaticConstGood() : super(_code);
  static const _code = 'STATIC_GOOD';
}

class StaticConstBad extends SafeException {
  // expect_lint: safe_exception_required
  const StaticConstBad() : super(_code);
  static const _code = 'not upper';
}

class StaticConstNonLiteral extends SafeException {
  // expect_lint: safe_exception_required
  const StaticConstNonLiteral() : super(_code);
  static const _code =
      'A'
      'B';
}

// FU-310: named constructors and super.code forwarding.
class NamedGood extends SafeException {
  const NamedGood() : super.named('NAMED_OK');
}

class NamedBad extends SafeException {
  // expect_lint: safe_exception_required
  const NamedBad(String c) : super.named(c);
}

class SuperCodeForward extends SafeException {
  // expect_lint: safe_exception_required
  const SuperCodeForward(super.code);
}

SafeException makeNamedGood() => const SafeException.named('MADE_OK');

SafeException makeNamedBad(String c) =>
    // expect_lint: safe_exception_required
    SafeException.named(c);

class SuperCodeWithConstants extends SafeException {
  const SuperCodeWithConstants(super.code);
  static const String one = 'ONE_CODE';
}
