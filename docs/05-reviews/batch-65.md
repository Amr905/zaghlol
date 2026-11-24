# Review — batch 65 (T-233, T-234, T-235)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Opus, code + security for T-233/T-234) |
| Date | 2026-11-24 |
| Commit / diff | `batch/2026-11-24-65` @ 5486a04a, `git diff origin/main...HEAD` (no PNG / generated) |
| Verdict | T-233 APPROVED · T-234 CHANGES_REQUESTED · T-235 CHANGES_REQUESTED |

Commands run: `flutter test --exclude-tags golden test/features/transactions test/features/ingestion test/support` (458 passed); `python3 -m unittest` in `docs/qa/tools` (7 passed); T-235 merchants test and Licenses test pass, and the merchants test fails with `chart_bodies.dart` from `origin/main` (checked locally, file restored).

Neither major below is a money, security, privacy or data issue. Under SPRINT.md the Lead may record them as follow-ups instead of running a fix round. The verdicts follow the review rule: any major means CHANGES_REQUESTED.

---

## T-233 — SMS scenario e2e + ingest transfer pairing (C3) — APPROVED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| 1 Every entry checked; mismatches listed by id, no bodies | PASS | `sms_charts_device_test.dart` `problems` and `say` lines hold ids, amounts and senders only. The run log (45369489896) shows 44/44 matched |
| 2 Chart numbers against independent expected numbers, per currency, ar + en | PASS | `test/support/scenario_expected.dart` and its unit test. The device test checks hero, rows, saved bars and heatmap days |
| 3 Green device-flows run, screenshots, bug fixed with unit test | PASS | Run 45369489896. `transfer_pairing_hook_test.dart` |
| 4 analyze / format / fixture tests | PASS | Local run above |

### TransferPairingHook analysis (the totals-changing part)
- **Same rules as manual/edit/import pairing.** The hook calls the existing `TransferPairingUseCase.onPersisted`, which the editor, bulk actions and import already call. It only pairs when all of these hold: the legs go in opposite directions, the amount is the same, the currency is the same, the accounts differ, the legs are at most 5 minutes apart, and each leg is the other's only candidate (`decideSameCurrency`). More than one candidate opens a `transfer_ambiguous` review item and pairs nothing. A leg in another currency only gets an `fx_pair_suggestion`; it is never paired, except for the documented `fx_conversion` inside one multi-currency account. A pair the user unlinked is remembered and never re-paired.
- **Idempotent.** A leg that is already paired returns `skipped`. All writes are conditional (`transfer_pair_id IS NULL`), and the UNIQUE out/in columns make a racing second pair fail and return `skipped`. Re-ingest and rescans that reach `_runHooks` (`inserted: false`) are safe.
- **One-sided legs.** These are only marked internal when `counterparty_kind = 'own_account'`, and the SMS ingest never sets that value (`_counterpartyOf` sets ipa/phone/person only). A lone SMS transfer leg therefore keeps counting, as it did before.
- **Failure isolation.** The pairing runs in a nested Drift transaction (savepoint) inside the message savepoint, and the hook swallows its errors. A pairing failure cannot cost the stored transaction. This is the same pattern as `RefundMatchingHook`.
- **Ordering.** The hook runs before `SalaryMatchingHook`, so a paired transfer-in leg is internal before anything offers it as salary. Correct.
- **Old rows.** The hook does not run on existing data, because already-stored SMS transfer legs are deduped and never reach the hook (see minor 2).

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | minor | `app/lib/features/ingestion/data/ingest_factory.dart:91` (rule in `packages/zaghlol_domain/lib/transfers/transfer_matching.dart:79`) | Auto-pairing ignores the counterparty. Example: an InstaPay send of 500 EGP from CIB to friend A and a receipt of 500 EGP into NBE from friend B, within 5 minutes and with no other candidate, are paired as internal. That takes 500 off both spend and income. The rule is T-089's approved rule, but with SMS feeding it many more person-to-person legs now reach it. The pair can be unlinked. | FU: skip auto-pairing (offer a review item instead) when both legs carry a known third-party counterparty (`ipa`/`phone`/`person`) that is not one of the user's own accounts. |
| 2 | minor | `ingest_factory.dart:91` | Transfer legs ingested before this batch stay unpaired, so earlier months still show own-account transfers as spend + income. | FU (PO decision, because it changes past totals): a one-off backfill that runs `onPersisted` over posted, unpaired transfer legs, in housekeeping. |
| 3 | minor | `app/test/features/transactions/application/transfer_pairing_hook_test.dart` | The hook tests cover pair / outside the window / no-throw only. Missing: (a) a test through `buildIngestRawMessages` showing the hook is wired (only the device run proves it); (b) running the hook twice on the same leg (idempotent); (c) two candidates → nothing paired; (d) a leg with the same amount in another currency → not paired. | FU: add (a)–(d). |
| 4 | minor | `.github/scripts/scenario-device.sh:78-95` | The device clock and `auto_time` are restored only after the loop. There is no `trap`, so a cancelled or timed-out job, or a `set -u` exit inside the loop, leaves the emulator clock in the past. The CI emulator is ephemeral, so this is low impact, but a PO emulator reused from this script would keep the wrong clock. | FU: `trap restore_clock EXIT` set before the first `date -u`. |
| 5 | minor | `app/integration_test/sms_charts_device_test.dart:233` | The test drops every `overflowed` FlutterError while it walks Insights, so the scenario run cannot catch a layout overflow (as found in T-235). | FU: let overflow errors through, or list them as problems. |
| 6 | minor | scenario (T-233 deviation 5) | The refund counts as income. This is the app's intended rule (SRS BR-XFR-03: "unmatched refunds count as income-type 'refund'"; `chart_repository.dart:64`), so it is not a gap. But the scenario never exercises a *matched* refund netting against spend (FR-XFR-03). | FU: add a merchant card refund that matches an earlier expense, and assert the spend net of it. |
| 7 | nit | `scenario-device.sh:132-156` | The `SCENARIO_PROBE` diagnostics block is dead code now that the probe is done. | Remove it in a later touch. |
| 8 | nit | `ingest_factory.dart:93-98` | The pairing reuses the `refundSchedule` override name. During a first-run scan, every auto pair publishes a `detective` MascotTrigger. | Rename to a neutral name. Consider not raising the mascot trigger for batch scans. |

