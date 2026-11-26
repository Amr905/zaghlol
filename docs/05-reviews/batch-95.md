# Batch review: batch 95 (`batch/2026-11-26-95`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security, one pass) |
| Date | 2026-11-26 |
| Diff | `git diff 576babb5..667526f4`. 576babb5 is the reviewed tip of batch 94. The local `origin/batch/2026-11-26-94` ref was stale at b8a4b715, so a three-dot diff against it would also pull in batch 83/94 commits |
| Tasks | T-349 (C4 backend), T-344 (C2/C3 app), T-346 (C2 UI), T-357 (C4 app, can overwrite user data) + fix commit 667526f4 (task/b95-fix-queue), T-360 (C1, Lead spot-check) |
| Verdicts | T-349 APPROVED · T-344 APPROVED · T-346 APPROVED · T-357 **CHANGES_REQUESTED** (1 major, privacy, in the fix commit) · T-360 spot-check: no blocking issue |

## Checks run (cloud workspace)
- **Backend:** `Zaghlol.Application.Tests`: 1422 passed, 0 failed. `Zaghlol.Api.Tests` and `Zaghlol.Contract.Tests`: every failure is `DockerUnavailableException` (Testcontainers). The endpoint tests, including the marker test, ran green on backend-ci for `ci/T-349` (Lead).
- **App:** `flutter test test/features/ask test/features/categorization test/core/db`. The only failures are:
  - `llm_ask_states_golden_test.dart`, 32 cases. These are new PNGs that CI regenerates, so they are not judged here.
  - `categorizer_seed_test.dart`, 2 perf cases. These fail only when the suite runs in parallel and pass when run alone (see T-357 (e)).
- **Parsing package:** `zaghlol_parsing` `dart test`: 2267 passed.
- **T-357 timing:** `categorizer_seed_test` ran 3× on the pre-T-357 merge (6d119c6b) and 3× on HEAD, alternating.
  - p95 with 3600 aliases, pre-T-357: 14.43 / 12.07 / 11.76 / 11.55 / 11.74 / 11.18 ms.
  - Same measure on HEAD: 11.98 / 12.27 / 11.93 / 10.96 / 11.22 ms.
  - The per-message p95 failed once on the **pre-T-357** tree (7.90 ms).
- **Eligibility probe** (shipped lexicon, `kind: businessPayment`): `rahul sharma` and `priya` are ELIGIBLE with party `merchant` but refused (`notBusinessPayment`) with party null. Egyptian, Coptic and common English names are refused either way (`personLike`).

---

## T-349: `POST /v1/ask/plan`. **APPROVED** (minors only)

| AC / focus | Result | Evidence |
|---|---|---|
| Gate order: cheap first, fail closed | PASS | `LlmGateChain.AdmitAsync` runs flag → spend pause → active provider + key (paused) → consent → account token → buckets → attestation (null proof → verifier → 422) → quota pre-check. `AskPlanService` then: resolve/prompt (config error → paused) → `ReserveAsync` → provider → validator → invest flag → commit. Every refusal returns before `ReserveAsync`. `AskPlanServiceTests` ("cheap first", "every gate refusal never reaches the provider", "rate limited does not reach attestation") pass. |
| Answer without being counted | PASS (by spec) | These cases are not counted: validator failure, provider refusal, `Invalid`, and INVEST while the flag is off. All return the static `PL-FALLBACK` with the pre-check quota, so no model content gets through uncounted. A valid FALLBACK/REFUSE is counted (§4.1). A commit that finds the counter `Exhausted` or `Unavailable` withholds the plan. |
| Counted twice | PASS | One `CommitAsync` per request. The same `requestId` within 2 min is a retry (install-row hash + `updated_at` guard in the SQL `WHERE`). The parallel same-id test passes on CI. |
| No question/plan/template in logs, metrics, problems, tables | PASS | Question, reply and plan are all `LlmSensitive`. `LoggerMessage`s carry fixed codes only. Provider exceptions are caught without their message. Problem bodies carry fixed codes plus `quota`/`providerId`/`retryAfterSeconds`. The prompt metric tag is regex-checked (12 hex chars). The marker test covers success, fallback, invalid plan, timeout, unusable, refused and exception. Cancelled-request and validator-exception paths are not covered (B95-m2). |
| Server scrub | PASS | `QuestionScrubber` is pure and logs nothing. It masks e-mail, IPA (also `name @ instapay`), separated Egyptian mobiles and runs of 8 or more digits (Arabic-Indic folded), and leaves the phone's `⟦…⟧` tokens alone. The validator's verbatim-ref check runs on the scrubbed text. |
| FU-404/417/418 | Closed | Control chars in `p` → schema invalid. `whatIf.target.currency` is checked. Provider id is 2–32 chars in every pattern. The secret-suffix scan has passing tests. |
| Rate limiter | Acceptable for one instance | In process, with documented N× per instance. Partitions are evicted by the runtime when idle. |
| OpenAPI `attestation` not required | No weakening | The server still refuses a missing proof (422, `missing`, provider not called). Only the 400-vs-422 status changes. The app client is handwritten, so no generated model loses the field. |
| NFC not enforced server-side | Nit | Consequence: a non-NFC question can fail the verbatim-ref check, which gives an uncounted fallback, and the 300-character limit is counted in UTF-16 units of the un-normalised text. Step 6 still requires NFC templates. No privacy or cost impact. |

