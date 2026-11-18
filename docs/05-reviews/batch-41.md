# Batch 41 review (2026-11-18)

Reviewer: code-reviewer (Opus), code + security. Branch `batch/2026-11-18-41`; diffs `origin/main...origin/task/<b>`.

Tests run on the merged tree: `flutter test --exclude-tags benchmark,golden test/features/export_import test/features/capture` 376 pass (the `test/features/share` path in the brief does not exist); `packages/zaghlol_parsing` 1544 pass; `tools/catalog_build` 65 pass; backend `PriceAdapterTests` 18 pass (the other Infrastructure tests need Docker and failed locally for that reason only).

## T-156 PDF statement import (bank-agnostic, stays BLOCKED on samples): CHANGES_REQUESTED

Checked and fine:
- pdfrx 3.0.0, pdfrx_engine 0.9.3, pdfium_dart/pdfium_flutter 0.4.3 are all MIT. PDFium is downloaded at **build time** by the native-assets hook, pinned to a release and SHA-256 per archive (`pdfium_archive_integrity.dart`). The only HTTP code at runtime (`openUri`, file cache) is not used. The adapter uses `openData`: in memory, no temp file. No telemetry found.
- The picked bytes are zeroed in `finally`. The password is used once by `passwordProvider` and never stored or logged. The dialog uses `obscureText` with IME learning off and clears the controller. Errors are typed, and every `toString` is redacted.
- Amounts are `parseAmount` integer minor units in the mapping currency, with no conversion. Dates handle Arabic-Indic digits, English and Arabic month names, and the day-first flag. Invalid calendar days are rejected.
- Templates are stored in the encrypted `settings` table: geometry and roles only.
- `ImportedTxn.source` defaults to `csv`, so the CSV import is unchanged. `existingAt` now delegates to `existingBetween(t, t+1)`, with the same semantics as before.
- No user-visible strings are hard-coded: every label comes from the caller, and the missing l10n keys are listed in the task file. The UI is not wired yet, so nothing is visible to users.

Dedupe question: matching on (local day, direction, amount, currency) as a multiset is acceptable. Two identical coffees on the same day with one already recorded import exactly one. The CSV import uses the exact instant because it round-trips its own export, so a looser day key is the right choice for statements. The real risk is which existing rows are counted (see the major below).

Findings:
- **major (money/data)** `app/lib/features/export_import/application/import_statement_pdf.dart:253-266` (via `drift_csv_import_store.dart:52`, where `TxnQuery.statuses` is empty, meaning all statuses): `declined`/`reversed` SMS rows are counted as existing. A common case: a card is declined, then a retry succeeds, and only the decline SMS was captured. The statement's posted row is then dropped silently as a "duplicate", so a real expense is lost from the import. Required change: count only statuses that represent settled money (posted, and pending if the PO wants) in statement dedupe. Test: an existing declined row of the same day and amount must not suppress the statement row.
- minor `app/lib/features/export_import/presentation/statement_mapping_step.dart:72`: `_mapping` drops `numberLocale` (and any locale from the template or header detection), so it resets to standard on confirm. Pass it through.
- minor `packages/zaghlol_parsing/lib/statements/pdf/statement_rows.dart:195`: an unsigned value in a signed "amount" column becomes income. Document this in the mapping hint copy when the UI is wired.
- minor `app/pubspec.yaml:67`: `pdfrx: ^3.0.0` is a caret range while its neighbours use exact pins. Pin `3.0.0`. Note: the Android APK build with the native-assets hook has only been verified on the runner/GitHub, not locally.
- minor: the dependency ships PDFium in the APK/IPA while the feature is unreachable (BLOCKED). Accept for now, but track it.

## FU-b41-native: APPROVED

- Android `ocrPath = share id` for images only (`ShareIntakeHost.kt:26`). The id resolves through `ShareStoreImageSource` to the already-encrypted store entry, so no plain path reaches Dart and `sealImage` is not involved. `discardShare` is idempotent after OCR discards. Covered by a Kotlin test and a Dart lifecycle test.
- T-165 script: UNKNOWN is returned when the confirm button was not tapped or the flags are unreadable. Entries from a debuggable build on API 31+ are classified UNKNOWN, which is correct: AOSP lets adb back up debuggable apps whatever `allowBackup` says. Release is non-debuggable (the default release buildType). The manifest has `allowBackup=false`, and `data_extraction_rules.xml` excludes all 9 domains in both `<cloud-backup>` and `<device-transfer>`.
- Alias changes from prefix to exact (H&M, العزبي, AL BORG, EL ABD, كلود, الدهان, النبوي) are sound. The lint test has a negative case. The seed has the same rows with only the `match` field changed, no reordering, and the signature was rebuilt. catalog_build tests pass.
- nit `app/lib/features/capture/presentation/scan_confirm_screen.dart:96`: the comment "Android until its host lands" is now stale.
- minor: the manifest check in the script can only PASS on a debuggable build. A release-build run would report UNKNOWN. Note this in the script header.

## FU-b41-infra: APPROVED

- The prod guard `inputs.environment != 'prod' || github.ref == 'refs/heads/main'` is correct, and the README asks for the matching environment branch rule. minor (`backend-deploy.yml:47`): a prod dispatch from another ref skips the job silently instead of failing. Consider a failing guard step.
- The dry-run AAB strip works: `zip -d 'BUNDLE-METADATA/*'`, then `unzip -l | grep proguard.map|mapping.txt`, which fails the job if a mapping is still present. The upload reads only the stripped copy.
- GoldAPI karat check: decimal arithmetic, expected value = ounce-derived 24K × karat/24, 5% tolerance, and the whole fetch fails (falls back to another provider). The test uses a 21K value that disagrees with the ounce price. The fixtures stay within tolerance.
- The SA guidance (conditioned `projectIamAdmin`), the privacy doc and the link fix are fine.

## T-031-public: APPROVED

Docs only. No wording invented, and the sources are listed. Open point: check whether `hsbc.json` holds Arabic templates. Public pages say HSBC Egypt sends alerts in English only. This is a follow-up and does not block.

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|---|---|---|---|
| T-156 | `app/lib/features/export_import/application/import_statement_pdf.dart:253-266` (+ `drift_csv_import_store.dart:52`) | Statement dedupe must ignore `declined`/`reversed` existing rows (count settled statuses only) | Existing declined row with the same day, direction and amount → statement row still imported (`imported == 1, duplicates == 0`) |

## Lead delta check: T-156 dedupe (2026-11-18)

6d180e2d (about 20 production lines): `existingBetween(settledOnly:)` filters `posted`/`pending` through `TxnQuery.statuses`, and only the PDF import turns it on, so CSV import is unchanged. Soft-deleted rows were already excluded by the DAO. New test: declined and reversed rows with the same day, direction and amount → imported 2, duplicates 0; a posted row still blocks. Verdict: T-156 **APPROVED**. All four tasks approved.
- **FU-261:** batch-41 minors (see the report); T-165 must still be proven on a non-debuggable release-type build (Android 12+ lets adb back up debuggable apps); HSBC's Arabic templates need a decision (HSBC Egypt states its alerts are English only); T-156 waits for real statements, per-bank fixtures and the T-158 flow wiring.
