# FU-api-decisions: Security and Privacy Review

**Reviewer:** security-privacy-reviewer · **Branch:** `task/FU-api-decisions` @ `478b0a9`
**Scope:**
- Round 5 was `git diff 9ae53aa d296a7f -- docs/03-technical backend`.
- The round-5 delta is `git diff d296a7f 478b0a9`.
- The cumulative design is `git diff e47127e...origin/fuapi`.
- Checked against SRS v1.7 on main: D-48 (v1.7 addendum), D-62…D-65, NFR-SEC-08, BR-SYNC-03 and NFR-PRIV-07.

**Final verdict: APPROVED.**
- R5-1, the only blocking finding, is resolved.
- All round-5 minors are resolved or written in as residuals with owners.
- The new unfreeze endpoint introduces one minor (R6-1), which goes to T-136 and does not block the merge.
- R5-3 still needs a PO choice between options (a) and (b). Either choice is compatible with approval.

---

## History

**Round 1 (2026-11-05): CHANGES_REQUESTED.**
- 2 blockers: a shared restore token gave Gold to unlimited installs, and the Apple sign-in nonce was not checked.
- 4 majors, plus minors. Fixed at `8fe1251`; findings 1 and 9 led to D-45…D-47 and ADR-012 Part B.

**Round 2 (2026-11-05): CHANGES_REQUESTED.**
- 1 blocker: R2-1, the attestation was bound to the body and not to the install.
- 3 majors and minors (R2-2…R2-10). The PO replaced the 3-seat model with D-52…D-54 (SRS v1.5).

**Round 3 (2026-11-06): CHANGES_REQUESTED.**
- Majors:
  - R3-1: the offline bound depended on the wall clock.
  - R3-2: support could act on insufficient proof.
- Minors R3-3…R3-9, info R3-10. The PO answered with D-55…D-61 and NFR-SEC-08 (SRS v1.6).

**Round 4 (2026-11-06): CHANGES_REQUESTED.**
- Majors:
  - R4-1: the seat-key proof could be relayed.
  - R4-2: a replayed signed server time.
- Minors R4-3…R4-5, info R4-6…R4-8. The PO answered with D-62…D-65 (SRS v1.7). D-62 explicitly accepts linkability in transit.

**Round 5 (2026-11-06, at `d296a7f`): CHANGES_REQUESTED.**
- R4-1 and R4-8 were resolved, or accepted by the PO under D-62.
- New major R5-1, pre-existing since round 1: the app didn't bind an entitlement token to its own install.
- Minors R5-2…R5-5, info R5-6…R5-9.
- The sign-in deviation from D-65(a) was evaluated: the gate is necessary, and the PO accepted it.

**Round 5 delta (2026-11-06, at `478b0a9`): APPROVED.** See below.

---

## Round 5 (at `d296a7f`): summary

### Resolution of round-4 findings
| ID | Status at round 5 |
|---|---|
| R4-1 (major) | **Resolved for restore. Bounded for sign-in, within the D-63 cap.** Element 0 is registered once per install (`SEAT_KEY_MISMATCH` otherwise). A rebind needs a match at position 1 or later, and the seat then follows the caller's registered key. `recent_rebinds` ≤ 2. The App Attest `clientDataHash` covers the seat public keys in order. The residual is documented. |
| R4-2 (major) | **Resolved.** A 128-bit `Zaghlol-Time-Nonce` is echoed in the signed body. Only the single outstanding nonce, echoed within 60 s on the same boot, may lower `hw`/`lb` or clear `tampered`. Everything else is raise-only. |
| R4-3 (minor) | **Resolved.** New `lb` bound for the tamper test; the 6 h charge goes to `hw` only; the iOS boot-reference shift is charged `max(m − mono, 6 h)`. |
| R4-4 (minor) | **Resolved.** The account rule is checked first on a plan change, with `accountRequired: true`. |
| R4-5 (minor) | **Accepted by the PO (D-62).** The ADR claim is corrected. |
| R4-6 (info) | **Resolved.** IdP conditional access is the control; the API's `acrs` check is advisory. |
| R4-7 (info) | **Addressed per D-64 / D-65(b).** Dispute freeze, `supportNotice`, the buying-install preference, and the `orders.get` fallback. |
| R4-8 (info) | **Resolved.** The privacy notice is in `security-model.md` §2a. |

