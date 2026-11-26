# Batch review — batch 91 (`batch/2026-11-26-91`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security, one pass) |
| Date | 2026-11-26 |
| Diff | `git diff origin/batch/2026-11-26-90...33ad5383` (batch 90 already reviewed) |
| Tasks | T-330, T-332, T-331, T-327, T-356 |
| Verdicts | T-330 **CHANGES_REQUESTED** · T-332 **CHANGES_REQUESTED** · T-331 APPROVED · T-327 APPROVED · T-356 APPROVED |

## Checks run (cloud workspace)
- `dotnet build -warnaserror Zaghlol.sln`: 0 warnings, 0 errors.
- Application tests (`~Llm|~Plan|~Ask`): 191 passed. Infrastructure `.Llm.`: 48 passed. Contract `AskPlan|LlmBinding|LlmFixture`: 24 passed. Docker tests not run (no Docker).
- `packages/zaghlol_parsing` `test/chat/llm/`: 293 passed. `packages/zaghlol_domain` `test/ask/invest_test.dart`: 24 passed.
- App: `flutter analyze` clean; migration v6/v7, DAO, schema audit, app_database, backup_restore, export_import/*, delete_everything: 345 passed.
- **Differential run of the two plan validators** (harness outside the repo, both fed the same 166 inputs: the 87 shared plan vectors plus 79 edge cases; Dart validator given the vectors' registry aliases, no `MaskMap`, no primary currency). All 87 vectors agree. 13 edge cases differ (below, with the template rows).

---

## Cross-task: plan validators, backend (T-330) vs phone (T-331)

| Input | Backend | Phone | Note |
|---|---|---|---|
| duplicate JSON key in the plan | **throws `ArgumentException`, message contains the key text** | `SCHEMA_INVALID` | M1 |
| `ref` `"⟦CARD_1⟧\n"`, `currency` `"USD\n"` | accepted (.NET `$` matches before a final `\n`) | `SCHEMA_INVALID` | m1 |
| `currency:"CIB"` / `"NBE"` | `PLAIN_NAME` | accepted | m5 (scope of the plain-name check) |
| `target.currency` set inside PL-INVEST `source.whatIf` | accepted | `TARGET_CURRENCY_SET` | m2 |
| PL-BALANCE with PL-SPEND `p` and a ref not in the text | `REF_NOT_IN_TEXT` | `PLAN_MISMATCH` | n1 (outcome same) |
| `mention` of 21 emoji (42 UTF-16 units) | `SCHEMA_INVALID` | accepted | m6 (length unit) |
| template naming `cib` / `بنك مصر` | kept | `TEMPLATE_PLAIN_NAME` | m3 |
| template with `❤️` (U+FE0F) | `TEMPLATE_NOT_NFC` | kept | conservative backend, harmless |
| template with shadda+fatha out of canonical order | `TEMPLATE_NOT_NFC` | kept | m6 |
| template `𝐚.𝐜𝐨𝐦` (supplementary letters) | kept | `TEMPLATE_LINK` | .NET `\p{L}` is per UTF-16 unit; n2 |

**Plain-name scope (asked by the Lead).** ask-llm.md §2.4 step 2 says "no plain-text account/card/bank name in **any string**". T-330 checks every string of `p` but not `t.text`; T-331 checks `mention` and `t.text` but not the other strings of `p`. In `p` the only free-form strings are `mention` and `currency` (`^[A-Z]{3}$`, which "CIB", "NBE", "QNB" match), so the spec-correct scope is **every string of `p` plus `t.text`** (a hit in `t.text` drops the template only). Each side is missing half: m3 (backend) and m5 (phone). Neither gap lets data leave the phone or widens what the phone reads: the backend runs first and the phone re-checks templates.

**Containment properties (checked).** The plan is data only: closed `anyOf` of `P_*` objects, `additionalProperties:false` everywhere, slugs/instruments/kinds are enums, refs must appear verbatim in the sent text (phone also: in this question's `MaskMap`). No plan field names a destination, URL, table or column, so a plan can't make the phone send anything or read outside the catalogue. Blanks are a closed list per plan; `{`/`}` outside an allowed blank, `⟦`/`⟧`, `\p{Nd}` of any script, bidi controls (U+061C, U+200B–200F, U+202A–202E, U+2066–2069, U+2060, U+FEFF) and Cc are rejected on both sides. Placeholders are `⟦KIND_n⟧`, n 1–99 (`_0`, `_100` rejected; `_99` accepted).

### Contract finding (not charged to T-330/T-331: both implement FR-LLM-35 and the vectors exactly)

| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| C1 | **major (spec gap)** | `backend/tests/Zaghlol.Contract.Tests/vectors/ask-plan-v1.json` `templateRules.DIGIT`; ask-llm.md §2.3; FR-LLM-35 | A model template can still show a number the phone didn't compute: (a) number words pass both grammars (`"صرفت ألف جنيه على {target}"`, `"You spent twenty thousand on {target}"` are kept); (b) the DIGIT rule is `\p{Nd}` only, so `①`, `⒈`, `½`, `²`, `Ⅻ` (No/Nl) pass. Related, step 4: digits inside placeholders count as question numbers, so `"⟦CARD_1⟧ هحوش"` lets the model put `amount:"1"` (1–99 from any placeholder index) — both validators accept. Also accepted: invisible Cf characters that are not in the CONTROL list (U+00AD, U+180E, U+2063, U+FFF9, U+E0001, U+0600). | Architect/PO decision, then one contract change applied to both validators: DIGIT → `\p{N}`; a NUMBER_WORD rule reusing the bundled number words (whole words after `foldKey`); strip `⟦…⟧` before extracting numbers in step 4; CONTROL → all `\p{Cf}` (U+200C/D included). Add vectors for each. Track as an open question against FR-LLM-35; must land before the LLM feature ships (T-349/T-342 path), not before this merge. |

---

## T-330 — Backend plan validator and template grammar (C3)
**Verdict: CHANGES_REQUESTED** (M1)

### AC → evidence
| AC | Result | Evidence |
|---|---|---|
| 1 vectors | PASS | `PlanValidatorTests.Ac1_*` iterate the file (now 87 plans / 46 templates; the task's AC map still says 85/43, n3); differential run agrees on all 87. |
| 2 rejection classes | PASS | `Ac2_AndAc3_EachRejectionClass…` (16 classes). |
| 3 template failure keeps plan | PASS | same theory + `Ac3_StepOneToFive…`. |
| 4 never logs or throws with plan text | **FAIL** | M1. Logging itself is reason-code only (`LoggerMessage` with `PlanReason`). |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| M1 | **major** (privacy) | `backend/src/Zaghlol.Application/Llm/Plans/PlanValidator.cs:81` | `JsonNode.Parse` of a reply with a duplicate property throws `ArgumentException("An item with the same key has already been added. Key: <key>")`. `JsonDocument` (used by `OpenAiResponsesProvider.Parse`, `OpenAiResponsesProvider.cs:166`) accepts duplicates, so a model reply like `{"…question echo…":1,"…question echo…":2}` reaches the validator and the key text (model output, can echo the question) lands in an exception message, which the host's exception handler logs. Reproduced: message contains the marker key. Breaks AC4 and ask-llm §4.4. | Make `Validate` total: reject duplicate properties as `SchemaInvalid` (e.g. `JsonDocumentOptions { AllowDuplicateProperties = false }` / `JsonNodeOptions` on .NET 10, or catch around parsing and return `SchemaInvalid`), and add a test with a duplicate-key marker asserting no throw and nothing in the log sink. Belt and braces: the adapter should also parse the reply with duplicates disallowed (see m7). |
| m1 | minor | `PlanValidator.cs:84` (schema via JsonSchema.Net) | .NET regex `$` matches before a trailing `\n`, so `ref:"⟦CARD_1⟧\n"` and `currency:"USD\n"` pass the schema; the phone (Dart `$`) rejects them. A counted question then ends in a phone fallback. | Post-check in the validator that ref/currency/amount strings contain no `\n` (or compile patterns with `\z` semantics); add vectors. |
| m2 | minor | `PlanValidator.cs:204` | `TARGET_CURRENCY_SET` checks only top-level `p.target`, not the PL-WHATIF-CUT `p` nested in PL-INVEST `source.whatIf`; the phone rejects it. | Check every `target` object (as the Dart side does) and add a vector. |
| m3 | minor | `PlanValidator.cs:64,107` | Plain-name check covers the strings of `p` but not `t.text` (spec: any string). | Run the alias check on `t.text` too; a hit drops the template only (`TEMPLATE_PLAIN_NAME`, same code as the phone); add a vector. |
| n1 | nit | `PlanValidator.cs` step order vs `plan_validator.dart:144` | Dart checks `PLAN_MISMATCH` before step 2, backend at step 5; a plan failing both gives different codes (same outcome). | Align the order (Dart's is the safer one: typed parsing needs it) or note in §2.4a that only outcome, not code, must agree for multi-failure plans. |
| n2 | nit | `TemplateGrammar.cs` `LabelTldRegex` | `\p{L}` in .NET does not match supplementary-plane letters, so `𝐚.𝐜𝐨𝐦` passes the backend LINK rule (phone rejects). | Evaluate per `Rune`, as the other rules do. |
| n3 | nit | `docs/04-tasks/tasks/T-330.md` AC map | Vector counts out of date (85/43 → 87/46). | Update. |

---

## T-332 — LLM gateway core, `Sensitive<T>`, OpenAI adapter, fake, resilience (C4; security part included)
**Verdict: CHANGES_REQUESTED** (M2)

### AC → evidence
| AC | Result | Evidence |
|---|---|---|
| 1 request body | PASS | `TheRequestIsStatelessStrictAndCarriesNoIdentifier`; body built from model, prompt, user text, `store:false`, strict schema, `reasoning.effort:none`, `max_output_tokens` only; only extra header is the bearer key. |
| 2 outcome mapping | PASS | Ok / Refused / Invalid / Timeout / Upstream tests. |
| 3 breaker | PASS (see m8) | `LlmCallGuardTests` on a controlled clock. |
| 4 `Sensitive<T>` never reveals via ToString, System.Text.Json, logger, exceptions | **FAIL** | M2. |
| 5 fake outside Dev/Testing | PASS | `LlmStartupCheck` + test; https required outside Dev/Testing. |
| 6 config only, decimals | PASS | `LlmProviderOptions` (decimal prices; endpoint must have no userinfo/query). |

### Security part
- No secret-looking literals in the diff; the key comes from `ILlmApiKeyProvider` (T-333) and is only placed in the `Authorization` header. `RemoveAllLoggers()` on the named client, so the default HTTP logging handler can't log headers/URI. Exceptions created by the gateway carry constant messages.
- Timeouts: attempt 8 s (configurable), total 9 s, caller cancellation rethrown and not counted; one retry only for connect failures (`NameResolutionError`/`ConnectionError`/listed socket errors). Reply capped at 256 KB before buffering.
- Spend guard / ledger is not in this task (ledger and cap are later tasks); usage is mapped from `usage.input_tokens`, `input_tokens_details.cached_tokens`, `output_tokens`. These names are unverified until the live test T-351 — noted, not blocking.

### Findings
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| M2 | **major** (privacy, AC4) | `backend/src/Zaghlol.Domain/Sensitive.cs:39-46`; `LlmTypes.cs` (LlmCall/LlmResult) | The reused `Sensitive<T>` **writes the bare value** with System.Text.Json. Only the two members of `LlmCall`/`LlmResult` are redacted by attribute; any other holder of the question (T-349's request DTO `q`, a problem body, an anonymous object passed to a JSON logger) serialises it in clear. AC4 says no reveal through System.Text.Json; the Lead asked that it can't be serialised by accident. | Give the LLM path a type that redacts on write but still reads (e.g. `SensitiveText`/`LlmSensitive<T>` in `Zaghlol.Application/Llm`, or an opt-in redacting variant of the converter), use it for `LlmCall.UserText`, `LlmResult.Json` and document it as the type T-349 must use for `q`/`p`/`t`; test that `JsonSerializer.Serialize` of the bare wrapper and of an object containing it never contains the marker. Leave `InstallResponse`'s behaviour untouched. |
| m7 | minor | `OpenAiResponsesProvider.cs:166` | Reply JSON is accepted with duplicate properties (feeds M1). | Parse with duplicate properties disallowed → `Invalid`. |
| m8 | minor | `LlmCallGuard.cs:166` | Any call that finishes while the circuit is open/half-open is treated as the probe result: a slow call started before the circuit opened can close it early (success) or clear `probeInFlight` while the real probe runs, letting a second probe in. | Record only the probe's own result in half-open (pass `isProbe` to `Record`; ignore late non-probe results). Add a time-controlled test. |
| m9 | minor | `LlmCallGuard.cs:96-113` | Only `HttpRequestException` and `OperationCanceledException` are mapped. `HttpIOException`/`IOException` while reading the body (connection reset mid-response) escapes as an exception, is not counted by the breaker and surfaces to the caller as a 500. Messages are constant, so no leak. | Map `IOException` during the attempt to `Upstream` and record it as a failure. |

---

## T-331 — Dart plan types, phone validator, template grammar, number words (C3)
**Verdict: APPROVED**

### AC → evidence
| AC | Result | Evidence |
|---|---|---|
| 1 same outcome as backend on all vectors | PASS | `shared vectors` group; differential run: 87/87 agree. |
| 2 phone-only checks | PASS | `phone-only checks (AC2)`; `REF_NOT_IN_MAP` when a `MaskMap` is given. |
| 3 regen no diff | PASS | `generated constants` group. |
| 4 template rules ar/en | PASS | template vectors + table. |
| 5 pure Dart, no double | PASS | amounts compared as canonical decimal strings; validator never throws (catch-all → `SCHEMA_INVALID`), never logs; `toString`s redacted. |

### Findings (follow-ups)
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| m4 | minor | — | Merging the m1/m2/m3 fixes into T-330 needs matching vectors; the phone side already behaves as recommended for those. | Re-run the shared vectors after T-330's fix. |
| m5 | minor | `packages/zaghlol_parsing/lib/chat/llm/plan_validator.dart:165` | Plain-name check covers `mention` (and `t.text`) only; `currency:"CIB"` passes on the phone (backend rejects). Harmless today (filters on a non-existent currency) but differs from the spec's "any string". | Check every string of `p` (skip only enum-typed fields if ordinary-word aliases collide). |
| m6 | minor | `template_grammar.dart` `isLikelyNfc`; schema `mention` pattern | (a) NFC heuristic misses non-canonical Arabic mark order (U+0651 then U+064E) that the backend rejects; (b) `unicode:true` counts code points, the backend counts UTF-16 units, so `mention` length 1–40 differs for astral characters. Both only matter when the backend is bypassed. | (a) Port the backend's canonical-order check for U+064B–U+0652/U+0670; (b) pin "UTF-16 code units" in §2.4a and check `length` explicitly. |

---

## T-327 — Investment bands D-93 (C3/C4 money)
**Verdict: APPROVED**

| AC | Result | Evidence |
|---|---|---|
| 1 worked example | PASS | group "AC1 worked example". |
| 2 bands | PASS | `investBand`: `S ≤ 0` nothingSaved; EGP `S ≤ minEgp` small (saving line only, no rows); no 21K EGP price → goldUnknown (no stocks line, no gold line, USD/certificate kept); otherwise exact BigInt cross-multiplication `S_minor·100·10^expP` vs `cg·price_minor·10^expS`: `<` → stocks (gold dropped, `stocksInGeneral` flag only, no named product), `≥` → gold. Boundaries 100.00/100.01/999.99/1000.00 tested. |
| 3 non-EGP | PASS | never banded or converted; gold only for EGP/USD, else `NoPriceRow`. |
| 4 stale | PASS | > 24 h flagged, still used. |
| 5/6 negative proofs | PASS | no `double` in `lib/ask/`; `InvestInstrument` closed (gold, usd, certificate; index omitted per §3.4 until a feed exists). Wording is not in code (flag + typed rows; the app owns copy, BR-LLM-04). |

| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| m10 | minor | `packages/zaghlol_domain/lib/ask/invest_bands.dart:99` | `saved <= thresholds.minEgp` assumes `minEgp` is EGP; a remote-config value parsed in another currency would hit the Money cross-currency comparison. | Assert/construct `minEgp` as EGP in `InvestThresholds` (or compare minor units after checking the currency). |
| n4 | nit | `docs/04-tasks/tasks/T-327.md:43` | "AC -> test map" heading duplicated. | Remove one. |

---

## T-356 — Drift schema v7, DAOs, export `category_source` (C4 data; security part included)
**Verdict: APPROVED**

### AC → evidence
| AC | Result | Evidence |
|---|---|---|
| 1 migration on populated DB, new tables usable | PASS | `migration_v7_test.dart` "AC1/AC2 … (background/foreground)"; both DAOs used after the upgrade. |
| 2 NP1 byte-identical rows | PASS | every v6 sample table compared as rowid + `quote()` per column, incl. `transactions` (with a rowid gap), `merchant_rules`, `outbox` (one row per v6 kind), `transactions_fts_src`. |
| 3 NP2 v6 backup restore | PASS | `backup_restore_test.dart` "AC3 (T-356)…". |
| 4 export mapping | PASS | `ai`+confirmed → `user_rule`; unconfirmed / corrected / no row / unknown → `ai_unconfirmed`; others unchanged. |
| 5 delete everything | PASS | `delete_everything_test.dart` "T-356 AC5…". |

### Data-safety review (focus 1)
- **Rows / rowid:** both rebuilds copy `rowid` + every v6 column by name, compare counts before the drop; a test ties the column lists to v6 and v7.
- **FTS:** `transactions_fts_src` and the FTS5 index are not touched; `DROP TABLE` runs with foreign keys off, so no implicit delete and no `trg_txn_fts_ad`. Test finds an old row by `MATCH` and indexes a new insert through the re-created `trg_txn_fts_ai`.
- **Triggers / view / indexes:** the two `offset_links` triggers and `transactions_fts_row` are dropped before and re-created after; the four triggers on `transactions` and the six + one indexes re-created from the v7 dump. Tests derive these lists from the v6/v7 dumps, and the migrated schema equals both the fresh v7 schema and the dump; `foreign_key_check` and `integrity_check` clean; offset triggers still abort.
- **Idempotent on retry:** any failing statement (stray `ai_merchant_suggestions`, `transactions__v7`, or `outbox__v7` after `transactions` was rebuilt) → `DB_MIGRATION_FAILED(restored)` with a byte-identical v6 file; reopen of a migrated file is a plain open.
- **Backup / delete:** both new tables are in `backedUpTables`; LLM outbox kinds stay device-only like all outbox rows; delete-everything removes the whole file.
- **Export/import after the merge (33ad5383):** header is 17 columns (`pair`, `kind`, `category_source` last), preview indices unchanged; the importer accepts exactly the 14/16/17-column headers by name and never stores `pair`/`kind`/`category_source`. Tests cover all three widths and the combined round trip.
- **Privacy:** no logging in the DAOs or the port; `merchant_norm` CHECK keeps the key to `[a-z0-9 ]` 2–64; nothing here sends data.

### Findings (follow-ups)
| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| m11 | minor | `app/lib/core/db/daos/merchant_rules_dao.dart:88`, `recategorizer.dart` | Rule application and the recategoriser list `('none','catalog','heuristic')` as replaceable, so a user rule (including the one created by Right/Wrong) won't touch `ai` rows; a `corrected` merchant's rows would keep exporting as `ai_unconfirmed`. No `ai` rows exist until T-357. | Owner T-357: add `ai` to the replaceable sources for user rules and confirm/correct, with a test. |
| n5 | nit | `app/lib/features/export_import/application/import_csv.dart:6` | Header comment says "`exportHeader` or the pre-T-356 header"; the code accepts 14/16/17. | Update the comment. |

---

## Follow-up rows for the Lead (minors and nits; FU numbers to assign)
| Label | Task / owner | Summary |
|---|---|---|
| B91-m1 | T-330 → T-349 | Trailing `\n` accepted by .NET `$` in ref/currency/amount patterns. |
| B91-m2 | T-330 | `TARGET_CURRENCY_SET` misses PL-INVEST nested what-if. |
| B91-m3 | T-330 | Plain-name check not applied to `t.text`. |
| B91-m4 | T-331 | Re-run shared vectors after T-330 fixes; add vectors for m1–m3. |
| B91-m5 | T-331 | Plain-name check not applied to `currency` (any string of `p`). |
| B91-m6 | T-331 | NFC mark-order gap; mention length unit (UTF-16 vs code points). |
| B91-m7 | T-332 | Adapter accepts duplicate JSON properties in the reply. |
| B91-m8 | T-332 | Breaker treats late non-probe results as the probe's. |
| B91-m9 | T-332 | `IOException` mid-body escapes the guard. |
| B91-m10 | T-327 | `minEgp` currency not enforced. |
| B91-m11 | T-357 | `ai` not replaceable by user rules / confirm-correct. |
| B91-n1…n5 | various | Reason-code order, LINK rule per rune, AC-map counts, duplicate heading, import comment. |
| B91-C1 | architect / PO | **Contract gap (major, before LLM launch):** number words, `\p{No}`/`\p{Nl}`, placeholder-index amounts, non-listed `\p{Cf}` in templates/plans. |

## Notes for the Lead
- Fix round: M1 (T-330) and M2 (T-332) are both small (a few lines plus one test each); the Lead delta check should suffice. M1's fix should come with m7 in the same pass if the fix agent touches the adapter.
- C1 is a spec decision, not a builder error; file it in `docs/01-requirements/open-questions.md` against FR-LLM-35 and block the LLM answer path (T-342/T-349) on it, not this batch.

## Fix round — backend
- **M1 (T-330):** `PlanValidator.Validate` wraps the plan check in a catch-all; any parse failure (duplicate keys, depth, anything) gives `SCHEMA_INVALID`, the exception is dropped and never logged. Tests `M1_*` (duplicate key at root, in `mention`, in `t`; default element; no plan text in the log).
- **m7 (T-332):** the OpenAI adapter parses the reply with `AllowDuplicateProperties = false`, so duplicates give `Invalid`. Test `AReplyWithDuplicatePropertiesIsInvalid`.
- **M2 (T-332):** new `Zaghlol.Application.Llm.LlmSensitive<T>` (ToString `***`, JSON writes `"***"`, still reads the bare value). Used for `LlmCall.UserText` and `LlmResult.Json`; T-349 must use it for `q`/`p`/`t`. `Domain.Sensitive<T>` is unchanged (the install token response needs the bare value). Tests `LlmSensitiveWrapperTests` (ToString, interpolation, STJ direct/nested/collection/dictionary/anonymous, `{@}` logger, exception).
- **Plain-name scope (m3):** validator checks `t.text` (a hit drops the template only, new `TEMPLATE_PLAIN_NAME`, same code as the phone). New vectors `invalid-plain-name-in-template-text` (expect `accept` plus new field `expect.templateReason: "TEMPLATE_PLAIN_NAME"`) and `invalid-plain-name-in-currency` (fallback, step 2, `PLAIN_NAME`). The contract reference now checks every string of `p`.
