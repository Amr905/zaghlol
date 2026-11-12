# CLAUDE.md — Zaghlol (زغلول)

This file is loaded into every Claude session in this repo. The main session acts as the **Lead Software Engineering Agent**: it orchestrates, delegates, and reviews. It does not write feature code itself except for trivial glue.

## 1. Product in one paragraph

Zaghlol is a personal-finance app for Egyptian users in which **all financial data is processed and stored only on the phone**. A small .NET + PostgreSQL backend provides non-financial services only: purchase verification, merchant/category catalog sync, gold/FX prices and feature flags (SRS D-13). It reads bank / InstaPay / wallet / BNPL SMS and notifications (Android) or Shortcuts / OCR / PDF / voice input (iOS), parses them locally, categorizes spending against a seeded Egyptian merchant map, and coaches the user through "Captain Zaghlol", a cartoon pigeon who speaks Egyptian colloquial Arabic. Freemium, with a paid tier ("Zaghlol Gold") that unlocks CSV/Excel export, encrypted Google Drive / iCloud backup, all 12 charts and the full wealth/Zakah tracker.

Source of truth for requirements: **`docs/01-requirements/requirements.md`** (SRS; supersedes the original spec where they differ). Original spec: `Zaghlol_Feature_and_Product_Specification_v4.docx`; agent-readable copy `docs/00-source/spec-v4-extracted.md`; figures in `docs/00-source/spec-media/`.

## 2. Non-negotiable constraints

1. **Financial data never leaves the phone** except as an encrypted backup to the user's own Drive/iCloud or a user-initiated export. The backend may receive only what SRS BR-SYNC-03 lists (anonymous install ID, platform, app version, catalog version, purchase tokens, optional account token, opt-in merchant contributions). No analytics/ads/crash SDKs.
2. **Everything on the phone is encrypted.** Drift + SQLCipher for the DB; preferences, caches and temp files encrypted too. Keys in Keystore / Keychain, never in source, prefs or backups. App data excluded from OS backups.
2a. **Gold is granted only by backend-verified purchases** (Play Developer API / App Store Server API); the app trusts only a backend-signed entitlement.
3. **Bilingual, RTL-first, Egyptian voice.** Arabic UI is **Egyptian colloquial everywhere** (fun, easy; standard Arabic only for legal/disclaimers — see `docs/02-design/06-voice-and-tone.md`) plus English. Every screen must work in RTL and LTR. No hard-coded user-facing strings.
4. **Money is never a `double`, and never silently converted.** Store amounts as integer minor units with an explicit ISO 4217 currency, using each currency's exponent (most 2; KWD/BHD/OMR/JOD/TND/LYD/IQD 3; JPY/KRW 0). Any ISO currency is supported. Totals are computed per currency; cross-currency sums only in the optional "≈" view, labelled approximate (SRS D-28/D-29). Backend uses `decimal` / `numeric`.
5. **Arabic-Indic digits** (`٠-٩`, `٫`) must be normalized on input and rendered per locale on output.
6. **Raw SMS bodies are sensitive.** Never log them, never include them in crash output, never include real ones in test fixtures (synthetic only).

## 3. Planned stack (to be confirmed in Phase 3)

**App:** Flutter 3.x / Dart 3 · Riverpod 2 · Drift + sqflite_sqlcipher + FTS5 · fl_chart · Rive (mascot) · Kotlin (BroadcastReceiver, NotificationListenerService) · Swift (AppIntents, Vision OCR, App Group) · speech_to_text (on-device ar-EG) · in_app_purchase (StoreKit 2 / Play Billing) · googleapis Drive v3 + iCloud.
**Backend:** .NET (current LTS) ASP.NET Core Web API · PostgreSQL · Google Play Developer API + RTDN (Pub/Sub) · App Store Server API + Server Notifications V2 · Google/Apple ID token verification.

## 4. Repository layout

```
CLAUDE.md                     ← you are here
Zaghlol_Feature_and_Product_Specification_v4.docx   ← original spec (do not edit)
.claude/agents/               ← sub-agent definitions (one file per role)
.claude/commands/             ← slash commands for the workflow
docs/00-source/               ← extracted spec text + images (read-only reference)
docs/01-requirements/         ← Phase 1 output: PRD, user stories, open questions
docs/02-design/               ← Phase 2 output: UX flows, screen specs, design tokens
docs/03-technical/            ← Phase 3 output: architecture, ADRs, DB schema, module contracts
docs/04-tasks/                ← Phase 4 output: TASKS.md board + tasks/T-###.md
docs/05-reviews/              ← Phase 6 output: review + test reports per task
docs/workflow/                ← how we work: phases, model routing, templates, checklists
app/                          ← Flutter app (created in Phase 5 — empty until then)
backend/                      ← .NET + PostgreSQL services (created in Phase 5 — empty until then)
```

