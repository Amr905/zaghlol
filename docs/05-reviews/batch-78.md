# Batch review — batch 78 (`batch/2026-11-26-78`)

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + money/security for the C4 task) |
| Date | 2026-11-26 |
| Diff | `git diff origin/main...8ddb4af2` (main = c7335880), 83 files |
| Tasks | T-272 (C4), T-273 (C3 native), T-274 (C2), T-275 (C3), T-276 (C3), T-277 (C2 copy) |

## Checks run (merged tree 8ddb4af2)

| Check | Result |
|-------|--------|
| `flutter pub get --enforce-lockfile` | OK |
| `flutter analyze` (app) | No issues |
| `dart analyze --fatal-infos` + `dart test` (zaghlol_domain) | clean, 544 passed |
| `flutter test -x golden` home, budget, transfers, transactions, ingestion, test/ingestion | 914 passed |
| `flutter test -x golden` voice, mascot, app, core/l10n, core/settings, insights, ask | 753 passed |
| `zaghlol_lints` | 650 files, 0 issues |
| `dart format --set-exit-if-changed` (app/lib, app/test, zaghlol_domain) | 0 changed |
| `tools/mascot_riv/generate.py` run twice | byte-identical to each other and to the committed `app/assets/rive/zaghlol.riv` (390006 bytes) |
| Kotlin (`OcrMerger.kt`, `OcrMergerTest.kt`) | not compiled locally; read for compile errors, none found |

Follow-ups start at FU-364.

---

## T-272 — Exchanged money counted once (C4, financial math) — **APPROVED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| PO story: USD income 1,000; exchange 600 → 29,700 EGP; EGP money in 29,700; USD exchanged out 600, left 400; categories unchanged; nothing twice | PASS | `exchange_totals_test.dart` (USD/EGP story, category, reconcile, KWD/JPY exponents) |
| Ingest of a synthetic `fx_conversion` fixture | PASS | `ingest_raw_messages_test.dart` (two legs + pair, same message twice, Arabic-Indic digits, zero received → review); `reparse_test.dart` |
| Suggestion: offer once, accept, decline | PASS | `transfer_pairing_test.dart` "cross-bank, no rate known: ONE suggestion; decline is remembered", "accept (link) …", "known rate far off (>15%) …" |
| Manual exchange (Add sheet + use case) | PASS | `transfer_pairing_test.dart` recordExchange ×3, `exchange_entry_screen_test.dart` |
| Balance-rise question | PASS | `exchange_jump_test.dart` (asks once, no foreign income, older than lookback, explained rise, under 500) |
| Cached closed month overlay | PASS | `cycle_repository_exchange_test.dart` |
| Negative proofs (≤ 3) | PASS | "an exchange is never income and never spending"; unpaired legs stay ordinary |
| Existing transfer, budget, chart tests green | PASS | runs above |

