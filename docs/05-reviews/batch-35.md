# Batch 35 review (code + security)

Branch `batch/2026-11-17-35`. Reviewer: code-reviewer (Opus), 2026-11-17.

Tests run on the merged tree: `flutter test --exclude-tags benchmark,golden` over notifications, budget, recurring, transactions, categorization, capture, home, onboarding, ingestion, gold, a11y, core/backend: **2156 passed, 0 failed** (`test/features/paywall` doesn't exist, so it was skipped). Backend `Zaghlol.Application.Tests` 1057/1057 and `Zaghlol.Workers.Tests` 30/30 passed. Docker tests: backend-ci green 44118802438.

Merge resolution in `capture_providers.dart`: both changes are present. `afterBatch: ref.read(afterIngestProvider)` is used on both the coordinator and the scan service, and `afterIngestProvider` still runs `duplicateCheckProvider` first. `backfillEventCategories(...)` is started after `reparseOnStart`. OK.

## FU-b35-wiring: APPROVED

What I checked:
- **Idempotency:** each step dedupes in its own store (fired alerts per threshold per period, reminders keyed by item and due date). `onRemoved` returns null when no pair is left, so the double calls from bulk delete plus the hook are safe.
- **Overdue:** no reminder is sent after the due date. The text builder throws, and `sendDueReminders` catches it for each item.
- **No deletes:** the sweep only calls the existing `onRemoved` hooks. Each query is bounded to 100 rows.
- **afterRemove:** one failing id never fails the delete. The voice Undo path is covered.
- **Restore gate:** checked before the run and between steps, and each step runs inside `guard`.

Findings (none blocking):
- **minor**, `housekeeping_providers.dart:234`: resume runs with `force: true`, so every resume runs all jobs, including the full-year `computeLive` and recurring detection. Single-flight stops overlapping runs but not back-to-back ones (OS dialogs, the share sheet and biometric prompts all trigger resume). Force the run on cold start only, and throttle resume (for example to 5 min). Follow-up.
- **minor**, `housekeeping.dart:55-60`: the throttle has no trailing run. Batches committed within 60 s of a run aren't alerted until the next trigger. Set a pending flag and run once more when the throttle window ends. Follow-up.
- **minor**, `housekeeping.dart:74`: long steps hold the pause gate, and a restore that waits more than 30 s fails with `IngestionBusy`. Follow-up.
- **nit**, `housekeeping_providers.dart:105`: `ref.watch` on the gate means a rebuild creates a new `Housekeeping`, which loses `_running` and the throttle state. Use `ref.read`.

## FU-b35-recat: APPROVED (strict pass)

What I checked:
- **Which rows change:** only `none`/`catalog`/`heuristic` rows that aren't user-verified. Every guard is checked again in the UPDATE (`deleted_at`, `is_internal`, `is_user_verified`, source, `IS NOT ?1`, category live and not archived). `user` and `user_rule` rows are never selected or written.
- **Chunks and gate:** 200 rows per transaction, each chunk written inside the gate. A gate refusal or any error leaves the marker unset, and a rerun is idempotent.
- **Derivation:** it matches the ingest categorizer. The event category beats catalog and P2P but never a rule: `atmWithdrawal` gives Cash, `instapayOut`/`instapayIn` give InstaPay, and a transfer to an `ipa` counterparty gives InstaPay. Enum strings match the schema CHECKs.

Findings (none blocking):
- **minor**, `event_category_backfill.dart:115`: the `db_meta` marker is written outside `gate.guard`. Wrap it in the guard.
- **minor**: a merchant rule the user added after ingest without "apply to past" still loses to the backfill, because the rule isn't checked again. The rows involved are `catalog`/`heuristic`, so this is consistent with the spec, but note it as FU. Closed `cycle_summaries` are not recomputed, which is the same as any recategorization.

## FU-b35-ui: APPROVED

- `pagerHeight` ignores pages that no longer exist, and the stale entries are pruned.
- `goldProductQueryProvider` is a test seam, and the 8 s timeout is tested.
- The onboarding actions are capped at half the page height and scroll.
- `reviewErrorSaveFailed` exists in both the ar and en ARB files, in Egyptian colloquial, and both review snackbars use it.

No findings.

## FU-b35-a11y: APPROVED

The sweep loads the four Plex faces with `FontLoader` and asserts that `found == 4`, so a missing font fails instead of falling back to Ahem silently. It covers ar and en at text scale 1.3, widths 360 and 320. All cases pass.

- **nit**: the check can't prove that every pump helper applies the app theme's `fontFamily`. A screen built outside the theme would still use Ahem. Add one assertion of `DefaultTextStyle.fontFamily` per case.

## FU-b35-be: APPROVED

- The LAN check refuses octets with a leading zero, which closes the octal ambiguity.
- A malformed dev-key list now gives a clear error that holds no key material. Dev kids only.
- The sandbox filter is in the SQL: `(@include_sandbox OR environment <> 'sandbox')`, where `environment` is NOT NULL with a CHECK, and the job passes `refresher.AllowSandbox`.
- The migration edit changes a doc comment only.

No findings.

## Fix list

None. No blockers, and no majors on money, security, privacy or data loss. The minors above become follow-ups.
