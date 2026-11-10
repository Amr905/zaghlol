# T-128 — Security & privacy review

| Field | Value |
|-------|-------|
| Task | T-128 Daily `POST /v1/sync` with throttle, contributions and bank-request intake (C4) |
| Reviewer | `security-privacy-reviewer` (Opus) |
| Date | 2026-11-10 |
| Diff | `origin/main...origin/task/T-128-sync` @ `65bc6d6` (EF Designer files skipped) |
| Verdict | **CHANGES_REQUESTED** (one Medium, plus one Low doc fix marked "before merge") |

## Scope read

`Api/Endpoints/V1/SyncEndpoints.cs`, `SyncDtos.cs`, `SyncTelemetry.cs`, `ApiPipeline.cs`, `Json/ApiJsonContext.cs`, `Json/StrictJson.cs`; `Application/Sync/*` (service, intake, composer), `Application/Contributions/ContributionPrivacy.cs`; `Infrastructure/Sync/SyncStore.cs`, `KeyedInstallHasher.cs`, `Observability/LogPseudonymizer.cs`, `ZaghlolMetrics.cs`; migration `20261110100314_AddInstallLastSyncAt.cs` + `Persistence/SyncSql.cs`; doc diffs (security-model §6, backend-api §4.2, backend-schema, deployment, OpenAPI `sync`); tests `SyncEndpointTests`, `SyncIntakeTests`, `SyncLiveContractTests`, `GrantTests`, `SyncStoreTests`.

## Findings

### S1 — Medium (before merge): the server privacy filter misses common phone-number shapes and the docs claim "any script"

- **Where:** `backend/src/Zaghlol.Application/Contributions/ContributionPrivacy.cs:20` (`Separators = ".,/_،-"`), `:48` (`DigitValue`: only ASCII, Arabic-Indic, Extended Arabic-Indic, fullwidth), `:72` (any other character resets the run); `backend/src/Zaghlol.Application/Sync/SyncIntake.cs:111-158` (`NormalizeText` removes only `Control`/`Format`, folds only U+FF01-FF5E and U+3000). Claims: `docs/03-technical/security-model.md:36` and `docs/03-technical/backend-api.md:124` ("no run of 6 digits **in any script**").
- **Leak path (no malicious client needed):** the app's filter is the primary control, and this filter is the server's only check before the text is stored for up to 180 days. The following `merchantNorm` / `institutionName` values pass `IsAcceptable` *and* the DB CHECK, so a phone or account number is stored in `merchant_contributions` / `bank_requests` with an `install_hash`:
  - `010–1234–5678` (U+2013 en dash; same for U+2010-2015 and U+2212 minus): longest run is 4.
  - `٠١٠ـ١٢٣٤ـ٥٦٧٨` (Arabic tatweel U+0640, common in Arabic SMS/notification text, category `Lm`): longest run is 4.
  - `010•1234•5678`, `010|1234|5678`, `010:1234:5678`, `(010) 1234·5678`: any separator outside the six listed resets the run.
  - Digits of other scripts (Devanagari `०-९`, Bengali, Persian variants are covered, but not e.g. `𝟎-𝟗` mathematical digits, superscripts, circled digits) are not folded although the docs say "any script". NFKC, which the design note (§4) required, folds the compatibility forms; the hand-rolled `Fold` does not.