### Money / security part
- **No double count in the main paths.** An exchange leg counts only when it is internal, live, posted/pending and in a complete `fx_conversion`/`cross_currency` pair (`isExchangeLeg`, `_isExchangeSql`). Internal rows were already excluded from income, spend, categories, charts, Ask, payday/salary detection and cash cover; those queries are unchanged, so an exchange can't reach them. Home "left" = money in − spend − exchanged out; budget, safe-to-spend and the budget bar unchanged (A1). Mascot "saved more" backs out the exchange (`home_mascot.dart`). Linked cards: the balance-jump ledger uses the T-266 root + linked cards.
- **Integer money.** `impliedRateE9`, `unexplainedBalanceRise`, `balanceJumpMinMinor` use int/BigInt; exponents handled on both sides (KWD 3, JPY 0 tested); `formatRateE9` integer; the entry screen parses text into minor units and prefills via `_plain` (no `double`).
- **Ingest.** Two legs + pair in the message's savepoint; `insertExchangePair` requires both legs live and unpaired (throws otherwise → rollback). Missing/same-currency/zero amount → `unrecognized`, nothing stored. User-confirmed input with a cross-channel match returns `IngestPossibleDuplicate`.
- **Re-parse** is idempotent: old `reparse_pending` conversions created no legs, the raw row is promoted conditionally (`_insertRaw` → `promoteRaw` from the start state), and a later re-parse of a `parsed` exchange row has `create == null` → stamp only.
- **Balance-rise question** creates only a review item; Yes opens the prefilled entry, nothing is saved without the user's Save; No dismisses, and the next balance compares with the newly recorded one, so the same jump is never asked again. Out-of-order (older) balances are skipped (`prevAt >= asOfMs`).
- No raw SMS bodies or amounts logged; no new network calls; `BalanceJumpFacts.toString` redacted.
- SRS edits (FR-PAR-12, FR-HOME-01, FR-CUR-06, A-61) and `domain-algorithms.md` / `parsing-engine.md` match the code and D-86 (Q1/Q4).

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | minor | `app/lib/features/ingestion/application/ingest_raw_messages.dart:1379` | A possible cross-channel duplicate of a conversion is stored as a second full pair (never merged), so exchanged in/out are doubled until the user acts; the review item points only at the out leg, and deleting it frees the in leg into ordinary EGP income (onRemoved heal). Today only notification templates (Wise/Revolut) exist, so this is unlikely. | FU-364: when the user resolves a `possibleDuplicate` on an exchange leg, delete or keep both legs together; or merge when both legs match. |
| 2 | minor | `app/lib/features/transactions/application/transfer_pairing.dart` (onRemoved heal) / `exchange_entry_screen.dart` | Deleting one leg of an exchange (two rows in the list) frees the other leg, which then counts as income (in leg) or spending (out leg) until it is deleted too. This matches the existing transfer behaviour, but an exchange is now one user action. | FU-365 (T-273 exchange row): delete/undo an exchange as one unit. |
| 3 | minor | `packages/zaghlol_domain/lib/transfers/exchange_hints.dart:12`, `ingest_raw_messages.dart:1914` | 500 major units for every currency (≈ USD 10 in EGP, < USD 4 in JPY/KRW). Any missed incoming credit ≥ EGP 500 asks "did you exchange money?" while a USD salary is within 45 days. The check also runs during the inbox catch-up scan, so old jumps can raise several items at first run. | FU-366: a per-currency threshold (or a share of the foreign income at a known rate), and skip or cap items from `inboxScan` older than N days. |
| 4 | minor | `app/lib/features/insights/domain/chart_summary.dart:79`, `app/lib/features/ask/domain/ask_models.dart:188` | Home "left" now includes exchanges; Insights "saved" and Ask "net" stay income − spend, so the same month shows different "left/saved" on different screens. Deferred by the plan (WP-6), but not written down as a known gap. | FU-367 (T-273/WP-6): show exchanged in/out on Insights/Ask, or label the difference. |
| 5 | minor | `app/lib/core/l10n/app_ar.arb:6100` (`homeQuickAddExchange` «حولت فلوس»), Home «وحولت {amount}» | In Egyptian usage «حولت فلوس» usually means "I transferred money" (InstaPay), not "I exchanged currency"; the hint helps, the KPI note does not have one. | FU-368: PO copy check, e.g. «غيّرت عملة» / «صرّفت دولار». |
| 6 | nit | `app/lib/features/budget/data/cycle_repository.dart:76` | `cachedTotals` (cold-start figures) has no exchange overlay, so money in/left can change when the live totals arrive. | FU-369 or accept (documented in the doc comment). |
| 7 | nit | `app/lib/features/transfers/presentation/exchange_entry_screen.dart:164` | A past date uses today's UTC offset (DST shift moves noon by an hour; never changes the day). | With FU-365. |
| 8 | nit | `app/lib/core/l10n/app_ar.arb:1530` | «السعر: ١ {from}»: hard-coded Arabic-Indic "١" ignores the Western-digits setting in Arabic. | Pass the 1 as a placeholder rendered by `digits.render`. |

Not verified: statement import of a USD statement line for a manually recorded exchange (manual leg is `transfer_out`, internal; a statement debit line may not dedupe against it). No change in this batch; FU-370 to check.

---

## T-273 — OcrMerger: credible Arabic only (C3 native) — **CHANGES_REQUESTED**

