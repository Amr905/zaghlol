# Batch review — batch 81 (`batch/2026-11-26-81`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security/data for the C4 task) |
| Date | 2026-11-26 |
| Diff | `git diff origin/main...a562b37d` (main = 7549c4f9), 36 files |
| Tasks | T-288 (C2), T-289 (C4, financial logic), T-290 (C3, Kotlin), T-291 (C2) |

## Checks run (merged tree a562b37d)

| Check | Result |
|-------|--------|
| `flutter pub get --enforce-lockfile` | OK |
| `flutter analyze` (app) | No issues |
| `dart format --set-exit-if-changed lib test` (app, zaghlol_domain) | clean |
| `flutter test -x golden test/features/insights test/features/mascot test/features/transactions test/features/budget test/features/export_import test/features/widgets_bridge` | 1128 passed, 0 failed |
| `flutter test -x golden test/features/ingestion test/core/db` | 1130 passed, 1 skipped, 0 failed |
| `dart test test/transfers` (packages/zaghlol_domain) | 62 passed |
| `flutter test test/features/insights/presentation/v2/trends_golden_test.dart` (regenerated `insights_v2_trends_exchange_*`) | 10 passed |
| Kotlin (`OcrMergerTest`) | not compiled here; GitHub `app-ci` on `ci/T-290` @ `6a8debf7` (same commit as the task branch): "kotlin unit tests (Gradle)" success. New tests also traced by hand below |

Follow-ups start at FU-391. **One major (T-290).**

---

## T-288 — Exchange chart colours, exchange selection count, no Rive preload under reduce motion (C2) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Contrast ≥ 3:1 for both colours on `#FFFFFF` and `#141414`; not the accent | PASS | `exchange_colors_contrast_test.dart`, run. Recomputed independently: `#7F6FCB` 4.17 / 4.42, `#3F86B5` 3.97 / 4.64 (WCAG relative luminance) |
| Exchange goldens regenerated | PASS | `insights_v2_trends_exchange_{ar,en}_{light,dark}.png` (regen `42ab3f91`), run |
| One exchange row selected → "1 selected" | PASS | `exchange_row_test.dart` (en "1 selected", ar «اخترت ١»), run |
| Reduce motion on → no preload | PASS (with the test seam) | `rive_preload_test.dart`, run |

### Code
Palette swap is a constant change; theme doc row added with the "Lead assumption pending UX sign-off" label. `ew` now satisfies `bw/2 + 2 + 2·ew + 1.5 ≤ slot/2` except under the 1 px floor, so the batch-80 overflow nit is fixed for every realistic slot. `_selectedRowCount` subtracts one per fully selected loaded pair; falls back to the leg count while exchanges load (brief "2 selected" flash at worst).

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | minor | `app/lib/features/mascot/presentation/rive_mascot.dart:158-166`, `app/lib/main.dart:78` | The flag is read in `main()` right after `ensureInitialized`, before the first frame. On Android the embedder sends accessibility features when the `FlutterView` / accessibility bridge attaches, which can be after `main()` runs, so `disableAnimations` may still read `false` and the preload runs anyway. The in-app reduce-motion setting is not consulted at all (builder assumption). Not verifiable here (device). | FU-391: on a device with "Remove animations" on, confirm no Rive load; if the flag is not yet set, defer the preload to the first frame (`addPostFrameCallback`) or to the first mascot provider read, where the in-app setting is also known. |
| 2 | nit | `app/lib/features/mascot/presentation/rive_mascot.dart:154-156` | `load` is a test-only seam on a production function signature. | Optional: `@visibleForTesting` comment or move the seam to a provider. |
| 3 | nit | `chart_palette.dart:17-21`, `05-theme-2026.md:87` | "From the category ramp": the two colours are darker shades of ramp `#9185D0` / `#5BA3C9`, not ramp members. | Reword to "darker shades of the ramp's violet/blue" at UX sign-off. |

---

## T-289 — Per-currency balance-rise threshold, cold-start exchange overlay, statement vs manual exchange (C4, financial logic) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| FU-366 JPY/KWD thresholds, no-rate fallback | PASS | `exchange_hints_test.dart` group "FU-366" (KWD 160 EGP → 3125, JPY 0.33 → 1516 rounded up, USD 50 → 1000, no rate / rate 0 / EGP → 500 major, floor), run |
| FU-366 old inbox-scan jump raises nothing; recent one still asks once | PASS | `exchange_jump_test.dart` "an old jump … a recent one still asks once", run |
| FU-366 store rate lookup (direct, inverse, none) | PASS | `exchange_jump_test.dart` "the store reads the stored rate…", run |
| FU-369 cached = live for a cycle with an exchange | PASS | `cycle_repository_exchange_test.dart` (exchangedIn/Out, income, spend for EGP and USD), run |
| FU-370 statement debit matching a manual exchange leg → duplicate, no spending | PASS | `drift_statement_import_test.dart` "FU-370 …" (duplicates 1, no `pdf` expense row), run. No production change needed: confirmed |
| ≤ 3 negative proofs | PASS | 3 (old jump, no rate, floor) |

