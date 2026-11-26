# Batch review: batch 97 (`batch/2026-11-27-97`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security, one pass) |
| Date | 2026-11-27 |
| Diff | `git diff aed433b4...4f9bb2d4`. aed433b4 is the remote tip of batch 96 (`git ls-remote`). 4f9bb2d4 is the remote tip of batch 97 |
| Tasks | T-353 (C4 backend), T-366 (C2 backend), T-367 (C3 app), T-368 (C3 both validators), T-361 (C2 UI), T-362 (C2 UI) + assembly commit 4f9bb2d4 |
| Verdicts | T-353 **CHANGES_REQUESTED** (1 major, before `llm_categorise` goes on) · T-366 APPROVED · T-367 APPROVED · T-368 APPROVED · T-361 APPROVED · T-362 APPROVED · assembly APPROVED |

## Checks run (cloud workspace)
- **Backend:** `Zaghlol.Application.Tests` 1523 passed. Contract tests filtered to `AskPlan|ConfigSpec`: 13 passed, including the shared plan vectors on the reference implementation. `PlanValidator` tests: 178 passed. The other contract tests and the Api/Infrastructure tests need Docker, so they did not run here (store, retention, endpoint and config-switch tests). The Lead reports T-353 and T-366 green on backend-ci.
- **Parsing package:** `dart test test/chat/llm/`: 305 passed (Dart runner of the shared vectors).
- **App:** `flutter analyze` on the 38 changed Dart files: no issues. `dart format`: 0 changed. `flutter test` on `core/llm`, `core/config`, `features/ask/application`, `features/categorization`, `features/catalog_sync`, `features/settings` and `features/transactions`: every test passes except the 12 new goldens of T-361/T-362, which have no PNGs yet (CI is regenerating them; not judged).

---

## T-353: categorise feedback intake through sync. **CHANGES_REQUESTED**

| AC / focus | Result | Evidence |
|---|---|---|
| 1 Right → confirmation, Wrong → correction, `custom` literal | PASS | `CategoriseFeedbackIntake.Prepare` and `SyncStore` `ConfirmationsSql` / `CorrectionsSql`. Only a system code or `custom` reaches `user_category`. |
| 2 Flag off → 0; items dropped one by one | PASS | `SyncService.cs` `feedbackOn` reads the install's own evaluated flag. Each item is filtered, code-checked and de-duplicated on its own. The cap is 50 in both the API and `Prepare`. |
| 3 Three installs delete the cache row, two do not | PASS (logic) | `ContradictionSql` with threshold 3. Rejected corrections are excluded. The unique key `(merchant_norm, install_hash)` exists in migration `20261126090000`. |
| 4 / 5 Negative proofs | PASS (CI) | Dump and marker tests in `SyncStoreTests` / `SyncFeedbackEndpointTests`. Telemetry uses fixed tags only. No logger in the intake. |
| 6 Retention | PASS (CI) | `RetentionStore.cs`: confirmations at 365 d or once promoted/rejected. Corrections 90 d after `resolved_at` or 180 d after `created_at`, whichever comes first. Matches FR-LCAT-34. |
| Idempotent | PASS | Inserts happen inside the claim transaction with `ON CONFLICT DO NOTHING`. A lost claim writes nothing. |
| Advisory locks | PASS | One lock domain (`llmcat:`), taken in sorted order after the install-row claim. No other code path takes these locks. The cache upsert in `CategoriseService` takes no advisory lock, so no cycle is possible. |
| Stored per row | PASS | Matches the task file's list. `created_at` is cut to the UTC day. |

**Security part (C4).**
- No financial data and no identifiers are stored. The rows hold only the HMAC (`install_hash`), the merchant key, codes and the day. The merchant name never reaches logs, metrics or traces (negative proof 2).
- Gold is not involved.
- Independence is the weak point (M1).

