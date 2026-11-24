# Lead handoff — read this first

_Last updated: 2026-11-24 (Cairo) by the Lead session: batch 66 (device E2E T-236..T-239; fixes: headless budget alerts, delete-everything close race) merging. Update it whenever the state below changes._

**All state is in the repo.** Agents from earlier sessions can't be messaged; start new ones from their branches. Where this file and the repo disagree, the repo wins.

## Start of a session (in order)

1. Attach the repo with push access (`add_repo` Amr905/zaghlol, access `push`), clone, register it. Project agent types (`code-reviewer`, `backend-engineer`, …) appear only after registration; before that, run roles as `general-purpose` with "act as `.claude/agents/<role>.md`".
2. Install the toolchains once: `bash docs/workflow/tools/cloud-sdk.sh`, then `export PATH=/home/claude/sdk/flutter/bin:/home/claude/sdk/dotnet:$PATH` (needs package installs allowed in the Claude network settings; they are, since 2026-11-10).
3. Check the PC runner is alive: newest `results/probe.log` on the PO's PC, or a recent commit on the `local-ci` branch. If it's silent, ask the PO to start Docker Desktop and `START-LOCAL-CI.cmd`.
4. Read CLAUDE.md §6 (process), this file, then `docs/04-tasks/TASKS.md` and `docs/implementation-status.md`.

## Process (CLAUDE.md §6 is authoritative)

- **Cost rules (PO, 2026-11-13; CLAUDE.md §6 top):** 2–3 negative proofs per C4 task; builders never wait for the PC runner; Sonnet builds C4 except crypto/keys and data-deleting code; **one** batch reviewer (Opus if any C4) covering security too; reviewers read code, run tests; up to 5 builders at once; C1/C2 builders and fix agents at `effort: "low"`.
- **Batch review (PO, 2026-11-11 22:00):** no per-task reviewers. Build 5 tasks (≤4 at once) → `BUILT`; assemble the batch branch; **one review round** (`/review-batch`): one `code-reviewer` over the whole batch diff (Opus if any C4, else Sonnet) + one Opus `security-privacy-reviewer` scoped to crypto/billing/SMS-ingestion tasks; one report `docs/05-reviews/batch-<n>.md`; one fix agent per lane; Lead delta check for ≤30-line fixes, else one delta-only Sonnet re-review; a still-failing task is reverted out of the batch. Batch 9 was the first run: 2 review agents + 1 fix + 1 re-review instead of ~6 reviewers.
- **Classes and reviews (what the batch round must cover):** C1 Lead spot-check · C2/C3/docs: one Sonnet `code-reviewer` (also checks tests) · C4: one **combined** Opus review (code + security, one report), except crypto/keys, billing/entitlements and SMS/notification ingestion, which keep two Opus reviewers. Re-reviews are delta-only on Sonnet. Only blocker/major (or security Medium+ / "before merge") trigger a round; everything else becomes `FU-###`.
- **Implementers:** C2/C3 Sonnet (C3 implementer writes its own short design note first). C4 Opus; its design note on Opus only for crypto/keys, billing/entitlements, SMS ingestion, otherwise Sonnet. Fix rounds: start a **fresh** agent with a short brief (cheaper than resuming a large context).
- **Verification ladder:** (1) local in the cloud workspace — format, analyze, lints, `flutter test`/`dart test`, `dotnet build -warnaserror`, `dotnet format`, backend unit tests; (2) PC runner on push to `task/**` — Android APK + permission check + Android unit tests + lint, backend Testcontainers tests; (3) GitHub only per batch (`batch/**`) or opt-in `ci/<task-id>` for Swift/iOS and emulator/simulator tests. `db-platform` may need `workflow_dispatch` on a new `ci/` branch.
- **Batches:** ~5 built tasks merged in order onto `batch/<date>-<n>` (push the branch at `main` first, then merge tasks), run local checks on the merged tree, add the status-doc updates, push, one full GitHub run, then one PR merged with a **merge commit**. PO authorised the Lead to merge green, approved PRs.
- **Speed-ups (PO, 2026-11-11):** up to 4 tasks at once on separate lanes; builders follow `docs/workflow/self-check.md`; non-crypto C4 builders write their own design note; Sonnet builds C4 tasks except crypto/keys, billing, SMS ingestion, migrations and data-deleting code; the Lead verifies small fix deltas itself.
- **Limits and quirks:** The git proxy allows 2 concurrent ops per repo; on 429 wait 5 s and retry once. `gh` works only as `gh api` (REST). Agents can't delete remote branches (proxy); the PO deletes leftover `ci/*` and proof branches. Known flakes: GitHub Android NDK download / Maven 429 (rerun failed jobs), `SeededSeriesTests` on the PC (FU-055), interleaved xcodebuild lines (tolerated since batch 2), iOS `SecretStoreTests.testExistingKeyWinsOverANewCandidate` missing from the xcodebuild log (3× on 2026-11-11; rerun; root cause open), Android API 35 emulator hang / `adb: device offline` in db-platform and sms-spike (cancel at the 75-min timeout, rerun failed jobs), Ubuntu apt DNS outage on GitHub runners (`Temporary failure resolving *.ubuntu.com`, db-platform host job; still failing at 22:00 on 2026-11-11), PC-runner timing tests failing under load (catalog seed load, categorizer perf, guard perf, ingest benchmark — pass in the cloud).
- **Restarts:** server and cloud-workspace restarts kill running agents several times a day. Brief every agent to commit early and push often. On restart: check each worktree for live processes (`ps aux`, `readlink /proc/<pid>/cwd`) and for pushed/unpushed commits before relaunching; relaunch as a "resume" agent pointed at the same worktree.
- **Batch scripts:** never chain `git commit` after `git merge` without first checking `git diff --name-only --diff-filter=U` (a conflicted merge got committed with markers once; fixed before push). Local CI step logs (`*.log`) are git-ignored; don't `git add -A` in a worktree where the step script ran without checking `git status`.
- **Copy deck checks:** `python3 docs/workflow/tools/copy_deck_check.py docs/02-design/copy-deck.md`.

