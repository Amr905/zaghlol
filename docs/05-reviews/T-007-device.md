# T-007: device timings (encrypted SQLite + FTS5 trigram)

Manual on-device run for ADR-002 ("Spike results (T-007)"), from the T-007 design note. CI already proves the contract and records emulator/simulator numbers (`.github/workflows/db-platform.yml`). Only a real device in **profile** mode shows whether FR-TXN-01 (search over 50k transactions < 200 ms) holds. Fill both rows **before the first release candidate** (T-171 checklist).

The test uses only synthetic data and a random key from `Random.secure()`. It never prints the key, the sentinels or any row text. It writes only under the app's temp directory and deletes everything afterwards.

| Field | Android | iPhone |
|-------|---------|--------|
| Device model | _e.g. Galaxy A15 / Redmi Note 13_ | iPhone 12 |
| SoC / RAM | _e.g. Helio G99, 6 GB_ | A14, 4 GB |
| OS version | _Android 12+_ | _iOS 17+_ |
| App commit | _SHA_ | _SHA_ |
| Flavor | devNoSms | dev |
| Tester / date | | |
| Verdict (contract passed, p95 < 200 ms) | _PASS / FAIL_ | _PASS / FAIL_ |

## Reference devices

- **Android:** a mid-range phone common in Egypt, Android 12+, 4–6 GB RAM, Snapdragon 6-series or Helio G-class (for example Galaxy A15/A25 or Redmi Note 12/13). Which model counts as the reference is PO decision (2) in the design note.
- **iPhone 12 (A14):** needs a Mac with Xcode and a signing team (PO decision (1); recommendation (c) through (a)).

## Run (from `app/`)

Android, from the PO's Windows PC (Flutter and the Android SDK are installed). Enable USB debugging, connect the phone, then find its id with `flutter devices`:

```sh
flutter drive --profile --flavor devNoSms \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/db_platform_test.dart \
  --dart-define=ZAGHLOL_DB_BENCH=1 \
  --dart-define=ZAGHLOL_DB_ENV=android-device \
  -d <id>
```

iPhone 12, on a Mac with Xcode. Open `ios/Runner.xcworkspace` once, select a signing team for the Runner target (`dev` configurations) and trust the developer profile on the phone. Then:

```sh
flutter drive --profile --flavor dev \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/db_platform_test.dart \
  --dart-define=ZAGHLOL_DB_BENCH=1 \
  --dart-define=ZAGHLOL_DB_ENV=iphone-12 \
  -d <id>
```

Each run takes a few minutes. Keep the phone unlocked, on charge, and with no other heavy app open.

## Record

1. Every contract test must pass (`All tests passed!`). Any failure is a **FAIL**: stop and attach the console output.
2. Copy the two lines that start with `ZAGHLOL_DB_BENCH {` and `ZAGHLOL_DB_FINDINGS {` from the console, with the device model, OS version and app commit, into the table below. The same benchmark JSON is also in `build/integration_response_data.json`. Neither line contains data or keys.
3. Put the numbers into ADR-002's "Spike results (T-007)" table, replacing **PENDING**.

| Device | `fts_list_ms` p50 / p95 / max | `fts_rank_ms` p95 | `open_cold_ms` | `open_warm_ms` | `ratio_list_p95` (enc/plain) | `pbkdf2_open_ms` |
|--------|------------------------------|-------------------|----------------|----------------|------------------------------|------------------|
| Android: _model_ | | | | | | |
| iPhone 12 | | | | | | |

Raw lines:

```
(Android) ZAGHLOL_DB_BENCH {...}
(Android) ZAGHLOL_DB_FINDINGS {...}
(iPhone 12) ZAGHLOL_DB_BENCH {...}
(iPhone 12) ZAGHLOL_DB_FINDINGS {...}
```

## If a device p95 is 200 ms or more

Record the number anyway and mark the verdict FAIL. Per ADR-002, the fallbacks to try, in this order, are:
1. `cache_size` and page-size tuning;
2. changing the query shape;
3. sqlite3mc's default ChaCha20-Poly1305 cipher. This conflicts with the literal "AES-256" in FR-SEC-01, so it needs a PO decision first.
