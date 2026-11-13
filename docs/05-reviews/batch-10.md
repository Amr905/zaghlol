# Batch 10 — code and security review (T-141, T-132, T-043, T-109, T-023)

Reviewer: `code-reviewer` (Opus), the only reviewer for this batch, covering code and security (CLAUDE.md §6 cost rules). Date: 2026-11-13. Batch branch `batch/2026-11-13-10`, head `5f80484`.

| Task | Class | Branch head | Verdict |
|---|---|---|---|
| T-141 App BackendClient, ES256 verification, install registration | C4 crypto | `2c0bb5f` | **APPROVED** |
| T-132 Entitlement tokens, `GET /v1/entitlement`, seat at verify, sync block, FU-112 backfill | C4 billing | `33ed1e6` | **APPROVED** |
| T-043 Bank notification listener | C4 notification ingestion | `fdea8b0` | **APPROVED** |
| T-109 Voice-phrase parser | C3 | `83b3cf9` | **CHANGES_REQUESTED** |
| T-023 Localization, digits mode, money/date formatting | C2 | `7970a6b` | **APPROVED** |

**Run on the batch head in this workspace:**
- `flutter pub get --enforce-lockfile`: OK.
- `flutter analyze`: no issues.
- `flutter test test/core/backend test/core/l10n`: 89/89 pass.
- `dart test test/voice` (packages/zaghlol_parsing): 17/17 pass.
- `dotnet test tests/Zaghlol.Application.Tests`: 1008/1008 pass.

**Not run here:**
- Kotlin JVM and instrumented tests (T-043). The Gradle wrapper isn't generated in this workspace.
- Testcontainers tests (T-132 store, seat at verify, backfill, live contract).
- iOS tests.

`origin/local-ci` has no result for any of the three C4 heads. The batch GitHub run (app-ci with Android unit tests, backend-ci, db-platform) is the gate for these. The Lead must confirm the T-043 JVM tests and the T-132 integration tests are green there before merging.

---

## T-141 — App BackendClient

### Design note (builder-written, Opus)
The note is sound and matches the code. I reviewed the deviations it takes on itself:
- **In-repo DTO generator instead of `openapi-generator-cli`.** Accepted. It adds no new dependency (it uses `package:yaml`, which is already locked), and `apiCodegenVersion` is written into the output. A test regenerates the code in memory and fails on any byte difference, which pins it as well as FU-013 asks. The generator refuses free-form objects, inline objects and nullable map values (`tool/api_codegen/api_codegen.dart:523-535`). The only maps generated are in response types (`FlagsBlock`, `FxBlock`).
- **Release key set empty, fail closed.** Correct by construction. An empty `ResponseSignatureVerifier` refuses every header, so every signed operation fails as `badSignature` and nothing is decoded. Dev kids (`?0000?`) verify only with `allowDevKeys`. See T141-3.

### Security checks
- **Signature canonicalisation vs T-123.**
  - Header regex `^kid=([se][0-9]{4}[a-z]); alg=ES256; sig=([A-Za-z0-9_-]{85}[AQgw])$` (`response_signature.dart:22-24`). This is byte for byte the backend form `kid={Kid}; alg=ES256; sig={Base64Url}` (`KmsPorts.cs:38`).
  - The final character class rejects non-canonical base64url padding bits.
  - The header is not trimmed, and a repeated header is refused (`BackendResponse.single`).
  - `e` kids are refused.
  - `1 ≤ r,s < n` is checked, high-S is accepted, and the point is checked to be on the curve.
  - The signed bytes are the decompressed body. The backend middleware signs inside response compression (`ResponseSigningMiddleware.cs:33-34`), and the client uses `autoUncompress`, so both sides use the same bytes.
  - The Dart verifier runs the backend's own vector file (`backend/tests/Zaghlol.Contract.Tests/vectors/response-signature-v1.json`): valid vectors pass and at least 6 invalid ones fail. **OK.**