### Acceptance criteria → tests
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Latin receipt keeps `Amount Due 436.00`, `Net Sales 382.46`, `VAT 53.54`, `Visa 436.00`; fails on old merger | PASS (by reading) | `latinReceiptKeepsTheMlKitLines` |
| Mixed line keeps both parts, no Arabic digits | PASS (by reading) | `mixedLineKeepsLatinAndAppendsCredibleArabicWordsWithoutArabicDigits` |
| Real Arabic receipt unchanged | **Only for 1-letter ML Kit garbage** | `arabicReceiptIsUnchangedAndDigitsComeFromMlKit` uses `"Jl 85.50"`; the old fixture `"Jlaa Jlj"` was changed to `"Jl J"` |
| ADR-009 updated; iOS unaffected | PASS | ADR-009 T-273 note; `OcrHost.swift` Vision only |
| Kotlin compiles | not checked locally | read: no compile errors found (`String.trim(vararg Char)`, `let { if … }` returning Unit, `sumOf` on Int are valid) |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | **major** | `app/android/app/src/main/kotlin/app/zaghlol/platform/ocr/OcrMerger.kt:98` (`strongLatin`), `:112` (`arabicWords`), `:29`/`:38` (0.60 gate) | Real Arabic receipts can lose their Arabic lines and amounts. (a) `strongLatin` counts any Latin run of 2+ letters, so ML Kit's usual garbage on Arabic script (e.g. `Jlaa Jlj`, the old fixture, which the builder had to shorten to `Jl J` to keep the test green) is "strong". A credible Arabic line that overlaps it no longer replaces it: the garbage stays and the Arabic line adds only digit-free words. With Arabic-Indic digits (`الإجمالي ٨٥٫٥٠`), which ML Kit Latin cannot read, the amount is lost. The old merger kept it. (b) The 0.60 gate drops every Arabic-majority line below it, with or without overlap. The bar comes from one photo (noise up to 0.56, the one real line 0.67), so a real Arabic merchant or total line at 0.45 to 0.59 disappears. | Apply the 0.60 bar only where the noise actually happens, i.e. a Tesseract line that overlaps a **strong** ML Kit line (Latin text that ML Kit read). Keep Arabic-majority lines at ≥ 0.45 (or similar) when they have no ML Kit overlap or overlap only weak lines. When a credible Arabic line overlaps a strong ML Kit line that has **no ASCII digit token** and the Arabic line has digits, keep the Arabic digit tokens. Tighten `strongLatin` (e.g. each counted word needs a vowel, or use ML Kit confidence when it is > 0). Add tests: `Jlaa Jlj`-style garbage over `الإجمالي ٨٥٫٥٠` keeps ٨٥٫٥٠; an Arabic merchant line at 0.50 with no overlap is kept; the PO receipt test stays green. |
| 2 | nit | `OcrMerger.kt` `mergeBoth` | One Arabic line that overlaps both a strong and a weak ML Kit line is kept in full **and** the strong line is kept, so the shared text can appear twice. | FU-371. |

Note: the receipt reader shows OCR results for confirmation before saving, so nothing is saved wrong without the user seeing it. That is why this is major, not blocker. If the Lead holds this to the sprint rule (fix rounds only for money/data majors), it counts: it drops amounts from receipts.

---

## T-274 — Mascot cuff tab, Home avatar 92 (C2) — **APPROVED**

| Criterion | Result | Evidence |
|-----------|--------|----------|
| Root cause with file names | PASS | task file (rig `wing` group carries the cuff tab) |
| Clean joint evidence | PASS (off-test) | node render per builder; `.riv` regenerated by me: deterministic and byte-identical to the committed file |
| Home goldens updated; no overflow at 1.3×, RTL/LTR | PASS | `home_mascot_slot_test.dart`, `zaghlol_avatar_trim_test.dart`; goldens regenerated via app-regen |

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | nit | `tools/mascot_riv/rig.py:63` | `gi` from `enumerate` is unused. | Drop `enumerate`. |
| 2 | minor | `tools/mascot_riv` Lab gate | The Lab vs riv comparison was not rerun (builder note), so the Lab HTML still draws the tab. | FU-372: rerun the gate after the Lab art is trimmed too. |

`trimHeadroom` applies only to the Rive path (not reduce-motion, interim or injected artboards); `OverflowBox` + `ClipRect` with `AlignmentDirectional.bottomCenter` is direction-safe.

