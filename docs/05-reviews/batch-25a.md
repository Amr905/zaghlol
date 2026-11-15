# Batch 25 review (part a): T-135, T-167 + T-168, T-071 + T-072

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus), code and security in one pass |
| Date | 2026-11-15 |
| Diff | `origin/main...origin/task/T-135-accounts`, `...task/T-168-zakah-screen` (includes T-167), `...task/T-071-072`; merged tree `batch/2026-11-15-25` |
| Verdicts | T-135 **APPROVED** · T-167 **CHANGES_REQUESTED** · T-168 **CHANGES_REQUESTED** · T-071 **CHANGES_REQUESTED** · T-072 **APPROVED** |

Tests run (not read): backend Application/Infrastructure/Api tests filtered to accounts, Apple callback, ID token and sign-in (all non-Docker tests pass; the 26 + 14 failures are all `DockerUnavailableException` and need the GitHub run). `dart test test/zakah` in `zaghlol_domain` (41 pass). `flutter test test/features/zakah test/features/wealth test/features/accounts` (211 pass). `international_templates_test.dart` (8), `registry_lint` (8), `bundled_registry_e2e_test` (8) pass. I also ran a throwaway pipeline probe (deleted afterwards) for the Revolut, KWD and INR cases below.

---

## T-135 — Accounts: ID token sign-in, link, sign-out, delete, Android Apple callback (C4)

**Verdict: APPROVED** (no blocking finding; follow-ups below).

### Lead's known issue: lock order deadlock (attach uses PostgreSQL uuid order, restore uses .NET Guid order)

**Not real as stated.** The two orders are the same. Since .NET Core, `Guid.CompareTo` compares `_a` as `uint`, then `_b`, `_c` as `ushort`, then bytes `d…k` in order, which is the RFC byte order. PostgreSQL's `uuid_cmp` is `memcmp` over the same 16 bytes, and Npgsql maps them big-endian. I checked this on the repo's .NET 10 SDK: 200,000 random pairs, `Guid.CompareTo` against the ordinal compare of the `N` string, 0 mismatches. Edge cases with the high bit set in group 1 and group 4 sort the same way too. So `AttachSql … ORDER BY id FOR UPDATE` (`AccountStores.cs:63`), `ReadIdsAsync` `ids.Sort()` (`AccountStores.cs:148`) and `RestoreService` `.Order()` (`RestoreService.cs:126`) all lock in one order.

There is a smaller ordering gap (finding 1): it is not one global order, and PostgreSQL detects and resolves it. It does not block.

### Security and contract checks

