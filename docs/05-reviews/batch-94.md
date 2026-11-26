# Batch review: batch 94 (`batch/2026-11-26-94`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security, one pass) |
| Date | 2026-11-26 |
| Diff | `git diff origin/batch/2026-11-26-93...b8a4b715` (batch 93 already reviewed) |
| Tasks | T-338 (C3), T-339 (C3, money), T-343 (C4), T-345 (C2), T-355 (C4) |
| Verdicts | T-338 APPROVED · T-339 **CHANGES_REQUESTED** (1 major, money) · T-343 **CHANGES_REQUESTED** (1 major, privacy) · T-345 APPROVED · T-355 **CHANGES_REQUESTED** (2 majors, privacy) |

## Checks run (cloud workspace)
- `dotnet build -warnaserror`: clean. `dotnet format --verify-no-changes`: clean.
- Backend tests filtered to `Llm|Spend|RemoteConfig|WebhookOps`: Application 294 passed. Infrastructure 187 passed and 41 failed. Contract 23 passed and 1 failed. Every failure is `DockerUnavailableException` (Testcontainers: `LlmTablesTests`, `LlmQuotaRepositoryTests`, `LlmSpendRepositoryTests`, `RemoteConfigStoreTests`, live contract). The PO notes that T-339's Postgres tests passed on backend-ci for `ci/T-339`. All of the new adapter, guard and spend unit tests pass.
- App: `flutter pub get --enforce-lockfile` ok. `flutter analyze`: no issues. `dart format --set-exit-if-changed` (app lib/test and zaghlol_parsing): clean. The ask flow, boundary, mask sources, consent sheet, remote config and sync orchestrator tests: 79 passed. `dart test` llm_eligibility: 87 passed. The golden PNGs are not judged (CI regenerates them).
- T-355 probe: I ran `LlmEligibility.check` with the shipped lexicon assets and `kind: businessPayment` over about 130 hand-written person, identifier and business strings. The results are quoted below.

---

## T-338: Vertex Gemini and Anthropic adapters (+ FU-406, FU-411). **APPROVED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 request body: schema, output cap, no grounding/cache (Vertex), no identifiers in body, headers or URL | PASS | `VertexGeminiProvider.BuildBody` and `AnthropicMessagesProvider.BuildBody` contain only the system prompt, the question, the schema and the cap. There is no `metadata`, no labels, no `cachedContent` and no tools other than the forced `reply_json`. WireMock tests run green |
| 2 outcome mapping per adapter | PASS | Fixtures `vertex-*` and `anthropic-*`. Timeout, Upstream and paused-without-key tests run green |
| 3 pure schema transform, same verdicts on the T-322 vectors | PASS | `LlmSchemaTransforms.ForProvider` removes only the root `$schema`, `$id` and `$comment`. `LlmSchemaTransformTests` checks the 89 vectors |
| 4 config entries with decimal prices | PASS | `LlmProviderOptions` (`Project` and `Region` are path-checked for Vertex). Also covered: `app.env.example` and `deployment.md` |

**Security part.**
- **Key and token handling:** the Vertex service-account JSON goes only to `IVertexAccessTokenSource`, which accepts the service-account type only (`CredentialFactory.FromJson<ServiceAccountCredential>`). Any credential exception becomes `Upstream` without its message (`VertexGeminiProvider.cs` catch). The bearer token is sent in the `Authorization` header and the Anthropic key in `x-api-key`. Neither ever appears in a URL. The project, region and model in the path pass a regex check. The library caches the token. A key rotation needs a restart (documented).
- **No question text logged:** the adapters do not log, and the named HttpClients call `RemoveAllLoggers()`. The guard logs the provider id and a state word only.
- **Timeouts and cancellation:** the guard owns them (`client.Timeout` is infinite). A cancelled token mint is rethrown. FU-406: a dropped body (`IOException`) is `Upstream`, and a late non-probe result is ignored while the circuit is open. The tests run green.
- **Duplicate properties:** the Anthropic envelope is parsed with `AllowDuplicateProperties=false`. For Vertex only the inner text is parsed that way (B94-m1).

