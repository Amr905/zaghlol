// T-015: standalone entry point for the key bootstrap device tests
// (db_key_tests.dart). CI runs them from db_platform_test.dart instead.
//   flutter test integration_test/db_key_test.dart --flavor devNoSms -d <id>

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'db_key_tests.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('T-015 key bootstrap', registerDbKeyTests);
}
