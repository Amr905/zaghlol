# T-123 test-engineer review (C4) - signing service, response-signature middleware, time-nonce filter

Branch origin/task/T-123-signing @ 9035f64. Reviewer: test-engineer. Evidence is static (no .NET SDK locally) plus CI.

## CI evidence
backend-ci run 42489960257, job "build, format, test": conclusion success; steps Restore, Build (warnings are errors), EF model check, Verify formatting, Test (unit + Testcontainers PG17) all success (confirmed via the GitHub jobs API). Test counts as reported by the implementer: Infrastructure 399, Api 44, Contract 42, Application 3, Workers 3, Ops 2.

## Acceptance criteria to tests

| AC | Tests | Would it fail if the behaviour broke? | Verdict |
|----|-------|----------------------------------------|---------|
| Signature verifies with exported public key | SignerTests.SignatureVerifiesWithTheExportedPublicKey; ResponseSigningTests.A200IsSignedOverTheExactBodyAndVerifiesWithTheExportedKey (real HTTP, real pipeline); SigningVectorTests (committed vectors, high-S, empty body, Arabic UTF-8) | Yes: verification uses JWKS built from PublishedKeys, header grammar regex checked, body bytes compared. Signing a different byte range or P1363->DER change fails. | PASS |
| Rotation keeps old kid verifiable | SignerTests.RotationKeepsTheOldKidVerifiableUntilItIsRemoved (A active, B next -> A retired, B active; old sig verifies, new kid = B, next never signs, retired still published); KeyRingTests.AMisconfiguredRingIsRejected (no active, two active, dup kid, kid pattern, purpose prefix, not P-256, short coordinate, shared keyRef); AJwkThatIsNotTheKmsKeyIsRejected; AnOffCurvePointIsRejected; EnvelopeAndHashTests.AfterKeyRotationOldEnvelopesStillDecrypt | Yes | PASS |
| R4-2 malformed nonce -> 400 VALIDATION_FAILED | TimeNonceTests.AMalformedNonceIs400... (21, 23, "==", "+", "/", non-canonical last char, space; asserts code, no `detail`, no signature header, nonce not echoed); TwoNonceHeadersAre400; TryRead unit test (empty value, two values, comma-joined); CanonicalFormIsTheOpenApiPattern (trailing newline, null); SigningVectorTests.TheOpenApiTimeNoncePatternMatchesTheFilter | Yes: boundaries on both sides, canonical-bit check, header multiplicity | PASS |
| valid echoed byte-for-byte inside signed body; absent -> null | TimeNonceTests.AValidNonceIsEchoed...(typed Ok<T> and union endpoint); AnAbsentNonceGivesAnExplicitNull; AnAnchoredBodyThatDoesNotEchoTheNonceFailsClosed (null and valid inputs -> 500, unsigned) | Yes, incl. the fail-closed guard | PASS |
| R4-2 nonce in no log/span/exception output | TimeNonceTests.TheNonceAppearsInNoLogSpanOrExceptionOutput | Strong: random sentinel, three paths (echo, handler throws, malformed), real `UseZaghlolPipeline` and real `ConfigureZaghlol`, Verbose level with Microsoft/System overrides, in-memory ActivityListener on all sources, positive control (handler failure text present, spans non-empty), polls until request-completion events are written. Would catch any log/LogContext/tag/exception leak by the filter. | PASS (see G3) |
| IKeyedHasher vector + no key-material API | SigningVectorTests.KeyedHashVectorsMatchThroughIKeyedHasher (RFC 4231 cases 1-4, vectors from file); EnvelopeAndHashTests.EachKeyedHashKeyUsesItsOwnKmsKey; KmsSurfaceTests.NoKmsMemberReturnsKeyMaterial (reflection over whole Kms namespace incl. LocalKms, public methods/properties/fields, ECParameters/ECDsa/algorithms/AesGcm, `*Key*` byte returns, `Export*`; asserts LocalKms was scanned so it is not vacuous) | Yes for return types; see G4 | PASS |
| DoD | CI format/analyzer steps green; no-hard-coded-string and no-double concerns are for code review | n/a | PASS |

Other design-note behaviours covered: only 200 of marked endpoints signed (404/409/unmarked), handler cannot supply its own header, Body and BodyWriter buffering (BodyWriter left unflushed on purpose), exception -> unsigned problem, cap boundary (exactly cap signs, cap+1 -> 500), KMS throw/hang -> 503 + Retry-After: 5 + no body, one retry then fail closed, caller cancellation is not an outage, wrong-key KMS fault, high-S accepted, Local provider refused in Production/Staging (unit and whole-host), unknown provider, missing key ring refuses to start, key-file path traversal, envelope layout v1, fresh DEK/nonce, AAD context mismatch, every tampered byte and every truncation rejected, empty context refused, JWS fixed header and `e`-key use, purpose separation.

