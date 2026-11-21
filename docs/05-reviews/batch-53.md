# Batch 53 review (batch/2026-11-21-53)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security, one pass) |
| Date | 2026-11-21 |
| Diff | `git diff origin/main...batch/2026-11-21-53` (merge f5902cb8) |
| Lanes | 1 server kit (B53-server-kit) · 2 widget FU-206a/b (B53-widget) · 3 small app items (B53-ui-small) · 4 legal/store drafts (B54-legal-store) · 5 design rework T-202/T-203/T-204 |
| CI evidence | backend-server-kit 44846160807 green (compose config, hardening jq asserts, caddy validate, promtool, amtool, shellcheck, actionlint); app-ci 44846615486 green on ci/B53-widget (Kotlin + Swift unit tests, all Android/iOS builds) |
| Local run | `flutter test test/core test/features/home test/features/b53 test/features/widgets_bridge --exclude-tags golden`: **1440 passed, 1 skipped, 1 failed** (see 3-1) |
| Goldens | not reviewed (CI regenerates) |

Summary of verdicts: lane 1 CHANGES_REQUESTED (2 major + 1 security Medium), lane 2 APPROVED, lane 3 CHANGES_REQUESTED (1 major, CI-red test table), lane 4 APPROVED, lane 5 APPROVED. Minors → **FU-275**.

---

## Lane 1 — Self-hosted server kit (ADR-025, deployment.md §6) — CHANGES_REQUESTED