**Vendor details not verified (for the T-351 live test; not blocking):**
1. Vertex: the field name `generationConfig.responseJsonSchema` on the Vertex `v1` path (rather than `responseSchema`).
2. Vertex: the value `thinkingConfig.thinkingLevel` = `"MINIMAL"`, which depends on the model.
3. Vertex: the `thought` flag on parts, and the `usageMetadata` names (`promptTokenCount`, `cachedContentTokenCount`, `candidatesTokenCount`, `thoughtsTokenCount`).
4. Vertex: the exact `finishReason` set, whether `pattern` is accepted, and the EU regional host.
5. Vertex: the `cloud-platform` scope.
6. Anthropic: the header `anthropic-version: 2023-06-01`, and `stop_reason: "refusal"`.
7. Anthropic: whether a root-object `input_schema` that uses `$defs`/`$ref` and `anyOf` is accepted as a non-strict tool.
8. Anthropic: the `usage` field names.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| B94-m1 | minor | `backend/src/Zaghlol.Infrastructure/Llm/VertexGeminiProvider.cs:115` | The Vertex envelope is parsed with duplicates allowed. A repeated `finishReason`, `candidates` or `text` is resolved silently. The design note says "Duplicate properties are Invalid for all three adapters". | Parse with `LlmReplyReader.NoDuplicates`, as Anthropic does, and add an envelope-level duplicate fixture. |
| B94-m2 | minor | `backend/src/Zaghlol.Application/Config/RemoteConfigService.cs:162` | FU-411 is active only in a host that registers `AddZaghlolLlm`. The admin host, which serves `PUT llm.provider`, does not, so in production an unknown id is still accepted. | Register `IKnownLlmProviderIds` in the admin host from `LlmProviderOptions.ReadAll(configuration)` (no adapters needed), or keep FU-411 open. |
| B94-m3 | minor | `backend/src/Zaghlol.Infrastructure/Llm/AnthropicMessagesProvider.cs:135` | `cache_creation_input_tokens` are priced as plain input, but Anthropic bills them at about 1.25×. The amount is negligible while no caching is requested. | Leave a comment, or add a cache-write price field when caching is turned on. |

---

## T-339: spend ledger, USD 10 cap, 80 % alert, pause, metrics. **CHANGES_REQUESTED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 decimal cost, cached tokens priced separately | PASS | `LlmCostCalculator.Cost`/`WorstCase` are decimal only and round up to 1e-6. Ledger `numeric`. `CostPricesCachedTokensSeparatelyAndRoundsUp` |
| 2 alert once per month per feature, re-arms | PASS | DB marker row claim (`ClaimSql` `ON CONFLICT DO NOTHING`) plus an in-memory set. A failed webhook post is logged by `WebhookOpsNotifier`. Claim-before-send (a failed post is not retried) is **acceptable**: the pause at 100 % does not depend on the alert |
| 3 at 100 % both features pause; cap raise resumes ≤ 60 s | PASS | `IsPausedAsync` and `ReserveAsync` use the global total over every provider and feature, so **switching provider can't bypass the pause**. An unknown provider (no price) is paused |
| 4 metric tags | PASS | `LlmSpendMetricsTests` |
| 5 purge 13 months | PASS (CI) | `ThePurgeKeepsThirteenMonths` (backend-ci, `ci/T-339`) |

