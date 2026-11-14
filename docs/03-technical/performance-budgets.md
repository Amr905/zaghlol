# Performance budgets (T-173, NFR-PERF-01..06)

All timing assertions are tagged `benchmark`, are excluded from normal runs
(`--exclude-tags golden,benchmark`, `dart test --exclude-tags benchmark`) and run
serially in app-ci's `perf` job (`-j 1`); numbers are printed in the log and the
job summary. Run locally: `cd app && flutter test --tags benchmark --concurrency=1`
and `cd packages/zaghlol_parsing && dart test --tags benchmark -j 1`.

| NFR | Budget | Benchmark (host, CI-enforced) | Device check |
|-----|--------|-------------------------------|--------------|
| PERF-01 parse | < 10 ms/message | `parsing_pipeline_test` "benchmark: mean parse time" (2 ms), `generic_parser_test` (10 ms), `registry_lint_test` per-message, `capture_guard_test` performance group, `registry_loader_test` (150 ms for 80 institutions), categorizer p95 25 ms | Reference mid-range Android (2023 Samsung A-series): record in release notes |
| PERF-03 scan | 10,000 SMS < 60 s, first progress < 10 s | `inbox_scan_benchmark_test`, `ingest_benchmark_test` | same device, real inbox size |
| PERF-04 charts | < 300 ms, 2 years of data | `chart_benchmark_test` | profile-mode frame timing, 60 fps scroll |
| PERF-05 voice | < 2 s after speech ends | `voice_parser_test` budget + hostile (parse portion only) | on-device speech_to_text latency, manual |
| Search (FR-TXN-01) | p95 < 200 ms on 50k rows | `transactions_search_benchmark_test`, `core/db/fts_benchmark_test` | db-platform emulator jobs |
| PERF-02 cold start | < 2 s to home | not host-measurable | Manual: `flutter run --profile --trace-startup` / `adb shell am start -W` on the reference device, median of 5 cold starts |
| PERF-06 battery | < 1 %/day attributable | not host-measurable | Manual 24 h check: `adb shell dumpsys batterystats` attributed to the app, capture on, screen off |

Budgets in the tests are deliberately a small multiple over measured host
numbers (the dev-box numbers are printed); a regression of more than 10 % over a
documented budget is a review finding, and a budget is only raised with a note
here.
