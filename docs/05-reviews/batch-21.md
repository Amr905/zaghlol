# Batch 21 review (T-067, T-174, FU sweep 1, FU-213)

Reviewer: code-reviewer (code + security). Tests run on the batch tree: `flutter test --exclude-tags benchmark,golden` over a11y, onboarding, backup/presentation, review, notifications, privacy, app, accounts, transfers, insights: all 956 pass. Swift/Kotlin read only.

## T-067 iOS setup S-03: APPROVED
- Gate: iOS Welcome -> `iosSetupScreen` -> `onFinish` (app_navigation/onboarding_gate). Skip at every step calls `onSkipped('ios_shortcuts')`; `recordSetupSkip` maps it to `skip_shortcuts` (a valid step in setup_steps.dart). "Finish setup" on iOS now opens the same screen.
- Wallet rule matches PO_DECISIONS T-064: `applePay` row is OK when `wallet.neverRan || !wallet.flagged`; the message rows are always checked. "Cannot tell" shows an info banner, never a failure.
- No message or amount is shown or logged; the install failure path is caught and shown as a banner.
- minor: `ios_setup.dart` `_skip` and gate `onSkipped` fire `recordSetupSkip` unawaited, then `onFinish`. Two settings writes race only if `onFinish` also writes `setup_progress`; it writes `setup_installed_on`, a different key. No action.
- minor: Step 1 has no way back from step 2/3. Matches spec flow; no action.

## T-174 a11y and golden pass: APPROVED
- `expectA11yGuidelines` (test/support/a11y_guidelines.dart) really runs Android 48 dp, iOS 44 pt, labeled-tap-target and text-contrast guidelines, and asserts `takeException()` is null (overflow). It is not a no-op.
- `ZCard` `MergeSemantics` only when `onTap != null`. I checked all 7 files that pass `onTap` to a `ZCard`: no tappable card contains a nested button, switch or other action, so no semantics are lost. The tappable card's own text becomes its label.
- minor: `bills_screen.dart:266` wraps the card in `Semantics(container: true, label: ...)` and the card now also merges its text, so a screen reader may read the row twice. Cosmetic.
- Defect fixes are correct and minimal: card detail `Row` -> `Wrap` (no overflow at 1.3x), donut legend amount in `Flexible`, link-sheet radio row `MergeSemantics` (replaces `container: true`, so the radio and its text form one node).
- Note: task/T-174b is a superset of T-174-a11y plus T-067; the merge is clean.

## FU sweep 1: APPROVED (minors only)
- FU-197: `restoreReplacesLocalDataProvider` checks `transactions` for any row (soft-deleted ones count, which is the safe side) and then the spool `pending > 0`. A failed DB read falls through to the spool; a failed spool read returns false, and the caller's `replacesExistingData` still asks. The confirm now gates a data-loss path from Welcome as well as from Settings. The test for the Welcome path proves `restore` is not called before the confirm.
- FU-215: logging regex now tolerates whitespace before `(` in both CI grep (`[[:space:]]*`) and `source_guards_test` (`\s*`); negative proofs for `print (x)` and tab added.
- Review pair labels: the merchant is the title and the account label is real (`_accountLabel`), no longer the merchant stuffed into `accountLabel`. Merchant goes through `_iso` (bidi isolate). OK.
- FU-214 budgets, checked against the first perf run (job 132314367152 of run 43551378324): generic parse 69 us -> limit 90; pipeline 83 us -> 110; FTS search p95 57.9 ms -> 75; categorizer p95 4.92 -> 6.5 and 8.85 -> 11.5. All are 1.3x one sample, as PO_DECISIONS T-173 says.
  - minor (CI flake risk, not blocking): sub-100 us means over 4000 runs and single-digit-ms p95 on a shared runner are noisy; the same job shows `like_short_ms` 4.7 -> 438 ms between passes. A 1.3x ceiling off one sample will probably go red on some run. Suggest 2x for the microsecond tests and the categorizer, and keep the 200 ms FR-TXN-01 gate as the hard line for search (75 ms is tighter than the spec gate). Follow-up, not before merge.

## FU-213 notification settings: APPROVED
- Toggles write the same `NotificationType.toggle` keys, `quietHoursEnabled`, `quietHoursStartMin/EndMin` and `hideAmountsNotifications` that the service reads. Loaded values come from the repo, so the `?? true` fallback in `on()` is only used before a load.
- Permission flow: asked on the first enable (no type was on) or while the OS state is off (`_osOff`); the result updates the denied banner. The denied banner shows only when permission is off and some type is enabled, with an Open settings button. Matches NOTIF-GW (asked on first enabling).
- Quiet hours: equal start and end is rejected with a message and not stored.
- `openSystemSettings`: Android uses `ACTION_APP_NOTIFICATION_SETTINGS` with `EXTRA_APP_PACKAGE` and `FLAG_ACTIVITY_NEW_TASK` (valid from an application context); iOS opens `UIApplication.openSettingsURLString` on the main queue. The only implementers of the host interface are the two hosts, both updated; the generated files are in the diff. The Dart wrapper swallows errors.
- minor: the denied banner is not re-checked when the user returns from system settings (no lifecycle observer); it clears only on the next toggle or reopen.
- minor: `notification_providers.dart` import order (`core/platform` after `core/settings`) is not alphabetical; format passes.

## Fix list
None. No blocking findings.
