# Batch 31 review (code + security)

Diff: `git diff origin/main...origin/batch/2026-11-16-31`. Reviewer: Opus (the batch has a C4 task).
Tests run on the merged tree:
- `flutter test --exclude-tags benchmark,golden` over test/ingestion, features/{ingestion,transactions,capture,settings,insights,categorization,gold,accounts,home,onboarding} and test/core: 2818 passed.
- `packages/zaghlol_parsing` `dart test`: 1502 passed.
- `tools/registry_lint` `dart test`: 8 passed.

Native code was read, not built. The device-flows emulator run on `ci/batch-31` is with the Lead.

## task/SMS-device (C4, native ingestion + security): APPROVED

**Re-parse at start.** It reuses the T-076 `ReparseJob`:
- Conditional status updates. It never deletes, and it never touches user-verified rows, amounts or categories.
- Every examined row is stamped, so a second run examines 0 rows (tested).
- The work is bounded: 50 rows per page, at most 5000 rows, and it yields between messages.
- It is idempotent next to the drain and scan.

**HSBC regex sender.** `expandSenderRegex` handles a closed grammar only. Anything else returns null (live capture only), and the output is capped at 64 entries. The inbox query stays `address IN (...)` and every row still goes through the Guard, so the scan does not read the whole inbox.

**Fix button.** Wired by default, best effort.

**SMS-NODIGIT.** The rule is identical in Dart, Kotlin and Swift: step 0, after the fold, before the sender check. The golden has `nodigit.*` cases.

**Diagnostics.** Two compile-time gates: `BuildConfig.SMS_DIAG` (dev only, otherwise `NONE`) and `kIsDevBuild`. They store a sender label and a stage only, and phone numbers show as `(number)`. Kotlin has no log calls.

**Workflow.** Adds no permissions. Logs hold sender ids and counts only.

Findings:
- minor `app/lib/features/capture/application/capture_providers.dart:218`: `reparseOnStart` writes straight to the captured `db`. It does not go through `IngestionPauseGate` (FU-139), unlike the inbox scan, which uses `ProviderIngestStore(gate:, rebuildPerBatch:)`. A restore started while the start-up job runs is not shielded. The window is short and the job only promotes review rows, so I see no loss of user data. Follow-up: wrap each message write in `gate.guard`, or stop when `gate.paused`.
- minor `app/android/.../platform/diag/SmsDiag.kt:83`: the counter file is plain text, and the whole file is rewritten on every record (once per inbox row during a scan). It is dev-only and holds no bodies, so this is acceptable. Follow-up: batch the writes.
- minor `app/integration_test/sms_device_test.dart:222-227`: the test counts the framework `!semantics.parentDataDirty` assertion instead of failing on it. That final commit has never run on a device. Follow-up: find the screen that raises the assertion.

## task/SMS-improve (registry + generic + categorization): APPROVED

**Registry.**
- `registryVersion` is 3. The 48 new templates are `version: 3`.
- Only `cib.instapay_out.ar` is `po-sample`. All others are `synthetic-unverified`, with 4 fixtures each. registry_lint is green.

**Hotlines.** A number with no currency marker never becomes an amount (tested with `19666`).

**Generic extractor.** `_withClock` produces a wall clock. `_occurred` turns it into UTC through the zone offset, so the time is correct.

**Categorization.** It goes through the existing categorizer. The batch changes only the seed, so it cannot override a category the user chose (the source stays `rule`/`catalog`). The seed signature was regenerated.

Findings:
- minor `app/assets/registry/institutions/*.json` (new `instapay_*` entries): the unverified templates use `baseConfidence` 0.95. Existing `synthetic-unverified` templates use 0.9. Follow-up: use 0.9 so that guesses are not auto-saved with more confidence than verified shapes.
- minor `tools/catalog_build/data/catalog_curated.csv:373,388,398`: these entries are broad and will mis-categorize some merchants:
  - alias `CLAUDE` as a prefix
  - keyword `محطة` → transport
  - keyword `food` → dining

  Follow-up: narrow them (for example `CLAUDE.AI`, `محطة وقود`).

## task/UI-po31 (acronyms, card digits, Keep, charts free): APPROVED

**Keep.**
- It re-reads the payload from the DB and saves exactly `GenericSuggestion`: a `Money` amount in minor units, its currency (with `allowForeignCurrency`), direction, date, merchant and last-4. It invents no field.
- The category comes from the auto categorizer. A stale or resolved item returns false.
- The button is disabled, with a reason, when there is no amount, or when the bank, kind or channel is unknown.

**Card digits.** `formatCardTail` wraps the tail in an LRI/PDI isolate with Western digits. It is used for review rows, transaction rows, card detail, merge, ignore rules and scan results.

**CHARTS-FREE.** `static bool` is mutable, but nothing in `lib/` writes it (only tests do). There is no remote or runtime path, so release builds cannot flip it. The paywall copy now sells "deeper insight", and that is still Gold-gated (`ExplanationTier.deep`), so the copy is honest.

Findings:
- minor `app/lib/features/ingestion/presentation/review/review_screen.dart:298-311`: the snack bar overflow is **real**. In English at 1.3x, the `SnackBarAction` "New message template" overflows by 72 px (`RenderFlex overflowed by 72 pixels`). Arabic is clean. The Keep test swallows this with `tester.takeException()` (`review_screen_test.dart`, Keep 1.3x test), and the same snack bar follows one-tap Confirm. Not money or security, so it does not block. Fix list below, at the Lead's request.
- nit `app/lib/features/gold/application/gating.dart:143`: a mutable global. Make it `const` and let tests override it through a provider or a `@visibleForTesting` setter.

## Fix list

No blocking findings. Non-blocking item requested by the Lead:

| Task | File:line | Required change | Test to add |
|---|---|---|---|
| UI-po31 (minor) | `app/lib/features/ingestion/presentation/review/review_screen.dart:298-311` | Avoid the 72 px overflow at 1.3x in English. Shorten the action label (e.g. a "Teach" key), or move "make a template" out of the `SnackBarAction` (`behavior: floating` with the action on its own line, or a separate button). | In the Keep 1.3x test, after the tap and `pump`, `expect(tester.takeException(), isNull)` in en and ar |