Checked and fine: two env files (Compose interpolates `production.env`; api/worker get only `app.env` plus their own connection strings; CI asserts the api env holds no `migrator`); passwords applied with `\getenv` + `:'var'` (never on a command line or in SQL text); `docker login --password-stdin` with a throwaway `DOCKER_CONFIG`; File-KMS mount `/etc/zaghlol/kms-production/keys:/run/zaghlol-kms:ro` on api and worker exactly as deployment.md §3 (not under `/run/secrets`; key tool makes 0500/0400 uid 1654; `harden.sh` creates the parent 0700 1654); `ulimits.core: 0`, `cap_drop: ALL`, `no-new-privileges`, read-only roots, non-root users on every service; swap off + no-core sysctl/systemd/limits in `harden.sh`, documented trade-off; only Caddy publishes 80/443(+udp) (CI-asserted), Grafana only on 127.0.0.1; fixed subnet 172.30.52.0/24 = `ForwardedHeaders__KnownNetworks__0`, Caddy replaces client XFF; automatic TLS; `/admin/*` CIDR-gated; catalog path `/srv/snapshots/catalog` matches `DirectorySnapshotStore` (`<dir>/catalog/<v>/…`). Deploy workflow: dispatch-only, repo-variable gate, `backend-production` environment with reviewer, pinned `known_hosts` + `StrictHostKeyChecking yes`, key written under `umask 077`, nothing secret echoed, digest-validated input, image deployed by digest, third-party images digest-pinned. Backups: ssh with pinned host key, `umask 077`, retention, failure unit; encryption at rest is documented as a target requirement (deployment.md "keep the target encrypted and private"), acceptable. `dump` restore refuses the live DB name. Deploy key = root-equivalent is documented in harden.sh, deployment.md and ADR-025.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1-1 | **major** (security **Medium, before merge**) | backend/deploy/server/Caddyfile:22-37 | Caddy's access log includes `resp_headers` by default and the filter only deletes `request>headers` and `request>tls`. `POST /v1/apple/android-callback` answers 303 with a `Location: intent://callback?…` carrying Apple's authorization code and `id_token` (email/sub); `AppleCallbackEndpoint` promises "the Location is never logged" and `LogFieldPolicy` lists `Location` as forbidden. On this host Caddy writes it to stdout → Docker json logs (kept 5×10 MB). Contradicts the privacy policy ("request logs without request content"). | Add `resp_headers delete` (or at least `resp_headers>Location delete`) to the `fields` filter. Add a CI step (e.g. `caddy adapt` + jq) asserting the filter deletes `resp_headers`. |
| 1-2 | **major** (data) | backend/deploy/server/backup/restore.sh:50-57 | `live` drops the live schema **before** checking the dump: a mistyped/unreadable path fails at the `< "$file"` redirect after `DROP SCHEMA zaghlol CASCADE`, and any pg_restore error (`--exit-on-error`, no transaction) leaves a half-restored schema; either way `set -e` exits with api/worker/caddy stopped. The brief asked for "no accidental drop of prod". | Before `confirm`: `[ -r "$file" ]` and `pg pg_restore --list < "$file" >/dev/null` (as `backup.sh` does). Then run drop + restore in one transaction (e.g. `pg_restore --single-transaction --clean --if-exists` instead of the separate DROP, or restore into a scratch DB and swap schemas). Keep services stopped on failure but print the recovery path. A shellcheck-level test is enough (CI can run it against a throwaway postgres container if cheap). |
| 1-3 | **major** (deploy gate) | backend/deploy/server/deploy.sh:53-56 | `caddy` has no healthcheck, so `{{.Health}}` is empty and `grep -vc ' healthy$'` always counts ≥1: the Docker-health wait can never succeed, always burns 180 s, and then only the public `/v1/health` curl decides. A crash-looping/unhealthy **worker** (RTDN/ASSN processing) or one dead api replica passes the smoke test and is never rolled back. Same in the rollback's `smoke`. | Check health only for services that define one (`api worker`), and fail `smoke` (return 1) if the loop times out rather than falling through; or give Caddy a healthcheck. Optionally require `running` ≥ API_REPLICAS+1. |
| 1-4 | minor | .github/workflows/backend-deploy-server.yml:27,124 | The token piped to the server is the job `GITHUB_TOKEN` with `packages: write` (needed for the build step). A compromised host can push to GHCR until the job ends. | Pull with a read-only token: split build (packages:write) and deploy (packages:read) into two jobs, pass the digest as output. → FU-275 |
| 1-5 | minor | backend/deploy/server/backup/restore.sh:44 | `dump` mode accepts `postgres`/`template1` as scratch name (`DROP DATABASE` then fails noisily). | Refuse `postgres`, `template0`, `template1`. → FU-275 |
| 1-6 | nit | backend/deploy/server/deploy.sh:88 | Redeploying the running digest sets `BACKEND_IMAGE_PREVIOUS` to the same digest, so a failed smoke "rolls back" to itself. | Keep the old `BACKEND_IMAGE_PREVIOUS` when `previous == IMAGE`. → FU-275 |
| 1-7 | nit | docs/03-technical/deployment.md §6 | The privacy policy (§11) promises deletion of the install record; nightly dumps and the off-server mirror keep it up to 15 days. | One line in deployment.md / policy draft: deleted records leave backups within the retention period. → FU-275 (PO legal list) |

## Lane 2 — Home-screen widget FU-206a/b — APPROVED

Traced: `widgetBridgeWiringProvider` returns before building anything while `appLockEnabledProvider` is still loading (widget_bridge.dart:122), so a cold start never publishes on a guess; `AppLockState` defaults to `locked: true`. With the lock on, `paused/hidden/detached` sets `appBackgroundedProvider` and the masked snapshot is published with zero delay; resume clears it; turning the lock off clears it. The builder never formats the real figure while masked (formatter `hidden:`), and `secondaryTextByDay` carries only day counts, no amount. Contract v2 is additive: Dart/Kotlin/Swift pigeon field nullable; both stores read v1 and v2 (`n ≤ 62` bounds check, trailing-bytes check on iOS), write v2; 62 × 120-char lines stays under the 16 KiB cap. Kotlin `secondaryAt` / Swift `secondary(at:)` pick by local-midnight count, clamp negative (clock back) to 0 and show "" past the list; `WidgetMidnightWorker` is a unique REPLACE one-shot, re-armed by `refreshAll`, cancelled in `onDisabled`, carries no data; iOS timeline has one entry per coming midnight with `.atEnd`. Tests: cold-start, background mask with/without lock, per-day lines, Kotlin/Swift v1-decode and roll tests (CI green).

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 2-1 | nit | app/lib/features/security/domain/app_lock_controller.dart:80 | Doc says "true while backgrounded **with the lock enabled**", but the notifier is set regardless of the lock; the lock check is in the bridge. | Fix the comment. → FU-275 |

