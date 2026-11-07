# Review: T-026 Copy deck part 1 (onboarding, capture, Home, transactions, review, accounts)

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer (Opus) |
| Date | 2026-11-07 |
| Commit / diff | `task/T-026-copy-deck-1` @ `f43b6e1`; `git diff origin/main...origin/task/T-026-copy-deck-1`. One new file, `docs/02-design/copy-deck.md` (1,033 lines). All line numbers below refer to that file at `f43b6e1`. |
| Verdict | **CHANGES_REQUESTED**: 3 majors (F-1, F-2, F-3) |

## How this was checked
- A script parsed every `| \`key\` | AR | EN | Notes |` row. It found 676 rows and 0 duplicate keys. Every key matches `^[a-z][a-zA-Z0-9]*_[a-z][a-zA-Z0-9]*_[a-z][a-zA-Z0-9]*$`. The per-section counts match the table in §1.K. There are 35 plural messages and 8 select messages, which also matches §1.K.
- Placeholder sets are identical in AR and EN for all 676 keys. Braces balance in every string, and every plural and select has an `other` branch.
- No AR string contains a literal digit, Western or Arabic-Indic, once ICU selectors and placeholder names are stripped. Every number and money value is a placeholder.
- Emoji appear only in mascot lines, greetings, success messages, empty states and the glossary's «مستني رأيك 👀». There are none on errors, permissions, destructive dialogs, backup passphrases or Gold. No string has more than one emoji per branch.
- Nothing claims "no server". `common_error_network` uses the wording from the voice doc.
- I read the deck against S-01…S-06 (`screens/10`, `07-flows` §C), S-10…S-16 (`screens/20`), S-40…S-43 (`screens/50`), S-61/S-62 (`screens/70`), SRS v1.8 (BR-SYNC-03, FR-ONB-01/10, FR-TXN-03/06, FR-PAR-14, BR-BUD-01/03, BR-MAS-*, BR-CAP-01, FR-EXP-04/06, EC-06, A-63), `database-schema.md`, `domain-algorithms.md` §2/§7, ADR-004 and ADR-017.

## Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| Every string on S-01…S-16, S-06, S-40…S-43, S-61/62 has AR+EN | PARTIAL | All 676 keys have both AR and EN. Most elements and states in the specs are covered. Some states have no key (F-5) and native OS strings are missing (F-6). S-07…S-09 don't exist in the inventory, which is correctly noted at line 99. |
| Keys follow naming convention | PASS | 676 unique keys, all three-segment camelCase. Feature segments match `architecture.md` §4.2. Nits in F-14 and F-19. |
| DoD (CLAUDE.md §7) | PASS / N/A | Docs only, so analyze, format and tests don't apply. No `double` money: every amount is a pre-formatted `{amount}`-style String. No raw SMS: the only sample is the synthetic `**1234` (line 880). |
| Design note recorded (task "Design note: Required") | PARTIAL | The note is in deck §1.0, not in `T-026.md`. The deck flags this as Q-14. |

## Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| F-1 | **major** | `copy-deck.md:33` vs 168, 233, 241, 242, 260, 262, 378, 454, 459, 527, 532, 538, 594, 595, 597, 644, 711, 747, 764–767, 793, 864, 970, 972 | §0.4 says "Arabic must supply all six forms: `=0`, `=1`, `=2`, `few`, `many`, `other`". 26 of the 35 AR plurals have no `=0`. `onboarding_iosSetup_checkCount` (378) has only `=1` and `other`. For some keys zero really happens: `transfers_link_afterMinutes`/`beforeMinutes` (764–765) when both sides land in the same minute, which is common for self-transfers, and `common_date_minutesAgo` (233). Those render «بعدها بـ ٠ دقيقة» / "0 min later". | Add `=0` to every AR plural, or amend §0.4 to "`=0` where count can be 0" and list the keys where 0 can't happen. Either way, add `=0` in AR and EN to 764–767 (e.g. «في نفس الدقيقة» / "same minute"; for days, «في نفس اليوم» / "same day") and decide 233 against `common_date_justNow`. Give 378 all six forms, even if they repeat. |
| F-2 | **major** | `copy-deck.md:24-29`, `59` | T-029 is a Haiku task that must "transcribe the tables mechanically" (line 104). §0.3 types only `amount`, `percent`, `date`/`time`/`when`, `card`, the data names and `count`/`n`. The deck uses 56 placeholder names. Nine are money values with no type or format rule: `paid`, `back`, `share`, `net`, `income`, `spent`, `left`, `limit`, `available`. Others are numbers or IDs with no type: `day`, `step`, `total`, `index`, `min`, `max`, `done`, `rate`, `size`, `last4`, `templateId`, `appVersion`, `sample`. The §0.6 isolate list also leaves out most of these, plus `fromCard`/`toCard`/`cards`/`person`/`name`/`query`/`provider`/`category`/`automationName`/`label`. A placeholder's type is only stated for plural rows. | Add a placeholder registry to §0: name → ARB type (String/int) → source formatter (`MoneyFormat`, digits layer, date formatter, or raw data) → isolate yes/no. Make §0.6 point to it instead of keeping its own partial list. |
| F-3 | **major** | `copy-deck.md:328` | On the SMS-permission screen, `onboarding_androidSetup_smsPointOnPhone` says «كل حاجة بتفضل على الموبايل ده» / "Everything stays on this phone". BR-SYNC-03 lets the backend receive opt-in merchant contributions and bank-support requests, and backups go to Drive or iCloud. Tone gate 4 (line 83), R-11 and CLAUDE.md §9 limit the claim to financial data. The note "financial data, true per §2.1" isn't what the string says. The S-02 wireframe (`screens/10:53`) has the same wording. | Change it to «بيانات فلوسك بتفضل على الموبايل ده» / "Your money data stays on this phone", and ask the designer to update the S-02 wireframe text to match. |
| F-4 | minor | `copy-deck.md:935`, `966` | «زغلول مش هيبص عليه خالص» / "won't look at" overclaims. BR-CAP-01 reads the institution, channel and card in memory before it discards the message. | Use the spec's wording (`screens/70:63`): «هيتجاهل رسايله ومش هيحفظ منها حاجة» / "messages for it are ignored and never saved". |
| F-5 | minor | various | Some spec states have no key: (a) S-04 "signing in" progress is listed at line 401 but has no key. (b) S-61 iOS Apple Pay checker result is "✓ Active", and the checker's "can't tell" state has no key (`screens/70:33`, FR-ING-I-07). (c) S-61 supported-banks rows have no per-bank channel line for Android; only the iOS note exists (952). (d) S-15 has no "Unassign" for FR-XFR-09 and no remove-person action. (e) S-16 relative time goes from minutes straight to days, so a 3-hour gap reads "180 min later". (f) The S-14 spec title shows a count, "Needs review (5)", and `ingestion_review_title` (678) has none. | Add keys for (a)–(e). For (f), either add a count variant or record that the count shown on the "All" chip replaces it. |
| F-6 | minor | §1.0 scope (99-101) | OS-surfaced strings for these flows aren't covered and no part claims them: iOS `NSFaceIDUsageDescription` (S-05/app-lock prompt), the Android NotificationListenerService label and description (line 339 tells the user to find "زغلول" in that OS list), AppIntent and Shortcut titles and phrases (S-03), and the share-extension display name. | Add a "native strings" subsection, or assign them explicitly to Part 3 or a native task in the §1.0 "Not in scope" list. |
| F-7 | minor | 311, 312, 315, 346, 359, 367, 371, 392, 394, 395, 409, 420, 441, 523, 564, 572, 593, 614, 644, 699, 700, 703, 793, 800, 838, 878, 888, 917, 964 | 29 keys (38 AR/EN values) exceed the deck's own length limits in §0.7, with placeholders excluded. Examples: `onboarding_iosSetup_shortcutTitle` T is AR 60/40 and EN 56/44; `capture_cardControls_smsIos` C is AR 24/16; `backup_restore_forgotBody` S is EN 155/130; `onboarding_welcome_restore` B is AR 24/20. | Shorten each one or reclassify it, for example to S. Re-run the length check before T-029. |
| F-8 | minor | 397, 952 | `capture_banks_iosNote` says iPhone tracks {bank} "through Apple Pay, screenshots and statements". Statement import is Gold (FR-EXP-04/06), so a Free user is promised a path they don't have. | Mark statements as Gold in the copy, or add a Gold-variant select. |
| F-9 | minor | 114-144 vs 591, 592, 696-698, 718, 769, 518 | §0.10 says screens reuse `common_*`, but several screen keys repeat a common action word for word: `transactions_list_bulkCancel`/`bulkDelete`, `ingestion_review_genConfirm`/`genEdit`/`genDismiss`, `ingestion_requestBank_send`, `transfers_link_link`, `home_prompt_paydayNo`. 31 AR+EN pairs are duplicated in total. | Either point these at the `common_action_*` keys, or state in §0.10 when a screen-specific copy is allowed, for example when the screen may need different wording later. |
| F-10 | minor | 49, 637 | §0.4 says platform selects use `ios`/`other`. `transactions_detail_deleteBodyAuto` uses `android`/`other`, so the caller has to pass different values for different keys. | Use `ios` / `other` and swap the branches. |
| F-11 | minor | 1008-1026 (§1.Q) | Several open questions are already answered by approved docs and should be closed or reworded (see the Q table below). A glossary conflict isn't raised at all: `06-voice-and-tone.md` §3 maps Notifications → «التنبيهات», while the deck uses «الإشعارات» everywhere (221-222, 335-341, 536). | Update §1.Q as shown in the table below. Add a Q-17 on «التنبيهات» vs «الإشعارات», most likely: glossary term for the app's own notifications, OS term for captured app notifications. |
| F-12 | minor | 510 | `home_mascot_payday` is a banner line, but `domain-algorithms.md` §7 treats `payday` as a motion-only UI event, and the C-14 priority list (shocked > detective > proud > tourGuide) has no payday slot. | Add a question for the architect on where payday sits in `MascotPolicy` priority, or move the line to a non-banner surface. |
| F-13 | minor | 488 | The note says "safe-to-spend ≤ 0". BR-BUD-03 and `domain-algorithms.md:28` clamp it with `max(0, …)`, so it is never negative. | Change the note to "= 0 with budget > 0". |
| F-14 | nit | 284, 493, 562 | `mascot_avatar_a11y`, `home_hero_a11y` and `transactions_row_a11y` don't follow the "ends in `A11y`" rule at line 18. | Rename them (e.g. `mascot_avatar_labelA11y`), or allow a bare `a11y` element in §0.1. |
| F-15 | nit | 315, 903 | Tone gate 5 says to prefer neutral wording. «أنا مستخدم زغلول قبل كده» is gendered and over the length limit. | Use «استخدمت زغلول قبل كده». |
| F-16 | nit | 120, 140 | «تخطّي» and «المزيد» read as MSA. | Flag them for T-058, e.g. «فوّت» / «كمان». |
| F-17 | nit | general | gen-l10n has a `use-escaping` option. If it is on, apostrophes in EN ("doesn't", "They'll") become ICU quote characters. | Add a note for T-029 to keep `use-escaping: false`, or escape apostrophes. |
| F-18 | nit | 779 | S-40's asset rows and net-worth unit lines are deferred to Part 2, but T-027's scope lists only S-44…S-46. | The Lead should add "S-40 assets section + unit lines" to T-027. |
| F-19 | nit | 641-645 | Rules belong to the `categorization` module (FR-CAT-05, `architecture.md` §4.2), not `transactions`. | Optionally rename to `categorization_rule_*`. Keys are stable after T-029, so decide now. |
| F-20 | nit | 291 | "Every pound you save" is ambiguous for GBP users (P-06). | Optional: "Every bit you save…". |

