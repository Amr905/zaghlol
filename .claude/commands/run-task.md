---
description: Implement and review one task from the board (Phase 5–6 loop)
argument-hint: <T-###>
---

Run task $ARGUMENTS through implementation and review.

1. Read `docs/04-tasks/tasks/$ARGUMENTS.md` and `docs/workflow/model-routing.md`. Check that all dependencies are DONE in `docs/04-tasks/TASKS.md`; if not, stop.
2. Verify the complexity class. If it's C3/C4 and the task has no Design note, delegate to `solution-architect` first to write a short one (sonnet, except opus for C4 crypto/keys, billing/entitlements and SMS/notification ingestion).
3. Set status IN_PROGRESS. Delegate to the task's agent, passing the task file path, with the model the class dictates (override the agent's default with the `model` parameter if needed).
4. Read the diff yourself. Then set IN_REVIEW and run only the reviews the class requires (CLAUDE.md §6):
   - C1: you spot-check the diff and CI;
   - C2 and docs-only: `code-reviewer` on sonnet;
   - C3: `code-reviewer` on sonnet (also checks tests);
   - C4: one combined review on opus (`code-reviewer` also acting as `security-privacy-reviewer`, also checks tests); two separate opus reviewers only for crypto/keys, billing/entitlements and SMS/notification ingestion.
   Re-reviews are delta-only on sonnet. Run at most 2 tasks at once.
5. Only blocker or major findings go back to the implementer, who may also fix trivial minors in the same pass. Log every other minor or nit as an `FU-###` follow-up and don't block on it. Only the reviewers who raised a blocker or major re-review, and only the delta. After two failed rounds, bump the class by one and re-delegate.
6. When all verdicts are APPROVED and the PC runner is green, the task is ready for the next batch (CLAUDE.md §6 "Batch merge"). It becomes DONE when its batch PR is merged; give me a 2–3 line summary.
