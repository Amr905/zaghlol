# Lead handoff — read this first

_Last updated: 2026-11-12 (Cairo) by the Lead session. Update it whenever the state below changes._

**All state is in the repo.** Agents from earlier sessions can't be messaged; start new ones from their branches. Where this file and the repo disagree, the repo wins.

## Start of a session (in order)

1. Attach the repo with push access (`add_repo` Amr905/zaghlol, access `push`), clone, register it. Project agent types (`code-reviewer`, `backend-engineer`, …) appear only after registration; before that, run roles as `general-purpose` with "act as `.claude/agents/<role>.md`".
2. Install the toolchains once: `bash docs/workflow/tools/cloud-sdk.sh`, then `export PATH=/home/claude/sdk/flutter/bin:/home/claude/sdk/dotnet:$PATH` (needs package installs allowed in the Claude network settings; they are, since 2026-11-10).
3. Check the PC runner is alive: newest `results/probe.log` on the PO's PC, or a recent commit on the `local-ci` branch. If it's silent, ask the PO to start Docker Desktop and `START-LOCAL-CI.cmd`.
4. Read CLAUDE.md §6 (process), this file, then `docs/04-tasks/TASKS.md` and `docs/implementation-status.md`.

## Process (CLAUDE.md §6 is authoritative)

- **Batch review (PO, 2026-11-11 22:00):** no per-task reviewers. Build 5 tasks (≤4 at once) → `BUILT`; assemble the batch branch; **one review round** (`/review-batch`): one `code-reviewer` over the whole batch diff (Opus if any C4, else Sonnet) + one Opus `security-privacy-reviewer` scoped to crypto/billing/SMS-ingestion tasks; one report `docs/05-reviews/batch-<n>.md`; one fix agent per lane; Lead delta check for ≤30-line fixes, else one delta-only Sonnet re-review; a still-failing task is reverted out of the batch. Batch 9 was the first run: 2 review agents + 1 fix + 1 re-review instead of ~6 reviewers.
- **Classes and reviews (what the batch round must cover):** C1 Lead spot-check · C2/C3/docs: one Sonnet `code-reviewer` (also checks tests) · C4: one **combined** Opus review (code + security, one report), except crypto/keys, billing/entitlements and SMS/notification ingestion, which keep two Opus reviewers. Re-reviews are delta-only on Sonnet. Only blocker/major (or security Medium+ / "before merge") trigger a round; everything else becomes `FU-###`.
- **Implementers:** C2/C3 Sonnet (C3 implementer writes its own short design note first). C4 Opus; its design note on Opus only for crypto/keys, billing/entitlements, SMS ingestion, otherwise Sonnet. Fix rounds: start a **fresh** agent with a short brief (cheaper than resuming a large context).
- **Verification ladder:** (1) local in the cloud workspace — format, analyze, lints, `flutter test`/`dart test`, `dotnet build -warnaserror`, `dotnet format`, backend unit tests; (2) PC runner on push to `task/**` — Android APK + permission check + Android unit tests + lint, backend Testcontainers tests; (3) GitHub only per batch (`batch/**`) or opt-in `ci/<task-id>` for Swift/iOS and emulator/simulator tests. `db-platform` may need `workflow_dispatch` on a new `ci/` branch.
- **Batches:** ~5 built tasks merged in order onto `batch/<date>-<n>` (push the branch at `main` first, then merge tasks), run local checks on the merged tree, add the status-doc updates, push, one full GitHub run, then one PR merged with a **merge commit**. PO authorised the Lead to merge green, approved PRs.
- **Speed-ups (PO, 2026-11-11):** up to 4 tasks at once on separate lanes; builders follow `docs/workflow/self-check.md`; non-crypto C4 builders write their own design note; Sonnet builds C4 tasks except crypto/keys, billing, SMS ingestion, migrations and data-deleting code; the Lead verifies small fix deltas itself.
- **Limits and quirks:** The git proxy allows 2 concurrent ops per repo; on 429 wait 5 s and retry once. `gh` works only as `gh api` (REST). Agents can't delete remote branches (proxy); the PO deletes leftover `ci/*` and proof branches. Known flakes: GitHub Android NDK download / Maven 429 (rerun failed jobs), `SeededSeriesTests` on the PC (FU-055), interleaved xcodebuild lines (tolerated since batch 2), iOS `SecretStoreTests.testExistingKeyWinsOverANewCandidate` missing from the xcodebuild log (3× on 2026-11-11; rerun; root cause open), Android API 35 emulator hang / `adb: device offline` in db-platform and sms-spike (cancel at the 75-min timeout, rerun failed jobs), Ubuntu apt DNS outage on GitHub runners (`Temporary failure resolving *.ubuntu.com`, db-platform host job; still failing at 22:00 on 2026-11-11), PC-runner timing tests failing under load (catalog seed load, categorizer perf, guard perf, ingest benchmark — pass in the cloud).
- **Restarts:** server and cloud-workspace restarts kill running agents several times a day. Brief every agent to commit early and push often. On restart: check each worktree for live processes (`ps aux`, `readlink /proc/<pid>/cwd`) and for pushed/unpushed commits before relaunching; relaunch as a "resume" agent pointed at the same worktree.
- **Batch scripts:** never chain `git commit` after `git merge` without first checking `git diff --name-only --diff-filter=U` (a conflicted merge got committed with markers once; fixed before push). Local CI step logs (`*.log`) are git-ignored; don't `git add -A` in a worktree where the step script ran without checking `git status`.
- **Copy deck checks:** `python3 docs/workflow/tools/copy_deck_check.py docs/02-design/copy-deck.md`.

