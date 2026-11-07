// Fixture for safe_exception_required in the db layer.
import '../core/safe_exception.dart';

// expect_lint: safe_exception_required
class BadDbException implements Exception {}

class GoodDbException extends SafeException {
  const GoodDbException() : super('db');
}
