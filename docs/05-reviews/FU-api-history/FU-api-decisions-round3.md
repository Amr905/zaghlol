# FU-api-decisions: Security and Privacy Review

**Reviewer:** security-privacy-reviewer · **Branch:** `task/FU-api-decisions` @ `e00fd92`
**Scope:** `git diff 74261e9 origin/fuapi` (round 3), with `git diff 5daf822...origin/fuapi -- docs/03-technical backend` for context.
**Current verdict: CHANGES_REQUESTED.** There are no blockers. Two majors must be fixed in the design before approval: R3-1 and R3-2.

---

## History

**Round 1 (2026-11-05): CHANGES_REQUESTED.**
- 2 blockers:
  - Finding 1: a shared restore token gave Gold to unlimited installs.
  - The Apple sign-in nonce was not checked.
- 4 majors, plus minors.
- Findings 2–8 and 10–12 were fixed at `8fe1251`.
- Findings 1 and 9 led to the PO decisions D-45, D-46 and D-47, then to the ADR-012 Part B design (3 seats with eviction, Play Integrity / App Attest on restore).

**Round 2 (2026-11-05): CHANGES_REQUESTED.**
- Round-1 findings 2–12 were confirmed resolved.
- 1 blocker: R2-1, the attestation was bound to the body and not to the install.
- 3 majors and further minors, across R2-2 … R2-10: account-link gaps, eviction and the 37-day window, basic-seat churn, iOS freshness, JCS duplicate keys, Play optional verdicts, idempotency scope, Google nonce, audit retention text.
- The PO then replaced the 3-seat model with D-52 (one install at a time, one move per rolling 30 days), plus D-53 and D-54 (SRS v1.5).

---

## Round 3 (2026-11-06)

### Method and dependence on CI
- **Review by reading only.** GitHub Actions is unavailable because of a billing block.
- **Vectors:** I recomputed both `valid` vectors in `backend/tests/Zaghlol.Contract.Tests/vectors/restore-binding-v1.json` with an independent Python script. JCS string, `bodyHashHex` and `requestHashB64u` all match. The vectors are ASCII-only, so code-point ordering and UTF-16 ordering agree.
- **These conclusions depend on CI and are not verified:**
  - `RestoreBindingVectorTests.cs` compiles and passes on net10.0 with `TreatWarningsAsErrors` and `AnalysisLevel=latest-recommended`.
  - The `None Update="vectors\…"` item actually copies the file. The test project is `Microsoft.NET.Sdk`, so `.json` is a `None` item, so this should work.
  - The existing T-006 contract tests still pass on the edited OpenAPI file: role table vs. `x-required-roles` for `adminMoveSeat`, refs, examples, and `x-third-party-body`.
  - The architect's local Python checks cover the same ground, but they are not the CI harness.

### Resolution of round-2 findings

| ID | Finding | Status | Evidence / residual |
|---|---|---|---|
| R2-1 (blocker) | Attestation bound to the body, not the install | **Resolved** | `bodyHash = SHA-256("zaghlol-restore-v1" ‖ 0 ‖ installId ‖ 0 ‖ JCS(…))`, with `installId` taken only from the install token (`backend-api.md:197-200`; ADR-012:102). The iOS `attestationObject` is made over the same hash, and a key registers only to the install named in the hash (ADR-012:105; `platform-channels.md:204`). Release Android builds trust system CAs only (`platform-channels.md:205`). Proxying through the owner's own phone is an accepted, bounded residual (ADR-012:112). |
| R2-2 | Account-link gaps | **Resolved**, with follow-ons R3-2, R3-3, R3-5 | Attach happens only from `purchases.install_id` (`backend-api.md:283`). The "sole attested seat holder" path is removed. The account-attach reclaim covers a seat leaked before linking (`backend-api.md:284`). Support attach brings back a lock-out path (R3-2). |
| R2-3 | Eviction / 37-day window | **Resolved in design**; enforcement gap in R3-1 | No eviction. `exp ≤ iat+7 d`, grace 7 d, so the worst-case overlap is 14 d (ADR-012:87-91). That bound holds only if the device clock is trusted (R3-1). |
| R2-4 | Basic-seat churn | **Resolved** | A basic device holds the single seat under the same cooldown, with `exp ≤ iat+3 d` (ADR-012:115). Churn is impossible because every user-initiated holder change spends the cooldown. |
| R2-5 | iOS freshness | **Resolved** (D-53 accepted by PO) | With the install binding, a stored assertion can only be spent by the install that could make a fresh one. The counter is strictly increasing. |
| R2-6 | JCS duplicate keys | **Resolved in spec; CI-dependent** | Single strict parse; duplicates and lone surrogates give `400`; JCS is computed over the same parsed object the DTO is bound from (`backend-api.md:197`, ADR-012:114). Shared vectors exist. The test gaps are in R3-8. |
| R2-7 | Play optional verdicts | **Resolved** | Off in Play Console (T-140 checklist). The DTO has no members for them, and they are never stored or logged (`backend-api.md:205`). |
| R2-8 | Idempotency scope | **Resolved**; minor hardening in R3-6 | Keyed by (install from token, operation, key) plus the body SHA-256. A mismatch gives `409 IDEMPOTENCY_KEY_REUSED`. Records are KMS-envelope-encrypted and kept 24 h (`backend-schema.md:155-163`). No cross-install leak through the authenticated operations. |
| R2-9 | Google nonce | **Resolved**; T-147 must prove it | The nonce is required for both providers, and `replay_guard` is keyed only by the nonce hash (ADR-016 Amendment 3). T-147 must show a fresh nonce on every attempt with `google_sign_in` 7.x. |
| R2-10 | Audit retention text | **Resolved** | `error-handling-and-observability.md:69` and `backend-schema.md:271`: support-lookup and support-seat-move rows are kept exactly 1 year; everything else 3 years. |

