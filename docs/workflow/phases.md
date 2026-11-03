# Workflow Phases

Each phase has an owner agent, required inputs, required outputs, and an exit gate. The Lead (main session) runs the phase by delegating to the owner, reviewing the output, and presenting it to the user for approval.

---

## Phase 1 — Requirements refinement
**Owner:** `requirements-analyst` (Opus)
**Inputs:** `docs/00-source/spec-v4-extracted.md`, spec images.
**Outputs (`docs/01-requirements/`):**
- `requirements.md` — single SRS: decisions, goals & metrics, personas, roles & entitlements, functional requirements (FR-*), business rules (BR-*), NFRs, edge cases, integrations, out of scope, risks, assumptions, open questions, traceability, glossary.
- `open-questions.md` — resolution log of setup-time questions.
**Gate:** User resolves open questions marked BLOCKING and approves the MVP scope.

## Phase 2 — UI/UX design
**Owner:** `ux-designer` (Opus)
**Inputs:** approved Phase 1 docs, spec screen images.
**Outputs (`docs/02-design/`):**
- `information-architecture.md` — nav model (bottom bar, FAB), screen inventory reconciled to one numbering.
- `flows/*.md` — onboarding, ingestion setup (Android / iOS), categorize, voice log, budget, backup, paywall.
- `screens/S-##-<name>.md` — per screen: purpose, states (empty / loading / error / populated / locked-Gold), components, copy keys (AR + EN), RTL notes, mascot state.
- `design-tokens.md` — colors (light/dark), type scale (Arabic + Latin fonts), spacing, radius, elevation, motion.
- `mascot-states.md` — Rive state machine inputs → triggers → screens.
- `copy-deck.md` — all user-facing strings, Egyptian Arabic + English, keyed.
**Gate:** User approves screens and copy deck.

## Phase 3 — Technical specification
**Owner:** `solution-architect` (Opus)
**Inputs:** approved Phases 1–2.
**Outputs (`docs/03-technical/`):**
- `architecture.md` — layers, module map, data flow from ingestion → parse → categorize → store → analytics.
- `adr/ADR-###-*.md` — one per significant decision (state mgmt, DB encryption & key handling, Android SMS policy strategy, iOS channels, chat engine, price data source, backup format, IAP verification).
- `database-schema.md` — final Drift tables, indexes, FTS, migrations policy.
- `platform-channels.md` — Dart ↔ Kotlin/Swift contracts.
- `parsing-engine.md` — SMS pipeline stages, regex registry format, fixture strategy, merchant normalization (FTS5 + trigram / Jaro-Winkler).
- `domain-algorithms.md` — self-transfer pairing, split offsets, payday cycle, burn rate, subscription detection, Zakah engine, ROI rules.
- `security-model.md` — threat model, key lifecycle, backup crypto, biometric lock, backend data boundary.
- `backend-api.md` — endpoints, request/response shapes, auth, signing.
- `backend-schema.md` — PostgreSQL schema and migrations policy.
- `testing-strategy.md` — unit / widget / golden / integration / device matrix.
- `project-structure.md` — final folder layout and naming.
**Gate:** User approves architecture and ADRs.

## Phase 4 — Task breakdown
**Owner:** `task-planner` (Opus)
**Inputs:** approved Phases 1–3.
**Outputs (`docs/04-tasks/`):**
- `TASKS.md` — board: milestones → tasks with ID, title, class, agent, model, deps, status.
- `tasks/T-###.md` — one file per task using `docs/workflow/templates/task.md`.
- Milestones should deliver vertical slices (e.g. M1: encrypted DB + one bank parsed end-to-end on Android + home screen).
**Gate:** User approves the board.

## Phase 5 — Implementation
**Owner:** Lead, delegating per `model-routing.md`.
Loop per task:
1. Lead confirms deps are DONE, sets status `IN_PROGRESS`.
2. Lead delegates to the task's agent with the task's model.
3. Agent implements + writes tests, returns summary and changed files.
4. Lead moves task to `IN_REVIEW` and triggers Phase 6 reviews for that task.
5. On APPROVED → `DONE`. On CHANGES_REQUESTED → back to step 2 (same agent, review notes attached).

## Phase 6 — Testing & code review
**Owners:** `test-engineer` (Sonnet), `code-reviewer` (Opus), `security-privacy-reviewer` (Opus, for C4 and anything touching data/crypto/ingestion).
**Outputs:** `docs/05-reviews/T-###.md` using `templates/review-report.md`; milestone-level `docs/05-reviews/M#-release-check.md`.
**Gate:** All tasks in the milestone APPROVED; milestone check passes on Android + iOS.
