---
description: Implement and review one task from the board (Phase 5–6 loop)
argument-hint: <T-###>
---

Run task $ARGUMENTS through implementation and review.

1. Read `docs/04-tasks/tasks/$ARGUMENTS.md` and `docs/workflow/model-routing.md`. Check that all dependencies are DONE in `docs/04-tasks/TASKS.md`; if not, stop.
2. Verify the complexity class. If it's C3/C4 and the task has no Design note, delegate to `solution-architect` first to write one.
3. Set status IN_PROGRESS. Delegate to the task's agent, passing the task file path, with the model the class dictates (override the agent's default with the `model` parameter if needed).
4. Read the diff yourself. Then set IN_REVIEW and run the reviews the class requires: `code-reviewer` (C2+), `test-engineer` (C3+ or any task with logic), `security-privacy-reviewer` (C4 or data/crypto/ingestion/permissions).
5. If any verdict is CHANGES_REQUESTED: send the findings back to the same implementer, then re-review. After two failed rounds, bump the class by one and re-delegate.
6. When all verdicts are APPROVED and the Definition of Done in `CLAUDE.md` §7 holds, set DONE and give me a 2–3 line summary.