### The sign-in deviation (opinion given to the PO)
- **The gate is necessary.** On stock iOS a user-CA proxy can rewrite unattested sign-in bodies, including element 0 as a software key. Over-cap rebinds ignore the cooldown, so without the gate people sharing account credentials could swap Gold without limit.
- **The owner was not truly "never locked out".** Restore, the suggested fallback, needs a StoreKit transaction on that iPhone, and Play-bought or other-Apple-ID Gold has none (R5-3).
- **Recommendation:** accept the gate, together with either (a) an optional App Attest assertion on iOS sign-in, or (b) an explicit residual.

### Round-5 findings
| ID | Severity | Finding |
|---|---|---|
| R5-1 | **Major (blocking)** | The app honoured any validly signed entitlement token. A proxy on stock iOS could relay the holder's token, or its account token, to any number of phones. |
| R5-2 | Minor | "Trusted" seat keys could be set by a proxied verify. The sign-in rebind budget needs no jailbreak on stock iOS, and the docs said otherwise. |
| R5-3 | Minor | The over-cap sign-in fallback (Restore) doesn't exist for Play-bought or other-Apple-ID Gold, so the owner can be refused for up to 30 days. |
| R5-4 | Minor | A support move didn't say what happens to `device_key_trusted`. |
| R5-5 | Minor (PO) | (a) The freeze doesn't stop correction ping-pong. (b) An owner who loses the phone after a correction has no path for up to 30 days. |
| R5-6 | Info | `SEAT_KEY_MISMATCH` ordering and app behaviour. It is not an oracle: it compares only against the caller's own key. |
| R5-7 | Info | `supportNotice` was cleared when sent, not when delivered. |
| R5-8 | Info | The Play fallback used the deprecated `latestOrderId`. |
| R5-9 | Info (doc) | (1) per-install keyed hash and (2) verify-time `seatKeys`, both versus the D-62 / BR-SYNC-03 wording; (3) stale `ownership_outcome` list in ADR-012. |

---

## Round 5 delta (`d296a7f` → `478b0a9`)

### CI status
**CI has run, and I confirmed it myself.**
- `backend-ci` run 42207189180 on `0b778cb` concluded `success`. All 5 jobs passed: vulnerable packages; build, format, test; OpenAPI lint (Spectral); image, non-root, scan; docker compose `/v1/health`.
- In the "build, format, test" job log, `Zaghlol.Contract.Tests` reports **34 passed, 0 failed**.
- The count matches the 34 `[Fact]`/`[Theory]` attributes on the branch (Documentation 5, LiveApi 6, RestoreBinding 5, SeatProof 3, SpecContract 15).
- `git diff 0b778cb 478b0a9` touches only `docs/03-technical/testing-strategy.md`, so the result carries over to `478b0a9`.
- **What I could not see:** the log uses normal verbosity, so it doesn't name each test. That the named tests (`IosClientDataHashCoversTheSeatPublicKeysInOrder`, `DuplicateVectorsAreRejectedByTheFrameworkStrictOption`, `SeatProofVectorTests`, `TimeNonceIsSentAndEchoedExactlyOnAnchoringOperations`, `AdminOperationRolesMatchTheSpecRequiredRoles`) are among the 34 rests on the attribute count and the file contents, not on per-test log lines.
- **Effect:** R2-6, R3-8, the R4-1(3) vectors and the R4-2 contract test move from "resolved in spec, CI pending" to **resolved, verified by CI**.

