# Batch review: batch 93 (`batch/2026-11-26-93`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security, one pass) |
| Date | 2026-11-26 |
| Diff | `git diff 48832e81...4ff8248a` (tip of batch 92, already reviewed, to the batch 93 merge of T-329) |
| Tasks | T-333 (C4 keys), T-336 (C4 attestation), T-340 (C4 app core/llm), T-342 (C3), T-329 (docs-only) |
| Verdicts | T-333 APPROVED · T-336 APPROVED · T-340 **CHANGES_REQUESTED** (one major, dev-only interop) · T-342 APPROVED · T-329 APPROVED |

## Checks run (cloud workspace)
- `dotnet build Zaghlol.sln -warnaserror`: clean. `dotnet format --verify-no-changes`: clean.
- Infrastructure `LlmApiKey|LlmAttestation`: 73 passed (includes the in-process OpenBao stub tests). Application `Llm`: 226 passed. Contract `LlmBinding`: 12 passed. Every other failure in the Infrastructure and Contract runs (`LlmTablesTests`, `LlmQuotaRepositoryTests`, the live contract tests) is `DockerUnavailableException`. None of them is in this batch's diff.
- App: `flutter pub get --enforce-lockfile` ok; `flutter analyze`: no issues; `flutter test test/core/llm test/core/backend test/privacy test/features/ask/application/plan_executor_test.dart`: 216 passed; `dart test packages/zaghlol_domain/test/ask`: 52 passed; `dart format --set-exit-if-changed` on `app/lib app/test packages/zaghlol_domain`: clean.

---

## T-333: LLM provider API keys from the KMS secret stores (C4, keys). **APPROVED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 each source loads; bad mode / missing / malformed refuses the start, source named, value not | PASS | `LlmKeyStartup.ReadFile/ReadHostSecrets/ReadOpenBaoAsync/ReadLocal`; `Refused()` builds its message from a constant reason, the source and the regex-checked id. `LlmApiKeyTests` AC1 group run green |
| 2 key in configuration refuses the start | PASS | `LlmKeyConfigurationScan.Check` runs first, before the "host has its own provider" early return; it scans every provider under `Llm`. See B93-m2 for gaps |
| 3 missing key pauses only that provider | PASS | Absent → `LogPaused`, not in the store. `OpenAiResponsesProvider.CompleteAsync` throws `LlmServicePausedException` before the circuit guard |
| 4 never in logs, traces, metrics, problem bodies, exceptions, `ToString` | PASS | `LlmSensitive<T>` writes `***` (JSON and `ToString`); `LlmApiKeyStore.ToString` is constant; log templates carry the id and source only; the random-marker sentinel test covers logs, `Activity`, metrics and exception text. Problem bodies: no endpoint yet (T-349) |
| 5 header only, never URL | PASS | `OpenAiResponsesProvider:72` `Authorization: Bearer`; WireMock test checks URL, query, body and the other headers |
| 6 runbook | PASS | `deployment.md` §3 "LLM provider keys" (formats, writing a key without printing it, start log line, rotation, leak order) |

