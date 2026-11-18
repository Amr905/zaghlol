# Batch 37 review (follow-up batch)

Reviewer: code-reviewer (Opus), code + security. Branch `batch/2026-11-18-37`. Each task was reviewed as `git diff origin/main...origin/task/<b>`.

Tests run on the merged tree: app `test/features test/core test/a11y` (benchmark and golden excluded) gave 4506 passed; `zaghlol_parsing` 1524 passed; `zaghlol_domain` 426 passed; `tools/lints` 34 passed; `tools/registry_lint` 8 passed. Running `dart analyze` on a probe file in `packages/zaghlol_domain` confirmed that the root `flutter_lints` + extra rules still apply to packages.

## task/FU-b37-core — APPROVED
- `refreshIfDue` now passes `hasToken` to `advance`, so a token without a trusted-time record starts `tampered`, the same as `evaluate`. Correct.
- The rollover cut uses the zone offset at local midnight. The `shouldStop` breaks are safe because the dedupe and detection are idempotent. The FU-110 linked-row sweep and the payday double invalidation are correct.
- Diag handlers record codes only (`diagEventForError` keeps only a SafeException code), a failure while recording is swallowed, and debug pass-through applies only under `kDebugMode`. No PII or SMS bodies are recorded.
- `lastForegroundMs`: a value in the future is treated as 0. Fine.

## task/FU-b37-catalog — CHANGES_REQUESTED
- Seed upgrade: verified. It writes only with `INSERT OR IGNORE`. `catalog_keywords` has PK (keyword_norm, lang) and aliases have UNIQUE(alias_norm, merchant_id), so no duplicates. Nothing is deleted. It is skipped when the catalog version is above the seed version. It runs behind the pause gate. The hash is written last, in the same transaction, and any error fails closed. OK.
- **M-1 (major, privacy)** `packages/zaghlol_parsing/lib/registry/regex_safety.dart:37` + `parsing_pipeline.dart:54,63,132,138`: a quarantined regex returns "no match". For drop patterns this fails open. A single wall-clock overrun of more than 50 ms (a GC pause, or a cold start on a low-end device) quarantines the global OTP/password drop for the rest of the process, and OTP bodies then flow into parsing and storage. Required: drop checks must treat a quarantined pattern as matched (fail closed), or drop patterns must never be quarantined.
- minor: `catalog_providers.dart:37` still uses `!kReleaseMode` for the seed dev keys, while core2 moved the backend keys to `kDebugMode`. Align them (follow-up).
- minor: a template's quarantine lasts for the life of the process and is set from a single timing sample. A transient stall silently disables a valid template. Consider requiring two overruns (follow-up).

## task/FU-b37-tools — APPROVED
- The app now includes the root options, which add `flutter_lints`, strict modes, extra rules and riverpod_lint. Packages and tools move from `lints/recommended` to `flutter_lints`, which is a superset. No rule got weaker.
- The FU-031 boundary fix is correct and has a fixture.
- Spectral is now installed via `npm ci` with a lockfile. `setup-node` is pinned by SHA. The `missing_provider_scope` ignore is justified.

## task/FU-b37-native — APPROVED
- Attest key ID: `SecItemUpdate` is tried first, and the add happens only on `errSecItemNotFound`. The query has no return or match attributes. The old key is never deleted, and there is a test for it.
- The pbxproj change touches only Debug-prod RunnerTests.
- `IntentRunLog` reports NOT_AVAILABLE for an unreadable log. The iCloud quota check now looks at the newest entry only. The masked widget snapshot is published immediately on lock. The seat-key catch is fine.
- nit: an in-place update keeps the old item's `kSecAttrAccessible`.

## task/FU-b37-parse — CHANGES_REQUESTED
- **M-2 (major, data loss)** `app/ios/Runner/Platform/OCR/OcrHost.swift:314-326`: the plain-root containment check runs on the unresolved path, then the symlink is resolved and the target is deleted. A link inside temp/cache that points to, for example, the database file in Application Support deletes that file. This breaks the "never touch a file outside temp/cache" guard. Required: resolve both the path and the roots (`/private/var` vs `/var`), re-check containment on the resolved URL, and refuse with `ioError` without deleting anything when the target is outside the roots.
- Al Rajhi patterns are now bounded (`.{0,60}?`), with registryVersion 5 and both guard bases bumped. `userAgent = null`, the ask `on Object` catch, the stop words and the CI retry/tags are fine.

## task/FU-b37-core2 — APPROVED
- Participant removal now runs in one transaction. Chart memo invalidation is driven by `tableUpdates`. The import dedupe pages with a keyset. Outbox rows are dropped one by one. Dev keys are allowed only under `kDebugMode`. A wrong-kind proof is turned into an `AttestationException`.
- The verified-entry cleanup removes only the purchase outbox entry (older than 14 days). No user financial data is touched.
- A wrapped store failure now surfaces as a code only.

## task/FU-b37-ui — APPROVED
- `savedPercent` uses integer math. ARB keys exist in both locales, and the emoji moved into the ARB.
- minor: `asset_form.dart:216,249` caps the name by UTF-16 `length`, not by characters (runes or grapheme clusters). Follow-up.

## task/FU-triage2 (docs) — APPROVED (skimmed)
## task/TEST-explorer4 — APPROVED (skimmed; the SMS fixtures are synthetic)

## Fix list

| Task | File:line | Required change | Test to add |
|---|---|---|---|
| FU-b37-catalog | `packages/zaghlol_parsing/lib/registry/regex_safety.dart:37`, `lib/pipeline/parsing_pipeline.dart:54,63,132,138` | A quarantined drop pattern counts as a match (fail closed); only templates fail to "no match" | Quarantine the global OTP drop regex, then parse an OTP body and expect `ParseDropped(globalPattern)` |
| FU-b37-parse | `app/ios/Runner/Platform/OCR/OcrHost.swift:314-326` | Re-check containment on the symlink-resolved path (resolve the roots too); throw `ioError` and delete nothing if the target is outside | XCTest: a symlink in the plain dir pointing to a file outside the roots leaves that file in place and throws `ioError` |

## Lead delta check: quarantined drop patterns (2026-11-18)

The fix agent's 11c18b2e made a quarantined drop pattern count as a match ("fail closed"). That swaps the OTP leak for data loss: once quarantined, a global drop pattern would drop **every** SMS, and an institution drop pattern every SMS from that bank, for the rest of the process. The Lead replaced it in a follow-up commit:
- **Rule:** drop patterns (`dropPattern: true`) are never quarantined and always run as a plain match. They are short, and registry_lint rejects backtracking-prone patterns. Template patterns keep the 3-strike quarantine.
- **Pipeline test:** with every global and institution drop pattern struck 3 times, an OTP is still `ParseDropped(globalPattern)` and an NBE purchase is **not** dropped.
- **Unit test:** a quarantined drop pattern still matches only what it matches.
- Parsing 1515 tests pass; analyze is clean.

Verdict: FU-b37-catalog **APPROVED** after this change.
