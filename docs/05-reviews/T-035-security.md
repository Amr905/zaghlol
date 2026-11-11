# T-035 Security and privacy review

| Field | Value |
|-------|-------|
| Task | T-035 Capture Guard rules in Dart, shared golden cases, config generator (C4, SMS ingestion) |
| Branch / commit | `task/T-035-capture-guard` @ `e76e682` (diff base `origin/task/T-035-design-note`) |
| Reviewer | security-privacy-reviewer (Opus), 2026-11-11 |
| Verdict | **CHANGES_REQUESTED** (M-1 and M-2, before merge) |

## Scope and method

I read the whole `lib/guard/` package, `portable_regex.dart`, `regex_safety.dart`, the schema, loader and lint changes, `guard_export.dart`, the synthetic registry and configs under `test/fixtures/guard/`, `golden.json`, and the doc changes (platform-channels §1.1/§1.2/§2/§3, parsing-engine, ADR-005 *Threats*). I ran `dart test test/guard test/registry` (all pass). I also ran a separate probe outside the repo: `CaptureGuard.load(t1_base.json, t1_user.json)` over 20 handwritten synthetic bodies. The results quoted below come from that run.

## Findings

### M-1 Medium, before merge: common OTP shapes are kept, so OTP codes get stored (BR-ING-03, EC-07, FU-082)

**Where.** The global drop patterns in `packages/zaghlol_parsing/test/fixtures/guard/registry/shared.json` lines 5-8 set the shape that T-036 will copy into the real registry. `golden.json` line 818 (`residual.otp_code_after_amount_kept`) pins the gap as **keep**, and T-038/T-061 will port that as their contract.

**Probe.** Every body below is from a registry sender (`NBE`, `sms`) and came back `GuardKeep(registry)`:

| Body (synthetic) | Gap |
|---|---|
| `Your OTP for EGP 1,500.00 purchase at SHOP X is 482913` | an amount sits between the keyword and the code (a common bank format) |
| `رمز التحقق لعملية بقيمة 500 جم هو 482913` | the same in Arabic |
| `كود 482913 لتأكيد عملية الشراء` / `InstaPay code 482913` / `Your code is 482913` | bare `كود` / `code` |
| `Your PIN is 4829`, `Your password is 482913`, `one time pin 482913` | keyword not in the list |
| `Your 3D Secure code is 482913` | keyword not in the list |
| `OTP: 48 29 13`, `Do not share. OTP: 482-913` | code split into groups |
| `0TP 482913`, `O T P 482913` | obfuscated keyword (low priority) |

**Leak path.** The native Guard keeps the message, so it is spooled under K_spool. At drain, pipeline stage 0 runs the same patterns and keeps it too. From there, one of two things happens:
- A card-purchase template matches the amount and merchant, so a phantom debit is auto-saved for a purchase that was only being authorised. The real transaction SMS that follows is counted a second time.
- The message lands in review as unrecognised, with the full body.

Either way, a live one-time code, together with the amount, merchant and sometimes the card last-4, is stored in the DB and its FTS index. It also ends up in every Drive/iCloud backup taken afterwards, and anyone holding the unlocked app can read it. BR-ING-03 says OTP messages from bank senders are "ignored and not stored". The design note's Q2 ("OTP + transaction → dropped") also contradicts the residual: the same message is dropped when the amount comes after the code and kept when it comes before.

**Required change.**
1. Widen the keyword-first gap so it also accepts amount-shaped tokens, without lookaround and inside the portable subset. Accepted tokens: decimal amounts `[0-9][0-9,]*[.,][0-9]{1,2}`, numbers of at most 3 digits, card masks `\*\*[0-9]{4}`, `x+[0-9]{4}`. Use a small bounded repeat (`{0,3}`, which the backtracking heuristic allows) around the token plus a non-digit run. The terminal code check (`[0-9]{4,8}` not followed by `[.,][0-9]`) stays as is.
2. Add a keyword set for `code`/`كود` combined with a confirm verb (`to confirm|لتاكيد|للتاكيد`). Add `pin`, `one time pin`, `3d secure` and `كلمه المرور`. Add split codes after a keyword (`[0-9]{2,4}[ -][0-9]{2,4}`, capped at 8 digits in total).
3. Flip `residual.otp_code_after_amount_kept` to drop. Add golden cases for each row above, in EN and AR, plus a negative case for each new keyword (for example a purchase that mentions "PIN-protected").
4. If the PO prefers to keep a residual, record it under Q2. The pipeline (T-033/T-073) must then never auto-save a body that contains an OTP keyword: such a body is always forced to review, and the review item shows no body. The ADR-005 *Threats* section must name the residual.

This is before merge because `golden.json` is the single cross-platform contract. Fixing it after T-038/T-061 port it means three re-syncs.

### M-2 Medium, before merge: a security footer followed by a hotline drops real transactions (fail-closed and unrecoverable)

**Where.** The first and third global patterns in `shared.json` lines 5 and 7: `keyword(?:[^a-z0-9][^0-9]{0,30})?[0-9]{4,8}`. The gap may contain letters and sentence punctuation.

