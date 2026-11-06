# FU-api-decisions round 4: task impacts (from the architect's report, 2026-11-06)

Branch `task/FU-api-decisions` @ `9ae53aa`. Not CI-verified (BLK-05). Apply these impacts to the task files when the branch merges.

## Existing tasks
- **T-122**: new schema objects:
  - `purchase_seats.next_move_at` and `device_key_hash`
  - new table `seat_claimants`
  - `purchases.attach_reclaim_used_at` and `account_linked_by`
  - `installs.registration_key_hash` and `registration_body_sha256`
  - `idempotency_records.account_id`
  - new KMS key `K_seat`
  - audit action `support_detach`
- **T-130**: Play `orders.get` for the support ownership check.
- **T-131**: App Store "Look Up Order ID".
- **T-132**: the seat service:
  - rebind (D-55), the cooldown rounded up to the hour, claimants (up to 3 for 7 days)
  - plan change: moves Gold, or leaves it in place inside a cooldown (D-59/D-61a)
  - the free reclaim, once per purchase, which counts as the move
  - the `moved`, `movedBy` and `paused` tokens
  - token lifetimes: 3 d (2 d for basic seats) plus 4 d grace
  - seat-proof verification
  - strict JSON, with an endpoint test for every invalid vector
- **T-135**: sign-in and sign-out:
  - sign-in returns 200 with `moveRefused`
  - the `replay_guard` insert stays outside the seat transaction
  - tokens for a deleted account get 401
  - sign-out returns 200 with an entitlement
  - deleting an account purges its idempotency records
  - `registerInstall` issues a fresh token on retry
- **T-136**:
  - FIDO2 checked through the `amr` claim
  - `ownershipCheck`, the attach gate, correction and detach
  - audit records and alerts
- **T-137**: the CLI and its operation:
  - auth-code + PKCE, and a prompt for the order ID that does not echo it
  - runbook actions and a quarterly role review
  - a PDPL check of the helpdesk vendor
- **T-139**: purges for the `support_detach` audit rows, the claimants and expired idempotency rows.
- **T-144**: on the app side:
  - trusted time and its unit tests (clock rollback, reboot, offline)
  - a 12-hour refresh
  - the `paused` state, and dropping the token on sign-out
  - `movedBy`
- **T-145**:
  - iOS `attestation.seatKeys`
  - a strict Dart parser, tested against the invalid vectors
  - a CSPRNG idempotency key
  - the Android "Delete everything" warning
- **T-147**: `seatKeys` at sign-in, and the user experience for `moveRefused`.

## New tasks to add to the board
- **Native, C4 (Opus, native-platform-engineer)**:
  - `AttestationHostApi`: Play Integrity standard request; App Attest with an install-bound key and assertion
  - `SeatKeyHostApi`: Secure Enclave P-256 key, held in the Keychain as ThisDeviceOnly
  - `TrustedClockHostApi`: monotonic clocks, `BOOT_COUNT`
  - release builds use a `network_security_config` that trusts system CAs only
  - device tests: the seat key survives a reinstall; the monotonic clock keeps counting during sleep
- **Backend, C4 (Opus, backend-engineer)**: attestation and seat-key verifiers, with fakes:
  - Play Integrity decode, ignoring the optional verdicts
  - App Attest attestation and assertion checks (CBOR, X.509, counter)
  - ECDSA verification of the seat key

## Still needs CI
- `SeatProofVectorTests.cs` and `DuplicateVectorsAreRejectedByTheFrameworkStrictOption` must compile and pass on net10.0.
- The `None Update` copy steps for the vector files.
- The existing T-006 contract tests must pass against the edited OpenAPI.

## Round 5 additions (architect, 2026-11-06)

Branch `task/FU-api-decisions` @ `2b8ccfd` (main merged at `8e77ece`). Not CI-verified (BLK-05). Covers R4-1…R4-8 and D-62…D-65.

### Existing tasks
- **T-122** (schema):
  - `installs.seat_key_hash` and `installs.seat_key_trusted`
  - `purchase_seats.recent_rebinds` (timestamptz[], at most 2) and `purchase_seats.device_key_trusted`
  - `purchases.dispute_frozen_until` and `purchases.support_link_notice_pending`
  - `purchase_events.cause` values `seat_rebind_over_cap:<restore|signin>`
  - audit `outcome` value `dispute_frozen`, `ownership_outcome` value `not_run`
