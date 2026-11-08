// T-007: 50k-row FTS benchmark on the CI host. Tagged `benchmark`: excluded
// from app-ci's static job, run (and gated) by db-platform.yml's host job.
// Budget (testing-strategy §5): FTS p95 < 50 ms on the CI host.
@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fts_benchmark.dart';

void main() {
  test('50k-row FTS benchmark (host budget p95 < 50 ms)', () async {
    final result = await runDbBenchmark(
      env: 'host-${Platform.operatingSystem}',
      runId: Platform.environment['GITHUB_RUN_ID'] ?? '',
    );
    emitBenchmark(result);
    final enc = result['enc']! as Map<String, Object?>;
    final rank = enc['fts_rank_ms']! as List<double>;
    final list = enc['fts_list_ms']! as List<double>;
    expect(rank[1], lessThan(50), reason: 'FTS rank p95 (ms) on CI host');
    expect(list[1], lessThan(50), reason: 'FTS list p95 (ms) on CI host');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
