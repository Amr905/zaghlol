# Batch review — batch 80 (`batch/2026-11-26-80`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security/data for the C4 task) |
| Date | 2026-11-26 |
| Diff | `git diff origin/main...8ff0b10c` (main = 9b8d79d5), 55 files |
| Tasks | T-283 (C2), T-284 (C3), T-285 (C2), T-286 (C4, can lose/overwrite user data), T-287 (C2) |

## Checks run (merged tree 8ff0b10c)

| Check | Result |
|-------|--------|
| `flutter pub get --enforce-lockfile` | OK |
| `flutter analyze` (app) | No issues |
| `dart format --set-exit-if-changed lib test` | clean |
| `flutter test -x golden test/features/insights test/features/widgets_bridge test/features/export_import test/features/ingestion test/features/transactions test/features/home test/features/ask test/core` | 2734 passed, 1 skipped, 0 failed |
| `flutter test test/features/insights/presentation/v2/trends_golden_test.dart` (incl. new `insights_v2_trends_exchange_*`) | 10 passed |
| Kotlin / Swift widget | not compiled here (no native change in this batch; CI only) |

Follow-ups start at FU-386. No blocker or major in this batch.

---

## T-283 — Insights: in-and-out chart draws exchange bars (C2) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Month with an exchange shows the two extra bars and legend; month without shows none | PASS | `trends_tab_test.dart` (T-283 cases), run |
| Goldens ar/en light/dark | PRESENT, PASS locally | `insights_v2_trends_exchange_{ar,en}_{light,dark}.png` (regen `e76cf695`) |

