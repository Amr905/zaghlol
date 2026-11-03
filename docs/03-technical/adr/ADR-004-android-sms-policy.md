# ADR-004: Android SMS policy strategy

| | |
|---|---|
| Status | Proposed |
| Date | 2026-11-03 |
| Deciders | Product owner (approval), solution-architect |
| References | FR-ING-A-*, NFR-LEGAL-01 |

## Context
Reading SMS needs Google Play's SMS-permission exception for "SMS-based money management" (D-02). Play's spyware policy forbids handling non-financial SMS. Play may refuse the exception or revoke it later (R-01). Competitors (Say, FinArt) use SMS + notifications.

## Options considered
1. **Single build with SMS; hope for approval** — Simple, but a refusal blocks release.
2. **Two flavors of the same app: `prodSms` and `prodNoSms`** — Submit with SMS; keep a ready fallback that ships the same day if refused. Small build complexity.
3. **No SMS at all (notifications only)** — Lowest policy risk, but loses historical scan and SMS-only banks.

## Decision
**Two flavors** (deployment §1). Notification capture is a first-class channel in both. The native Capture Guard reads only allowlisted financial senders (inbox query filtered by address in SQL), so personal SMS never reach storage. Declaration material is a demo video of capture + privacy screen, plus a written description of the data boundary.

## Consequences
Two release artifacts per Android release; capability flags hide SMS UI in `prodNoSms`. The degraded-mode UX (FR-ING-A-05) is the same code path as permission denial.
