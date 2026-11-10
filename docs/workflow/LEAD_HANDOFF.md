# Lead handoff — read this first

_Last updated: 2026-11-11 01:00 (Cairo) by the Lead session. Update it whenever the state below changes._

**All state is in the repo.** Agents from earlier sessions can't be messaged; start new ones from their branches. Where this file and the repo disagree, the repo wins.

## Start of a session (in order)

1. Attach the repo with push access (`add_repo` Amr905/zaghlol, access `push`), clone, register it. Project agent types (`code-reviewer`, `backend-engineer`, …) appear only after registration; before that, run roles as `general-purpose` with "act as `.claude/agents/<role>.md`".
2. Install the toolchains once: `bash docs/workflow/tools/cloud-sdk.sh`, then `export PATH=/home/claude/sdk/flutter/bin:/home/claude/sdk/dotnet:$PATH` (needs package installs allowed in the Claude network settings; they are, since 2026-11-10).
3. Check the PC runner is alive: newest `results/probe.log` on the PO's PC, or a recent commit on the `local-ci` branch. If it's silent, ask the PO to start Docker Desktop and `START-LOCAL-CI.cmd`.
4. Read CLAUDE.md §6 (process), this file, then `docs/04-tasks/TASKS.md` and `docs/implementation-status.md`.

## Process (CLAUDE.md §6 is authoritative)

- **Classes and reviews:** C1 Lead spot-check · C2/C3/docs: one Sonnet `code-reviewer` (also checks tests) · C4: one **combined** Opus review (code + security, one report), except crypto/keys, billing/entitlements and SMS/notification ingestion, which keep two Opus reviewers. Re-reviews are delta-only on Sonnet. Only blocker/major (or security Medium+ / "before merge") trigger a round; everything else becomes `FU-###`.
- **Implementers:** C2/C3 Sonnet (C3 implementer writes its own short design note first). C4 Opus; its design note on Opus only for crypto/keys, billing/entitlements, SMS ingestion, otherwise Sonnet. Fix rounds: start a **fresh** agent with a short brief (cheaper than resuming a large context).
- **Verification ladder:** (1) local in the cloud workspace — format, analyze, lints, `flutter test`/`dart test`, `dotnet build -warnaserror`, `dotnet format`, backend unit tests; (2) PC runner on push to `task/**` — Android APK + permission check + Android unit tests + lint, backend Testcontainers tests; (3) GitHub only per batch (`batch/**`) or opt-in `ci/<task-id>` for Swift/iOS and emulator/simulator tests. `db-platform` may need `workflow_dispatch` on a new `ci/` branch.
- **Batches:** ~5 reviewed tasks merged in order onto `batch/<date>-<n>` (push the branch at `main` first, then merge tasks), run local checks on the merged tree, add the status-doc updates, push, one full GitHub run, then one PR merged with a **merge commit**. PO authorised the Lead to merge green, approved PRs.
- **Limits and quirks:** at most 2 tasks at once (PO may raise it). The git proxy allows 2 concurrent ops per repo; on 429 wait 5 s and retry once. `gh` works only as `gh api` (REST). Agents can't delete remote branches (proxy); the PO deletes leftover `ci/*` and proof branches. Known flakes: GitHub Android NDK download / Maven 429 (rerun failed jobs), `SeededSeriesTests` on the PC (FU-055), interleaved xcodebuild lines (tolerated since batch 2).
- **Copy deck checks:** `python3 docs/workflow/tools/copy_deck_check.py docs/02-design/copy-deck.md`.

## Progress: 28 of 186 tasks done (15.1%)

DONE: T-001…T-007, T-012, T-013, T-014, T-015, T-016, T-022, T-026, T-027, T-028, T-034, T-060, T-122…T-129, T-138, T-139. **Merged but open:** T-136 (IdP evidence), T-165 (device run).

| Milestone | Done | Total |
|---|---|---|
| M0 | 16 | 28 |
| M1 | 1 | 29 |
| M2 | 1 | 29 |
| M5 | 10 | 35 |
| M3, M4, M6, M7 | 0 | 65 |