- **Verify before decode.** In `_call`, the signature is checked before `_decode`. `rotateInstallToken` is applied only from a verified answer, and only with compare-and-set against the token that was sent (`backend_client.dart:385-397, 497-505`). **OK.**
- **BR-SYNC-03 boundary.**
  - Request bodies come only from generated request classes: `toJson()` writes declared properties only and omits nulls.
  - `InstallRequest` carries `installId`, `platform` and `appVersion` only.
  - Headers come from the operation table. There is no `Accept-Language`, and `Zaghlol-Account` is sent only where the contract allows it.
  - iOS-only members and variants throw before serialization on Android, and the reverse is also true (`_checkPlatform`, `prepareSignIn`). **OK.**
- **R5-1 ordering.**
  - The order is: marker, entitlement token, account token, install token, install ID, then `POST /v1/installs` (`backend_client.dart:660-676`).
  - Re-registration happens only on a strictly parsed `401` whose problem `status` equals the HTTP status and whose code is `INSTALL_TOKEN_INVALID`. It happens only while the stored token is still the one that was sent. It never happens for `deleteInstall`.
  - The ordered fake-server test asserts that both deletions come before the send. **OK.** See T141-1 for a crash-window nit.
- **R3-6.**
  - The ULID's 80 bits come from the injected `Random`, which is `Random.secure()` by default.
  - The pending registration (`{installId, key, body}`) is persisted before the first send. A retry resends the same key and bytes.
  - `409 INSTALL_EXISTS` or `IDEMPOTENCY_KEY_REUSED` deletes only our own record (compare-and-delete) and starts again.
  - `IdempotencyKey`, `TimeNonce`, the request, the response and the internal records all redact `toString`.
  - The diag log gets codes and the HTTP status only. **OK.**
- **Transport.**
  - No redirects are followed.
  - The body is capped at 1 MiB after decompression.
  - Transport errors are mapped to kinds, and OS messages are dropped.
  - The base URI must be HTTPS; plain HTTP is allowed only for loopback/emulator hosts and only on opt-in.
  - The recording transport throws in a product build. **OK.**
- `INTERNET` permission is added to the main manifest (T-001 F16). **OK.**

### Findings

| # | Severity | Where | Issue | Required change |
|---|---|---|---|---|
| T141-1 | minor (Security: Info) | `app/lib/core/backend/backend_client.dart:543-548, 660-670` | If the app crashes after the `reregistration` marker is written but before the install token is deleted, the next call's `_register()` sees an existing install, emits `InstallReregistered`, and clears the marker, all while the **old, refused** token is still stored. The next 401 then re-runs R5-1 correctly, so no token survives. But T-144 and T-179 receive one event too early, and possibly twice. The KDoc says a crash "leaves either the old token … or no token plus the marker", which does not cover this case. | Follow-up: announce only when the marker is set **and** the stored install ID differs from the one recorded in the marker. For example, store the old install ID in the marker and compare. |
| T141-2 | nit | `backend_client.dart:379, 555` | `baseUri.replace(path: path)` drops any path prefix of the base URI. That is harmless with today's root-hosted backend, but it is surprising. | Follow-up: join paths, or assert in `BackendConfig` that `baseUri.path` is empty or `/`. |
| T141-3 | minor (Security: Info) | `app/lib/core/backend/` (no provider) | Nothing constructs `BackendClient`, `BackendConfig` or the pinned key set yet. "Release set empty / fail closed" therefore depends on the first wiring task passing `allowDevKeys: !kReleaseMode` and an empty (or PO-supplied) `s` key list. | Follow-up for the first consumer (T-143/T-144): add the Riverpod provider with the pinned `s` JWKs as constants, plus a test that a release-mode config refuses `s0000t`. |

Generated file size (1,424 lines) and generator (865 lines) are in scope for FU-013. No out-of-scope changes.

---

## T-132 — Entitlement tokens, `GET /v1/entitlement`, seat at verify, sync block, backfill

### Security checks
- **No unverified, refunded or expired purchase yields Gold.**
  - `EntitlementRules.Classify` (`EntitlementRules.cs:101-111`) makes only `Active`/`InGrace`/`CanceledActive` purchases entitling, and only while they have no expiry or `ExpiresAt > now`.
  - `Refunded`/`Revoked` purchases become `refunded`. Every other state, including pending, becomes `expired`.
  - `VerifyGrant` returns `None` unless the store verification is `Active` with a written purchase ID (`VerifyGrant.cs:27-31`). **OK.**