## Progress: 167 of 186 tasks done (89.8%)

DONE: T-001…T-007, T-012…T-024, T-025…T-028, T-030, T-032…T-035, T-038…T-043, T-048, T-049, T-052, T-045, T-046, T-047, T-050, T-051, T-060, T-073…T-075, T-076, T-077, T-078, T-089, T-090, T-094…T-097, T-103, T-109, T-112, T-115, T-119, T-122…T-131, T-132, T-133, T-134, T-138, T-139, T-141, T-142, T-144, T-148…T-150, T-154, T-180…T-185. **Merged but open:** T-008 (device rows AC1/AC2), T-136 (IdP evidence), T-165 (device run).

| Milestone | Done | Total |
|---|---|---|
| M0 | 24 | 28 |
| M1 | 18 | 29 |
| M2 | 7 | 29 |
| M4 | 4 | 17 |
| M5 | 24 | 35 |
| M6 | 4 | 19 |
| M3 | 7 | 18 |
| M7 | 0 | 11 |

The PO asked for this progress table in every update.

**Merged batches:** #28, #29, #32–#36 (batch 7), #37 batch 8 (T-041 + T-042, T-051), batch 9 (`batch/2026-11-11-9`: T-021, T-040, T-047, T-077, T-182, T-184 + the batch-review workflow), batch 10 (`batch/2026-11-13-10`: T-023, T-043, T-109, T-132, T-141; first under the cost rules), batch 11 (`batch/2026-11-13-11`: T-048, T-049, T-052, T-119, T-181, T-183), batch 12 (`batch/2026-11-13-12`: T-024, T-052, T-089, T-180, T-185), batch 13 (`batch/2026-11-13-13`: T-078, T-094, T-115, T-154; T-103 pulled out), batch 14 (`batch/2026-11-13-14`: T-076, T-095, T-103, T-144, T-149), batch 15 (`batch/2026-11-13-15`: T-090, T-096, T-097, T-142, T-150, iOS CI retry), batches 16–18 in one PR (#50, `batch/2026-11-14-18`: 38 tasks, sprint mode), batch 19 (#51), batch 20 (#52), batch 21 (#53), batch 22 (#54), batch 23 (#55), batch 24 (#56), batch 25 (#57), batch 26, batch 27 (#59), batch 28 (#60), batch 29 (#61: T-070 BNPL templates, T-186 support endpoints, FU-244 generic FX/fee, design pass 3 with the Android FAB docked, explorer English/dark/x1.3/onboarding/paywall), batch 30 (#62: SMS-auto — confident bank SMS auto-save (PO SMS-AUTO), settlements as transfers, original SMS on review cards, HSBC re-parse via registryVersion bump; budget route black-screen fix; ZHaptics; brand-colour bank avatars), batch 31 (#63: SMS-device — on-device SMS e2e on the emulator (`adb emu sms send`), start-up re-parse of pending rows, regex-sender inbox scan, permission Fix button, SMS-NODIGIT, dev diagnostics; SMS-improve — InstaPay templates for 12 banks, hotline guard, auto-categorization, registryVersion 3; UI-po31 — bank acronyms, Western-digit card numbers, review Keep, charts free), batch 32 (#64: follow-up sweep — backend DB-clock lock + detach checks, registry v4 + parsing minors, re-parse behind the restore gate, UI minors (onboarding pinned actions, paywall timeout, neutral spend colour, Insights copy, narrow shell), explorer3 (review Keep/Edit/Ignore, 12 free charts, diagnostics) and the Keep tap fix), batch 33 (#65: FU-139/131/133/130/141 privacy+data, FU-142/132/136/143 ledger (refund-matching hook, annual budgets), FU-219 due-days setting, dispute freezes from the DB clock, privacy guard regex), batch 34 (#66: CAT-cash — InstaPay and Cash categories, withdrawn-cash pool so cash payments aren't counted twice; FAB-mockup — floating Add button per mockup 20, Home banner order), batch 35 (#67: housekeeping jobs — budget alerts incl. annual, recurring detect/auto-mark/dues/reminders, dangling-links sweep, delete frees links; InstaPay/Cash backfill on old rows; UI minors; 1.3x overflow sweep on every screen; backend FU-228/232 minors), batch 36 (#68: FU triage (81 closed, 4 obsolete, open table by lane), housekeeping throttle/trailing/stop, rollover carry shared by screen and alerts, backend action SHA pins, voice/catalog keywords, copy fixes, FU-138 trusted-time, lint extensions), batch 37 (#69: itemised FU triage (213 rows), core/catalog seed upgrade/ReDoS budget (drop patterns never quarantined), riverpod_lint + Spectral npm, native minors, parsing/test/backend minors, core2 17 items, UI 14 items, explorer4 cash/InstaPay e2e). Next free follow-up number: **FU-262**.