- **T-130**: confirm `orders.get` is available to the developer account and returns `purchaseToken`; otherwise implement the `subscriptionsv2.latestOrderId` (over the `linkedPurchaseToken` chain) / `productsv2` order-ID fallback.
- **T-132** (seat service):
  - element-0 registration per install; `400 SEAT_KEY_MISMATCH` on restore and sign-in; ignore on verify
  - rebind only from a `seatKeys` position ≥ 1; the seat's hash becomes the caller's registered key
  - D-63 cap (2 per purchase per rolling 30 days) and the D-65(a) over-cap rebind (never refused, window restarts); for sign-in only with a trusted seat key, else an ordinary move with `restoreSuggested`
  - the `seat_rebind` alert
  - plan-change account rule: `accountRequired` and a claimant, seat never moved without the account token (R4-4)
  - restore: verify the App Attest assertion over the new `clientDataHash` (seat public keys folded in); pass the extended `restore-binding-v1.json` vectors
  - echo `Zaghlol-Time-Nonce` as `timeNonce` in every signed 200 of sync (throttle included), entitlement, verify, restore, sign-in and sign-out; validate its pattern; never log it
  - `supportNotice` delivery to the buying install, cleared once sent
- **T-135**: sign-in runs the element-0 check before linking; `restoreSuggested` in the response; sign-out echoes `timeNonce`.
- **T-136**:
  - FIDO2 enforced by IdP conditional access scoped to the `zaghlol-ops` and admin clients; confirm on the chosen IdP which claim proves it (Entra `acrs` authentication context; Entra `amr` has no FIDO2 value; Google Workspace generally none). If none, document the API check as advisory
  - dispute freeze (D-64, D-65(b)): `409 ADMIN_CONFLICT` for non-correction moves and links, checked before the ownership call, audited as `dispute_frozen`; each correction restarts it
  - support attach sets `support_link_notice_pending`; detach clears it
  - lookup fields `isBuyingInstall`, `disputeFrozenUntil`, `rebindsLast30Days`
  - alerts: `dispute_frozen` refusal, `seat_rebind`
- **T-137**:
  - privacy notice and store disclosures per security-model §2a: D-62 same-iPhone linkability in transit; R4-8 (iOS "Delete everything" keeps the seat keys on the phone and a keyed hash on the server); the time nonce; the support-link notice
  - runbook: `seat_rebind` and `dispute_frozen` alert actions; prefer the claimant that is the purchase's buying install (R4-7(3)); record the IdP FIDO2 policy as the control (R4-6)
- **T-139**: nothing new to purge beyond the install row (`seat_key_hash` goes with it); prune `recent_rebinds` is done inline.
- **T-144** (trusted time):
  - the time nonce: CSPRNG, one outstanding, 60 s, same boot; only the echo lowers `hw`/`lb` or clears `tampered`; every other signed time raises only
  - the uncharged bound `lb` for the tamper test; the 6 h charge to `hw` only; iOS boot-reference shift with `m ≥ mono` charges `max(m − mono, 6 h)`
  - required unit tests: another install's signed body; a withheld older response; a reused echo; an idempotency replay; an honest quick offline reboot (and the following advances); an iOS wall correction without reboot
  - `supportNotice` one-time message
- **T-145**: iOS restore computes `clientDataHash = SHA-256("zaghlol-restore-attest-v1" ‖ 0x00 ‖ bodyHash ‖ SHA-256(pk₀‖…‖pkₙ₋₁))` for both the assertion and `attestKey`; one retry without `seatKeys` on `SEAT_KEY_MISMATCH`; Dart must pass the new vector fields.
- **T-147**: sign-in retries with a fresh nonce and no `seatKeys` on `SEAT_KEY_MISMATCH`; `restoreSuggested` UX; verify `accountRequired` UX.

### New tasks (already listed above), additions
- **Native C4**: the device test proves the Keychain item **and** its Secure Enclave key survive app deletion and reinstall (sign/verify after reinstall) on the oldest and newest supported iOS (R-19, SRS v1.7); `publicKeys()` keeps the same own key for the install's life.
- **Backend C4 verifiers**: App Attest assertion over the extended `clientDataHash`; seat-key verification with distinct keys and the element-0 registration hash.

### Still needs CI (round 5)
- `RestoreBindingVectorTests.IosClientDataHashCoversTheSeatPublicKeysInOrder` (new) and the existing vector tests against the extended `restore-binding-v1.json`.
- `SpecContractTests.TimeNonceIsSentAndEchoedExactlyOnAnchoringOperations` (new) and `SignedResponsesCarryTheSignatureHeader` with `signOut` added.
- `DocumentationConsistencyTests` with the new `SEAT_KEY_MISMATCH` code.