**Security part.**
- *Custody (ADR-026):* `ReadHostSecrets` calls `HostSecretsKms.CheckCustody` and `CheckNoKeysInFiles` again, so a HostSecrets key outside Development/Testing needs `Kms:AcceptSharedHostCustody=true` even if the KMS check were bypassed. `Local` is refused outside Development/Testing (`LocalNotAllowedMessage`).
- *OpenBao least privilege:* the `zaghlol-api` policy gains only `read` on `zaghlol/data/llm/*`. It gets no `list`, no `metadata` and no write, and `setup.sh` never handles a key value. The transit mount can't be named `zaghlol`. KV 403 or unreachable → paused with a warning (by design note). A bad shape → refused.
- *Value hygiene:* buffers are pinned and zeroed. The key ends as a process-lifetime `string` (accepted residual, documented). Bearer keys are limited to `0x21..0x7E`, so header injection is impossible. Tests build keys from a random marker, and no secret-looking literals are in the tests.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| B93-m1 | minor | `backend/src/Zaghlol.Infrastructure/Llm/Keys/LlmKeyFormat.cs:37` | Provider id rule `^[a-z0-9][a-z0-9-]{0,39}$` is wider than the contract's `LlmConsent.provider` `^[a-z0-9][a-z0-9-]{1,31}$` (OpenAPI, mirrored by the app's `LlmConsentGrant.providerPattern`). A 1-character id or one of 33–40 characters loads a key, but no phone can ever consent to it, so the feature is silently dead. | Use the contract pattern (2–32 characters), or check it in `LlmStartupCheck`. Add one test. |
| B93-m2 | minor | `LlmKeyStartup.cs:275-307` | The configuration scan matches whole segments only (plus the `…apikey` suffix). `Llm:Providers:x:AuthToken`, `OpenAiKey` and `ApiSecret` pass. | Also match the suffixes `secret`, `token`, `password` and `credential(s)`. If `key` becomes a suffix rule too, exempt `Llm:Attestation:DevProofKey` explicitly: T-336 owns it, and it is refused outside Development/Testing anyway. |
| B93-n1 | nit | `backend/deploy/openbao/setup.sh:202` | An existing `zaghlol/` mount of another type or KV v1 passes the name-only check. Reads then 404, and every provider is paused with only a warning. | Check `type`/`options.version` in the JSON and `die` if it differs. |

---

## T-336: attestation for the LLM endpoints (C4, attestation crypto). **APPROVED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 vectors byte-exact (ask, cat) | PASS | `LlmBindingProductionTests` (12 green). JCS: members sorted ordinal (UTF-16, as RFC 8785), lowercase `\u00xx`, integers only within ±2^53, lone surrogates → no hash |
| 2 valid pass; missing / stale / replayed / wrong-body / wrong-install refused (Enforce), counted and passed (ReportOnly) | PASS | `LlmAttestationVerifier.VerifyAsync` verdict switch; `EveryInvalidProofIsRefusedInEnforceAndCountedButPassedInReportOnly` green |
| 3 Production unconfigured → 503 | PASS | `VerifyStoreAsync` checks readiness before the proof; `WithUnconfiguredVerifiersEveryRequestIsUnavailable` |
| 4 mode guard (neg. proof 1) | PASS | `LlmAttestationSettings.Resolve`; `LlmAttestationStartupCheck` |
| 5 any byte change / reuse refused (neg. proof 2) | PASS | `AProofForOneBodyIsRefusedWhenAnyByteOfTheBodyChanges`, `AValidProofUsedTwiceIsRefusedTheSecondTime` |
| 6 fixed codes only | PASS | `LogNotVerified` and the metric take tags from fixed sets, with `other` as the fallback; proof records override `ToString`; tokens are `Sensitive<string>` |

