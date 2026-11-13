# Sprint mode: v1 code-complete (PO, 2026-11-13 20:10 Cairo)

The PO asked for the rest of the app in one day. The target is **v1 code-complete**: every task that isn't blocked on PO inputs, real devices or store reviews, or flagged off at launch, is built, reviewed and merged. These rules override CLAUDE.md §6 where they differ, until the PO ends the sprint.

## Rules

1. **Waves of up to 10 builders, pipelined.** When a wave's builders report, the Lead assembles them and starts the review. Then it starts the next wave right away, from whatever is ready, without waiting for the review or CI. Builders branch from current `main`; a task that depends on an unmerged task branches from that task's branch.
2. **Two reviewers per wave of ten**, five tasks each, with the model per the cost rules (Opus if their half holds a C4 task). Each writes its own report, `batch-<n>a.md` / `batch-<n>b.md`.
3. **Fix round only for blockers, and for majors that touch money, security, privacy or data loss.** Other majors become `FU-###` items and get one fix sweep at the end of the day. The Lead checks the delta for fixes of about 40 lines or fewer, with a failing test; larger fixes get one delta-only Sonnet re-review.
4. **CI:** app-ci and backend-ci gate every wave PR. The slow `db-platform` device jobs (iOS simulator, Android emulators) are **not** waited for per wave: they run on `main` at midday and at the end of the sprint, and any failure there gets fixed then. Native tasks still prove themselves on `ci/<task-id>` (app-ci).
5. **No ARB edits outside T-029/T-087.** Builders use l10n keys from the copy deck and add missing ones to a `docs/04-tasks/tasks/T-###.md` note. T-087 or the Lead adds them, so the ARB files don't conflict across ten branches.
6. **Native registration lines** (`MainActivity`, `AppDelegate`, `project.pbxproj`, Pigeon registrations) are expected to conflict. The Lead resolves them at assembly by keeping every side.
7. Everything else in CLAUDE.md §2, §6 (cost rules) and §7 still applies: the non-negotiables, the self-check, at most 2–3 negative proofs per C4 task, low effort for C1/C2 builders and fix agents, Opus for crypto/keys and data-deleting code.

## v1 scope

**In v1 (64):** T-009, T-010, T-029, T-044, T-053–T-057, T-059 (agent-drafted list), T-061–T-067, T-079–T-087, T-091–T-093, T-098, T-100–T-108, T-110, T-111, T-113, T-114, T-116–T-118, T-121, T-143, T-145–T-147, T-151–T-153, T-155, T-160, T-162–T-164, T-166, T-171, T-173, T-174, T-178, T-179.

**Deferred (33), each with what unblocks it:**

| Tasks | Waiting for |
|---|---|
| T-031, T-036, T-037, T-068–T-072, T-156–T-158 | Bank SMS / notification / statement samples (OQ-04/OQ-18) |
| T-159, T-161 | `tesseract4android-4.9.0.aar` |
| T-167–T-170 | Zakah scholar sign-off (flags off at launch) |
| T-135, T-136, T-137, T-186 | Support sign-in provider (T-136 Q1/Q2) |
| T-140, T-175 | Hosting provider and region, PDPL (OQ-16) |
| T-176, T-177 | Store accounts, release signing |
| T-172 | Real devices / store sandbox |
| T-008, T-011, T-120, T-165 | Real-device runs |
| T-058 | Native Egyptian-speaker copy review |
| T-088, T-099 | Rive mascot file |