## Progress: 60 of 186 tasks done (32.3%)

DONE: T-001…T-007, T-012…T-021, T-022, T-025…T-028, T-030, T-032…T-035, T-038…T-042, T-045, T-046, T-047, T-050, T-051, T-060, T-073…T-075, T-077, T-112, T-122…T-131, T-133, T-134, T-138, T-139, T-148, T-182, T-184. **Merged but open:** T-008 (device rows AC1/AC2), T-136 (IdP evidence), T-165 (device run).

| Milestone | Done | Total |
|---|---|---|
| M0 | 22 | 28 |
| M1 | 14 | 29 |
| M2 | 5 | 29 |
| M4 | 1 | 17 |
| M5 | 16 | 35 |
| M6 | 1 | 19 |
| M3, M7 | 0 | 29 |

The PO asked for this progress table in every update.

**Merged batches:** #28, #29, #32–#36 (batch 7), #37 batch 8 (T-041 + T-042, T-051), batch 9 (`batch/2026-11-11-9`: T-021, T-040, T-047, T-077, T-182, T-184 + the batch-review workflow). Next free follow-up number: **FU-115**.

**Lessons:** never chain `git commit` after `git merge` in one script without checking for conflicts. Server/cloud restarts happen often: brief agents to commit early and push often; on restart, check worktrees for live processes (`ps`, `/proc/<pid>/cwd`) before relaunching.

## In flight (2026-11-12 Cairo)

1. **Batch 9** (`batch/2026-11-11-9`): reviews in `docs/05-reviews/batch-9.md` and `batch-9-security.md`, all six tasks APPROVED (21-1 fixed, Lead delta check; 77-1 fixed, delta re-review). backend-ci and db-platform green on e7bcdb2 (later commits touch only Dart and docs); app-ci on the final head. **Next:** merge the PR with a merge commit when app-ci is green.
2. **T-159 Android OCR:** waiting for the PO's `tesseract4android-4.9.0.aar` (`/home/claude/wt-T159-fix`, unpushed).
3. **PC runner** silent since 2026-11-11 22:29; T-040 negative proofs 6b and 14 still pending on it (FU-111).

Next free follow-up number: **FU-115**.

## Ready next (dependencies done)

- **Ingestion chain (Android):** T-043 notification listener (T-040 merged in batch 9) (design note on `task/ingest-notes-combined`; T-043 owns the listener, its intake thread and its manifest entries); T-048 catch-up scan after the PO decides FU-109 M-1 (must restart the scan on `INVALID_ARGUMENT`, implement `CatchUpScheduler`).
- **App core:** T-052 home read model (needs T-049?), T-079 bulk-edit UI wiring (FU-114), T-113 net worth (needs T-096), T-141 BackendClient (C4), T-142 contribution outbox (C4), T-183 request-binding library (C4), T-149/T-150 backup.
- **Backend:** T-132 (T-184 done; take FU-112 PO Q1 backfill), T-185 (FU-112 lock order), T-186 (FU-112 184-2); T-181 attestation verifiers (C4); T-140 (hosting); FU-107 M-1 (dead-lettered notification rows never retried → Gold kept) before go-live.
- **Native/iOS:** T-009 iOS App Intent spike, T-010/T-011 spikes, T-178 / T-180.
- **Parsing:** bank templates T-036, T-037, T-068–T-072 wait for real SMS samples (OQ-04).
- **UI:** T-053 ZaghlolAvatar (needs UX dark tokens, FU-047).
- **Human:** T-058, T-059, T-088.