## Open questions §1.Q: assessment
| Q | Real gap? | Who decides | Note |
|---|---|---|---|
| Q-01 | Yes (doc conflict) | UX designer | D-34's glossary already decides it: «الحسبة». Update `03-navigation.md`. |
| Q-02 | **Already answered** | Architect (done) | `database-schema.md:87` has `source … 'share'` (and channel `share`/`paste`). Map `common_source_shared` → `share`. The FR-TXN-03 text needs only a wording fix (requirements analyst). |
| Q-03 | Partly answered | Architect + UX | ADR-004 / `deployment.md:13` define the `prodNoSms` flavour. Still needed: the S-02 flow in that flavour, i.e. whether step 1 is skipped and where `playUnavailable` appears. |
| Q-04 | Yes | UX + Lead (device check, T-058) | Not a product question. |
| Q-05 | Minor | UX | The hour boundaries are a UX choice. |
| Q-06 | Mostly answered | UX | BR-BUD-03 clamps to 0. The only open point is whether to show "0" with a caption. |
| Q-07 | Yes | **Product owner** (via requirements analyst) | A salary on day 29–31 conflicts with BR-BUD-01 (1–28). This is a behaviour choice. |
| Q-08 | **Not a gap** | none | FR-TXN-06 says Undo for changes and confirmation for delete, and the S-11 spec says delete can't be undone. The deck already matches. Close it. |
| Q-09 | Yes (spec text) | UX designer | The SRS wins (FR-PAR-14, BR-SYNC-03). Update the S-14 spec. |
| Q-10 | Yes | UX (examples); **PO/legal** for brand clearance (OQ-09, already open) | InstaPay is not a wallet. Replace it with a real wallet brand, subject to OQ-09. |
| Q-11 | Yes | **Product owner** | What "hide" does to totals is a behaviour choice (FR-ACC-04). `accounts.is_hidden` exists but has no semantics. |
| Q-12 | Yes | Architect (can merge be reversed? `merged_into_id`) + UX | No PO decision needed unless "no undo" is chosen. |
| Q-13 | Yes, and wider than stated | Architect + UX | The S-12 spec says pending is n/a, but EC-06, A-63 and the schema's `status IN ('posted','pending','declined','reversed')` mean pending and reversed rows can exist. They need row and detail copy. |
| Q-14 | Process | Lead | Copy §1.0 into `T-026.md`. |
| Q-15 | Yes | Architect | Confirm the approach against ADR-017's `DigitsMode`/`NumberFormat`. It looks compatible. |
| Q-16 | Yes | Architect | Confirm where FSI/PDI is applied. This depends on the placeholder registry in F-2. |

