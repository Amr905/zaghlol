// T-007: 50k-row FTS benchmark on the CI host. Tagged `benchmark`: excluded
// from app-ci's static job, run (and gated) by db-platform.yml's host job.
// T-016 §8 (FU-069): the hard gate is the real NFR, FR-TXN-01 search
// p95 < 200 ms; the testing-strategy §5 host figure (50 ms) is a printed soft
// warning. Each figure is the median of 3 measured passes after one warm-up.
@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fts_benchmark.dart';

/// FR-TXN-01: search p95 < 200 ms at 50k rows (hard gate).
const double ftsGateMs = 200;

/// testing-strategy §5 host figure: printed as a warning only.
const double ftsSoftBudgetMs = 50;

void main() {
  test(
    '50k-row FTS benchmark (gate p95 < 200 ms, FR-TXN-01; soft 50 ms)',
    () async {
      final result = await runDbBenchmark(
        env: 'host-${Platform.operatingSystem}',
        runId: Platform.environment['GITHUB_RUN_ID'] ?? '',
      );
      emitBenchmark(result);
      final enc = result['enc']! as Map<String, Object?>;
      final gated = {
        'fts_rank_ms': enc['fts_rank_ms']! as List<double>,
        'fts_list_ms': enc['fts_list_ms']! as List<double>,
        'short_prefix_ms': enc['short_prefix_ms']! as List<double>,
      };
      for (final MapEntry(:key, :value) in gated.entries) {
        if (value[1] >= ftsSoftBudgetMs) {
          // ignore: avoid_print
          print('ZAGHLOL_DB_WARN $key p95=${value[1]} >= $ftsSoftBudgetMs ms');
        }
      }
      for (final MapEntry(:key, :value) in gated.entries) {
        expect(
          value[1],
          lessThan(ftsGateMs),
          reason: '$key p95 (ms), FR-TXN-01',
        );
      }
      expect(enc['short_prefix_hits'], greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
