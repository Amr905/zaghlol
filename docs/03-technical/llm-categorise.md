# Automatic category for unknown merchants: technical specification (LLM-CATEGORISE)

| | |
|---|---|
| Status | **DRAFT, awaiting PO approval** (Phase 3) |
| Date | 2026-11-26 |
| Requirements | `docs/01-requirements/llm-categorise.md` (D-94…D-96, approved as a whole 2026-11-26: 15/month Free, 150 Gold, separate counter; 3 confirmations from distinct installs → operator review; "independent" means distinct attested installs, see §5 "What the evidence means") |
| Shared pieces | [`ask-llm.md`](ask-llm.md): gateway and provider adapters (§3), quota table and Cairo month (§4.2), rate limits/spend cap/kill switch (§4.3), scrub rules (§4.4), remote config (§4.5–4.6), attestation (§5); [ADR-027](adr/ADR-027-ask-llm-gateway.md) |

## 1. Data flow

```
transaction saved ─► Categorizer: user rule > catalog > keyword > AI suggestion > needs classification
   └─ needs classification ─► Eligibility (pure, FR-LCAT-05) ─ no ─► stays as today (never queued)
                              └─ yes ─► llm_cat_queue (encrypted DB, cap 100 distinct, 60 days)
CatSender (app open, ≤ once/10 min while open, back-off ≤ 1/h after failure; flag + consent + quota snapshot + online)
   ─► POST /v1/categorise (≤ 20 merchants) ─► backend: auth · flag llm_categorise · spend cap · consent · buckets · attestation
        ─► ContributionPrivacy re-check ─► catalog lookup ─► answer cache ─► trim to quota ─► ILlmProvider (closed set)
        ─► validate ─► count applied ─► cache (conf ≥ threshold) ─► 200 per-merchant results
   ◄─ results ─► ai_merchant_suggestions ─► Recategorizer (needs-classification rows of that merchant only) ─► AI chip
Right / Wrong ─► local user rule ─► sync outbox ─► POST /v1/sync `llmCatFeedback` ─► llm_cat_confirmations / llm_cat_corrections
```

## 2. On-phone eligibility (`packages/zaghlol_parsing/lib/categorize/llm_eligibility.dart`, pure)

`LlmEligibility.check(CategorizeInput, merchantNorm) → Eligible | Ineligible(reason)`; reasons are an enum (never text). All must hold:
1. **Source:** the merchant field of a card / POS / online / wallet payment to a business, direction expense or refund. Not a
   counterparty field.
2. **Kind:** not a transfer (InstaPay, wallet P2P, bank transfer in/out, internal, `ownAccount`), not ATM/cash, not salary/income.
3. **No person counterparty** (`person` kind, T-075).
4. **No identifiers** after FR-PAR-04 folding: `hasPersonalDataMarks(text, minDigitRun: 6)` (existing outbound filter: `@`, `+digit`,
   digit runs across separators in any script) plus phone shapes (`01[0125]` + 8 digits, `+20`, any 8+ digit run), IBAN
   (`EG` + 27 digits, or 2 letters + 2 digits + ≥ 10 alphanumerics), e-mail, URL (`://`, `www.`, `label.tld`), handles (`@x`, `x@instapay`).
5. **Not person-like:** strip honorifics (أ، أستاذ، م، د، دكتور، حاج، حاجة، Mr, Mrs, Ms, Dr, Eng); if 1–4 tokens remain and every
   token is in the bundled given-name list (ar + en transliterations, ≥ 2 000, asset `assets/data/eg_given_names.txt`, folded)
   and **no business word** is present (صيدلية، مطعم، ماركت، سوبر ماركت، كافيه، معمل، عيادة، شركة، مكتبة، مخبز، pharmacy,
   restaurant, market, cafe, clinic, lab, store, bakery, co, ltd, llc…), it is ineligible.
6. **Length** 2…64 after normalisation (same as contributions) and **not tried before** (`ai_merchant_suggestions` row exists).