**Probe.** Both bodies below are from `NBE`/`sms` and came back `GuardDrop(otp_or_promo_global)`:
- `Purchase EGP 450.00 card **2468. Never share your OTP with anyone. Call 19623`
- `تم خصم 450.00 جم من بطاقة **2468. لا تشارك رمز التحقق مع أحد. للاستفسار 19623`

Egyptian banks use 5-digit hotlines (19xxx) and often put them right after a "don't share your OTP" footer. The design note's claim that such footers do not drop a real transaction holds only when no 4-8 digit number follows within 31 characters. This is not a confidentiality leak. It is an integrity and availability failure with no recovery: the Android catch-up scan re-runs the same Guard and drops the message again, notifications are lost, and the user never sees the transaction. The existing negative case `neg.otp_footer_on_purchase` only passes because nothing follows the footer.

**Required change.** The keyword-first gap must not cross a sentence boundary. Exclude `. ! ? ؟ ؛` and newline (already folded to a space, so in practice `.`, `!`, `?`, `؟`) from the gap class, for example `[^0-9.!?؟]{0,30}`. Then check that `Your OTP is: 482913` and `OTP 482913. Do not share` still drop. Add the two bodies above as `negative` golden cases. M-1's widened gap must keep the same rule.

### L-1 Low, follow-up (owners T-038, T-061; doc fix now): the user-part file paths contradict the OS-backup exclusion

`docs/03-technical/platform-channels.md` line 45 has two problems:
- **Android.** It says `files/guard/guard.user.enc (Android, noBackupFilesDir)`. `files/` is `filesDir`, not `noBackupFilesDir` (`no_backup/`). The manifest exclusions (security-model §6, `allowBackup=false` plus `dataExtractionRules`) cover it today, but the spec contradicts itself.
- **iOS.** The doc puts the file at `guard/guard.user.enc` in the App Group root. That directory is **not** in the security-model exclusion list (`docs/03-technical/security-model.md` line 155 excludes App Group `spool/`, `Library/Application Support` and `Caches` only). The file would go into iCloud and Finder backups. Its content is AES-GCM under a `ThisDeviceOnly` key, so it can't be decrypted elsewhere. Even so, this breaks CLAUDE.md §2.2 ("app data excluded from OS backups"), and the file's presence and size reveal roughly how many ignore rules the user has.

**Required change.** Use `noBackupFilesDir/guard/` and App Group `Library/Application Support/guard/` (the original §1.1 location), or add `guard/` to the iOS exclusion list. T-038/T-061 add a test asserting the exclusion.

### L-2 Low, follow-up (owners T-038, T-047, T-061): the plaintext `writeGuardConfig` is still named and described as encrypted

The contract change itself is sound. Dart can't use the non-exportable K_spool, the user part is data the app already holds decrypted in its DB, and nothing in `lib/guard/` writes to disk or prefs (it has no `dart:io`, enforced by the source scan). The naming is the risk:
- `app/pigeons/capture_api.dart:123` and `app/lib/core/platform/capture_api.g.dart:563` still call the parameter `encryptedConfig`.
- `docs/04-tasks/tasks/T-047.md` line 22 still says "Write encrypted guard config".

**How it goes wrong.** A T-038/T-061 implementer reads `encryptedConfig` and persists the bytes as-is. Institution + last-4 pairs and user sender IDs then sit in plaintext under `files/`. Alternatively, a T-047 implementer "encrypts" in Dart with an improvised key, or keeps the built bytes in a provider or prefs for re-sending.

**Required change.** Rename the Pigeon parameter now (a regenerate) or add explicit acceptance criteria:
- T-038/T-061: "the file on disk is AES-GCM ciphertext; a test reads the file and asserts no last-4 or sender value appears in it; the input buffer is zeroed".
- T-047: "the user part is built on demand from the DB, passed to `writeGuardConfig` and dropped; never written to disk, prefs, logs or a long-lived provider".

Correct T-047 line 22.

### L-3 Low, follow-up (owners T-038, T-039; ADR-005 wording now): the rate limit is a weak DoS bound, and ADR-005 overstates it

`SenderRateLimiter` (`lib/guard/sender_rate_limiter.dart` lines 214-267) has three limits:
- It counts per `(channel, sender)` only.
- It forgets the least recently used key beyond 64.
- It lives in memory, so Android loses it whenever the receiver process is cold-started between SMS.

An attacker can rotate alphanumeric IDs that match `senderHints` plus `bodyHints` (`xbank1`, `xbank2`, ... with "EGP 1"), or keep spoofing one registry ID across process restarts. Either way they reach the spool caps (500 entries / 4 MiB, new messages refused). Real bank SMS are then refused until the next drain: SMS come back through the catch-up scan, notifications are lost. ADR-005 *Threats* says the rate limit and spool caps "bound disk use", which is true. They do not protect the capture of real messages.

