# Review — batch 70 (T-248, T-249, T-250)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Opus, code + money/data safety; one batch reviewer) |
| Date | 2026-11-25 |
| Commit / diff | `batch/2026-11-25-70` @ e017a5ec, `git diff origin/main...e017a5ec` (main ce09e166) |
| Verdict | T-248 CHANGES_REQUESTED · T-249 APPROVED · T-250 CHANGES_REQUESTED |

Commands run (worktree at e017a5ec):
- `flutter pub get --enforce-lockfile`: ok.
- `cd app && flutter analyze`: no issues.
- `dart analyze --fatal-infos` in `packages/zaghlol_parsing`: no issues.
- Registry lint (`--check-guard-config guard_base.json`): 64 institutions, 1424/1424 fixtures, 0 findings.
- `dart test` in `packages/zaghlol_parsing`: 1671 passed (PO suite incl. the new T-248 group).
- `flutter test -x golden test/ingestion test/features/ingestion test/features/recurring test/features/accounts test/features/settings/debug`: 582 passed.
- Scratch probes (not committed, deleted): (a) an Arab Bank instant transfer `... الي 0021234***5678 ...` from sender `ArabBank` through `buildIngestRawMessages` with the bundled registry; (b) re-parse of a CIB due notice (case 7 wording, due `25/07`, received 120 days before "now") on a card with no stored due. Results under T-248 M-1 and T-250 M-2.

Registry: T-248 (`arab_bank.account_purchase.ar` → v10) and T-250 (`cib.cc_due.ar`, `cib.cc_statement.ar` → v10) both target `registryVersion` 10; manifest, `guard_base.json` and the devSms spike guard base are 10. Re-parse selects rows with `registry_version < 10` (`drift_ingest_store.dart:339`), so rows stamped 9 by either template's old version are looked at again. Confirmed.

---

