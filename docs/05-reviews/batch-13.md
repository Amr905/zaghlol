# Batch 13 review (batch/2026-11-13-13)

Reviewer: one `code-reviewer` (Sonnet), code and security. Scope: production diff per task, AC to test maps, riskiest paths read. Ran `flutter test test/features/security test/features/export_import test/features/capture test/features/wealth test/features/notifications`: 256 passed in the first run (log tail "All tests passed"; the merged tree's 2019 tests were reported green by the Lead). Kotlin and Swift were NOT compiled here; the `ci/T-103` app-ci run was still in progress at review time (gate for T-103 native code).

## Verdicts

| Task | Verdict |
|---|---|
| T-103 App lock | APPROVED (pending green app-ci on ci/T-103) |
| T-154 CSV/Excel export | APPROVED |
| T-078 Ignore rules | APPROVED |
| T-115 ≈ combined view | APPROVED |
| T-094 Local notifications | APPROVED |

No blockers, no majors.

## T-103 App lock (C3, security) — APPROVED

Traced: `AppLockController`, `AppLockGate`, `device_security_providers.dart`, `DeviceSecurityHost.kt/.swift`, `MainActivity`, styles, `SceneDelegate`, `Info.plist`.

Checked and sound:
- Starts locked; unreadable setting counts as on; setting loading gives a blank cover; unreadable timeout locks at once; authenticator exception is `failed`. Only `AuthOutcome.success` unlocks.
- Bypass paths: content is `Offstage` (not painted, not hit-tested, not in semantics) plus `TickerMode` off; focus is dropped on lock; dialogs live in the same navigator so they are covered; deep links land after unlock (FU-125); Android back only pops hidden routes.
- Resume timing: larger of wall and monotonic elapsed; wall clock moved back locks; timeout 0 locks; `inactive` alone does not lock but the Dart cover blanks the switcher; lifecycle ignored while the OS prompt is up, and `_run` clears the background stamps afterwards.
- Android: `FlutterFragmentActivity` is the correct base for `local_auth`; `AppCompat.DayNight.NoActionBar` parent is right for BiometricPrompt on minSdk 26 (appcompat arrives with androidx.biometric); `FLAG_SECURE` is re-applied in `onCreate` before the first frame; recents screenshot off on API 33+.
- iOS: scene cover on `sceneWillResignActive`, removed on active, no-op unless enabled.
- No secrets stored, nothing logged, only booleans cross the channel.

Findings:
1. **minor / Low** `docs/04-tasks/tasks/T-103.md` (design note) and `app/lib/features/security/domain/app_lock_controller.dart:176` (`enable`): the Lead decision "turning app lock on sets `hide_amounts.notifications` to true (user can turn it off)" is not implemented anywhere (`Settings.hideAmountsNotifications` is never written outside settings_keys). `enable()` is the natural place, or T-104. Required: do it in T-104's lock toggle (note it in the T-104 task file) or add one write in `enable`. Not blocking T-103 because T-094's comment already says "T-103 turns it on", so someone must own it: **T-104 must own it.**
2. **minor / Low** `app/ios/Runner/Info.plist:82`: `NSFaceIDUsageDescription` is English only; no `InfoPlist.strings` for `ar`. Builder disclosed it. Follow-up (needs ar `InfoPlist.strings` plus Xcode project entry); not before merge.
3. **minor / Low** `DeviceSecurityHost.kt` / `SecureWindowState`: `FLAG_SECURE` is applied only after Dart reads the setting, so a cold start briefly has no secure window. Disclosed. Follow-up option: persist a native flag in a non-sensitive device-protected pref so `onCreate` can apply it at once.
4. **info** Disabling the lock needs no re-auth; acceptable because the app is already unlocked at that point.

Tests: AC to test map is complete and the gate test drives the real Pigeon class. Native tests unverified until CI. Goldens in ar/en for the lock screen exist as widget text/direction tests (acceptable for a C3 gate).

## T-154 CSV/Excel export (C2) — APPROVED

- Free: `GoldGate.exportPreviewOnly` returns `ExportPreview` before any bytes are encoded and before `destination.write`; test "Free gets preview only and nothing is written" covers it.
- Gold path needs the not-encrypted warning ack, writes only through the injected `ExportDestination`; no temp file or `dart:io` in the module. Initiated only by the caller.
- Amounts come from `Money.toCanonicalString()` (integer minor units, per-row currency, never converted); xlsx numeric cells only when plain decimal of at most 15 digits, else text.
- Formula guard covers `= + - @ TAB CR` on merchant and note.
- Zip writer: I checked the local header, central directory (disk/attr fields) and EOCD field by field against the spec; offsets, CRC32 and stored sizes are right, content types, rels and workbook are valid, so Excel/LibreOffice will open it. XML escaping strips illegal control characters.

Findings:
1. **minor** `export.dart` (`exportRow`): `id`, `account_id`, `category_id` are not run through `neutralizeFormula`. They are app-generated ids today; custom/imported ids could start with `=`/`@`. Cheap to apply to all non-amount cells.
2. **minor** `export.dart` `_load`: offset paging over a live DB can skip or duplicate a row if data changes mid-export; also the Free preview fetches a 500-row page for 20 rows. Follow-up.
3. **nit** the test named "xlsx is a valid zip" should unzip with a real reader (e.g. `package:archive` as dev dependency) rather than checking bytes; not required.

## T-078 Ignore rules (C3) — APPROVED

- Keep is the default; delete only through `DeleteExisting(confirmedIds)`, intersected with a fresh `_matching` query, so rows that arrived after the preview or no longer match are never deleted. Soft delete through `BulkEditUseCase` with one undo batch per chunk. Paired legs are found before the delete and each goes through `onRemoved`. Un-ignore leaves data untouched. Validation normalizes Arabic-Indic digits; errors are code-only.

Judgment on the builder's open item (crash between delete and `onRemoved`): `onRemoved` is idempotent, but the surviving leg keeps `is_internal = 1` with a dead pair and is excluded from totals, and nothing re-runs the cleanup (a retry skips already deleted ids). The window is small (process kill, not an exception), so **minor**, follow-up; but see 1.

Findings:
1. **minor** `ignore_rules.dart` (`add`, loop over `paired`): if `_onRemoved` throws for one id, the remaining paired legs are skipped and the `AddIgnoreResult` (including `undoBatchIds`) is lost even though rows were deleted. Required: catch per id, continue, and report the count of failed unlinks in the result. Plus a follow-up (`FU`, owner T-078 lane or transfers) for a startup sweep that runs `onRemoved` for soft-deleted legs that still have a pair.
2. **nit** `_pairedAmong` does one query per id (up to 1000 per chunk); one `IN` query would do.

## T-115 ≈ combined view (C3) — APPROVED

- `ApproxView` is a sealed type; off yields no figure and rates are not read (provider short-circuits too). The figure is `ApproxFigure`, not a storable `Money` type in any repository; nothing writes back.
- Missing rate goes to `excluded`, never guessed; zero totals neither converted nor listed. One half-even rounding per converted currency via `FxTable.convertApprox`, sums exact; oldest rate date and stale flag reported; `MoneyOverflow` propagates typed and documented. Provider family key has value equality.

Findings:
1. **minor** `approx_view.dart` `approximate` flag: false with a non-empty `excluded` list means a partial target-only sum with no "≈" label. UI (consumer task) must show the not-included note whenever `excluded` is non-empty; add that to the doc comment or set `approximate` true when anything was excluded.

## T-094 Local notifications (C2) — APPROVED

- Disabled type does nothing and does not mark fired; once-only dedupe through `markFired`; quiet hours delay via `schedule` at the quiet end (calendar-field based, wraps midnight, empty window means no quiet hours), never dropped; redacted title/body used when `hideAmounts`; payload is a route; no raw SMS path (text comes from the caller's l10n). l10n strings in both languages.

Findings:
1. **minor** `notification_service.dart:53-72`: `markFired` runs before `gateway.show/schedule`. If the gateway throws, the dedupe row is already written and that alert can never fire again (silently dropped). Required before the platform adapter lands: either un-mark on failure or document and test the failure path.
2. **minor** `notification_service.dart:64`: a notification scheduled during quiet hours carries the redaction decision made at schedule time; if the user turns app lock on before it fires, full text shows. Rare; note for the adapter (re-evaluate or cancel on lock enable).
3. **nit** Redaction relies on the caller giving amount-free redacted text; nothing enforces it. Acceptable by design, keep the callers' tests.

## Fix list (blockers and majors only)

| Task | Lane | Finding |
|---|---|---|
| (none) | | |

Follow-ups to record in `docs/implementation-status.md`: T-104 owns `hide_amounts.notifications = true` on lock enable (T-103 #1); ar `InfoPlist.strings` for Face ID (T-103 #2); native early secure-window flag (T-103 #3); per-id `onRemoved` isolation and a startup unlink sweep (T-078 #1); un-mark/handle gateway failure (T-094 #1); id-cell formula guard (T-154 #1). Gate: green app-ci on `ci/T-103` before merge.
