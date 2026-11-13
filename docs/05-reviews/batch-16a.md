# Batch 16, review half A (T-053, T-054, T-079, T-083)

Reviewer: code-reviewer (Sonnet). Scope: production diff per task (`origin/main...origin/task/<branch>`, own files only), AC to test map spot-checked, tests run.
Tests: `flutter test --exclude-tags benchmark,golden` over home, transactions, money, mascot, accounts on the batch tree: 258 passed, 0 failed. Goldens not committed (app-regen).

## T-053 ZaghlolAvatar - APPROVED
- Single file, no strings, no money, no logging. Ignores pointers, still pose when reduce motion (OS or app) or no artboard; label null makes it decorative.
- nit: `zaghlol_avatar.dart:32` the `set` method on a Riverpod 3 notifier is fine, comment is redundant.
- nit: `zaghlol_avatar.dart:60` the `Semantics(excludeSemantics: true)` plus inner `ExcludeSemantics` is doubled; harmless.

## T-054 Home S-10 - APPROVED
- Money per currency only (`home_widgets.dart` figures per currency; no cross-currency fold found). Spending uses `c.text` (ink); red is only used for banner error tone.
- No amount reaches logs. No hard-coded user strings seen in home files; all via AppLocalizations.
- minor: `home_screen.dart:128` error branch discards the error (fine, nothing logged) but offers no retry; follow-up.
- minor: `main.dart` change is wiring only; ok.
- Text scale 1.3: no fixed-height containers found around text in the diff; no finding.

## T-079 Transactions list S-11 + bulk_actions - CHANGES_REQUESTED
Delete path verified: `BulkActions.delete` (`bulk_actions.dart:54-62`) does the soft delete in one all-or-none transaction, then calls `TransferPairing.onRemoved` and `RefundMatching.onRemoved` for every deleted id. Day totals are per currency (`dayTotals`). Undo snackbar present with SafeException handling.

- **major** `bulk_actions.dart:65` + `transactions_list_screen.dart:353`: Undo restores the rows via `BulkEditUseCase.undo` but nothing re-establishes what `onRemoved` dissolved. A restored transfer leg comes back unpaired (and a restored refund unlinked), so it is counted as spending/income again and totals are wrong until the user re-pairs by hand. Required change: `BulkActions.undo` must, for the restored ids, re-run `TransferPairing.onPersisted` and refund matching (or an equivalent re-link), with a test: delete a paired transfer leg, undo, assert the pair/link is back and the transfer is excluded from spending.
- minor `bulk_actions.dart:57-61`: hooks run after the delete transaction commits, so a hook failure leaves rows deleted with stale links and the screen shows "save failed" with no Undo. Wrap or surface; follow-up acceptable once the major above is fixed.
- minor `transactions_list_screen.dart:353`: the Undo `onPressed` has no mounted check before `ref.invalidate` after an await; guard it.
- nit: `required this._bulk` private-named params rely on the current Dart language version; analyze passes, fine.

## T-083 Money tab S-40 - APPROVED
- Net worth is per unit (`net_worth_repository.dart` header and code; no cross-currency sums found), accounts show their own currency with "as of" times, hidden accounts entry present, no amounts in logs.
- minor `gating.dart:20`: enum `foreignAssets` renamed to `investmentAssets` in a UI task; analyze passes on the merged tree so no dangling users, but it is outside the task's scope and should be noted in the status docs.
- minor `money_tab.dart:444` `_AssetsPlaceholder`: placeholder section is shipped; confirm it is gated/flagged until the assets task lands.

## Fix list (blocks under the sprint rule)

| # | Task | File:line | Severity | Required change |
|---|------|-----------|----------|-----------------|
| 1 | T-079 | `bulk_actions.dart:65`, `transactions_list_screen.dart:353` | major (money) | Undo of a delete must re-pair restored transfer legs and re-link refunds (`onPersisted` / refund re-match for restored ids); add a test for delete then undo of a paired transfer. |