**Required change.**
1. Reword ADR-005 to say the rate limit is best-effort per process and the spool cap is the hard bound.
2. Add a global cap on **generic**-kind keeps per minute (hint-matched senders are the cheap spoofing route), so a flood can't fill the spool with generic items.
3. Confirm `SPOOL_FULL` triggers the catch-up scan (FU-084b) and shows the user a degraded-capture state.

### Info

- **I-1 Spoofing stance (FU-084).** Acceptable as documented in ADR-005 *Threats*. Confusables are deliberately not folded (golden `nf.confusable_sender_greek_epsilon`), so folding never widens the allowlist. A further residual worth one line in *Threats*: a spoofed registry-sender message can introduce a new card last-4 or account into the user's ledger. User senders on `notification` accept any package (for example a messenger). T-047's picker should limit choices to packages that have posted a money-looking notification, or warn the user.
- **I-2 Plaintext in Dart memory.** `buildGuardUserConfig` builds a Dart `String` (`JsonEncoder`) and a `List<int>`, and neither can be zeroed. This is the same data the app already holds in decrypted DB pages, so I accept it. Native zeroing of its own copy is worth doing but is only best effort.
- **I-3 No rollback protection on `guard.user.enc`.** The AAD `zaghlol.guard.v1|user` is static, so an attacker with the same UID or root could replace the file with an older ciphertext from before an ignore rule existed. The drain-time Dart re-check (T-046), which rebuilds from the DB, catches this. Optionally, T-038 could put a generation counter in the AAD.
- **I-4 Last-4 parity with several cards.** The Guard takes the first mask hit (`capture_guard.dart` lines 164-183), but a template may attribute a different card. A card ignore rule can therefore miss, or hit the other card, in multi-card bodies (pinned by `card.two_cards_*`). The drain re-check uses the same logic. This is a documented behaviour, not a leak. If users report it, consider "any found last-4 matches an ignore rule → drop".
- **I-5 Shared text skips the Guard on both platforms** (platform-channels §3 now matches §2.1). This is fine because sharing is user-initiated and always confirmed (FR-ING-A-04). Suggestion for T-073: when shared text matches an OTP drop pattern, show a hint before saving instead of storing it silently.
- **I-6 Q1 `keepWithBase`.** While the user part is unreadable, messages for ignored institutions or cards are spooled under K_spool and dropped at drain. That is acceptable only because T-046's re-check is mandatory. Keep it as an acceptance criterion there.

## Verified, no finding

- **No raw text in logs or errors.** `lib/guard/` has no `print`, `log`, `dart:io` or `dart:developer` (my grep matches the in-test source scan). `GuardKeep`/`GuardDrop`/input `toString` print the kind or reason only. `GuardConfigError` carries a code and a fixed path; unknown keys are not echoed. The canary test (`ZG_CANARY_7731` plus last-4 under a `print`-capturing zone) passes. The lint's `guardLast4Mismatch` reports the path and field only.
- **Fail-closed choices.** `config_invalid` is checked first. An unknown channel drops. Any exception in `decide` drops (`capture_guard.dart` lines 37-42). Body over 4,000 and source over 256 UTF-16 units are rejected before any regex. Readers are strict, with byte, list, string and pattern caps checked before decoding or compiling. Q1 never turns a bad user part into `invalid`, and the fuzz tests cover this.
- **ReDoS.** Every Guard-bound pattern (sender regexes, drop, last-4, hints) goes through `backtrackingProblems` plus the portable lint plus the runtime probe, now including `*`/`x` mask runs. That probe caught the quadratic `\*{2,}` pattern. Patterns ship only with the app (D-17, no OTA templates), and user input never becomes a Guard regex: user senders are exact folded values. The global OTP patterns use only bounded gaps. Natives measure ICU timing in T-038/T-061.
- **EC-59.** Ignore keys always carry `inst`. The schema and reader reject a rule without `inst`, and a property test covers random rule sets.
- **Fixtures are synthetic.** They use `com.example.*` packages, `SHOP A`…`G` merchants, an obviously fake `+201000000001`, a `"synthetic": true` flag and invented last-4 values. Bank sender IDs and names are public registry data. I found no copied reference formats.
- **The OS-backup exclusion of the Android file holds today** through the manifest rules (see L-1 for the spec fix).

## Summary

| ID | Severity | Before merge | Owner |
|----|----------|--------------|-------|
| M-1 | Medium | **yes** | T-035 (patterns + golden), T-036 copies |
| M-2 | Medium | **yes** | T-035 (patterns + golden), T-036 copies |
| L-1 | Low | no (doc fix suggested now) | T-038, T-061 |
| L-2 | Low | no | T-038, T-047, T-061 |
| L-3 | Low | no | T-038, T-039, ADR-005 |
| I-1…I-6 | Info | no | as noted |

Re-review scope after the fix: the delta to `shared.json` (all three test registries), `golden.json`, and a rerun of the probe bodies above. M-1 and M-2 touch only data and golden cases, so this is likely a Lead delta check under the review-round policy if the change stays small and the new golden cases fail without it.
