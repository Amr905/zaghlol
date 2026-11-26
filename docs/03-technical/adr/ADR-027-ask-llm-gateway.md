# ADR-027: LLM gateway for the online helper and automatic categories

| | |
|---|---|
| Status | Proposed (Phase 3, awaiting PO approval) |
| Date | 2026-11-26 |
| Deciders | Product owner (ASK-LLM, LLM-CATEGORISE, D-88…D-96), solution-architect |
| References | `docs/03-technical/ask-llm.md`, `docs/03-technical/llm-categorise.md`; SRS `ask-llm.md` v0.2, `llm-categorise.md`; ADR-012 (attestation on restore), ADR-022 (backend), ADR-026 (HostSecrets) |

## Context
D-88 and D-94 allow two LLM uses while keeping financial data on the phone: (1) a typed, scrubbed and placeholdered question
becomes a **plan** that the phone executes; (2) a normalised business merchant name becomes one **system category code**. Both
need the same server pieces: provider access with no retention, a structured-output contract the model cannot leave, quotas per
install/account per Cairo calendar month (5/50 questions, 15/150 merchants), device attestation, rate limits, a spend cap, a kill
switch and no logging of the text. The backend runs on a 256 MB shared IIS site with embedded workers (ADR-026) or on the
self-hosted kit (ADR-025); store accounts (Play Console, App Store Connect) are not set up yet, so real attestation tokens can't
be produced. The PO asked for the cheapest two providers to be compared on an Egyptian-Arabic accuracy test (D-91).

## Options
**A. Where the model runs**
1. Backend gateway calling a hosted provider (chosen below).
2. On-device model (e.g. a small open model): no text leaves the phone, but hundreds of MB of download, weak Egyptian Arabic,
   slow on mid-range phones, and still needs a closed output contract. Rejected for v1; keep the plan schema so it could plug in later.
3. App calls the provider directly: exposes the provider key, no quota or kill switch. Rejected.

**B. Output contract**
1. Provider structured output (JSON Schema, strict) + server and phone validation (chosen).
2. Free-text answer parsed by heuristics: unbounded injection surface, numbers from the model. Rejected (FR-LLM-05/08).
3. Tool/function calling with one tool per plan: equivalent safety, more tokens and provider-specific shapes. Kept as a fallback
   if a provider's JSON Schema subset can't express `anyOf`.

**C. Providers** (prices per 1M tokens, paid/standard tier, read 2026-11-26)
| Candidate | Model id (config) | Input / cached / output | Retention | Notes |
|---|---|---|---|---|
| OpenAI | `gpt-6-luna` | **$0.10 / $0.01 / $0.50** on the model page; the pricing page lists **$0.05 / $0.005 / $0.25** | API data not used for training; abuse-monitoring logs up to 30 days by default; ZDR / Modified Abuse Monitoring need OpenAI approval | Structured outputs supported; reasoning effort `none` available; regional processing +10 % for models released on or after 5 Mar 2026 |
| Google | `gemini-3.1-flash-lite` | **$0.25 / $0.025 / $1.50** (Gemini API) | Paid-tier data not used to improve products; guaranteed ZDR requires Vertex AI; explicit `cached_content` and Search/Maps grounding store data (avoid) | Vertex AI regional endpoint; Vertex price to confirm at contract |
| Excluded | `gemini-2.5-flash-lite` ($0.10 / $0.40) | | | Model page: access limited to users who already used the 2.5 models; new projects pointed to newer models |
| Excluded | `gpt-5-nano` ($0.05 / $0.40) | | | Its snapshot is listed as deprecated; the page recommends GPT-6 Luna |

Sources: [OpenAI GPT-6 Luna model page](https://developers.openai.com/api/docs/models/gpt-6-luna.md) ·
[OpenAI pricing](https://developers.openai.com/api/docs/pricing?latest-pricing-expanded=true) ·
[OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data) ·
[OpenAI GPT-5 nano](https://developers.openai.com/api/docs/models/gpt-5-nano) ·
[Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing) ·
[Gemini zero data retention](https://ai.google.dev/gemini-api/docs/zdr.md.txt) ·
[Gemini 2.5 Flash-Lite](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-lite).

**D. Quota month:** Cairo calendar month (chosen; matches the approved FR-LLM-10 copy "resets on 1 December") vs UTC month
(simpler, but resets at 02:00/03:00 Cairo on the 1st). The spend ledger uses UTC days/months because provider billing does.

**E. Attestation before store accounts exist:** (1) skip attestation until launch: no; (2) a fake verifier everywhere behind a
remote flag: a flag could weaken production, rejected; (3) staged modes bound to the environment, production always enforcing (chosen).

## Decision
1. **One backend LLM gateway** in `Zaghlol.Application/Llm` with `ILlmProvider` and two plain-`HttpClient` adapters
   (`OpenAiResponsesProvider`, `VertexGeminiProvider`) plus a fake. Model ids, endpoints, regions and prices are configuration;
   the active provider is the remote config value `llm.provider`. No vendor SDK, no new backend package (uses
   `Microsoft.Extensions.Http.Resilience`, `JsonSchema.Net`, `Google.Apis.Auth`, already referenced). Provider API keys come from
   the active KMS provider's secret store (File, HostSecrets `ZAGHLOL_KEYS__llm_<id>`, OpenBao KV), never from configuration files.
2. **Structured output only**: `ask-plan/1` (closed catalogue, placeholders, template grammar) and `cat/1` (index + closed category
   enum + confidence). The backend validates before replying and the phone validates again; invalid → fallback, not counted.
3. **Provider choice by evaluation**: the 40-item ar/en set (recorded in CI, live on demand). Default if both pass: the cheaper,
   expected to be `gpt-6-luna`; else `gemini-3.1-flash-lite` on Vertex AI. Request OpenAI ZDR (or Modified Abuse Monitoring);
   until granted the privacy policy names the 30-day window (FR-LLM-33 allows "the shortest abuse-monitoring window offered").
4. **Quotas** in one table `llm_quota_counters (feature, subject_kind, subject_id, month_key, used, last_request_hash)`, Cairo month,
   idempotent per request id; **spend** in `llm_spend_daily` with an 80 % alert and a 100 % pause shared by both features.
5. **Attestation** reuses the restore verifiers with new body-binding prefixes (`zaghlol-ask-v1`, `zaghlol-cat-v1`); modes `Fake`
   (Development/Testing), `ReportOnly` (Staging), `Enforce` (forced in Production). The flags go on in production only after
   real enforcement is verified.
6. **No text at rest**: no column for question text or templates; scrub tests over logs, traces, metrics and tables. Merchant
   names are stored only in the categorise cache and feedback tables, as D-96 allows.

## Consequences
- Cost: about $0.0001–0.001 per question and $0.00001–0.0002 per new shop; a $20 monthly cap covers ≈ 20 000 questions.
- A provider switch is a config change plus re-consent (UX-ASK-02); the eval must pass first.
- Until store accounts exist, production can't serve either feature; staging and tests run on the fake/report-only modes.
- A new remote-config channel (`remote_config` table, signed sync `config` block) is introduced and reused by later features.
- Play Integrity is now called per question; the daily quota must be raised before launch.
- The gpt-6-luna price discrepancy between OpenAI's two pages is unresolved; budgets use the higher figure.
- Revisit when an on-device model can pass the same eval (option A2): the plan schema and phone validator stay unchanged.
