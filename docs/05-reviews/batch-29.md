# Batch 29 review (`batch/2026-11-16-29`)

Reviewer: `code-reviewer` (Opus; code + security for the C4 task). Date: 2026-11-16.
Scope: `git diff origin/main...origin/batch/2026-11-16-29`, per task branch.
Tests run on the merged tree: app `test/features/{settings,home,accounts,ingestion}` all pass; `packages/zaghlol_parsing` 1467 pass; `tools/registry_lint` 8 pass; backend `Zaghlol.Application.Tests` 1057 and `Zaghlol.Ops.Tests` 3 pass (Docker-backed suites cannot run here; `backend-ci` and `app-ci` are green on `ci/T-186` head `548d6ee9`).

## T-186: support seat move, detach, unfreeze (C4, security) — APPROVED

R6-1 check: unfreeze is refused unless the caller differs from the freeze-row operator **and** from the operator of the row it reversed, and unless at least 24 h have passed since the freeze row (`SupportRules.FreezeLockElapsed`, from the audit row `at`). A missing freeze row fails closed. Non-correction moves are refused while frozen (`dispute_frozen`, before the store call, audited). The 24 h lock on the unfreezing operator's next ordinary move is in place. Roles: `support_agent` for move/detach, `support_lead` for unfreeze. Strict hand-parsed bodies; the order ID exists only as `Sensitive<string>` and never reaches an audit row. There is exactly one audit row per call, refusals included. Two-phase flow: no lock is held over the store call, and phase 2 re-locks (purchase, then seat, `FOR UPDATE`) and re-runs every gate. A replayed move becomes a `noop` and a replayed unfreeze or detach becomes a `noop`, so concurrent duplicates are safe. No new secrets.

| Sev | File:line | Issue | Change |
|---|---|---|---|
| minor | backend/src/Zaghlol.Application/Support/SupportActionService.cs (`DetachAsync`, phase 1) | Phase 1 only checks that the purchase exists. A detach that is certain to be refused (no support link, wrong `correctsAuditId`) still makes the store call. | Run the link and source checks in phase 1 too. Follow-up. |
| minor | SupportActionService.cs `FreezeLockElapsed` / `UnfreezeLockActive` | Compares the app clock (`TimeProvider`) with `audit_log.at`, which is the DB's `now()`. Clock skew shifts the 24 h edge. | Read `now()` from the DB in the transaction, or document the tolerance. Follow-up. |

## T-070: BNPL templates (C2) — APPROVED

The 4 new institutions and the new templates are all `synthetic-unverified`. The due/reminder drops are per institution (`byInst`) only and the global drop list is unchanged. The guard base was regenerated, and `registry_lint` is clean (64 institutions).

| Sev | File:line | Issue | Change |
|---|---|---|---|
| minor | app/assets/registry/registry_manifest.json:3 | `registryVersion` stays 1 although the templates changed. It gates re-parse (`rawsToReparse`) and the native guard config, so a build that already shipped would not re-parse old review rows. Pre-launch, and the same as T-071/072. | Bump it once per release that changes the registry (Lead, at release). |
| minor | app/assets/guard/guard_base.json:107,408 | Sender `contact` and wallet card name `Contact` are generic guesses and could match unrelated senders or cards. | PO to confirm sender IDs (already an open item in the task file). |

## FU-244: generic `originalAmount` (C2, money) — CHANGES_REQUESTED

| Sev | File:line | Issue | Change |
|---|---|---|---|
| **major** (money, D-28) | packages/zaghlol_parsing/lib/generic/generic_parser.dart:199-201 | The foreign cue treats `equivalent / equiv / approx / يعادل` and any bracket as "foreign". These usually mark the **converted account-currency** amount. Probed results: `Purchase of USD 20.00 at AMAZON, equivalent EGP 1,000.00 …` → amount **USD 20.00**, `reasons=[]`, conf 700. `charged USD 20.00 (EGP 1,000.00)` → USD as well. `خصم 20.00 USD يعادل 1000.00 EGP` → USD. Before this change these were flagged `currencyAmbiguous`. The parser now picks a currency silently, and an always-capture sender auto-saves it, possibly into a newly created USD account. | Keep `currencyAmbiguous` (and the confidence cut) whenever a different-currency amount is present, unless the cue is an explicit `original/foreign/الاصلي`. Drop `equivalent/equiv/approx/يعادل/ما يعادل` from "foreign", or treat them as ambiguous. |
| **major** (money) | app/lib/features/ingestion/application/ingest_raw_messages.dart:1374,1427 | `ParseGeneric.originalAmount` is never read. The review payload and the auto-save `TxnInsert` drop it, so the second amount disappears silently while the ambiguity flag is gone too. | Add `'originalAmount': g.originalAmount?.toJson()` to the payload (and the prefill/confirm path), and `originalAmount:` to `TxnInsert`. Keep it integer minor units in its own currency; never add it to totals. |
| minor | packages/zaghlol_parsing/test/fixtures/generic/unseen_set.json:272 | The fix targets a named hold-out miss (`knownMiss` removed), so the hold-out no longer measures generalisation for this case. | Add fresh hold-out FX items (both orders) that are not in `fuzzy_corpus.json`. Follow-up. |