---

## T-275 — Voice first-listen (C3) — **APPROVED**

| Criterion | Result | Evidence |
|-----------|--------|----------|
| Stale end/no-match before "listening" ignored | PASS | `speech_to_text_port_test.dart` |
| One silent retry < 2 s, never after user stop, nothing saved | PASS | `voice_logger_test.dart` (cold start, real silence, Done at once, permission denied) |
| Root cause + PO device steps | PASS | task file |

Logic checked: `_quickRetry` requires listening phase, empty transcript, first attempt, no user stop; `_restart` bumps the session before cancel so the cancelled session's events are dropped; `stopListening` sets `_userStopped` first. The Android plugin (speech_to_text 7.5.0) sends `listening` synchronously inside `startListening`, so the port's `_heard` guard cannot leave a session stuck waiting for it.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | nit | `app/lib/features/voice/data/speech_to_text_port.dart:105` | Because `listening` arrives at once on Android, the guard only covers the window between `start()` and the plugin's start. Stale events after that are handled by the quick retry, not the guard. The doc comment overstates what the guard does. | Reword the comment (FU-373). |

---

## T-276 — Mascot tap without reload (C3) — **APPROVED**

| Criterion | Result | Evidence |
|-----------|--------|----------|
| Same State across taps, loader called once, never paints the still | PASS | `mascot_smooth_tap_test.dart` |
| Moods lab switch does not reload | PASS | same file |
| Root cause + PO steps | PASS | task file |

`preloadRiveMascot` runs `unawaited` with every error swallowed, and `_loadSharedFile` clears a failed future, so a failure neither delays nor crashes startup and the mascot retries on mount. Last tap wins through `_generation`; replay of the same value bounces through `(index+1) % 15` for one frame.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | minor | `app/lib/main.dart:77` | The preload starts the Rive native runtime and decodes the file for every user, including reduce-motion users who never show Rive. Before, reduce motion never loaded Rive, which made it an escape hatch on a device where the native runtime misbehaves. | FU-374: skip the preload when reduce motion is on (or when the platform disables animations). |

---

## T-277 — 32 Zaghlol tips (C2 copy) — **APPROVED**

| Criterion | Result | Evidence |
|-----------|--------|----------|
| ≥ 30 tips ar + en | PASS | 32 keys (`mascotTip*`), copy deck updated |
| Overflow over every tip at 1.0×/1.3×, RTL/LTR | PASS | `mascot_tips_overflow_test.dart` |
| Rotation unit test; target routes exist | PASS | `mascot_tips_test.dart` |
| No «دورة», no "AI" claims | PASS | grep of the new ar strings: 0 «دورة»; no AI wording |
| Settings key counters only | PASS | `Settings.mascotTipState` = `u.s.h.shown`, decode regex-validated |

Truthfulness check: scan, share, voice, link card, payday, statement import (CIB/NBE/Banque Misr/QNB exist in the import flow), Review Keep/Edit/Ignore, InstaPay name search, hide amounts, category budgets, expected salary, Ask tab, manual card due/limit, Insights, auto-category memory, due notices, duplicate flagging, receipt OCR: each has a screen or engine on this branch. Privacy wording uses «بياناتك مابتطلعش من موبايلك»; no "no server" claim. A tip shows only when no proud/alert/payday line is up.

| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| 1 | minor | `app/lib/core/l10n/app_ar.arb:4309` (`mascotTipSmartTransfer`) | ar «لو حولت من كارت لحسابك» (card → your account) and en "Move money from one of your cards to another" say different things. Self-transfers pair between accounts. | FU-375: align both, e.g. "Move money between your own accounts …". |
| 2 | minor | `mascotTipSmartSms` | "When a bank message reaches me I read it" is shown on iOS too, where SMS are not read (Shortcuts only). | FU-375: platform-specific variant, or neutral wording ("bank messages you share or capture"). |
| 3 | nit | `app/lib/core/l10n/app_ar.arb:4315` and `mascotTipSmartVoice` | Hard-coded Arabic-Indic digits (٢٤, ١٥٠, ٤٥) ignore the Western-digits setting in Arabic. | Same fix as T-272 #8 (placeholders), FU-375. |
| 4 | nit | `app/lib/features/mascot/application/mascot_tips.dart:290` | The FutureProvider writes settings as a side effect, and it advances again whenever `settingsRepositoryProvider` / `setupInstalledOnProvider` rebuild. | Accept; or move the advance to an explicit "shown" call. |

