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
- **Speed-ups (PO, 2026-11-11):** up to 4 tasks at once on separate lanes; builders follow `docs/workflow/self-check.md`; non-crypto C4 builders write their own design note; Sonnet builds C4 tasks except crypto/keys, billing, SMS ingestion, migrations and data-deleting code; the Lead verifies small fix deltas itself.
- **Limits and quirks:** The git proxy allows 2 concurrent ops per repo; on 429 wait 5 s and retry once. `gh` works only as `gh api` (REST). Agents can't delete remote branches (proxy); the PO deletes leftover `ci/*` and proof branches. Known flakes: GitHub Android NDK download / Maven 429 (rerun failed jobs), `SeededSeriesTests` on the PC (FU-055), interleaved xcodebuild lines (tolerated since batch 2).
- **Copy deck checks:** `python3 docs/workflow/tools/copy_deck_check.py docs/02-design/copy-deck.md`.

## Progress: 46 of 186 tasks done (24.7%)

DONE: T-001…T-007, T-012…T-020, T-022, T-025, T-026, T-027, T-028, T-030, T-032…T-035, T-045, T-050, T-060, T-073, T-074, T-075, T-122…T-131, T-134, T-138, T-139, T-148. **Merged but open:** T-008 (device rows AC1/AC2), T-038 (instrumented golden run after T-039), T-136 (IdP evidence), T-165 (device run).

| Milestone | Done | Total |
|---|---|---|
| M0 | 21 | 28 |
| M1 | 7 | 29 |
| M2 | 4 | 29 |
| M5 | 13 | 35 |
| M6 | 1 | 19 |
| M3, M4, M7 | 0 | 46 |

The PO asked for this progress table in every update.

**Merged batches:** #28, #29, #32, #33, #34 (batch 5: FU-094, T-019, T-074, T-035), batch 6 (`batch/2026-11-11-5`: T-134, T-148, T-075, T-038, T-020, T-025). Next free follow-up number: **FU-104**.

## In flight

- T-039 Android encrypted spool + spool host API (Opus build, resumed after a restart; worktree `/home/claude/wt-T-039`). Then two Opus reviews. Its emulator step must run T-038's instrumented golden suite (FU-101).
- T-046 IngestRawMessages (built, `task/T-046-ingest` @ 8e904fd): code + security reviews (Opus) running. Ships `RulesOnlyCategorizer`; wire T-075 through `buildIngestRawMessages(categorizer:)` (small follow-up task or T-047).
- T-159 Android OCR: Tesseract-only rework committed locally in `/home/claude/wt-T159-fix`, not pushed — waiting for the PO's `tesseract4android-4.9.0.aar`.
- PC runner back online since ~08:10 UTC 2026-11-11.

## Ready next (dependencies done)

- **App core:** T-021 redacting diagnostic log (C3), T-051 payday cycle engine (C3), T-077 bulk edit/undo (C3), T-112 prices/FX store (C2), T-141 BackendClient (C4), T-142 contribution outbox (C4), T-183 request-binding library (C4); T-047 after T-039 + T-046; T-040 after T-039 (FU-101 first).
- **Native:** T-042 inbox reader (C4), T-009 iOS App Intent spike, T-010/T-011 spikes, T-178 / T-180.
- **Parsing:** bank templates T-036, T-037, T-068–T-072 wait for real SMS samples (OQ-04); T-109 voice-phrase parser (C3).
- **Backend:** T-133 Google RTDN (C4 billing), T-181 / T-182 verifiers (C4), T-132 after T-184, T-140 (hosting).
- **UI:** T-053 ZaghlolAvatar (needs UX dark tokens, FU-047).
- **Human:** T-058 copy review, T-059 merchant seed list (+ Arabic aliases from T-075), T-088 Rive file.

## Waiting on the PO (Amr)

1. **Operator sign-in provider** (T-136 Q1/Q2, "decide later"): needed to close T-136 and before T-186 goes live (FU-060 S-4). Google needs a design change; Entra needs a token-lifetime policy ≤ 60 min.
2. **D-41** local gold-price provider, before T-127 go-live.
3. **Copy decisions:** Q-20, Q-23, Q-24, Q-25, Q-33, Q-36; Q-44 (restore-notice wording, UX); later Q-17, OQ-09 brand clearance.
4. **Inputs:** `tesseract4android-4.9.0.aar` in `C:\\Projects\\Zaghlol\\` (T-159); Play Console service account, product IDs, quota and a tester order (T-130 §13); App Store Connect IAP key, bundle/team ID, products, sandbox-in-production, Family Sharing, sandbox testers (T-131 §12 questions 1–7); T-035 Guard Q1–Q6 (provisional defaults in code); T-019 data questions 1–4; T-134 questions 1–4 and T-148 questions 1–3 (in their design notes); T-046 Q1–Q3; T-039 Q1–Q2; T-075 PO-1…PO-4; T-020 key defaults; T-025 14-day maxAge; test phones + second SIM for SPK-01 (T-008 Q1); IBM Plex Sans Arabic TTFs (FU-044); synthetic-able SMS samples (OQ-04/OQ-18, T-031); Rive file (T-088).
5. **Device runs:** T-165; T-015 device checklist (StrongBox phone; iPhone reboot + background read before unlock); T-060 manual steps (FU-067); reference Android phone and iPhone 12 timings (T-007).
6. **Housekeeping:** delete leftover branches `ci/FU-030`, `ci/T-016`, `ci/T-017`, `ci/T-018`, `ci/T-008`, `ci/T-131`, `task/T-130-negproof`, `task/T-003-throwaway-red`, `task/T-165-proof`, `task/T-004-scratch`, `task/T-004-negctl`, `task/T-007-proof*`, `task/T-015-proof-*`, `scratch/*`.
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