## Vectors and independent verification
Committed vectors hold public JWKs only (CommittedVectorsHoldPublicKeysOnly asserts the exact JWK member set, so a `d` fails). The verifier in ReferenceVerifiers.cs is separate from the signer code path (own regex grammar, own JWS parsing, rejects `d`, requires 64-byte signature, `typ`, `e` kid) and is applied to 4 valid + 9 invalid response vectors and 2 valid + 7 invalid JWS vectors (alg none, HS256 with public key as secret, unknown kid, `s` kid on JWS, DER, padding, modified payload). Fresh FakeKms signatures are run through the same verifier each run (generator self-check). The OpenAPI header pattern is asserted verbatim and against vectors.

## FU claims

| FU | Test | Verdict |
|----|------|---------|
| FU-019 session_user | DatabaseRoleGuardTests.ASuperuserLoginThatSwitchedToTheApiRoleIsRejected (superuser + `-c role=zaghlol_api`; asserts current_user really is zaghlol_api first, then RejectRoleSwitched) | PASS; would fail if the guard used only current_user |
| FU-022 probe timeout | ReadinessProbeTests: setting asserted == ConnectTimeoutSeconds; AnAbandonedProbeFreesThePoolOfOneWithinTheConnectTimeout (string says Timeout=30, expects a 2nd connect attempt within ~3 s; BlackHole server) | PASS; fails if Timeout is not forced. Uses real 3 s delay (see G5) |
| FU-023 transitive membership + exit code | AnyExtraTransitiveMembershipIsRejected (direct pg_write_all_data, via intermediate role to ops_rw, clean control accepted); TheGuardStopsTheHostWithANonZeroExitCode... asserts 0 before and DatabaseLoginRejected after | PASS |
| FU-025 Include Error Detail guard | IncludeErrorDetailIsRefusedAtStartup (two spellings; data source factory, options validation, probe string forces it off) | PASS for the guard. The "server log verbosity for CHECK failures" half of FU-025 has no test and no claim of one (see G6) |
| FU-026 N3 sequences | GrantTests.NoRoleHoldsAnyPrivilegeOnASequence (ACL scan with non-empty guard + nextval/setval/last_value as all four logins -> 42501) | PASS |
| FU-026 N6 audit window | AuditLogSecurityTests.OperatorsMayStampRowsOnlyWithinAMinuteOfNow (+-30 allowed, +-90 and +3600 refused) | PASS; the exact 60 s edge is untested (nit) |
| FU-026 N7 ApiHostGroup | HostStartupTests.EveryTestClassThatCanBootAHostIsInTheApiHostGroup (reflection, asserts >= 5 classes, TheoryAttribute derives from Fact so Theory-only classes are found) | PASS |
| FU-026 N9 readiness caching/cancellation | AReadyAnswerIsCachedForTwoSeconds (1.9 s cached, 2.1 s re-probed), ACallerThatGivesUpWhileWaiting..., TheProbeIgnoresTheCallersToken | PASS |

## Gaps (none leaves an acceptance criterion unproven)

| # | Sev | Owner | Gap |
|---|-----|-------|-----|
| G1 | minor | T-128/T-132/T-135/T-185 | The six anchoring operations are not wired in this task (by design); nothing yet proves each applies `.WithTimeNonce()` and `.RequireResponseSignature()`, nor that the sync throttle answer and sign-out are signed. Each endpoint task and T-132's cross-operation contract test must carry it. |
| G2 | minor | T-124 / T-141 | No test for idempotent-replay re-signing with the current active key, nor for "compression outside signing" (only the gzip invalid vector). Dart verifier (T-141/T-144) will be the first truly independent (non-.NET) consumer of the vectors; the current "independent" verifier uses the same System.Security.Cryptography primitives. |
| G3 | nit | T-123 or T-138 | The leak test proves the filter adds nothing, but the default Serilog/ASP.NET logging never logs request headers, so it cannot show that `Zaghlol-Time-Nonce` is on the deny-list; T-138 should assert that directly. |
| G4 | nit | T-123 | The reflection test does not cover `SigningKey.PublicJwk` (a JsonWebKey could carry `D`). Parsing reads only crv/x/y so private members cannot flow in today; a one-line assertion on PublishedKeys (no `D`) would lock it. |
| G5 | nit | T-123 | FU-022 test sleeps 3 s of real time and asserts a connection count; possible flake on a slow runner. Acceptable. |
| G6 | minor | T-140 | FU-025 second half (server log verbosity for CHECK failures) and FU-022's "recovery" variants are untested; keep the follow-up open or re-home it to T-140. |
| G7 | nit | T-123 | Invalid-vector tests assert only "rejected", not the reason, so a vector could be rejected for an unintended cause (for example the regex) while its intended defect goes untested. |

## Verdict
TESTS_SUFFICIENT. Every acceptance criterion maps to tests that would fail on regression (negative and boundary cases, rotation, nonce malformations, sentinel leak test with positive control, reflection surface test, vectors checked by a separate verifier). No major gaps; G1, G2, G6 are minor follow-ups with owners above.
