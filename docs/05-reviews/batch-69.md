# Review — batch 69 (T-244, T-247 + FU-296)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (single batch reviewer; privacy + money-adjacent logic) |
| Date | 2026-11-25 |
| Commit / diff | `batch/2026-11-25-69` @ 7b1af756, `git diff origin/main...HEAD` (main 24e30da) |
| Verdict | T-244 APPROVED · T-247 APPROVED (with minors) |

Commands run:
- `dart analyze --fatal-infos` (repo root): no issues.
- `dart test` in `packages/zaghlol_parsing`: 1668 passed. `packages/zaghlol_domain`: 516 passed.
- `flutter test -x golden test/features/ask test/features/salary test/features/settings test/features/budget test/features/insights test/features/home test/features/onboarding test/core/l10n`: 928 passed, 0 failed.
- Scratch probe (deleted) of `shapeSignature` with names, phones, merchants and cue-word collisions; see T-244.

No blockers, no majors. Minors go to FU-305…FU-308.

---

## T-244 — real generic reason, `shapeSignature`, SMS diagnostics (C2) — APPROVED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Known sender keeps the generic reader's real reason | PASS | `parsing_pipeline.dart` `_keptGenericReasons` (notice conflict, no amount, declined, promotion); other reasons still `noTemplateMatched`. Pipeline test updated. |
| `shapeSignature` pure, text-free | PASS | digit-bearing token -> `9`, Latin -> `A`, Arabic -> `ع`, only cue words (>= 3 chars, no digit) kept, runs collapsed, 80-char cap. Probe: names, phone, IBAN, merchants, card digits all gone. |
| Diagnostics: per-sender unread reasons + top 5 signatures, dev-only | PASS | `debug_sms_diagnostics.dart`; screen is behind `smsDiagnosticsEnabledProvider` (`kIsDevBuild`). Reason is validated to `^[A-Za-z]{1,40}$` before display, otherwise `unknown`. Sender label goes through `diagSenderLabel` (numbers -> `(number)`). |

### Privacy check (CLAUDE.md §2.6)
- The raw body is read from SQLCipher only inside the snapshot builder, turned into a signature at once, and never stored, logged or shown. The UI gets reason codes, counts and signatures only.
- Digits: any token with a digit (either script, via `\p{N}`) becomes `9`; the probe found no digit survive.
- Names / merchants: survive only if they equal a cue word. Probed bodies with Arabic and Latin names, merchants and wallet names: none survived.
- The signature is also used in a widget `Key` (`sms-diag-<sender>-shape-<sig>`); same text-free content, dev-only, fine.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| FU-305 | minor | `packages/zaghlol_parsing/lib/generic/shape_signature.dart:10-30` | Builder's known gap holds: a name or merchant that equals a cue word (3+ letters, e.g. a first name that is also a keyword) survives into the signature. Short words are excluded, and the screen is dev-only, so the exposure is one common word, never a full name or number. | Follow-up: after the next real-message review, drop cue words that are also common given names or merchant words, or keep only cues from a small allow-list. Add a test with a known collision. |
| FU-306 | nit | `app/lib/features/settings/debug/debug_sms_diagnostics.dart` (unread query) | No `LIMIT`; every unresolved unrecognized SMS body is loaded and shaped on each refresh. Dev-only, so harmless. | Cap at the newest few hundred rows if the screen feels slow. |

---