**Cap overshoot analysis.**
- *Concurrency in one process:* the reservation is made under the lock and checked as `total + inFlight + worst ≤ cap`. This holds as long as the real cost stays at or below the reserved worst case (see B94-m5).
- *Process restart:* in-flight reservations are lost. The overshoot is bounded by the calls in flight at the crash. Accepted.
- *Failed ledger write:* the entry stays queued and counted, and the guard is paused until it is written. Correct.
- *Cap missing, zero or negative:* `allowed` is false, so the guard is paused. Correct.
- *Month rollover:* UTC. `localSettled` resets with the fresh read, and in-flight reservations carry over (safe side).
- *Token counts missing:* **not fail-closed** (B94-M1).
- *Zero price:* accepted (B94-m4).

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| **B94-M1** | **major** (money) | `backend/src/Zaghlol.Application/Llm/Spend/SpendGuard.cs:247` | `SettleAsync` prices whatever usage it is given. The adapters return `LlmUsage.None` (0/0/0) on `Timeout`, on transport `Upstream`, and on an Ok/Invalid/Refused reply without a `usage`/`usageMetadata` block (`LlmTypes.cs:52`; `ReadUsage` in both adapters). A timed-out call that the vendor completed and billed is recorded at USD 0. If a vendor field name differs from what the adapter assumes (unverified, see T-338 list), **every** call is recorded at 0. The cap then never trips, so overshoot is unbounded, not "one in-flight worst case". The class doc promises fail closed. | When the usage is unknown (`LlmUsage.None` or all zeros) and the outcome is not "never sent" (open circuit or connect failure), settle at the reservation's worst-case usage. Count that as a metric `usage_missing`. Test: a Timeout and an Ok-without-usage each add `WorstCaseUsd` to the ledger. |
| B94-m4 | minor | `backend/src/Zaghlol.Infrastructure/Llm/LlmProviderOptions.cs:104` | `PriceInPerMTok` and `PriceOutPerMTok` accept 0. A typo makes every call free, and the cap never trips. | Require `> 0` for the in and out prices (cached may be 0). Add one config test. |
| B94-m5 | minor | `backend/src/Zaghlol.Application/Llm/Spend/SpendGuard.cs:37` | `MaxInputTokens = 4000` is documented as a "true upper bound". The schema alone is about 14 KB after the strip (about 3.5–4.5 k tokens), and the system prompt and question come on top, and Anthropic adds its tool overhead. The real input can exceed the reservation, which weakens the concurrency bound. The dollar effect is small. | Derive the bound from the prompt catalog plus schema size plus 300 characters at startup, or measure it in T-351 and set it from config. |
| B94-m6 | minor | `backend/src/Zaghlol.Application/Llm/Spend/SpendGuard.cs:368` | Refresh race. A settle that adds to `localSettled` after `TotalAsync` has read, but before the lock resets `localSettled = 0`, is lost until the next refresh. The same happens to entries still queued after a failed write. The doc says a race "can only double count". The under-count is bounded by about 60 s. | Snapshot `localSettled` before the read and subtract only that snapshot. Also add the costs of the pending queue to `baseTotal`. Or correct the doc. |

---

## T-343: Ask flow orchestrator. **CHANGES_REQUESTED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 a state for every UX §1 case | PASS | `llm_ask_flow_test.dart` "AC1 states" (local, clarify, declined, quota 0, offline, paused, 409 twice, 422 key retry, 429/502/timeout, Stop, valid), run green |
| 2 NEG-PROOF 1: request bodies hold only the FR-LLM-02 fields, no fixture data | PASS (fixture scope, see B94-M2) | `llm_ask_boundary_test.dart:316` |
| 3 NEG-PROOF 2: zero requests | PASS | `llm_ask_boundary_test.dart:390`, `llm_ask_flow_test.dart:398` |
| 4 nothing stored or logged after the answer | PASS | `llm_ask_boundary_test.dart:432` (DB plus settings dump plus log capture) |
| 5 an invalid plan answers PL-FALLBACK | PASS | `validation.rejected` → `LlmFallbackAnswer`; `execute` is never called (test at `:418`) |

**Security part (data boundary).** I traced every exit:
- The only send is `client.plan(masked: MaskResult)`, and the gateway builds `q` from `masked.sentText` only (`llm_gateway_client.dart` `askPlan`). The rest of the request is the language, the consent `{provider, v}`, the requestId and the attestation.
- **Retries:** the 409 and 422 paths resend the same `masked`. 409 clears the stored consent (gateway), prompts once, and never loops.
- **Error states:** `AskLlmFailed`, `AskLlmPaused` and the others carry no text. `on Object` swallows the exception with no log.
- **Persisted state:** the consent grant holds `{provider, v, at}` only. The quota snapshot holds counters.
- **`toString`:** redacted on `ConsentPrompt`, `AskLlmAnswered`, `MaskSourcesDrift` and `InstitutionNames`.
- **"What I sent":** `sentText` lives only on the emitted state. No storage exists in this batch (T-346 must keep it in memory).
- **Cancelled request:** Stop is checked before and after the send, and nothing is queued.
- **Consent prompt:** it shows `sentText` only.
- **Fail-closed checks:** `MaskUnresolved(failed)`, a mask exception and `ScrubResult.failed` (FU-398) all end in a local answer with no send. The 300-character cap comes before everything. Flag off or unknown terms means no send.
- **FU-415:** `resumeAll` after a good sync is safe. A server that is still paused answers 503 again and the app re-marks it.

**Known open PO question (not blocking): person names are not masked.**
- `MaskSourcesDrift.load` feeds the masker three sources only:
  - account label, institution and last-4;
  - registry names and short forms;
  - `merchant_norm`/`merchant_raw` of the user's transactions.
