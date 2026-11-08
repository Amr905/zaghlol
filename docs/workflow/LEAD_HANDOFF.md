# Lead handoff — read this first

_Last updated: 2026-11-08 by the Lead session. Update it whenever the state below changes._

The previous Lead conversation got too long and expensive, so the work moved to a fresh session. **All state is in the repo.** Agents from earlier sessions can't be messaged; start new ones from their branches.

## Process (changed 2026-11-08; see CLAUDE.md §6)

- **Reviewers per class:**
  - C1: Lead spot-check.
  - C2 and docs-only: one code-reviewer on Sonnet.
  - C3: code-reviewer + test-engineer, both on Sonnet.
  - C4: code-reviewer (Opus) + security (Opus) + test-engineer (Sonnet).
- **Rounds:** only blocker or major findings trigger another round. Minors and nits become `FU-###` follow-ups. Re-reviews look at the delta only, and only by the reviewer who raised the finding.
- **Models:** Sonnet by default for C2 and C3, design notes included. Opus only for C4.
- **Fast checks:** use the local runner on the PO's PC; see `docs/workflow/local-ci.md`. GitHub Actions stays the merge gate. Read CI with `curl -s https://api.github.com/repos/Amr905/zaghlol/actions/runs?branch=<branch>`, which goes through the proxy with auth.
- **Merging:** once the `main` ruleset is Active, merge only through a PR: `gh pr create --base main --head <branch>`, then `gh pr merge --squash`. Commit the consolidated `docs/05-reviews/T-###.md` before merging.

## Progress: 6 of 186 tasks done

T-001, T-003, T-005, T-006, T-012 and T-026 are DONE. T-165 is merged but needs a device run.

## In flight

| Task | State | Next step |
|---|---|---|
| T-122 Backend EF model | **All three reviews APPROVED** at `d5943be` (backend-ci 42407789072). The review is in `docs/05-reviews/T-122.md` on main. | Waiting on the PO to set ruleset 26756600 ("main requirs PR") to **Active**. Check with `curl -s https://api.github.com/repos/Amr905/zaghlol/rulesets/26756600`. Then PR and squash-merge, set DONE, and update TASKS.md. |
| T-002 Custom lints (C2) | Implementer stopped by the usage limit mid-work. Branch `task/T-002-custom-lints` @ `0f52efa`. | Start a fresh `flutter-core-engineer` (Sonnet) to finish from the branch: green app-ci, no temporary CI commits. Then one code-reviewer on Sonnet. |
| T-165 No OS backups | Merged (`189acf7`), status IN_REVIEW. | It becomes DONE only after `docs/05-reviews/T-165-device.md` passes on a release-candidate device run (PO, later). |

## Ready to start (dependencies DONE)

- **App:**
  - T-004 Pigeon (C2). It touches the lockfile, so don't run it at the same time as T-002.
  - T-014 Result/Failure types (C2, `packages/zaghlol_domain`).
  - T-022 Design tokens and themes (C2).
  - T-007 SQLCipher spike (C4).
  - Spikes T-010 (C3) and T-011 (C2).
- **Docs:** T-027 and then T-028, copy deck parts 2 and 3. Both edit `copy-deck.md`, so run them one at a time. T-027 also covers the S-40 assets section (F-18).
- **Backend, after T-122 merges:** T-123 (C4), then T-138 (C3). Run them one at a time, because they share the backend files.
- **External:** T-088, the Rive file from the illustrator.

## Waiting on the PO

1. Set the `main` ruleset to Active. This blocks the T-122 merge.
2. Start Docker Desktop and `START-LOCAL-CI.cmd` (local runner v2).
3. Later: the T-165 device run, OQ-09 brand clearance (bank and wallet names), and Q-17 («التنبيهات» vs «الإشعارات»).
4. Housekeeping: delete the branches `task/T-003-throwaway-red` and `task/T-165-proof`.

## Waiting on the architect or UX (before T-029)

- T-026 copy questions Q-03, Q-12, Q-13, Q-15, Q-16 and Q-18. Q-15 and Q-16 block T-029.
- R2-4: add the hidden-accounts row and list to the S-40 spec.
- T-122 code #15 and security F13: doc fixes.

## Progress page

- Dashboard artifact: https://claude.ai/artifact/JLtixDQ3FQ7aogVaWxRoEG. Refresh it per `docs/workflow/tools/README.md`.
- The `datasets/tasks` document is at version 4.