- **ID token** (`IdTokenVerification.cs`): RS256 only. `jku`/`jwk`/`x5u`/`x5c` are never fetched. `kid` comes from the cached JWKS (Apple's issuer is pinned through discovery, refresh every 24 h, an unknown `kid` refreshes at most once per 5 min). The signature is checked before the claims. `iss` is exact, `aud` must be a single string in the configured list (an array is refused), `exp` allows 60 s skew, and `sub` must be non-empty. A missing key set gives 503, an unknown `kid` with keys present gives 422. Tests use `FakeOidcIssuer` and the network is never touched.
- **Nonce (R2-9)**: required for both providers. The constant-time compare is lowercase `hex(SHA-256(raw))`, which matches the app (`app/lib/features/account/application/nonce.dart`: Dart `crypto` digest `toString()` is lowercase hex; raw nonce is 32 base64url characters and matches `^[A-Za-z0-9_-]{22,128}$`). `iat` must be within 10 min (and at most 5 min in the future). `replay_guard` is committed on its own before the transaction (R3-5) and stores only the hash.
- **Account token**: `{sub, iid, iat, exp}` signed by the entitlement ring. The validator checks the `iid` equals the caller and the `account_installs` row still exists, so a deleted account or an unlinked install gives `401 ACCOUNT_TOKEN_EXPIRED` (R3-6).
- **Delete**: Apple revoke first, then one SQL transaction that locks the account, clears `account_id`/`account_linked_by` (`attach_reclaim_used_at` untouched, D-58), deletes the account's `idempotency_records` and deletes the account (FU-015: no tracked EF graph). The idempotency writer re-checks the account under `FOR SHARE`, so a sign-in finishing at the same moment can't leave an orphan row.
- **Apple Android callback**: stateless. Only `state`/`code`/`id_token`/`error` are read, each once, each against an anchored pattern. `user` is never read. Body capped at 32 KB, including chunked bodies. `Location` is built from constants plus `Uri.EscapeDataString`, and the package is validated at startup. `state` single use and expiry are checked by the app (`apple_state.dart` `consume`). Replay of a callback only re-bounces. The sign-in it feeds is protected by `replay_guard`.
- **No financial data accepted**: `StrictJson` refuses unknown members, so the body is only the account-token class of BR-SYNC-03.
- **Logging**: only fixed messages and status codes. No token, code, nonce, email or `Location` is logged. Every result `ToString()` is `***` or the kind.
- **App match**: the generated client (`api_models.g.dart` `/v1/accounts/signin|signout|me`) sends `provider`, `idToken`, `nonce`, `authorizationCode`, `replaceLink`, `seatKeys`, which matches `SignInRequestDto`.

### Apple revoke fails closed: judgement and proposal

A transient Apple failure (5xx, timeout) answered with 503 and an app retry is fine. A **permanent** failure is not fine. Examples: the Sign in with Apple key is revoked or rotated in Apple's console, so `invalid_client` comes back as 400 and is not `invalid_grant`; or `Accounts:Apple:*` goes missing after tokens were stored. Either way every delete returns 503 forever. That blocks the user's right to delete their account (and Apple guideline 5.1.1(v)) because of our own configuration. Production refuses to start without the key, which makes this unlikely at launch, so it doesn't block this batch.

**Proposal (FU, PO to confirm):** delete the account at once in every case. When the revoke fails, move only the sealed refresh token and client ID into a `pending_apple_revocations` row: no account ID, no subject, kept at most 30 days. A worker retries the revoke and alerts on repeated `invalid_client`. 503 is then never caused by Apple. Until that exists: map `invalid_client`/`unauthorized_client` and "not configured" to a loud error metric, so an operator sees the stuck deletions.

### Acceptance criteria

The builder's AC→test map is in `AccountEndpointTests`, `SignInServiceTests`, `AccountLifecycleServiceTests`, `AppleCallbackTests`, `IdTokenVerifierTests` and `AccountsLiveContractTests`. The non-Docker parts pass here. The DB-backed ACs (FR-GOLD-07, R3-3/D-58 second sign-in, D-54, R3-5, R4-1(1), R5-2, D-63/D-65(a)/R5-3(b), sign-out paused, FU-011 live contract) are Testcontainers tests and are **gated on the batch GitHub run**.

### Findings

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | minor (FU) | `backend/src/Zaghlol.Application/Accounts/SignInService.cs:210-219`, `backend/src/Zaghlol.Infrastructure/Accounts/AccountStores.cs:61-66,169` | Sign-in locks the D-54 attach subset first (ordered), then the rest of the account's entitling purchases (ordered). Together that is not one global order. Example: attached `{P3}`, entitling `{P1,P3}` locks P3 then P1, while a concurrent restore locks P1 then P3. Delete's `UPDATE … WHERE account_id = @id` locks in scan order. PostgreSQL detects the deadlock and aborts one side with a 500 (no data loss, and the sign-in nonce is spent, so the app redraws it). | Lock the union first: `SELECT id FROM purchases WHERE (install_id=@install AND account_id IS NULL) OR account_id=@account ORDER BY id FOR UPDATE`, then attach and seat. In delete, lock `… WHERE account_id=@id ORDER BY id FOR UPDATE` before the `UPDATE`. Test: two transactions on a P1/P3 pair interleaved through a barrier finish without `40P01`. |
| 2 | minor (FU, PO) | `backend/src/Zaghlol.Application/Accounts/AccountLifecycleService.cs:64-70` | A permanent Apple revoke failure blocks account deletion indefinitely (see the judgement above). | The pending-revocation queue in the proposal above, or at least an error metric and an alert on `invalid_client` and on "not configured". |
| 3 | minor | `backend/src/Zaghlol.Infrastructure/Accounts/AppleAccountClient.cs:110` | `RevokeAsync` catches only `HttpRequestException`/`TaskCanceledException`. A `CryptographicException` from minting the client secret (bad PEM after rotation) becomes a 500 instead of the documented 503. The exchange path catches more types. | Catch `CryptographicException` and `InvalidOperationException` too, and return `Unavailable`. |
| 4 | nit | `AccountLifecycleService.cs:66-67` | If `vault.OpenAsync` returns null (the envelope key is lost), the account is deleted without a revoke and nothing records it. | Log a fixed warning or metric. |
| 5 | nit | `docs/04-tasks/tasks/T-135.md` | The Lead's earlier follow-up about the retention wording is already handled in `backend-schema.md:438`. | None; noted for the board. |

---

## T-167 — Zakah engine (C4 money) and T-168 — Zakah screen (C2, reviewed as money)

**T-167 verdict: CHANGES_REQUESTED** (docs only). **T-168 verdict: CHANGES_REQUESTED** (one copy line plus docs).

### What is right

- **Native-unit math**: lots are integers (minor units per the currency's own exponent, milligrams for gold, milli-coins for the coin). The due is `amount × 25/1000` through `BigInt`, rounded once to the unit's smallest step (half-even by default and configurable). Tests cover EGP 2, KWD 3 and JPY 0 decimals, and gold to the milligram.
- **Nisab is the only cross-unit sum.** Every zakatable lot is valued in the 24K price's currency through the caller's converter. A missing 24K price or rate gives `needsPrices` with no dues and no guessed cost (tests).
- **No cross-currency total**: `dueByUnit` is keyed by unit. The screen renders one line per unit (`_Totals`). Cost lines are per lot and labelled `≈` / `تقريباً`, with a stale banner on top.
- **Ledger per unit**: `upsertCycle` writes `<lotId>@<cycle start>` with the native amount and status in one statement, so the `paid <= amount` CHECK holds.
- **Flag off hides everything**: `_ZakahEntry` and `ZakahScreen` both watch `featureFlagProvider(FeatureFlag.zakah)` and read no data when it is off. There is no other entry point (grep). Widget test: "flag off: nothing is shown and no entry point". The disclaimer is always at the top, also for Free users.
- Spec §11 table reproduced in `zakah_engine_test.dart` "spec section 11 table" (8 cases). Boundaries are tested at 353/354 days and 84.9/85 g.

### Findings

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| Z1 | **major (money, blocking)** | `app/lib/features/zakah/presentation/zakah_screen.dart:558`; `app/lib/core/l10n/app_en.arb:3415` (+ `app_ar.arb`) | The "How it's calculated" section tells the user "Debts that are due now are deducted from cash first", but the repository passes **no debts** (`zakah_repository.dart`: "Debts: none are read yet"). The user is shown a rule that the numbers don't follow, and their dues are overstated without warning. The Lead asked that simplifications never be shown to users as final. | Replace the line with true copy, e.g. EN "Debts aren't deducted yet. If you owe money that's due now, ask a scholar how it changes your Zakah." with Egyptian-colloquial AR, or remove the line. Widget test: the populated state does not show the old debts sentence and does show the new one (`ar` and `en`). |
| Z2 | **major (money, blocking)** | `docs/04-tasks/tasks/T-167.md` "For the scholar" | The scholar list describes the engine, not what T-168 ships. Item 5 (debts deducted) and item 10 ("zakatable flag is the user's choice") are not true in the app: there is no debts source, and every asset is zakatable with no way to exclude personal-use jewelry. Glue choices are missing from the list entirely: an **account balance's hawl starts on the day the account was added to the app** (`zakah_repository.dart:251`), the balance used is the last parsed balance, an asset's hawl starts at `acquired_at` or else the day it was added, certificates count at principal and funds at the manual value, and real estate, cars and others are excluded. The scholar sign-off (OQ-10) is the gate before the flag goes on, so the list must describe what ships. | Add an "As shipped in T-168 (differs from the engine)" block to the scholar list with the items above, and mark items 5 and 10 "engine only, not wired". Copy the block into `docs/01-requirements/open-questions.md` OQ-10, or point to it from there. |
| Z3 | minor | `zakah_screen.dart:541` | The percentage is assembled by hand with a Latin `%` and a hard-coded decimal separator. Arabic should use `٪` under the locale's number format. | Use `NumberFormat.percentPattern(lang)` (or an ARB placeholder) with the digits mode. |
| Z4 | minor | `zakah_screen.dart:380` | `'${title} · $amount'`: the separator is hard-coded and the order is fixed, which is not RTL-safe for mixed text. | Add an ARB pattern (`zakahMainLotCoin(title, amount)`). |
| Z5 | minor | `zakah_repository.dart` `compute()` | A lot that can't be mapped (unknown karat or currency) is dropped silently from the nisab test (`_make` returns null), so wealth can be understated. | Count the dropped lots and show a "some assets weren't counted" note, or treat them as `needsPrices`. |
| Z6 | nit | T-168 build notes | "partly paid" is shown but can't be entered; the missing l10n keys are listed. | FU for the T-168 copy pass. |

---

## T-071 — International notification templates (Wise, Revolut, Monzo, bunq, N26, Payoneer)

**Verdict: CHANGES_REQUESTED.**

What is right: every template is `synthetic-unverified` (test). Fixtures are synthetic. Wise `fx_conversion`: `amount` is the debited leg and `originalAmount` the received leg, both taken from the text and never computed (`Wise USD to EGP` test: USD 10000 / EGP 485000). Wise `card_purchase_fx`: `amount` is the charged account-currency figure. `card_purchase` can't swallow a `card_purchase_fx` text, because the merchant class `[^(]` stops at `(`. Revolut pending and settled share the merchant key, so the EC-54 merge (T-046) can match. `fx_conversion` is still a `DeferredEvent` (`ingest_rules.dart:58`): the raw is stored `reparse_pending`, no transaction is created and nothing is lost before T-089. Patterns use bounded `\D{0,16}` and lazy groups, and `registry_lint` reports 0 findings. The Guard base and spike base are regenerated and the e2e count is 60.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| R1 | **major (money, blocking)** | `app/assets/registry/institutions/revolut.json:30,43,56` and the `fx_conversion`, `wallet_topup`, `refund` and `declined` patterns | `(?<cur>[£€$])` has no left boundary. Revolut writes AUD, CAD and SGD as `A$`, `CA$`, `S$`, and the lowercased `a$12.00` matches `$12.00`. Probe on the merged tree: `"Card payment\nA$12.00 paid to Woolworths"` gives `cardPurchase USD 1200, needsReview=false`; `CA$5.00` gives USD 500. A foreign amount is saved under the wrong currency and auto-accepted, which breaks CLAUDE.md §2.4 (explicit currency, never silently changed). | Add a left boundary to every Revolut currency capture, including `ocur` and the balance symbol: `(?<![a-z])(?<cur>[£€$])`. Better still, also capture the prefix and map `a$`→AUD, `ca$`→CAD, `s$`→SGD, `us$`→USD in `currencyMap`. Test in `international_templates_test.dart`: `A$12.00 paid to X` and `CA$5.00 paid to X` either don't parse as USD (no match, or needsReview) or parse as AUD/CAD. `$12.00 paid to X` stays USD. |
| R2 | minor | `docs/03-technical/parsing-engine.md` §4 | The `fx_conversion` field convention (`amount` = debited leg, `originalAmount` = received leg) exists only in the task notes, and T-089 will need it. | Add one line to parsing-engine.md next to the FX conversion row. |
| R3 | minor | AC "two legs" | The test proves the two fields. The two transactions themselves are T-089 (deferred today). | Note in the TASKS.md row that the AC is met at the parser level and the legs come with T-089. |

## T-072 — Regional SMS templates (HDFC, Paytm, Al Rajhi, ENBD, Liv, Warba)

**Verdict: APPROVED.**

Probe and tests: `Rs.1,23,456.78` parses as INR 12345678 and `Avl bal Rs 5,00,000.00` as balance 50000000 (EC-51). `KWD 1.234` parses as 1234 fils, and `KWD 1,234` as 1234000 fils with `Available limit KWD 500.000` going to `available`, not `balance` (EC-36). `د.ك`/`ر.س`/`د.ا` are mapped explicitly. Limit wording maps to `available` in every `limit|lmt` and `الحد` branch. Arabic-digit fixtures are on the AR templates. All templates are `synthetic-unverified`. The `englishOnly` exemption in `real_registry_test.dart` is scoped to the 8 English-only providers.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| G1 | minor | `app/assets/registry/institutions/alrajhi.json` (all `.*? … (?<merchant>.+?) … $` patterns) | Two lazy dot runs plus optional tails before `$` backtrack about O(n²) on a long non-matching body. The SMS length cap keeps it bounded, and lint passes. | FU: replace `.*?` after `last4` with `[^:]{0,40}?` or similar. |
| G2 | nit | `enbd.json` | `(?<cur>[a-z]{3}|د\.ا)` accepts any three letters as a currency. Unknown codes are refused downstream by `Currency.tryOf`. | None. |

---

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| T-168 | `app/lib/features/zakah/presentation/zakah_screen.dart:558`; `app/lib/core/l10n/app_en.arb:3415`, `app_ar.arb` `zakahMainHowDebts` | Stop claiming debts are deducted: write true copy (debts not deducted yet, ask a scholar) or remove the line. | Widget test (`ar` + `en`): the populated Zakah screen shows the new debts line and not the old claim. |
| T-167 / T-168 | `docs/04-tasks/tasks/T-167.md` "For the scholar" (+ OQ-10 in `open-questions.md`) | Add an "as shipped" block: no debts read; every asset zakatable with no opt-out for personal jewelry; account hawl starts on the day the account was added; last parsed balance used; asset hawl from `acquired_at` or else the day added; certificates at principal, funds at manual value; excluded asset types. Mark items 5 and 10 as engine-only. | None (docs). |
| T-071 | `app/assets/registry/institutions/revolut.json` (every `[£€$]` capture, lines 30, 43, 56 and the fx/topup/refund/declined patterns) | Add a left boundary `(?<![a-z])` before the symbol, or capture and map `a$`/`ca$`/`s$`/`us$` explicitly. | `international_templates_test.dart`: `A$12.00 paid to X` and `CA$5.00 paid to X` never give USD auto-accepted; `$12.00 paid to X` stays USD 1200. |

---

## Delta re-review (fix round)

Scope: `origin/review/batch-25a..origin/batch/2026-11-15-25`, non-merge commits `55e03545` (fix25b), `3eee0fb9` (fix25a), `18b9f84e` + `de931e0d` + `0aa8b197` (fix25k, T-135). Reviewer: Opus, delta only. Covers the blocking items of this report and of `batch-25b.md`.

**Runs on the batch tip `0aa8b197`:** `packages/zaghlol_parsing` `dart test --exclude-tags benchmark`: 1282 passed. `app/` `flutter test test/features/export_import test/features/roi test/features/zakah --exclude-tags golden,benchmark`: 97 passed. Backend `Zaghlol.Application.Tests` 1039 passed, `Zaghlol.Workers.Tests` 30 passed. `Zaghlol.Api.Tests`: only the Testcontainers tests fail here (no Docker), including the new `Delete_WhileAppleIsDown_StillDeletesAtOnce_AndQueuesOnlyTheSealedToken` and `Delete_WhenAppleSaysInvalidGrant_QueuesNothing`. `HostStartupTests` failed once under the full parallel run and passed 3/3 alone; that flake is older than this delta. The DB-backed tests (`AccountPurchaseLockOrderTests`, grant, schema and check tests) and the migration snapshot check are gated on GitHub. The Lead reports backend-ci green on `ci/fix25k`.

### T-071: R1 resolved, **APPROVED**
- Every currency capture in the 25 templates of Revolut (7), Monzo (4), N26 (4), bunq (4) and Payoneer (3) is now `(?<cur>(?:[a-z]{1,2})?[£€$])`, and Revolut `fx_conversion`'s `ocur` has it too. Each of those templates has `currencyMap` `a$/ca$/s$/us$/nz$/hk$`. I scanned every other registry file: no other template captures `$`.
- An unknown prefix can't become USD. `template_extractor.dart` `resolve` checks `currencyMap` first, then `resolveCurrencyMarker`. That function knows only bare symbols, plus a 3-letter ISO code through `Currency.tryOf`, so `c$`, `r$`, `z$`, `e£`, `mx$` and `xn$` (from `MXN$`) all resolve to null. A null `cur` is a `currency` problem, not a fallback (`template_extractor.dart:206`). Out-of-tree probe on the 5 institutions × `C$ MX$ R$ E£ MXN$ NT$ Z$`: every case gives `ParseUnrecognized`, never USD. Bare `$` stays USD (test). The fix also covers `E£`, which used to match its `£` and parse as GBP.
- Tests: `international_templates_test.dart` group "dollar-prefix currencies are never silently USD" checks A$, CA$, S$, US$, NZ$, HK$ and bare $ on Revolut, plus one case each on Monzo, N26, bunq and Payoneer.

### T-168 Z1 and T-167 Z2: resolved, **APPROVED** (T-167 and T-168)
- `zakahMainHowDebts` in en and ar now says debts are not deducted and tells the user to ask a scholar. The Arabic is Egyptian colloquial. The widget test (ar and en) checks the new line is shown, the old claim is gone, and the text contains "not deducted" / "مش بتتخصم".
- `T-167.md` has the "As shipped in T-168" block with every item I asked for, and items 5 and 10 are marked engine only. OQ-10 points to it.

### T-158 blocker 1: resolved, **APPROVED**
- `importRunnerProvider` now passes `onImported: importPostPersistHook(pairing, refunds)`. For each new id after the commit (`import_csv.dart:259-264`), the hook runs `TransferPairingUseCase.onPersisted` and then `RefundMatching.onPersisted`, each in its own try/catch, so a hook failure never fails an import that is already saved. The order matches `bulk_actions.dart` and `transaction_editor.dart`.
- Test `import_hooks_test.dart`: real in-memory DB, both legs imported, one `transfer_pairs` row. A re-import gives `imported 0`, and the pair count stays 1.

### T-169/T-170 minor 5: resolved (still **APPROVED**)
- In `roi_providers.dart`, the `transport` case is gone, so `commuteMonthly` stays null and rule 5 is silent. A test covers this. The rule-2 erratum (22,200) is recorded in `requirements.md`.

### T-135 follow-ups 1–4 and the PO queue proposal: done, **APPROVED**, security part included
- **Deletion is never blocked.** `AccountLifecycleKind.Unavailable` and the 503 are removed from the service, the endpoint and the OpenAPI. If revoke throws (except on cancel) or returns anything other than `Revoked`, the token is re-sealed and queued. If re-sealing fails, or the stored blob doesn't open, the account is still deleted and a fixed warning is logged. The warning carries only the exception type name: no token, subject or message. Finding 4 is resolved. Finding 3 is resolved too: `AppleAccountClient.RevokeAsync` now also catches `CryptographicException` and `InvalidOperationException`.
- **The queue holds only what revoke needs.** Its columns are `id`, `sealed_blob`, `attempts`, `created_at`, `next_attempt_at` and `expires_at`. There is no account, install or subject column. The token is re-sealed under the constant vault context `pending-apple-revocation`, so the blob doesn't name its subject either. It is inserted in the same transaction as the account delete, so the queue row and the account deletion are both saved or both lost together. `PendingAppleRevocation.ToString()` is `***`. The worker logs counts only.
- **Retention is bounded.** `expires_at = now + 30 d`, with `CHECK (expires_at > created_at)`. Each pass first deletes expired rows, and `ListDue` also filters on `expires_at > now`. A row is deleted on `Revoked`, which includes `invalid_grant`, and an unreadable blob is dropped. Back-off runs 15 min ×2ⁿ up to a 24 h cap. The table is listed in `backend-schema.md` §4.
- **The worker can't resurrect an account.** `AppleRevocationRetryJob` and `PendingAppleRevocationStore` touch only `pending_apple_revocations`, on the Worker login. The worker's grants on that table are SELECT, DELETE, and UPDATE of `(attempts, next_attempt_at)` only. The worker has no new grant on `accounts` or `purchases`.
- **The migration is safe.** It is plain SQL outside the EF model: the class says so, and the Designer is the unchanged target model, which the Lead reports the backend-ci snapshot check passed. Grants come from the frozen `GrantMatrix.PendingAppleRevocations`. The API gets INSERT only, so it can't read the blob back, and no operator role gets any grant. `Current` merges the new grants. Down runs `DROP TABLE`, which also drops the indexes and grants.
- **Lock order is consistent.**
  - Sign-in locks install, then the account (upsert), then links, then `LockPurchasesAsync`. That call locks, in one ascending-uuid statement, the union of this install's unlinked purchases and the account's linked purchases. Attach and seats come after.
  - Delete locks the account row, then the account's purchases in ascending ID order, then runs the `UPDATE`.
  - Restore already locked in ascending ID order (as checked in the original review).
  - Accounts are always locked before purchases, and purchases always in ascending order, so finding 1 is resolved. A Docker test asserts the union lock.

### New findings (none blocking)

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| D1 | minor (FU, before go-live) | `backend/src/Zaghlol.Workers/Program.cs:64-68`; `docs/03-technical/deployment.md` (worker section) | The worker now calls `AddZaghlolKms` and builds `AppleAccountClient` through `AccountsOptions.Read`. In Production, that throws without all of `Accounts:*`, including `Google:ClientIds` and `AndroidPackage`, which the worker never uses. The whole worker would then fail at startup, and with it the Play/Apple notification processors, the ack sweeper and retention. It fails fast and loudly, but `deployment.md` doesn't say the worker now needs `Kms:*` and `Accounts:*`. Only `docker-compose.yml` was updated. | Add the worker's new `Kms:*` / `Accounts:Apple:*` needs to `deployment.md`. Better still, give the revocation worker an Apple-only options read, so a missing Google client ID can't stop billing processing. |
| D2 | minor | `docs/01-requirements/open-questions.md:17-19` | The OQ-10 "as shipped" paragraph is inserted between the OQ-10 and OQ-11 table rows. That ends the table, so OQ-11 and OQ-12 render as loose pipe text. | Move the paragraph below the table. |
| D3 | nit | `backend/src/Zaghlol.Infrastructure/Accounts/PendingAppleRevocationStore.cs:14-18` | `ListDue` doesn't use `FOR UPDATE SKIP LOCKED` and takes no advisory lock, so two worker replicas could revoke the same token twice. This is harmless, because a second revoke returns `invalid_grant`, which counts as `Revoked`. `deployment.md` already says to run one worker replica. | None now. Add an advisory lock if the worker ever scales out. |
| D4 | nit | `app/lib/features/export_import/presentation/import_ports.dart:21` | It imports `transferPairingUseCaseProvider` and `refundMatchingProvider` from `transactions/presentation/list/txn_list_providers.dart`, so one feature's presentation layer depends on another's. This is an existing placement of those providers. | FU: move the two providers to `transactions/application` or `data` when that file is next touched. |

### Delta verdicts

| Task | Verdict |
|------|---------|
| T-071 | **APPROVED** |
| T-072 | APPROVED (unchanged) |
| T-135 | **APPROVED** (security: pass; D1 and D3 are follow-ups) |
| T-167 | **APPROVED** |
| T-168 | **APPROVED** |
| T-158 (batch-25b) | **APPROVED** |
| T-169 / T-170 (batch-25b) | APPROVED (minor 5 resolved) |

None of the new findings is a blocker or a money/security/privacy/data major. D1 and D2 are follow-ups. The batch can merge once the GitHub run is green, including the Testcontainers tests named above.