---

## Verdict summary
| Task | Verdict | Blocker / major |
|------|---------|-----------------|
| T-272 | APPROVED | none (minors FU-364…FU-370) |
| T-273 | CHANGES_REQUESTED | 1 major: Arabic lines/amounts lost (`strongLatin` too loose, 0.60 gate applied everywhere) |
| T-274 | APPROVED | none |
| T-275 | APPROVED | none |
| T-276 | APPROVED | none |
| T-277 | APPROVED | none |

---

## Delta re-review (fix78)

Scope: `git diff 6bacc0c7 891484cd` (14 files). Kotlin could not be compiled here; read by hand and every `OcrMergerTest` case traced.

### T-273 — **APPROVED** (original major resolved; 1 minor, 2 nits)

| Check | Result |
|---|---|
| Real Arabic lines at 0.45-0.60 with no strong ML Kit overlap kept, incl. Arabic-Indic amounts | PASS. `MIN_ARABIC_CONFIDENCE = 0.45`; `arabicLineAtMidConfidenceWithoutOverlapIsKept` and `arabicLineOverWeakGarbageIsKeptWithItsAmount` keep `الإجمالي ٨٥٫٥٠` untouched |
| 0.60 gate only on overlap with a strong ML Kit line | PASS. `passesOverlapGate` uses the same `overlap >= OVERLAP` as `mergeBoth`'s matcher |
| `strongLatin` rejects `Jlaa Jlj`, `Jl J`, `lall`, `JI plw` | PASS by hand (no word-like token, or one 4-letter token alone) |
| `strongLatin` accepts `Total 436.00`, `VAT 53.54`, `Visa 436.00`, `Net after Discount`, long single words, digit-only | PASS |
| Original bug (noise digits 1,558 vs 436) not reintroduced | PASS for the PO photo: noise 0.47/0.52/0.48 over strong lines is dropped by the gate; the 0.67 line only adds `نقدى`; the mixed-script token `1١5206` is refused by `arabicAmountTokens`. Residual risk in findings 2 and 3 |
| Kotlin compiles | Expected yes. `a + if (c) x else emptyList()` parses with the `if` as right operand; `String.trim(vararg Char)`, `Regex.matches`, `Char in String` all exist; `val extra`/`words` types infer to `List<String>` (same shape as the previous `if ... emptyList() else ...`). Cannot be confirmed without kotlinc |
| Operator precedence in `extra` | Correct: `arabicWords(..) + (if (digitTokens(line.text).isEmpty()) arabicAmountTokens(..) else emptyList())` |

Hand trace of `OcrMergerTest` (all 17 cases): all expected to pass, including `latinReceiptKeepsTheMlKitLines` (6 of 7 noise lines gated or non-credible, 7 lines out, first line `Name: عميل نقدى`), `arabicReceiptIsUnchangedAndDigitsComeFromMlKit` (`الإجمالي 85.50`, `12 صيدلية النور`), `arabicAmountIsAppendedWhenStrongMlKitLineHasNoDigits` (`Total Amount الإجمالي 85.50`) and the `strongLatin` assertions.

Is a weak verdict harmless unless a credible Arabic line overlaps? Yes. `strongLatin` only matters (a) in the gate and (b) to decide replace vs append. A weak real Latin line is affected only when an Arabic line with Arabic-majority letters and conf >= 0.45 overlaps it at >= 0.5 (or any Arabic line >= 0.60). Then the line is replaced, but its ASCII digit tokens are kept (`digitsWin`), so amounts survive; the label/currency word is what is lost. Separate amount boxes (`436.00`) are digit-only, hence strong, and still gate the noise out.

#### Findings

