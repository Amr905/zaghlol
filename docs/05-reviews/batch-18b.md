# Review batch-18b: T-146, T-107, T-108, T-111, T-104

Reviewer: code-reviewer (code + security), 2026-11-13. Tree: `origin/batch/2026-11-14-18` @ 8644dd1f. Task-own files read via the single feature commits (dab61bfa, 340f01c6, b183e139, fdc818b2, bc21f9fa).
Ran: `flutter test --exclude-tags benchmark,golden` on `test/features/{gold/presentation,ask/presentation,insights/presentation,home}`: all 135 pass.
Sprint rule applied: only blocker/major findings on money, security, privacy or data loss block.

## T-146 Paywall S-68: APPROVED
- Prices: only `PlanOffer.storePrice` from `queryProductDetails`; ARB strings carry no amounts. PASS.
- Messages (cooldown, attest help, account_required, moved user/support, paused, tampered, held-elsewhere +/- account, supportNotice): no money or account details; support code is the install ID only. PASS (EC-65).
- Every T-145 purchase outcome and T-144 restore outcome is mapped in `_onPurchase` / `_restore`. PASS.
- supportNotice dismiss goes through T-144 and is invalidated. PASS.

| # | Sev | File:line | Issue | Change |
|---|-----|-----------|-------|--------|
| 1 | minor | gold_ui_ports.dart (`upsellCapStoreProvider`) | The weekly cap store is in-memory (builder notes it), so the cap resets on every cold start and is not yet enforceable (A-22). Nothing calls `UpsellCap.tryShow` yet. | Follow-up: persisted setting key plus first caller (owner: the task that raises unsolicited prompts). |
| 2 | minor | paywall_launcher.dart | `paywallTriggerOverride` is not wired in `main.dart`, so gates do nothing at runtime. `goldLinkOpenerProvider` is a no-op, so Terms/Privacy/Manage do nothing. | Follow-up: wire in the composition root. |
| 3 | minor | gold_messages.dart tampered case | FU-138 "set clock to automatic" copy missing (known). | Follow-up. |
| 4 | nit | ARB `goldPaywallBenefitCharts` | "All twelve charts" while the chart set is 13 (A-06). | Copy check. |

## T-107 Charts S-20: APPROVED
- Locked previews: `LockedChartCard` runs no query and paints a fixed silhouette, so no real figure sits behind the overlay. PASS.
- Free set: cash flow, donut, top merchants (limit 5 via `topMerchantsLimitFor`), budget bars. PASS.
- RTL data order: data is reversed in RTL under a forced-LTR fl_chart. PASS. Per-currency chips, nothing summed. PASS.

| # | Sev | File:line | Issue | Change |
|---|-----|-----------|-------|--------|
| 1 | minor | charts_screen.dart:95 | Locked previews are shown to every user, including Gold, because the screen does not call `decideChart`. Gold users see "Unlock" on charts they own. The Gold charts belong to later tasks (T-114/T-174). | Follow-up: skip `LockedChartCard` when `decideChart(...).allowed`. |
| 2 | minor | chart_bodies.dart:54 | `(net.minor * 100 / income.minor).round()` goes through `double` for a percent. Display only, not stored. | Use `deltaBp`/`mulDivRound` from `chart_rules.dart`. |

## T-108 Chart detail S-21: APPROVED
- The explainer reads the same chart providers as the chart (`cashFlowChartProvider`, `donutChartProvider`, `merchantsChartProvider`), so its numbers match the chart. Free never loads previous-cycle data (`deep` only). PASS.
- Q-25: `essentialCategoryIdsProvider` uses buckets needs and obligations. This is a superset of the PO list (it also covers all transport, not only work transport), so it errs towards not roasting. Accepted.
- Locked detail is gated by `decideChart`. PASS.

| # | Sev | File:line | Issue | Change |
|---|-----|-----------|-------|--------|
| 1 | minor | chart_explain_providers.dart:34 | The essential set follows the bucket, so a user-made `needs` category becomes essential. | Document (acceptable). |

## T-111 Ask screen S-50: APPROVED
- One figure per currency: `_perCurrency` emits one line per currency, led by the currency code; compare and top-merchants build per-currency mini charts; nothing is summed. PASS.
- Question never stored or logged: in-memory notifier only, `toString` is redacted, no log calls. PASS.

| # | Sev | File:line | Issue | Change |
|---|-----|-----------|-------|--------|
| 1 | minor | ask_screen.dart `_InputRow` TextField | Questions can name merchants and amounts, but the field keeps the default IME learning and suggestions. | Set `enableIMEPersonalizedLearning: false`, `enableSuggestions: false`, `autocorrect: false`. |
| 2 | minor | ask_answer_text.dart:200,246 | Hard-coded Arabic comma `'، '` is used in the English locale too. | Localize the list separator. |
| 3 | minor | ask_answer_text.dart (noDues) | Literal `'0'` passed to `chatAnswerDues` bypasses digit mode. | Render through the digits mode. |
| 4 | minor | ask_chat_controller.dart | The chat lives in a non-autoDispose provider until the process ends or the user clears it. Accepted: session-only, in memory. | None. |

## T-104 Home contextual cards: CHANGES_REQUESTED
- App-lock offer only when `hasTransactions && !lockOn && !handled`. PASS.
- `enableAppLock` sets `hide_amounts.notifications = true` on success and then marks the offer spent (FU-130). Code is correct.

| # | Sev | File:line | Issue | Change |
|---|-----|-----------|-------|--------|
| 1 | major (privacy) | test/features/home/presentation/cards/cards_harness.dart:25 | The harness fakes `HomeCardActions.enableAppLock`, so the real behaviour (turn lock on, hide notification amounts, mark offer handled; leave the setting alone when the result is not `enabled`) has no test. FU-130 is a privacy property with no coverage. | Add a unit test on the real `HomeCardActions` with a fake settings repo and a fake `AppLockController`. |
| 2 | minor | home_cards.dart:137-143 | The two writes after `enable` are not guarded. If the second `set` throws, the lock is on but notification amounts stay visible and the error escapes to `_toggle` (`_busy` stays true). | Wrap in try/catch, or write the hide-amounts setting before enabling. |
| 3 | minor | home_cards_view.dart (AppLockOfferCard) | The offer does not tell the user that amounts in notifications will also be hidden. | Copy line in `homePromptAppLockSub` (Lead decision FU-130 allows it). |
| 4 | minor | home_cards.dart:46 | `setupSalaryCreditProvider` and `setupBackupExistsProvider` are stubs (FU-144), so the payday and backup cards stay off. Known. | Follow-up. |

## Fix list (blocking only)
| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| T-104 | app/lib/features/home/application/home_cards.dart:128-146 (test in app/test/features/home/application/) | None to production code except the optional guard in minor #2. | Unit test on the real `HomeCardActions.enableAppLock`: result `enabled` gives `hideAmountsNotifications == true` and the `app_lock` slug in `setupSuggestionsHandled`; results `notSecure` and `failed` change neither setting. |
