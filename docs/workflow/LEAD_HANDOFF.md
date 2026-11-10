# Lead handoff — read this first

_Last updated: 2026-11-10 by the Lead session. Update it whenever the state below changes._

**All state is in the repo.** Agents from earlier sessions can't be messaged; start new ones from their branches.

## Process (see CLAUDE.md §6)

- **Reviewers per class (Balanced, 2026-11-08):** C1 Lead spot-check · C2, C3 and docs-only: one `code-reviewer` (Sonnet), which also checks tests · C4: `code-reviewer` (Opus, also checks tests) + `security-privacy-reviewer` (Opus). Re-reviews are delta-only, on Sonnet. At most 2 tasks at once.
- **Rounds:** only blockers/majors trigger another round; minors/nits become `FU-###`. Re-reviews look at the delta only, by the reviewer who raised it.
- **Agent roles:** `ux-designer` (and other roles without Bash) can't create worktrees or push. Run those tasks as `general-purpose` with "act as the role in `.claude/agents/<role>.md`".
- **Parallel agents:** each agent works in its own `git worktree` under `/home/claude/wt-<task>`. The git proxy allows 2 concurrent git ops per repo.
- **CI:** read with `curl -s "https://api.github.com/repos/Amr905/zaghlol/actions/runs?branch=<branch>"`. Android Maven HTTP 429s are flaky; re-run with `POST .../actions/runs/<id>/rerun-failed-jobs` (JSON body, `Content-Type: application/json`). Local runner: `docs/workflow/local-ci.md` (no results published yet).
- **Merging:** the `main` ruleset (26756600) is **Active** (PR required). The **PO authorised the Lead (2026-11-08) to merge approved PRs**: when all reviews are APPROVED and CI on the PR head is green, squash-merge via `PUT /repos/Amr905/zaghlol/pulls/<n>/merge` (`gh` has no valid token here). If the PR branch is behind code that changes its checks (e.g. new lint rules), merge `main` into it and wait for green CI first.
- **Copy deck checks:** `python3 docs/workflow/tools/copy_deck_check.py docs/02-design/copy-deck.md`.

## Progress: 20 of 186 tasks done (10.8%)

DONE: T-001…T-007, T-012, T-013, T-014, T-022, T-026, T-027, T-028, T-122, T-123, T-124, T-125, T-126, T-138. T-165 is merged but needs a device run.

| Milestone | Done | Total |
|---|---|---|
| M0 | 14 | 28 |
| M5 | 6 | 35 |
| M1–M4, M6, M7 | 0 | 123 |

The PO asked for this progress table in every update.

## In flight (limit: 2 tasks at once)

Nothing in flight. T-165 is merged, IN_REVIEW, waiting for a device run.

**Session notes (2026-11-09):** project agent types (`code-reviewer`, `backend-engineer`, …) only appear after the repo is registered in the session; before that, run them as `general-purpose` with the role file. For a fix round, start a fresh agent with a short brief instead of resuming the implementer (cheaper). `gh` works through `gh api` (REST only, no GraphQL). The PC runner now runs in Linux containers (#17, #18) and is reliable; agents should read it first.

## Ready next (dependencies DONE)

- **App:** T-015 secure DB key bootstrap (C4, Opus design note: crypto/keys), spikes T-010 (C3) and T-011 (C2), T-032/T-034 parsing (after FU-030 lint hardening).
- **Lint hardening (FU-030):** must land before T-032/T-033 parsing work. T-013 is merged without it; ask the task-planner to add a small task.
- **Backend:** T-127 prices (BLOCKED only for go-live; can be built with fakes, Sonnet); T-128 sync after T-127, T-136 operator auth (unblocks all /admin routes, FU-058); T-130 needs the FU-052 S-2 idempotency design fix first.
- **Docs:** T-029 (ARB from copy deck part 1) needs T-023 and the Q-15/Q-16 answers.
- **External:** T-088 (Rive file), T-058 (native-speaker review, now unblocked: all three copy-deck parts are merged).

## Waiting on the PO

1. Start Docker Desktop alongside `START-LOCAL-CI.cmd` (backend tests need it). The runner hasn't published to `local-ci` yet.
2. Copy questions needing a PO/legal call: Q-20 (financial-advice line on tips), Q-23 (Zakah/Smart ROI disclaimer + scholar sign-off, before those flags go on), Q-24 (halal mention and example-rate owner), Q-25 (never-roasted categories), Q-33 (category name on redacted alerts), Q-36 (subscription renewal wording, legal).
3. Later: the T-165 device run, OQ-09 brand clearance, Q-17 («التنبيهات» vs «الإشعارات»).
4. Housekeeping: delete branches `task/T-003-throwaway-red` and `task/T-165-proof`.

## Waiting on the architect or UX (before T-029)

- T-026 copy questions Q-03, Q-12, Q-13, Q-15, Q-16, Q-18 (Q-15/Q-16 block T-029); T-027/T-028 questions Q-19, Q-22, Q-27, Q-29, Q-34, Q-39, Q-41.
- T-122 code #15 and security F13 doc fixes; FU-025 account hard-delete wording.

## Progress page

- Dashboard artifact: https://claude.ai/artifact/JLtixDQ3FQ7aogVaWxRoEG. Refresh it per `docs/workflow/tools/README.md`. The `datasets/tasks` document was at version 5 (not refreshed this session).