### Resolution of round-5 findings
| ID | Status | Evidence |
|---|---|---|
| R5-1 (major) | **Resolved** | `backend-api.md` §4.3 *App rules*: an entitlement token is honoured only if `sub` equals this install's current ID, compared as an exact string, and an account token only if `iid` does. A failing token is ignored: not cached, grants nothing, doesn't replace the cached token, only increments a diag counter, and nothing is logged. A body carrying such a token is raise-only for time, even with a fresh nonce echo. The fresh-echo rule now requires every token in the body to pass the binding. On `INSTALL_TOKEN_INVALID` both tokens are deleted *before* re-registration (§6). T-144 tests cover a foreign-`sub` token with the app's own fresh echo, a foreign-`iid` account token paired with a matching `acct`, and an old-`sub` replay after re-registration. Also corrected: ADR-012 (d) "Transport", `security-model.md` (Gold entitlement row), and the testing-strategy sandbox case "second iPhone behind a proxy fed the holder's body". This closes the stock-iOS relay. |
| R5-2 (minor) | **Resolved** | `seat_key_trusted` is set only by an App Attest-covered request: a restore, plus an attested sign-in only if the PO picks R5-3(a). Verify and plain sign-in register the key untrusted. The flag only goes from false to true (§4.3 *Trusted registration*, step 5 of verify, `backend-schema.md` installs). ADR-012 (g), `backend-api.md` §4.3 / §4.6 and `security-model.md` now say that a proxy on stock iOS can drive the sign-in rebinds, and that the jailbreak / oracle precondition applies to restore only. |
| R5-3 (minor) | **Option (b) is written in as an accepted residual; still pending a PO choice of (a) or (b)** | §4.3 and ADR-012 (g) state the up-to-30-day refusal for Play-bought or other-Apple-ID Gold. With `restoreSuggested`, the app checks StoreKit (`Transaction.currentEntitlements` / `Transaction.all`): it offers Restore only when there is a transaction, and otherwise shows `nextMoveAt` and the support path (T-147, T-145, plus a sandbox test). Option (a) is drafted correctly as "Pending PO", with no schema change. Its `clientDataHash` (`"zaghlol-signin-attest-v1"‖0‖installId‖SHA-256(nonce)‖seatKeysDigest`) binds the install, the single-use nonce and the keys. A missing or invalid assertion never fails sign-in; it only leaves the key untrusted. I endorse that draft as written. |
| R5-4 (minor) | **Resolved** | A support move sets `device_key_trusted` from the target install's flag. It is false whenever `device_key_hash` is `NULL` and on a move back, and it is never kept from the previous holder (§5.3, `backend-schema.md` purchase_seats). Three T-132 / T-136 tests are specified. |
| R5-5 (minor) | **(a) accepted residual; (b) resolved by the PO's choice of `purchase:unfreeze`** | See the unfreeze review below and R6-1. |
| R5-6 (info) | **Resolved** | On restore, the element-0 check runs after App Attest, in the same transaction as the counter update, and a mismatch rolls back both. A replayed assertion can only repeat the same mismatch, because the registered key never changes. After a confirmed mismatch the app persists "own seat key unusable" and stops sending `seatKeys` from that install (`backend-api.md` §4.3, §6; `platform-channels.md` §4b). |
| R5-7 (info) | **Resolved** | The notice repeats, each time with a fresh token whose `iat` goes into `support_link_notice_iat`. It clears only when a later `POST /v1/sync` sends `entitlementIssuedAt ≥ support_link_notice_iat`. The app keeps the notice in `secure_state` until the user dismisses it. Nothing new is sent by the app: `entitlementIssuedAt` is an existing D-48 cursor. A client that falsely claims delivery can only suppress its own notice. Detach clears both columns. |
| R5-8 (info) | **Resolved** | The fallback now uses `lineItems[].latestSuccessfulOrderId`, and the deprecated `latestOrderId` is explicitly not used (`backend-api.md` §5.3, ADR-012 (f), T-130). |
| R5-9 (info) | **(3) resolved** (`not_run` in ADR-012 (f), and a new `DocumentationConsistencyTests` check). **(1) and (2) remain SRS wording** for the PO's next revision. They add no privacy risk. |

### Review of the new `POST /admin/v1/support/purchase:unfreeze`
**Checked with no finding:**
- **Role and authentication:** role `support_lead`, with the same FIDO2 / IdP conditional-access control as `support_agent`. Named staff, reviewed quarterly. `x-required-roles: [support_lead]` and `operatorOidc` security are present in the OpenAPI, and `AdminOperationRolesMatchTheSpecRequiredRoles` is among the passing tests.
- **Request shape:** `SupportUnfreezeRequest` has `additionalProperties: false`. `ticketRef` uses the existing regex, so no free text. `ownershipCheck` uses the shared `OwnershipCheck` schema, so the order ID is never stored, logged or audited, and the CLI reads it from a no-echo prompt.
- **Order of checks:**
  - With no freeze running, the call is a `noop` with `ownership_outcome: not_run` and no store call. It reveals only `disputeFrozenUntil`, which the lookup already shows.
  - The different-operator check runs before the store call, so a refused unfreeze leaks nothing about the order ID.
  - Then the live ownership check, then `dispute_frozen_until = NULL`.
