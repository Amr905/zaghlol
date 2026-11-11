# T-042 — Security and privacy review (Inbox reader for the historical scan)

| Field | Value |
|-------|-------|
| Reviewer | `security-privacy-reviewer` (Opus) |
| Date | 2026-11-11 |
| Branch / commit | `task/T-042-inbox` @ `f9c2d8c` (T-042 delta `4b14630..f9c2d8c`) |
| CI | app-ci 43032612836, sms-spike 43032676943 (green, per Lead brief) |
| Scope | `capture/inbox/{InboxReader,InboxCursor,InboxSource,AndroidInbox}.kt`, `AndroidCaptureHost.queryInbox`, `CaptureGuard.senderKind`, JVM + instrumented tests, `sms-spike-device.sh` inbox step, `platform-channels.md` §2 |
| **Verdict** | **APPROVED** (no Critical/High; M-1 is a PO decision that must be settled before T-048 ships the scan; L-1 is "before merge" of the wiring commit, not of this branch) |

## Summary

The reader does what Play's "SMS-based money management" exception and the "data never leaves the phone" promise need. The SQL selection is a constant template with `?` only. Sender addresses are allowlisted twice: the native Guard checks the requested addresses before they are bound, and each row read is checked again before its body is read. Every row then goes through the full Guard (OTP and promo drops, ignore rules). Error paths return codes only. There is no state between calls, no spool copy, no logging, no network path, and no manifest or permission change in the T-042 delta. The headless engine cannot read the inbox, because the reader is not wired into any host yet (fail closed). The main privacy risk is the open PO Q1 default (M-1), not the code.

## Checks

| Area | Result | Evidence |
|---|---|---|
| Data egress | Pass | No network, no new dependency. Pages go only over the in-process Pigeon channel to Dart (`AndroidCaptureHost.kt:81`). |
| Sender filter in SQL | Pass | `InboxReader.kt:309-314` builds `address IN (?,…) AND date > ? AND _id > ?` from constants. Bound values come only from `allowlisted()` (`:321-328`, Guard `senderKind`). URI is `Telephony.Sms.Inbox.CONTENT_URI` (`AndroidInbox.kt:17`), so sent messages and drafts are never read. |
| Guard on every row | Pass | `InboxReader.kt:257` re-checks the bound set and `senderKind` before `getString(body)` (`:260`). `:261` runs the full `decide` without the rate limiter, and only `Keep` is returned (`:263`). Test: `aProviderIgnoringTheSelection…` (negative proof listed). |
| Sender hints not an allowlist | Pass | `CaptureGuard.kt:42-56` leaves out `senderHints`. Test: `alwaysCaptureUserAndRegexSendersAreReadButHintsAreNot`. |
| SQL injection | Pass | No input reaches the selection or sort text (`SORT_ORDER` is constant, `:304`). Sender strings and the cursor only become bound args (`:228-233`). `selection()` `require`s 1..898. |
| Cursor token | Pass (see I-2) | `InboxCursor.kt:90` has a strict regex, ≤ 64 chars, bounded digit counts, and `toLongOrNull`. It holds a chunk index, the last `_id` and a CRC32. It carries no sender or body text. A tampered token can only move the `_id` floor or the chunk inside the same Guard-filtered query. It cannot add senders, because the sender set comes from the request, which is re-filtered on every call. A changed Guard config or sender set changes the CRC, so the call returns `INVALID_ARGUMENT`. |
| Logs / exceptions / toString | Pass | No `Log`/`println` in `capture/inbox` (app-ci grep plus local grep). `InboxReader.query` (`:168-176`) and `guarded` (`AndroidCaptureHost.kt:167-173`) rethrow `CaptureApiError(code, null, null)`, so Pigeon `wrapError` never takes the `toString`/stack-trace branch (`CaptureApi.g.kt:33-37`). `InboxReader.toString`, `Position.toString` and `GuardConfig.toString` hold no data. Canary covered by JVM `theCanaryNeverReachesErrorsCursorsOrStandardStreams` plus the device logcat scan (0 hits on API 30/34/36), with a non-vacuous uid filter. |
| Resource bounds | Pass | ≤ 1,000 addresses (`:181`). `pageSize` clamped to 1..500 rows **read** (`:195`), so the Guard drop rate doesn't change the cost. ≤ 898 variants per query, so ≤ 4 chunks. A no-progress provider gets `IO_ERROR` (`:208`). `since` floored at now − 25 months (`:194`, `:317`). Cursors are closed on every path (`use {}`, test `cursorsAreClosedOnEveryPath`). Cursor tokens have no lifetime problem because no native state is held. |
| Memory exposure | Accept (I-3) | At most 500 bodies of ≤ 4,000 chars (≈ 4 MB UTF-16) per call. Handed to Dart directly with no plaintext spool copy. AC2 10k × 4,000 chars passes in constant heap (JVM and device). |
| Headless engine | Pass now, L-1 for the wiring | The `inbox` param defaults to null and `need(inbox)` returns `NOT_AVAILABLE` (`AndroidCaptureHost.kt:42-43, 81`). Test: `theHeadlessHostHasNoReaderAndAnswersNotAvailable`. |
| Permission | Pass | `*NoSms` returns `NOT_AVAILABLE` before the provider is touched (`:179`). Not granted returns `PERMISSION_DENIED` (`:182`). `SecurityException` maps to `PERMISSION_DENIED` (`:172`). A revoke mid-scan: Android kills the process on a runtime-permission revoke. A revoke between calls returns `PERMISSION_DENIED`. An exception mid-iteration throws away the partial page (`items` never returned). Device test `revokedPermissionIsPermissionDenied` after `pm revoke`. |
| Manifest / permissions | Pass | No manifest or permission change in the T-042 delta. `READ_SMS` was already declared in the `*Sms` flavours (T-008/T-039). |
| Test fixtures | Pass | All SMS are synthetic (`SYNTH SHOP`, `5550100`/`5550199`, canary `ZG_CANARY_7731`). |
| Play policy fit | Pass for registry/alwaysCapture senders; see M-1 for user-added numbers | |