Tests: the SRS §8 FR-LCAT-05 table (ar + en) as a table-driven suite, plus Arabic-Indic digit IBANs/phones, digit runs split by
spaces/dashes, honorific + name («حاج سيد», "Dr Mona"), name + business word ("Dr Hany Clinic" eligible), single business-like
name («محمود» ineligible: accepted false negative), and a property test that no eligible output matches the server's
`ContributionPrivacy` rejection. The backend re-runs `ContributionPrivacy` and drops failures (status `rejected`, not counted).

## 3. Endpoint `POST /v1/categorise` (install token; `Zaghlol-Account` optional)

```json
// request (closed, ≤ 4 KB)
{ "v": 1, "requestId": "01JD…", "lang": "ar", "merchants": ["zawya coffee", "مكتبة النور"],
  "consent": { "provider": "openai-luna", "v": 1 }, "attestation": { … } }          // binding prefix "zaghlol-cat-v1", App Attest clientData prefix "zaghlol-cat-attest-v1" (ask-llm §5)
// 200
{ "serverTime": "…", "counted": 1,
  "results": [ { "merchant": "zawya coffee", "status": "ok", "category": "dining", "confidence": 88, "source": "llm" },
               { "merchant": "مكتبة النور", "status": "ok", "category": "education", "confidence": 90, "source": "cache" } ],
  "quota": { "limit": 15, "used": 4, "remaining": 11, "resetsAt": "2026-11-30T22:00:00Z" } }
```
`merchants`: 1…`cat.batch_max` (20) unique strings, 2…64 chars. `status` ∈ `ok · unknown · low_confidence · rejected · quota`.
Errors as ask-llm §4.1 (`LLM_CONSENT_REQUIRED`, `LLM_SERVICE_PAUSED`, `DEVICE_ATTESTATION_FAILED`, `RATE_LIMITED`,
`UPSTREAM_UNAVAILABLE`); quota is reported per merchant (`quota`), never as a 403, so catalog/cache hits still arrive at 0 left.

**Server order per merchant (request order):** (1) `ContributionPrivacy` → `rejected`. (2) **Catalog**: published catalog aliases,
exact then fuzzy with the FR-CAT-06 rules (existing catalog read model) → `ok/source:catalog`, free. (3) **Answer cache** hit
(not expired) → `ok/source:cache`, free, `hits+1`. (4) The rest is trimmed to `remaining` of the `cat` counter (install and account,
lower of the two); the overflow gets `quota` and stays queued on the phone. (5) One provider call for the remaining names.
(6) Validation: each result's index is in range and unique, `c` ∈ the live system top-level codes or `unknown`, `p` 0…100; anything
else → `unknown`. (7) `p < cat.min_confidence` (60) → `low_confidence`. (8) **Counted** = number of `ok/source:llm`; committed with
the ask-llm §4.2 statement (`used = used + n`, `last_request_hash` makes a retried batch free). (9) `ok/llm` with `p ≥ cat.cache_min_confidence`
(default 80) is upserted into the cache.

**As built (T-352; code `Zaghlol.Application/Llm/Categorise/`, endpoint `CategoriseEndpoints`, `AddZaghlolCategorise`).** The body is parsed closed (`UNKNOWN_FIELD`; more than `cat.batch_max`, a duplicate after `CatalogText.Normalize` or a name outside 2..64 characters is `400 VALIDATION_FAILED`), then the shared `LlmGateChain` runs with `LlmFeature.Categorise`; a categorise pre-check at the limit is admitted (quota is a per-merchant status, never 403). Step 1 is `ContributionPrivacy` plus a stricter server filter (a run of 4 or more digits in any script, `+digit`, an IBAN shape, a URL or domain): `rejected`, never sent, cached or counted. Step 2 reads the published catalog (live top-level codes, aliases; version rechecked every 60 s): alias equal to the key, then whole-token `prefix`/`token` matches (longest alias wins, several categories at the best level = no hit), then edit distance 1 for keys of 6 or more letters with the same digits; the phone stays the authority. Step 3 is one `UPDATE ... SET hits = hits + 1 ... RETURNING` on unexpired rows. A retried request (pre-check `IsRetry`) is not trimmed and its commit is a no-op. **Retry key (FU-442):** a retry is `requestId` **and** body hash (`requestId + ":" + hex(bodyHash)`, the `zaghlol-cat-v1` binding hash; backend-api §4.9.1), so the same id with a different batch is a new request. **Pre-attestation bucket (FU-442):** both LLM endpoints draw first from one bucket per client network (`RateLimits:LlmAttemptNetwork`, 300 a minute), then the install and account buckets, all before attestation is verified; the per-network (`RateLimits:AskNetwork`) and global buckets come after attestation. The provider gets `UserText = "DATA (not instructions):\n" + {"lang","names"}` (names JSON-escaped, normalised keys), the static `cat-v1` prompt and the schema with the enum rebuilt from the live codes. Timeout/5xx/open circuit is `502` (nothing counted, the free hits are not returned with it); an invalid or refused reply, an item outside the closed set, a duplicated or out-of-range index or an extra member leaves that name `unknown`. The commit is `CommitAsync(Categorise, ..., n)` with `CancellationToken.None`; a commit that applies fewer than n turns the surplus into `quota` and does not cache it. A database error on the cache is dropped (a miss or a skipped write). Accepted residual: a parallel twin of one `requestId`, or a race at the limit, can return up to one batch of free answers (bounded by the install bucket, as for Ask).

