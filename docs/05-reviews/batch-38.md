# Batch 38 review — 2026-11-18

Reviewer: `code-reviewer` (Opus, code + security). Scope: `task/PO-b38-reminders` (`git diff origin/main...origin/batch/2026-11-18-38`), PO rows WEEKLY-FRIDAY and OVERDUE-REMINDERS (PO_DECISIONS Part 1, 2026-11-18).

Tests run: `flutter test --exclude-tags benchmark,golden test/features/notifications test/features/recurring test/app/notification_action_test.dart`: 115 passed. Kotlin/Swift: green on `ci/b38act` (read, not built).

## PO-b38-reminders — APPROVED

Checked against the PO rows:
- **Weekly on Friday:** `isLocalFriday` is correct (epoch day 0 was a Thursday). It runs once per local Friday because `notifWeeklyLastRun` is compared by local day. The window `weeklySummaryPeriod` covers Fri−7 to Thu, which is the seven days ending Thursday. Quiet hours apply through the service.
- **Overdue reminders:** `overdueReminders()` sends only on day+1 and day+3, only from 10:00 local, and only for `active` items, so none go out for paid, dismissed or deleted items. Card dues get none. The dedupe key `type|item|dueDate|threshold=overdueDays` means each reminder goes out once. When hide-amounts is on, the redacted body is used. The alarm receiver carries the action extras, so they survive quiet hours. Tests cover day 1/2/3/4/5, paid, deleted, before 10:00 and hide-amounts.
- **Copy:** the ICU plurals are correct in ar (`=1`, `=2`, `few`, `many`, `other`) and en. The Arabic is Egyptian colloquial ("عدّى ميعاده", "دفعته؟", "أيوه دفعته"). No amount appears in the action label.
- **Mark as paid:** the route is `/recurring/<id>/paid/<yyyy-mm-dd>`, checked against the allow-list in both native code and Dart. The action calls `markPaidManual(id, expectedDue:)`, which pays nothing if the pinned date is no longer the next due date. `INSERT OR IGNORE` on the occurrence makes it idempotent. The action opens the app; nothing financial runs in native code.

**Security: forged route to the exported MainActivity.** Impact is low and does not block. To forge a mark-paid, an attacker needs the item's id, a `Random.secure` UUIDv4 that never leaves the device, plus its current due date. PendingIntent extras can't be read by other apps. An app with notification-listener access can only press the real action, and that action is limited to its pinned date. So another app cannot mark arbitrary bills paid. What a forged intent can do: open Insights or Backup, and cancel the app's own notifications through `EXTRA_CANCEL_ID`. Both are cosmetic.

| # | Sev | File:line | Finding | Required change |
|---|-----|-----------|---------|-----------------|
| 1 | minor (sec Low) | `app/android/.../MainActivity.kt:86-87,141-156` | Any app can send an intent with `EXTRA_ROUTE` or `EXTRA_CANCEL_ID`. It can open screens and cancel Zaghlol notifications, but it cannot pay a bill without the item's UUID. | Follow-up: send the action through a non-exported trampoline activity, or add a nonce for each notification. |
| 2 | minor | `app/lib/app/notification_taps.dart:59` | If the action fails (for example, the app is locked or the DB is not open yet), the error is swallowed. The notification has already been cancelled, so the press is lost and the user gets no feedback. | Follow-up: keep the pending mark-paid until the app is unlocked, or show a toast. |
| 3 | minor | `app/lib/features/notifications/application/notification_providers.dart:359` | The weekly summary runs only if the app starts or resumes on a Friday. If the app isn't opened that Friday, that week's summary never goes out. | Follow-up: schedule the summary as a Friday alarm. |
| 4 | minor | `send_due_reminders.dart` (existing behaviour) | When quiet hours delay an overdue alert, the scheduled alert is not cancelled if the bill is paid before it fires. The "Mark as paid" action on it is a no-op because of `expectedDue`. | Follow-up: cancel scheduled reminders for an item when it is paid. |

## Fix list

None (no blockers or majors).