**Lessons:** never chain `git commit` after `git merge` in one script without checking for conflicts. Server/cloud restarts happen often: brief agents to commit early and push often; on restart, check worktrees for live processes (`ps`, `/proc/<pid>/cwd`) before relaunching.

## Session summary (2026-11-15 → 2026-11-18)

Batches 26–37 (PRs #58–#69) were driven by the PO's real-phone tests. All CI checks (app-ci, backend-ci, db-platform) were green at each merge. Board progress stayed at 167/186: every remaining board task waits on PO inputs or devices. This session cleared PO feedback and follow-ups.

**PO feedback handled (decisions recorded in `PO_DECISIONS.md` Part 1):**
- **App defaults:** light theme and Arabic by default. Screens were brought toward the approved mockups in several design passes.
- **Add button (FAB-MOCKUP):** after a docked-FAB detour in batch 29, it floats as in mockup 20, with tab and Ask-input clearance.
- **SMS-AUTO:** confident bank SMS auto-save. The rule requires all of these:
  - a known bank sender;
  - a clear direction;
  - an unambiguous amount and currency;
  - a last-4 or a merchant;
  - not a duplicate.

  Suspicious messages go to review and show the original text, with a **Keep** button (REVIEW-KEEP). Credit-card settlements are saved as transfers into the card account.
- **Why the phone read nothing (batch 31):**
  - Pending rows were never re-parsed at start.
  - The inbox scan didn't query regex-only senders such as HSBC.
  - The permission Fix button was dead.

  The on-device SMS e2e (`adb emu sms send` in device-flows) now guards this. The PO can read Settings → About → SMS diagnostics (dev builds only; counts, no bodies).
- **SMS rules:**
  - SMS-NODIGIT: messages with no digits are dropped.
  - OTP drops are global and need a code. Promo, due and statement drops are per bank only.
  - InstaPay templates exist for 12 banks, from the PO's CIB sample. Hotline numbers (19666) are never amounts.
  - The generic extractor reads amount, currency, last-4, merchant and date. A foreign amount is taken only after an explicit "original"/"foreign" cue.
  - Templates guessed without samples are marked `synthetic-unverified`.
  - registryVersion is now 5; bump it whenever templates change, or pending rows aren't re-parsed.
- **Categories:**
  - Auto-categorization covers subscriptions, food delivery, groceries, telecom, fuel and utilities.
  - CAT-INSTAPAY: InstaPay transfers get the InstaPay category until the user changes it.
  - CAT-CASH: ATM withdrawals get Cash. Manual cash payments draw from a per-currency withdrawn-cash pool, so they aren't counted twice: cover = min(pool, gross) and spend = net − cover. No category ever shows negative; cover across cycles shows a "paid from cash withdrawn earlier" note.
  - Old rows were backfilled once, never touching user-set categories.
- **UI and display:**
  - BANK-ACRONYM: long Arabic bank names fall back to the English acronym.
  - CARD-DIGITS: card numbers always use Western digits, LTR.
  - CHARTS-FREE: all 12 charts are free, behind one switch.
  - Haptics (`ZHaptics`), brand-colour bank avatars with a logo slot. Real logos need bank permission or a licensed source; see `docs/02-design/brand/LOGOS.md`.
- **Notifications:**
  - WEEKLY-FRIDAY: the weekly summary arrives on Friday.
  - OVERDUE-REMINDERS: the Lead drafted the copy (PO delegated, 2026-11-18). Being built on `task/PO-b38-reminders`.

**Other work:**
- **Housekeeping jobs:** after ingest and at start/resume. They run:
  - budget alerts, including annual and rollover with a shared carry;
  - recurring detect, auto-mark paid, card dues and reminders;
  - a dangling-links sweep.

  They are throttled, single-flight and yield to the restore gate.
- **Catalog seed upgrade:** existing installs get new seed rows through INSERT OR IGNORE only.
- **ReDoS budget:** **drop patterns are never quarantined**. Fail-closed would drop every SMS; skipping them would leak OTPs.
- **Tooling:** riverpod_lint runs as an analyzer plugin, Spectral via npm ci, backend-ci actions are pinned by SHA, and a 1.3× overflow sweep covers every screen.
- **FU triage:** `docs/implementation-status.md` has "Open follow-ups by lane" and "Itemised follow-ups (triage 2)". About 100 items need nothing external, mostly UI; the rest need PO, device or hosting.

**Lessons this session:**
- Check every fix agent's "fail closed" idea against data loss. Batch 37's quarantined drop pattern would have dropped all SMS.
- Golden tests must pin clocks; the Home greeting depends on the hour.
- The cash-cover CTE needed `MATERIALIZED`; charts went from 15 s to 15 ms on 10k rows.
- `adb emu sms send` accepts alphanumeric senders.
- Explorer "dead tap" reports were often test timing (`ensureVisible` without a pump).
- db-platform sometimes fails with "Failed to start Dart Development Service" on the emulator. Rerun failed jobs.

## Session summary, part 2 (2026-11-18, batches 38–42, PRs #70–#76)

The PO asked the Lead to work on the tasks blocked on PO inputs (web research allowed), then sent new phone-test reports and statement samples.

**PO decisions (recorded in `PO_DECISIONS.md` Part 1):**
- **WEEKLY-FRIDAY:** the weekly summary arrives on Friday and covers the 7 days ending Thursday.
- **OVERDUE-REMINDERS:** the Lead drafted the copy (PO delegated). Reminders go out on day+1 and day+3 from 10:00, with a redacted variant when amounts are hidden. The "أيوه دفعته / Mark as paid" action opens the app and pays with the due date pinned.
- **HSBC:** keep the Arabic templates even though HSBC Egypt says it sends English only, since it may be a per-customer setting.

**Batch 38:** reminders and the weekly summary.

**Batch 39 — blocked tasks moved forward:**
- **T-136:** operator OIDC for Entra or Google, by config.
- **T-059:** 854 merchants, compiled by an agent and spot-checked online; PO to spot-check.
- **T-099:** mascot moments using the interim brand art. The Rive file switches in automatically when it lands.
- **T-159:** Android OCR via JitPack, sha256-verified, with ML Kit telemetry removed.
- **T-165:** emulator evidence.

**Batch 40:**
- **T-127:** gold adapters; MetalpriceAPI recommended.
- **T-140 prep:** GCP Frankfurt recommended. OpenTofu and a manual OIDC deploy are ready but not deployed. Includes a PDPL note, which is not legal advice.
- **T-176/177:** unsigned store pipelines, store docs in docs/06-release, the Sign in with Apple entitlement, and the widget privacy manifest.
- **T-058 pass 1:** 54 Arabic fixes; 31 calls left for the human reviewer.

**Batch 41:**
- **T-156:** bank-agnostic PDF import.
- **Android share:** now reaches OCR.
- **Merchant aliases:** a lint for risky aliases.
- **Infra/release minors:** cleared.
- **T-031:** web search; no verbatim SMS were found.

**T-165 on a release-type build (PR #75):** a non-debuggable build is refused backup and `adb backup` contains 0 app entries on API 30 and 34. Debuggable builds can be backed up on Android 12+, which is expected per Android's docs.

**Batch 42 (from the PO's 2026-11-18 reports):**
- **CIB gold-certificate promo saved as a transaction:**
  - **Root cause:** the generic fallback read "السحب" (draw) as a withdrawal and took a "merchant" from "من …".
  - **Fixes:** draw/promo cues → `genericPromotion`. A CIB drop limited to draw wording; the Lead narrowed `السحب على` so a real `تم السحب على حسابكم` is kept, and a plain T&C footer is never dropped.
- **Arab Bank (sender `EG`, now `templateOnly`):**
  - InstaPay out with account, recipient, ref and balance.
  - USD salary credit, kept in USD.
- **Mashreq (Mashreq-e&, Mashreq):** card purchase; the terminal id is stripped from the merchant.
- **Vodafone Cash (VF-Cash):** synthetic templates; the PO will send a real sample.
- **registryVersion:** 6.
- **PDF statements (T-156b) for the PO's 3 sample layouts:**
  - The layouts: Credit/Debit/Balance with a summary; Paid In/Paid Out with Brought Forward; and a scanned US e-statement with year-less dates and page-2 duplicates.
  - The running balance validates direction.
  - Rows that don't reconcile, or whose direction is unknown, go to user review; the year must be confirmed if it isn't printed.
  - Scanned PDFs use on-device OCR on Android and iOS.
  - The import UI for those decisions isn't built yet (FU-262).
- **SPRINT rule 5 (no ARB edits) is superseded:** builders add their own keys.

**Lessons:**
- **Separate worktrees:** two agents shared the main checkout, so one pushed an empty branch and its commits landed on another branch. Every agent now works in its own worktree; the Lead recovered the commits by cherry-pick.
- **Builder tools:** the parsing builder has no WebSearch. Use a general-purpose agent for web research, and the Lead verifies a sample.
- **"Fail closed" and "drop" rules:** check each against real messages that share the wording (T&C footers, "السحب على حسابكم").

## In flight (2026-11-18 Cairo)

1. **Statement import UI (FU-262):** the review decisions, year confirmation and l10n keys, plus T-158 flow wiring. Then T-156 can go live with real statements.
2. **PO samples still useful:** a Vodafone Cash SMS, real bank statements, and any SMS the diagnostics screen shows as unread.
3. **Remaining FUs:** the itemised table; about 20 UI items from batch 37 are not started (FU-257).

Next free follow-up number: **FU-295**
Next free follow-up number: **FU-276** (FU-276 unused: batch 54 minors fixed in the fix round).

## Batch 39 (2026-11-18)

`batch/2026-11-18-39`: T-136 operator OIDC for Entra or Google by config (PO picks and registers the app; docs/03-technical/operator-idp-setup.md), T-059 merchant seed (854 merchants, 705 compiled by agent from its own knowledge; PO spot-check pending), T-099 mascot moments with interim animated brand art and automatic RiveMascot when T-088's .riv lands (docs/02-design/mascot-rive-handoff.md), T-159 Android OCR (Tesseract4Android via JitPack with sha256 verification, ML Kit telemetry excluded), T-165 backup exclusion proven on the emulator (phone rows remain). FU-260.

## Batch 40 (2026-11-18)

`batch/2026-11-18-40`: T-127 gold price adapters (GoldAPI + MetalpriceAPI by config; recommendation MetalpriceAPI, PO to confirm EGP coverage and redistribution terms and add the key), T-140 hosting prep (GCP Frankfurt recommended; OpenTofu modules + manual OIDC deploy workflow, not deployed; PDPL summary, not legal advice), T-176/T-177 release pipelines (unsigned dry runs green; docs/06-release; secrets list in PO_DECISIONS Part 2), iOS Sign in with Apple entitlement + widget privacy manifest, T-058 pass 1 (54 Arabic fixes, 31 judgement calls in docs/02-design/copy-review-pass1.md for the human reviewer). FU-259.

## Batch 41 (2026-11-18)

`batch/2026-11-18-41`: T-156 bank-agnostic PDF statement import (pdfrx, column mapping per bank, settled-only dedupe; stays blocked on real statements), Android share → OCR, T-165 emulator script tightened (debuggable builds may be adb-backed-up on Android 12+; a release-type run is still needed), risky merchant aliases made exact + lint, FU-259 infra/release minors, T-031 public-sample search (no verbatim SMS found; docs/03-technical/sms-public-samples.md). FU-261.

## Batch 43 (2026-11-19): QA audit fixes

An independent QA audit of `main` @ bc5b9d1d (`docs/qa/`) found the app NOT READY for release: never run on a device in the audit, BUG-001 (no production keys), and 19 open board tasks. `batch/2026-11-19-43-qa-fixes` fixes the rest:
- BUG-002: API and Workers exit 0 on SIGTERM (was 134); process-level test `GracefulShutdownTests`.
- BUG-003: `GET /admin/v1/bank-requests` (catalog_editor, top 500, distinct installs) and `GET /admin/v1/metrics/daily-active` (any operator, `days` 1–90); a contract test now fails when a spec operation has no route.
- BUG-004/005: `Zaghlol-App` required (400) on every /v1 app operation; a purchaseToken over 512 chars is 400; bad bank-request country/channel still dropped silently, now documented.
- BUG-006/008: SRS, status rows (T-059/T-099/T-159 IN_REVIEW), README, phase log.
- BUG-007: `// ignore: riverpod_lint/missing_provider_scope` (plugin rules are namespaced).
- BUG-009: `ck_installs_catalog_version`.

This session had **no push access** (the push attach was refused), so the batch was handed to the PO as a git bundle in `C:\Projects\Zaghlol`. Cloud workspace notes: Docker Hub is blocked, so Testcontainers can't pull `postgres:17`; in-process HttpClient calls to 127.0.0.1 need `UseProxy = false`.

## Batch 44 (2026-11-19): T-137 and T-175 pass 1

`batch/2026-11-19-44` (on top of batch 43):
- **T-137** zaghlol-ops CLI: OIDC auth-code + PKCE loopback (IdP-agnostic; Entra or Google by config), token only in the OS credential store or memory, order ID from a no-echo prompt (no flag/env), a command for every Admin operation (a test fails on a missing one), `docs/ops/support-runbook.md` (one action per alert, R6-1 server rule + break-glass), `docs/ops/privacy-disclosures.md`, `backend/deploy/db/break-glass-unfreeze.sql` (only the sole enabled support_lead; canonical UUID). Waits on the PO for the IdP and the helpdesk/PDPL/retention record.
- **T-175 pass 1** (`docs/05-reviews/T-175-pass1.md`): 0 Critical, 1 High (= BUG-001), 1 Medium, 6 Low. Fixed here: M-1 (Dependabot, osv-scanner, gitleaks, CycloneDX SBOM in `security-scan.yml`), L-1 (notification taps only via the non-exported `NotificationTapActivity` with a per-process token; mark-paid waits for the lock and asks), L-2 (early error muting), L-3, L-6 (authenticated-by-default fallback policy, anonymous routes = spec `security: []`). Pass 2 needs signed builds, staging and devices.
- Review: one Opus combined review + one Sonnet delta; two Lead deltas (break-glass F1/F2, test-host routes under the fallback policy).

## 2026-11-19 evening: PO requests → M8, and two designs awaiting a pick

- **New tasks (M8, SRS v1.9 D-67…D-69):** T-187 hide amounts (eye, `****`), T-188 chart period selector, T-189 charts review (mockups for PO sign-off first; Lead review findings and research in the task file), T-190 app size (measure first; ~150 MB reported), T-191 BUG-001 trust anchors (blocked on T-140), T-192 T-175 leftovers, T-193 FU-263/264 sweep. Later the same evening T-194…T-199 (dark-mode quip, salary matching, 1/3/6/12-month bills, credit vs debit, bank badges, net-worth breakdown; SRS v1.10 D-70…D-75). Board now 199 tasks.
- **Designs, NOT tasks yet (PO asked to agree first):** design canvas "Zaghlol: bottom bar and dark mode options" (claude.ai artifact `7f8c9c63-f72c-433f-a501-8d9bdbed1b3d`): bottom-bar options A (current) … E (Captain Zaghlol hub), each on iOS 26 and Android M3 with a light/dark switch; dark themes 1 Jade Night (current) … 5 Night Garden. When the PO picks, update `docs/02-design/03-navigation.md` / `05-theme-2026.md` and then add the build tasks.

## 2026-11-20: no cloud KMS → T-200 (file keys) now, T-201 (OpenBao) before Gold

PO can't use a cloud provider. D-76 / ADR-023: `Kms:Provider = File` (T-200, merged into `batch/2026-11-19-45-planning`, review APPROVED) runs on a self-hosted Linux server: keys generated with `dotnet Zaghlol.Workers.dll --generate-keys`, bind-mounted read-only, owned by uid 1654, 0400/0500; 15 start-up guards; process non-dumpable. Deployment steps: `deployment.md` §3 "File KMS on a self-hosted server". T-201 (self-hosted OpenBao Transit) must land before Gold is sold to real users; envelope re-wrap decision belongs in its design note.

## Batches 46–48 (2026-11-20, run back to back at the PO's request)

- **46:** T-201 OpenBao Transit KMS, T-198 bank badges, T-194 dark-mode quip.
- **47:** T-196 recurring 1/3/6/12-month bills (schema v5), T-187 hide amounts (eye + `no_unmasked_amount` lint).
- **48:** T-195 salary as income (no schema change), T-197 credit vs debit.
All approved; branches stack: `batch/2026-11-20-48` contains 43–48. **Batch 49** (T-188 chart periods, T-199 net-worth breakdown, T-193 backend/ops/CI part) stacks on it: `batch/2026-11-20-49` contains 43–49. Not pushed (no push access this session); delivered as a git bundle. Before merging: run the CI `app-regen` workflow for goldens (lists in each review), then app-ci / backend-ci / the new `openbao-live` job. Still waiting on the PO: bottom-bar and dark-theme pick (design canvas), T-189 mockups, T-190 (Android build machine), T-191 production keys, bank badge colours/codes.

## Ready next

All board tasks left (19) wait on PO inputs or devices; see `PO_DECISIONS.md` Part 2:
- T-008, T-011, T-165, T-172 need devices.
- T-031, T-156, T-157 need real samples.
- T-058 needs an Egyptian-Arabic reviewer.
- T-059: built from public knowledge; PO spot-check.
- T-088 needs the Rive mascot (T-099 works with interim art).
- T-127: adapters built; PO picks the provider and adds the key.
- T-136: OIDC built for both IdPs; PO picks one and registers the app. T-137 follows.
- T-140: prep done (GCP Frankfurt recommended); PO chooses, plus legal check.
- T-159: built (JitPack, verified); needs a device accuracy run.
- T-175, T-176 and T-177 are release work, after hosting and store accounts.

Meanwhile the Lead clears follow-ups in batches of up to 5 lanes, and the explorer and device tests rerun on the emulator after big changes.

## Waiting on the PO (Amr)

Everything is in **`docs/workflow/PO_DECISIONS.md` Part 2** (business/legal, store accounts, files and devices, housekeeping). Part 1 holds the decisions the Lead took on 2026-11-13 under the PO's delegation; builders apply the rows for their task.

## Waiting on the architect or UX

- T-026 copy questions Q-03, Q-12, Q-13, Q-15, Q-16, Q-18 (Q-15/Q-16 block T-029); T-027/T-028 questions Q-19, Q-22, Q-27, Q-29, Q-34, Q-39, Q-41.
- Dark tokens §0 left undefined (FU-047) before T-053.
- T-122 code #15 and security F13 doc fixes; FU-025 account hard-delete wording.

## Decisions recorded this session

- D-70: database key stored with Zaghlol's own native channel, not `flutter_secure_storage` (T-015).
- K_spool is TEE-backed AndroidKeyStore, never StrongBox (Lead, T-060 review C1); K_db keeps StrongBox with fallback.
- Canonical merchant key keeps single spaces between tokens (parsing-engine §5, T-034).
- T-128: a lost sync reply waits for the next day; no server-side person-name detection (PO accepted).
- Batch CI workflow, combined C4 review, status docs per batch (PO, #27).
- 2026-11-11 (Lead): shared text skips the Capture Guard on both platforms; Pigeon `encryptedConfig` → plaintext, native encrypts; possible duplicates use `low_confidence` + reason (no schema change); `capture_senders` stays keyed by sender, DAO refuses channel conflicts; T-041 owns `CaptureRuntime.kt` and the Pigeon changes, build order T-041 + T-042 → T-040 → T-043, T-047 lands with T-040; devSms spike receiver stays until T-040; FU-094 busy handler (Dart VM profiler SIGPROF cut SQLite busy sleeps); FU-101 portable-regex lint rejects classes starting with `:` (Android ICU).
- Lead recommendation to the PO on FU-109 M-1 (user-added phone-number senders): live capture only with a financial-looking filter, consent text, separate opt-in "scan past 3 months", never put their unparsed messages in review.

## Progress page

- Dashboard artifact: https://claude.ai/artifact/JLtixDQ3FQ7aogVaWxRoEG (not refreshed since 2026-11-08; see `docs/workflow/tools/README.md`).