## Lane 3 — Small app items (FU-229b, FU-166a, FU-237a, FU-172d) — CHANGES_REQUESTED

Checked: `zaghlol/app_settings` carries one method, no arguments (Kotlin `ACTION_APPLICATION_DETAILS_SETTINGS` for own package; Swift `openSettingsURLString`), Dart side swallows `PlatformException`/`MissingPluginException`; handler unregistered in `cleanUpFlutterEngine`. Upsell cap: `tryShow` returns false for Gold before reading the store, persists `upsell_last_shown` in encrypted settings, a clock moved back (`last` in the future) keeps it closed, so it can't nag; only caller is the voice limit on the transition into `limit`; any error → no prompt. ROI dismissals persist as validated slugs (8 rules × currency; max 64 entries). Salary credit derived from `salary.plan` + latest `salary.state` anchor; backup flag from the backup module.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 3-1 | **major** (CI red) | app/test/core/settings/settings_repository_test.dart:24 (`allKeys`) | "every key is in the allKeys table (none forgotten)" fails: expected 49, actual 47. The two new keys `upsellLastShown` and `roiDismissedTips` are not in the table, so their round-trip/reset is untested and app-ci on the batch will fail. | Add both rows (e.g. `upsellLastShown: null → 1760000000000`, `roiDismissedTips: {} → {'egp_coffeemachine'}`). |
| 3-2 | minor | app/test/features/b53/small_followups_test.dart:114 | Test is named "… never for Gold" but no case calls the provider with `isGold: true`. | Add the Gold case (entitlement override → returns false, paywall not opened, `upsell_last_shown` not written). → FU-275 |
| 3-3 | minor | app/lib/features/gold/presentation/upsell_cap.dart (`tryShow`) | Read-then-write is not serialised; two app-raised prompts in the same frame could both pass. Only one caller today. | Serialise in `UpsellCap` (a pending future) before a second caller is added. → FU-275 |

## Lane 4 — Legal / store drafts (site/**, site-pages.yml, store-listing.md) — APPROVED

Privacy policy matches the real flows: names the server and its four jobs (never "no server"); server-received table matches BR-SYNC-03 as amended (install ID, platform/versions, purchase tokens, attestation D-45, iOS seat keys D-62, time nonce, optional sign-in, opt-in contributions, bank requests, truncated-IP logs 30 days); no analytics/ads/crash SDKs; backups AES-256-GCM to drive.appdata/iCloud; OS online speech recognizer disclosed with consent; order ID not stored server-side. Pages hold no scripts, iframes or external resources (CSS local); workflow is dispatch-only, `persist-credentials: false`, refuses `{{PLACEHOLDERS}}` by default, actions SHA-pinned. Store listing uses the approved claim only, no voice/charts-tier/Zakah claims. The PO contradiction list in PO_DECISIONS (FU-195-legal) is the right place for open legal points.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 4-1 | minor | .github/workflows/site-pages.yml:11,47 | `allow_placeholders: true` publishes the "draft preview" to the only (public, custom-domain) Pages site, so a placeholder-filled privacy policy can go live. | Drop the input, or make it upload the artifact only (no `deploy` job). → FU-275 |
| 4-2 | nit | site/privacy/index.html §11 | No mention that deleted server records persist in backups up to the retention period (see 1-7). | Add after legal review. → FU-275 |

## Lane 5 — Design rework T-202 / T-203 / T-204 — APPROVED