**Security part.**
- **Prompt-injection residual.** The question is untrusted. The defences are:
  - the closed plan catalogue with schema-bounded params;
  - refs must occur verbatim in the scrubbed question, and registry names are refused;
  - the template grammar (≤200 chars, no digits, links, `@`, markup or bidi controls; script ratio).
- **What gets through.** A valid plan is a read-only local query, so it cannot change data on the phone. What injection *can* get is a ≤200-character model sentence in Zaghlol's voice with no digits, links or handles (for example "call your bank now", or an unfounded "more than usual"). On the phone, T-344 adds a number-word, script and format filter. This residual is accepted by design (BR-LLM-04). The phone shows only computed figures.
- **Retry reuse (FU-413, still open).** At the limit, the last counted `requestId` can be reused with **different** questions for 2 min without counting. That is bounded by the 3/min bucket, so about 6 extra answers per install per 2 min, all on the spend ledger. Keep FU-413 on T-351/T-352.

**Findings**

| # | Sev | File:line | Issue | Required change |
|---|---|---|---|---|
| B95-m1 | minor | `backend/src/Zaghlol.Application/Llm/Ask/AskPlanService.cs:163` | The `ask_llm_invest` flag read uses the request token *after* the validated reply. A Stop that lands there throws, so a validated, paid-for reply is not counted. That contradicts §4.1 ("Stop after the validated reply still counts"). INVEST only, small window. | Pass `CancellationToken.None`, or read the invest flag before the provider call. |
| B95-m2 | minor | `backend/tests/Zaghlol.Api.Tests/Llm/AskPlanEndpointTests.cs:377` | The marker test leaves out a client-aborted request and a validator throwing a non-`JsonException`. A non-Json exception escapes to the global handler as a 500 and is not caught as `Rejected`. | Add both paths to the marker test. Consider catching validator exceptions as `SchemaInvalid` (fail closed, uncounted). |
| B95-m3 | minor | `backend/src/Zaghlol.Application/Llm/Ask/LlmGateChain.cs:131` | Buckets are drawn before attestation. A holder of cheap install tokens without a valid proof can drain the shared `/24` bucket and the per-process global 120/min, so honest users get 429s. With carrier-grade NAT on Egyptian mobile networks, a `/24` is many users. This follows the spec order (§1). | Architect: draw only the install/account buckets before attestation and the network/global ones after it, or refund on a 422. |
| B95-n1 | nit | `AskPlanRequest.cs` `NormaliseQuestion` | NFC is not enforced; see the table. | Document only. |

---

## T-344: template filler. **APPROVED** (minors only)

| AC / focus | Result | Evidence |
|---|---|---|
| 1 UX §5 examples ar/en | PASS | `template_filler_test.dart` green |
| 2 INVEST / multi-currency app-owned | PASS | `_blanksFor` returns null except for single-figure data and what-if answers. INVEST, SUGGEST, REFUSE, FALLBACK, breakdown and top-N fall to `default`. |
| 3 hide amounts | PASS | Every amount goes through `_money` → `MoneyFormat(hidden:)`, including FX rate and gold price. Grams → `kAmountMask`. `_pct` stays visible (D-67). |
| 4 digits | PASS | `_n`, `_redigit` and `ZDateFormat` follow the digits setting. |
| Numbers only from the phone | PASS | The model text is re-checked: `TemplateGrammar`, then `templateTextRefusal` (Nd/No/Nl, Cf/Cc/Co/Cs/Cn, `⟦⟧`, Latin/Arabic letters only, number words). Blank values all come from computed `Money`/ints. Unknown or missing blanks → app template. |
| Per currency never summed | PASS | `_perCurrency` gives one line per currency with a code lead. Balance gives one line per account. |
| `months` int → String (4 ARB strings) | PASS | `_months` uses `chatUnitMonths` (ar: `=1 شهر`, `=2 شهرين`, `few … شهور`, `other … شهر`), so the plural is chosen on the int before it is inserted. The Arabic sentences read correctly ("في شهرين", "بعد ١٢ شهر"). |

