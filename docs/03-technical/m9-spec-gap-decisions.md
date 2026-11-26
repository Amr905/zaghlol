# M9 spec gaps: provider identity, model-written text, person names

| | |
|---|---|
| Status | Item 1 **decided** (technical, applied to `ask-llm.md` §4.5/§4.6 and `llm-categorise.md` §7). Item 2 **recommendation, needs PO approval** (reverses OQ-ASK-07; only its technical part 2.0 is applied). Item 3 **for the PO** (OQ-ASK-11). |
| Date | 2026-11-26 |
| Closes / feeds | FU-425 (+ FU-431), FU-409, FU-433, FU-438, FU-423 |
| Inputs | `ask-llm.md`, `llm-categorise.md`, ADR-027, SRS `ask-llm.md` FR-LLM-05/09/18/35, BR-LLM-04, OQ-ASK-07; batch-91 C1, batch-94 T-343, batch-95 T-344/T-349 |

## 1. FU-425: where the app learns the provider the consent is bound to (DECIDED)

**Decision.** The signed sync `config` block carries the **effective provider id** as the app-visible key `llm.provider`, and the provider's display names come from the **same** source as the id, so the id and the names the user agrees to can never come from two different configurations. The 409 is a **safety net only**: it never supplies the new terms.

**Rationale.**
- Learning from the first 409 means the first question after a provider switch is sent before the user agreed to the new provider. The backend parses the body before the consent gate, so the text reaches our server, though not the provider. With this decision that happens only in the short race between a switch and the next sync.
- The 409 also has no display names, so a sheet built from it would name the old provider.
- The sync already runs and carries no question, so this adds no round trip. Stale config (> 14 days) means no id, so nothing is sent (fail closed; the flags are off then anyway).
- The provider switch changes the `llm.provider` row version, so the block version moves and every app gets the new id on its next sync. A different id from the stored `{provider, v}` re-shows the sheet (UX-ASK-02).

**Wire (response side only; BR-SYNC-03 unchanged, the request still carries only `configVersion`).**
- `config.values["llm.provider"]`: the effective id (`^[a-z0-9][a-z0-9-]{1,31}$`; row if set, else `Llm:ActiveProvider`). It is present only when the id is non-empty **and** that provider has both display names. Otherwise the key is absent and `providerName` is null.
- `config.providerName {ar, en}`: same field as today. The source moves from the remote-config keys `llm.provider_name.ar/.en` to host configuration `Llm:Providers:<id>:DisplayNameAr` / `DisplayNameEn` (same character set). Startup refuses a configured provider without both names. The two `llm.provider_name.*` keys leave the closed key set; a stored row is ignored and the admin API answers 404.
- `PUT /admin/v1/config/llm.provider` refuses (400) an id that has no `Llm:Providers:<id>` section with names and a key (`HasKey`).
- `version`: unchanged formula, but `llm.provider` is now app-visible, so its row version counts. Residual: changing only the host fallback `Llm:ActiveProvider` does not move the version; the 409 net covers it, and the runbook says to switch providers through the row only.
- Consent version: stays a code constant on both sides (backend `LlmConsentTerms.Version`, app `askLlmConsentVersion` / `catLlmConsentVersion`, all 1). It is pinned by one shared fixture value `consentVersion: 1` in `fixtures/ask-plan-responses-v1.json`, which both test suites assert. Bumping it is an app release plus a deploy (out of scope).

**App behaviour.**
- `RemoteConfig.llmProvider` already parses `llm.provider`. Terms = `{provider: llmProvider, v, names: providerName}` only when the id **and** both names are non-empty; otherwise null, so nothing is sent.
- `askConsentTermsProvider` (sheet), `askLlmTermsProvider` (flow) and `llmCatTermsProvider` derive from that one value. This closes FU-431's "two places".
- On **409** (Ask): do not adopt `providerId` from the problem body. Clear the Ask consent, set the stored `configVersion` to 0 and run one sync (it carries no question). Then:
  - if the synced terms differ from the cleared consent, show the sheet once and resend on Allow (the existing `consentRetried` rule);
  - otherwise answer with the paused copy, with no resend (app too old, or a host-fallback drift).
- On **409** (categorise sender): clear `cat.llm_consent`, keep the queue (this is not a withdrawal), reset the config cursor, stop sending, and show the passive re-consent row.

**Tasks.**

