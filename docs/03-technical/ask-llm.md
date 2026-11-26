# Ask Zaghlol online helper and the shared LLM gateway: technical specification (ASK-LLM)

| | |
|---|---|
| Status | **DRAFT, awaiting PO approval** (Phase 3 for ASK-LLM and LLM-CATEGORISE) |
| Date | 2026-11-26 |
| Requirements | `docs/01-requirements/ask-llm.md` v0.2 (D-88…D-93, approved) · `llm-categorise.md` (D-94…D-96, approved as a whole 2026-11-26) |
| Design | `docs/02-design/ask-llm-ux.md` (approved, UX-ASK-01…08 defaults) |
| Decision | [ADR-027](adr/ADR-027-ask-llm-gateway.md) (gateway, provider abstraction, attestation staging, quota storage) |
| Sibling | [`llm-categorise.md`](llm-categorise.md): the categorise feature on the same gateway |

## 1. Components and data flow

```
PHONE: question ─► AskEngine (offline, unchanged) ─ AskUnderstood ─► local answer (no request, no quota)
  └ AskUnrecognized ─► digits (FR-PAR-04) ─► ClientScrub (FR-LLM-03) ─► ReferenceMasker (D-92) ─ unresolvable ─► clarification
  ─► LlmGate (flag ask_llm · paused · quota snapshot · online · consent{provider,v}) ─► LlmAskClient: POST /v1/ask/plan + attestation
BACKEND: network bucket ─► install token ─► Zaghlol-App ─► strict JSON ≤ 4 KB ─► flag per install (kill switch) ─► spend cap
  ─► consent = active provider ─► install/account buckets ─► attestation (body-bound) ─► tier + quota pre-check
  ─► ILlmProvider (structured output) ─► PlanValidator (§2.4) ─► ask_llm_invest gate ─► commit count ─► 200 {plan, counted, quota}
PHONE: PlanValidator (own pinned copy) ─► PlanExecutor (repositories, per currency) ─► TemplateFiller ─► bubble
```

Every stage on the phone is a pure function except the executor (reads Drift) and the client. The placeholder map lives only in
the `MaskResult` object of one question (FR-LLM-19) and is dropped when the answer is rendered.

## 2. Plan schema `ask-plan/1`

One JSON Schema file, `backend/contracts/ask-plan-v1.schema.json`, is the source for: the provider's structured-output schema,
the backend validator (JsonSchema.Net, already a dependency) and generated Dart constants (`packages/zaghlol_parsing/lib/chat/llm/`).
Shared vectors: `backend/tests/Zaghlol.Contract.Tests/vectors/ask-plan-v1.json` (valid and invalid plans, with the sent question),
run by both .NET and Dart tests. Breaking change = `ask-plan/2`; the request carries `planVersion` and the backend answers in that version.

### 2.1 Envelope
```json
{ "v": 1, "plan": "PL-WHATIF-CUT",
  "p": { "target": {"slug":"dining","ref":null,"mention":null,"currency":null},
         "mode": {"kind":"percent","percent":50,"amount":null,"currency":null}, "months": 12 },
  "t": { "lang": "ar", "text": "لو قللت {target} {pct}، هتوفر حوالي {monthly} في الشهر، يعني {total} في {months}." } }
```
`p` is an `anyOf` of one closed object per plan (all fields required, `null` for unused, `additionalProperties:false`), so it
works with OpenAI strict structured outputs and Gemini `responseJsonSchema`. `t` is `null` or a template (§2.3).

### 2.2 Common types and plan variants
- **Period** `{k, o, n, m, y}`: `k` ∈ day·week·month·year·cycle·lastDays·monthOfYear·allTime (= `AskPeriodKind`); `o` int −36…0; `n` 1…366 only for lastDays; `m` 1…12 and `y` 2000…2100|null only for monthOfYear; others `null`.
- **Filter** `{slug, ref, mention, currency}`: at most one of `slug` (system category code, enum from the bundled catalog), `ref` (placeholder `^⟦(ACCOUNT|CARD|BANK|MERCHANT)_[1-9]⟧$`, U+27E6/U+27E7), `mention` (1…40 chars, no digits); `currency` ISO 4217 `^[A-Z]{3}$`|null.
- **Amount** `{amount, currency}`: `amount` decimal string `^[0-9]{1,9}(\.[0-9]{1,3})?$`, fraction ≤ the currency exponent; `currency` null = primary. Must equal a number in the sent question or a bundled number word («ألف», «ميت», "thousand"…); otherwise PL-FALLBACK (the model may not invent amounts).

