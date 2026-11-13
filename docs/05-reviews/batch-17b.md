# Batch 17b review: T-101, T-106, T-085, T-080, T-162

Reviewer: code-reviewer (code and security). Batch tree `batch/2026-11-14-18`.
Ran: `flutter test --exclude-tags benchmark,golden` on insights, budget, settings, accounts and transactions: 545 passed, 0 failed. Golden tests not run.

## T-101 Insights shell and Budget S-22: APPROVED
- Percent and "not budgeted" math is integer only (`budget_view.dart:132`). Budgets count per currency and are never summed across currencies. Limits parse through `MoneyFormat.parseInput`, which normalises digits and rejects extra decimals. A comma in a limit is invalid, not silently stripped.
- minor `budget_saver.dart:30-55`: the delete, update and insert writes are not in one DB transaction. A failure partway can leave budgets deleted or half-updated. The draft is still on screen, so the user can re-save. Wrap the body in `db.transaction` (follow-up FU).
- nit: rollover carry-in is not applied to the S-22 bars, and the annual list and S-72 are callbacks (builder-noted, not blocking).

## T-106 Explanation engine: APPROVED
- The engine returns typed args (`MoneyArg`, `PercentArg` in basis points, and so on) taken from the chart results. Percentages use `mulDivRound` and `Money.mulDiv` with integer math, and there is no `double`. A line whose values can't be computed is dropped whole. The basic tier never reads `previous*` inputs.
- Q-20: no disclaimer line is emitted. Q-24: no halal wording. Q-25: tips skip essential categories and protected merchants. Facts may still name them.
- minor `explanations.dart:258`: `defaultEssentialCategoryIds` is a second copy of the Q-25 set, and it differs from `zaghlol_domain/lib/mascot_rules/mascot_rules.dart:30`. This copy has `transport_work`, `utilities` and `installments`. The domain copy has `work_transport`. If the seed id is `work_transport`, work transport can be targeted by a tip. Use one shared constant and check it against the catalog seed ids (T-108 should pass the catalog's ids, as the builder noted).

## T-085 Add/edit card S-43, merge: APPROVED
- Merge goes through `AccountsRepository.merge`, which is existing code and not part of this diff. It moves transactions, recurring items and balances in one DB transaction. Balances are matched per currency: the newer figure wins and per-currency rows are never summed. The default cash account can't be merged. The UI confirms first and warns when the bank differs. Merged accounts are excluded from the candidates and from net worth. No money is lost or double-counted by the UI path.
- `createCard` finds an existing institution and last-4 and returns it as a duplicate, so no second account is created. The limit is parsed with `Money.tryParse` after digit normalisation.
- minor `merge_flow.dart:44`: `catch (e) on Object` swallows the error code. This is acceptable because nothing is logged, but a typed code would help support.
- minor: the "which balance wins" outcome (one balance replaced by the newer one) is not said in the confirm copy. Product call, not blocking.

## T-162 Settings S-60: APPROVED
- The contribution opt-in calls `ContributionQueue.setOptIn`. It writes the setting and deletes queued contributions in one transaction (EC-48).
- Turning app lock on writes `hideAmountsNotifications = true` (FU-130), after `enable` returns `enabled` only.
- The delete-everything dialog requires typing DELETE or احذف, and shows the last backup and the iOS key notes.
- The server-knows list is generated from the `ServerKnows` enum, and the copy `switch` has no default. It covers the D-45, D-48, D-55 to D-62 and FR-PAR-14 items: app id, purchase, sign-in, merchants, versions, attestation, bank request, time nonce, seat keys (iOS only), delete-keeps-keys (iOS only) and the support notices. It matches BR-SYNC-03. Nothing financial appears in it.
- minor `privacy_screen.dart:164-168`: if `wipeEverythingProvider` is null the confirmed delete does nothing and says nothing, and the "Deleting…" message is not shown. An exception from `wipe()` is not caught. The default is null until T-174, so this can't hit users yet. When T-174 wires the provider, catch the error and show `commonErrorSaveFailed`.
- minor: D-55 requires a warning before "Delete everything" on Android when the phone holds Gold. The dialog doesn't read `goldPlanProvider` and there is no l10n key for it. Needs a key and a follow-up. Tracked as a follow-up because Gold is not yet wired.

## T-080 Transaction detail/edit S-12/S-13: CHANGES_REQUESTED
- Good: EC-40 repair runs inside the edit's own transaction (`drift_transaction_repository.dart:157-162`, hook `reimbursements.dart:347`). It uses the same DB, so it nests in that transaction and the schema trigger can't fire. Deletes use `BulkActions.delete`, which soft-deletes then runs the pair and refund `onRemoved` hooks and offers Undo. `onPersisted` for pairing and refund matching runs after save in `TransactionEditor._afterSave`. The detail raw body is only displayed, never logged.
- **MAJOR (money)** `txn_form.dart:38`: `parseAmount` does `normalizeDigits(text).trim().replaceAll(',', '')`, so every comma is treated as a thousands separator. A user whose keypad produces a decimal comma (the numberWithOptions keyboard follows the system locale, and pasting is unrestricted) who types `12,5` stores 125.00. `12,50` stores 1250.00. The amount is silently 10x to 100x too large, and the field has no `inputFormatters`. Fix: accept a comma only as valid grouping (`^\d{1,3}(,\d{3})+(\.\d+)?$`). Otherwise reject with `amountDecimals` / `amountRequired`, or treat a lone comma followed by at most `exponent` digits as the decimal point. Also restrict the field with an `inputFormatter`.
- minor `transaction_edit_screen.dart:274`: the edit sends the amount through the hook. The repair `event` (cycles to refresh) is dropped in `onAmountChange` (`transactions_providers.dart:44`). Cycle and budget views may stay stale until the next change event. Publish `RepairResult.event` after the commit.
- minor: the EC-40 notice reuses `transfersAssignErrorExceedsExpense` until `transactionsEditLinksRemoved` is added (builder-noted).
- minor: a currency chip change on an edit with no links silently re-denominates the row. It is the user's explicit act, but a currency change in edit mode should probably be disabled (the amounts are not converted).
- nit: contextual cards on S-12 are not built (builder-noted).

## Fix list (blocking only)
| Task | file:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| T-080 | `app/lib/features/transactions/presentation/edit/txn_form.dart:38` | Don't blanket-strip commas. Accept them only as valid thousands grouping. Reject, or read as a decimal, a comma that isn't grouping. Add a decimal-pad `inputFormatter`. | `parseAmount('12,5', EGP)` is not `125.00` (error, or `12.50`). `parseAmount('1,250.50', EGP)` is `1250.50`. `parseAmount('١٢٫٥', EGP)` is `12.50`. |