## DESIGN-pass3: money rows, docked Add, About (C2) — APPROVED

`dropZeroFraction` (app/lib/core/l10n/money_format.dart:33) clears the fraction only when every digit is `0`, working on the canonical string at each currency's exponent. A non-zero minor part is never hidden or rounded, and 3-decimal and 0-decimal currencies render correctly. The hero still uses `heroNumber` (ink). The docked Add button uses `EdgeInsetsDirectional` inside a `Row`, so it is RTL-safe. The deviation from mockup 20 is deliberate (FU-246). The duplicate `DisclaimersScreen` was resolved by the Lead into `disclaimers_screen.dart`.

| Sev | File:line | Issue | Change |
|---|---|---|---|
| minor | app/lib/core/ui/shell/app_shell.dart:132 | With 5 destinations plus the Add button on a 320 dp screen at text scale 1.3, labels may truncate. There is no golden at that width. | Add a narrow-width golden in ar and en. Follow-up. |
| nit | app/lib/features/accounts/presentation/money_tab.dart:66 (also budget, bills, charts, home) | `fabClearance` bottom padding is no longer needed on Android now that the button is docked. | Drop it on Android. Follow-up. |

## TEST-explorer2: explorer variants + small fixes (C2) — APPROVED

The integration test and the CI script use synthetic data only, and `font_scale` is reset after the loop. The home pager height fix and the KPI end gap use directional insets.

| Sev | File:line | Issue | Change |
|---|---|---|---|
| minor | app/lib/features/home/presentation/home_screen.dart:295 | The fixed heights 440/330 are magic numbers tied to the content. | Size to content (intrinsic or measured). Follow-up. |

## Fix list (blocking)

| Task | File:line | Required change | Test to add |
|---|---|---|---|
| FU-244 | packages/zaghlol_parsing/lib/generic/generic_parser.dart:199-201 | Only an explicit `original/foreign/الاصلي` cue may resolve two currencies. Brackets and `equivalent/approx/يعادل` keep `currencyAmbiguous` and the confidence cut. | Parser tests: `USD 20.00 … equivalent EGP 1,000.00`, `USD 20.00 (EGP 1,000.00)` and `20.00 USD يعادل 1000.00 EGP` each expect `currencyAmbiguous`. `… original USD 30.00` expects charge EGP and `originalAmount` USD. |
| FU-244 | app/lib/features/ingestion/application/ingest_raw_messages.dart:1374,1427 | Carry `originalAmount` into the generic review payload, the prefill/confirm path and the auto-save `TxnInsert` (minor units plus currency, never summed). | Ingest tests: a generic FX message gives a review payload with `originalAmount`, and an always-capture auto-save stores `original_amount_minor` and its currency. |

## Lead delta check (FU-244 fix round, 2026-11-16)

Commit 4a7be14e: about 35 production lines plus tests.
- **Major 1:** `_foreignLead` now matches only `original` / `foreign` / `الاصلي`. Brackets and `equivalent` / `approx` / `يعادل` keep `currencyAmbiguous`. Parser tests cover each phrasing and the `original` case. `en_fx_two_currencies` is back to `knownMiss` (ambiguous by design); add fresh hold-out FX items as a follow-up.
- **Major 2:** `originalAmount` is carried as `Money` (its own currency, integer minor units, never summed) into the review payload, `GenericSuggestion.fromPayload` (dropped unless positive), the one-tap confirm (`ManualTxnInput` → `originalAmountMinor` / `originalCurrency`) and the generic insert. Two ingest tests cover them.
- Parsing 1455 and ingestion + transactions 410 pass; analyze, format and lints are clean.

Verdict: FU-244 **APPROVED**. All five tasks approved.
- **FU-247:** batch-29 minors: T-186 (two), T-070 (`registryVersion` not bumped), and fresh hold-out FX cases for the generic parser.