Only Q-07 and Q-11 need a product-owner decision; Q-10's brand clearance is already tracked as OQ-09. Q-02 and Q-08 should be closed, and Q-03 and Q-06 narrowed.

## Checklist
- [x] `flutter analyze` clean: N/A (docs)
- [x] Tests added and passing: N/A. A Lead copy checklist is required by the task. The script checks above are a substitute for the mechanical parts.
- [ ] RTL + LTR verified: RTL rules are in §0.6, but isolate coverage is incomplete (F-2)
- [x] No hard-coded strings: N/A
- [x] No `double` money, explicit currency: all money values are formatted String placeholders, and no copy sums across currencies
- [x] No sensitive data in logs or fixtures: no SMS bodies; the sample is synthetic
- [x] Stays within the task's scope: one file, no changes to other docs

## Notes for the Lead
- To get to APPROVED: fix F-1, F-2 and F-3. Minors F-4 through F-13 should be fixed in the same pass, since T-029 freezes the keys. Nits can go to T-058 or follow-ups.
- Coordinate F-3 with an S-02 wireframe fix (`screens/10-onboarding-security.md:53`) by the UX designer. This reviewer doesn't edit design docs.
- Add the S-40 asset rows to T-027's scope (F-18).
- Not separately reviewed: Arabic naturalness. That is T-058's job (native Egyptian speaker).