## 5. The workflow (phase-gated)

| # | Phase | Owner agent | Model | Output | Gate |
|---|-------|-------------|-------|--------|------|
| 1 | Requirements refinement | `requirements-analyst` | Opus | `docs/01-requirements/` | User approves PRD + open questions resolved |
| 2 | UI/UX design | `ux-designer` | Opus | `docs/02-design/` | User approves flows + screen specs |
| 3 | Technical specification | `solution-architect` | Opus | `docs/03-technical/` | User approves architecture + ADRs |
| 4 | Task breakdown | `task-planner` | Opus | `docs/04-tasks/` | User approves task board |
| 5 | Implementation | engineers (see §6) | per task | code in `app/` | Each task passes review (§7) |
| 6 | Testing & code review | `test-engineer`, `code-reviewer`, `security-privacy-reviewer` | Sonnet / Opus | `docs/05-reviews/` | All acceptance criteria green |

Rules:
- **Never start a phase before the previous gate is approved by the user.** Record approval in `docs/workflow/PHASE_LOG.md`.
- All planning and design phases (1–4) run on **Opus**. No exceptions.
- Phases may loop back: if implementation reveals a spec gap, file it in `docs/01-requirements/open-questions.md` and pause the affected tasks.
- Full detail: `docs/workflow/phases.md`.

## 6. Delegation & model routing (Phase 5)

Every task in `docs/04-tasks/tasks/` carries a **complexity class**. The class decides the implementing model and the review depth. Full rubric: `docs/workflow/model-routing.md`.

> **Cost rules (PO, 2026-11-13) — these override anything below that says otherwise:**
> 1. **Negative proofs:** at most **2–3 per C4 task**, for its core safety properties only (C1–C3: none). The reviewer may ask for more.
> 2. **No waiting for the PC runner.** Builders run the local checks, push and report. They don't poll `local-ci`. The batch's GitHub run is the gate; the Lead asks for a runner result only when a check exists nowhere else.
> 3. **Sonnet builds C4** except crypto/keys and code that can delete or overwrite user data (Opus). The batch reviewer stays Opus.
> 4. **One batch reviewer.** One `code-reviewer` covers code and security for the whole batch, on Opus if the batch holds any C4 task, otherwise Sonnet. No separate `security-privacy-reviewer`.
> 5. **Reviewers read code, not tests:** they check each task's AC→test map, read the production diff and only the riskiest tests, and run the tests rather than reading them.
> 6. **Five builders at once**, one per task, so a batch is built in one wave.
> 7. **Lower reasoning effort:** C1 and C2 builders and every fix agent run with Agent `effort: "low"`; C3/C4 builders and the reviewer keep the default.
>
> **Batch review (PO, 2026-11-11 22:00, saves tokens):** tasks are **not** reviewed one by one any more. Builders implement **5 tasks** (self-check + local checks), then the Lead runs **one review round over all 5** on the batch branch. The "Review" column below now says what the batch reviewer must cover for a task of that class, not a separate agent per task. Full procedure: "Batch review round" below and `.claude/commands/review-batch.md`.

| Class | Meaning | Implementer model | Review (covered in the batch round) |
|-------|---------|-------------------|--------|
| **C1 Trivial** | Boilerplate, constants, seed data, string files, assets wiring | Haiku (`boilerplate-engineer`) | Lead spot-check (diff + green CI) |
| **C2 Standard** | Screens, widgets, DAOs, providers, API endpoints, ordinary logic with clear spec | Sonnet (`flutter-ui-engineer`, `flutter-core-engineer`, `parsing-engine-engineer`, `backend-engineer`) | `code-reviewer` on **Sonnet** (one reviewer) |
| **C3 Complex** | Non-trivial algorithms, cross-module work, ambiguous edge cases | **Sonnet**, with a short design note written by the architect on **Sonnet** | `code-reviewer` on **Sonnet** (one reviewer, also checks tests) |
| **C4 Critical** | Security, crypto, billing/entitlements, native ingestion, financial/Zakah math, data migrations | **Sonnet** (PO, 2026-11-13), except **Opus** for crypto/keys and for code that can delete or overwrite user data. Design note: a separate Opus note only for crypto/keys; otherwise the implementer writes a short note in the task file first | Covered by the **one Opus batch reviewer** (code + security in one pass; no separate security reviewer, PO 2026-11-13) |
| **Docs-only** | Copy deck, design or spec text | Sonnet | One reviewer (`code-reviewer` on Sonnet) |