### New findings

#### R3-1 (Major): the 14-day offline bound depends on the device's wall clock, so a phone Gold moved away from can keep it indefinitely
- **Where:**
  - `docs/03-technical/backend-api.md:232` ("The app grants Gold while `now < graceUntil`")
  - ADR-012:91 (worst-case overlap)
  - `docs/03-technical/security-model.md:14` (the Gold-entitlement threat row lists no clock manipulation)
  - `docs/04-tasks/tasks/T-144.md:22` ("grant while now < graceUntil")
- **Exploit:**
  1. Phone A holds the seat and refreshes. B restores, which is a legitimate move.
  2. A blocks the app's network: Android per-app data restriction or firewall, or simply never comes online. The app is local-first, so this costs the user almost nothing.
  3. A turns off automatic time and sets the clock back.
  4. `now < graceUntil` stays true forever.
- **Effect:**
  - The FR-GOLD-08(d) acceptance criterion ("A loses Gold no later than 14 days after the move") and D-52(a) "one install at a time" fail.
  - After one move per 30 days, every former holder keeps Gold permanently.
  - No root and no modified app are needed.
  - Under the 3-seat design this was a latent weakness. Under D-52 it is the load-bearing control.
- **Required change (T-144, plus security-model threat row; contract in `backend-api.md` §4.3):**
  - Evaluate expiry against a **trusted-time high-water mark**, not the raw wall clock.
  - Persist, encrypted in `secure_state`: `hw = max(hw, lastVerifiedServerTime, wallClock, hwAtBoot + elapsedRealtimeSinceBoot)`.
    - Android: `SystemClock.elapsedRealtime`.
    - iOS: `ProcessInfo.systemUptime` / `CLOCK_MONOTONIC_RAW`, with a stored boot reference.
  - Treat a wall clock more than 10 minutes below `hw` as "clock tampered": no Gold, and copy saying "connect to check Gold".
  - Also expire when `hw ≥ graceUntil`.
  - Accumulate an elapsed-time counter from verified `iat`, so that resetting the clock after every boot doesn't help.
  - `serverTime` must come from a signed response (the entitlement or signed sync body).
  - Add a unit test with clock rollback, reboot and offline scenarios.

#### R3-2 (Major): the support move and support attach can transfer or permanently lock a purchase on proof the design itself calls insufficient
- **Where:**
  - `backend-api.md:396` (target = pending claimant or, "for `attachToAccount` alone", the current holder)
  - `backend-api.md:398` (attach)
  - `backend-api.md:399` (cooldown not restarted)
  - `backend-api.md:403` (alerts only)
  - ADR-012:123
  - `zaghlol-v1.yaml:1305`, `zaghlol-v1.yaml:2888`
  - SRS EC-68 ("support verifies ownership", with no standard defined)