## Waiting on the PO (Amr)

1. **Operator sign-in provider** (T-136 Q1/Q2, "decide later"): needed to close T-136 and before T-186 goes live (FU-060 S-4). Google needs a design change; Entra needs a token-lifetime policy ≤ 60 min.
2. **D-41** local gold-price provider, before T-127 go-live.
3. **Copy decisions:** Q-20, Q-23, Q-24, Q-25, Q-33, Q-36; Q-44 (restore-notice wording, UX); later Q-17, OQ-09 brand clearance.
4. **Inputs:** `tesseract4android-4.9.0.aar` in `C:\\Projects\\Zaghlol\\` (T-159); Play Console service account, product IDs, quota and a tester order (T-130 §13); App Store Connect IAP key, bundle/team ID, products, sandbox-in-production, Family Sharing, sandbox testers (T-131 §12 questions 1–7); T-035 Guard Q1–Q6 (provisional defaults in code); T-019 data questions 1–4; T-134 questions 1–4 and T-148 questions 1–3 (in their design notes); T-046 Q1–Q3; T-039 Q1–Q2; T-075 PO-1…PO-4; T-020 key defaults; T-025 14-day maxAge; T-112 manual FX override (OQ); T-133 Q1–Q6 (Pub/Sub setup, push account, refund policy, chargeback reviews, test vector, quota); **FU-109 M-1: user-added phone-number senders and inbox history (before T-048)**; T-040/T-043/T-041/T-047 questions (spool share, user notification senders, missed notifications, held messages, NoSms Home banner, missed-notification copy, banner priority, rule-save copy); T-051 Q1–Q5; T-182 Q1 (K_seat emergency rotation); T-040 Q1 80 % SMS spool share; T-184 Q1–Q2 (pre-T-132 purchases, vacant seat); test phones + second SIM for SPK-01 (T-008 Q1); IBM Plex Sans Arabic TTFs (FU-044); synthetic-able SMS samples (OQ-04/OQ-18, T-031); Rive file (T-088).
5. **Device runs:** T-165; T-015 device checklist (StrongBox phone; iPhone reboot + background read before unlock); T-060 manual steps (FU-067); reference Android phone and iPhone 12 timings (T-007).
6. **Housekeeping:** delete leftover branches `ci/T-040`, `ci/T-184`, `task/T-040-negproof-a/b/c/d`, `review/batch-9`, `review/batch-9-security`, `ci/FU-030`, `ci/T-016`, `ci/T-017`, `ci/T-018`, `ci/T-008`, `ci/T-131`, `ci/T-134`, `ci/T-148`, `ci/T-038`, `ci/T-039`, `ci/T-133`, `ci/T-133-neg`, `task/T-130-negproof`, `task/T-003-throwaway-red`, `task/T-165-proof`, `task/T-004-scratch`, `task/T-004-negctl`, `task/T-007-proof*`, `task/T-015-proof-*`, `scratch/*`.
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
- 2026-11-11 (Lead): shared text skips the Capture Guard on both platforms; Pigeon `encryptedConfig` → plaintext, native encrypts; possible duplicates use `low_confidence` + reason (no schema change); `capture_senders` stays keyed by sender, DAO refuses channel conflicts; T-041 owns `CaptureRuntime.kt` and the Pigeon changes, build order T-041 + T-042 → T-040 → T-043, T-047 lands with T-040; devSms spike receiver stays until T-040; FU-094 busy handler (Dart VM profiler SIGPROF cut SQLite busy sleeps); FU-101 portable-regex lint rejects classes starting with `:` (Android ICU).
- Lead recommendation to the PO on FU-109 M-1 (user-added phone-number senders): live capture only with a financial-looking filter, consent text, separate opt-in "scan past 3 months", never put their unparsed messages in review.

## Progress page

- Dashboard artifact: https://claude.ai/artifact/JLtixDQ3FQ7aogVaWxRoEG (not refreshed since 2026-11-08; see `docs/workflow/tools/README.md`).