### Code
Exchange bars are separate thin bars beside the spending bar, never stacked; the y-scale includes them; per-currency minor units only. Legend entries and a11y lines only when some month has an exchange. ar copy «غيّرت عملة: دخل / خرج» is Egyptian and matches the plan.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | minor | `app/lib/features/insights/presentation/charts/chart_palette.dart:19` | **Brand conflict: yes.** `exchangeIn = 0xFFFFB86B` is exactly the `accent` token, which `05-theme-2026.md` §0 (light row 17; dark: "apricot stays the colour of Add, Gold and Captain Zaghlol's voice") and CLAUDE.md §8 reserve for Add and Gold. A chart series in the accent reads as a Gold/Add affordance. Also on the light card it is 1.7:1 against `#FFFFFF` (below the 3:1 non-text contrast the chart's other series aim at). The task's "mint/apricot family" wording allowed a family colour, not the accent itself. | FU-386: pick a distinct chart token (e.g. a darker amber/terracotta pair or a teal pair) that is not `#FFB86B`, ≥ 3:1 on `#FFFFFF` and on `#141414`; UX sign-off; regen goldens. |
| 2 | nit | `app/lib/features/insights/presentation/v2/in_out_chart.dart:162-186` | With `slot < 48` the two bars end at `cx + 0.49·slot + 3.5`, past the slot edge; in the last LTR slot (first RTL slot) they can paint ≈3 px outside the canvas. E.g. 13 months on a 320 px chart. | FU-386 (same pass): clamp `ex`/`x2` to `[0, size.width]` or shrink `ew` so `bw/2 + 2 + 2·ew + 1.5 ≤ slot/2`. |
| 3 | nit | `app/lib/core/l10n/app_{ar,en}.arb` (T-283 keys) | One-line `{"description": "T-283 legend"}` metadata, no class prefix (`C ·`/`S ·`) unlike the rest of the file. | Follow-up only; fix with the next ARB touch. |

---

## T-284 — Home-screen widget "+USD" hint (C3) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Payload: no cards → no hint; 1, 2, 3 currencies (`+N`) | PASS | `widget_snapshot_builder_test.dart` group "T-284" (also hidden, locked, rolled days, no budget, Arabic digits), run |
| Wiring | PASS | `widget_bridge_test.dart` "T-284 …", run |
| Kotlin and Swift render the hint | PASS by design | No native change: the hint rides in `secondaryText` / `secondaryTextByDay`, which both platforms already draw; contract note added to `platform-channels.md` §5 |

### Code / privacy
Codes only, never an amount or sum; omitted whenever `maskForLock` (locked **or** backgrounded with the lock on), so with the app lock on the widget never shows which currencies are held; kept under hide-amounts (written in the task file and contract). LRI/PDI isolates, `+N` through `DigitsMode`. Source is `homeModelProvider.currencyCards` (T-278 rule).

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | nit | `app/lib/features/widgets_bridge/domain/widget_snapshot_builder.dart:133-136` | Line two gets longer («٧ أيام على القبض · + USD, EUR +١»); on the 2×1 widget it may ellipsize the days count first. Not verifiable here (native render). | FU-387: check on a small widget in the device pass; if it truncates, drop the hint before the days text. |

---

## T-285 — Export pair/kind columns; importer reads old and new (C2) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Exchange → two rows, same pair id; own-account transfer likewise; ordinary rows empty | PASS | `export_test.dart` (T-285 cases), run |
| Round-trip import of a new export; old 14-column file still read | PASS | `import_csv_test.dart` (T-285 cases), run |

### Code
Two columns appended after `note`; pair label = 40-bit FNV-1a of the pair id (no internal id exported, hex only so no formula prefix possible). Importer picks the 14- or 16-column header, compares every name, row width checked against the file's own header; `pair`/`kind` ignored (pairs rebuilt by existing hooks). No converted amount column. `TransactionRecord.transferPairId` added and mapped.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | minor | `app/lib/features/export_import/presentation/export_ports.dart:41-47` | `pairKinds` runs one `TransferPairsDao.byId` per distinct pair, sequentially, inside the export; a large export with thousands of transfers does thousands of awaits. Also the DAO is built in a presentation-layer provider. | FU-388: one `SELECT id, kind FROM transfer_pairs WHERE id IN (…)` (chunked) in the data layer, injected into `ExportService`. |
| 2 | nit | `app/lib/features/export_import/application/export.dart:62-68` | Opened in Excel, a label like `0000012345` or `12345e6789` becomes a number (leading zeros lost / scientific). Both legs change the same way, so matching still works. | Follow-up only (optional `p` prefix if users complain). |

---

## T-286 — Cross-channel merge marker (FU-383) + exchange-safe bulk actions (FU-384) (C4) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| SMS A, A's notification (merged), notification for real conversion B with equal amounts → two exchanges + possibleDuplicate item, A untouched | PASS | `ingest_raw_messages_test.dart` "T-286 FU-383: a second, real conversion …" (read) |
| Same rule for ordinary attach; third channel still merges | PASS | "T-286 FU-383: a second, real payment …", "T-286: a copy from a third channel still merges" (read) |
| T-281 true copy still merges and leaves a hidden resolved mark on the out leg | PASS | "both legs match one stored exchange → merged …" (read; asserts no open items, mark payload) |
| Exchange row selects both legs; Category/Card off with reason; Delete whole; Select all under USD filter | PASS | `exchange_row_test.dart` group "T-286 FU-384" en + ar (read) |
| Set account / category cannot change one leg | PASS | `exchange_unit_test.dart` "T-286 FU-384 …" (run) |
| ≤ 3 negative proofs | PASS | 3 listed in the task file |

### Security / data part
- **Mark never causes a merge.** `hasCrossChannelCopy` only removes a match from the merge branch; when it is true the message falls through to the normal insert with `possibleDuplicate` (pending/settled step is skipped because `possibleDuplicates` is non-empty). Nothing stored is patched or deleted; the user decides through the existing review card. No new delete path.
- **Atomicity.** Mark is written after `_insertRaw`/`_attach` in the same per-message savepoint; a rollback removes both.
- **No leaks of the resolved mark rows.** Checked every `review_items` reader: review queue / `countOpen` / `open()` / `review_repository` count filter `resolved_at IS NULL`; SMS diagnostics filter `resolved_at IS NULL`; transfer, refund, recurring, suggestions and FX queries are other kinds or open-only; `oldDueOfferTxns` filters `reason = oldDueNotice`; reparse resolves only open items. `purgeResolvedBefore` has no caller. `sweepDanglingLinks` does not touch `review_items`. Export does not read `review_items`. Backup snapshots the table as-is (resolved rows round-trip harmlessly). FKs cascade with the raw message or the transaction. Payload holds only `reason` and the source code; no SMS body, nothing logged.
- **Bulk.** `SetCategory` refusal (`BULK_EXCHANGE`) runs inside the DB transaction before any write; `SetAccount` already refused any paired leg. UI re-checks unloaded rows via the lookup before opening a sheet and shows the reason.
- No schema change; no backend call.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | minor | `app/lib/features/ingestion/application/ingest_raw_messages.dart:1092-1095` (with `_settle`, ~1155) | **True copy stored twice after a fast pending→posted settle.** The mark lives on the transaction id, and `_settle` turns the pending row into the posted one in place. Failing input: SMS pending 120.50 at t0, notification pending (merged, mark `notification`), SMS posted 120.50 at t0+30 s (settles in place), notification posted at t0+60 s → `crossChannelMatches` matches the now-posted row, the `notification` mark blocks the merge → a second 120.50 expense + a possibleDuplicate card (before T-286: merged). User-visible and reversible, so not a data-loss blocker, but spending is double-counted until the card is answered. | FU-389: store the status class in the mark payload (or check `statusClassOf`) and only let a mark block a match of the same status class; add the four-message test. |
| 2 | nit | `app/lib/features/ingestion/application/ingest_raw_messages.dart:1092` | With two matches, one already marked for this source, the marker could narrow to the unmarked one and merge (today: no merge, possibleDuplicate, as before T-286). Missed improvement, not a regression. | Follow-up only (FU-389 scope). |
| 3 | nit | `app/lib/features/transactions/presentation/list/transactions_list_screen.dart:145` | The title counts legs: one exchange row selected reads "2 selected" / «٢ متختارين». | FU-390: count exchange rows once in the title (delete dialog already says the pair goes together). |
| 4 | nit | `app/lib/features/transactions/application/bulk_edit.dart:242-249` | One `_pairs.byId` per paired row; fine at `maxIdsPerCall`, but a set of distinct pair ids would halve the reads. | Follow-up only. |

---

## T-287 — Batch 79 minors FU-379…382, FU-385 (C2) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| FU-380: row at 23:30 +03:00 on the last cycle day, device on UTC | PASS | `currency_view_feed_test.dart`, run |
| FU-381: USD 600 → EGP 29,700 and USD 100 → EUR 92 → sheet 49.50 | PASS | `home_approx_providers_test.dart` (FU-381 case), run |
| FU-385: USD salary last month, USD 600 exchanged this month → Ask USD left −600 | PASS | `ask_exchange_out_only_test.dart`, run |
| l10n parity; analyze clean (dead code removed) | PASS | `test/core` l10n tests; analyze no issues |
| FU-382 copy neutral (ar/en) | PASS | ARB text matches the task wording; Egyptian colloquial |
| BR-FX-01 bank-rate-first sentence | PASS | `requirements.md` BR-FX-01 |

### Code
Feed now queries the cycle window (padded ±14 h) and tests the day with the row's stored offset, like cycle totals. Bank rate per foreign currency from pairs whose received side is the target only; per-currency `Money` sums, display only. Ask includes a currency when income, exchanged-in or exchanged-out is non-zero.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | nit | `app/lib/features/home/application/currency_view_providers.dart:94-95` | Inline `dayMs` / `padMs` constants; the domain package already has a ms-per-day constant. | Follow-up only. |

---

## Follow-ups to file

| FU | Owner task | Summary |
|----|-----------|---------|
| FU-386 | T-283 follow-up (UI) | Exchange chart colours: not the reserved accent `#FFB86B`, ≥ 3:1 on light and True Black; clamp bars inside the slot/canvas; regen goldens. |
| FU-387 | T-284 follow-up (device pass) | Check line two with the currency hint on the smallest widget size in ar/en. |
| FU-388 | T-285 follow-up (core) | Batch pair-kind lookup for export in the data layer. |
| FU-389 | T-286 follow-up (ingestion) | Mark scoped by status class so a fast pending→posted settle still merges the posted copy; optionally narrow multi-match by marks. |
| FU-390 | T-286 follow-up (UI) | Selection title counts an exchange row once. |

## Verdict summary
| Task | Verdict |
|------|---------|
| T-283 | APPROVED |
| T-284 | APPROVED |
| T-285 | APPROVED |
| T-286 | APPROVED (security part: no High/Medium; FU-389 Low) |
| T-287 | APPROVED |

---

## Delta re-review (fix80)

Scope: `git diff d0cc0dad origin/fix/fix80` (FU-389). Ran `flutter test -x golden test/features/ingestion test/ingestion`: 405 passed, 0 failed.

**Verdict: RESOLVED**

### Checks
| Check | Result |
|-------|--------|
| 4-step SMS pending, notif pending (merged, mark `pending`), SMS posted (settles in place), notif posted | One expense. `crossChannelMatches` needs the candidate's current class to equal the new one; the posted row passes, the mark class `pending` differs from `posted`, so no block; merge + second mark `posted`. New test asserts 1 txn and 0 open review items. |
| Real second identical payment, same class, other channel | Still blocked: mark class equals new class, so it is stored with possibleDuplicate. Existing T-286 tests still pass. |
| Old marks without `statusClass` | SQL `json_extract(...) IS NULL` branch counts them, so T-286 behaviour is kept. |
| SQL null handling | `?6` is bound as a null `Variable<String>` when no class is given, and `?6 IS NULL` short-circuits. A missing JSON key gives SQL NULL. Parentheses are correct. Placeholder reuse is fine in SQLite. |
| Payload / logs | Payload gains only `statusClass` (`pending`/`posted`); no message text, no new logging. |
| Fixtures | Synthetic (`ZBANK`, "Synth Shop", card `*4321`). |
| Deletion | None added. Merge is attach-only, as before. |

### Sequence where the class check lets a real second payment merge
Reachable: SMS pending P1, notification pending (merged, mark `notification:pending`), SMS posted (P1 settles in place to posted), then a genuine second payment's posted notification with the same amount/last4 inside the cross-channel window. The row is posted, the mark says `pending`, so it merges and the second payment is silently not stored. It is indistinguishable from the true copy in step 4 of the target sequence (same data), so this is the inherent cost of FU-389, not a bug in the fix. It needs two identical payments within the short window plus a pending→posted settle, and the raw message is kept attached to the target. Impact: undercount by one expense with no review card; user can add it manually. Rated minor, accept.

The other mixes do not merge: a pending notification vs a posted row fails the class match; a posted row with a `posted` mark blocks a second posted notification.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| 1 | minor | `ingest_raw_messages.dart` (`_markClass`, ~1930) | Residual ambiguity above: stale `pending` mark lets one genuine second posted copy merge after an in-place settle. | None; accept, document in FU-389 note. |
| 2 | nit | `ingest_raw_messages.dart` `_markClass` | Any non-pending status maps to `posted` (includes failed/other if ever reachable); fine today since `crossChannelMatches` uses the same pending/other split. | None. |