| # | Task | Class | Agent | Size |
|---|---|---|---|---|
| 1a | T-334 follow-up: `llm.provider` app-visible with the effective id; names from `Llm:Providers:<id>` (startup check); retire the `llm.provider_name.*` keys; PUT validation; tests: the block id equals the gate id from one snapshot, a row switch moves the version, a block never has an id without names | C2 | backend-engineer | S |
| 1b | T-343/T-345/T-358 follow-up: one terms provider (id + names) feeding `askConsentTermsProvider`, `askLlmTermsProvider` and `llmCatTermsProvider`; wire `askConsentTermsProvider` in `ask_wiring.dart` (remove the FU-425 comment); the 409 handling above for Ask and categorise; tests for a provider switch, no names, stale config, and a 409 with the same id | C3 | flutter-core-engineer | M |
| 1c | T-348 / T-363 E2E: the fake backend switches provider between two syncs, so the next question shows the sheet again; no request before Allow | in the existing tasks | — | — |
| 1d | T-364 docs: backend-api line "Sync additions" (`values` may hold `llm.provider`; source of `providerName`), deployment.md `Llm:Providers:<id>:DisplayName*` and switch runbook | Docs | — | S |

## 2. FU-409 + FU-433 + FU-438: model-written template text

### 2.0 Applies under either option (technical, applied to `ask-llm.md` §2.4a)
- In step 4, every `⟦…⟧` token is removed from the sent text before its numbers are extracted. Without this, `⟦CARD_1⟧` lets the model claim `amount:"1"` (batch-91 C1).
- The DIGIT rule for `mention` uses `\p{N}`, not only `\p{Nd}`.
- Both validators get the change; new vectors: `"⟦CARD_1⟧ هحوش"` + amount 1 gives `AMOUNT_NOT_IN_TEXT`, and a mention with `½` is refused.
- Task **2.0**: T-330 + T-331 follow-up, one change to the vectors, C3, backend-engineer then parsing-engine-engineer, S.

### 2.1 Recommendation: (A) no model-written text at launch (NEEDS PO APPROVAL: reopens OQ-ASK-07 as OQ-ASK-10)
**Rationale.**
- **Safety and privacy:** Egyptian number words are an open set: teens «حداشر…تسعتاشر», duals «ألفين، ميتين», «ربعمية، تلتلاف», «مليون ونص», the `ال` prefix and chat-alphabet spellings. A block-list can't be complete, and even a perfect filter still lets a ≤ 200-character sentence in Zaghlol's voice say "call your bank now" or "more than usual" (FU-438). Under (A), injection can at most pick the wrong read-only plan.
- **UX:** the app templates already exist for every plan (T-344 needs them as the fallback). They are reviewed Egyptian copy with fixed goldens. Model Arabic drifts to MSA and varies between answers.
- **Cost and latency:** the output drops from about 120–200 to about 60–110 tokens. That saves only about $0.03 per 1 000 questions, but output tokens dominate latency (about 0.3–0.6 s less). The prompt loses about 300 tokens and still stays above the 1 024-token cache threshold.
- **Loss:** phrasing that echoes the question. Mitigation: 2–3 ARB variants per plan, picked deterministically from `requestId`.

**Exact changes if approved.**
- **SRS:**
  - FR-LLM-05: the reply is `{plan, params}`; the optional template is gone.
  - FR-LLM-35: the template clause is replaced by "the model writes no user-visible text; every sentence is an app-owned template per plan".
  - BR-LLM-04: covers all plans.
  - The FR-LLM-35 acceptance row becomes "a reply with a non-null `t` shows the app template; the model text is never rendered".
  - OQ-ASK-07 is superseded by OQ-ASK-10.
- **Contract (non-breaking, stays `ask-plan/1`):**
  - The provider-facing structured-output schema drops `t`. A `ProviderSchema` view of the contract file has `t` removed; the contract file keeps `t` nullable so pinned phones still parse.
  - The backend always answers `t: null` and drops any `t` before validation. The phone ignores `t` even when it is non-null, and the filler never reads it.
  - New vector: a reply with `t` set, plan kept, `t` absent from the output.
  - `templateRules` stays in the vectors (dormant, for a later (B)).