- **Effect:** it moves nothing. Seat, account, window, rebinds and claimants are unchanged, and a T-136 test checks this. So an unfreeze alone can't grant or remove Gold.
- **Audit and alert:**
  - Every call writes a `support_unfreeze` row (`freeze_audit_id`, `frozen_until`, outcome), kept for 1 year and included in the `RetentionPurger` action list.
  - Every call alerts the support-lead group, and a second lead reviews within 2 business days. An unfreeze followed by a move also falls under the >2-moves review.
- **Abuse by the attacker the freeze was meant to stop:** someone with store-account access still needs a lead to agree, and the lead's action is alerted and reviewed. This is strictly better than R5-5(b)'s gap, and no worse than the PO's single-agent baseline.

#### R6-1 (Minor, T-136 / T-137): the different-operator rule doesn't stop one operator from undoing a correction alone
**Where:** `backend-api.md` §5.3 *Unfreeze*: "the caller must not be the operator of the correction that started the current freeze", and "An ordinary support move (by any `support_agent`, the lead included if they hold that role) can then follow".

**Path:**
1. Agent X makes a wrongful move M1, either socially engineered or as an insider.
2. A different agent Z corrects it, which starts the freeze.
3. If X also holds `support_lead`, X passes the different-operator check, because only Z is excluded.
4. X unfreezes and then repeats M1 with `seat:move`, alone.
5. The same applies to any lead who holds both roles: unfreeze plus move is a one-person action that overrides a colleague's correction.

**What contains it:** the unfreeze alert, the second-lead review within 2 business days, the >2-moves alert, `movedBy: support` shown to the losing phone, and the correction path. So it is bounded and detected, not prevented.

**Required change (T-136, acceptance criteria; it does not block this merge). Make both rules server-side:**
- The unfreezing operator must differ from the operator of the correction that started the freeze **and** from the operator of the row that correction reversed (`corrects_audit_id`).
- For 24 h after an unfreeze, the unfreezing operator may not perform the next non-correction `seat:move` on that purchase (`409 ADMIN_CONFLICT`, audited).
- Alternatively, T-137 makes `support_lead` and `support_agent` disjoint role assignments, and the quarterly review checks this. The server-side rule is preferred, because role reviews drift.

### Regression check (delta)
- **No regressions found.** The delta changes no app-to-server field: the R5-3(a) sign-in assertion is a draft only, and `SignInRequest` is unchanged.
- The idempotency, strict-JSON, nonce, signing and alert rules are unchanged.
- Admin DTOs keep `additionalProperties: false`, and the new admin operation follows the existing response set (400–503).
- BR-SYNC-03: nothing new leaves the app. The diag counters `entitlement_sub_mismatch` and `account_iid_mismatch` are local only.

---

## Verdict
**APPROVED** at `478b0a9`.
- **Merge conditions:** none beyond the items below, which are carried as owner-task acceptance criteria or PO decisions.
- **Owner-task acceptance criteria:**
  - R6-1: T-136 / T-137.
  - R5-3: T-147 / T-145 for option (b) as written, or T-135 / T-147 / T-131 if the PO picks (a).
  - The R5-1 tests: T-144.
  - The R5-2 and R5-4 tests: T-132 / T-136.
  - The R5-6 app flag: T-145 / T-147.
  - The R5-7 delivery proof: T-136 / T-144.
  - R5-8: T-130.
  - The privacy notice and store disclosures: T-137.
- **SRS wording** (R5-9(1)–(2)): at the next revision.
- **Device-dependent checks, which CI can't cover:** the Secure Enclave key surviving reinstall, `CLOCK_MONOTONIC_RAW` across sleep, `BOOT_COUNT`, and the StoreKit check for `restoreSuggested`. These stay on the C4 app task and the store sandbox plan.

