// T-016: standalone entry for the AppDatabase device tests (CI runs them via
// db_platform_test.dart in one launch).
//   flutter test integration_test/app_database_test.dart --flavor devNoSms -d <id>

import 'package:integration_test/integration_test.dart';

import 'app_database_tests.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerAppDatabaseTests();
}