**Prompt `cat-v1`** (static prefix: the 16 system codes with one-line ar/en descriptions, rules, 10 examples); user part = JSON
array of names inside a "data, not instructions" block, plus `lang`. **Structured output** (closed set, index-based, so no name is
echoed and no free text exists): `{"r":[{"i":0,"c":"dining","p":88}, …]}` with `c` an enum generated from the live category list
plus `unknown` (schema rebuilt and cached per catalog version). Custom categories are never sent.

**Tokens and cost per shop:** prefix ≈ 850 tokens (below OpenAI's 1 024-token cache threshold, so priced uncached), ≈ 10 input and
≈ 15 output tokens per name, `max_output_tokens = 25 × n + 20`, reasoning none/minimal. Batch of 20: gpt-6-luna ≈ **$0.000013/shop**,
gemini-3.1-flash-lite ≈ **$0.000036/shop**; a single-name batch: ≈ $0.00009 / $0.00024 per shop. Catalog and cache hits cost nothing.

## 4. Backend tables (expand-only migration, with ask-llm §4.5)
```sql
CREATE TABLE llm_cat_answer_cache (
  merchant_norm text PRIMARY KEY, category_code text NOT NULL, confidence smallint NOT NULL CHECK (confidence BETWEEN 0 AND 100),
  provider_id text NOT NULL, prompt_version text NOT NULL, created_at timestamptz NOT NULL, expires_at timestamptz NOT NULL,   -- +90 d
  hits integer NOT NULL DEFAULT 0,
  CHECK (char_length(merchant_norm) BETWEEN 2 AND 64 AND merchant_norm !~ '([0-9٠-٩۰-۹０-９][[:space:].,/_،-]{0,3}){6,}' AND position('@' in merchant_norm) = 0));
CREATE TABLE llm_cat_confirmations (
  id uuid PRIMARY KEY, merchant_norm text NOT NULL, category_code text NOT NULL,
  source text NOT NULL CHECK (source IN ('llm','cache','catalog')), install_hash bytea NOT NULL, created_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'collecting' CHECK (status IN ('collecting','promoted','rejected')),
  UNIQUE (merchant_norm, install_hash), CHECK (<same merchant_norm backstop>));
CREATE TABLE llm_cat_corrections (                                            -- the PO's separate review table
  id uuid PRIMARY KEY, merchant_norm text NOT NULL, ai_category text NOT NULL, user_category text NOT NULL,   -- code or 'custom'
  source text NOT NULL CHECK (source IN ('llm','cache','catalog')), install_hash bytea NOT NULL, created_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','promoted','rejected','prompt_issue')),
  operator_id uuid, resolved_at timestamptz,
  UNIQUE (merchant_norm, install_hash), CHECK (<same merchant_norm backstop>));
```
No install ID, account, IP or app version in the last two; `install_hash` = the existing KMS-peppered HMAC of contribution intake
(counts distinct installs, not joinable to `installs`, never joined with the quota counter). Intake side effect: ≥ 3 distinct-install
corrections of a cached category (`ai_category` = cache row) delete that cache row (FR-LCAT-12). Retention purger (FR-LCAT-34; **as built** the purger covers confirmations and corrections, a read ignores an expired cache row and no job deletes it, `backend-schema.md` §4):
cache at `expires_at`; confirmations 365 days or when promoted/rejected; corrections 90 days after `resolved_at` or 180 days after
creation. Grants: `app_rw` insert/select (intake, endpoint), `ops_rw` select/update status, `worker_rw` delete.

## 5. Feedback through sync
`POST /v1/sync` request gains `llmCatFeedback` (≤ 50 per call, closed items):
`{ "merchantNorm": "zawya coffee", "verdict": "right"|"wrong", "aiCategory": "dining", "userCategory": "dining"|"education"|"custom", "source": "llm"|"cache"|"catalog" }`.
Accepted only while the install's flag is on; each item re-checked with `ContributionPrivacy` and the category codes; stored by
verdict; duplicates per (merchant, install_hash) keep the first; `accepted.llmCatFeedback` counts stored rows. The `llm_categorise`
consent covers it (OQ-LCAT-04); the D-16 contributions toggle is not consulted.

**As built (T-353; `Zaghlol.Application/Llm/Categorise/Feedback/CategoriseFeedbackIntake`, `SyncService`, `SyncStore`).** Items are looked at only while the install's own `llm_categorise` flag (evaluated for its platform and app version from the stored flag rows) is on; with the flag off the call stores nothing, the hasher is not called and `accepted.llmCatFeedback` is `0` (the member is absent when the request had no `llmCatFeedback`). At most 50 items are read (the API also answers `400` above 50). Each item is checked on its own and dropped silently (counted by `kind` = `llm_cat_confirmation` / `llm_cat_correction` and `result`, never echoed): (1) the name's `CatalogText.Normalize` key (the cache key, so the stored name is the one the cache uses) passes `CategoriseNameFilter` (the filter of `POST /v1/categorise`); (2) `aiCategory` is a live non-deleted system category code (never `custom`) and `userCategory` is one too or, on `wrong`, the literal `custom` (FU-410); `right` needs both equal, `wrong` needs them to differ; (3) one row per key and verdict in the call (the first wins). In the sync's claim transaction: the merchants of the corrections are locked (`pg_advisory_xact_lock` in sorted order, so two syncs correcting one name at once both see the other's row), `right` and `wrong` rows are inserted with `ON CONFLICT DO NOTHING` (the unique key `(merchant_norm, install_hash)` keeps the first, so a retry or a resend adds nothing), then every cache row of those merchants whose `category_code` equals the `ai_category` of at least 3 non-`rejected` corrections **created after the cache row's own `created_at`** is deleted (3 distinct installs by the unique key; one install can reach 1; a row re-learned after a delete is not deleted again by the corrections that deleted its predecessor, and a correction made on the UTC day the row was written does not count against it). **Attestation evidence (B97-M1):** the whole feedback block of a sync (both tables and the delete) is stored only when the install has an `llm_quota_counters` row (`feature='cat'`, `subject_kind='install'`, `used > 0`) for the current or previous Cairo month, which only an attested `POST /v1/categorise` that committed an answer creates; otherwise the items are dropped silently (accepted count 0, no error, nothing about the rule is revealed). The counter id is read in the claim transaction and is not stored with the feedback. **What the evidence means (FU-447):** an attestation (Play Integrity or App Attest) proves that a genuine app on a genuine phone made the request, not that the phone has one install ID: one phone reinstalled (or using a work profile, an app clone or a second user) gets a new install ID and a new counter, and each can make one counted call and vote. So **3 distinct `install_hash` values are three attested installs, not three people or three phones**; a single phone reinstalled three times can delete one cache row or push one name to operator review (about 15 minutes of manual work on one phone, rated Low). Accepted for launch because both outcomes are harmless by design: a deleted row is re-learned on the next request, and a name in the review queue is decided by an operator, never automatically. Per-merchant evidence (an install votes only on names it asked about) is FU-446, after launch. **Cache write guard (FU-439, B97-m1):** one provider call carries every name of a request, so an answer is written to the shared cache only when the prompt held exactly one name (a sibling name cannot steer it); a cached row is served only at `confidence >= cat.cache_min_confidence` (a raised floor retires weaker rows) and the catalog is always checked before the cache, so a cache row never overrides the catalog. A failure anywhere rolls back with the claim. **Stored per row:** confirmation = random id, `merchant_norm`, `category_code`, `source`, `install_hash`, `created_at`, `status` (`collecting`); correction = random id, `merchant_norm`, `ai_category`, `user_category` (a system code or `custom`; the custom name is never sent), `source`, `install_hash`, `created_at`, `status` (`open`). `install_hash` is the existing KMS-peppered HMAC of the install id (the same value as in `merchant_contributions`); `created_at` is cut to the UTC day (no time that could be matched to one sync). No install id, account, IP, app version or token is stored, and the intake itself does not join the rows to `installs`. Accepted residuals: the install hash is stable across tables, so the same install's contributions, confirmations and corrections can be joined to each other (not to the install) by anyone with database access; and a merchant name arrives in the same request as the install token (FU-412, PO wording open). "Independent" confirmations are counted as distinct `install_hash` values (T-354 reads `count(*)` per `(merchant_norm, category_code)`: the unique key makes it one per install per merchant); **Residual after B97-M1:** the evidence is per install, not per merchant, so an attested install can still vote on a merchant it never asked about; three real attested devices (each needing a passing store attestation and spent quota) are still needed to delete a row or reach 3 confirmations. Per-merchant evidence (the install asked about this merchant) needs a new column or table and is follow-up FU-446. Retention (`RetentionPurger` rules `llm_cat_confirmations`, `llm_cat_corrections`, on `worker_rw`): confirmations at 365 days or once `promoted` / `rejected`; corrections 90 days after `resolved_at` or 180 days after `created_at`.