| Plan | `p` fields (ranges) |
|---|---|
| PL-SPEND · PL-COMPARE | period, filter · periodA, periodB, filter |
| PL-BREAKDOWN · PL-TOPN | period, by ∈ category·merchant·account, limit 1…10 · period, of ∈ merchant·category·expense, n 1…10 |
| PL-AVERAGE · PL-INCOME · PL-SAVED | per ∈ day·week·month, period, filter · period, filter (slug null) · period |
| PL-BILLS-DUE · PL-BUDGET-LEFT · PL-SAFE-SPEND | windowDays 1…60 · slug|null · — (empty object) |
| PL-BALANCE | ref (ACCOUNT/CARD/BANK placeholder)|null |
| PL-WHATIF-CUT | target (filter without currency), mode `{kind: percent|amount, percent 1…100|null, amount|null, currency|null}`, months 1…60 |
| PL-WHATIF-SAVE | amount, months 1…60 |
| PL-SUGGEST | currency|null |
| PL-INVEST | source `{kind: savedLastPeriod|whatIf|amount, whatIf: <PL-WHATIF-CUT p>|null, amount|null}`, instruments ⊆ {gold, usd, certificate, index} (1…4, unique), horizonMonths 1…24 |
| PL-FALLBACK | reason ∈ unsupported·ambiguous·zakah·noData |
| PL-REFUSE | reason ∈ offTopic·unsafe·specificPick, selfHarm bool |

### 2.3 Template grammar (FR-LLM-35)
`t.text`: NFC, 1…200 chars, one line; `t.lang` = the request `lang`; only the blanks allowed for that plan (`{target}`, `{period}`,
`{periodB}`, `{amount}`, `{amountB}`, `{diff}`, `{pct}`, `{monthly}`, `{total}`, `{months}`, `{count}`, `{date}`), each at most once.
Rejected if it contains: any digit (`\p{Nd}`), `⟦`/`⟧`, `{` not forming an allowed blank, `@`, `://`, `www.`, a `label.tld` shape,
`< > [ ] ( ) * _ # \` | ~`, control or bidi-override characters, more than one emoji, or (ar) < 70 % Arabic-script letters / (en)
any Arabic letter. Templates are used only for single-currency answers of data and what-if plans; PL-INVEST, PL-SUGGEST,
PL-REFUSE, PL-FALLBACK and multi-currency answers always use app templates (BR-LLM-04). Any failure → app template, plan kept.

### 2.4 Validation (backend and phone, same rules)
1. JSON Schema valid. 2. Every `ref` occurs verbatim in the sent text; no plain-text account/card/bank name in any string
(phone: checked against its registry and the mask sources; backend: against the bundled registry aliases). 3. `mention` is a
substring of the sent text after normalisation. 4. Amount rule (§2.2). 5. Cross-field rules (one filter key; `n`/`m` only for
their `k`). 6. Template grammar (failure drops `t` only). Failures 1–5 → **PL-FALLBACK, `counted:false`**. The phone pins its
schema copy per release and applies the same steps after the backend (defence in depth, FR-LLM-06).

