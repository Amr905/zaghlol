# Batch 32 review: follow-up sweep

Reviewer: code-reviewer (Opus), covering code and security. Branch `batch/2026-11-17-32`. Each task is diffed with `git diff origin/main...origin/task/<b>`. The Review "Keep saves nothing" fix is out of scope here; it gets its own delta check.

Tests run on the merged tree:
- `packages/zaghlol_parsing`: 1510 passed.
- `tools/catalog_build`: 59 passed. This includes `--check`, which shows the committed seed matches the CSV and the dev key.
- `packages/zaghlol_catalog`: 38 passed.
- `backend/tests/Zaghlol.Application.Tests`: 1057 passed.
- App (`flutter test --exclude-tags benchmark,golden`) on onboarding, insights, home, capture, core/ui, gold (paywall), ingestion and budget: 1046 passed. The one reported failure is only that `test/features/paywall` doesn't exist; the paywall tests live in `test/features/gold`.
- `Zaghlol.Infrastructure.Tests` (Support) need Docker, so GitHub runs them.

## FU-sweep-be32 (C4: support / entitlements): APPROVED

Security:
- Detach now runs its link check and its source-audit check in phase 1, under the purchase row lock and before any store call. A refused detach writes an audit row with `refused` / `not_run`.
- Phase 2 runs the same checks again, so a link that changes between the two phases is still refused.
- The 24 h unfreeze lock and the 24 h freeze lock are both compared against the database's `now()`, the same clock that writes `audit_log.at`. A fast app clock can no longer shorten either lock.
- No new data reaches the backend, and nothing new is logged.

Tests: the detach test now asserts zero store calls and a `not_run` audit row. A new test skews the app clock by 48 h, and the unfreeze is still refused. Both tests fail without the fix.

- minor `SupportActionService.cs:310`: `frozen_until` is still set from the app clock (`now + FreezeLength`), while the lock edges now use the database clock. This is harmless, because the database-clock edge is the one that gates the unfreeze.

## FU-sweep-parse32: APPROVED

- **Registry version.** The manifest, `guard_base.json` and `spike_guard_base.json` all move to `registryVersion` 4. Each changed template's `version` is bumped too.
- **InstaPay confidence.** Every `synthetic-unverified` InstaPay template is now 0.9. Two groups stay at 0.95:
  - `cib.instapay_out.ar`, which is `po-sample`, so 0.95 is correct.
  - The older `instapay.*` SMS templates. They have no `source` field and predate batch 31, so they are outside FU-251.
- **Seed signature.** The seed is re-signed with kid `s0000a`, the dev key. The tool refuses any non-dev kid, release builds reject dev kids, and no production key is in the repo.
- **Contact wallet names.** The bare "Contact" wallet name is replaced by "Contact Financial" and "Contact Credit", and a test covers this.
- **FX hold-out and settlement tests.** The FX hold-out cases are new. The settlement tests now make positive assertions and no longer pass vacuously under `if (r is ParseGeneric)`.

- minor `tools/catalog_build/test/broad_keywords_test.dart:7`: the test checks only `catalog_curated.csv`. It doesn't check the generated `catalog_seed.csv`, but `--check` keeps the two files in sync, so this is acceptable.
- minor `generic_fx_holdout_test.dart:33`: the else-branch accepts a foreign-currency pick as long as it's flagged, so the test can't tell a fix from a regression in amount choice. Assert which cases are known misses.

## FU-sweep-core32: APPROVED

The start-up re-parse now runs inside `IngestionPauseGate.guard`. While a restore is in progress the gate refuses the job, it returns null, and the rows are retried on the next start. The test fails without the fix.

- minor `startup_reparse.dart:45`: the whole job is guarded as one write. A long re-parse can therefore hold the gate past the 30 s `pause` timeout, and the restore then reports busy. The behaviour is safe (no data loss) but unfriendly. Guarding per batch would fix it.

## FU-sweep-ui32: APPROVED

- **Pager height measurement.** I checked whether it can loop:
  - `_MeasureHeight` sits inside an `OverflowBox` with `maxHeight: infinity`, so a page's measured height doesn't depend on the pager's height. There is no feedback loop.
  - The render object reports only when the height changes, and `_setHeight` ignores equal values.
  - The test's `pumpAndSettle` would time out if the measurement looped.
- **Budget bar colour.** `overLimit` keeps the old terracotta for the budget bar at or over the limit. Spending charts use a neutral slate, and the ramp no longer contains the over-limit colour.
- **Strings and layout.** No hard-coded strings were added. The onboarding actions and the feed row are RTL-safe (directional insets, `BankNameText`).

Minors:
- `home_screen.dart:229`: `_pageHeights` is never pruned. When the currency count drops, a stale taller height keeps the pager too tall. Also, pages more than one away from the current page aren't measured, so the pager can jump in height on swipe.
- `store_timeout_test.dart`: the test covers `withStoreTimeout` but not that `goldOffersProvider` ends in the error state ("prices failed").
- `onboarding_parts.dart:229`: the pinned actions column has no scroll fallback. Very tall actions at a large text scale could overflow.

## TEST-explorer3: APPROVED

The task changes only integration tests and CI wiring. The emulator SMS are synthetic. `_say` prints counts and labels only, never an SMS body. The `ci/TEST-explorer3` branch defaults are acceptable; drop them once the task is done.

## Fix list

None. No blocker or major finding touches money, security, privacy or data loss. The minors above go to a follow-up.