- **What the claimant rule actually proves:** the claimant passed attestation, store verification and the account rule. For an unlinked purchase that means only **access to the buyer's store account plus a genuine phone**. D-46 / FR-GOLD-02 explicitly say this is not ownership. Realistic holders are a family member, an ex-partner, or the buyer of a second-hand phone still signed in to the store.
- **Exploit A, permanent lock-out:**
  1. The attacker restores after a cooldown (becoming holder) or during one (becoming claimant).
  2. The attacker signs in on their own install with their own Google or Apple account.
  3. The attacker asks support: "buying phone gone, please link" (`reasonCode: buying_phone_gone`, `attachToAccount: true`).
  4. `purchases.account_id` now points to the attacker's account.
  5. Every restore by the owner is `account_required`. A sign-in on the buying phone can't attach because `account_id IS NOT NULL` (`backend-api.md:283`). There is no detach or correction path anywhere in the API.
- **Exploit B, cooldown bypass by collusion:**
  - Owner and friend alternate "lost phone" tickets. Each support move is free (it doesn't restart the cooldown) and unbounded.
  - The only control is an alert above 2 moves per 90 days, and no runbook action is defined for it.
- **Insider:** one `support_agent` with MFA can do both, with no second approval. By contrast, catalog publish already has a second-operator rule (`security-model.md:82`).
- **Required change (T-136 endpoint and role, T-137 runbook and CLI, T-132 seat service):**
  1. **Ownership proof standard** in the runbook, enforced as a required request field `ownershipCheck ∈ {store_order_id, account_signin}`.
     - Store order ID: Play `orderId` / `latestOrderId`, or Apple's App Store Server API "Look Up Order ID". Compare on demand against the store API. Never persist the order ID. Record only `ownership_check` and its outcome in the audit `details`.
  2. **Server-side gate for attach:**
     - allowed only when the buying install is gone (`purchases.install_id IS NULL`) or has not synced for ≥ 30 days;
     - otherwise `409 ADMIN_CONFLICT`, and the owner must link from the buying phone (D-54).
     - Drop "current holder, for attach alone" unless the same gate applies.
  3. **Two-person approval** for every `attachToAccount` and for any support move beyond the first per purchase in 30 days, through `zaghlol-ops support move` → `approve` by a second `support_agent`.
  4. **An audited correction path:** `seat:move` back, plus `detach` and re-attach, so a mistaken or fraudulent attach can be reversed.
  5. **Hard cap:** at most 1 support move per purchase per 30 days without a second approver. The alerts get a runbook action.
  6. **Victim notice:** the previous holder's `status: moved` copy for a support move says so and shows the support link. This needs a `movedBy: support` claim or equivalent, with no operator data.

#### R3-3 (Minor): the account-attach reclaim can be repeated by deleting and re-creating the account
- **Where:**
  - ADR-012:82 ("at most once per account link")
  - `backend-api.md:284`
  - `backend-schema.md:76` (`account_id … ON DELETE SET NULL`)
  - `backend-api.md:308`
- **Path:**
  1. On the buying install: sign in (attach, free reclaim), then `DELETE /v1/accounts/me`. `account_id` goes back to NULL.
  2. Sign in again: the server creates a new account row, attaches, and reclaims again for free.
- **Impact:** the bound is per link, not per purchase. The buying install can pull Gold back from another phone any number of times. This breaks D-52(b) literally, though only in the buyer's favour.
  - It does not raise total Gold-days. The other direction still spends the cooldown. With the 14-day overlap, the buyer gets about 30/30 days and one other phone about 14/30.
- **Required change (T-132 / T-135):**
  - Persist `purchases.attach_reclaim_used_at` and don't clear it when the account is deleted.
  - Allow the free reclaim once per purchase. Later attaches are seat moves under the normal cooldown.
  - Or the PO accepts the residual, and ADR-012:82 is reworded to say so.

#### R3-4 (Minor): the pending claimant is a single "last writer" slot, and `MOVE_COOLDOWN` reveals the exact time of the last move
- **Where:** `backend-schema.md:125` ("last install refused only by the cooldown"); `backend-api.md:202`; `zaghlol-v1.yaml:1666`.
- **Paths:**
  - A token holder can keep re-probing during the cooldown (up to 10/day per purchase) and overwrite the real owner's claim. Support then refuses the owner's new phone with `409 ADMIN_CONFLICT` until the owner retries restore.
  - Each 409 returns `nextMoveAt` to the second, so `last_moved_at` is exact. That tells a co-holder of the store account precisely when the owner changed phones.
  - The oracle is otherwise inherent to D-52. Only installs that pass attestation, store and account checks reach it. For account-linked purchases, `account_required` takes precedence (`backend-api.md:200`).
- **Required change (T-132, T-136):**
  - Keep up to 3 claimants per purchase, each for 7 days (a small table, or a JSON array of `{install, at}`). Support must pick one explicitly, and the lookup marks each.
  - Round `nextMoveAt` up to the next whole UTC hour or day in the 409 and in the token, and enforce the rounded value server-side so the two agree. The app shows a date anyway.

#### R3-5 (Minor): a sign-in that ends in `409 MOVE_COOLDOWN` rolls back the attach from the buying phone
- **Where:** `backend-api.md:280` ("nothing is written, the link included") with steps 3–5 (`backend-api.md:283-285`).
- **Path:**
  1. An unlinked purchase's seat sits on another install of the owner that is already linked to account A.
  2. The buying phone signs in to A. Attach succeeds and the seat stays (step 4).
  3. Step 5 tries to move the seat to the buying phone, and the cooldown refuses it. This install holds no Gold, so the call returns 409 and the attach rolls back.
  4. D-54 makes this the only self-service link path, so the owner can't protect the purchase during the cooldown. A leaked-token holder can use that window.
  - Also, the `replay_guard` insert must not be in the transaction that rolls back. Otherwise the same ID token plus raw nonce stays usable within its 10-minute `iat` window after a 409.
- **Required change (T-135):**
  - Commit the account upsert, the link, the attach and the reclaim independently of the step-5 move result. Return 200 with no Gold and `nextMoveAt`, or document a 409 that still links.
  - Insert into `replay_guard` before, and outside, the seat transaction.

#### R3-6 (Minor): idempotency hardening
- **Where:** `backend-api.md:16`; `backend-schema.md:155-163`, `backend-schema.md:275`; `backend-api.md:64-68`.
- **Issue (a), unauthenticated `registerInstall`:** this record is keyed by the **body** `installId`, and its stored 201 contains the `installToken`. The install ID is now shown in the app as the "support code" and handed to support (`error-handling-and-observability.md:28`; `backend-api.md:395`). The only remaining secret is the 80-bit random part of the client's ULID `Idempotency-Key`. Anyone who learns the install ID, the key and the exact body within 24 h gets the token.
- **Issue (b), purge timing:** `RetentionPurger` runs daily, so rows can live up to about 48 h unless lookups also enforce `expires_at`.
- **Issue (c), stale credentials after deletion:** after `DELETE /v1/installs/me` or `DELETE /v1/accounts/me`, stored sign-in bodies (with `accountToken`) stay for up to 24 h.
- **Required change:**
  - App: generate `Idempotency-Key` with `Random.secure()`. Never log it; header logging is already off (`error-handling-and-observability.md:64`).
  - Server: every lookup requires `expires_at > now()`.
  - Install and account deletion delete that install's `idempotency_records`.
  - Server: reject an `accountToken` whose account no longer exists.
  - Owners: T-122 (schema), T-139 (purger), T-135, and the app's API-client / install-registration task.

#### R3-7 (Minor): a plan change from another install is a move that skips the cooldown
- **Where:** ADR-012:83 ("Upgrade chains … Its seat binds to the buying install like any verify").
- **Path:** someone with the store account upgrades or downgrades the plan (new token with `linked_purchase_token`) on their own phone. The successor's seat binds there, and the predecessor's seat on the owner's phone stops granting Gold. The holder changes without spending or checking the cooldown. The proration cost bounds this.
- **Required change (T-130/T-132):**
  - When the successor's buying install differs from the predecessor's holder, record it as a move (`last_moved_at = now`, `seat_move:verify`). Never refuse it, because this is the payment path (BR-GOLD-06).
  - Or the PO accepts the residual explicitly.

#### R3-8 (Minor; CI-dependent): the vector test only checks itself
- **Where:** `backend/tests/Zaghlol.Contract.Tests/RestoreBindingVectorTests.cs:59-180`.
- **Issue:**
  - The test checks a test-local canonicalizer and a test-local strict parser, not the production pipeline.
  - Default System.Text.Json accepts duplicate properties (last wins). The production rejection must be configured explicitly, for example `AllowDuplicateProperties = false` on .NET 10, or a reader pre-pass.
  - The invalid vectors cover only a top-level duplicate.
- **Required change:**
  - Add nested-duplicate vectors: inside a `purchases[]` item, and inside `attestation`, which is excluded from the hash but bound to the DTO.
  - T-132 adds an endpoint-level test that posts every `invalid` vector to `/v1/purchases/restore` and expects `400 VALIDATION_FAILED`.
  - T-145 adds the Dart counterpart.
  - Confirm on the first green CI run that the file compiles under `TreatWarningsAsErrors`.

#### R3-9 (Minor): operator CLI sign-in for the highest-value role
- **Where:** `backend-api.md:53`, `backend-api.md:404`; `security-model.md:18`.
- **Issue:** `support_agent` can now move and attach paid entitlements. The device-code flow is a known phishing vector: an attacker sends an operator a code to approve.
- **Required change (T-136/T-137):**
  - Require phishing-resistant MFA (FIDO2) for `support_agent` instead of "preferred".
  - Restrict the device-code grant with IdP conditional access (managed devices or named network), or use auth-code + PKCE with a loopback redirect.
  - Keep `support_agent` assignments to named staff, and review them quarterly.

#### R3-10 (Info): sharing within the rules, for PO awareness
- Two phones that share a store account can alternate one move per 30 days. After each move, the losing phone stays offline and keeps Gold for 14 days. Each phone then has Gold about 44 of every 60 days, and both have it at once about 14 of every 30 days.
- With three phones in rotation, the total is about 1.47 phone-equivalents of Gold per purchase.
- This is inside D-52(d) as accepted, and only if R3-1 is fixed. Without that fix it is unbounded.
- Optional tightening, as a PO decision: `exp ≤ iat + 3 d`, grace 4 d. That still gives at least 6 offline days after a daily refresh, so FR-GOLD-04 (5 days) holds, and it cuts the overlap to 7 days. It means amending A-38.

### BR-SYNC-03 / egress check (D-45, D-48 amendments)
- Nothing new leaves the app towards the backend. The restore body is unchanged: the install ID enters only the hash, and is not sent as a new field. The Google `nonce` is already classified under D-48. `movedFromOtherPhone` and `nextMoveAt` are server-to-app only. The optional Play verdicts are off and ignored.
- The "support code" (install ID) is given by the user to support, outside the app–backend channel. The user starts it, and it is a permitted identifier.
- **Info:** the privacy notice should say that a support ticket links the install ID to the user's contact details in the helpdesk tool. T-137 should check whether the helpdesk vendor is a processor under PDPL (OQ-16).

### Regression check against round-1 fixes
- **No regressions.** Specifically checked:
  - Apple nonce: stricter now, and extended to Google.
  - Unknown fields are rejected on the new admin request (`SupportSeatMoveRequest` has `additionalProperties: false`, `zaghlol-v1.yaml:2871`).
  - `ticketRef` is a regex code, not free text, so no personal data reaches the audit row.
  - No personal data or credentials go in query strings. The admin move uses a POST body.
  - The support lookup still stores only the HMAC e-mail pseudonym. The new `SupportPurchase` returns no tokens, transaction IDs or other installs' IDs.
  - Alerts carry the purchase UUID only.
  - Verify still relies on the store binding, and acknowledgement keeps priority.
  - The restore buckets are kept. Dropping the basic-integrity 1/day bucket is justified by the cooldown.
- **Residual:** with root and spoofing modules, a device that fakes basic integrity could run a modified app. That reopens a small part of round-1 Finding 1, but it is bounded by one seat plus the cooldown per purchase. Accepted under R-19.

### Product-owner decisions needed
1. **OQ-19(a):** confirm that a reinstall or "Delete everything" counts as a new install and spends the move. I agree with the recommendation, and with rejecting Block Store and device identifiers.
2. **OQ-19(b):** confirm that a support move does not restart the window, **conditional on R3-2's hard cap and two-person rule**. Without them, (b) makes support an unlimited bypass.
3. **Ownership-proof standard for support (R3-2):** what a user must show (store order ID or sign-in), and whether support attach needs two people. I recommend yes.
4. **R3-3:** cap the free account-attach reclaim to once per purchase (recommended), or accept the repeatable reclaim.
5. **R3-7:** count a plan change made from another install as a move (recommended), or accept it.
6. **R3-10:** accept the 14-day offline overlap, or tighten to about 7 days (amends A-38).

### Verdict
**CHANGES_REQUESTED.**
- All ten round-2 findings are resolved in the design. R2-6 still needs its first green CI run.
- Before approval, the architect must specify:
  - R3-1: trusted-time expiry on the device (T-144 contract and security-model threat row).
  - R3-2: ownership proof, the server-side attach gate, two-person approval, a correction path and a hard cap for the support move.
- R3-3 … R3-9 are minors. Each may be fixed in this branch or carried into its named owner task's acceptance criteria. If carried, each must be logged on that task before merge.
- Re-review scope for round 4: the R3-1 and R3-2 text changes, any PO decisions above, and the first CI run that includes `RestoreBindingVectorTests`.