- **Prompt:** `ask-plan-v2` (new id and hash): template rules and template parts of the 14 examples removed; `max_output_tokens` 300 → 200. Re-run the recorded eval (T-350) and the live eval (T-351).
- **Closes** FU-433 (the filler's number-word list is no longer needed: delete `templateTextRefusal` and the model-text path in `TemplateFiller`) and FU-438. FU-409 closes with 2.0.

**Tasks (if A).**

| # | Task | Class | Size |
|---|---|---|---|
| 2A-1 | Backend: provider schema without `t`, `t` forced null, prompt `ask-plan-v2`, max tokens 200, recordings refreshed (T-349/T-350 follow-up) | C3, backend-engineer | S |
| 2A-2 | Phone: filler ignores `t`, delete the model-text path and the number-word filter, ARB variants per plan (T-344 follow-up) | C2, flutter-core-engineer | S |
| 2A-3 | ARB variants (2–3 per data/what-if plan, ar Egyptian + en), copy review | C1/Docs, UX copy | S |
| 2A-4 | SRS and `ask-llm.md` §2.1/§2.3/§2.5 text, OQ-ASK-10 closed (after PO) | Docs | S |

### 2.2 Alternative (B): keep model text with a whitelist grammar (not recommended)
Both validators replace rule 6 with a **whitelist**:
- NFC; 1–160 characters; one line.
- Allowed code points:
  - ar: U+0621–U+063A, U+0641–U+064A, U+064B–U+0652 (marks), space, `، ؟ . ! :` and `-` (tatweel U+0640 not allowed);
  - en: `A–Z a–z`, space, `, . ? ! : ' -`;
  - plus the allowed `{blank}`s.
- Anything else is refused, including every `\p{N}`, `\p{Cf}`/`\p{Cc}`, emoji and `⟦⟧`.
- **NUMBER_WORD:** any whole word after `foldKey` that is in the bundled number-word list or matches stems (`ال`? + {واحد…عشر, حداشر…تسعتاشر, عشرين…تسعين, مية/ميت/مائة, ميتين, ربعمية…تسعمية, ألف/الاف/آلاف/تلتلاف…, ألفين, مليون/ملايين, مليار, نص/ربع/تلت} with dual/plural suffixes `ين/ات/ان`; en cardinals, ordinals, `half, quarter, dozen, couple, k, m, bn`) is refused.
- **CLAIM:** imperative or contact verbs (`كلم، اتصل، ابعت، حول، ادفع، اشتري؛ call, send, pay, buy, transfer, visit, contact`) are refused.
- Shared vectors carry about 60 cases per rule.
- Residual: misleading comparatives («أكتر من العادي») remain.
- Cost: T-330 + T-331 + T-344 follow-ups (C3 ×2, C2), about M in total, plus copy review of the stems list. It is still a block-list on claims.

## 3. FU-423: person names, category/budget/goal names and notes (FOR THE PO, OQ-ASK-11)

**What the phone knows.**
- `transactions.counterparty_value` with `counterparty_kind = 'person'`: payee names from InstaPay and wallet messages, often in Latin capitals.
- `split_participants.name`: typed by the user.
- Custom category, budget and goal names, and notes, are user text too.

**What can never be masked.**
- Names the phone has never seen.
- A different script or spelling from the stored one ("MONA ADEL" stored, «منى» typed).
- Nicknames and kinship words («ماما»، «أبو أحمد»).
- Single given names: they collide with ordinary words («أمل»، «نور»، «كريم»، «سعيد»), so the masker matches only the stored full name or its first two tokens, each ≥ 3 letters, whole-token and folded.
- Anything retyped from a note.

**Options.**

| | Design | Impact | Tasks |
|---|---|---|---|
| **P0** keep | Names go as typed; consent copy names it explicitly | copy only | 1 × C1 (ARB) |
| **P1** hold locally (recommended) | Masker gains kind `PERSON` (sources above). A question with a matched person is **not sent**: a local bubble «الأسئلة اللي فيها أسامي ناس بتفضل على موبايلك» plus a chip that opens the transactions search filtered by that counterparty. No quota is used, and there is no schema, prompt or executor change | masker `MaskHeldLocal(personChips)`, one UI state, 2 ARB strings, outgoing-inspection proof extended to person fixtures | masker + proof C4 M; UI C2 S; copy C1 S; SRS FR-LLM-09/18 + consent text Docs S |
| **P2** mask and answer | P1's masker sends `⟦PERSON_n⟧`. New plan `PL-TRANSFERS {period, ref: PERSON\|null, direction: out\|in}`; the `ref` pattern gains `PERSON`, allowed only in that plan; executor over transfers by counterparty, per currency; prompt `ask-plan-v2` + eval items; vectors | schema change (amend v1 before release or `ask-plan/2`), both validators, prompt, executor, eval | ≈ 6 tasks: 2 × C4 (masker, executor), 2 × C3 (validators/vectors, prompt + eval), C2 UI, Docs |

- **Category, budget and goal names, and notes, in all options:** not masked. Masking them would break `mention` resolution, and they are low-risk labels the user chose to type. The consent copy says they go as typed.
- **Consent copy (UX to finalise), P1** (append to `chatConsentSends`): ar «ولو سألت عن حد زغلول يعرفه من تحويلاتك أو تقسيماتك، السؤال مش هيتبعت خالص. أي أسامي تانية بتكتبها، أو أسامي فئات وميزانيات، بتتبعت زي ما هي.» / en "If you ask about someone Zaghlol knows from your transfers or splits, the question isn't sent at all. Other names you type, and category or budget names, go as typed." For P0, drop the first sentence and say "Names of people you type go as typed."

> **For the PO.** Today a typed person name goes to our server and the AI provider together with the fact that you send them money.
> - **Recommended: P1.** Known names never leave, it costs about 4 small tasks and nothing on the backend, and "how much did I send Mona" is answered by a one-tap local search instead of the helper.
> - **P2** answers such questions through the helper but costs about 6 tasks and a schema change.
> - **P0** is free but only discloses the leak.
> - Under every option, names the phone has never seen, and category, budget and goal names, are sent as typed, and the consent copy says so.
