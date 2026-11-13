# Batch 18d review: T-055, T-056, T-163, T-098

Reviewer: code-reviewer (Opus), code and security. Tree: `batch/2026-11-14-18`. Sprint rule applies: only blockers and majors that touch money, security, privacy or data loss block.

## T-055 Welcome S-01 — APPROVED
- Copy (EN and AR keys `onboardingWelcome*`) says "money data stays on your phone", never "no server". Language toggle writes the setting, so direction flips live. Keys, a11y labels and 48dp targets are present; no hard-coded strings.
- minor: `welcome.dart:60` `minHeight: box.maxHeight - 32` is a magic number that can go negative on tiny viewports. Use `ZSpacing.screen * 2`.

## T-056 Android capture setup S-02 — APPROVED
- Prominent disclosure: the SMS step shows three disclosure bullets and the Allow button together. `requestSmsPermission` is reachable only from that button (`android_setup.dart` `_allowSms`). The notification step shows `onboardingAndroidSetupNotifPrivacy` before `openNotificationAccessSettings`. The degraded step shows the same text beside the "turn on" action. OK.
- NoSms: `_init` routes `!smsFlavor` to the degraded step with no SMS request. If `getCapabilities` throws, the screen falls back to the SMS step. The Allow button could then call the host, but the native NoSms build returns `NOT_AVAILABLE` (covered by PermissionFlowsTest), so no prompt appears and the user lands in degraded. OK.
- FU-109: `startFirstRun` uses `settings().includePersonal`, which defaults to false. The UI passes no override. Personal senders are scanned only with the opt-in. OK.
- Counts only are shown (imported count, institutions); no body, sender or amount is rendered or logged.
- minor: `_listenScan` can run twice (init with permission already granted, or retry after deny) and overwrites `_sub` without cancelling the earlier subscription. Cancel before reassigning.
- minor: the degraded "Continue" calls `onSkipped(kSetupStepSms)` and then `onDone()`. A caller that navigates in both would navigate twice. It also records the SMS step as skipped when only notifications were declined. Document or split.
- minor: scan errors are swallowed (`onError: (_) {}`), so the card stays at "running" if the scan fails.

## T-163 Categories & rules S-63/S-64 — APPROVED (with non-blocking majors)
- Delete needs a replacement. `deleteWithReplacement` rejects an empty or same id, an archived replacement, a replacement that is a child of the deleted category, and system categories. The UI confirm stays off until a choice is made.
- Atomicity: the transaction UPDATE, the merchant_rules UPDATE and the archive all run inside one `_db.transaction`, so a failure rolls all three back. Moving rules cannot hit UNIQUE(match_kind, match_value), because that key does not include the category. User rules are re-pointed, never dropped. `category_source` is untouched, so user choices stay `user` or `user_rule`.
- Gold gate: create, save and delete are gated in the UI (`isGold`). Without Gold the editor is read-only and the list stays visible (BR-GOLD-04). The data layer is ungated by design ("caller's job"). Acceptable, since there is no other caller.
- major (non-blocking: no data loss, no money moved): `categories_admin.dart:240-262`. The header comment says the delete "archives [id] (and its subcategories)", but only `id` is archived. Children keep `parent_id` pointing at an archived parent. They are hidden from S-63, because top-level rows are filtered by `parentId == null` and custom rows open the editor. Their transactions and rules are not moved. The UI already excludes children from the replacement list, which shows the intent. Either cascade (move the children's transactions and rules to the replacement, then archive them) or refuse the delete while active children exist. Test to add: delete a custom parent that has a custom child with a transaction.
- major (non-blocking): the same function leaves `budgets` rows (`budgets.category_id`) on the archived category. The user's limit stops tracking, because spending is now counted under the replacement. No money is lost. Re-point the budgets (merge, or keep the higher limit when `UNIQUE(category_id, currency, period)` collides), or warn in the delete dialog. Track as a follow-up with an owner in the budgets lane.
- minor: `_checked` compares the duplicate name against both `nameAr` and `nameEn` of all categories. Fine. Custom names are stored in both columns (accepted).
- minor: the delete `catch (Object)` shows a generic failure, with no code.
- Tests present: `categories_admin_test.dart` (create validation, system read-only, delete moves transactions and rules), screens and goldens. No test covers the children or budgets cases above.

## T-098 Mascot trigger policy — APPROVED (with a non-blocking major)
- Pure Dart in `zaghlol_domain`, integer money only. `spent*100 <= limit*85` and `spent*30 <= sum*13` avoid doubles and stay inside int64 for the allowed range. Day-before-20 and 85% boundaries are correct (strictly greater than 85%). The 3-cycle average needs three full cycles. Dedupe by `kind:subject:cycle` id plus dismissed ids. `decideMascot` returns at most one banner, with a 60 s gap, priority shocked > detective > proud > tourGuide, and still-only when reduce motion is on. Q-25 matches PO_DECISIONS (rent, bills, groceries, health, education, fees, debt, work transport).
- major (non-blocking: product policy, nothing consumes it yet): `mascot_rules.dart:30-39` `defaultEssentialCategoryIds` holds bare codes (`rent`, `groceries`), but real category ids are `sys:<code>` (`categories_dao.dart:14` `systemCategoryId`), and `budgetShocked` and `diningSpike` compare `categoryId` by exact match. A caller that passes a DB id, such as `sys:rent`, is roasted for essentials, which defeats the Q-25 safety property. Subcategories of essentials (parent `sys:groceries`) and custom categories under an essential parent are also unprotected. Required before the first caller (T-099 and later): normalize the id (strip `sys:`) inside the function, or take the set as `systemCategoryId(...)` values, and accept a parent id. Add tests with `sys:rent` and a child of `sys:groceries`. Also confirm that `work_transport` is a real seeded code; no seed matched it in this tree.
- minor: the shocked pose from `diningSpike` takes any category, so the caller must restrict it to dining and delivery.

## Test runs
Domain `dart test test/mascot_rules` and app onboarding and categorization tests were started, but the app run did not finish before this report was written. The merged tree is reported green by the Lead.

## Fix list (blocking findings only)
| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| none | | | |