| # | Sev | File:line | Issue | Required change |
|---|---|---|---|---|
| 1 | minor | `OcrMerger.kt` `wordLike`/`strongLatin` (~l.121-135) | Real short or consonant-only Latin tokens are weak when alone or with only digits: currency codes `KWD 5.000`, `CHF 20.00`, `GBP 20.00`, `BHD 3.000`, `JPY 1000` (no vowel / consonant start), `LE 85.50`, `Rs 50`, `No. 12345` (2 letters), `Qty 2` (`qt` not a cluster), and lone `Cash`, `Tip`, `Tax`, `Net`. Concrete: latin `KWD 5.000` + Arabic `كود 5.000` conf 0.50, same box: gate passes (line is weak), line replaced, output `كود 5.000`, the currency code is lost (amount kept). The parser then has no currency on that line (CLAUDE.md rule 4: never silently wrong currency). Amounts are never lost, so not a major; the OCR result goes through the review screen. Egypt-default EGP/USD/EUR/SAR/AED/QAR are strong, so the common cases are fine | Follow-up: treat an all-caps 3-letter token (any vowels) next to a digit token as strong, or add the ISO code check to `strongLatin`. Add `KWD 5.000`, `Qty 2` to the `strongLatin` test. Owner: T-273 follow-up (FU) |
| 2 | minor | `OcrMerger.kt:85-95` | Amount-append path trusts Arabic digits when the strong ML Kit line has no ASCII digits and the Arabic line is >= 0.60. Concrete: latin `Net Sales` (0,300,200,340) and separate `382.46` (300,300,500,340), Arabic noise `321146 535 أول١ا` conf 0.62 spanning both: `Net Sales 321146 535` is emitted next to the correct `382.46`. Not reachable with the measured PO noise (max 0.56) and only for pure-ASCII noise tokens, so the 1,558 case stays fixed; the 0.60 margin rests on one photo (already noted in ADR-009, SPK-02) | None now; keep under SPK-02. Optionally append the amount only when the ML Kit line is not label-only next to a digit-only ML Kit line |
| 3 | minor | `OcrMerger.kt` `overlap`/`mergeBoth` | An Arabic noise line at 0.45-0.60 whose box overlaps a strong ML Kit line by < 0.5 (vertical drift) counts as "no overlap" and is kept whole with its wrong digits. PO-photo boxes align within a few px, so tests do not cover it | Known limit; note for SPK-02 |
| 4 | nit | `OcrMerger.kt` ~l.79-84 | `val extra = ...; val words = extra` is a redundant alias | Inline |
| 5 | nit | `OcrMergerTest.kt` | No test for the gate boundary (conf exactly 0.45 / 0.60) or an Arabic-Indic-only amount appended | Optional |

### Copy (T-272 / T-277): PASS, no findings

- Exchange wording is now "تغيير عملة / غيّرت عملة" everywhere in `app_ar.arb` (title, intro, save/saved/failed, KPI lines, jump question, Add row, a11y); en is "I exchanged currency / Currency exchange". No stale "حولت فلوس" left in lib or the design plan table (updated). Egyptian colloquial, no standard-Arabic drift.
- `mascotTipSmartTransfer` ar/en now say the same thing (move money between own accounts is not spending). `mascotTipSmartVoice` and `mascotTipHabitWait` use word-form numbers in ar (`مية وخمسين`, `استنى يوم`); en keeps digits, acceptable.
- ar/en key parity and generated files: `test/core/l10n` green.

### MascotTip.androidOnly: PASS

`tipsOf(g, android: false)` drops only `mascotTipSmartSms`; the smart pool keeps >= 10 tips, so no empty pool on iOS and `rotation.of(group) % list.length` stays valid for any saved counters (at worst one tip is skipped or repeated once). The provider passes `defaultTargetPlatform == TargetPlatform.android`; new test covers both platforms over 400 picks. Defaults are `true`, so existing callers and tests are unchanged.

### Tests run

`flutter test -x golden test/features/mascot test/app test/core/l10n test/features/ingestion test/features/transfers test/features/voice` in `app/`: **550 passed, 0 failed**.

### Not verified

Kotlin compile and `OcrMergerTest` execution (no Android SDK/kotlinc; CI is the gate; traced by hand only). Real-device OCR accuracy (one PO photo only). Goldens excluded by the command.

### Verdict (fix78)

T-273: **APPROVED**. No blocker or major remains. Findings 1-3 become follow-ups (FU, owner T-273 / SPK-02), not merge-blocking.