## T-247 + FU-296 — cycle naming (D-82) and payday follow-ups (C3) — APPROVED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| `cycleLabelMonth`: 20 -> same month, 21 -> next, Dec 24 -> January next year | PASS | `cycle_label.dart`; `cycle_label_test.dart` |
| Home, budget, charts name a cycle by the label month | PASS | `homeHeroSpentInCycleMonth` (payday set, no budget); budget cycle line; cash-flow cycle bucket, saved months, in/out, category trend all via `ZDateFormat.cycleMonthName(from)`. Calendar `month` buckets stay named by their end month. Goldens `home_cycle_named_*` in ar and en, light and dark. |
| Ask "this month" / "last month" / month names with payday 24 | PASS | `ask_period.dart`; `ask_period_test.dart`, `ask_engine_test.dart`, `ask_answer_text_test.dart` |
| FU-296 m-1 (post-persist runs the rule only for a salary row) | PASS | `PaydayAutoService.onPersisted`; hook calls it |
| m-2 (what counts as a salary) | PASS | `_countsAsSalary`; see FU-308 |
| m-3 (28-day ring) | PASS | `_arc` / `_ringDistance`; 28 and 1 are neighbours, tolerance 2; `payday_detection_test.dart` |
| m-4 (`setPayday` + `payday_auto` in one transaction; Undo too) | PASS | `_db.transaction` around both; rollback test in `payday_auto_test.dart` |
| m-5 / m-6 (banner goldens, capped-day copy) | PASS | `payday_auto_banner*` tests, goldens plain and capped, ar and en; old state without `d` reads as null |
| n-1 (old payday suggestion card removed) | PASS | `SetupSuggestionKind.payday`, `paydayDay`, `HomeCards.salary`, `acceptPayday` removed; the stored `payday` slug in old handled lists is ignored |

### Consistency with D-82 / D-68
- D-82 says "Ask uses the same name". Ask "this month" is now the cycle that holds today and "last month" the one before, the same cycle Home shows. With payday 1 a cycle is the calendar month, so nothing changes there. Home "spent this cycle" and Ask "this month" now give the same total (no silent difference).
- D-68 chart presets "this month" / "last month" stay calendar months (the `month` bucket branch is untouched), and "this cycle" / "last cycle" stay cycles. This matches the task text and D-68 (the presets list both). The only difference a user can see is Ask "this month" (cycle) against the chart preset "this month" (calendar) when payday is not 1. This is a product choice in the task file, not a code defect; the Lead may want to tell the PO.
- Money: totals are unchanged in kind (per currency, integer minor units). Only the period boundaries move. `payday_auto_service` still reads dates and currency codes for the rule; the extra columns it now selects (`merchant_raw`, `counterparty_value`, `note`) feed `salaryLooksLikeSalary` only and are not logged or stored.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| FU-307 | minor | `app/lib/features/ask/domain/ask_period.dart:56-60` | `monthOfYear` infers the year as "this year if `m <= today.month`, else last year" from the calendar month. With payday 24 on 26 Nov the current cycle is named December, "this month" resolves to it, but "in December" resolves to December of last year. | Infer the year from the cycle names (try the current cycle's label month first), then fall back as today. Add a test for payday 24 on 26 Nov. |
| FU-308 | minor | `app/lib/features/salary/application/payday_auto_service.dart:162-176` | The old rule used only `salary.state` entries with `captured`; the new one ties every entry, so the manual rows ("My salary / It arrived" without a captured SMS) now count too. The builder lists this as intended. Risk: a manual row on an expected date feeds the payday before the real SMS arrives. | Confirm with the PO, or restrict to captured plus manual rows with `e.anchor` equal to the real arrival. |
| nit | nit | `insights/presentation/charts/chart_bodies.dart`, `categories_tab.dart`, `saved_months_chart.dart`, `trends_tab.dart` | Import edits left a stray blank line between package and relative imports (formatter accepts it). | Tidy in passing. |

---

## Follow-ups to record
FU-305 (cue-word name collision in signatures), FU-306 (cap the diagnostics query), FU-307 (Ask month-name year inference vs cycle names), FU-308 (manual salary rows count for payday).

## Lead delta check (`fix/fix69-ask`)

25 production lines, read by the Lead; both new tests fail on the old code (fix agent).
- **FU-307 FIXED:** a month name without a year resolves to the nearest non-future cycle carrying that name (up to 14 cycles back), else the old calendar rule; payday 1 unchanged.
- **FU-308 FIXED:** only captured `salary.state` entries count as tied; manual rows (anchored on the expected payday) count only if they pass the other salary tests.
- Checks: `dart analyze --fatal-infos` clean; `flutter test -x golden test/features/ask test/features/salary` green.