## Findings

### M-1 (Medium) — PO Q1 default: a user-added phone-number sender has its whole SMS history read and kept

**Where:** `CaptureGuard.kt:49` (`senderKind` returns `USER`) and `CaptureGuard.kt:76`/`decideUnsafe`. For `inst == null`, a `USER` keep only goes through `globalDrop` (OTP and promo). It never goes through a financial body check. `InboxReader.kt:257-263` then returns every such row.

**Leak path (on-device, no egress):** The user adds a mobile number as a custom sender, for example a cooperative treasurer, a *gam'eya* organiser or a shopkeeper who is also a relative. T-048's first-run scan passes that number. The reader returns **every** SMS from it in the last 25 months, personal ones included. Each one is a `user` keep. At ingest the unparsable ones become `unrecognized` raw messages in the review queue (`ingest_rules.dart:51`). Private conversations end up in the encrypted DB and are shown back in the app's review UI. They are also included in encrypted backups (Gold), so they leave the phone to the user's own Drive/iCloud. The Guard's live path has the same behaviour for new messages, but the inbox scan multiplies it by up to 25 months of history in one step, and the user is not told this.

**Policy angle:** Play allows `READ_SMS` <a href="https://support.google.com/googleplay/android-developer/answer/10208820?hl=en">only for the app's critical core functionality</a>, and its example for budgeting apps is that they <a href="https://support.google.com/googleplay/android-developer/answer/10208820?hl=en">may not exfiltrate or share non-financial or personal SMS history</a>. Zaghlol does not exfiltrate these messages. Even so, keeping and showing a contact's personal history weakens the "only financial SMS" story in the Play declaration form and in review.

**Required change (decision for the PO; enforce in T-048 / Guard before the first-run scan ships, not on this branch):** pick one, in order of preference.
1. **Financial body gate for numeric user senders on the inbox path:** an inbox row from a `USER`-kind sender that looks like a phone number (folded key matches a mobile/landline shape, for example `^\+?\d{8,15}$`) is kept only if `bodyHints` (amount + currency / card / transfer tokens) match. Anything else is dropped natively and never returned. Alphanumeric user senders (`MyCoop`) are kept as they are today.
2. Otherwise, **live capture only** for numeric user senders (the reader leaves them out of `allowlisted()`), with an optional "scan this number's past messages" action that shows its own disclosure.
3. In every case: when a phone number is added as a custom sender, show an in-flow disclosure ("Zaghlol will read messages from this number, past and future, to find transactions") with explicit consent. Use a shorter look-back for numeric senders (for example 3 months instead of 25). Unparsed inbox rows from numeric user senders are not kept in the review queue.