## 6. Operator review (FR-LCAT-50, `catalog_editor`, every action audited)
- `POST /admin/v1/llm-cat/corrections/query` `{status?, limit, cursor}` → groups `(merchantNorm, aiCategory, userCategory, votes,
  firstSeen, lastSeen, status)`, open first, by votes. No per-install rows, no hashes.
- `POST /admin/v1/llm-cat/corrections/resolve` `{merchantNorm, aiCategory, userCategory, action: promote|reject|prompt_issue}`:
  promote upserts merchant + alias into the **draft** catalog through the existing catalog ops (normal publish follows); a
  `custom` user category can't be promoted (reject or prompt_issue only); `prompt_issue` exports the case to the eval set backlog.
- `POST /admin/v1/llm-cat/confirmed/query` → merchants with ≥ `cat.confirm_n` (3) distinct installs confirming the same category and
  no open correction ("AI-confirmed"); `…/confirmed/resolve` `{merchantNorm, category, action: promote|reject}`. Never automatic.
- `zaghlol-ops llmcat corrections list|promote|reject|prompt-issue` and `llmcat confirmed list|promote|reject`.

## 7. App
- **Drift migration** (encrypted DB): `ai_merchant_suggestions(merchant_norm PK, category_id, confidence, source, state ∈
  unconfirmed·confirmed·corrected·no_answer, created_at, decided_at)`; `llm_cat_queue(merchant_norm PK, txn_count, first_queued_at,
  last_seen_at, attempts, next_attempt_at)`; outbox kinds `llmCatConfirmation`/`llmCatCorrection`; `CategorySource.ai('ai')` for
  transactions. Export column `category_source` maps `ai` + unconfirmed → `ai_unconfirmed`.
