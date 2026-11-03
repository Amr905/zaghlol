---
description: Start or resume a workflow phase (1–6) with its owner agent
argument-hint: <phase-number>
---

Start Phase $ARGUMENTS of the Zaghlol workflow.

1. Read `CLAUDE.md`, `docs/workflow/phases.md` and `docs/workflow/PHASE_LOG.md`.
2. Confirm the previous phase's gate is recorded as approved in PHASE_LOG. If not, stop and tell me what is missing.
3. Delegate to the phase's owner agent (Opus for phases 1–4) with the inputs and outputs listed in `phases.md`.
4. Review the output yourself against the phase's output list. Send it back to the agent if anything is missing or inconsistent.
5. Present a short summary to me with the decisions I need to make for the gate. Log "phase started" in PHASE_LOG.
