// T-007 (SPK-05): the encrypted-SQLite contract and FTS benchmark on the
// binaries the app ships (Android APK / iOS app, real flavors and minSdk).
//
// CI (db-platform.yml):
//   flutter test integration_test/db_platform_test.dart --flavor devNoSms
//   flutter test integration_test/db_platform_test.dart --flavor dev
// Real devices (docs/05-reviews/T-007-device.md):
//   flutter drive --profile --flavor devNoSms \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/db_platform_test.dart \
//     --dart-define=ZAGHLOL_DB_BENCH=1 -d <id>
//
// The benchmark runs only with --dart-define=ZAGHLOL_DB_BENCH=1 (or true).
// Nothing here is reachable from lib/main.dart; release builds never contain it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/core/db/fts_benchmark.dart';
import '../test/core/db/sqlite3mc_contract.dart';

const String _benchFlag = String.fromEnvironment('ZAGHLOL_DB_BENCH');
const String _envLabel = String.fromEnvironment('ZAGHLOL_DB_ENV');
const String _runId = String.fromEnvironment('ZAGHLOL_RUN_ID');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final env = _envLabel.isEmpty ? Platform.operatingSystem : _envLabel;

  registerSqlite3mcContract(env: env);

  final bench = _benchFlag == '1' || _benchFlag == 'true';
  test(
    '50k-row FTS benchmark (recorded; device budget p95 < 200 ms)',
    () async {
      final result = await runDbBenchmark(env: env, runId: _runId);
      emitBenchmark(result);
      // Also handed to `flutter drive` (build/integration_response_data.json).
      binding.reportData = {'zaghlol_db_bench': result};
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: bench ? false : 'benchmark off (--dart-define=ZAGHLOL_DB_BENCH=1)',
  );
}
