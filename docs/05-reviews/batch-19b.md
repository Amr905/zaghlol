# Batch 19b review (T-116, T-114, T-084, T-057, T-153, T-164, T-160, L10N-topup)

Reviewer: code-reviewer (code + security). Read the production diff of each task branch against batch-18. Ran `flutter test` on the backup presentation, card detail, onboarding, capture presentation and OCR tests: 158 passed. Swift read only (CI green per the review rules).

## T-116 currency switcher + ZApproxRow: APPROVED
- Widgets take finished strings and add nothing; single-currency shows no switcher (EC-55). The batch commit 79af9c17 now uses `accountsOverviewApproxNotIncluded` in `z_currency_switcher.dart:100`.
- minor `home_screen.dart`: `animateToPage(indexWhere(...))` is not guarded against -1. Unreachable today (codes come from `figures`).

## T-114 Gold charts: APPROVED
- Every provider is keyed by one currency code and `_filter(code)`; nothing is summed across currencies. Net worth is per unit.
- Gating: S-20 uses `decideChart(entitlementState, id)` and builds `GoldChartCard` only when allowed, so a Free user triggers no Gold provider. S-21 gates through `_LockedDetail`.
- minor: the `isEmpty` for inflation is `length < 2`, and the cards opener hook is null until the shell wires it (builder note).

## T-084 card detail S-41 / compare S-42: APPROVED
- All reads go through the chart repository per (account, currency). S-42 has a currency chip, and category rows come from per-card donuts in the picked currency. No cross-currency sums.
- minor `card_detail_providers.dart` (`compareDataProvider`): the "Total" row uses `cardsSplit.spend`, and the cells use donut slices. The repo tests only check slices vs `donut.total` on a fake. If `_byCategory` drops a category whose net is <= 0 (refunds), the column may not sum to its total. Follow-up: add a repository-level test, or take the total from the slices.
- minor: the compare table width uses `double` constants for layout only (not money).

## T-057 scan results S-06: APPROVED
- Shows counts, card labels and last4 only; no message body, sender or amount. 0 found goes to `onDone` through a post-frame callback.
- Ignore creates rules with `KeepExisting` (no data removed) and shows a snackbar.
- minor `scan_results.dart` `_ignore`: with `last4 == null` the rule covers the whole institution, but the UI reads as "this card". Only sms and notification channels are covered. Follow-up.

## T-153 backup & restore screens: CHANGES_REQUESTED
- Passphrase handling is fine: it is held only in controllers, which are cleared on dispose. The result goes straight to the services, there is no logging, errors are code-only kinds, and `keys.zeroize()` is called. The 10-character minimum, the confirmation and the "can't be recovered" tick are enforced.
- The restore flow order matches FU-139: pause, restore, invalidate the DB, recover the key if needed, resync, read and clear the flags, then resume in `finally`. A wrong passphrase before the swap leaves the state at `found` (unlimited retries).
- **major (data loss) `restore_screen.dart` (constructor) / `restore_flow.dart:restore`**: the screen is also reached from S-66 "Restore a backup" (`onOpenRestore`) on a phone that already holds data. The "Restore" button calls `restore()` at once. The T-149 swap replaces the live database, and the user gets no confirmation and no "this replaces what is on this phone" warning. Nothing may destroy data without confirmation.
- minor `backup_ports.dart` `DbRestoreSideEffects`: `pause`, `resume` and `resyncCatalog` are no-ops. The sync and capture pause that FU-139 relies on is not wired, so a capture write racing the swap can be lost. The owner task must override `restoreSideEffectsProvider`; track it as a follow-up.
- minor: the old-backup deletion after a passphrase change (PO T-148 Q1) is not in this UI and is not triggered. That is fine as long as the owner task asks for confirmation first.

## T-164 custom template builder: APPROVED
- Regex safety: the user never writes a regex. The generator emits bounded shapes only (`{1,60}`, `{0,N}?` <= 300), caps the pattern length, runs `backtrackingProblems`, and requires a compile and a self-parse. `fromJson` re-validates stored JSON as untrusted input (v, channel, sender, groups, date format, currency map, length) and never throws. Built-in senders win over custom ones.
- Privacy: `toString` is redacted on the spec, the sample and the state. Errors are codes. Only `sha256(foldKey(sample))` is stored. The state is cleared after saving and the notifier auto-disposes. No logging.
- Gold gate: `gateOrPaywall` in `save()`.
- minor `template_builder_screen.dart:~177`: the paste field has no `autocorrect: false` / `enableSuggestions: false`, so the keyboard may learn bank text.
- minor: the hash is unsalted SHA-256 of a short message (the task asks for a hash). The builder notes list the unwired parts (pipeline registration, re-parse hook, route); they are follow-ups.

## T-160 iOS OCR host + Dart OCR port: APPROVED (follow-up needed)
- The image is decrypted in memory and zeroed after use. The encrypted file is deleted in a `defer`, except for NOT_AVAILABLE. Errors are code-only and nothing is logged. The path check resolves symlinks and `..` and requires a path inside the container. The size is capped at 25 MB and AES-GCM carries AAD with the file name. Arabic is used only when Vision lists it. Dart `OcrTextLine`/`OcrException` redact text and path.
- major (functional, not a security or data-loss item, so not blocking) `OcrHost.swift`: `OcrPaths.isInside` uses `NSHomeDirectory()`, but the iOS spool is in the App Group container (`Shared/SpoolLocation.swift`). Spool files would be rejected as IO_ERROR. With `UnprovisionedSpoolKeyProvider` always returning NOT_AVAILABLE, iOS OCR cannot work end to end yet. Follow-up for the Share Extension owner: allow the spool/files dir of the App Group, provision the key, and restrict deletion to that directory instead of the whole container.

## L10N top-up: APPROVED
- 11 keys with matching placeholders (`currencies`, `time`, `count`) in both locales, and the generated files are in sync. Arabic is colloquial («مش محسوبة»، «خد نسخة»، «ظبّط»). `money_tab.dart` uses the new key.
- minor: the Arabic plural has only `=1` and `other`, so "11 مبالغ" is slightly off grammatically. Acceptable.

## Fix list (blocking only)
| Task | File:line | Required change | Test to add |
|---|---|---|---|
| T-153 | `restore_screen.dart` (widget + found state), `restore_flow.dart:restore` | Add a `replacesExistingData` parameter, set true when opened from S-66 (and whenever the DB already holds data). When true, tapping "Restore" shows a confirm dialog («هيستبدل اللي على الموبايل ده») and calls `restore()` only after the user confirms. Add the l10n keys in ar and en. | Widget test: with `replacesExistingData` true, tapping Restore calls no `gateway.restore` until the dialog is confirmed, and cancel leaves the state at `found`. A test with false restores directly. |

## Lead delta check (fix round 19)

Commit `e119a0bc` (about 40 production lines incl. generated l10n; tests fail without the change):
- **T-153:** `RestoreScreen.replacesExistingData` asks before `restore()`; S-66 / Settings passes true, Welcome passes false. Two new widget tests (ar and en): with the flag, no `gateway.restore` until confirmed and cancel stays `found`; without it, restore runs directly. Correct.
- The native drain hold during restore was not possible (no pause API on either host); logged as FU-194, before release. The extra "database already has data" check is FU-197.

Verdict: APPROVED.