### Code (traced)
- **Integer math.** `balanceJumpMinMinor` = ceil(500 · 1e9 · 10^exp / egpPerUnitE9) in `BigInt`; result > `Money.maxMinor` → plain 500 major; below the floor → floor (1 major; 100 units for exponent 0). Checked: KWD 3125, JPY 1516, USD 1000 by hand. No `double` anywhere.
- **Rate direction.** `fx_rates` stores "1 base = rate_e9/1e9 quote" (`financial_c.drift:92`). Direct row `base = X, quote = EGP` is EGP per X = `egpPerUnitE9`; inverse row `base = EGP, quote = X` is X per EGP, inverted as `1e18 / rate` in `BigInt` (result 0 or > 2^53 → null → plain rule). `ORDER BY (base = 'EGP')` puts the direct row first; `PRIMARY KEY(base, quote)` means one row per direction. Correct both ways, tested both ways.
- **Nothing converted or stored.** The rate only sizes the threshold; the review payload still carries the rise in the account's own currency. `BalanceJumpFacts` gains one optional field; no schema change.
- **Age cap.** `_checkBalanceJump` returns when `asOfMs < now − 14 d` before any DB read; `_recordBalance` still records the old balance, so the next (recent) report compares against it and is asked normally (the test proves the recent jump still asks once). A recent real jump can only be hidden if its own message timestamp is > 14 days old (a delayed spool message), which is the documented builder assumption.
- **FU-369.** `cachedTotals` now goes through the same `_withExchanges` overlay as the closed-cycle cached path of `totals`, with the same `'*'` → all-accounts mapping. Income/spend in the cache still exclude exchange legs, so no double count.

### Security / privacy
| # | Sev | Area | Note |
|---|-----|------|------|
| S1 | Info | Rate trust | `fx_rates` are backend display rates. A wrong rate can only move the threshold: a huge rate pins it at the floor (more "did you exchange?" questions), a tiny one raises it up to ~5·10^13 minor (question effectively off). No money is created, moved or converted; worst case is one extra or one missing review item per jump. No action. |
| — | — | Logging / egress | No new logging, no network, nothing leaves the device. SQL uses bound variables. |

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | nit | `packages/zaghlol_domain/lib/transfers/exchange_hints.dart:48` | `'EGP'` is a literal as the threshold's home currency (also `drift_ingest_store.dart:468-471`). Fine for this app, but it duplicates the "500 EGP" assumption in two layers. | Optional: one `balanceJumpHomeCurrency` constant used by both. |

---

## T-290 — Android OCR merge minors FU-371/376/377/378 (C3) — **CHANGES_REQUESTED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| One new test per item | PASS | FU-371 `arabicLineOverStrongAndWeakLines…`, FU-376 `arabicNoiseDigitsDoNotDisagree…`, FU-377 `noiseDriftedVertically…`, FU-378 `confidenceBarsAreInclusiveAtExactly045AndExactly060` |
| Existing tests unchanged and passing in CI | PASS | No existing test edited; CI Kotlin unit tests green on `6a8debf7` |
| PO receipt (436) still holds | PASS (traced) | `latinReceipt` lines are all strong, so `replacing` stays empty (FU-371 path unused); every `araNoise` line < 0.60 shares a row with its strong line and is gated out as before; `عميل نقدى` (0.67) has no strong digit line overlapping (FU-376 path unchanged), so "Name: عميل نقدى" and all 7 ML Kit lines incl. "Amount Due 436.00" are kept |