- These are not sources: `transactions.counterparty_value` (kinds `person`, `ipa`, `phone`), user category names, budget or goal names, and transaction notes.
- So for «بعت لمنى عادل كام الشهر ده؟» or "how much did I send to Mona Adel", the name `منى عادل` / `Mona Adel` is sent verbatim to the Zaghlol backend and on to the LLM provider. With it goes the fact that the user transfers money to that person.
- The exceptions:
  - phone and InstaPay-address shapes are scrubbed by `ClientScrub`;
  - a name is masked as MERCHANT when a parser stored the recipient in `merchant_raw`.
- The consent copy ("Anything else you type … goes as typed") and the first-time preview disclose this.
- Nothing is retained server-side per FR-LLM-32.
- Questions after the first carry no preview.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| **B94-M2** | **major** (privacy) | `app/lib/features/ask/data/mask_sources_drift.dart:133` | The query keeps only `merchant_norm IS NOT NULL`. Manual transactions are inserted with `merchant_raw` only (`drift_transaction_repository.dart:134`), and an edited merchant sets `merchant_norm` to NULL (`:211`). No code in `app/lib` recomputes it. So every merchant the user typed or corrected is **never masked** and leaves in plain text ("Gym Captain Mido", "عيادة د. هاني"). The header comment says "No cap: a name left out here would be sent in plain text", and the consent copy promises "without the names of places you shop". | Also select rows with `merchant_norm IS NULL AND merchant_raw IS NOT NULL`. Use a stable id the executor can resolve (for example `foldKey(merchant_raw)` with a prefix, resolved in `PlanExecutor` against `merchant_raw`), or mask them with a non-resolvable merchant id when the plan doesn't need to resolve them. Add a fixture row with NULL `merchant_norm` to the NEG-PROOF 1 fixture DB. |
| B94-m7 | minor | `app/lib/features/ask/data/llm_ask_providers.dart:37` | `askOnlineCheckProvider` always returns true, so the UX "Offline" state before the send is never reached. A failed connect ends in `LlmOffline` with nothing queued. This is safe. | Track it for T-348 (connectivity), already listed in the design note's "gaps". |

---

## T-345: consent sheet, "What I sent", Settings → Privacy row. **APPROVED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 Allow stores `{provider, v, at}`; Not now/drag/back store nothing; switch off clears; Cancel leaves off | PASS | `AskConsentFlow.prompt` stores only when `allowed == true`. `consent_sheet_test.dart` runs green |
| 2 chips per kind, first-strong direction, bidi-isolated | PASS | `SentTextView`, `firstStrongDirection`, FSI/PDI around chip labels. Placeholders carry kind and number only, never the map |
| 3 goldens ar/en, light/dark, 100/130 % | Not judged | PNGs are regenerated by CI. The golden test file is present. The 130 % stacking logic is in `ConsentSheet.build` |
| 4 a11y: one node, expanded state, ≥ 48 dp | PASS | `Semantics(container, label: chatSentTextA11y)` plus `ExcludeSemantics`. The toggle has `expanded:` and `minHeight: ZSpacing.minTarget` |
| 5 row hidden while flag off; quota hidden while paused; "unknown" text | PASS | `PrivacyAskLlmSection`. The server-knows bullet shows only while the flag is on |

No hard-coded strings. Every text comes from `AppLocalizations`, and the keys match copy deck §4.2 (intro naming `{aiProvider}`, sends, never, storage). Directional insets are used throughout.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| B94-m8 | minor | `app/lib/features/ask/presentation/consent_sheet.dart:40`; `app/lib/features/ask/data/llm_ask_providers.dart:32` | The description says "implements `ConsentPrompter` (T-343)", but no implementation exists, so `consentPrompterProvider` still declines (fail closed). There is also no `sentText` → `List<SentSegment>` converter. The terms have two sources: the sheet reads `askConsentTermsProvider` (default null), and the flow uses `askLlmTermsProvider` plus a 409-supplied provider. If an adapter wraps `AskConsentFlow.prompt`, the sheet could **name and store** a provider other than the one the flow sends with, and the grant would be stored twice. | Follow-up for T-348/T-346. The adapter must display and store `ConsentPrompt.terms` (not `askConsentTermsProvider`). Leave storage to the flow. Add a round-trip test: the segments parsed from `sentText`, rendered back to tokens, equal `sentText`. |