## T-248 — own-account counterparty, `strongSenderOnly`, signature cue masking, diagnostics cap (C2) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| 1. Masked own account not stored as `person` | PASS for HSBC case 10, but see M-1 | `card_dues_ingest_test.dart` payments group, `counterparty_kind == 'own_account'` |
| 2. `EG` sender never reaches `arab_bank.account_purchase.ar`; `ArabBank` still does | PASS | `po_suite_test.dart` "T-248 strong-sender-only template"; `parsing_pipeline.dart:168-175` |
| 3. FR-PAR-13 numbers in `T-243.md` | PASS | `docs/04-tasks/tasks/T-243.md` last section |
| 4. Title Case / ALL CAPS cue word masked | PASS | `shape_signature_test.dart` T-248 test |
| 5. Diagnostics unread query capped at 500 | PASS (weak test, see m-2) | `debug_sms_diagnostics.dart:154-155` |
| PO suite 12/12, registry lint, analyze | PASS | commands above |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| M-1 | **major** (money) | `app/lib/features/ingestion/application/ingest_raw_messages.dart:1806-1820` | `own_account` is inferred from the mask shape alone, for every template and the generic reader. `own_account` is not a neutral label: `transfer_pairing.dart:490` then marks the row a one-sided internal transfer (`is_internal = 1`), and the categorizer returns `internal` with no category. Internal rows drop out of spending/income totals, payday detection (`payday_auto_service.dart:167`), refund matching and notifications. A transfer to **someone else's** masked account is common in templates with a free counterparty group (`arab_bank.instapay_out.ar` `الي (?<counterparty>[^.]+?)`, hdfc/bunq/n26 `to/from (?<counterparty>.+?)`), and the generic reader deliberately keeps `*` tokens (`generic_parser.dart:1370`). Probe (a): `تم تنفيذ تحويل لحظي بمبلغ EGP 5000.00 ... الي 0021234***5678 ...` from `ArabBank` → stored `transfer_out`, `counterparty_kind = own_account`, `is_internal = 1`, own transfer pair, `category_source = none`: a 5,000 EGP payment to a third party silently vanishes from spending. A salary from an employer's masked account would likewise vanish from income. The mask regex is also loose: any name with `xx`/`XX` and a digit (`Exxon 24`, `Maxx 2`) matches. | Do not infer "own" from a mask. Either (preferred) let the template say it: a template-level flag (or the `cc_payment` event on a card-destination template such as `hsbc.cc_payment_transfer.en`, whose wording "to your credit card" proves the source is the user's) maps the counterparty to `own_account`; everywhere else a masked account gets a kind that neither pairs nor hides (e.g. keep the mask out of `person` by storing no counterparty kind / putting it in `reference_no`, per the original m-1 suggestion). Test: the probe (a) message stays `is_internal = 0` and in totals; HSBC case 10 keeps `own_account`. |
| m-1 | minor | `packages/zaghlol_parsing/lib/generic/shape_signature.dart:56-58` | Tokens are now cut from the original body and folded one by one. Arabic diacritics (`\p{Mn}`, e.g. `مُبلغ`) and other marks that `foldKey` removed before now split words, so the same shape gives different signatures with and without tashkeel, and an Arabic cue word with a mark is lost. Diagnostics only. | FU-313: strip marks (or tokenize the folded text and read the original casing via `folded.origin`) before the Title Case test; add a tashkeel case to the test. |
| m-2 | minor | `app/test/features/settings/debug/debug_sms_diagnostics_test.dart:54-57` | The FU-306 test only asserts the constants, not that the query is ordered newest-first and limited. | FU-314: seed 501 unread rows and assert the oldest is not read. |

---

## T-249 — card dues: due day in step, atomic payment hook, zero due, due-line goldens (C3) — APPROVED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| FU-301: notice moves due day → sync leaves the date | PASS | `card_dues_ingest_test.dart` "T-249 FU-301…"; `card_dues.dart:171` writes `dueDay` = the card's day, which is what `syncCardDues` compares (`recurring_repository.dart:568`) |
| FU-302: injected reminder failure leaves the payment uncounted | PASS | "T-249 FU-302…" (trigger `RAISE(ABORT)`); `onPayment` wrapped in `_db.transaction` (nested savepoint inside the message savepoint; the hook still swallows) |
| FU-304: zero total and minimum = nothing due, paid line, no reminder created; lone zero minimum is not | PASS at the dues layer | `card_due_test.dart`, `card_due_line_test.dart`, "T-249 FU-304…" ×2 |
| FU-303: due/partial/paid goldens ar/en × light/dark from app-regen | PASS | 12 PNGs, committed by `github-actions[bot]` (9b8a9946) |
| `flutter analyze` clean | PASS | |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| m-3 | minor | `app/lib/features/recurring/data/card_dues.dart:62-64` (with the parser) | FU-304 is not reachable from a real message today: the parser drops zero amounts, so a "total 0.00, minimum 0.00" statement arrives with neither amount, has no currency and is discarded at `onNotice`. The previous cycle's reminder then stays as it was. The rule is correct and tested at the dues layer, but the user-facing case it was written for still behaves as before. Worth an FU, not a blocker (nothing is marked paid on doubt). | FU-315 (parsing lane): keep explicit zero `amountDue`/`minDue` on `cc_statement`/`cc_due` notices (transactions keep dropping zero), with a synthetic fixture; then an ingest test from SMS to "nothing due". |
| n-1 | nit | `app/lib/features/accounts/domain/card_due.dart:143-160` | A newer notice for the same due date with total 0 and no minimum inherits the stored minimum, so `nothingDue` is false and the reminder is set to amount 0 while unpaid. Only reachable after FU-315. | Cover in FU-315. |

---

## T-250 — old due reminders saved as spending: Remove/Keep offer (C4) — CHANGES_REQUESTED

### Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Case 7 auto-saved → one review item after re-parse, transaction still live and in totals | PASS | `old_due_offer_test.dart` "case 7 auto-saved…" |
| Remove → gone from totals (`TransactionsChanged`), Undo restores, not re-offered | PASS | "Remove: …" |
| Keep → stays, verified, never offered again; Remove after Keep no-op | PASS | "Keep: …" |
| Edited transaction (verified / note / user category) → no item | PASS | "negative proof 1" |
| Re-parse twice offers once | PASS | "negative proof 3" |
| Strings ar (colloquial) + en; buttons act only on tap; swipe never removes | PASS | `review_old_due_test.dart`; `app_ar.arb`/`app_en.arb` |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| M-2 | **major** (data) | `app/lib/features/ingestion/application/ingest_raw_messages.dart:493` → `app/lib/features/recurring/data/card_dues.dart:123-176` | Re-parse now feeds every old `parsed` notice row to the dues hook. Newer-wins holds against a stored newer due (`mergeNotice` rejects `<=`), but when no newer due is stored (a phone that skipped the batch 67–69 builds, or no notice since), the newest **old** notice becomes the card's due with `paid = 0` (re-parse never replays the payments already stored) and `_applyTo` has no date guard. Probe (b): a notice received 120 days ago, due `25/07` → stored due `2026-07-25`, `paid 0`, `applied: true`, and the card's `card_due` reminder set to `next_due_date 2026-07-25`, amount 51.77, on 2026-11-25. The card detail shows an unpaid due and the reminder is months overdue for a statement the user long paid. This happens on exactly the phones T-250 targets. | At re-parse, do not apply a notice whose due date is before today (local): skip the hook for it (or store it without touching the reminder or showing it). Live ingest and the inbox scan keep the current behaviour. Test: probe (b) leaves no reminder and no unpaid due line; case 7 with a future due still applies. |
| m-4 | minor | `app/lib/features/ingestion/application/old_due_review.dart:24-34` | Remove is check → delete → resolve in three separate transactions. If the resolve throws after the delete, the transaction is deleted, the screen shows "save failed" with no Undo, and the item stays open but hidden (`_toCard` drops it). A Keep in the window deletes then restores the row (two `TransactionsChanged`). The final state is correct in the tested race. | FU-316: resolve the item conditionally first and delete in the same write transaction (roll back on any failure), so the snackbar Undo always matches what happened. |
| n-2 | nit | `app/lib/features/ingestion/presentation/review/review_screen.dart:374-378` | When the offer no longer applies (edited, kept elsewhere), Remove shows `reviewErrorSaveFailed`, which reads as an error. | FU-317: a neutral "already handled" message, or just refresh. |
| n-3 | nit | `app/lib/features/ingestion/data/drift_ingest_store.dart:417-431` | The offer does not exclude a transaction recorded in `recurring_occurrences` (the user marked a reminder paid with it). Only a question, so safe; noted for completeness. Idempotency also relies on resolved items never being purged (`purgeResolvedBefore` has no caller); a future caller must keep `oldDueNotice` items. | FU-317: add the `recurring_occurrences` clause and a comment on `purgeResolvedBefore`. |

### Security / data safety
- **Nothing removed without a tap: holds.** Re-parse only stamps the row, calls the dues hook and inserts `low_confidence` items (`_reparseNotice`); no delete, no field change on the transaction. Removal happens only in `OldDueReview.remove`, reachable only from the card's Remove button. Swipe on the card is end-to-start only (`canAccept` false) and calls `ReviewRepository.dismiss`, which only resolves the item (`txn_id` set, raw status untouched). No accept path exists for this card.
- **Who can be offered: holds.** One SQL read requires live, background source (sms/notification/shortcut/apple_pay), `expense`/`fee`, `is_user_verified = 0`, `category_source <> 'user'`, `note IS NULL`, no transfer pair, not internal, no split, no offset link on either side. Remove re-checks open + reason + live + unverified. Manual/voice/OCR/PDF/CSV/share rows never offered.
- **Idempotent: holds** (NOT EXISTS over items of this reason in any state; test with a forced second re-parse). See n-3 for the purge caveat.
- **Keep/Remove race: final state correct** (Keep wins, delete undone; test "two actors"); atomicity improvement in m-4.
- **Raw message with several transactions:** each eligible transaction gets its own item; `txnOfRaw`'s single-row assumption is not used on this path.
- **Old notice vs newer due:** never overwrites a newer stored due; but see M-2 for applying a stale one when nothing newer exists.
- **Privacy:** payload is `{"reason":"oldDueNotice"}` only; no message text in payloads, diagnostics (`REPARSE_OFFERED` count) or logs; no new logging; no network.
- No schema change; `review_items.kind` CHECK unchanged.

---

## Follow-ups (minors / nits)
| FU | From | Owner lane |
|----|------|-----------|
| FU-313 | T-248 m-1 (signature tokenisation with tashkeel) | parsing |
| FU-314 | T-248 m-2 (diagnostics LIMIT test) | app core |
| FU-315 | T-249 m-3, n-1 (zero amounts on notices dropped by the parser) | parsing |
| FU-316 | T-250 m-4 (Remove atomic) | app core |
| FU-317 | T-250 n-2, n-3 (Remove copy, `recurring_occurrences` clause, purge note) | app core |

## Delta re-review (Sonnet)

Delta `15b7b7fc..34feb1c6` (fix/fix70). Analyze clean; registry lint 1425/1425, 0 findings; `po_suite` + `notices` pass; app ingestion, features/ingestion and features/recurring pass (455, goldens excluded).

Targeted fail-before proof, run in a clean worktree on the merged tree, then restored (tree clean):
- M-1: restoring the old mask inference (`_isMaskedAccount(c.name!) ? 'own_account' : 'person'`) makes 3 tests in `fix70_counterparty_test.dart` fail (masked Arab Bank InstaPay out, masked-employer salary, "Exxon 24"). The HSBC case-10 test, the FU-315 test and the M-2 tests still pass.
- M-2: replacing the `_dueIsPast` guard with `if (true)` makes exactly 1 test fail ("a notice with a past due date changes no due and no reminder"). The future-due test still passes.

| Item | Verdict | Notes |
|---|---|---|
| M-1 | RESOLVED | `own_account` now only when the template sets `counterpartyOwnAccount` (only `hsbc.cc_payment_transfer.en`, version bumped, registry and guard versions bumped). The pipeline sets it only when a name was extracted. The mask regex is gone, so no other path marks a masked third-party account internal. Everything else is `person` as before T-248. |
| M-2 | RESOLVED | The guard is only in the re-parse path (`_dueIsPast`, UTC-midnight date against today's local date). Live capture and the inbox scan don't call it. A null due date still applies. |
| FU-316 | RESOLVED | Check, conditional resolve and delete run in one `_db.transaction`. The resolve comes first, so a Keep that landed earlier makes it return null with nothing deleted. A throwing delete rolls the resolve back, and Undo restores the delete batch. Minor note, no action needed: any non-DB side effects inside `TxnBulkActions.delete` (undo image, change event) happen before commit, but the delete is the last step. |
| FU-315 | RESOLVED | A zero amount or minimum is kept only for `ccDue` and `ccStatement`. Other events still reject zero, and the notice path never produces a transaction. `mergeNotice` now sets min due to 0 when the incoming total is an explicit 0 with no minimum. Test covers a real 0.00 statement and a zero purchase staying a non-transaction. |

New blocker/major: none.

Verdict: APPROVED.