- **Categorizer:** new tier after keyword: `aiSuggestionFor(merchantNorm)` (unconfirmed state only; confirmed/corrected are user
  rules already). The recategorizer applies a new suggestion only to that merchant's `needs classification` rows and to future
  ones; it never touches user-set, rule, catalog or keyword categories. A later catalog hit replaces an unconfirmed suggestion.
  "Needs classification" = live, not internal, not user-verified, `category_source = 'none'` and no category. Precedence
  (T-357): a user rule (incl. Right/Wrong), catalog, keyword or event category replaces an `ai` one (FU-408); `ai` replaces
  only "needs classification". A catalog hit that replaces an `ai` row drops the unconfirmed suggestion.
- **Queue and sender** (`features/categorization/application/llm_cat_sender.dart`): eligibility before queueing; cap 100 (oldest
  dropped), 60-day expiry; order most transactions then most recent; triggers at app open and ≤ once/10 min while open; back-off
  ≤ 1/h after failure; 0 remaining before `resetsAt` → nothing sent; at reset sent automatically; switch off empties the queue.
  `unknown`/`low_confidence`/`rejected` → state `no_answer` (never re-sent); `quota` → stays queued.
- **UI:** AI chip («اقتراح زغلول» / "Zaghlol's guess", icon + text) on row, details, queue, drill-down; ✓/✗ (48 dp, 8 dp apart) on
  details and queue; Right → user merchant rule + confirmation in outbox; Wrong → category picker → rule + correction (`custom`
  for custom categories); picker cancelled → unchanged; 5 s Undo removes rule and outbox row. Counter in Settings → Privacy and
  the queue header (`cat.llm_quota` snapshot). Discovery card when ≥ 3 distinct eligible uncategorised merchants, settings
  `cat.card_shown` (count ≤ 3), `cat.card_last_shown` (≥ 30 days), `cat.card_never`; passive row in the queue header while off.