**Findings**

| # | Sev | File:line | Issue | Required change |
|---|---|---|---|---|
| B95-m4 | minor | `app/lib/features/ask/application/template_filler.dart:64-106` | Templates that pass the guard and still state a number:<br>• Egyptian teens: حداشر, اتناشر, تلتاشر … تسعتاشر.<br>• Duals and plurals: الفين, مليونين, ملايين, الاف (no hamza), مئات; English hundreds, thousands, millions, twice.<br>• Words with the definite article: المليون, الألف. The prefix strip covers only و/ب/ل/ف/ك.<br>Example that passes: `"You spent {amount}, thousands more than usual"`. The figures shown are still the phone's. The residual is a misleading claim, as the file header accepts. | Extend the list (teens, duals, plurals, `ال`/`بال`/`وال` prefixes). Add one test per family. |
| B95-m5 | minor | `docs/04-tasks/tasks/T-344.md` | The task file has no AC→test map and its Status is still `TODO`. | Add the map; set the status in the status docs. |

---

## T-346: S-50 online-helper states. **APPROVED** (minors only; PNGs not judged)

| AC / focus | Result | Evidence |
|---|---|---|
| No send without consent | PASS | `consentPrompterProvider` defaults to `DecliningConsentPrompter`. `SheetConsentPrompter` declines when no S-50 is mounted. The flow (T-342) asks before every first send. |
| Stop cancels | PASS | `AskChatController.stop()` → `AbortSignal.abort()` on the in-flight flow. The flow and client cancel the HTTP request (T-342). The "stopped" snackbar shows on `stoppedCount`. |
| Counter, paused, at-limit not bypassable | PASS | The UI hides the counter and shows the sleep state, and the server is the only gate (403/503). A crafted UI send would still be refused. |
| 1 widget test per state ar/en | PASS | `llm_ask_states_test.dart` green |
| 3 flag off unchanged | PASS | `ask_screen_golden_test` green |
| 4 a11y | PASS | Counter `Semantics(label: chatQuotaRemainingA11y)`, Stop has a tooltip and a 48 dp target, and the stop icon is not mirrored. |
| 5 See Gold | PASS (follow-up) | `paywallTriggerProvider(GoldCapability.deepCoaching)` on tap only. |
| Strings | PASS | All via `AppLocalizations`. |

**Findings**

| # | Sev | File:line | Issue | Required change |
|---|---|---|---|---|
| B95-m6 | minor | `app/lib/features/ask/presentation/ask_screen_llm.dart:175` | The paywall trigger uses `GoldCapability.deepCoaching`. There is no Ask-quota capability, so S-68 shows the deep-coaching pitch and the FR-GOLD-05 counter is attributed to it. | Follow-up: add an `askQuota` capability (or confirm with the PO), owner T-348. |
| B95-m7 | minor | `docs/04-tasks/tasks/T-346.md` | No AC→test map; Status still `TODO`. | Add the map. |

---

## T-357: categorizer AI tier, recategorizer, queue filler (+ fix 667526f4). **CHANGES_REQUESTED**

| AC / focus | Result | Evidence |
|---|---|---|
| (a) AI never overwrites | PASS | `apply` returns 0 for an `ai` decision with a non-null old category. `replaceable(ai) = ['none']`. The single UPDATE has `category_source IN (?8) AND category_id IS ?6 (NULL) AND is_user_verified = 0 AND is_internal = 0 AND deleted_at IS NULL` plus the live-category `EXISTS`. `applySuggestion` reads only `needsClassificationSql` rows of that merchant. Negative proofs 1 and 2 are green. |
| (b) rule/catalog/keyword replace `ai` | PASS | `replaceable(userRule/catalog/heuristic)` includes `ai`. `MerchantRulesDao._eligible` and the event backfill include `ai`. A catalog replacement deletes the unconfirmed suggestion in the same transaction. The FU-408 test is green. |
| (d) idempotent, no double count | PASS | `put` sets `txn_count` and does not add to it. The fill is a full recompute in one transaction. `pickForSend` reads the quota snapshot and never writes it. A second `accept` changes 0 rows. |
| (e) timing | Not caused by T-357 | The pre-T-357 tree shows the same spread (11.18–14.43 ms, one per-message failure). The AI lookup runs only on the no-match path and is one indexed PK read. The failures come from host load. The 11.5 ms budget is too tight for a shared runner; widen the margin or measure the median (follow-up, not this task). |
| (c) queue evidence | **FAIL** | See B95-M1. |