- **Adversarial path (malicious or modified client):** a combining mark (`Mn`, e.g. U+0301, U+034F CGJ, U+FE0F variation selector) after each digit is neither removed nor a separator, so `0́1́0́1́2́3́4́5́6́7́8́` passes. The small commercial at `﹫` (U+FE6B, NFKC → `@`) passes the `@` check, so `name﹫instapay` (an IPA) is stored.
- **Required change:**
  1. In `HasDigitRun`, fold every decimal digit, not a fixed list: enumerate `Rune`s and use `CharUnicodeInfo.GetDecimalDigitValue` / `Rune.GetNumericValue` (CoreLib's own Unicode tables, available under invariant globalization). Count any digit-like rune (`Nd`, plus `No` such as superscripts/circled digits) as a digit.
  2. Treat as separators (still capped at 3 in a row) every `Pd` (dash punctuation), U+2212, U+0640 tatweel, `Ps`/`Pe` brackets, `Po` other punctuation (`• · : |` etc.) and `Sm`/`So` symbols; or, simpler and stricter, let any non-letter character be a separator.
  3. In `NormalizeText`, drop `NonSpacingMark`/`EnclosingMark` characters that follow a digit (or make `HasDigitRun` skip them without resetting), and fold `﹫` (U+FE6B) to `@` (U+FF20 is already folded).
  4. Add `SyncIntakeTests` vectors for each bullet above (en dash, tatweel, bullet, Devanagari, mathematical digits, combining marks, `﹫`), all filtered.
  5. Either make the "any script" wording true (items 1-3) or narrow it in `security-model.md:36`, `backend-api.md:124` and `backend-schema.md:311,367`. The DB CHECK can stay as it is (a narrower backstop is fine; the API is the control).

### S2 — Low (before merge, docs only): `backend-schema.md:367` claims "Contributions can't contain people or amounts"

- **Where:** `docs/03-technical/backend-schema.md:367` (threat-table row heading; pre-existing wording, but T-128 is the task that starts writing these tables and the PO-accepted residual must not be contradicted).
- **Why:** the server detects no person names (PO-accepted residual, correctly stated in `security-model.md:36`), and the 6-digit rule lets short amounts and dates through (`250.00`, `12/05`, `99 egp`). The heading promises both. This is the text an auditor or a future agent will quote.
- **Required change:** reword the row to what is enforced, e.g. "Contributions carry no phone, card/account number or e-mail/IPA; names, short amounts and dates rely on the app filter, the A-48 threshold and operator review (security-model §6)".
- `security-model.md:36` is correct on names (it says the server does not detect them). The OpenAPI `ContributionInput` description ("No amounts, dates, accounts or person names", `zaghlol-v1.yaml:2130`) reads as the client's obligation and is acceptable (see I2).

### S3 — Low (follow-up): `zaghlol.count_daily_active` takes any day and any platform

- **Where:** `backend/src/Zaghlol.Infrastructure/Persistence/SyncSql.cs` `CreateCountDailyActive`; `GrantTests.cs:96` asserts `app_rw` may call it with `DATE '2000-01-01'`.
- **Abuse path:** anything running as `app_rw` (a compromised API process, or a future SQL injection on any App-login path) can call `SELECT zaghlol.count_daily_active('2025-01-01','x','1.0.0')` in a loop to inflate any past or future day's count, or create rows with arbitrary `platform` text (`daily_active_counts.platform` has no CHECK). It **cannot** read the counters, decrement, set a value, or touch another table: the body is a single static `INSERT ... ON CONFLICT DO UPDATE SET installs = d.installs + 1`, no dynamic SQL, returns `void`, `SET search_path = zaghlol, pg_temp` (pg_temp last), `REVOKE ALL ... FROM PUBLIC`, `GRANT EXECUTE` to `app_rw` only, and `GrantTests` covers admin/worker/ops_ro denial plus `app_rw` having no table privilege. So only the integrity of an anonymous aggregate is at stake; T-122 SEC F10 holds.
- **Required change (follow-up):** drop `p_day` and use `(now() AT TIME ZONE 'UTC')::date` inside the function (the caller's `now` is server time anyway), and reject `p_platform NOT IN ('android','ios')` (or add the CHECK on the table). New migration; `SyncSql` stays frozen.

### I1 — Info: install-hash pepper reuse is properly domain-separated

`KeyedInstallHasher` feeds `"zaghlol-install-hash-v1" ‖ 0x00 ‖ <uuid D form>`; `LogPseudonymizer` derives its monthly key from `"zaghlol-log-v1" ‖ 0x00 ‖ yyyy-MM` under the same `InstallHashPepper`, then HMACs the install ID with that in-process sub-key. Labels differ, contain no NUL and are NUL-terminated, so the inputs are prefix-free and cannot collide; the process-held log sub-key cannot compute `install_hash`. The hash is computed in the KMS and the raw install ID never reaches the contribution tables. Note for T-129/retention: `install_hash` is stable for the life of the install by design (one vote per merchant), so an install's contributions and bank requests are linkable to each other for the 180-day retention; no change requested.

### I2 — Info: OpenAPI description of `ContributionInput`

`zaghlol-v1.yaml:2130` "No amounts, dates, accounts or person names" is fine as a client contract. Optionally append "(the app filters these; the server checks only digits, `@` and length)" so no reader takes it as a server guarantee.

## Verified (no finding)

- **BR-SYNC-03 boundary.** `SyncRequest`/`SyncContributionInput`/`SyncBankRequestInput` carry only the cursors, `entitlementIssuedAt`, `registryVersion` and the two outbox lists; `UnmappedMemberHandling.Disallow` and case-sensitive names are set on the source-generated context and in `StrictJson` (`ApiJsonContext.cs:14-16`, `StrictJson.cs:178-179`), so nested extras are `400 UNKNOWN_FIELD` (tests `SyncEndpointTests.cs:284-286` plus the live contract test). `SyncLiveContractTests` pins the member allow-list. Platform is taken from the install row, not the header. Body capped at 64 KB before parsing (`StrictJson.cs:58,68`).
- **Caps.** 51 contributions / 11 bank requests reject the whole call (`TryValidate`), tested.
- **Throttle.** Server clock only; pre-check is one indexed read; the authoritative claim is the conditional `UPDATE ... WHERE (last_sync_at IS NULL OR last_sync_at <= @cutoff)` under READ COMMITTED, so the second of two concurrent claims re-evaluates the predicate after the row lock and gets 0 rows (tested with `Task.WhenAll`). A throttled call writes nothing: no intake, no DAU, no `last_seen_at` (asserted in `SyncEndpointTests.cs:156-191`). Intake, claim and DAU are in one transaction; a lost claim rolls back.
- **Response signing and nonce.** `.WithTimeNonce().RequireResponseSignature()` on the route; both response types implement `IAnchoredResponse` with `timeNonce` always serialized; the nonce comes from the current request's context only, so another install's nonce cannot be echoed (tested). Throttle body is structurally three members.
- **Logging.** Only fixed event codes with closed-set reasons (`SYNC_THROTTLED`, `SYNC_BLOCK_FAILED`, `SYNC_FLAG_RULES_INVALID`); no body, contribution text, nonce, token, hash or `entitlementIssuedAt`; log-capture test with a phone-number contribution. A non-transient DB error goes to the existing global handler; with `Include Error Detail` off (FU-025) a CHECK/FK message carries no row values.
- **Metrics.** Tags are fixed sets (`outcome`, `mode`, `kind`/`result`, `block`, `flag` from `FlagKeys.Known` only); no install id or text; series seeded at 0.
- **DoS.** 64 KB body, 50/10 caps, one KMS HMAC per effective sync, existing per-token and per-network rate limits, `MaxDeltaOps` bound with `full` = URL only, `Retry-After: 30` on 503. Failures before the claim consume nothing.
- **Hasher outage.** Intake dropped, sync succeeds, diag metric; no raw install ID fallback.

## Required before merge

1. S1: widen digit folding and separators, strip combining marks, fold `﹫`; add the test vectors; keep the docs' "any script" claim only if true.
2. S2: reword `backend-schema.md:367`.

S3, I1, I2 are follow-ups (FU entries in `docs/implementation-status.md`). Re-review: delta only, on Sonnet.
