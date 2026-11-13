# Review — batch 12 (T-185, T-180, T-089, T-052, T-024, glue d5492f5)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer acting also as security-privacy-reviewer (one reviewer, Opus) |
| Date | 2026-11-13 |
| Base | `origin/batch/2026-11-13-12` @ d5492f5; per-task diffs `origin/main...origin/task/<branch>` |
| Verdicts | T-185 APPROVED · T-180 APPROVED (device ACs open) · T-089 **CHANGES_REQUESTED** · T-052 **CHANGES_REQUESTED** · T-024 APPROVED · glue d5492f5 OK |

## Checks run on the batch head

| Check | Result |
|---|---|
| `flutter pub get --enforce-lockfile`, `flutter analyze` | clean |
| `dart format --set-exit-if-changed` (app/lib, app/test, zaghlol_domain) | 0 changed |
| `flutter test test/core test/features/home test/features/transactions test/features/budget test/main_test.dart test/goldens` | 1321 passed, 1 skipped (pre-existing) |
| `dart test` packages/zaghlol_domain | 254 passed |
| `dotnet test` Zaghlol.Application.Tests | 1008 passed |
| `dotnet test` Zaghlol.Contract.Tests `RestoreParser` | 18 passed |
| Api restore tests, `RestoreServiceTests` (Testcontainers) | no Docker here; taken from GitHub backend-ci 43352840839 on `ci/T-185` @ 4efbe3b (= task head), all jobs green |
| T-180 Swift/Kotlin | GitHub app-ci 43349912019 on `ci/T-180` @ 723fdb5 (= task head), green |

---

## T-185 — POST /v1/purchases/restore — APPROVED

Traced: strict parse (`AllowDuplicateProperties=false`, depth 32, lone-surrogate walk, by-hand binding from the same tree, JCS from the same tree minus top-level `attestation`, ordinal UTF-16 member order, lowercase `\u00xx`); `bodyHash` takes `installId` from the token only (R2-1 test posts A's body with B's token → 422). Order: seat-key structure → attestation → per-purchase limit → store verification with no transaction open → one seat transaction (distinct purchase ids ascending, FU-112) → entitlement. iOS App Attest register/assert, `SeatKeyProofVerifier.Verify`, element-0 registration with `AppAttestVerified` and the limit charge share one transaction; every refusal returns before `CommitAsync`, so R5-6 holds (the test reads the counter before/after and replays a matching element 0 to show the counter does advance). Attestation `Unavailable` → 503 + `Retry-After`; Play Integrity maps HTTP non-2xx, timeouts, circuit-open and JSON errors to `Unavailable`, so a decode outage is never 422. Store outage → 502, own budget → 503. 409 only when nothing is `active`/`pending` and a cooldown refusal exists, with the earliest stored `nextMoveAt`. Precedence matches. Responses carry no token/key/proof; `RestoreItem.ToString()` is masked; no request logging.

| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| 1 | minor (Security Low) | backend/src/Zaghlol.Infrastructure/Purchases/RestoreServiceCollectionExtensions.cs:28,65 | `Prune` can `TryRemove` a key whose queue another thread has just obtained via `GetOrAdd` and enqueued into; that attempt is then lost. Only reachable at ≥ 200 000 live keys. | FU: remove only under the queue lock and re-check emptiness, or swap in a fresh queue with `TryRemove(KeyValuePair)`. |
| 2 | minor (Security Info) | backend/src/Zaghlol.Application/Purchases/Restore/RestoreService.cs:68,289 | `ChargeLimits` charges purchase by purchase; when the 2nd purchase is over its limit the 1st has already been charged, and on iOS a charge survives a failing `CommitAsync`. Fails closed (only over-counts). | FU, or note it in the design note as accepted. |
| 3 | nit | backend/src/Zaghlol.Application/Purchases/Restore/RestoreService.cs (FoldAsync) | A `Refused` seat with `NextMoveAt == null` falls through to a 200 with status `invalid` instead of 409. T-184 always stores `nextMoveAt` on refusal, so it can't happen today. | Optional: assert/fail closed explicitly. |
| 4 | Info | RestoreServiceCollectionExtensions.cs | 10/day per purchase is per process (accepted by the Lead for one instance). | Go-live check stays in T-140. |

