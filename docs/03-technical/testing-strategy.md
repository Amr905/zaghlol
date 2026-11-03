# Testing Strategy

The test pyramid is weighted heavily toward pure-Dart domain and parsing tests, which run on every PR in seconds. Device tests cover the platform seams; contract and privacy tests guard the data boundary.

## 1. Layers

| Layer | Tool | Scope | Gate |
|---|---|---|---|
| Domain unit | `package:test` | Money, cycles, safe-to-spend, pairing, offsets, subscriptions, voice grammar, chat intents, Zakah, ROI (spec numbers as cases) | 100% of `domain-algorithms.md` rules have named tests; coverage ≥ 90% lines in `zaghlol_domain` |
| Parsing fixtures | `package:test` + `tools/registry_lint` | ≥ 4 fixtures per template (AR, EN, edge) per FR-PAR-01/10/15; generic-parser unseen set; normalization tables | Every fixture passes; accuracy report ≥ SM-03 targets; no fixture may match two templates |
| Property-based | `glados` | Money arithmetic (no loss across split/allocate), amount parser round-trip in all digit/grouping styles, cycle boundaries for every payday 1–28 × every month | — |
| Data/DB | Drift in-memory + encrypted file tests | DAOs, FTS search (< 200 ms @ 50k rows benchmark), triggers/invariants, migration tests from every schema snapshot | Migration matrix green |
| Widget & golden | `flutter_test` + golden toolkit | Every screen in `ar` RTL + `en` LTR, light + Jade Night dark, text scale 1.0 and 1.3 (NFR-UX-02) | Golden diff = 0 |
| Accessibility | `flutter_test` semantics guidelines | Tap targets ≥ 48 dp, labels in both languages, contrast tokens | No violations |
| Native unit | JUnit + Robolectric (Kotlin), XCTest (Swift) | Capture Guard (shared golden cases with Dart), spool crypto, multipart SMS, notification extraction, App Intents perform() | Shared Guard cases identical across Dart/Kotlin/Swift |
| Integration (device) | `integration_test` on emulators/simulators + Firebase-free device farm (self-hosted or BrowserStack) | Onboarding → SMS injection (`adb emu sms send`) → transaction on Home < 10 s (app killed); notification capture; inbox scan 10k < 60 s; Shortcut intent → spool → visible; backup → restore cross-platform; purchase in sandbox; delete everything | Release-candidate gate |
| Privacy | `tools/privacy_scan`, recording proxy | (1) Sandbox contains no plaintext amounts/card digits/merchant/message text after the scripted session (FR-SEC-03). (2) Every outgoing request ⊆ BR-SYNC-03 allow-list; contribution payloads contain none of amount/date/card/IPA/phone (FR-CAT-09). (3) Ignored-card SMS leaves no trace (FR-CAP-02). (4) OS backup excludes app data (FR-SEC-05). | Must pass for every release |
| Backend unit | xUnit | Entitlement state machine, flag targeting, contribution filters, delta builder, signer | — |
| Backend integration | xUnit + Testcontainers PostgreSQL + WireMock (Google/Apple fakes) | Verify/ack flows, RTDN/ASSN processing incl. out-of-order and duplicates, restore re-binding, sign-in linking, retention purge | — |
| Contract | OpenAPI schema tests (both sides) | App DTOs ↔ `zaghlol-v1.yaml`; server rejects unknown fields | Breaking change fails CI |
| Store sandbox (manual + scripted) | Play license testers, App Store sandbox / StoreKit test config | Purchase, pending (cash method), renew, grace, refund, revoke, restore on a new phone, cross-platform with sign-in | Before each release that touches Gold |
| Security | MobSF static scan, dependency/SCA scans, ZAP baseline on staging API, manual pen test before launch | MASVS L2 / ASVS L2 checklists | No high findings open |
| Performance | Benchmarks in CI on a reference profile + manual on reference device (2023 Samsung A-series, iPhone 12) | NFR-PERF-01…06 budgets: parse < 10 ms, cold start < 2 s, charts < 300 ms, voice < 2 s, battery check over 24 h | Regressions > 10% fail |
| Usability (FR-ONB-09) | Moderated tests, 5 users/platform | Time to first value ≤ 60 s; 4 of 5 unaided | Before launch |

## 2. Test data rules
- **SMS and notification fixtures are synthetic only.** Real samples from the product owner (OQ-04/18) are **converted** into synthetic fixtures by changing names, digits and references; the originals are never committed.
- Each template's fixture set includes Arabic-Indic digits, a missing optional field, the foreign-currency variant and declined/reversal variants where the bank sends them.
- **Seed builders:** `TestWorld` creates accounts, transactions, cycles and catalog in one call for domain and widget tests.

## 3. Device matrix

| Platform | Versions | Devices |
|---|---|---|
| Android | 8.0 (API 26), 10, 13, 14, 15, 16 | Samsung A-series (reference), Xiaomi/Redmi (aggressive battery management), Oppo/Realme, Pixel, dual-SIM device (EC-11) |
| iOS | 17.x, 18.x, 26.x | iPhone 12 (reference), iPhone SE 2/3 (small screen), a recent Pro |
| Languages | Arabic (Egypt) default, English; text scale 100% / 130% | — |

## 4. Definition of Done hooks
Each task's DoD (CLAUDE.md §7) adds the relevant rows above. Parsing tasks must include fixtures, and C4 tasks must include privacy tests where data is touched.

## 5. Benchmarks (CI budgets)
- `parse_benchmark`: 10k mixed fixtures, mean < 2 ms on CI host (≈ 10 ms budget on device).
- `scan_benchmark`: 10k-message inbox through the pipeline < 30 s on the CI host.
- `search_benchmark`: FTS on 50k transactions < 50 ms on CI host.
- `chart_benchmark`: 2 years of data for each chart query < 100 ms on CI host.

## 6. Privacy contract test (detail)
A debug-only `RecordingHttpClient` wraps `BackendClient` in integration tests and records every request. The assertion checks each JSON body against a JSON Schema generated from the BR-SYNC-03 allow-list, with `additionalProperties: false`. A deny-list scan also looks for any fixture amount, card digits, IPA or phone pattern.