- **B97-M1, major (security: cross-user cache integrity and the operator review queue; fix before the `llm_categorise` flag goes on).**
  - **Where:** `SyncService.cs` (`feedbackOn`), `SyncStore.cs` `ContradictionSql`.
  - **Issue:** "3 independent installs" is really 3 distinct `install_hash` values, and a new hash costs one call to `POST /v1/installs`. Registration needs no attestation, and its limit is 60 per hour per /24. Sync needs no attestation either. The flag is evaluated on the platform and app version the caller declares. A script with no app can therefore:
    1. register 3 installs and send one `wrong` each with `aiCategory` set to the cached category (the cached category is what any genuine user is served), which deletes any shared cache row in about 6 HTTP calls; or
    2. send 3 `right` items and push any name into the operator confirmation review.
  - **Impact:**
    - Deleted rows go back to the model and draw on the shared USD 10 cap.
    - The open corrections stay for 180 days. Every later sync of one of those installs repeats the delete, so the row can be kept out of the cache.
    - Together with FU-439 (below), a good row can be deleted and then re-seeded wrong through prompt injection by one attested install.
    - Reinstalling 3 times has the same effect, because a new install id gives a new hash.
  - **Required:** Before the flag goes on, accept (or at least count toward the contradiction delete and the T-354 confirmation count) only feedback from installs that have passed LLM attestation. For example, record `llm_attested_at` on the install row when the LLM gate verifies a proof, and in the intake drop feedback from installs that don't have it. This costs genuine users nothing, because every AI category they can judge came from `POST /v1/categorise`, which needs attestation. An alternative is that the contradiction marks the cache row `contested` for operator review instead of deleting it.
  - **Tests:** Add `SyncServiceTests.FeedbackFromAnInstallThatNeverAttestedIsIgnored` and a store test in which 3 unattested installs leave the cache row in place.
  - **Docs:** Update `llm-categorise.md` §4 "Accepted residuals".
- **B97-m1, minor (FU-439 stays OPEN; before the flag).** T-353 adds the contradiction delete, which was half of the B96-m1 requirement. The other half is missing: cache writes only from single-name batches, or only after two installs agree (`CategoriseService.cs` cache upsert is unchanged). The T-353 task file does not mention FU-439. Owner: the B97-M1 fix or T-364.
- **B97-m2, nit.** `Prepare` keeps separate `seenRight` / `seenWrong` sets, so one install can store both a confirmation and a correction for the same name in one call. This is harmless for the thresholds (one row per table), but a contradictory pair could be dropped. `Prepare` also trusts the API for `source`. The DB CHECK backs it, but a bad value would then fail the whole sync transaction instead of dropping one item. Consider checking `source` in `Prepare` too.

---

## T-366: provider id and display names in the signed config block. **APPROVED**

| AC / focus | Result | Evidence |
|---|---|---|
| 1 / 4 Effective id, the same one the gate uses | PASS | `ConfiguredLlmProviderIdentity.EffectiveId` (row, else `Llm:ActiveProvider`) is the only resolver. `RemoteConfigActiveLlmProviderId` (the gate, `LlmGateChain` step 3) delegates to it. |
| 2 Names from host config, startup check | PASS | `LlmProviderOptions.Name` (pattern check) and `LlmStartupCheck` throws when a name is missing. The `llm.provider_name.*` keys are removed. |
| 3 PUT refusal | PASS (logic) | `ConfiguredLlmProviderIds.IsKnown` requires both names and a key. |
| 5 A row switch moves the version | PASS | `llm.provider` is now `SentToApp`, so its row version counts toward the block version. |
| 6 Never an id without names | PASS | `ToAppBlock` drops the id when either name is missing. |

- The documented residual is acceptable: a switch only through the host fallback, or a names-only change, does not move the version. The 409 net together with the runbook covers it, and the app fails closed.
- **B97-m3, minor (FU-443, backend lane).** These refusals have no dedicated tests yet. Add:
  - `LlmStartupCheckTests.AProviderWithoutBothDisplayNamesStopsTheHost` (one case per missing name, in Production and in Testing);
  - `LlmProviderOptionsTests.ADisplayNameOutsideThePatternIsRefused` (newline, `@`, 65 characters);
  - `RemoteConfigAdminTests.PutLlmProviderRefusesAnIdWithoutNames` and `...WithoutAKey` (both `400`, store untouched);
  - `ConfiguredLlmProviderIdentityTests.NamesAreNullUnlessBothAreSet`.
- **B97-m4, minor.** `ConfiguredLlmProviderIds.IsKnown` ends with `?? true`. When no `ILlmApiKeyProvider` is registered, the key half of the check is skipped (fail open). The admin host also leaves `knownProviders` null (FU-430). Make it fail closed (`?? false`), or assert at startup that the key provider is present wherever the PUT is served.

---

## T-367: one terms provider from the synced config; 409 handling. **APPROVED**