AC → evidence: R3-8 `R38EveryInvalidVector…`; R2-6 `ADuplicateNestedMember…`; R2-1 `R21AProofMadeForOneInstall…`; Android failures/basic `AFailedProofIs422…` (theory), `ABasicIntegrityRestore…`; R4-1(3) `R413AReordered…`; R5-6 `R56AnElementZero…`; R5-2 `R52APassingRestore…`; D-65(a) `D65aAThirdSameIPhone…`; cooldown `TheCooldownIs409…`; account `AnAccountLinkedPurchase…`; limits `TheSixthRestoreInAnHour…` (endpoint + live), `TheEleventhAttempt…`; outage `AnAttestationOutageIs503…`, `AStoreOutageAborts…`; R4-2 + FU-011 `RestoreLiveContractTests`. All PASS (CI).

## T-180 — TrustedClockHostApi — APPROVED (device ACs open)

Android `currentTimeMillis` / `elapsedRealtime` / `Settings.Global.BOOT_COUNT` (null on missing setting or `SecurityException`); iOS `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)` (Darwin's continuous clock, counts sleep, restarts at boot), `bootCount = nil`; read back to back; no logging (also asserted by a source test); Pigeon regenerated (`clock_api.g.dart`, `.g.kt`, `.g.swift`, Swift file now in the Xcode project); `PrivacyInfo.xcprivacy` in Runner resources with `NSPrivacyAccessedAPICategorySystemBootTime` / `35F9.1`; registered and unregistered on the UI engine.

| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| 1 | minor (AC open) | docs/05-reviews/T-180-device.md:3 | The three real-hardware ACs (sleep ≥ 15 min on both OSes, Android reboot `bootCount + 1`, iOS reboot monotonic drop) are "NOT YET RUN". The code is right; the task can't be marked DONE on them. | Merge; keep T-180 open as "device test pending" (PO device checklist, alongside T-165/T-015) and make it a gate for T-144 shipping, not for the merge. |
| 2 | Info | app/ios/Runner/PrivacyInfo.xcprivacy | Reason 35F9.1 forbids sending the value or anything derived from it off the device. | T-144 must not put `monotonicMs`-derived values in any backend request; note it in T-144's brief. |
| 3 | nit | app/pigeons/clock_api.dart:1-4 | Header still says "Names only; methods … are added by the owner task". | Update the comment when next touched. |

## T-089 — Self-transfer pairing, FX, card settlement — CHANGES_REQUESTED

The core is sound: pure rules in the domain package with integer/BigInt FX math; one `BEGIN IMMEDIATE` transaction per call; every claim is `… WHERE deleted_at IS NULL AND transfer_pair_id IS NULL` with exactly-one-row checks plus UNIQUE out/in, so concurrent callers get one winner (tested for two engines and link vs auto); ambiguity on either side opens `transfer_ambiguous`; cross-currency is a suggestion only; nothing converts or merges amounts; `unlink` relies on `ON DELETE SET NULL` and clears both flags (tested); FU-114 77-3 `BULK_PAIRED` is correct.

**Lead's question: when one leg is soft-deleted, is money silently missing? Yes.** `TransactionsDao` soft-delete (transactions_dao.dart:90) only sets `deleted_at`. The surviving leg keeps `is_internal = 1` and a `transfer_pair_id` whose pair still names the deleted leg, so:
- its amount is left out of spend (out leg) or income (in leg), and no review item or label explains why;
- it can never pair again: `_evaluate` skips it (`existing.inTxnId != null`, transfer_pairing.dart:261) and `_freeLegs` filters it out, so a correct late counterpart arrives, stays unpaired and is counted too.
The typical case is a mis-pair: the user deletes the wrong leg instead of unlinking, and the other leg's 1,000 EGP drops out of the totals for good. Before T-089 this state couldn't exist, so the fix belongs to this task.

**Re-pairing a manually unlinked pair:** the builder's residual is real. After `unlink`, both legs are free again, and the next `onPersisted` on either one (the doc comment says to call it after any edit) pairs them again silently. The user's explicit FR-XFR-02 decision is undone and the spend disappears again. The same happens to a one-sided own-account leg the user unlinked: it gets re-marked internal.

| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| 1 | **major** | app/lib/features/transactions/application/transfer_pairing.dart:241-263 (+ no removal entry point) | Soft-deleting a paired leg orphans the partner: it stays internal, is excluded from totals and can never re-pair (above). | Add a use-case entry (e.g. `onRemoved(txnId)`) that, in one transaction, deletes the pair and returns the survivor to the free state (clear `is_internal`, then re-evaluate it, so an `own_account` out leg becomes one-sided again). Also make `_evaluate` treat a pair whose other leg is not live (deleted or no longer a posted transfer) as dissolved. Tests: delete the in leg, then check the out leg counts as spend; delete, then check a late correct counterpart pairs. Add an FU so the delete/edit wiring task calls `onRemoved`. |
| 2 | **major** | app/lib/features/transactions/application/transfer_pairing.dart:207-237, 268-370 | A manual unlink is not remembered, so the next `onPersisted` pairs the legs again or re-marks the one-sided leg internal, silently removing money from the totals. | Persist the decision (e.g. a resolved `review_items` row, `resolution = 'unlinked'`, holding both ids, or whatever the schema allows without a migration) and exclude that leg pair from auto pairing and the one-sided rule. `link` still overrides it. Test: link, unlink, `onPersisted` on both legs, still unpaired and counted. |
| 3 | minor | packages/zaghlol_domain/lib/transfers/transfer_matching.dart:109 | `decideSameCurrency`'s doc says the pool "may contain [leg]", but the reverse check uses `[...all, leg]`. If the pool already holds `leg`, it appears twice, `reverse.length == 2`, and a clean one-to-one pair is reported as `AmbiguousMatch`. Production passes a pool without self (`t.id <> ?1`), so this isn't reachable today. | Drop `leg` from `all` before adding it (or dedupe by id) and add the domain test `decideSameCurrency(i, [o, i])` → `PairWith`. Trivial; fix in the same pass. |
| 4 | minor | transfer_pairing.dart:357-369 | Re-running `onPersisted` on a one-sided own-account **in** leg re-claims it and publishes a fresh event every time (not a no-op, unlike the doc's "Idempotent"). Harmless but noisy. | FU: skip when the leg is already `is_internal = 1` with no pair. |
| 5 | Info | — | Not wired anywhere yet (no provider/ingest hook calls `TransferPairingUseCase`). So #1/#2 aren't reachable by users at merge, but they must be fixed before the wiring task lands. | — |

AC1 spec example (0 spend, both internal) PASS; AC2 two candidates → no auto-pair PASS; tests run green.

## T-052 — Home read model — CHANGES_REQUESTED

Per-currency figures are never summed (`orderCurrencies`, primary first, one `HomeCurrencyFigures` per currency, `net` same-currency); EC-55 `showCurrencyUi` only with > 1 currency; feed rows carry `excludedFromTotals = isInternal`; the card filter is a non-auto-dispose `NotifierProvider`. FU-110 ordering is now right: one app-level listener runs `onTransactionsChanged` and only then bumps `cycleDataVersionProvider`; readers watch the version, so there is no race between two listeners. Resume handling re-reads today, sweeps since the last foreground, then bumps.

| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| 1 | **major** | app/lib/features/home/application/home_read_model.dart:112-117 | Contradicts the Lead decision. `buildCycleOverview` gets `repo.totals(cycle, accounts: filter)`, so `safeToSpend` (and its budget figures) is computed from the **filtered** spend. Picking one card inflates safe-to-spend by everything spent on the other cards. No test covers safe-to-spend under a filter. | Compute the overview, and therefore `safeToSpend`, from unfiltered totals (`repo.totals(cycle)`). Use the filtered totals only for the displayed spend/income/pending figures, plus the feed. Test: budget 5,000, spend 1,000 on acc1 and 300 on acc2, select acc2: `safeToSpend` is unchanged and `spend` is 300. |
| 2 | minor | app/lib/features/capture/application/capture_providers.dart:190 (pre-existing, outside T-052 files) | Nothing publishes on `domainEventBusProvider` yet: the UI-engine scan ingest is built without `events:`, so Home refreshes after a scan only on the next resume sweep. | FU for the wiring/composition-root task: pass `ref.read(domainEventBusProvider)` to `buildIngestRawMessages` (and to bulk edit and pairing when they're wired). |
| 3 | nit | app/lib/features/home/application/home_read_model.dart:35-37 | `net` is income − spend, which can go negative. Fine for a `Money`, but it is computed from the filtered totals; if #1 is fixed by splitting the totals, say which set `net` uses. | Doc comment. |

AC "only EGP → no currency UI" PASS (`showCurrencyUi` tests). AC "card filter changes all Home figures": PASS for spend, income and the feed, **except** safe-to-spend, which per the Lead decision must not change.

## T-024 — App shell — APPROVED

go_router `StatefulShellRoute.indexedStack` (four branches keep state; re-tap pops to root; back on a non-Home tab goes Home); iOS glass capsule + detached Add, Android M3 `NavigationBar` + `endFloat` FAB; only directional insets, first tab on the right in RTL (tested); all labels from ARB, Egyptian colloquial in `ar`; goldens 2 platforms × 2 locales × 2 themes. Deep links: `zaghlol` scheme only (manifest VIEW filter and `CFBundleURLTypes`), more than 256 chars or an unknown target → `/home`, other schemes pass through untouched. The link is never logged or shown.

| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| 1 | minor (Security Low) | app/lib/core/routing/app_router.dart:57-61 | No `errorBuilder`/`onException`. Any location that matches no route falls to go_router's default error page, which prints the location (echoes input) and leaves the user stuck there. Today only `zaghlol` links reach the app and they all map, but a later route change or an OEM passing a raw path would expose it. | FU (or trivial fix now): `onException: (_, __, router) => router.go(AppRoutes.home)`. |
| 2 | Info (Security) | app/android/app/src/main/AndroidManifest.xml (+ Info.plist) | `BROWSABLE` custom scheme: any web page or app can open `zaghlol://add`/`review`. It only navigates, carries no parameters and has no side effects, so this is acceptable. Future targets that act (pre-filled amounts, confirmations) must not trust the link. | Note in 03-navigation §6. |
| 3 | Info | — | FU-044 (IBM Plex fonts) is still PO-blocked; the goldens use the fallback font. | — |

AC: tabs preserve state PASS; platform variant PASS; deep links PASS (`deep_links_test`, shell tests); DoD PASS.

## Glue d5492f5 (app/lib/main.dart) — OK

`_LocalizedApp` watches `cycleAppWiringProvider` once at the root, so the wiring lives as long as the container. On `AppLifecycleState.resumed` it calls `onResume`; the observer is removed in `dispose`.

| # | Severity | File:line | Issue | Required change |
|---|---|---|---|---|
| 1 | minor | app/lib/main.dart:87 | `unawaited(onResume())`: a DB error in the sweep becomes an unhandled zone error. Separately, an `AsyncError` from `cycleAppWiringProvider` (line 93) is ignored, so a failed wiring leaves the cache never invalidated, with no signal. | FU: catch inside `onResume` (code-only, no payload) and retry the wiring on the next resume. |

---

## Fix list (blockers / majors only)

| # | Task | Lane | Finding | Fix |
|---|---|---|---|---|
| 1 | T-089 | A (app core) | Soft-deleting one leg leaves the other internal and excluded from totals forever (money silently missing; can't re-pair) | `onRemoved(txnId)` dissolving the pair + `_evaluate` self-heal when the partner isn't live; tests; FU for the delete wiring |
| 2 | T-089 | A (app core) | Manual unlink is undone by the next `onPersisted` (auto re-pair / one-sided re-mark) | Persist the unlink decision; exclude the pair from auto pairing and the one-sided rule; test |
| 3 | T-052 | A (app core) | Safe-to-spend computed from card-filtered totals, contrary to the Lead decision | Overview/safe-to-spend from unfiltered totals; filter only the displayed spend figures and the feed; test |

T-089 and T-052 are on the same lane but touch different files (`transfer_pairing.dart` / `home_read_model.dart`); they can run in parallel. Each fix is small; per policy the Lead can check the T-052 fix (about 10 lines plus a test) as a delta. T-089 needs a Sonnet delta re-review.
