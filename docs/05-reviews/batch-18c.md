# Batch 18c review (T-102, T-081, T-086, T-121, T-093)

Reviewer: code + security, one pass. Scope: production diff of each task branch, AC to test map, targeted test run. Sprint rule: only blocker or major findings touching money, security, privacy or data loss block.

## T-102 Bills S-24 / S-25 — APPROVED
- Card dues cannot be marked paid by hand: guarded in the repository (`recurring_repository.dart` `markPaidManual`, kind check) and in the view (`bills_view.dart:43` `canMarkPaid`). Double guard holds.
- `markPaidManual` runs in one DB transaction; the occurrence claim (`INSERT OR IGNORE`) makes a second tap a no-op, so no double count. `progressAfterPayment` is reused, no new arithmetic.
- `deleteItem` relies on the FK cascade for occurrences; confirmed by a dialog in S-25.
- minor: `updateManual` doc says "keeps ... status", but it always writes active/completed (`recurring_repository.dart` ~L349). Only active items are reachable from the UI, so no data effect. Fix the comment or the code later.
- minor: `updateManual` does not check that the id exists before validating; returns false, UI shows saved snackbar regardless (`bill_edit_screen.dart` `_save`). Follow-up.

## T-081 Review queue S-14 — APPROVED
- Raw SMS never shown or logged: `review_providers.dart` `_sender` reads only `rawMessages.sender`; models carry sender, amount, merchant and ids. No log calls in the three files.
- Deferred apply on Undo is correct: pending job map, Undo removes it, `closed` applies it, `dispose` flushes the rest (`review_screen.dart` L41-L100). Replacing a snackbar closes the previous one, which applies its job, so nothing is lost or applied twice (repo `_resolve` is idempotent).
- `resolveManually` is not called from the screen at all, so the "only where allowed" rule cannot be broken here; the repository still enforces kind and `txnId == null`.
- Request-bank sends only name, country and channel; repository validates with `hasPersonalDataMarks`.
- minor: a throwing deferred job in `.closed.then` is unhandled and leaves the item hidden until the next queue reload (`review_screen.dart` L84-L88). Wrap in try/catch and show `commonErrorSaveFailed`.
- minor: `categorize` edits the transaction and resolves the item in two calls (not atomic); a failure between them leaves the item open on an already-categorized transaction. Harmless, re-acceptable.

## T-086 Capture settings S-61 / S-62 — APPROVED
- Delete of existing transactions needs two explicit steps: the stop-tracking dialog (default Keep) then a second `_DeleteSureDialog` (`card_capture_sheet.dart` L135-L156). S-61 add path never passes `DeleteExisting` (KeepExisting default), so it cannot delete.
- `IgnoreRulesService.add` intersects `confirmedIds` with what still matches at write time and deletes through `BulkEdit` (soft delete, undoable batch); unseen rows are never deleted. Pair legs get `onRemoved`.
- All rule writes go through `IgnoreRulesService`; Guard config rewritten before return. Undo removes only rules this action created; deleted data stays deleted (stated in the file header).
- Play-build variant: re-scan row and offer depend on `canRescan = scanService != null && rescanAvailable`, so builds without SMS read hide them. iOS uses the Apple Pay channel.
- minor: the re-scan offer after un-ignoring calls `rescan(depthMonths: kDefaultScanDepthMonths)`, which writes `scanDepthMonths` and overwrites the user's saved depth (`capture_settings_screen.dart` L497-L503, `capture_controls.dart` `rescan`). Only persist the depth from the explicit re-scan sheet.
- minor: `gating.dart` renames `foreignAssets` to `investmentAssets`; shared with T-121, intended.

## T-121 Assets S-44 / S-45 — APPROVED
- Parsing is exact and integer-only: `parseMilli` (regex, max 3 decimals, no `double`), `parseRateBp` (max 2 decimals, 0..100), money through `MoneyFormat.parseInput`. Digits normalized first.
- Gold stays in native units: milli-grams per karat symbol and coin counts (coin = count x 1000 milli). `goldUnits` renders per unit; value only via `valueGold` (`mulDiv`, half-even) and only when the price's `perUnit` matches the symbol.
- Nothing sums across currencies in the presentation: per-asset rows show their own currency; cash without a rate shows "no rate" instead of converting.
- minor: certificate/stock names have no length cap in `validateAssetForm`. Add the 60-char rule used elsewhere.
- minor: if `pricePaid` is typed but no currency is chosen, the error lands on `AssetField.currency`, which gold form does not render. Follow-up.

## T-093 Split / link sheets S-15 / S-16 — APPROVED
- Writes go through `Reimbursements` and `TransferPairingUseCase` only (`drift_transfers_sheet_port.dart`); the port holds read queries and no direct writes.
- A reimbursement is not counted as income: `assign` is clamped by `planReimbursement` and DB triggers (expense, source, participant, currency); what is not assigned stays income (BR-XFR-06). Candidates are same-currency expenses with room. Net spend uses `netOfOffsets`.
- Removing a participant who has repayments keeps the links (`offset_links.participant_id ON DELETE SET NULL`), so no reimbursement is lost.
- Share and assign amounts parse through `MoneyFormat.parseInput` in the expense's currency; sums are checked in integer minor units; implied rate uses BigInt.
- minor: `saveSplit` applies removals, updates and adds as separate calls, not one transaction; a failure part-way leaves a partially saved split (each step valid). Wrap in a DB transaction later.
- minor: Undo of an unassign does not catch errors (`split_sheet.dart` L131-L140); `assign_sheet.dart` L91 `firstWhere` can throw if the candidate list reloads under a picked row.
- minor: "mark anyway" is hidden (`supportsMarkAnyway` false); known gap (EC-15), recorded in the task file.

## Tests
161 tests in recurring, review, capture/presentation, wealth/presentation and transfers presentation passed (golden and benchmark excluded).

## Fix list (blocking findings only)
| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| none | | | |