---

## T-355: categorise eligibility rule. **CHANGES_REQUESTED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 FR-LCAT-05 table, ar and en | PASS | `table: eligible` / `table: ineligible text` |
| 2 Arabic-Indic IBAN/phone, split runs, «حاج سيد», "Dr Mona", «محمود» | PASS | Probe confirms. Identifier checks are strict: `Ahmed 1234`, `0101 2345`, `010-123-45`, spaced IBANs, `ahmed instapay` and `mohamed.ahmed` are all refused |
| 3 NEG-PROOF 1 vs server `ContributionPrivacy` | PASS | Ported rule with a source note. 20 k strings |
| 4 NEG-PROOF 2 transfer/ATM/salary/person never eligible | PASS | 5 k strings |
| 5 enum reasons, no text returned or logged | PASS | `Ineligible(reason)` only |

**Security part.** The identifier side is sound and stricter than the server. The person-like side has holes that real Egyptian payee strings hit. Probe results (all `kind: businessPayment`, no counterparty):

| String | Result | Class |
|--------|--------|-------|
| `محمد احمد محمود علي حسن`, `MOHAMED AHMED MAHMOUD ALY HASSAN`, `Ahmed Mohamed Ali Hassan Ibrahim` | **ELIGIBLE** | 5-part full legal name (InstaPay and wallet show the full name) |
| `محمد عبد الرحمن`, `Mohamed Abdel Rahman` | **ELIGIBLE** | split `Abd`/`Abdel` compound |
| `MOHAMED A***`, `MOHAMED AHMED M***`, `MOHAMED A. HASSAN`, `Mohamed A Hassan`, `M. Ahmed`, `Rana W.` | **ELIGIBLE** | initials / bank-masked names (Arabic `محمد أ. حسن` is refused) |
| `To Ahmed Mohamed`, `تحويل الى احمد محمد`, `Transfer Ahmed`, `Vodafone Cash Ahmed`, `فودافون كاش احمد`, `ipa ahmed` | **ELIGIBLE** | transfer verb or wallet brand plus a name |
| `Hag Sayed`, `Haj Sayed`, `Hajj Sayed`, `شيخ احمد`/`الشيخ احمد`, `Captain Mido`/`كابتن ميدو`, `Madam Mona`/`مدام منى`, `Ostaz Ahmed`, `مهندس كريم` | **ELIGIBLE** | honorifics missing from `eg_honorifics.txt` (the Latin variants of «حاج», which batch-90's variant classes require) |
| `Mido`, `Bebo`, `Zizo`, `Hamada`, `حماده`, `Ahmed Hamada`, `Basant`, `Kerolos Nabil`, `A7med`, `m7md`, `mohamedahmed` | ELIGIBLE | accepted gap (nicknames, unlisted or Coptic spellings, chat alphabet, glued tokens; covered by the design note's residuals). Add the common nicknames to the list as a follow-up |
| `محمد للتجارة`, `صيدلية د. أحمد`, `Mohamed Ahmed Store`, `Ahmed Ali Shop` | ELIGIBLE | correct: business word present (accepted residual) |
| `Ahmed 123`, `احمد ٢٠١`, `EG12` | ELIGIBLE | accepted: fewer than 4 digits, no IBAN shape |

**Fail-closed on `kind`.** Only `businessPayment` passes, and `unknown` is refused. A **wrong** `businessPayment` for a transfer is still caught if `counterpartyKind` is `person`, `ipa`, `phone`, `bank` or `own_account`, or if the event category is cash, income or InstaPay. With a null counterparty and no event category, only the text rules remain, which is where the holes above bite. Not fully fail-closed against a wrong caller (B94-m9).

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| **B94-M3** | **major** (privacy) | `packages/zaghlol_parsing/lib/categorize/llm_eligibility.dart:285`, `:231`, `:313` | Person-shape gaps. (a) The `tokens.length > 4` cap returns "not person" for 5-plus-part full names. (b) Single-letter or masked initials (`A.`, `A***`, `W.`) count as `other`. (c) `abd`/`abdel`/`abdul`/`عبد` are neither connectors nor names, and the second half (`rahman`/`الرحمن`) is not a name. (d) Transfer words and wallet brands (`to`, `from`, `transfer`, `ipa`, `الى`, `تحويل`, `vodafone cash`/`فودافون كاش` …) count as `other`, so a name after them passes. A plausible InstaPay or wallet person payee is therefore eligible. | (a) Drop the token ceiling for all-name strings (the 64-character cap remains). (b) Treat 1-letter Latin or Arabic tokens and `*`-masked tokens as initials, skipped like connectors, while still requiring at least one name. (c) Add `abd`, `abdel`, `abdul`, `abdal`, `عبد` to the connectors, and the common second halves (`الرحمن`, `الله`, `العزيز`, `الفتاح`, `rahman`, `aziz`, `fattah` …) to the names or to a compound list. (d) Skip transfer, wallet and «لـ/الى» stop words (and refuse when one appears with a name). Add each probe row above as a table test. |
| **B94-M4** | **major** (privacy) | `app/assets/data/eg_honorifics.txt` (consumed by `llm_eligibility.dart`) | The honorific list covers `dr eng mr mrs ms ا استاذ حاج حاجه د دكتور م` only. Missing: Latin `hag`/`haj`/`hajj`/`hagg`, Arabic `شيخ` (Latin `sheikh` happens to be refused), `captain`/`capt`/`كابتن`, `madam`/`مدام`, `ostaz`/`ustaz`/`ostaza`, `مهندس`/`مهندسه`, `انسه`/`miss`, `mister`. Batch-90 M1–M3 made Latin transliterations a required variant class. | Extend the list. If `eg_honorifics.txt` belongs to T-325, note that in the fix. Add table rows for each. |
| B94-m9 | minor | `packages/zaghlol_parsing/lib/categorize/llm_eligibility.dart:74–90` | With `kind` stated by the caller and a null counterparty, a misclassified transfer falls to the text rules only. | In T-358, derive `kind` from typed fields (source, direction, event category), never from text, and add a test there. Optionally treat `counterpartyKind == null` together with a transfer-like `source` as `notBusinessPayment`. |

---

## Non-negotiables (CLAUDE.md §2) across the batch
- No backend call carries financial data. The phone's outgoing request is `sentText` plus the FR-LLM-02 fields (T-343). Exposures are recorded above (B94-M2, and the open person-name question).
- No `double` money. The backend spend math uses `decimal`/`numeric`, and the app has no money arithmetic in this diff.
- No raw SMS or question text in logs. Backend log templates are constant, and the app flow and gateway do not log.
- RTL: the T-345 widgets use directional insets and the first-strong direction with bidi isolates. No hard-coded user-facing strings.
- Nothing new is persisted on the phone except the consent grant `{provider, v, at}`.

## Follow-ups (minors; not blocking)
B94-m1 (T-338/T-351), B94-m2 (FU-411 admin host), B94-m3, B94-m4–m6 (T-339 owner), B94-m7 (T-348), B94-m8 (T-348/T-346), B94-m9 (T-358), and the nickname/Coptic additions to `eg_given_names.txt` (T-325 list owner).

## Fix round — T-343

**B94-M2 (major, privacy): fixed.** `MaskSourcesDrift.load` now reads every distinct `merchant_raw` and `merchant_norm` (deduped by `GROUP BY` in SQL), including rows with `merchant_norm` NULL (manual entries, edited merchants). Such rows get the mask id `merchantKey(raw)` (the categoriser's normaliser, read-time, no migration, no schema change). `ChartRepository.merchantSpend` and `biggestExpense` (what `PlanExecutor` uses to resolve a merchant mask id) now also match NULL-norm rows whose `merchantKey(merchant_raw)` equals the id (`_merchantMatch`), so a masked question about a hand-typed merchant is still answered correctly. There is no user-alias table (catalog aliases are public). Person/counterparty names are still not masked (open PO decision); the file header notes that adding a counterparty kind is one more query.

Tests: `llm_ask_boundary_test.dart` gains a manual-entry and an edited-merchant fixture (norm NULL), two questions naming them and the names in the never-on-the-wire list; `plan_executor_test.dart` gains 'B94-M2 ... answered by its read-time key'; `mask_sources_drift_test.dart` updated (the old assertion encoded the bug) plus a 5,000-transaction load under 200 ms. With the `lib/` changes stashed, the boundary, executor and sources tests fail; with them, they pass. `consent_sheet_golden_test` goldens fail identically on the unmodified branch (environment); not touched.