Hand trace of the four new tests: all four produce the asserted output (FU-376 test: both ML Kit lines match the Arabic line at 0.9, `strongAmountOverlaps` true via "382.46", no words survive the digit filter → `["Net Sales", "382.46"]`; FU-377 test: drifted noise shares 15/40 = 0.375 ≥ 0.3 of the row → gated; the row below has `h ≤ 0` → kept).

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | **major** | `app/android/app/src/main/kotlin/app/zaghlol/platform/ocr/OcrMerger.kt:127-131` | **FU-371 de-dup drops a real amount.** A token is removed when the kept strong line's text *contains it as a substring*, and the filter runs over the Arabic text after the weak lines' ML Kit digits were appended (`digitsWin`). Failing input: `latin = [line("Ref 1436", 0,0,200,30), line("Jl 436", 0,30,200,60, 0.3)]`, `arabic = [line("الإجمالي ٤٣٦", 0,0,200,60, 0.85)]`. Before T-290: `["Ref 1436", "الإجمالي 436"]`. Now: `"436"` is dropped because `"Ref 1436".contains("436")` → `["Ref 1436", "الإجمالي"]`; the total is lost. Same with any ASCII digits Tesseract returns itself, and with Arabic words that are substrings of a longer Arabic token in a strong line (`الكل` vs `الكلي`). | Compare whole tokens, not substrings: drop an Arabic-line token only when it equals (after the same trim and `normalizeDigits`) a token of a kept strong line. Never drop a token that came from `digitsWin` unless that exact token is in the strong line. Add the failing input above as a test. |
| 2 | minor | `OcrMerger.kt:68-71` | FU-376 suppresses the Arabic amount when *any* strong line with an ASCII digit overlaps the Arabic box, not only an amount. E.g. `latin = ["Total Amount" (0,0,200,30), "Ref 12" (210,0,400,30)]`, `arabic = ["الإجمالي ٨٥٫٥٠" (0,0,400,30, 0.85)]` → `"Total Amount الإجمالي"`, `"Ref 12"`; 85.50 lost (before: appended). Matches the task's prescribed rule, and needs a label, an Arabic-digit amount and an unrelated digit line on one Tesseract box, so not blocking. | FU-392: require the strong line's digit token to match `AMOUNT` with a decimal part (or sit horizontally over the Arabic amount token) before it wins. |

---

## T-291 — Export pair-kind batching, widget line-two length rule, voice comment (C2) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| FU-388 one query for N pairs | PARTIAL | `financial_c_daos_test.dart` checks results (`{'p1': 'manual'}`, unknown id absent, empty input) only; no query count and no > 500 chunk case. Code read: one `IN` query per 500 distinct ids, data layer only; the provider no longer loops `byId` |
| FU-387 long payday text + hint → hint dropped, payday kept | PASS | `widget_snapshot_builder_test.dart` "FU-387 …" (also every rolled day), run |
| FU-373 comment | PASS | `speech_to_text_port.dart:108-110`, comment only |

### Code
`widgetMaxLineChars = 120` mirrors `WidgetView.MAX_TEXT_CHARS` (`WidgetSnapshotStore.kt:49`), both counted in UTF-16 units (Dart `String.length`, Kotlin `take`), LRI/PDI included. Contract row updated in `platform-channels.md`.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | minor | `app/lib/features/widgets_bridge/domain/widget_snapshot_builder.dart:140-143` | The 120-unit rule guards native storage truncation, not the visual clipping FU-387 was about (2×1 widget ellipsizing «٧ أيام على القبض · + USD, EUR +١», ~35 units). The rule as scoped will practically never fire. | FU-393: keep the device check of line two on the smallest widget (ar/en); if it ellipsizes, add a per-size rule (e.g. hint only on the larger sizes) in native layout. |
| 2 | minor | `app/test/core/db/financial_c_daos_test.dart:774-775` | AC asks to prove one query for N pairs; the test proves only results. The 500-chunk boundary is untested. | FU-394: test with 501+ ids (all found) and, if cheap, count statements via a query interceptor. |

---

## Follow-ups (FU-391 onwards)

| FU | Owner | Item |
|----|-------|------|
| FU-391 | T-288 follow-up (device pass) | Rive preload under "Remove animations": confirm the platform flag is set when `main()` reads it; else defer the check; honour the in-app reduce-motion setting. |
| FU-392 | T-290 follow-up (native) | FU-376 rule: only a strong *amount* token (not any digit, e.g. "Ref 12") suppresses the Arabic amount append. |
| FU-393 | T-284/T-291 follow-up (device pass) | Widget line two with the currency hint on the 2×1 size in ar/en; per-size rule if it ellipsizes. |
| FU-394 | T-291 follow-up (tests) | `kindsByIds`: test > 500 ids and the query count. |

Major for the fix round: **T-290 #1** (token equality in the FU-371 de-dup; add the failing input as a test).

### Lead delta check (fix81)

- T-290 major #1 fixed in `OcrMerger.kt` (about 10 production lines): the FU-371 de-duplication drops an Arabic token only when it equals a kept strong line's token after the same trim and `normalizeDigits`; the substring `contains` check is gone. New test `deDuplicationDropsOnlyWholeTokensSoASubstringAmountSurvives` uses the reviewer's failing input (`Ref 1436` + `Jl 436` + `الإجمالي ٤٣٦` → `["Ref 1436", "الإجمالي 436"]`); it fails on the old substring rule by construction (436 ⊂ 1436). Compiled and run by CI only. **T-290: APPROVED.**