- **No token covers another install's seat.**
  - `HeldSql` is keyed by `purchase_seats.install_id = @install`, and `sub` is always the caller (`EntitlementRules.cs:73`).
  - `LostSql` returns only plan, product and `next_move_at` for seats now held elsewhere. It returns no holder identity and no operator data.
  - `GET /v1/entitlement` never moves a seat. The verify-time token is issued after the seat transaction commits, from the seat rows. **OK.**
- **Account-token handling.**
  - Validation order is: signature with the published `e` key (active or retired), `alg = ES256`, `iid` equals the caller, `exp` in the future, `sub` is a UUID, then the database check that the account exists and the install is still linked to it (`AccountTokenValidator.cs`).
  - Every failure returns `null`, which yields `paused` and never an error. The token is capped at 2 KB and is not echoed.
  - The sync refresh happens only for a validated token with less than 7 days left, and is re-bound to the same `iid`.
  - A multi-valued `Zaghlol-Account` header counts as absent (`SyncEndpoints.AccountHeader`). **OK.**
- **D-60 lifetimes.**
  - `exp ≤ iat + 3 d`, or `+ 2 d` if any covering seat is `basic`.
  - Active/grace tokens never outlive the store expiry.
  - `graceUntil = exp + 4 d`.
  - A property test runs across plan × state × proof. **OK.**
- **Support notice (R5-7).**
  - The notice is keyed by the buying install.
  - The `iat` is recorded only after signing, monotonically (`support_link_notice_iat < @iat`).
  - It is cleared only when `support_link_notice_iat <= entitlementIssuedAt`.
  - A forged future `entitlementIssuedAt` can only clear the caller's own notice. **OK.**
- **Seat keys at verify (R5-2).**
  - Keys are parsed and verified only after the store checks, with challenge `SHA-256(signedTransaction)`, and registered with `attested: null`, so they are untrusted.
  - A bad proof leaves `verifiedKeys = null` and the request continues with 200. **OK.** See T132-2.
- **FU-112 backfill migration.**
  - Data only. It inserts a seat only where none exists (`NOT EXISTS` plus `ON CONFLICT DO NOTHING`), so a seat the service wrote first wins.
  - If the buying install is gone (NULL or `deleted_at` set), the seat is vacant: `install_id`, `proof` and `bound_at` are NULL, which satisfies `ck_purchase_seats_holder_proof`.
  - `last_moved_at` and `next_move_at` are NULL, so there is no cooldown, and `ck_purchase_seats_move_pair` holds.
  - No event row is written, and `attach_reclaim_used_at` is untouched.
  - Down is a deliberate no-op, and the reasoning is documented. Backfilling refunded or expired purchases is harmless: the rules classify them as non-entitling. **OK.** The integration test (`BackfillPurchaseSeatsTests`) runs only under Testcontainers.

### Findings

| # | Severity | Where | Issue | Required change |
|---|---|---|---|---|
| T132-1 | minor | `backend/src/Zaghlol.Infrastructure/Entitlements/EntitlementStore.cs:28-35` | `moved` is reported only for purchases this install **bought** (`p.install_id = @install`). The task says "a seat this install held went elsewhere". A former holder that was not the buyer (it got the seat by restore or sign-in and later lost it) gets `none` instead of `moved`. In the same query, `movedBy` comes from the purchase's *latest* `seat_*` event. A later event by the new holder (for example `seat_rebind:restore`) turns a support move into `user`. Gold is not affected; only the "your Gold moved" message is wrong. | Follow-up (T-184/T-144 owner): derive `moved`/`movedBy` from the latest `seat_move:*` event whose previous holder was this install, or record the previous holder on the move event. |
| T132-2 | minor | `backend/src/Zaghlol.Application/Entitlements/VerifyGrant.cs:35-39` | The task says a bad verify-time `seatKeys` proof or a non-registered element 0 is "ignored **with a diag counter**". The rejection (`check.Rejection`) is dropped silently. | Follow-up: increment the existing seat-key rejection counter (codes only). |

AC→test map: every AC maps to a test. AC 1–4 have Application unit tests, which ran green. AC 5–12 are covered by `SeatAtVerifyTests`, `EntitlementStoreTests`, `BackfillPurchaseSeatsTests` and `EntitlementLiveContractTests`. Those are Testcontainers tests and are not run here (see the top).

---

## T-043 — Bank notification listener