### Security / privacy (T-233)
- No real SMS: the bodies come from the synthetic per-bank templates (README says so). No body is logged. The script prints ids, senders and counts. The test's `say` lines print ids, amounts and merchants. The failure tail is the test log, which prints no text. The `scenario-define.json` that carries the bodies goes only into the job artifact, and the `device-shots` publish copies `*.log` and screens only. **Info.**
- The pairing hook writes nothing outside the DB transaction and logs nothing. No backend calls. **No findings above Low.**

---

## T-234 — PO emulator tool (C2) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Tool + guide committed | PASS | `docs/qa/tools/sms_scenario.py`, `.ps1`, `docs/qa/sms-emulator.md` |
| Tests pass (no real adb) | PASS | `test_sms_scenario.py`, 7 tests |
| Works with the T-233 format | **PARTIAL** | `--list`, `--live` and `--all-live` work. `--historical` does not (finding 1) |
| No bodies printed | PASS | Only id, sender and counts are printed. A failure prints id and sender, not the adb output |
| Refuses real phones by default | PASS | `check_target`, tested |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | **major** | `docs/qa/tools/sms_scenario.py:139-144, 231` | `--historical` uses `content insert --bind body:s:…`. T-233's probe on the API 34 Google APIs emulator found that the shell `content insert` into `content://sms` does not work: it answers nothing or prints its usage text, and `:` splits the bind value. 35 of the 46 scenario bodies contain `:`. The success check for this mode only looks for exit code 0 and no "error"/"exception" in the output, so the usage text is counted as "sent". The guide tells the PO to run `--historical` first. The PO would get "sent 38, failed 0" and an empty inbox. | Either deliver past entries the way T-233 does (root, `auto_time 0`, set the clock per entry, `emu sms send`, restore the clock in `try/finally`), or remove `--historical` and point the guide at `--all-live`. In either case, count a send as good only on a positive signal. |
| 2 | minor | `docs/qa/sms-emulator.md:20` | "Refunds reduce spend" contradicts the tool, which counts a refund as income, and the app's rule for unmatched refunds (BR-XFR-03). | Say: "an unmatched refund counts as income". |