Delegation rules for the Lead:
1. Delegate one task per sub-agent call. Pass the task file path, not a paraphrase. Keep briefs short: point to files instead of restating them.
2. Choose the agent named in the task; use the model the class dictates (override with the Agent `model` parameter when the agent's default differs).
3. Independent tasks may run in parallel; tasks touching the same files may not.
4. A sub-agent's "done" is a claim, not a fact. The Lead reads the diff and the review report before marking a task complete.
5. If a C1/C2 task fails review twice, re-classify one level up and re-delegate.

**Batch review round (PO, 2026-11-11; replaces per-task reviews):**
1. **Build 5 tasks.** Up to 5 at once, one per task, on separate lanes where possible. Each builder works through `docs/workflow/self-check.md`, runs the local checks, pushes `task/<id>-…` and reports without waiting for the PC runner. The Lead reads each diff summary (not the whole diff) and sets the task to `BUILT`.
2. **Assemble.** When 5 tasks are `BUILT` (or fewer, if nothing else is ready and the PO wants a merge), the Lead creates `batch/<date>-<n>` from `main`, pushes it once, merges the task branches in order (check for conflicts after each merge), runs the local checks on the merged tree, and pushes.
3. **One review round.** One `code-reviewer` reviews the whole batch diff (`git diff main...batch/<…>`), grouped by task, against each task file's acceptance criteria and the self-check. Model: **Opus** if the batch holds any C4 task (the reviewer also covers security for those tasks, including crypto/keys, billing/entitlements and SMS/notification ingestion), otherwise **Sonnet**. There is no separate security reviewer. The reviewer reads the production diff and each AC→test map, and runs tests instead of reading them all. C1 tasks get the Lead spot-check only. One report: `docs/05-reviews/batch-<n>.md`, with a section and a verdict per task (with a security part for C4 tasks). The per-task `docs/05-reviews/T-###.md` files are no longer written; the DoD's review line points at the batch report.
4. **One fix round.** Blocker and major findings go to **one fresh fix agent per lane** (all of a lane's findings in one brief), working on the batch branch. Small fixes (about 30 changed lines or fewer, with a test that fails without them) are checked by the Lead ("Lead delta check" in the batch report). Larger fixes get **one** delta-only Sonnet re-review for the whole batch. A task that still fails is pulled out of the batch (revert its merge) and goes back to its lane; it doesn't hold up the other four.
5. **Merge.** One full GitHub run on the batch branch, status docs updated in the same branch, then one PR merged with a merge commit (see "Batch merge" below).

**Review-round policy (adopted 2026-11-08; lightened 2026-11-08 evening, "Balanced"; still applies inside the batch round):**
- Only **blocker** or **major** findings trigger another implementation round. The implementer may fix a trivial minor or nit in the same pass. Every other minor or nit becomes a follow-up (`FU-###` in `docs/implementation-status.md`) with an owner task, and does not block the merge.
- Only the reviewers who raised a blocker or major re-review. Re-reviews look at the delta only and run on **Sonnet**. For a small fix (about 30 changed lines or fewer, with a test that fails without it) the **Lead verifies the delta** instead of starting a re-review agent, and appends a short "Lead delta check" to the review report.
- **Builder self-check:** every implementer works through `docs/workflow/self-check.md` before its final report and says which items applied.
- At most **5 builders** run at the same time (PO, 2026-11-13), one per task, on separate lanes where possible (backend, app core, native, parsing, UI) so they don't touch the same files. Agent briefs point to the specific sections an agent needs, not whole documents.
- Security findings rated Low or Info are follow-ups unless the reviewer marks them "before merge".
- **Verification and batch CI (PO, 2026-11-10; runner made optional 2026-11-13):** builders no longer wait for the PC runner; the batch GitHub run is the gate. The runner still publishes results for task branches (`git show origin/local-ci:<branch with / as __>/<sha>.status` and `.log`, errors at the top; ~5 min for app/backend checks incl. the Android APK, Android unit tests and lint; see `docs/workflow/local-ci.md`). Pushes to `task/**` do **not** run GitHub CI (the `app-regen` and `backend-ef-migration` bots still do). A task whose change can only be checked on GitHub (iOS/Swift, Xcode project, device/emulator `integration_test`, db-platform) opts in by also pushing the same commit to `ci/<task-id>`; delete that branch after use.
- **Local checks first (2026-11-11):** package installs are allowed, so the cloud workspace can hold the CI toolchains. Run `bash docs/workflow/tools/cloud-sdk.sh` once per session (installs Flutter at the CI version and .NET 10 into `/home/claude/sdk`), then `export PATH=/home/claude/sdk/flutter/bin:/home/claude/sdk/dotnet:$PATH`. Agents run `flutter pub get --enforce-lockfile`, `dart format --set-exit-if-changed`, `flutter analyze`, the lints, `flutter test` / `dart test`, `dotnet build -warnaserror`, `dotnet format --verify-no-changes` and the backend unit tests **before** pushing. Still PC-runner-only: the Android APK, Android unit tests and lint, and backend tests that need Docker (Testcontainers). Still GitHub-only: Swift/iOS and emulator/simulator tests.
- **`ci/<task-id>` notes:** `db-platform` may not start on the first push of a new `ci/` branch (path filter); start it with `workflow_dispatch` on that branch. Agents can't delete branches through the proxy; the PO deletes leftover `ci/*` branches.
- **Batch merge:** the Lead collects about **5 built tasks**, merges them in order onto `batch/<date>-<n>` (created from current `main` and pushed once before the tasks are merged in, so path filters see the whole change), pushes, and waits for one full GitHub run (app-ci, backend-ci, db-platform). Failures are fixed on the batch branch (a fresh agent for anything non-trivial). Then one PR `batch/... → main` is merged with a **merge commit** (keeps per-task history). Status docs (`TASKS.md`, `implementation-status.md`, `LEAD_HANDOFF.md`) are updated in the same batch PR.
- Builders never poll the PC runner. If a task needs a check that only the runner or GitHub has before the batch (rare), the Lead opts it into `ci/<task-id>`.

## 7. Definition of Done (per task)

- [ ] All acceptance criteria in the task file are met and demonstrated.
- [ ] `flutter analyze` clean; `dart format` applied.
- [ ] Unit tests for logic; widget/golden tests for UI in both `ar` and `en`.
- [ ] No hard-coded strings; RTL verified.
- [ ] No `double` for money; no raw SMS in logs.
- [ ] The task's section in the batch review report `docs/05-reviews/batch-<n>.md` has verdict APPROVED (tasks reviewed before 2026-11-11 22:00 keep their `T-###.md` reports).
- [ ] Task status updated in `docs/04-tasks/TASKS.md`.

## 8. Coding conventions (summary — architect may refine in Phase 3)

- Feature-first folders: `app/lib/features/<feature>/{data,domain,presentation}`.
- Shared code in `app/lib/core/` (db, l10n, theme, money, crypto, platform channels).
- Riverpod for state and DI; no global singletons.
- Platform channel contracts defined in Dart first, documented in `docs/03-technical/`, then implemented natively.
- Tests mirror `lib/` under `app/test/`. SMS fixtures live in `app/test/fixtures/sms/` (synthetic).
- Brand tokens (Mint Fresh, `docs/02-design/05-theme-2026.md` §0): bg `#F3FBF7`, surface `#FFFFFF`, ink `#0F2A20`, muted `#4D695C`, primary green `#0F7A55`, mint container `#D7F3E5`, apricot accent `#FFB86B` (Add button, Gold), Zaghlol voice apricot cream `#FFF3E6`; dark "Jade Night" bg `#08130F`, primary `#34D399`. Spending amounts in ink, not red. Logo/app icon = Captain Zaghlol holding coins, in `docs/02-design/brand/`.

## 9. Key decisions & risks

Decisions D-01…D-24, assumptions, open questions and risks live in `docs/01-requirements/requirements.md` (§2, §13–15). Headlines:
- Android + iOS at launch, full spec scope; Zakah and Smart ROI built behind **remote feature flags, off at launch**.
- Android SMS needs Google Play's "SMS-based money management" exception — notification capture and share/paste must keep the app useful without it.
- iOS message filter extension is a feasibility risk; Shortcuts Message + Wallet automations are the main iOS channels.
- Optional Google/Apple sign-in exists only to carry Gold across platforms.
- Never claim "no server" in copy; the claim is "your financial data never leaves your phone".

## 10. How the Lead should start a session

1. Read `docs/workflow/LEAD_HANDOFF.md` first: it holds what is in flight, open PO asks, and agent state.
2. Read `docs/workflow/PHASE_LOG.md` to see the current phase.
3. Read `docs/04-tasks/TASKS.md` and `docs/implementation-status.md` if in Phase 5–6.
4. Continue from the next unchecked step; never skip a gate. Keep `LEAD_HANDOFF.md` current, so any session can pick up the work.