### Security checks
- **Non-registry apps never read.**
  - The main-thread filter (`NotificationFilter.accepts`) reads only `packageName` and `flags`. It drops our own package, group summaries, ongoing and foreground-service notifications, and a null `Notification`, which defaults to the ongoing flag.
  - On the intake thread, `admits(pkg)` runs before `posted.fields()` (`NotificationIntake.kt` `process`).
  - `admitsNotificationPackage` accepts only `REGISTRY`, or `USER` on the `notification` channel. An invalid base gives `config == null`, so nothing is admitted. The generic and always-capture paths are excluded for notifications (`CaptureGuard.kt:47-54`).
  - `NotificationAdmissionTest` asserts zero extras reads and an unchanged data-dir tree for unknown, hint-only, sms-only-user and invalid-base cases. **OK.**
- **Nothing raw logged.**
  - No `Log`/`println`/`printStackTrace` in `platform/capture` apart from the pre-existing generated Pigeon file.
  - Every new type redacts `toString`.
  - The dedupe map holds 16-byte SHA-256 prefixes in memory only.
  - The dispatcher swallows exceptions without printing them.
  - The canary test and source scan are extended. **OK.**
- **Manifest and service guard.**
  - `exported="true"` with `BIND_NOTIFICATION_LISTENER_SERVICE`, `directBootAware="false"`, and the ongoing filter meta-data.
  - The placement script now requires the class and the permission in every flavour's APK. **OK.**
- **Missed counting.**
  - Queue overflow is counted with an atomic on the main thread and flushed on the intake thread, so there is no Keystore access on the main thread.
  - Refused and rate-limited items go through `CaptureIntake`, as in T-040.
  - Dedupe is recorded only after a `Written` result. **OK.**

### Findings

| # | Severity | Where | Issue | Required change |
|---|---|---|---|---|
| T043-1 | minor (Security: Low) | `app/android/app/src/main/kotlin/app/zaghlol/platform/capture/NotificationCapture.kt:35` | `installForTest` is a public hook in the main source set. It redirects every admitted bank notification to any intake. This is the same pattern as T040-L1. | Fold into FU-111 (T040-L1): move both hooks to a debug/test-only seam. |
| T043-2 | nit | `NotificationExtractor.kt:82` | The title (≤ 256) + `\n` + content (≤ 4,000) can reach 4,257 units, but the Guard's `MAX_BODY_LENGTH` is 4,000. A long big-text bank notification is then dropped as `too_long` and not counted as missed. That's unlikely for real bank notifications. | Follow-up: cap content at `4000 − title − 1`, or count the drop as missed. |

---

## T-109 — Voice-phrase parser

The 17 tests pass. The 254-phrase fixture set passes the ≥ 95 % gate. The spec phrase gives 150 Groceries, 45 Dining and 30 Transport. No `double` is used: amounts are exact rationals with half-up rounding to minor units. Input is capped at 1,000 chars and 300 tokens, and every case I tried ran in 0.1–15 ms.

I ran 37 phrases of my own that are not in the fixtures. Twenty-seven were right, and the other 10 hit the defects below. The correct ones include:
- "كشري خمسة وتلاتين وعصير عشرين" → 35 + 20
- "اشتريت جزمة بألف وميتين" → 1,200
- "صرفت ألفين وخمسميه على الإيجار" → 2,500
- "دفعت ٢٥٫٥ جنيه مواصلات" → 25.50
- "عشرين دولار هدية" → USD 20, not converted
- "بنزين ٢٠٠ دينار" → ambiguousCurrency
- "Netflix 120 pounds"
- "نص ألف" → 500
- "تلت ألف" → 333.33
- three-item lists with Arabic-Indic digits
- the over-length inputs, which give `tooLong`

Two defects give a **wrong amount with high confidence and no issue flag**:

