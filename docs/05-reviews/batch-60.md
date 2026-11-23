# Batch 60 review (T-213..T-217)

Reviewer: code-reviewer (Opus). Branch `batch/2026-11-23-60`. Method: production diff read; non-golden tests run (app/home/voice/mascot/settings/backup/onboarding/core-ui/insights: all green; backend `--filter OpenBao`: 88 passed, 4 live skipped).

## T-213 startup sheet flash: APPROVED
- Root cause is right: a cold-start catch-up scan on a later run went running -> done while the gate was already past onboarding, opening an empty S-06 sheet. Gating on `_sawFirstRun` (set when the flow is built) is sound.
- Interrupted first run resumed after a restart: `setupInstalledOn` is still null, so the flow shows again and `_sawFirstRun` is true. Nothing lost.
- Trade-off (accepted): a user-started rescan in a later session no longer opens the sheet from the gate. It must have its own results UI (the scan screen). Minor FU: confirm.
- Minor: `enabled` is checked after `_sawRunning` is updated, fine.

## T-214 voice online consent remembered: APPROVED (minors)
- Stored as boolean in the encrypted settings DB (`voice.online_consent`), default false, revocable via the Privacy switch, wiped with the DB by delete-all. On-device is still tried first; consent is read only when on-device is unsupported. A read failure means not consented; a write failure falls back to this-session only. Correct.
- Travels in backups only if the settings table is in the snapshot (same as the contribution opt-in): acceptable, it is a preference, not financial data.
- Minor: `docs/06-release/privacy-consistency.md` row 4 says "only with explicit consent"; add "remembered, revocable in Privacy" so the store forms match.
- Minor: copy-deck label length warnings (AR 43 > 28, EN 41 > 30 for L). Shorten, e.g. "Online voice recognition" / "التعرّف على الصوت أونلاين". The sentence is also two sentences in AR (S = one sentence).
- Minor: no test that revoking in Privacy makes the next session ask again (the AC map covers the switch write only).

## T-215 mascot moods: APPROVED (minors)
- Payday: celebrates only captured (bank-message) anchors within 3 days; older ones are marked silently; marked before display, stored in settings, so once per payday across restarts. Latched in the slot so rebuilds keep the line. Correct.
- Minor: if the mark is stored but the Home slot is never shown (app killed before first frame), the celebration is lost. Acceptable.
- `ZMascotBubble` timer is cancelled in `dispose` and the `mounted` guard is present; the home/onboarding/core-ui/insights suites that mount it pass with no pending-timer failures.
- Tap line rotation and the one-bird-per-screen rule: no regression seen (payday and normal bubble are exclusive).

## T-216 FU sweep: APPROVED
- Backup wait timeout: `TimeoutException` is caught by `on Object`, returns false before the entitlement check, so a non-verified user cannot reach Gold-only runs and a Gold schedule is not cancelled (reconcile is not reached). Next start or resume retries. Correct.
- Drill state isolation: search, card filter and selection are overridden in the drill scope. OK.
- Rive: shared file cached once, failure not cached, controllers per mount; paint guard falls back to the still through a post-frame callback. OK. Minor: a guard that swallows every paint error also hides real bugs in debug; log in debug only (no data involved).
- `paceProvider` future-period fix and `rederivePending` `|| hidden` rerun are small and tested.

## T-217 OpenBao relogin race: APPROVED
- The forced-login failure timestamp is now written before the gate is released (`catch when (forced)` then rethrow), so a waiter cannot log in unthrottled. Success clears it as before. Race test present; OpenBao suite passes.

## Docs finding (copy-deck check)
`copy_deck_check.py` reports 24 errors. 22 come from batch 58 `insights_v2_trends_*` rows (key shape, digits in AR). 2 are new in this batch: `voiceOnlineConsent_label` / `_sentence` (bad key shape: keys must be `snake_case` segments like `privacy_voiceOnline_label`). Not major: the app's l10n ARB files are not generated from the deck and CI does not run the checker (confirmed by the green tests). Fix both in FU-288.

## Verdict: APPROVED (no blockers or majors)

## Proposed FU-288 (minors)
1. Fix 24 copy-deck key-shape/digit errors (22 `insights_v2_trends_*`, 2 `voiceOnlineConsent_*`); shorten the voice label (L limits); make the sentence one sentence in AR.
2. Update `privacy-consistency.md` row 4 for the remembered, revocable voice consent.
3. Test: revoking voice consent in Privacy makes the next voice session show the consent sheet.
4. Confirm a user-started rescan after first run shows its results in its own screen (the gate no longer opens the sheet).
5. Rive paint guard: debug-only log for swallowed paint errors.
