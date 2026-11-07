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
  const GoodParseException() : super('parse');
}

class GoodIndirectException extends GoodParseException {
  const GoodIndirectException();
}

class NotAnException {}
