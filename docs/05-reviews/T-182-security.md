# Security & privacy review — T-182 Backend seat-key proof verifier and keyed hashes (K_seat), with fakes

| Field | Value |
|-------|-------|
| Reviewer | security-privacy-reviewer (Opus) |
| Date | 2026-11-11 |
| Commit / diff | `origin/task/T-182-seat-proof` @ `f066e9b`; `git diff origin/task/T-182-design-note...f066e9b` (41 files, +9171 / −43; 5714 lines of that are the vendored Wycheproof file) |
| CI evidence | `backend-ci` on `ci/T-182` green (per the Lead's brief; I did not download the logs). |
| Local re-run | .NET 10 in `/home/claude/sdk`. Application seat/P256 tests 74/74 passed. Contract `SeatProof*`, `SeatKeyHash*`, `Wycheproof*` and `RestoreBinding*` 17/17 passed. Infrastructure `SeatKey*` 19/19 passed. The 5 other matches in that filter need Docker and failed with `DockerUnavailableException` only. |
| Independent checks | (1) I recomputed `installKeyHashHex`, `seatKeyHashHex` and `seatCheckHex` in `seat-key-hash-v1.json` with Python `hmac` from the documented inputs, and all three match. (2) I downloaded `testvectors_v1/ecdsa_secp256r1_sha256_p1363_test.json` and `LICENSE` from C2SP/wycheproof at commit `dab4ea2e…7d911`. The SHA-256 values are byte-identical to the vendored copies (`c60de693…c986` and `58d1e17f…d8bd`), so the pin in `WycheproofP256Tests` L15 matches upstream. (3) `seat-proof-v1.json` holds no private key material (grep for `d`/private/secret). |
| Inputs | `docs/04-tasks/tasks/T-182.md` (design note, implementation notes, deviations 1–8, PO Q1), `docs/03-technical/backend-api.md` §1 (idempotency) and §4.3 *Same-iPhone recognition*, `docs/03-technical/deployment.md` §3, `CLAUDE.md` §2 |
| Verdict | **APPROVED**. There are no Critical or High findings. There is 1 Medium finding, which concerns the provisional rotation runbook text and not code; it must be fixed before PO Q1 is closed or T-140 automates the procedure, but it does not block this merge. There are 2 Low and 6 Info findings. Nothing is marked "before merge". |

## Summary

The verifier is sound. It checks the point explicitly in managed code (prefix `0x04`, x, y < p, the curve equation) before the platform import. P-256 has cofactor 1, so any point that passes is in the prime-order group. That rules out invalid-curve and small-subgroup inputs. The point at infinity has no 65-byte `0x04` encoding, and (0,0) fails the equation because b ≠ 0. r and s are range-checked to [1, n−1] before `VerifyData`. Strict base64url (exact length, alphabet, decoder status, canonical re-encode) runs after a count cap and before any crypto. Platform exceptions map to rejections, so `Parse`/`Verify` stay total.

The signed message is `"zaghlol-seat-v1" ‖ 0 ‖ op ‖ 0 ‖ installId ‖ 0 ‖ challenge(32)`. The prefix and the op are NUL-terminated, and the install ID and challenge have fixed widths, so the encoding is injective. `installId` comes only from the token, the op is in the message, and `Verify` refuses a challenge whose op differs from the parsed op (L38). So a proof made for one op, install or challenge never verifies for another. The tests cover each case: AC 3.

The `K_seat` constructions use one dedicated KMS key. Their inputs have pairwise different fixed lengths (109/101/22) and different first bytes (`i`, a hex digit, `z`), and only verified keys reach them. The two hash types are distinct and compare in constant time. KMS failures propagate, and the startup check refuses a missing, malformed or mismatching `SeatCheck` or an unreachable KMS outside Development/Testing. No key, signature, hash, challenge or message bytes appear in logs, spans, metric tags or exception messages (sentinel test). Every type's `ToString` is `***`, and `seatKeys` is on the `LogFieldPolicy` drop list. Test support lives only in `Zaghlol.Testing` and is linked by `<Compile Include>` into test projects only. An architecture test over Domain, Application, Infrastructure, Api, Workers and Ops enforces that.

## Checks performed and results

| Area | Result | Evidence |
|------|--------|----------|
| Invalid-curve / off-curve / coordinates ≥ p | PASS | `P256.cs` L38–55 (`IsUncompressedOnCurve`), called first in `Check` L60. Constants are pinned against `ECDsa.ExportExplicitParameters` (`P256ConstantsTests`). A negative proof shows the explicit check is what the test pins, since OpenSSL import would also refuse. Malformed vectors cover `y+1` and `second-element-off-curve`. |
| Small subgroup | N/A (PASS) | The secp256r1 cofactor is 1, so every on-curve point except O has order n. |
| Point at infinity / all-zero / hybrid / compressed | PASS | Infinity can't be encoded as `0x04‖X‖Y`. The all-zero point fails the equation. `0x06`/`0x07` are refused in the parser (`SeatKeyProofVerifier.cs` L123) and again in `P256` L40. A 33-byte compressed key and a 64-byte truncated key fail the 87-character length check. All are in `malformed` vectors. |
| r, s = 0 / ≥ n | PASS | `P256.cs` L71–76. Vectors cover `r=0`, `s=0` and `r=n`. Wycheproof: 262 cases (173 valid, 89 invalid, 0 acceptable) through the production `VerifyP1363`. |
| Hash / format | PASS | `VerifyData(message, sig, SHA256, IeeeP1363FixedFieldConcatenation)` (L96). DER signatures fail at 86 characters (vector). |
| High-S accepted (malleability) | PASS (accepted, see I-1) | No signature is stored, hashed, used as an identifier or used as a replay key. Replay protection is the App Attest counter (restore), `replay_guard` on the nonce (sign-in) and the set-once registration (verify). None of them depends on signature bytes. A mauled signature changes the body hash, so it can't reuse another request's idempotency record (→ `409 IDEMPOTENCY_KEY_REUSED` for the same install and key). The restore `clientDataHash` covers public keys only, by design. |
| Domain separation of the proof | PASS | `Message` L64–82: fixed prefix, NUL-terminated op, 36-byte install, 32-byte challenge. Op/challenge mix-ups are blocked by `SeatChallenge` factories plus the L38 op check. Tests: another install, another op, another challenge, key B with key A's signature, second element signed with the first's signature. |
| Freshness / one-time use | PASS (enforced by consumers) | Nothing in T-182 enforces single use. That is correct, since this module is pure and the enforcement points are T-185 (App Attest counter, rolled back with the element-0 check), T-135 (`replay_guard` committed first) and T-184 (set-once registration). Verify proofs are reusable only by the same install, and a replay re-registers the same key (no-op). See I-2. |
| Every element verified / no partial acceptance | PASS | `Verify` L44–52 runs `Check` for every element and keeps the first reason. `VerifiedSeatKeys` exists only if every element passed. Negative proof: "only element 0 checked" goes red. |
| Timing / oracle | PASS | Every input to `Parse`/`Verify` is attacker-supplied public data. Early returns inside `P256.Check` and in the parser reveal only facts about the attacker's own input. No secret is involved until the MAC. Rejection reasons reach only the metric. Restore and sign-in callers answer a uniform `400 VALIDATION_FAILED`. `SEAT_KEY_MISMATCH` is distinct, but it needs a fully valid proof under the caller's own install token, so it reveals nothing about anyone else. |
| Keyed hashes: construction | PASS | `SeatKeyHasher.cs` L120–139. The vectors match my independent Python computation. `purchaseId.ToString("D")` is lower-case in .NET, and `InstallId.ToString()` is pinned by the vector. |
| Keyed hashes: domain separation | PASS | The three inputs have different lengths, so no input of one construction equals an input of another. HMAC-SHA256 is a PRF, so outputs are independent across constructions. `K_seat` is a separate KMS key from `Audit` and `InstallHashPepper` (`deployment.md` §3, `KeyedHashKey.Seat`). |
| Keyed hashes: unlinkability | PASS | `InstallKeyHash` is keyed per install and `SeatKeyHash` per purchase, so the same public key gives unrelated values across installs and purchases. Without `K_seat` the hashes link nothing. With MAC access to `K_seat`, linking needs the raw 65-byte key, which is never stored or logged. |
| Constant-time compare / distinct types | PASS | `InstallKeyHash.Matches` and `SeatKeyHash.Matches` use `FixedTimeEquals`. They have no shared base and no cross-type `Equals` (reflection test). `SeatCheckValue.Matches` is constant time after a format check on non-secret config. `MatchSeatAsync` hashes and compares every candidate with no early exit (counting-fake test). |
| Element-0 / install binding | PASS | `VerifiedSeatKey` carries its `InstallId`. `InstallKeyHashAsync` L70 refuses a key verified for another install (deviation 3, a useful hardening). Element 0 is never a seat-match candidate (`Others` only, L98). Verify has max 1 key, so `Others` is empty and verify can never produce a rebind match. |
| KMS failure → never "no match" | PASS | `KmsSeatKeyMac` passes `KmsUnavailableException` through. `FromMac` refuses a MAC that isn't 32 bytes. Test `AKmsFaultIsKmsUnavailableAndNeverAResult` plus a negative proof. |
| `K_seat` lifecycle / startup check | PASS (see M-1, I-4) | `SeatKeyStartupCheck` (Infrastructure L62–97): outside Development/Testing a missing value throws (L67). A malformed value throws in every environment. KMS unavailable → `KmsConfigurationException` (L86). A mismatch throws. Messages are constants and never carry the value. It is registered as an `IHostedService`, like the existing T-123/T-131 checks, so it starts before Kestrel. `deployment.md` §3 requires an immutable key version, auto-rotation off and deletion protection (T-140 to implement). |
| Logs / metrics / exceptions | PASS | All exception messages are constants. Metric tags come from fixed word sets and `ZaghlolMetrics.Tags` sanitises them as well. The sentinel test covers a capturing logger, `ActivityListener`, `MeterListener`, startup-check and KMS-fault exceptions and a rejected set. |
| Test support out of production | PASS (see I-5) | `src/` has no reference to `tests/` (grep: the only `.csproj` match is a comment). All 8 files in `tests/Shared` are in namespace `Zaghlol.Testing`, which the rule catches whatever the type name. `TestSupportExclusionTests` loads Domain, Application, Infrastructure and Api (Api tests) plus Workers and Ops (their own tests). The `FakePriceProvider` allowlist is one exact full name and is refused in Production by T-127. `InternalsVisibleTo` names only the three test assemblies. |
| Wycheproof provenance / licence | PASS | The upstream bytes at the pinned commit match the vendored file and LICENSE (independent download). `NOTICE.txt` records source, commit, path and SHA-256. Apache-2.0 is compatible, and vendoring an unmodified file with LICENSE and NOTICE meets §4. |
| Data egress / BR-SYNC-03 | PASS | No new endpoint, field, dependency or outbound call. Public keys and signatures are already part of the contract (D-55/D-62). They are processed in memory and only keyed hashes leave the module. |

## Findings

### M-1 (Medium) — Emergency-rotation runbook does not sequence the clear against running API instances; it can leave hashes under the old `K_seat` that can never be cleared afterwards

`docs/03-technical/deployment.md` L65: "in one `migrator` transaction … set `installs.seat_key_hash = NULL` … ; deploy the new reference and check together."

**Leak / failure path.** The startup check runs only at process start. API instances already running on the old key version keep serving after the clearing transaction commits. During a rolling deploy, any verify, restore or sign-in that reaches an old instance after the clear sees `seat_key_hash IS NULL` and registers element 0 under the **old** `K_seat`. It also writes `device_key_hash` under the old key. After the new instances are up, every such install gets `SEAT_KEY_MISMATCH` on restore and sign-in. The SEC F9 set-once trigger forbids replacing the hash, so the only fix is to run the trigger-bypassing clear a second time. That is exactly the "mismatch storm" the design note says the procedure avoids. In the reverse order (new instances up before the clear), the new instances can't start at all on Production, because the check needs the new `SeatCheck`, or they read the old hashes as mismatches.

**Required change (before PO Q1 is closed or before T-140 scripts this; not before merge):** state the order explicitly:
1. Stop or scale the API to zero, or reject `seatKeys` with a maintenance flag, so no instance holds the old key reference.
2. Run the clearing transaction.
3. Deploy the new `Kms:HmacKeys:Seat` and `SeatCheck` together.
4. Start the instances.
5. Verify `zaghlol.seat.element_zero{status=mismatch}` stays flat.

Also specify:
- the bypass uses `ALTER TABLE … DISABLE TRIGGER` inside the same transaction (transactional in PostgreSQL, ACCESS EXCLUSIVE lock), not `session_replication_role`, which would also disable FK triggers on every table;
- two-person approval and an audit-log row;
- revoking `MacSign` on the old key version afterwards, and destroying it only after a holding period.

### L-1 (Low) — `SeatKeyHashAsync` accepts any verified key, including positions ≥ 1, as the value for `device_key_hash`

`SeatKeyHasher.cs` L80. backend-api §4.3 says `device_key_hash` is always the hash of the caller's **registered** key (element 0). Writing the hash of a position-≥1 key (a relayed or oracle key) would let that key "own" the seat, which defeats the rebind cap logic ("the key it leaves on the seat is the caller's … key"). Today nothing prevents a T-184 call such as `SeatKeyHashAsync(pid, keys.Others[i], ct)`. `InstallKeyHashAsync` already has an equivalent guard (install binding, L70). **Required change (follow-up, owner T-184 or a small T-182 delta):** add a dedicated `SeatKeyHashForHolderAsync(purchaseId, VerifiedSeatKeys keys)` that hashes only `keys.ElementZero` and use it for writes, or have `SeatKeyHashAsync` refuse `Position != 0` and keep a private path for `MatchSeatAsync`. Add a test.

### L-2 (Low) — PO Q1: recommend that a suspected `K_seat` compromise is first handled by IAM revocation, not hash clearing

`K_seat` is non-exportable inside the KMS (design note §6). "Compromise" therefore realistically means someone else could call `MacSign`, not that the key bytes leaked. On its own that gives no linkage: raw public keys are never stored, so there is nothing to recompute against stored hashes. Even combined with a DB dump, it only confirms links for public keys the attacker already holds from transit. The clearing procedure, on the other hand, degrades every iPhone holding Gold: trust is lost and the TOFU registration window reopens for every install at once, including a user-CA-proxied verify that registers untrusted. **Recommendation for the PO answer:** (1) revoke the foreign principal's permission and review KMS audit logs; (2) rotate (M-1 procedure) only if key material could have left the HSM (for example a software-protection-level key, or provider-confirmed exfiltration) or the DB was also writable by the attacker. Record this in the runbook. Follow-up for the architect with Q1; not blocking.

### I-1 (Info) — High-S acceptance is safe; keep it that way downstream

The analysis is in the table. The condition to preserve is that no consumer (T-132/T-135/T-184/T-185) ever uses signature bytes as an identifier, dedup key or replay key, or includes them in a stored hash. Suggest T-184's and T-185's review checklists carry that line.

### I-2 (Info) — Freshness lives entirely in consumers

`Verify` is order-independent and has no single-use state. Single use for restore (App Attest counter in the same transaction as the element-0 check) and sign-in (`replay_guard` committed before) must be verified in T-185 and T-135 respectively. The consumer API section in the task file says this. Make sure those tasks' reviews check it.

### I-3 (Info) — `SeatChallenge.ForVerify` UTF-8 encodes lone surrogates as U+FFFD

`SeatChallenge.cs` L28. Two `signedTransaction` strings that differ only in a lone surrogate would map to the same challenge. There is no impact: a JWS is ASCII and is verified separately by T-131/T-132, which rejects such input first. Optionally use `new UTF8Encoding(false, throwOnInvalidBytes: true)` and treat a throw as "ignore seatKeys".

### I-4 (Info) — Development/Testing environment names relax the startup check

`SeatKeysServiceCollectionExtensions.cs` L67. If an unset `SeatCheck` is combined with `ASPNETCORE_ENVIRONMENT=Development` in a real deployment, the check is skipped. This is the same trust assumption as the T-123 refusal of the Local/fake KMS outside those environments, and T-140 IaC should pin the environment name. No change for T-182.

### I-5 (Info) — The exclusion rule is name/namespace based

It would not catch a test helper with an ordinary name placed in a production namespace. Today all `tests/Shared` files use `Zaghlol.Testing`, so the namespace rule covers them. Keep "every `tests/Shared` file uses namespace `Zaghlol.Testing`" as a convention, or assert it in the test. Remove the `FakePriceProvider` allowlist entry when D-41 closes (track as a follow-up with T-127).

### I-6 (Info) — `dev-keys.sh` passes the local `K_seat` hex on the `openssl` command line

`backend/tools/dev-keys.sh` L65 (`-macopt hexkey:…`). The value is visible in `ps` for the duration of the call. The key is a throwaway Local-provider dev key, so there is no impact. If wanted, compute it with a short `python3 -c` reading the key file instead of passing the key as an argument.

## Verdict

**APPROVED.** There is no Critical, High or "before merge" finding. Follow-ups:
- M-1: architect, with PO Q1, before the runbook loses "provisional", and T-140;
- L-1: T-184 (or a small T-182 delta);
- L-2: architect / PO Q1;
- I-1, I-2: T-184 and T-185 reviewers;
- I-3, I-6: optional;
- I-4: T-140;
- I-5: T-127 / D-41.