| AC / focus | Result | Evidence |
|---|---|---|
| 1 / 2 One source | PASS | `llmProviderTermsProvider` reads only `remoteConfigProvider`. `askConsentTermsProvider` (`ask_wiring.dart`), `askLlmTermsProvider` and `llmCatTermsProvider` all derive from it. `AskConsentFlow.prompt(expect:)` refuses when the sheet's terms and the flow's terms differ (FU-431). |
| 3 Null terms | PASS | Empty or bad id, or a blank name → null. A stale config (14 d) gives defaults with no names → null (`remote_config_test` 'provider names go stale'). The UI checks `catFeatureOfferedProvider` and the senders check `terms()`. |
| 4 Provider switch → re-consent | PASS | The consent is stored as `{provider, v}`. A new id no longer matches the stored grant. The gate compares against the same effective id. |
| 5 409 never trusted | PASS | `LlmConsentRequired` has no `providerId` member. Ask calls `resyncConfig`, then sends only through `_ask`, which asks the user again and only when the synced terms differ. Otherwise it shows the paused copy, and a second 409 ends the loop. A malicious 409 can therefore cost one sync, but it cannot change the provider or cause a send. The forced sync is an ordinary `run(force: true)`: it carries no question and no categorise names. |
| Cursor | PASS | While reset, `version` reads 0. A block at the same version is then accepted, and `confirm` is ignored. |

- **B97-m5, minor (contradicts AC5 and the sender comment).** On a categorise 409, `LlmGatewayClient` calls `_consent.clear(categorise)`. In production, `llmConsentStoreProvider`'s `onCleared` then **empties the queue** (`llm_gateway_client.dart:426`). The sender test passes only because its `LlmConsentStore` has no `onCleared`. The impact is low, because the filler rebuilds the queue from transactions after consent. Either add a `clear(..., withdraw: false)` for the 409 path, or change the AC and the comment. Make the test use the real `onCleared` closure either way.

---

## T-368: placeholders stripped before amounts; `\p{N}` refused in mentions. **APPROVED**

- Both runners agree on every vector, including the 9 new ones: the .NET `PlanValidatorTests` and contract `AskPlanVectorTests` pass, and the Dart `plan_validator_test` (shared vectors) passes. The schema is unchanged.
- **False rejects:** placeholder tokens are ASCII `⟦KIND_n⟧` written by the masker, and each one becomes a single space, so a number outside a token still counts and two sides never join. The only new rejection is an amount that existed only inside a masked name (for example "CIB 2" masked to `⟦ACCOUNT_1⟧`), and rejecting that is correct, because the number belonged to the name. `\p{N}` in a mention only adds `Nl`/`No` (`½`, `①`, `Ⅻ`) to the earlier digit rule, and legitimate mentions do not carry these. Rating: no realistic false reject.
- `½` is declared at step 3, not step 1. That is fine: the schema pattern is pinned (it is the provider copy and the copy older phones hold), and the contract requires step-1 vectors to fail the schema file. The reason code set stays closed.
- Regexes are bounded (generated with a 200 ms timeout; linear on the phone).

---

## T-361: AI chip, ✓/✗ on the detail screen, picker, Undo. **APPROVED**

| AC / focus | Result | Evidence |
|---|---|---|
| Chip only on `ai` rows with a merchant | PASS | `isAiUnconfirmed`. Used by the row (`txn_row.dart`) and the detail screen. |
| ✓/✗/Undo reach the real service | PASS | `_ServiceActions` over `llmCatFeedbackProvider` (`confirm` / `correct` / `undo` with the receipt). The list and detail are invalidated after each action and after Undo. |
| Picker excludes the row's own category; cancel changes nothing | PASS | `c.id != categoryId`. `picked == null` returns before any call. |
| Strings, RTL, a11y | PASS | All strings come from ARB. Directional insets are used throughout. 48 dp targets are measured in `ai_feedback_test`. |

- **PO/UX question (not a defect):** the PO asked for "a small feedback control beside it". The row shows only the chip, and ✓/✗ are on the detail screen (and the queue item). Ask the PO whether ✓/✗ should also sit on the list row.
- **B97-m6, minor.** `_decide` swallows a failed `confirm`/`correct`/`undo` with no message, so the user gets no feedback at all. Show the generic error snackbar.
- **B97-m7, nit.** In the row's a11y label, `'. ${l.categorizationAiChipLabelA11y}'` builds part of the label from a hard-coded separator. Move it into the ARB string.

---

## T-362: discovery card, consent sheet, Settings row and counter, queue header. **APPROVED**

| AC / focus | Result | Evidence |
|---|---|---|
| Consent only on explicit Allow | PASS | `LlmCatConsentFlow.prompt` stores the grant only when the sheet returned `true`. Not now, a drag or Back stores nothing (test 'Not now on the sheet stores nothing and sends nothing'). |
| Allow kicks only the gated sender | PASS | `catSenderKickProvider` → `LlmCatSender.run`. That call checks `terms()`, its throttle and the filler, and the gateway re-checks consent, flag and attestation. |
| Flag off or terms null → hidden | PASS | `catFeatureOfferedProvider` controls the card, the queue header, the Settings row and the "server knows" bullet. |
| Switch off empties the queue | PASS | `store.clear` → `onCleared` → queue cleared (test 'allow, ... then off clears and empties the queue'). |
| Provider name (assembly) | PASS | `catProviderDisplayName` takes the name from T-367's terms in the UI language. |