### Security / privacy (T-234)
- `subprocess.run` with argument lists, no `shell=True`, so there is no host shell injection. The device-side `content insert` string quotes every value in single quotes and escapes `'` correctly (tested).
- **Info:** `adb emu sms send` passes the text to the emulator console, which reads commands line by line. A `--text` containing a newline could issue further console commands on the PO's own emulator. The input is the PO's own and the target is emulator-only. Optional FU: reject `\n`/`\r` in sender and body.
- Never prints bodies; refuses non-`emulator-*` serials unless `--i-know-this-is-a-real-phone`. **No findings above Info.**

---

## T-235 — Explorer dead taps, allow-list precision, merchants row (C2) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Bill Save / card Save / Hide account justified with test | PASS (weak) | Existing `edit_card_test` cases. No check that the disabled Save is visibly disabled with semantics, which the scope asked for |
| About → Licenses has a way back | PASS | `settings_screens_test` adds `pageBack` → `AboutScreen` |
| Merchants row fits 320dp | PASS | `charts_redesign_test` T-235 (ar + en, 1.3x). It fails without the fix |
| Allow-list entries all have control matches (FU-292) | **FAIL** | Finding 1 |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | **major** | `app/integration_test/support/explorer_allow.dart:114`, `:132`, `:120-122` | The PO asked for precise control matches, but three entries are effectively blanket. (a) The restore-picker entry (`:114`) and (b) the emoji-title detail entry (`:132`) use `where: '.*'`, which `ExplorerAllow.matches` treats exactly like `where == null`. Any finding of that kind on those screens is still allowed, so the AC holds in letter only. For (b), the screen regex `^[^A-Za-z؀-ۿ0-9]{1,6}$` also matches any short symbol-only title. (c) The new Bill/Card dead-tap entry (`:120`) matches any screen with `Card`/`كارت` anywhere in the title (Cards, Credit card, card charts…) and any `Save` or `Switch` control on it, so a really dead Save on any card-titled screen is hidden. | (a) Match the picker's choice controls (e.g. `^(radio|listtile|inkwell) `) instead of `.*`. (b) Match the category chip/row that changes the category. (c) Anchor the screens (`^Card details$`, `^تفاصيل الكارت$`, `^Edit bill$`, …) and the controls (`^button "Save"$`-style, plus the hide switch label). |
| 2 | minor | `explorer_allow.dart:89` | The link-transfer `where` includes bare `ListTile`/`InkWell`, which covers every row on the sheet, not only the preselected candidate. | FU: match the candidate row's semantics label pattern. |
| 3 | minor | T-235 scope | "Save disabled until valid" was taken as the explanation without showing the state is visible (disabled styling + semantics `enabled: false`) as the scope asked. | FU: a widget test that asserts `SemanticsFlag.hasEnabledState` without `isEnabled` on the disabled Save (ar + en). |

---

## Checklist (batch)
- [x] Tests pass locally (458 Flutter, 7 Python); `flutter analyze` / format were not re-run by the reviewer (the builders report them clean)
- [x] RTL + LTR: the merchants row test covers ar + en
- [x] No hard-coded user-facing strings added (the scripts and tool are dev tooling)
- [x] No `double` money (integer minor units throughout; `_fmt_minor` is integer-only)
- [x] No sensitive data in logs (synthetic bodies, never printed)
- [x] Scope: CI workflow changes are limited to the new scenario job and the skip conditions

## Proposed follow-ups (FU-293, one entry with sub-items)
FU-293 (owner: T-233 lane unless noted):
- a. Counterparty-aware auto-pairing (T-233 #1).
- b. Backfill pairing for old SMS transfer legs, PO decision (T-233 #2).
- c. Hook tests: wiring, idempotency, ambiguous, other currency (T-233 #3).
- d. Clock-restore `trap` (T-233 #4).
- e. Stop swallowing overflow errors in the scenario test (T-233 #5).
- f. Matched-refund scenario entry (T-233 #6).
- g. Remove the probe block and rename `refundSchedule` (T-233 #7, #8).
- h. Guide refund wording; reject newlines in tool input (T-234 #2, Info; owner T-234 lane).
- i. Link-transfer `where` precision; disabled-Save semantics test (T-235 #2, #3; owner T-235 lane).

## Notes for the Lead
- Fix round candidates: T-234 #1 and T-235 #1. Both are small. Neither is a money, security, privacy or data issue, so under SPRINT.md you may fold them into FU-293 instead. T-233's ingest change is sound, and its spend/income impact matches T-089's approved rules.
