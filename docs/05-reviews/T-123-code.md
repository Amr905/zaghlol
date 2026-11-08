# Review — T-123 Signing service (ES256 via KMS abstraction) and response-signature middleware — code review

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Opus, C4) |
| Date | 2026-11-08 |
| Commit / diff | `origin/task/T-123-signing` @ 9035f64 vs merge base 635c791 (55 files). CI backend-ci 42489960257 green, 5/5 jobs, head SHA 9035f64 confirmed |
| Verdict | **CHANGES_REQUESTED** (1 major) |

Traces read: task T-123 and its design note (2026-11-06), backend-api §1, FU-019/022/023/025/026, and the 2026-11-07 Lead decision (IEnvelopeCipher in T-123, cloud adapter in T-140, key ring as configuration).

## Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Signature verifies with the exported public key | PASS | `SignerTests.SignatureVerifiesWithTheExportedPublicKey` (through `EcPublicJwk.ToJwks`); `ResponseSigningTests.A200IsSignedOverTheExactBody…`; committed vectors verified by an independent reference verifier (`SigningVectorTests`) |
| Rotation keeps the old kid verifiable until retired | PASS | `SignerTests.RotationKeepsTheOldKidVerifiableUntilItIsRemoved`: Next is published but never signs; A→Retired, B→Active; A's old signature still verifies |
| R4-2 malformed nonce is 400 `VALIDATION_FAILED`; valid one echoed byte-for-byte in the signed body; absent gives `null` | PASS | `TimeNonceTests`: 21 and 23 chars, `=`, `+`, `/`, non-canonical last char, space, empty, two headers, comma-joined; echo checked inside the signed bytes for `Ok<T>` and `Results<Ok<T>,NotFound>`; explicit `null` |
| R4-2 nonce appears in no log, span or exception output | PASS | `TheNonceAppearsInNoLogSpanOrExceptionOutput`: sentinel sent to echo, throwing and malformed paths, with Verbose Serilog capture (message, properties, exception) and an all-sources `ActivityListener` (tags, baggage, events) |
| `IKeyedHasher` matches a test vector; no API returns key material | PASS (production adapter deferred) | RFC 4231 cases 1–4 through `IKeyedHasher` (values checked against the RFC); `KmsSurfaceTests.NoKmsMemberReturnsKeyMaterial` covers `LocalKms` and every public type in the namespace. The cloud adapter is T-140 (see #6) |
| DoD: analyze/format clean, tests, no hard-coded strings, no `double` money, no raw SMS in logs | PASS | CI build/format/test green; backend only, no UI, no money, no SMS |

FUs claimed done:
| FU | Result | Evidence |
|----|--------|----------|
| FU-019 `session_user` checks and role-switch rejection | DONE | `DatabaseRoleGuard.Query` runs every check on `session_user` and its closure; `ASuperuserLoginThatSwitchedToTheApiRoleIsRejected` (`-c role=zaghlol_api`) |
| FU-022 probe connect timeout, BlackHole recovery test | DONE | `ProbeConnectionString` forces `Timeout=2`; `AnAbandonedProbeFreesThePoolOfOneWithinTheConnectTimeout` |
| FU-023 transitive membership and non-zero exit | DONE | recursive `pg_auth_members` closure; `AnyExtraTransitiveMembershipIsRejected` (`pg_write_all_data`, group through an intermediate role); `HostExitCode` 78 returned by API and Workers |
| FU-025 `Include Error Detail` guard and server log verbosity | DONE (code part) | options validator + `CreateDataSource` guard (covers the migrator); compose `log_error_verbosity=terse`; deployment.md note for managed PostgreSQL. The account-delete doc wording stays with the architect, as the FU says |
| FU-026 sequences, future-dated audit insert, ApiHostGroup enforcement, readiness caching/cancellation | DONE | `NoRoleHoldsAnyPrivilegeOnASequence`, `OperatorsMayStampRowsOnlyWithinAMinuteOfNow`, `EveryTestClassThatCanBootAHostIsInTheApiHostGroup`, `AReadyAnswerIsCachedForTwoSeconds`, `ACallerThatGivesUpWhileWaitingDoesNotDisturbTheProbe`, `TheProbeIgnoresTheCallersToken` |

## Declared deviations
| # | Deviation | Judgement |
|---|-----------|-----------|
| D1 | Own `EcPublicJwk` record instead of `JsonWebKey` | **Accepted.** `JsonWebKey` would add `Microsoft.IdentityModel.Tokens`, which breaks the note's "no new NuGet dependency". The record checks the curve point, and `ToJwks` gives the export format |
| D2 | Extra `IHmacProvider` / `IDataKeyProvider` ports | **Accepted.** The note leaves the adapter shape for HMAC and data keys open. Three narrow ports match the three KMS capabilities the note lists, and let `FakeKms` replace them |
| D3 | Purpose enforcement (Sync only signs raw bytes, Entitlement only JWS) | **Accepted.** Server-side defence in depth for the app's `s`/`e` kid rule; the `purpose` parameter is now redundant but harmless |
| D4 | Verify-before-return, fail closed | **Accepted.** One extra P-256 verify per response catches a wrong `keyRef` at runtime. See nit #9 on the status it maps to |
| D5 | STJ web defaults for JWS payloads | **Accepted.** camelCase matches the rest of the API JSON. The exact bytes are signed, so verifiers don't depend on the serializer |
| D6 | Extra startup probes (all HMAC keys, envelope round-trip, JWS) | **Accepted.** In line with "readiness never goes green on a wrong ring"; the cost is a handful of KMS calls per pod start |
| D7 | `TestServer` host for middleware tests | **Accepted.** It runs the real `ApiPipeline` order, which is what matters, and needs no DB |
| D8 | Vectors generated by one temporary CI run, then committed | **Accepted.** The temporary step dumped only the two public vector files; the private keys lived in memory only. The step is gone at HEAD (verified: no `ZAGHLOL_GEN_VECTORS` or `TEMP` in the workflow). The WIP commit c76f75f still carries it, so the PR must be **squash-merged** |
| D9 | Compose/CI container runs as Development with dev keys; CI proves Production refuses to start | **Accepted for now.** There is no adapter that Production could use. Side effect: no smoke test now runs the image in Production mode (minor #7) |

## Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | **major** | `backend/src/Zaghlol.Api/Signing/ResponseSigningMiddleware.cs:73` | `ContentLength = body.Length` is set for every status, including a bodiless 4xx. `UseStatusCodePages` (outer) skips any response whose `ContentLength.HasValue`. So a signed endpoint that returns `TypedResults.NotFound()`, `Unauthorized()`, `StatusCode(429)` or the `NotFound` arm of a `Results<Ok<T>,NotFound>` sends an empty `Content-Length: 0` response instead of the RFC 9457 problem body the contract requires (backend-api §1 "Errors"). Unsigned endpoints still get the problem body, so the seven signed operations behave differently from the rest. `signed-404`/`signed-409` miss this because they carry bodies | Leave the response untouched when the status isn't 200 and the buffer is empty (set `ContentLength` only on 200 or when you copy bytes). Add a test: a signed endpoint that returns a bodiless 404 gets `application/problem+json` with `code`, unsigned |
| 2 | minor | `backend/src/Zaghlol.Infrastructure/Kms/EnvelopeCipher.cs:247,352` | Encrypt and decrypt let a `CryptographicException` from `GenerateDataKeyAsync` through as is (decrypt maps the unwrap case only). `Signer` and `KeyedHasher` map it to a constant-message `KmsUnavailableException`. A cloud SDK's crypto exception text can name the key ARN, and `GlobalExceptionHandler` logs it | Map it to `KmsUnavailableException` the same way. Owner: **T-124** (first consumer) |
| 3 | minor | `backend/src/Zaghlol.Api/Signing/TimeNonceFilter.cs:269` | The fail-closed echo check only matches `IValueHttpResult` whose `StatusCode` is 200. `Results.Json(dto)` / `JsonHttpResult<T>` without an explicit status has `StatusCode == null`, so it skips the check (fail open) | Treat `null` status as 200 when the value is `IAnchoredResponse`, or document that anchored handlers must return `Ok<T>`. Owner: **T-132** (live contract across the six operations) |
| 4 | minor | `backend/tests/Zaghlol.Infrastructure.Tests/ReadinessProbeTests.cs:64,115` | Wall-clock timing tests (real `Task.Delay` of 3 s; asserting ≥ 800 ms elapsed; 2 s polling deadline) can flake on a loaded runner | Widen the margins or drive them from the fake clock where Npgsql allows it. Owner: **T-140** |
| 5 | minor | `backend/src/Zaghlol.Infrastructure/Kms/KmsCall.cs:263-272` | When an attempt times out and is retried, a `DataKey` that the abandoned attempt returns later is never disposed, so the plaintext DEK stays in memory until GC | In `Observe`, dispose an `IDisposable` result of a late success. Owner: **T-140** (with the cloud adapter) |
| 6 | minor | `backend/tests/Zaghlol.Infrastructure.Tests/Kms/EnvelopeAndHashTests.cs:171` | `KmsSurfaceTests` scans only the `Zaghlol.Infrastructure.Kms` namespace. The "production provider exposes no key material" AC is proven only once the cloud adapter is covered | The T-140 adapter must live in this namespace, or the test must widen to the adapter's namespace. Owner: **T-140** |
| 7 | minor | `backend/docker-compose.yml:56`, `.github/workflows/backend-ci.yml:166` | Compose-smoke and the container step now run as `Development`, so no CI job serves requests with Production configuration (in .NET, Development also turns on the developer exception page) | Restore a Production-mode smoke once the cloud adapter exists, or add a CI-only adapter for it. Owner: **T-140** |
| 8 | nit | `backend/src/Zaghlol.Api/Problems/GlobalExceptionHandler.cs:37` | `RetryAfter = "5"` duplicates the `KmsRetryAfterSeconds` constant | Derive it from the constant (trivial, may be fixed in the round for #1) |
| 9 | nit | `backend/src/Zaghlol.Infrastructure/Kms/Signer.cs:180-184` | A signature that fails verify-before-return (wrong `keyRef`, a config fault) becomes 503 with `Retry-After`, the same as a transient outage, so clients retry a permanent fault. It shares the `unavailable` metric | Give it its own metric tag (e.g. `operation=sign_verify`) so T-138 alerts tell it apart. Owner: **T-138** |
| 10 | nit | `backend/src/Zaghlol.Api/Signing/TimeNonceFilter.cs:159-171` | `IAnchoredResponse` / `ITimeNonceFeature` are `internal` to `Zaghlol.Api`, so anchored response DTOs must be declared in Api, not Application | Confirm the DTO placement when the first anchored endpoint lands. Owner: **T-128** |

## Checklist
- [x] Analyze/format clean (CI `build, format, test` green; backend, so `dotnet format` not `flutter analyze`)
- [x] Tests added and passing (Kms, signing middleware, nonce filter, vectors, FU tests; CI 5/5)
- [ ] RTL + LTR verified (not applicable: no UI)
- [x] No hard-coded user-facing strings (none; exception messages are constants without key refs, data or nonces)
- [x] No `double` money (not applicable)
- [x] No sensitive data in logs (nonce sentinel test; `LocalKms` hides file paths; key refs never in messages)
- [x] Stays within the task's scope (the `ApiPipeline` extraction is needed for the test host; Persistence changes are the FUs this task owns; doc edits trace to the design note)

Architecture: KMS code sits in `Zaghlol.Infrastructure/Kms` and middleware/filter in `Zaghlol.Api/Signing`, as the note asks. No private, HMAC or data-key material crosses a port. The key ring is configuration, `Local` fails closed outside Development/Testing, and the pipeline order puts signing after routing and inside any future compression. No temporary CI change remains at HEAD.

## Notes for the Lead
- Only #1 needs another round. It's about one line plus one test, and only code-reviewer re-reviews that delta. #8 may be fixed in the same pass.
- Route #2 to T-124, #3 to T-132, #4–#7 to T-140, #9 to T-138 and #10 to T-128 as FUs.
- Squash-merge the PR: WIP commit c76f75f contains the temporary vector-dump CI step (D8).
- The branch is based on 635c791; origin/main has moved on to bb81775. Rebase before merging and re-run CI.

## Round 2 (delta re-review)

| Field | Value |
|-------|-------|
| Date | 2026-11-08 |
| Commit / diff | `git diff 9035f64 1a8d165 -- backend/` (6 files). Merge commit 7bf7e9a ignored; it touches nothing under `backend/` |
| CI | backend-ci 42502737300 green, 5/5, head SHA 1a8d165 confirmed |
| Verdict | **APPROVED** |

| Round-1 item | Result | Evidence |
|--------------|--------|----------|
| #1 major: bodiless non-200 responses lost the problem body | FIXED | `ResponseSigningMiddleware`: for a non-200 response with an empty buffer, the middleware now returns before it sets `Content-Length` or writes anything, so the outer `UseStatusCodePages` writes the RFC 9457 body. A non-200 response with a body is still copied out unsigned. A forged `Zaghlol-Signature` header is still removed first. `ABodilessErrorOfASignedEndpointStillGetsTheProblemBody` covers bare 404, bare 401 and the `NotFound` arm of `Results<Ok,NotFound>`: each gets `application/problem+json` with the right `code` and no signature |
| 200s are always signed | CONFIRMED | The `StatusCode == 200` branch is checked first and doesn't depend on body size, so an empty 200 is still signed and gets `Content-Length` (`AnEmptyObjectBodyIsSigned`, the cap tests and the echo tests are unchanged and green) |
| #8 nit: `Retry-After` constant | FIXED | Derived from `KmsRetryAfterSeconds` with the invariant culture |
| #3 minor / security L-2: echo check skipped status-less results | FIXED | The pattern now matches `StatusCode: null or 200`. `TypedResults.Json` (null status, writes 200) is checked; a `Json(..., statusCode: 4xx)` is still exempt, which is correct. `AnAnchoredBodyThatDoesNotEchoTheNonceFailsClosed` now also runs `/t/anchored-json-wrong`, for both the absent and the valid nonce |

No new findings. Follow-ups #2, #4–#7, #9 and #10 stand as routed in round 1; #3 and #8 are closed. Squash-merge still required (D8).