T-202: dark tokens equal the True Black table in 05-theme §0 (bg/surface/surfaceAlt/surfaceSunk/outline/text/textMuted/primary/primaryContainer/incomeText/zaghlol/warning/danger; apricot gradient same as light); dark `shadow` transparent, hero flat `#141414` + outline, progress mint; light values unchanged (only new fields added, equal to existing light colours). Contrast test covers AA pairs in both themes (documented 18.4 vs 18.7 deviation). T-203: one `ZBottomBar` + `ZAddButton` for both platforms (62 dp, 5 dp ring, raised 34 dp, light-only shadow) laid out by a delegate so the body ends at the bar top; bar hides with the keyboard; tabs ≥ 48 dp, `Semantics(selected:)`, Add labelled, caption excluded from semantics; labels wrap at 1.3×. `usesGlassBar`, NavigationBar/FAB paths and the iOS/Android shell goldens are gone; remaining `TargetPlatform.iOS` checks are content-only (capture, scan, OCR, transitions). T-204: one Home header, `flatBorder` outline on flat dark surfaces, no green text in Home dark (test). AC→test maps present in the task files; tests pass locally.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 5-1 | minor | app/lib/core/theme/z_tokens.dart:117 (`brandMint`, `surfaceSunk`, `zaghlolText`) | New tokens are not used anywhere. 05-theme §0 says chart series and switches use `brandMint` in dark; charts still read `c.primary` (e.g. gold_chart_bodies.dart:55), so dark charts draw **white** series and the Material switch uses white. Not green text (AC holds), but not the spec. | Point chart series / switch theme at `brandMint`, hero KPI strip at `surfaceSunk`, Zaghlol banners at `zaghlolText`; or remove the unused tokens. → FU-275 |
| 5-2 | nit | app/lib/core/ui/z_card.dart:31 | `ZCard`/`ZHeroCard` repeat `brightness == dark ? Border.all(outline) : null` instead of the new `c.flatBorder`. | Use `c.flatBorder`. → FU-275 |

---

## Fix round (Lead)
Blocking: **1-1** (security Medium, before merge), **1-2** (data), **1-3** (deploy gate), **3-1** (CI red). 1-1, 1-3 and 3-1 are a few lines each (Lead delta check); 1-2 is ~15 lines in a shell script. Everything else → **FU-275** (owner: B53-server-kit lane for 1-4…1-7, ui-small for 3-2/3-3, legal for 4-1/4-2, flutter-ui for 2-1/5-1/5-2).

## Checklist
- [x] Tests run (1440 pass, 1 fail = 3-1); Kotlin/Swift via CI 44846615486
- [x] RTL/LTR: shell uses directional insets/alignment; site pages ar+en
- [x] No hard-coded strings (new `commonNavAddLabel`, `commonNavBadge*` in both ARBs)
- [x] No `double` money; widget lines carry no amount
- [ ] No sensitive data in logs — fails on 1-1 (Caddy response headers)
- [x] Scope: each lane stays in its files; CLAUDE.md token line updated for D-79 only

## Fix round (Lead check)

- 1-1, 1-2, 1-3 fixed on the batch branch (server kit): Caddy log filter drops response and request headers (CI asserts it via `caddy adapt` + jq); `restore.sh live` checks the dump, restores into `zaghlol_restore_new`, verifies, then swaps by rename with the old database kept and services restarted by a trap; `deploy.sh` waits on api and worker health and rolls back on timeout. New `restore-test` CI job proves a missing, garbage or empty dump leaves the source database untouched. backend-server-kit run 44852011550 green (5 jobs).
- 3-1 fixed by the Lead (settings `allKeys` table), test passes.
- Lane 5 minor (unused True Black tokens) taken now at the PO's design priority: `brandMint` for progress, switches and the first chart series in dark, `surfaceSunk` for the hero KPI strip, `zaghlolText` for Zaghlol banners; light pixel-identical; `brand_mint_test.dart`.
- All lanes **APPROVED** after the fix round. Remaining minors stay in FU-275.