**Security part (focus 2).**
- *Another body:* `bodyHash` covers the JCS of the whole body except the top-level `attestation`. Play `requestHash` = that hash, and App Attest `clientDataHash` = SHA-256 of the clientData prefix ‖ 0 ‖ bodyHash. Any change fails.
- *Another install:* the install ID is inside `bodyHash`.
- *ask ↔ cat:* both the body prefix (`zaghlol-ask-v1` / `zaghlol-cat-v1`) and the clientData prefix differ, so a proof can't cross.
- *Stale:* Play has the 5-minute freshness and the `replay_guard` row. App Attest has the counter but no time bound (Apple's design; accepted residual, documented).
- *Mode:* read once from `IConfiguration` into a singleton. Fake is allowed only in Development/Testing, ReportOnly only in Staging, and `DevProofKey` only in Development/Testing. Any other environment name can only run Enforce, and "Production" is forced to Enforce. The Production startup check also rejects substituted verifiers. No remote-config or flag dependency exists (test sets every key).
- *503-before-proof:* returns `not_configured` with no proof parsing and no echo. ReportOnly never answers 503.
- *App Attest:* registration and assertion run in one transaction that commits only when verified.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| B93-n2 | nit | `backend/src/Zaghlol.Infrastructure/Llm/Attestation/LlmAttestationServiceCollectionExtensions.cs:48` | `PlaceholderTeamId = "TESTTEAM00"` duplicates the literal in `AttestationOptions.cs:100`. If one changes, iOS readiness becomes true on the placeholder. That still fails closed (Enforce refuses), but the result is 422 where it should be 503. | Reference one shared constant. |

The dev-proof key encoding problem across T-336 and T-340 is filed under T-340 (B93-M1).

---

## T-340: app `core/llm`: consent and quota stores, binding, gateway client (C4). **CHANGES_REQUESTED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 vectors (ask, cat) in Dart | PASS | `llm_attestation_test.dart` "AC1 binding vectors" green; reuses the restore `jcs.dart` and the strict parser |
| 2 dev proof unreachable in release, no key bundled | PASS | `llmDevKeyDefine = kReleaseMode ? '' : …`; `DevLlmProver` throws outside debug; `BackendClient._checkLlmProof` refuses `dev` under `dart.vm.product`. See B93-n3 for profile builds |
| 3 error table, 12 s timeout, cancel | PASS | `_mapFailure`; fake-clock timeout test; `transport_abort_test.dart` (real `HttpClientRequest.abort`) |
| 4 no body logging | PASS | No logger in `core/llm`; the marker test covers `print`, `debugPrint`, diag rows and `toString` |
| 5 stores encrypted, wiped, provider/version change → consent | PASS | `settings` table of the SQLCipher DB (`ask.`/`cat.llm_consent`, `llm_quota`, `llm_paused_until_sync`), so they go with the DB on "Delete everything"; `needsConsent` fails closed on bad terms or bad text |

**Security / privacy part (focus 3 and 4).**
- *Gate:* `_gate` runs before any I/O, install registration or attestation: flag (`FeatureFlagsState.isOn` = fresh && on) → not paused → consent covers provider+v → local quota not exhausted. An unknown quota (before first contact) passes, as the spec says. "Negative proof 3" is green.
- *Bodies:* ask sends `{planVersion, requestId, q = MaskResult.sentText, lang, consent, attestation}`. The gateway takes a `MaskResult`, never raw text. Categorise sends `{v, requestId, lang, merchants, consent, attestation}`. Both come from generated DTOs. The body is hashed with a placeholder proof and re-hashed after the real proof (must match). `BackendClient` adds the proof-type ↔ platform check.
- *Persistence and logging:* nothing persists or logs `q`. Abort races the transport and also calls `req.abort()`. A late reply after Stop or timeout is dropped with no store side effects (`live` check).
- *Privacy allow-list review* (`br_sync_03.dart`, `data_boundary_client_test.dart`). The new classes `llmQuestion` (`q`, `lang`, ask only) and `llmMerchants` (`merchants[]` ≤ 20, `lang`, categorise only) match D-90/D-96 and FR-LLM-02/FR-LCAT-02. The relaxed attestation assertion now allows exactly restore + the two LLM ops, with the platform's own type only (`attested` set), which matches FR-LLM-14. Install-scoped headers and the optional account token on the LLM ops are listed in FR-LLM-02/FR-LCAT-02. **Not listed in the SRS:** `requestId`, `planVersion`/`v` and `consent{provider,v}` (B93-m3).

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| B93-M1 | **major** | `app/lib/core/llm/llm_attestation.dart:181` vs `backend/src/Zaghlol.Application/Llm/Attestation/LlmAttestationMode.cs:98`; `docs/03-technical/ask-llm.md:199` | **The dev proof key differs between app and server.** The app uses the UTF-8 bytes of the `--dart-define` string as the HMAC key, and accepts any length (its test uses the 17-byte `'synthetic-dev-key'`). The server base64-decodes `Llm:Attestation:DevProofKey` and requires ≥ 32 bytes. HMAC, input (`bodyHash`) and output encoding (unpadded base64url, 43 chars) agree. Setting the same value on both sides gives different keys, so every debug-build request is refused in Fake mode (422). Each side tests only against itself, so no test catches it. Dev/test only, with no release or security impact, but it blocks the stage-0 end-to-end path the spec defines. | The app treats `ZAGHLOL_LLM_DEV_KEY` as base64 (same alphabet as the server), decodes it, and throws `StateError` under 32 bytes. Document "base64, ≥ 32 bytes, same value as `Llm:Attestation:DevProofKey`" in ask-llm.md §5. Add one shared vector (key, bodyHash, proof) checked by both `llm_attestation_test.dart` and `LlmAttestationVerifierTests`. |
| B93-m3 | minor | `docs/01-requirements/ask-llm.md:31` (FR-LLM-02), `docs/01-requirements/llm-categorise.md:21` (FR-LCAT-02) | FR-LLM-02 says "carrying only" and lists the question, language, app version, platform, install ID, account token and attestation. The request also carries `requestId` (random ULID), `planVersion`/`v` and `consent{provider, v}` (the backend's own provider id + sheet version). These hold no user data, and the tech spec and OpenAPI define them, but the SRS list is closed and the allow-list classes them as `protocol`/`versions` without an SRS row. | Requirements-analyst adds a line to FR-LLM-02/FR-LCAT-02: "plus protocol fields: request ID, schema version, the consent terms". No code change. |
| B93-m4 | minor | `app/test/privacy/support/br_sync_03.dart` (`llmQuestion(null)`, `llmMerchants(null)`) | "What Zaghlol's server knows" has no row for the question text or merchant names (`disclosedAs: null`), even though copy rows `privacy_server_itemAskLlm`/`itemLlmCat` exist. The builder already reported this. | Follow-up for T-345/T-358/T-362: map both classes to their privacy rows when the screens land. |
| B93-n3 | nit | `app/lib/core/llm/llm_attestation.dart:171` | `kReleaseMode ? '' : String.fromEnvironment(…)` keeps a defined key in **profile** builds. It can't be used there (the selector and the prover require debug), but it is bundled. | Use `kDebugMode ? String.fromEnvironment(…) : ''`. |
| B93-n4 | nit | `app/lib/core/llm/llm_gateway_client.dart:272` | `stop.whenAborted.then(...)` stays attached forever when the caller's Stop signal is reused and never fires. | Acceptable for one-shot signals. Note it in the `stop` doc comment. |

Also open: `LlmQuotaStore.resumeAll()` is not yet called after a successful sync (builder follow-up (a), owner T-343). Until then a `LLM_SERVICE_PAUSED` pause is permanent on the phone. This must land with T-343 before `ask_llm` can be turned on.

---

## T-342: plan executor, read-only, per currency (C3). **APPROVED**

| AC | Result | Evidence |
|----|--------|----------|
| 1 fixture figures | PASS | "AC1 fixture figures" green (+200.00 / 625 bp with USD separate, 661.29, 4,500.00, CARD_1 only) |
| 2 mention not found → chips; missing placeholder → fallback | PASS | `_target` (`map[ref] == null` → `missingPlaceholder`; unmatched mention → `x.notFound()`) |
| 3 EC-24 | PASS | `_safeSpend` adds no figure without a budget |
| 4 no cross-currency sum | PASS | Every loop is per `Currency` with `ChartFilter(currency: c)`. `_balance` keys sums by currency (and by account when named). Bills and suggestions are per currency |
| 5 no `double`, half-even once | PASS | static test green; `mulDiv(…, halfEven)` / `mulDivRound` integer only |

**Read-only and scope:** the new `ChartRepository` queries are `SELECT`s only, and the executor has no network, no logger and no write. Filters come only from the validated plan: `slug` → `sys:<slug>` from the closed catalogue (validator), `ref` → the in-memory mask map only, `currency` → `Currency.tryOf`, so a plan can't read outside those. `InvestThresholds` now rejects non-EGP `minEgp` (FU-407), and the what-if base ≤ 0 → `NotEnoughData` (FU-401).

**Mention via `parseAskQuestion('صرفت كام على <mention>')` (focus 5):** this is safe. The mention is already a substring of the user's own sent text (`PlanValidator` rule 3). Only the parser's id slots are used (category, merchant, account). Period or other slots are ignored. No match or an ambiguous match gives `notFound`, never a guess. It is correct for the tested Arabic cases. Two edge cases remain untested (B93-m5).

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| B93-m5 | minor | `app/lib/features/ask/application/plan_executor.dart:201-226`; `test/.../plan_executor_test.dart:222-240` | Only Arabic mentions are tested. Untested: (a) an English mention inside the Arabic frame (`صرفت كام على Uber`) on an `en` question; (b) a merchant name that contains a category word (e.g. «بيت الأكل»), where the `categoryId` checked first could win over the merchant; (c) a mention that is itself a period word. | Add the three tests. If (b) resolves to the category, check the merchant before the category when both match, or return `notFound` on a tie. |
| B93-n5 | nit | `plan_executor.dart:220` | The executor still maps an account mention to `LlmTarget.accounts`, although the validator already refuses account/card/bank mentions. That is harmless (the user's own data), but the path is dead. | Add a comment, or treat it as `notFound` to match the validator. |

---

## T-329: copy deck §4.12 automatic category (docs-only). **APPROVED**

Voice: Egyptian colloquial throughout («يلا يخمّن», «مش دلوقتي», «ولا يهمك، مبعتّش حاجة»). No emoji on the consent, quota or error lines. It never says "no server": the consent names Zaghlol's server and `{aiProvider}`. Plurals have the `=0` cases where the line can show 0, and the no-zero rows are registered. The two length warnings (`privacy_llmCat_turnedOff`, `privacy_server_itemLlmCat`) are a snackbar and a list row; they are acceptable, but check them in the T-358/T-362 goldens. Consent accuracy against FR-LCAT-02/05/12/31: what is sent (shop name + language to the provider; app version, platform, install ID, attestation to the server) and what is never sent (amounts, balances, dates, banks, cards, message text, transfers, people's names, custom category names) is right, with two small inaccuracies below.

| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| B93-m6 | minor | `docs/02-design/copy-deck.md:3232` | `categorization_aiConsent_sendsMore` leaves out "your sign-in token, if you're signed in", which FR-LCAT-02 lists (quota per account). | Add «ولو داخل بحسابك، علامة حسابك» / "and your account sign-in, if you're signed in" (wording to legal with OQ-LCAT-08). |
| B93-m7 | minor | `copy-deck.md:3235`, `:3268` | "without anything that identifies you" (`من غير أي حاجة تدل عليك`) overstates FR-LCAT-31. The server keeps a keyed install hash per vote: not reversible and not joined, but pseudonymous rather than anonymous. | Use "without your app ID or account" («من غير رقم التطبيق أو حسابك»). Put this on the legal sign-off list (OQ-LCAT-08). |

---

## Notes for the Lead
- Fix round: only **B93-M1** (T-340, about 10 lines of app code + docs + one shared vector). It is a dev-only interop major, not money, security, privacy or data. Under SPRINT rules it may instead become a follow-up owned by T-349 (the first task that exercises Fake mode end to end). If deferred, T-340 can move to APPROVED with the FU recorded.
- Minors B93-m1…m7 and nits B93-n1…n5 → `FU-###`. B93-m3 and B93-m7 belong with the PO/legal items already open (D-90/D-96 text in BR-SYNC-03, OQ-LCAT-08).
- `resumeAll()` after sync (T-343) is a release blocker for `ask_llm` ON, not for this batch.