## Acceptable residuals (accepted or for the PO to accept, with owners)
1. **Sign-in rebind budget on stock iOS behind a proxy** (R5-2, D-63): up to 2 cooldown-free rebinds plus 1 over-cap hop per purchase per 30 days for people sharing account credentials. A key is trusted only after an App Attest-covered request. Owner: T-132, with `seat_rebind` alerting.
2. **Two jailbroken iPhones that pass App Attest swapping by restore past the cap**, one holder at a time, each swap alerted (R-19). A jailbroken participant can patch the app anyway. Owner: T-132 / T-137 runbook.
3. **Undetected iOS reboot** gaining time the app wasn't running, slightly widened by R4-3(b) by up to `mono` per cycle (ADR-012 (h)). Owner: T-144.
4. **Same-iPhone install linkability in transit** (D-62, accepted by the PO). Owner: T-137 disclosures.
5. **Correction ping-pong under single-agent support** (R5-5(a)), contained by alerts and lead review. Owner: T-137.
6. **One operator holding both support roles can unfreeze and move alone** (R6-1), until the T-136 rule lands. Detected by the unfreeze alert and second-lead review. Owner: T-136 / T-137.
7. **R5-3: PENDING A PO CHOICE between (a) and (b).**
   - Under (b), as currently written: a Play-bought or other-Apple-ID owner can be refused on the holding iPhone for up to 30 days after a third reinstall within 30 days. The app shows the support path and `nextMoveAt`, and support (with unfreeze if needed) can move the seat. Owner: T-147 / T-145.
   - Under (a), the recommended option, this residual disappears for honest apps, and stripped requests fall back to the gate. Owner: T-135 / T-147 / T-131, plus a `signin-attest-v1` vector set.
8. **`supportNotice` delivery** relies on the buying install syncing again. This is now robust to a lost response or a crash; at worst a client suppresses its own notice (R5-7). Owner: T-136 / T-144.

**No longer a residual:** R5-1 (token relay), R5-4 (trust inheritance), R5-5(b) (no support path during a freeze) and R5-8 (deprecated Play field) are resolved.

## PO decisions needed
1. **R5-3:**
   - Option (a), recommended: approve the optional App Attest assertion on iOS sign-in, with a one-line amendment extending D-45 / FR-GOLD-09 attestation to iOS sign-in (same BR-SYNC-03 data class). The architect's draft is security-sound as written.
   - Option (b): formally accept residual 7.
2. **R6-1 (optional):** choose either the server-side rule (recommended) or disjoint `support_lead` / `support_agent` assignments. Either way it is recorded as a T-136 / T-137 acceptance criterion.
3. **R5-9(1)–(2):** at the next SRS revision, note the per-install keyed hash `installs.seat_key_hash`, and `seatKeys` element 0 being sent on verify, in BR-SYNC-03 / D-62 / NFR-PRIV-07.

**Relevant files (at `origin/fuapi` = `478b0a9`):**
- `/home/claude/zaghlol/docs/03-technical/backend-api.md` (§4.2 support-link notice; §4.3 *App rules*, *Trusted time*, *Same-iPhone recognition*; §5.3 *Unfreeze*; §6)
- `/home/claude/zaghlol/docs/03-technical/adr/ADR-012-purchase-verification-entitlements.md` ((d) Transport, (f), (g), Consequences)
- `/home/claude/zaghlol/docs/03-technical/backend-schema.md`
- `/home/claude/zaghlol/docs/03-technical/security-model.md`
- `/home/claude/zaghlol/docs/03-technical/platform-channels.md`
- `/home/claude/zaghlol/docs/03-technical/error-handling-and-observability.md`
- `/home/claude/zaghlol/docs/03-technical/testing-strategy.md`
- `/home/claude/zaghlol/backend/openapi/zaghlol-v1.yaml` (`adminUnfreezePurchase`, `SupportUnfreezeRequest`)
- `/home/claude/zaghlol/backend/tests/Zaghlol.Contract.Tests/DocumentationConsistencyTests.cs`
- `/home/claude/zaghlol/backend/tests/Zaghlol.Contract.Tests/RestoreBindingVectorTests.cs`
- `/home/claude/zaghlol/backend/tests/Zaghlol.Contract.Tests/SpecContractTests.cs`

**Sources:**
- [Google Play Developer API: `SubscriptionPurchaseV2.latestOrderId` deprecated, use `lineItems.latest_successful_order_id`](https://developers.google.com/android-publisher/deprecated-apis/latestOrderId.subscription.purchasev2)