**Security part (privacy).** The fix commit (FU-428) gives a row `counterpartyKind = 'merchant'` whenever its bundled template's event is `cardPurchase`/`cardPurchaseFx` on an expense row, or `refund` on a refund row. With party `merchant`, `LlmEligibility` skips the business-word requirement (B94-m9), and only the given-name lexicon stands between a person's name and the provider.

For bank card templates (`… لدى <merchant>`, `at <merchant> with card`) the counterparty is an acquirer-registered business, so the evidence is sound. Several bundled `card_purchase` templates, however, are "paid to" wallet payments where the payee can be a private person:

| Template id(s) | Pattern |
|---|---|
| `vodafone_cash.payment.ar` | `تم دفع … (?:الي\|ل\|لـ) <merchant>` |
| `vodafone_cash.ocr_payment.en` / `.ar` | `paid to: <merchant>` / `الى: <merchant>` |
| `revolut.card_purchase.en` | `… paid to <merchant>`. Revolut uses "paid to" for P2P too. |
| `paytm.card_purchase.en` | `paid ₹ to <merchant> from paytm wallet`. This is mostly P2P/UPI to individuals. |

The probe shows names outside the lexicon (`rahul sharma`, `priya`) become ELIGIBLE only because of this evidence. Before the fix they were refused (`notBusinessPayment`).

On refunds: `refund` evidence on refund rows (monzo, n26, revolut, wise, liv "refunded by/from <merchant>") is reasonable. `reversal` is correctly not evidence. A merchant is queued only when *all* its rows qualify. Custom templates (`custom_*`) and OTA templates are not in the bundled map, so they fail closed.

**Findings**

| # | Sev | File:line | Issue | Required change |
|---|---|---|---|---|
| **B95-M1** | **major** (privacy) | `app/lib/features/categorization/application/llm_cat_queue.dart:81-89, 221-226`; `app/lib/features/categorization/data/llm_cat_providers.dart:57` | Any `card_purchase` template counts as business evidence, including wallet "paid to" templates whose payee can be a person. This removes the business-word safeguard, and person names outside the given-name lexicon can be sent to the backend and the LLM provider (FR-LCAT-05). | Make the evidence an explicit allowlist of template ids, or exclude "paid to"/wallet-payment templates: at least `vodafone_cash.payment.ar`, `vodafone_cash.ocr_payment.*`, `revolut.card_purchase.en`, `paytm.card_purchase.en`. Better: a registry field such as `payeeMayBePerson` (or a per-institution kind check limiting evidence to bank card templates). Those rows fall back to party null, so the business word is required again. Add a test: a Vodafone Cash "تم دفع … لـ <name not in lexicon>" row is never queued. |
| B95-m8 | minor | `app/test/features/categorization/data/categorizer_seed_test.dart` | Perf budgets flake under parallel load on both the old and new tree. | Follow-up: use the median, or a looser host budget. |
| B95-m9 | minor | `llm_cat_queue.dart` (refund evidence) | Foreign wallet refund templates (`revolut.refund.en` "refunded from <X>") would also pass on the lexicon alone. Low risk, because every row of the merchant must qualify. | Review it together with the B95-M1 allowlist. |

---

## T-360: ARB strings §4.12 (C1, Lead spot-check)
All 47 keys are present in both locales and the Egyptian voice is consistent. Notes (follow-ups, not blocking):
- **B95-n2.** `categorizationAiConsentStorage` and `privacyServerItemLlmCat` say "من غير أي حاجة تدل عليك" / "nothing that identifies you". This is the same overstatement already open as **FU-421** (legal, OQ-LCAT-08).
- **B95-n3.** `categorizationAiChipLabelA11y` "لسه متأكدتش" is ambiguous ("I'm not sure yet" vs "you (f.) haven't confirmed"). Suggest "لسه مش متأكد منه", to match en "not confirmed".

---

## CLAUDE.md §2 non-negotiables
- **§2.1 (data leaves the phone):** the backend receives only the scrubbed, masked question and the gate fields. B95-M1 is the one gap: a person name can be sent as a "merchant".
- **§2.2 (encryption):** queue and suggestion tables live in the SQLCipher DB, and nothing new is stored outside it.
- **§2.3 (strings and RTL):** no hard-coded strings, and RTL is handled (the Stop icon intentionally does not mirror).
- **§2.4 (money):** amounts are `Money`/minor units, with no `double` and no cross-currency sums. The backend spend math is `decimal`.
- **§2.6 (raw SMS):** no raw SMS is logged, and merchant keys are never logged.

## Follow-ups to file
B95-m1…m9 and B95-n1…n3, as above. FU-413 stays open (retry not bound to body).