### 2.4a Contract details fixed by T-322 (vectors are authoritative)
- **Step 5 also ties `plan` to `p`:** `p` must validate against `$defs/P_<plan>` of the schema (the `anyOf` alone can't), reason `PLAN_MISMATCH`. Other cross-field rules: `n` only with `lastDays` and required there, `m` only with and required for `monthOfYear`, `y` only with `monthOfYear`; `mode.percent` set exactly when `kind = percent`, `mode.amount` exactly when `kind = amount`; `source.whatIf` exactly for `whatIf`, `source.amount` exactly for `amount`; `instruments` unique; `PL-WHATIF-CUT` `target.currency` null; `PL-INCOME` `filter.slug` null.
- **Normalisation** for steps 3 and 4 is `foldKey` (`packages/zaghlol_parsing/lib/normalize/text_normalizer.dart`). A number in the text is `[0-9]+(,[0-9]{3})*(.[0-9]+)?` after folding, compared as a decimal; number words are whole words after folding. The fraction rule applies when `currency` is non-null (the phone re-checks `null` against its primary currency).
- **Template blanks per plan** and the ordered step 6 rules with reason codes are in `vectors/ask-plan-v1.json` (`templateBlanks`, `templateRules`). `t.lang` and `t.text` carry no schema constraint, so a bad template drops only `t`.
- Reason codes are fixed strings (`SCHEMA_INVALID`, `REF_NOT_IN_TEXT`, `PLAIN_NAME`, `MENTION_NOT_IN_TEXT`, `AMOUNT_NOT_IN_TEXT`, `AMOUNT_FRACTION_TOO_LONG`, `PLAN_MISMATCH`, `FILTER_MULTIPLE_KEYS`, `PERIOD_FIELD_MISMATCH`, `MODE_FIELD_MISMATCH`, `SOURCE_FIELD_MISMATCH`, `INSTRUMENTS_DUPLICATE`, `TARGET_CURRENCY_SET`, `INCOME_SLUG_SET`, `TEMPLATE_*`); they are what a validator logs (never the text).

### 2.5 Prompt, tokens, cost
- System prompt `ask-plan-v1` (file in `Zaghlol.Application/Llm/Prompts/`, hash in metrics): role, rules (plans only, placeholders opaque, never answer numbers), the catalogue in one line per plan, 14 short ar/en/mixed examples. Static and **first** in the request, the question last, so automatic prefix caching applies (OpenAI caches prefixes ≥ 1 024 tokens; Gemini implicit caching). No conversation history, no user data, no install data (FR-LLM-34).
- Budget per call: system ≈ 1 300 + schema ≈ 900 (≈ 2 200 cacheable) + question ≤ 150 input tokens; output capped at `max_output_tokens = 300` (typical 120–200); reasoning `none` (OpenAI) / minimal thinking (Gemini).
- **Cost per question** (prices in ADR-027): gpt-6-luna ≈ **$0.00014** cached / **$0.00034** uncached / ≤ $0.0004 worst; gemini-3.1-flash-lite ≈ **$0.0004** cached / **$0.0009** uncached / ≤ $0.0011 worst. Planning figure **$0.001 per question**: 10 000 questions ≈ $10.

## 3. Provider abstraction (details and vendor evidence: ADR-027)

```csharp
public interface ILlmProvider { string Id { get; } Task<LlmResult> CompleteAsync(LlmCall call, CancellationToken ct); } // Zaghlol.Application/Llm
public sealed record LlmCall(LlmFeature Feature, string PromptId, Sensitive<string> UserText, string Lang, JsonElement OutputSchema, int MaxOutputTokens);
public sealed record LlmResult(LlmOutcome Outcome /* Ok|Invalid|Timeout|Upstream|Refused */, Sensitive<byte[]> Json, LlmUsage Usage /* in, cached, out */);
```
- Adapters (plain `HttpClient`, no vendor SDK): `OpenAiResponsesProvider` (`POST /v1/responses`, `store:false`, `text.format = json_schema strict`, `reasoning.effort = none`, `max_output_tokens`), `VertexGeminiProvider` (`generateContent` on a regional Vertex AI endpoint, `responseMimeType: application/json`, `responseJsonSchema`, minimal thinking, no `cachedContent`, no grounding, service-account OAuth via `Google.Apis.Auth`, already a dependency), `FakeLlmProvider` (recorded fixtures; Development/Testing only).
- Configuration `Llm:Providers:<id>:{Kind, Model, Endpoint, Region, TimeoutMs, PriceInPerMTok, PriceCachedPerMTok, PriceOutPerMTok}` (decimals); the active id is the remote config value `llm.provider` (§4.6), so switching needs no deploy. Model ids and prices are configuration, never constants.
- **API keys** come from the active KMS provider's secret store, never from `appsettings*.json`: File KMS `<keydir>/llm_<id>.secret` (same mode checks), HostSecrets `ZAGHLOL_KEYS__llm_<id>` (same JSON wrapper with a `secret` field, same refusal of file sources, ADR-026), OpenBao KV path `zaghlol/llm/<id>`. Read once at start; never logged, never in problem bodies; rotation = new value + restart.
- **No retention:** OpenAI `store:false` + ZDR/Modified Abuse Monitoring requested for the project; Vertex AI with no caching or grounding (Google's ZDR conditions). The provider contract and region are launch-checklist items (OQ-ASK-03).
- **Resilience** (`Microsoft.Extensions.Http.Resilience`, already used): attempt timeout 8 s; total budget 9 s (client waits 12 s); one retry only on connection failure before the request was sent; circuit breaker per provider (≥ 50 % failures over 30 s with ≥ 10 calls, or 5 in a row → open 30 s, one half-open probe). Open circuit → `502 UPSTREAM_UNAVAILABLE`, not counted.
- **Evaluation harness** (`backend/tests/Zaghlol.LlmEval/`): the 40-item set of SRS §10.1 as synthetic YAML (question, lang, expected plan + params or refusal). CI runs it against **recorded** provider replies per adapter (WireMock, deterministic) and checks the validator path. A manual workflow `llm-eval-live` (secrets in a protected environment) runs it against each live provider and writes a report: exact plan + params, refusal/injection items, schema failures, p95 latency, tokens, cost/1 000. **Pass:** ≥ 36/40, all 9 refusal/injection items correct, 0 schema failures reaching the phone, p95 ≤ 4 s; then the cheapest wins. Re-run on every prompt, schema or model change; recordings refreshed from the live run.

## 4. Backend

### 4.1 `POST /v1/ask/plan` (install token; `Zaghlol-Account` optional)
```json
// request (closed, ≤ 4 KB; 16 KB when attestation carries an attestationObject, backend-api §4.9)
{ "planVersion": 1, "requestId": "01JD…(ULID)", "q": "صرفت كام بكارت ⟦CARD_1⟧ في ⟦MERCHANT_1⟧؟", "lang": "ar",
  "consent": { "provider": "openai-luna", "v": 1 },
  "attestation": { "type": "play_integrity", "token": "…" } }      // or {"type":"app_attest","keyId","assertion","attestationObject"?}
// 200
{ "serverTime": "…", "plan": { …§2… }, "counted": true,
  "quota": { "limit": 5, "used": 3, "remaining": 2, "resetsAt": "2026-11-30T22:00:00Z" } }
```
`q`: 1…300 chars after trim, NFC. `lang` ∈ ar·en. Platform and version come from `Zaghlol-App`. Not signed (not an anchoring
operation; the phone validates the plan itself). Problem bodies may carry the extension member `quota` (only for the codes below).

| HTTP | `code` | When | Counted | App |
|---|---|---|---|---|
| 403 | `LLM_QUOTA_EXHAUSTED` (+`quota`) | install or account counter at its limit | no | at-limit bubble (Free/Gold) |
| 409 | `LLM_CONSENT_REQUIRED` (+`providerId`) | `consent.provider`/`v` ≠ active provider or consent version | no | clear consent, show sheet (UX-ASK-02) |
| 503 | `LLM_SERVICE_PAUSED` | flag off for this install, spend cap reached, or LLM module disabled | no | paused bubble, hide counter; no auto-retry |
| 422 | `DEVICE_ATTESTATION_FAILED` | proof missing/invalid/stale/replayed | no | integrity copy, one Try again |
| 429 | `RATE_LIMITED` | network, install, account or global bucket | no | slow-down copy |
| 502/503 | `UPSTREAM_UNAVAILABLE` | provider timeout/5xx/open circuit, attestation service outage | no | error + Try again |
| 400 | `VALIDATION_FAILED`, `UNKNOWN_FIELD` | malformed body | no | bug |

A valid model reply of PL-FALLBACK or PL-REFUSE is counted (FR-LLM-10); a validator failure or a PL-INVEST while
`ask_llm_invest` is off becomes PL-FALLBACK with `counted:false`.

### 4.2 Quota storage
Table `llm_quota_counters` (shared with categorise, §4.5). **Month = calendar month in Africa/Cairo** (FR-LLM-10, approved): the
user sees "resets on 1 December" in local terms, and a UTC month would reset at 02:00 Cairo on the 1st, contradicting that copy.
`month_key` = `yyyymm` of the request time converted with `TimeZoneInfo` id `Africa/Cairo` (IANA ids resolve on Windows/IIS with ICU,
.NET 10; startup self-check, else the LLM module stays disabled → `LLM_SERVICE_PAUSED`). `resetsAt` = first instant of the next
Cairo month, in UTC. Tests cover DST changes and 30 Nov 23:50 / 1 Dec 00:05 Cairo.
- Limit = remote config `ask.quota_free` / `ask.quota_gold`; Gold only for the install holding a Gold seat, paused Gold = Free (existing seat/entitlement services). With an account token, the account counter uses the calling install's limit and the request is refused if either counter is at its limit (FR-LLM-11).
- **Commit:** after a valid reply, one statement per subject: `UPDATE … SET used = used + 1, last_request_hash = $h WHERE … AND used < $limit AND last_request_hash IS DISTINCT FROM $h` (insert-on-conflict for the first use). Concurrent requests can overshoot by the in-flight count, bounded by the install burst (3); accepted and documented.
- **Idempotency:** `requestId` is a ULID per question; `last_request_hash = SHA-256(requestId)`. A retry with the same id passes the pre-check even at the limit and is never counted twice. No response body is stored (it may echo the question), so a retry calls the provider again (charged to the ledger, not to the user).
- **Stop:** the provider call is cancelled with `HttpContext.RequestAborted`. Stop before the provider answered → not counted; Stop after the reply was validated → counted (the backend decides; copy promises nothing, UX-ASK-05).
- Retention: rows of months before the previous one are deleted by the retention purger; `DELETE /v1/installs/me` and `DELETE /v1/accounts/me` delete their subject's rows.

### 4.3 Rate limits, spend cap, kill switch
- Buckets (in-process, existing `ZaghlolRateLimits` style, config `RateLimits:Ask*`): per install 3/min burst 3 and 20/day; per account the same; per /24 30/min; global `Llm:GlobalPerMinute` (default 120). Categorise has its own install buckets (2/min, 30/day).
- **Spend ledger** `llm_spend_daily` (UTC day; provider billing is UTC) is incremented after **every** provider call, counted or not, with tokens and cost from the configured prices (`numeric`). The month's total (UTC month) is cached for 60 s per process. ≥ 80 % of `llm.spend_cap_usd` → one alert per month through the existing ops notifier; ≥ 100 % → both LLM features answer `LLM_SERVICE_PAUSED` until the next month or a cap raise. Overshoot ≤ 60 s × global rate × worst call cost (≈ $0.13 at defaults).
- Flags `ask_llm`, `ask_llm_invest`, `llm_categorise` join the closed `FlagKeys` set; the endpoint evaluates them per install on every request (FR-LLM-61), independent of the app's cached copy.

### 4.4 No logging of question text
`q`, `p`, `t` and provider bodies are held as `Sensitive<…>` and never reach a logger, span tag, metric tag, problem body or the DB.
The request log keeps route template, status, duration and the pseudonymised install (existing policy). Provider HTTP spans record
host and status only (no URL query, no body). Validation failures log a fixed reason code. **Scrub tests** (integration, fake
provider): a marker question and a marker template are sent through success, fallback, validation-failure, timeout and exception
paths; the in-memory log sink, the in-memory OTel exporter, metrics and a full dump of every table must not contain the marker.

### 4.5 Database migration (expand-only)
```sql
CREATE TABLE llm_quota_counters (
  feature text NOT NULL CHECK (feature IN ('ask','cat')), subject_kind text NOT NULL CHECK (subject_kind IN ('install','account')),
  subject_id uuid NOT NULL, month_key integer NOT NULL CHECK (month_key BETWEEN 202601 AND 209912),
  used integer NOT NULL CHECK (used >= 0), last_request_hash bytea, updated_at timestamptz NOT NULL,
  PRIMARY KEY (feature, subject_kind, subject_id, month_key));
CREATE TABLE llm_spend_daily (
  day date NOT NULL, feature text NOT NULL CHECK (feature IN ('ask','cat')), provider_id text NOT NULL, model text NOT NULL,
  calls integer NOT NULL, input_tokens bigint NOT NULL, cached_tokens bigint NOT NULL, output_tokens bigint NOT NULL,
  cost_usd numeric(14,6) NOT NULL, PRIMARY KEY (day, feature, provider_id, model));       -- kept 13 months (FR-LLM-62)
CREATE TABLE remote_config (key text PRIMARY KEY, value text NOT NULL, version bigint NOT NULL, updated_by uuid, updated_at timestamptz NOT NULL);
```
No text column can hold a question. `remote_config` is a **closed key set** like `FlagKeys` (`llm.provider`, `llm.spend_cap_usd`,
`ask.quota_free`, `ask.quota_gold`, `ask.s1_pct`, `ask.s4_share_pct`, `ask.s4_saving_pct`, `ask.cd_example_rate_bp`,
`ask.invest_min_egp`, `ask.invest_gold_min_cg`, `ask.invest_gold_karat`, `cat.*` of the sibling doc), typed and range-checked,
edited by `flags_admin` through `PUT /admin/v1/config/{key}` (audited) and `zaghlol-ops config set`. Grants: `app_rw` R/W on the
counters and ledger, R on config; `worker_rw` DELETE on counters (purger). Categorise tables: sibling doc §4.

### 4.6 Remote config to the app
`POST /v1/sync` gains a signed `config` block `{version, values}` (sent when `configVersion` differs, like `flags`) carrying the
app-relevant keys and `llm.providerName` per language for the consent sheet. Missing or stale (> 14 days) → bundled defaults; the
LLM UI stays governed by the flags (fail closed).

### 4.7 Hosting
IIS in-process with embedded workers (ADR-026, deployment §7) and the self-hosted kit run the same code: calls are inline (no queue),
purge and alert checks join the embedded retention/heartbeat jobs, outbound 443 to the provider (verify at first deploy), no SDKs, one `HttpClient` per provider (256 MB RAM).

## 5. Attestation (FR-LLM-14)
- **Binding:** `bodyHash = SHA-256("zaghlol-ask-v1" ‖ 0x00 ‖ installId ‖ 0x00 ‖ JCS(body without "attestation"))` (installId from the install token). Android: Play Integrity **standard request** with `requestHash = b64u(bodyHash)`, verified by the existing `IPlayIntegrityVerifier` (5-min freshness, replay guard, `PLAY_RECOGNIZED`, device or basic integrity per R-19). iOS: App Attest assertion over `clientDataHash = SHA-256("zaghlol-ask-attest-v1" ‖ 0x00 ‖ bodyHash)` with the install's registered key (`app_attest_keys`, existing `IAppAttestVerifier`, counter strictly increasing); `attestationObject` on a key's first use. Vectors `ask-binding-v1.json` (and `cat-binding-v1.json`) for .NET and Dart.
- **Feasible now:** neither Play Console nor App Store Connect is set up (PO-blocked), so no real token can be produced. Staged plan:

| Stage | Environment | `Llm:Attestation:Mode` | Behaviour |
|---|---|---|---|
| 0 now | Development, Testing | `Fake` | accepts only `{"type":"dev","proof":"<HMAC of bodyHash with a test key>"}` from debug builds; refused at start in any other environment |
| 1 now | Staging | `ReportOnly` | verifies real proofs when present, counts failures by reason, does not refuse (side-loaded builds) |
| 2 store accounts live | Production | `Enforce` (forced) | Production ignores the setting and always enforces; with verifiers unconfigured every request is `503 UPSTREAM_UNAVAILABLE`, so `ask_llm` stays off |

  Production never weakens: a startup guard refuses `Fake`/`ReportOnly` outside their environments, and no remote flag can relax enforcement. "Enforce by remote flag later" means turning `ask_llm` on in production only after stage 2 is verified (launch checklist). Play Integrity per-question volume: request a daily-quota increase in the Play Console before launch.

## 6. App
```
packages/zaghlol_parsing/lib/chat/llm/  client_scrub · reference_masker · plan_schema.g · plan_validator · template_grammar · number_words
packages/zaghlol_domain/lib/ask/        what_if · savings_suggest (S1–S4) · invest_bands (§3.4/3.4a)          (both pure Dart)
app/lib/core/llm/                       llm_consent · llm_quota_snapshot · llm_attestation · llm_gateway_client   (shared with categorise)
app/lib/features/ask/  data: llm_ask_client, mask_sources_drift · application: llm_ask_flow, plan_executor, template_filler
                       domain: llm_answer_models · presentation: consent_sheet, sent_disclosure, quota_counter, llm_answer_views (+ S-71 row)
```
- **Masker (D-92):** sources = Drift accounts (label, nickname, institution + type, last-4), the bundled institution registry aliases ar/en (word-like aliases need an adjacent bank/account/card word), and merchant names from the user's own transactions (`merchant_norm` + display names). Matching on folded text (Arabic letter folding, Arabic-Indic digits, case, tatweel, diacritics), longest match first, token-boundary aware; 4-digit tokens within 3 words of a card/account word → `CARD`. Resolution per FR-LLM-20 before sending; failure → `MaskUnresolved(chips)` and no request. Output `MaskResult{sentText, map}`; `map` never leaves memory, `toString` redacts.
- **Executor:** one function per variant over existing repositories (`ChartRepository` spend/breakdown/top/average, accounts `listWithBalances`, cycle budgets, `safe_to_spend`, recurring/dues, prices store for gold `XAU21_G`/`XAU24_G` and FX). Per-currency results, primary first, no cross-currency sums except labelled ≈ USD lines; half-even rounding once per figure; amounts as `Money`. Missing `ChartRepository` queries (income totals, average over full units) are added there, not in the feature.
- **Calculators** are pure and table-tested from the SRS §10 examples (19 200.00, 3 000.00, top-3 S4/S1/S2, ≈ 1.12 g, bands at 100.00 / 100.01 / 999.99 / 1 000.00, G unknown). Comparisons in minor units, no `double`.
- **Settings (encrypted):** `ask.llm_consent` = `{provider, v, at}` (a different provider or `v` re-shows the sheet; cleared by the S-71 switch and "Delete everything"); `ask.llm_quota` = last `{limit, remaining, resetsAt}` ("—" before first contact or after `resetsAt`); `ask.llm_paused_until_sync` flag. At `remaining = 0` before `resetsAt` nothing is sent.
- **"What I sent":** kept **in memory only** on the chat message for the session (UX §2). It is derivable, the chat history today is in memory, and not persisting it removes one more copy. If chat history is persisted later, `sentText` stays excluded.
- **Hide amounts / digits:** the filler renders money through C-04 (masked `****`, grams hidden); percentages stay.
- **Flags:** `FeatureFlag.askLlm('ask_llm')`, `askLlmInvest('ask_llm_invest')`, `llmCategorise('llm_categorise')`; off → today's S-50.

## 7. Security and privacy review points

| Threat | Control |
|---|---|
| Prompt injection makes the model emit instructions, links, other plans | Closed schema via structured output; backend + phone validation; template grammar; app templates for INVEST/REFUSE/SUGGEST |
| Model invents numbers or names; MITM (user CA) alters a plan | Numbers only from the executor; amounts and `ref`s must occur in the question; phone validation, worst case one wrong local figure |
| Leak of account/card/bank/merchant names | Masker + scrub on the phone; outgoing inspection tests (§8); server rejects plans with plain registry names |
| Question text stored or logged | `Sensitive<T>`, no text columns, scrub tests over logs/traces/metrics/DB; provider `store:false`/ZDR |
| Replay, scripted abuse, quota farming | Body-bound attestation per request (Play replay guard, App Attest counter); install/account/24/global buckets; account counter |
| Cost blow-up, provider outage | 300-char input, 300-token output, ledger, 80 % alert, 100 % pause; 9 s budget, circuit breaker, not counted |
| Stale kill switch; provider key theft | Server-side flag check per request; keys only in KMS secret stores, file configs refused, rotation runbook |
| BR-SYNC-03 drift | Closed request body (`UNKNOWN_FIELD`); D-90 text added to the SRS and privacy policy (task D1) |

## 8. Test strategy
- **Pure Dart:** scrub/masker tables (SRS §10, ar/en/mixed, Arabic-Indic digits, word-like aliases, duplicate last-4); validator over shared vectors; grammar; calculators.
- **App unit:** executor per plan on a fixture DB (per currency, EC-23/24); orchestrator with a fake client (local-first, clarify, consent, quota 0, offline, paused, 409/422/429/502, Stop).
- **Widget (ar + en, light/dark, 130 %):** every S-50 state of UX §1, consent sheet with preview, "What I sent" chips, counter, S-71 row; goldens.
- **Backend unit:** validator vectors, Cairo month math (DST, edges), commit/idempotency SQL, spend cap, gating order, adapters vs WireMock recordings (`store:false`, schema, max tokens, no identifiers).
- **Backend integration (Testcontainers + fake provider):** pipeline, counting per outcome, duplicate `requestId` in parallel, account counter across installs, scrub, purge.
- **Device E2E (emulator, fake backend):** one question end to end in ar and en, consent, at-limit, airplane mode.
- **Negative proofs (2–3 per C4 task):** (1) captured request bodies/headers/URLs over the whole fixture set contain no fixture amount, merchant, account label, nickname, last-4 near a card word, registry alias or SMS string; (2) marker text absent from all backend sinks and tables; (3) a request without valid attestation or over quota never reaches the provider (fake provider call count 0).
- **Eval:** recorded 40-item run in CI; live run manual (§3).

## 9. Proposed task breakdown (ids by the planner)

| # | Task | Class | Agent | Depends | Size |
|---|---|---|---|---|---|
| A1 | Flags `ask_llm`, `ask_llm_invest`, `llm_categorise` (backend + app enums); `remote_config` table, admin endpoint, ops CLI, sync `config` block + app store | C2 | backend-engineer (+ flutter-core for app side) | — | M |
| A2 | LLM gateway core: `ILlmProvider`, OpenAI + Vertex adapters, fake, resilience, provider-key secret sources (File/HostSecrets/OpenBao), spend ledger + cap + alert, metrics, scrub tests | **C4** (keys → Opus) | backend-engineer | A1 | L |
| A3 | Quota store: `llm_quota_counters`, Cairo month, tier/account rules, idempotent commit, purge + delete flows, migration | **C4** | backend-engineer | A1 | M |
| A4 | Attestation for LLM endpoints: binding hashes, modes + startup guard, vectors | **C4** | backend-engineer | — | S |
| A5 | `POST /v1/ask/plan`: pipeline, plan schema file + validator, prompt v1, error codes, OpenAPI | **C4** | backend-engineer | A2–A4 | M |
| A6 | Eval harness: 40-item synthetic set, recorded CI run, live workflow + report | C3 | backend-engineer | A2, A5 | M |
| P1 | Client scrub + reference masker + outgoing inspection tests | **C4** | parsing-engine-engineer | — | M |
| P2 | Dart plan types/validator/template grammar/number words from the schema; shared vectors | C3 | parsing-engine-engineer | A5 (schema) | M |
| P3 | What-if, S1–S4 suggestions, investment bands (pure) | **C4** (financial math) | flutter-core-engineer | — | M |
| P4 | Plan executor over repositories, per currency | C3 | flutter-core-engineer | P2, P3 | M |
| P5 | Gateway client, attestation binding, gate, orchestrator, consent/quota settings | C3 | flutter-core-engineer | A4 vectors, P1, P2 | M |
| P6 | UI: S-50 states, consent sheet, "What I sent", counter, answers, S-71 row; widget/golden ar+en | C2 | flutter-ui-engineer | P5, P7 | L |
| P7 | Copy-deck Part 4 → ARB keys | C1 | boilerplate-engineer | — | S |
| P8 | Device E2E with fake backend | C2 | flutter-core-engineer | P6 | S |
| D1 | Docs: backend-api §2/§4/§6, backend-schema, SRS BR-SYNC-03 text, privacy policy + privacy-consistency rows | Docs | — | A5 | S |

Categorise tasks: sibling doc §8.

## 10. Open technical questions (recommended defaults)
1. **Provider:** run the eval on both; default **gpt-6-luna** if it passes (cheapest), else **gemini-3.1-flash-lite on Vertex AI**.
2. **Region / retention:** EU processing (OpenAI EU data residency, +10 % uplift on newer models; Vertex `europe-west`); request OpenAI ZDR or Modified Abuse Monitoring; until granted, the privacy policy states the 30-day abuse-monitoring window.
3. **Spend cap:** `llm.spend_cap_usd` = **$10/month** at launch (PO 2026-11-26; ≈ 10 000 questions or > 50 000 shops).
4. **gpt-6-luna price discrepancy** (pricing page $0.05/$0.25 vs model page $0.10/$0.50 per 1M): budget on the higher until billed.
5. **`remote_config` table + signed sync `config` block** as the remote-config channel (no such channel exists today): approve.
6. **Unsigned ask/categorise responses** (validated on the phone instead): approve.
7. **Quota overshoot** under concurrent requests (≤ 2 per month per install): accept.
8. **Play Integrity quota** per question: request an increase before launch; no per-question fallback without attestation.