- **B97-m8, minor (FR-LCAT-43).** `cat.card_shown` / `cat.card_last_shown` change only on "Not now". If the user ignores the card, it stays on Home on every visit indefinitely, which is not "at most once per 30 days". Count a showing when the card is first built in a session (or once per day), or ask the PO whether "dismissed" is the intended counter.
- **B97-m9, minor (a11y).** The queue header's passive row wraps an `InkWell` in `Semantics(button: true, excludeSemantics: true)` without `onTap`. The excluded child also loses its tap action, so TalkBack/VoiceOver may announce a button that does nothing. Pass `onTap` to `Semantics`, as `_FeedbackButton` does.
- **B97-m10, minor (process; T-361 and T-362).** The task files still say `Status: TODO` and have no AC→test map or self-check line. The tests exist (`ai_feedback_test`, `llm_cat_ui_test`, goldens), so add the maps in the batch PR.

---

## Assembly commit 4f9bb2d4. **APPROVED**

- `AskPlanRequest.attestation` is nullable in the regenerated model. The only constructor call site (`LlmGatewayClient` `build(LlmAttestation a)`) always passes a proof. `BackendClient.askPlan` throws a client bug on null before any I/O, and `proofOf` throws as well. No path sends an ask without a proof. The categorise request model is unchanged (attestation still required).
- On the server, `AskPlanRequest` still parses a missing `attestation` as `Proof = null`, which the verifier answers with `422 missing`. Unchanged.

## Non-negotiables (CLAUDE.md §2)
- No financial data leaves the phone. The new sync members are merchant key, verdict, codes and source, covered by the categorise consent.
- No `double` money is touched.
- No sensitive logging. The new UI strings come from ARB, and RTL is handled with directional insets.
- No new SDKs.

## Follow-ups (minors)
B97-m1 (keeps FU-439 open), m3 (FU-443 test names above), m4, m5, m6, m8, m9, m10. Nits: m2, m7.

## Fix round — backend (task/b97-fix-B)
- **B97-M1 fixed (no schema change).** `SyncStore.ClaimAsync` takes feedback only from an install with a categorise counter row (`used > 0`) in the current or previous Cairo month; unattested items are dropped silently (accepted 0, no error). The contradiction delete counts only corrections created after the cache row's `created_at`, so the same three installs cannot delete a re-learned row again. Tests: `UnattestedInstallsCannotDeleteACacheRow`, `ThreeFakeConfirmationsFromUnattestedInstallsDoNotCount`, `OnlyAnAttestedCallInTheCurrentOrPreviousMonthWithUsedAboveZeroCounts`, `ARelearnedCacheRowIsNotDeletedAgainByTheCorrectionsThatDeletedItsPredecessor` (store), `FeedbackFromAnInstallThatNeverAttestedIsDroppedAndNotCounted` (endpoint).
- **Residual:** evidence is per install, not per merchant; an attested install can vote on merchants it never asked about, and three real attested devices still suffice. A correction made on the UTC day a cache row was written does not count against it. Follow-up FU-446: per-merchant evidence (needs a column or table).
- **B97-m1 / FU-439 fixed.** The pipeline sends all names of a request in one prompt, so the cache is written only when exactly one name was sent; a row is served only at `cat.cache_min_confidence`; the catalog is checked before the cache. Tests: `AnswersFromAPromptWithSeveralNamesAreNeverWrittenToTheSharedCache`, `OnlyAnAnswerAtTheCacheThresholdIsCached`, `ACachedRowBelowTheCurrentFloorIsNotServedAndGoesToTheModel`.
- **B97-m4 fixed:** `ConfiguredLlmProviderIds.IsKnown` fails closed without a key provider. **B97-m3 (FU-443):** `LlmProviderNameRefusalTests` (startup refusal per missing name in Production and Testing, pattern refusals, `NamesAreNullUnlessBothAreSet`, known-only-with-names-and-key, no-key-provider). The 400-at-the-endpoint variants were not added; the service-level refusal (`AnLlmProviderIdWithNoAdapterIsRefusedAndNeverWritten`) and `IsKnown` tests cover the logic.
- Local: build -warnaserror clean, format clean, Application tests 1526 passed. Postgres tests run in CI.
