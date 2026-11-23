# Batch 61 review (T-218..T-222)

Reviewer: code-reviewer (Opus). Diff: `git diff origin/main...HEAD`. Tests run: `flutter test --exclude-tags golden test/features/insights test/core/theme test/features/settings test/features/voice test/app` -> 648 passed.

## T-218 — APPROVED
`chartsOpenToFreeProvider` (default true) replaces the static; `GoldGate.chart(openToFree: true)` default keeps user behaviour identical; every call site (chart_detail, charts_screen, overview/trends/categories tabs, paywall benefits) watches the provider. Gold gates elsewhere untouched. Hero caption now takes a period (this month / resolved period) in ar and en; select forms intact. Covered-earlier line on the categories tab has a test.

## T-219 — APPROVED
«آخر ست شهور» is colloquial and avoids digits; voice label «التعرّف على الصوت أونلاين» is shorter and neutral, with en «Online voice recognition». No tone issue.

## T-220 — APPROVED
Light #F3FBF7 and dark #000000 match 05-theme-2026.md section 0 and D-79. Android: `launch_bg` in values and values-night, v31 and night-v31 splash styles set the splash background and icon, legacy drawables use the color. iOS: LaunchBackground colorset (light and dark) referenced by the storyboard; the storyboard fallback namedColor is the light value. Colour test present.

## T-221 — APPROVED (minor)
`run_backend_local.sh` reads four env vars, fails fast if unset, and has no password literals left.
- minor: `docs/qa/tools/api_db_followup.py:286-295` still does `.replace('zaghlol_dev_only', ...)` with literal dev passwords; this no longer matches the env-supplied SU password, so the script is silently broken and still holds literals.

## T-222 — APPROVED (minor)
bundletool SHA-256 verified: I downloaded `.../releases/download/1.18.1/bundletool-all-1.18.1.jar` and got 675786493983787ffa11550bdb7c0715679a44e1643f3ff980a529e9c822595c, which matches the pin. `sha256sum -c` runs right after the curl. `enforce_budget` is true in the baseline and the comment now says so. Items closed as already done were verified in code: MainActivity.kt:117 `setLaunchRoute(launch?.route)`, :189 LAUNCHED_FROM_HISTORY handling. Import order fixed.
- minor: the workflow change is not exercised by a `ci/T-222` run; the batch run is the gate.

## Proposed FU-289 (minors)
1. Fix `api_db_followup.py` to use the QA_PG_* env vars.
2. Confirm size-report on the batch run.

Verdict: all five APPROVED; no blockers or majors.