- **Consent:** `cat.llm_consent` `{provider, v, at}` (encrypted), sheet text per FR-LCAT-44; Settings switch; cleared by "Delete everything". Terms (provider id and names) come from the sync `config` block exactly as for Ask (`ask-llm.md` §4.6, FU-425); on a 409 the sender clears this consent, keeps the queue, resets the config cursor, sends nothing and shows the passive re-consent row.
- **Flag:** `llm_categorise` (fail closed, 14-day staleness); off → no card, no request, existing chips and controls stay.

## 8. Tests and tasks
Tests: eligibility table (ar/en) and property test; sender scheduling, caps and trimming with a fake client; recategorizer only
touching needs-classification rows; widget tests ar+en for chip, controls, undo, card frequency; backend unit (order of lookups,
trimming, validation, counting, cache contradiction); integration with the fake provider (catalog hit free, cache hit free, batch
25 → 20 + 5, quota 2 of 5, ask counter unchanged); marker-name scrub test (absent from logs/traces/metrics, present only in cache
and feedback tables). **Negative proofs:** (1) captured `/v1/categorise` bodies over the fixture set contain no amount, last-4,
institution, date or SMS text and no ineligible name; (2) `llm_cat_confirmations`/`corrections` rows hold no install ID (schema +
data check); (3) a quota-0 batch makes no provider call.

| # | Task | Class | Agent | Depends | Size |
|---|---|---|---|---|---|
| L1 | Eligibility rule + tests (pure) | **C4** | parsing-engine-engineer | L2 | M |
| L2 | Egyptian given-name list asset (public-domain sources, OQ-LCAT-05) + business-word list | C1 | boilerplate-engineer | — | S |
| L3 | `POST /v1/categorise`: catalog → cache → quota trim → provider (closed set) → validate → count; cache table | **C4** | backend-engineer | A2–A4 | M |
| L4 | Feedback intake in sync, confirmations/corrections tables, retention, cache contradiction | C3 | backend-engineer | L3 | M |
| L5 | Operator review admin endpoints + `zaghlol-ops llmcat` commands, audit | C2 | backend-engineer | L4 | M |
| L6 | Drift migration, categorizer AI tier, recategorizer, outbox kinds, export column | **C4** (Opus: rewrites stored categories) | flutter-core-engineer | L1 | M |
| L7 | Queue + sender + quota snapshot + consent store | C3 | flutter-core-engineer | L6, P5 shared client | M |
| L8 | UI: AI chip, ✓/✗, picker, undo, discovery card, consent sheet, Settings row, counter; widget ar+en | C2 | flutter-ui-engineer | L7 | M |
| L9 | Docs: backend-api (§2, §4, admin §5), backend-schema, SRS BR-SYNC-03 (D-96), privacy policy rows | Docs | — | L3–L5 | S |
