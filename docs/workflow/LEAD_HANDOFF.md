# Lead handoff — read this first

_Last updated: 2026-11-08 (afternoon) by the Lead session. Update it whenever the state below changes._

**All state is in the repo.** Agents from earlier sessions can't be messaged; start new ones from their branches.

## Process (see CLAUDE.md §6)

- **Reviewers per class:** C1 Lead spot-check · C2 and docs-only one `code-reviewer` (Sonnet) · C3 `code-reviewer` + `test-engineer` (Sonnet) · C4 `code-reviewer` (Opus) + `security-privacy-reviewer` (Opus) + `test-engineer` (Sonnet).
- **Rounds:** only blockers/majors trigger another round; minors/nits become `FU-###`. Re-reviews look at the delta only, by the reviewer who raised it.
- **Agent roles:** `ux-designer` (and other roles without Bash) can't create worktrees or push. Run those tasks as `general-purpose` with "act as the role in `.claude/agents/<role>.md`".
- **Parallel agents:** each agent works in its own `git worktree` under `/home/claude/wt-<task>`. The git proxy allows 2 concurrent git ops per repo.
- **CI:** read with `curl -s "https://api.github.com/repos/Amr905/zaghlol/actions/runs?branch=<branch>"`. Android Maven HTTP 429s are flaky; re-run with `POST .../actions/runs/<id>/rerun-failed-jobs` (JSON body, `Content-Type: application/json`). Local runner: `docs/workflow/local-ci.md` (no results published yet).
- **Merging:** the `main` ruleset (26756600) is **Active** (PR required). The **PO authorised the Lead (2026-11-08) to merge approved PRs**: when all reviews are APPROVED and CI on the PR head is green, squash-merge via `PUT /repos/Amr905/zaghlol/pulls/<n>/merge` (`gh` has no valid token here). If the PR branch is behind code that changes its checks (e.g. new lint rules), merge `main` into it and wait for green CI first.
- **Copy deck checks:** `python3 docs/workflow/tools/copy_deck_check.py docs/02-design/copy-deck.md`.

## Progress: 11 of 186 tasks done

DONE: T-001, T-002, T-003, T-005, T-006, T-012, T-014, T-026, T-027, T-028, T-122. T-165 is merged but needs a device run.

## In flight

| Task | State | Next step |
|---|---|---|
| T-123 Signing service (C4) | Implemented on `task/T-123-signing` @ `9035f64`, backend-ci 42489960257 green. Three C4 reviews running; reports go to `docs/05-reviews/T-123-{code,security,tests}.md` on local `review/T-123-*` branches. | Consolidate into `docs/05-reviews/T-123.md`, fix round if needed, PR, merge. Then T-138 (C3). |
| T-004 Pigeon (C2) | Implementer running on `task/T-004-pigeon`. Owns `pubspec.lock` this wave. | One Sonnet review, PR, merge. Then T-007 (C4, also changes the lockfile). |
| T-022 Design tokens (C2) | Implementer running on `task/T-022-design-tokens`. Must not change the lockfile. May harden lint rule 2 (FU-031). | One Sonnet review, PR, merge. |
| T-165 No OS backups | Merged (`189acf7`), IN_REVIEW. | DONE after `docs/05-reviews/T-165-device.md` passes on a release-candidate device run (PO, later). |

## Ready next (dependencies DONE)

- **App:** T-007 SQLCipher spike (C4, after T-004 for the lockfile), spikes T-010 (C3) and T-011 (C2), T-013 normalization (C3, needs T-012 ✓), T-015 after T-007.
- **Lint hardening (FU-030):** must land before T-032/T-033 parsing work. Ask the task-planner to add a small task, or fold it into T-013.
- **Backend:** T-138 (C3) after T-123; T-124 after T-123; T-125 and T-126 (need T-122 ✓, T-123).
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