| # | Severity | Where | Issue | Required change |
|---|---|---|---|---|
| T109-1 | **major** | `packages/zaghlol_parsing/lib/voice/voice_parser.dart:384-397` | A fraction word before **مليون** is not read as part of the amount. "دفعت نص مليون جنيه عربية" gives `[text "نص", 1,000,000 EGP, conf 950]` plus `[text "عربية", missingAmount]`, "ربع مليون شقة" gives 1,000,000 with text "ربع", and "تلت مليون" gives 1,000,000 with text "تلت". These amounts are 2× and 4× too large, the fraction word becomes the item text, and nothing is flagged. The fraction branch handles only `hundred`/`thousand`. "نص مليون" and "ربع مليون" are common Egyptian phrasing for large purchases. | Accept `LexKind.million` (and `millionDual` if it makes sense) after a fraction word, the same way as `thousand`. Add fixtures for "نص مليون", "ربع مليون" and "تلت مليون". |
| T109-2 | **major** | `voice_parser.dart:152-157` (with the bare-currency branch at 398-402) | A digit amount over 12 whole digits or 4 decimals makes `_digitsToQ` return `null`. The token then stops being a number, and the following "جنيه" is read as a **bare currency word = 1 pound**. Examples: "1000000000000 جنيه", "12345678901234567890 جنيه" and "12.34567 جنيه" all give **EGP 1.00** (`missingItemText`, conf 650). `VoiceIssue.invalidAmount` exists for "too large to store", but this input path never reaches it. Speech-to-text can produce such digit runs, and the input is untrusted. | Keep an over-long digit token as an amount span that yields `amount: null` + `invalidAmount`, instead of dropping it. Add tests for >12 whole digits and >4 decimals, with and without a currency word. |
| T109-3 | nit | `voice_parser.dart` (span split) | "ألف ألف جنيه" gives two items of 1,000 EGP each, not one item. This is rare, and the user confirms the items before saving. | Follow-up, optional. |

---

## T-023 — Localization, digits mode, money/date formatting

- **No `double`.** `MoneyFormat` works on `toCanonicalString()` and the integer minor units, so exponents 0, 2 and 3 are exact. `parseInput` normalizes digits, then calls `Money.tryParse`, which is strict about decimals. **OK.**
- **Digit normalization.** Arabic-Indic and Persian digits become ASCII, and `٫` becomes `.`. `DigitsMode.resolve` follows A-29: `auto` gives Arabic-Indic for `ar`. Dates are normalized and then re-rendered, so `DigitsPref.western` works in Arabic. **OK.**
- **RTL switch.** `_LocalizedApp` watches `appLocaleProvider`. `MaterialApp.locale` changes live, and `GlobalMaterialLocalizations` supplies the direction. The test confirms the direction flips without a restart. Money is wrapped in FSI…PDI. **OK.**
- No user-facing strings are hard-coded. The ARB files hold only `appName`.

| # | Severity | Where | Issue | Required change |
|---|---|---|---|---|
| T023-1 | minor | `app/lib/core/l10n/digits_mode.dart:49-51` | `normalizeDigits` removes `٬` and the Arabic comma `،` (U+060C) anywhere, without checking the grouping. It does not remove ASCII `,`. So "١٢،٥٠" silently becomes 1250, while "1,250" is rejected. Some users type `،` as a decimal separator. | Follow-up (amount input task): accept group separators only in valid 3-digit groups, and treat ASCII `,` the same as `٬`. Reject a lone `،` instead of dropping it. |

---

## Fix list (blockers and majors only)

| # | Task | Lane | Finding | Fix |
|---|---|---|---|---|
| T109-1 | T-109 | parsing | "نص/ربع مليون" amounts 2×/4× too large, fraction word left as item text | Fraction × million in the fraction branch, plus fixtures |
| T109-2 | T-109 | parsing | Over-long digit amounts become EGP 1.00 via the bare "جنيه" path | Over-long digits → `invalidAmount`, `amount: null`, plus tests |

Every other finding is a minor or nit and becomes a follow-up under the review-round policy. No Security finding is marked "before merge". T-141, T-132 and T-043 still depend on the batch GitHub run being green (Android unit tests, Testcontainers, db-platform), because none of those ran here.

## Lead delta check T109-1 / T109-2 (976df24)

- **T109-1:** the fraction branch now multiplies by 1,000,000 when the next word is a million, exactly like the existing thousand branch.
- **T109-2:** an over-long digit run stays an amount token valued 0. The item then gets `amount: null` with `invalidAmount`, so the following currency word is no longer read as 1.
- **Tests:** two new tests cover several phrasings, both fail without the fix (builder ran this), and the 19 voice tests pass here.

Both majors are resolved. Verdict for T-109: **APPROVED**.