Keep the provisional constant until the PO decides. Track it as a follow-up owned by T-048, plus the Guard owner if option 1 is chosen.

### L-1 (Low, **before merge of the wiring commit**) — headless exclusion depends on a wiring line that is not on this branch

**Where:** the implementation notes ("Wiring") and `AndroidInbox.kt:58`. Whichever of T-041/T-042 merges second adds `inbox = if (headless) null else InboxReaders.forUiEngine(context)` in `CaptureRuntime.newHost`. `InboxReaders.forUiEngine` is a public object function, so nothing in the type system stops the headless host from getting a reader.

**Leak path:** a careless merge (for example passing `forUiEngine(context)` without the conditional) would let the background engine (WorkManager worker or receiver-triggered headless Dart) read the inbox with no user present. That is not allowed by FU-088 and by the consented-scan rule.

**Required change:** the wiring commit must include a JVM test at the composition point: `CaptureRuntime.newHost(headless = true).queryInbox(...)` → `NOT_AVAILABLE`, and the UI host → a reader. Today's `InboxHostTest` only checks the default parameter. The Lead checks for this test in the delta of the merge that wires the reader.

### L-2 (Low, follow-up for T-036) — registry sender regexes are unanchored, so a broad pattern would allowlist personal numbers for a full-history read

**Where:** `CaptureGuard.kt:119`: `cfg.senderRegexes.firstOrNull { it.first.containsMatchIn(sourceKey) }`. `senderKind` returns `REGISTRY` for any address that a registry regex matches **anywhere**.

**Leak path:** Dart passes regex-matched senders taken from `raw_messages.source` (design §2). Suppose a registry rule such as `\d{4,5}` (short codes) or `^0?1[0125]` is added. Every 11-digit mobile number contains such a match. One stray capture from a personal number would then make that number "registry" in both the live Guard and the inbox reader. The reader would return its 25-month history, minus OTP and promo, under a bank institution code. There is no such rule today, because no production registry has been seeded yet.

**Required change (T-036 registry lint):** sender regexes must be anchored (`^…$`). The lint should reject any sender regex that matches a synthetic Egyptian mobile (`01[0125]XXXXXXXX`, `+201…`) or a generic `+` E.164 number. Add a Guard golden case for this.

### I-1 (Info) — a provider that ignores the selection still brings personal rows into the process

`InboxReader.kt:233-260`. If an OEM provider ignores `address IN`, the cross-process `CursorWindow` (≈ 2 MB) holds every row's projected columns, **bodies included**. The reader never turns those bodies into Strings and never returns them; the `address` check runs first (`:257`). The design's claim that rows are "never materialised" is true only for conforming providers. This is acceptable: the data stays in the app process and the window is released at `close()`. A narrower projection (`_id, address, date, sub_id` first, then a body fetch by `_id` for kept rows) would close this gap, but it doubles the number of queries. Not required.

### I-2 (Info) — the cursor can carry the `_id` of a non-allowlisted message

`InboxReader.kt:254` updates `maxId` before the address check (`:257`). On a provider that ignores the selection, `nextCursor` (and so Dart) can hold the integer `_id` of a personal SMS. It reveals no content, sender or time, and Dart cannot use it to read anything outside the allowlist. No change needed. Optionally, update `maxId` only after the address check, together with the no-progress guard.

### I-3 (Info) — plaintext bodies in memory

Up to about 4 MB of immutable `String` bodies per page, plus the Pigeon `ByteBuffer` and Dart copies. They cannot be zeroed and are reclaimed by GC. This is the same exposure as live capture and stays in the same process. The direct handoff, with no spool, avoids a second persisted copy, which is the right trade-off. Accept.

### I-4 (Info) — `catch (Throwable)` maps `OutOfMemoryError` to `IO_ERROR`

`InboxReader.kt:174` and `AndroidCaptureHost.kt:171`. A fatal error is reported as a normal error code instead of crashing. That is consistent with the host's existing pattern, and it is privacy-safe because no message text is carried. No change needed.

## Verdict

**APPROVED.** No Critical, High or before-merge finding affects this branch. M-1 must be settled by the PO and enforced before T-048 enables the first-run scan for user-added numeric senders. L-1 is before merge of the commit that wires `InboxReaders.forUiEngine` into `CaptureRuntime`. L-2 and I-1…I-4 are follow-ups.