The PO asked for this progress table in every update.

**Merged batches:** batch 1 (#28: T-015, T-034, T-129, T-139); batch 2 (#29: T-016, T-060, FU-030 lint hardening, workflow fixes).

## In flight

Nothing. Batch 3 has not started.

## Ready next (dependencies done)

- **App core (unblocked by T-016):** T-017, T-018, T-019 schema batches A–C (C4, Opus; T-017 also gets the FTS short-query table proposal from T-016 and must handle FU-071 m-3 CHECK constraints). T-148 backup file format (C4 crypto, two reviewers).
- **Parsing (unblocked by FU-030):** T-032 template registry + registry_lint (C3, Sonnet). Then T-033.
- **Native:** T-008 Android SMS receiver → spool → headless engine spike (C4, SMS ingestion: Opus note + two reviewers; must use `SpoolKey`, FU-068, and register `SecretStoreRegistration` in the headless engine). T-009 iOS App Intent spike. T-159 / T-160 OCR hosts (C3).
- **Backend:** T-130 / T-131 purchase verification (C4 billing; T-130 first needs a design fix for FU-052 S-2, the idempotency session holding a DB connection). T-181 / T-182 attestation and seat-key verifiers. T-140.
- **UI:** T-053 ZaghlolAvatar (needs UX to confirm the dark tokens, FU-047).
- **Human:** T-058 native-speaker copy review, T-088 Rive file.

## Waiting on the PO (Amr)

1. **Operator sign-in provider** (T-136 Q1/Q2, "decide later"): needed to close T-136 and before T-186 goes live (FU-060 S-4). Google needs a design change; Entra needs a token-lifetime policy ≤ 60 min.
2. **D-41** local gold-price provider, before T-127 go-live.
3. **Copy decisions:** Q-20, Q-23, Q-24, Q-25, Q-33, Q-36; Q-44 (restore-notice wording, UX); later Q-17, OQ-09 brand clearance.
4. **Inputs:** IBM Plex Sans Arabic TTFs (FU-044); synthetic-able SMS samples (OQ-04/OQ-18, T-031); Rive file (T-088).
5. **Device runs:** T-165; T-015 device checklist (StrongBox phone; iPhone reboot + background read before unlock); T-060 manual steps (FU-067); reference Android phone and iPhone 12 timings (T-007).
6. **Housekeeping:** delete leftover branches `ci/FU-030`, `ci/T-016`, `task/T-003-throwaway-red`, `task/T-165-proof`, `task/T-004-scratch`, `task/T-004-negctl`, `task/T-007-proof*`, `task/T-015-proof-*`, `scratch/*`.
7. **PC:** keep Docker Desktop (Linux containers, 10 GB in `.wslconfig`) and `START-LOCAL-CI.cmd` running while agents work; restart the runner after a new `runner.ps1` is deployed.

## Waiting on the architect or UX

- T-026 copy questions Q-03, Q-12, Q-13, Q-15, Q-16, Q-18 (Q-15/Q-16 block T-029); T-027/T-028 questions Q-19, Q-22, Q-27, Q-29, Q-34, Q-39, Q-41.
- Dark tokens §0 left undefined (FU-047) before T-053.
- T-122 code #15 and security F13 doc fixes; FU-025 account hard-delete wording.

## Decisions recorded this session

- D-70: database key stored with Zaghlol's own native channel, not `flutter_secure_storage` (T-015).
- K_spool is TEE-backed AndroidKeyStore, never StrongBox (Lead, T-060 review C1); K_db keeps StrongBox with fallback.
- Canonical merchant key keeps single spaces between tokens (parsing-engine §5, T-034).
- T-128: a lost sync reply waits for the next day; no server-side person-name detection (PO accepted).
- Batch CI workflow, combined C4 review, status docs per batch (PO, #27).

## Progress page

- Dashboard artifact: https://claude.ai/artifact/JLtixDQ3FQ7aogVaWxRoEG (not refreshed since 2026-11-08; see `docs/workflow/tools/README.md`).
