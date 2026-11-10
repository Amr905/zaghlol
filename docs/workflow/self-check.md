# Builder self-check (before reporting a task as done)

Every implementer runs through this list **before** its final report and states in the report which items applied and how they were handled. It collects the findings that caused most fix rounds in batches 1–2 (T-124, T-128, T-136, T-015, T-016, T-060, T-034). A reviewer finding one of these is a sign the self-check was skipped.

## 1. Never destroy data on doubt
- Is any delete, wipe, overwrite, key re-creation or "reset" reachable from an error path? It must run only on **proven** evidence (the thing is positively absent or provably corrupt), never on a transient, unknown, I/O, timeout, permission or "can't tell" error.
- `File.exists()` / similar return false on errors: use APIs that distinguish "absent" from "unknown".
- A single failed read is not proof: confirm with the retry schedule the design gives.
- Order destructive multi-step operations so a crash in the middle leaves a recoverable state.

## 2. Concurrency and multiple actors
- Can two engines, isolates, processes, requests or operators run this at the same time (UI + background engine, two syncs, two admins, a retry racing the original)? Write a test with two actors.
- Only act on state you own (a copy, a lease, a lock you created in this call). Check ownership before restore/delete/release.
- Leases and locks expire: re-check validity right before the critical step.
- Database: conditional updates / unique constraints for "exactly one winner"; no long-held connections across awaited handlers.

## 3. Untrusted input
- Every external input (other apps, HTTP bodies, files, URIs, SMS, provider data) has a size cap, a count cap, a time limit and a type check on the bytes actually read.
- Strict parsing: unknown fields rejected where the spec says so; Unicode tricks considered (other-script digits, combining marks, zero-width characters, look-alike symbols, userinfo in URIs).
- Errors never echo the input.

## 4. Fail closed
- Missing or invalid configuration outside Development/Testing stops startup (proxies, issuers, keys, providers).
- Unknown enum/state/role → deny.
- A security feature that can't be verified at startup is refused, not silently disabled.

## 5. Secrets and logs
- No keys, tokens, raw SMS, contribution text, addresses or amounts in logs, metrics tags, error messages, problem bodies or test output. Metric tags come from fixed sets.
- Key material not cached in providers/singletons; zero buffers where the platform allows.
- Tests that prove it (log capture with a sentinel).

## 6. Docs match the code
- Every doc sentence you add or touch describes what the code actually does — no "any script", "can't contain", "guarantees" unless a test proves it. State accepted residuals plainly.
- Contract changes (APIs, channels, schema) are written into `docs/03-technical/` and flagged in the report.

## 7. Evidence
- Each acceptance criterion maps to a named test.
- For C4: at least one negative proof (break the guard, show a test goes red) for each safety property, run locally or on a throwaway branch, listed in the report.
- Local checks green before push (CLAUDE.md §6); PC runner green after push.
