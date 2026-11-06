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
