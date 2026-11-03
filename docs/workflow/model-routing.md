# Model Routing & Complexity Classification

The Lead classifies every task before delegation. When unsure between two classes, pick the higher one.

## Classification rubric

Score each factor 0–2 and sum:

| Factor | 0 | 1 | 2 |
|--------|---|---|---|
| Ambiguity | Fully specified | Minor judgement calls | Requires design decisions |
| Blast radius | Single file / leaf widget | One feature module | Cross-module, schema, or platform |
| Correctness risk | Cosmetic | Wrong output is visible & fixable | Wrong output loses money/data, leaks data, or breaks store policy |
| Domain depth | Generic Flutter | Egyptian finance / Arabic NLP basics | Crypto, native OS APIs, Shariah math, billing |
| Novelty | Copies an existing pattern in repo | Adapts a pattern | No precedent in repo |

| Score | Class | Implementer | Reviews required |
|-------|-------|-------------|------------------|
| 0–2 | **C1 Trivial** | `haiku` | Lead spot-check |
| 3–5 | **C2 Standard** | `sonnet` | code-reviewer |
| 6–7 | **C3 Complex** | `sonnet` after an Opus design note in the task file, or `opus` | code-reviewer + test-engineer |
| 8–10 | **C4 Critical** | `opus` | code-reviewer + security-privacy-reviewer + test-engineer |

**Automatic C4** regardless of score: anything touching encryption keys, SQLCipher setup, backup crypto, purchase verification & entitlement signing (app or backend), store webhooks, sign-in token verification, SMS/notification permissions & native receivers, schema migrations (app or backend), Zakah computation, money arithmetic primitives, the backend's accepted-fields boundary (BR-SYNC-03).

## Agent ↔ model map

| Agent | Default model | Typical classes |
|-------|---------------|-----------------|
| requirements-analyst | opus | Phase 1 |
| ux-designer | opus | Phase 2 |
| solution-architect | opus | Phase 3 + C3 design notes |
| task-planner | opus | Phase 4 |
| boilerplate-engineer | haiku | C1 |
| flutter-ui-engineer | sonnet | C2, C3 |
| flutter-core-engineer | sonnet | C2, C3 (opus override for C4) |
| parsing-engine-engineer | sonnet | C2, C3 (opus override for C4) |
| native-platform-engineer | opus | C3, C4 |
| backend-engineer | sonnet | C2, C3 (opus override for C4) |
| test-engineer | sonnet | Phase 6 |
| code-reviewer | opus | Phase 6 |
| security-privacy-reviewer | opus | Phase 6 (C4 + data-touching) |

To run an agent on a different model than its default, pass `model` in the Agent call (e.g. `flutter-core-engineer` with `model: opus` for a C4 money-arithmetic task).

## Escalation

- Failed review twice → bump class by one and re-delegate (may change model).
- Agent reports a spec gap → pause task, add to `docs/01-requirements/open-questions.md`, ask the user.
- Haiku output touching anything outside the task's listed files → reject and re-delegate as C2.

## Examples

| Task | Class | Why |
|------|-------|-----|
| Add 14 seed categories as Drift seed data | C1 | Transcription from approved schema |
| ARB files for onboarding copy | C1 | Copy already approved in copy deck |
| Home dashboard screen with KPI strip | C2 | Clear screen spec, standard widgets |
| NBE + CIB SMS regex templates + fixtures | C2 | Registry pattern established |
| Merchant fuzzy matching (FTS5 + Jaro-Winkler) | C3 | Algorithmic, tuning required |
| InstaPay self-transfer pairing (< 5 min) | C3 | Edge cases, affects totals |
| Egyptian Arabic voice phrase splitter | C3 | Arabic NLP, multi-item split |
| SQLCipher key generation & Keystore/Keychain storage | C4 | Crypto |
| Android SMS BroadcastReceiver + historical scan | C4 | Native, permission, store policy |
| Zakah native-unit engine | C4 | Religious-financial correctness |
| Drive backup encrypt/upload/restore | C4 | Crypto + data loss risk |
