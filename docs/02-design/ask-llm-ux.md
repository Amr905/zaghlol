# Ask Zaghlol with an LLM — UX (ASK-LLM)

| | |
|---|---|
| Status | **DRAFT — awaiting PO approval** (Phase 2 for ASK-LLM) |
| Requirements | `docs/01-requirements/ask-llm.md` v0.2 (D-88…D-93), PO_DECISIONS row ASK-LLM |
| Extends | S-50 Ask Zaghlol (`screens/60-zaghlol.md`), S-71 Privacy (`screens/70-settings.md`), copy deck §2.16 / §3.10 |
| Copy | `copy-deck.md` **Part 4** (§4.1–§4.11, 105 keys). Keys below are written without the `chat_` / `privacy_` prefix only where obvious |
| Tokens | `05-theme-2026.md` §0 (Mint Fresh light, True Black dark); components `04-design-system.md` §3; motion `08-mascot-motion-and-bank-logos.md` |

## 0. Principles for this feature
1. **No new screen.** Everything lives in S-50 (chat), one bottom sheet (consent) and one S-71 row. With `ask_llm` off, S-50 looks exactly as today (FR-LLM-60).
2. **Local first, and visibly so.** The offline engine answers first (FR-LLM-01). Only an LLM answer carries the "Online helper" badge and the "What I sent" disclosure; local answers look as today.
3. **Every number is the phone's.** LLM answers use the same bubble (C-33) and money text (C-04) as local answers.
4. **Honest, short trust copy.** The consent sheet shows the question exactly as it will leave the phone before the first send.
5. **No mic.** S-50 has no microphone today and voice to the LLM is a v1 non-goal, so none is added (`listening` mood unused here).

## 1. Flow and states (S-50)

```
type ─► Send ─► local engine ──understood──► [A] local answer (no badge, no quota)
                    │
                    └─not understood─► resolve references (D-92)
                          ├─ unresolvable ──► [C] clarification (nothing sent)
                          └─ ok ─► flag/paused/quota/offline checks
                                 ├─ quota 0 ──► [Q] at-limit bubble (nothing sent)
                                 ├─ offline ──► [O] needs-internet bubble
                                 ├─ no consent ─► [N] consent sheet ─ Not now ─► fallback chips
                                 └─ send ─► [S] sending (thinking) ─► plan ─► compute ─► [R] answer
                                                   ├ timeout/5xx ─► [E] error + Try again
                                                   ├ 429 / attest ─► [E] slow down / integrity
                                                   └ service_paused ─► [P] paused, counter hidden
```

| State | Trigger | What the user sees | Mascot (`ZaghlolAvatar`) | Copy keys | Sent? Quota? |
|---|---|---|---|---|---|
| Flag off | `ask_llm` off or stale > 14 d | S-50 exactly as today | as today | §2.16 | — |
| Idle | open tab | greeting (first time) + chips + input; counter at the input's end edge | `tourGuide` once, first open | `chat_main_greeting`, `chat_llmInput_hint`, `quota_remaining` / `quota_unknown` | — |
| Typing | text in field | Send enabled 1–300 chars; counter `{n}/{max}` from 250; at 300 input blocked + `chat_main_tooLong` | — | `llmInput_counter` | — |
| Answered locally | engine `AskUnderstood` | normal answer, no badge, counter unchanged | as today | `chat_answer_*` | No / No |
| Clarification | placeholder unresolvable (FR-LLM-20) | Zaghlol bubble + chips of the user's matching cards/accounts + caption "not sent" | `detective` still pose | `clarify_*`, `clarify_notSent` | No / No |
| Consent | first LLM-bound send, no `ask.llm_consent` | bottom sheet (§1.1) over the chat; the user bubble is already shown | `tourGuide` still in sheet header | `consent_*` | Not until Allow |
| Consent declined | Not now | fallback bubble + 3 chips; nothing stored | `tourGuide` | `consent_declined` | No / No |
| Sending | Allow, or consent present | typing row: thinking mood + `llmStatus_sending`; Send becomes **Stop** | `thinking` loops while waiting (> 1 s); typing dots from 300 ms | `llmStatus_sending`, `llmStatus_thinkingA11y`, `llmInput_stop` | Yes / per backend |
| Computing | plan received | same row, `llmStatus_computing` (usually < 300 ms, often never shown) | `thinking` | `llmStatus_computing` | — |
| Answer | plan valid | bubble: answer, optional mini chart, footer row: badge + "What I sent" (§2) | bubble pose per plan (table §1.2) | §1.2 | counted |
| Stopped | Stop tapped | user bubble stays, snackbar | — | `llmStatus_stopped` | backend decides (OQ UX-ASK-05) |
| Fallback | PL-FALLBACK | existing fallback + 3 chips, never a number | `tourGuide` | `chat_fallback_text` | counted only if the model chose it |
| Refusal | PL-REFUSE | app copy per reason; specificPick adds the "If I had saved?" chip; self-harm cues add the support line | `tourGuide` (offTopic), still pose (unsafe) | `refuse_*` | counted |
| Offline | no network before send | bubble + 3 chips + caption "won't be sent later" | `oops` still | `llmStatus_offline`, `llmStatus_notQueued` | No / No |
| Error | timeout 12 s / 5xx / invalid | inline error in the Zaghlol bubble + one **Try again** (resends the same question) | `oops` | `llmStatus_timeout`, `llmStatus_error`, `common_action_tryAgain` | not counted |
| Slow down / integrity | 429 / attestation failed | inline error, no retry button for 429 (wait), Try again for integrity | `oops` | `llmStatus_slowDown`, `llmStatus_integrity` | not counted |
| Service paused | `service_paused` | bubble; counter and "online" hint hidden until next sync says otherwise | `sleep` | `llmStatus_paused` | No |
| Last question | remaining = 1 | one-line note above the input (N style, not a snackbar) | — | `quota_lastOne` | — |
| Exhausted, Free | remaining = 0, Free | bubble + Gold hint line + text button "See Gold" (opens S-68) + caption | `tourGuide` still | `quota_freeOut`, `quota_goldHint`, `quota_seeGold`, `llmStatus_notQueued` | No / No |
| Exhausted, Gold | remaining = 0, Gold | bubble with the reset date (1st of next month, Cairo) | `tourGuide` still | `quota_goldOut`, `llmStatus_notQueued` | No / No |
| Hide amounts | D-67 on | every amount blank `**** ج.م` / `**** EGP` (C-04 masked), grams hidden; percentages stay | — | `common_money_maskedA11y`, `invest_gramsHiddenA11y` | — |
| Reduce motion | OS or app toggle | `thinking` becomes a still pose + the status line; no loops, no confetti | still poses | same | — |

Rules: one Zaghlol per screen (the avatar in the latest bubble animates; older ones are still). The bird never delays the answer: when the plan is computed the answer replaces the typing row at once, even mid-loop. Chips that start a known plan (`invest_suggestChip` → PL-SUGGEST, `invest_chip` → PL-INVEST savedLastPeriod) run **on the phone directly**: no request, no quota.

### 1.1 Consent sheet (C-17, half height, scrolls to full at 130 %)
```
RTL (ar)                                        LTR (en)
┌───────────────── ── ─────────────────┐        ┌──────────── ── ────────────────┐
│ السؤال ده محتاج المساعد الأونلاين  [🐦]│        │[🐦] This one needs the online helper│
│ مقدرش أجاوبه من موبايلك لوحدي…        │        │ I can't answer it on your phone…  │
│ ده اللي هيتبعت بالظبط                  │        │ Exactly what will be sent         │
│ ┌──────────────────────────────────┐ │        │ ┌──────────────────────────────┐ │
│ │ صرفت كام بـ [كارت ١] في [مكان ١]؟ │ │        │ │ Spent on [Card 1] at [Place 1]? │ │
│ └──────────────────────────────────┘ │        │ └──────────────────────────────┘ │
│ ✓ بيتبعت  … ✗ عمره ما بيتبعت …        │        │ ✓ What's sent … ✗ Never sent …    │
│ سيرفر زغلول مبيحفظش سؤالك…            │        │ Zaghlol's server doesn't keep…    │
│ عندك ٥ أسئلة أونلاين في الشهر…         │        │ You get 5 online questions…       │
│ تقدر تقفلها في أي وقت من «خصوصيتك».    │        │ You can turn it off any time…     │
├──────────────────────────────────────┤        ├──────────────────────────────────┤
│ [ تمام، ابعت ]        [ مش دلوقتي ]   │        │ [ Allow and send ]  [ Not now ]   │
└──────────────────────────────────────┘        └──────────────────────────────────┘
```
- Sticky action bar: primary filled (C-03 Primary) "Allow and send", text button "Not now". Both ≥ 48 dp; at 130 % they stack vertically (primary first).
- Dismissing by drag/back = Not now. The sheet is also opened read-only from S-71 "What's sent?" (no buttons except Close, preview hidden).
- Android: Material 3 modal bottom sheet with drag handle. iOS: Cupertino-style sheet (grabber, medium then large detent), light haptic on Allow.
- The provider name (`{aiProvider}`) comes from remote config; see UX-ASK-02.

### 1.2 Answer anatomy and per-plan layout
Zaghlol bubble (C-33, start-aligned, `zaghlol bg`): body text (values bold), optional per-currency blocks (`chat_answer_currencyLead`, primary first, never summed), optional mini chart (C-13 compact, with a text alternative), then a **footer row**: badge `sent_badge` (C-21 style, `primaryContainer` pill) at the start, "What I sent ▾" text button at the end.

| Plan | Body | Extras | Pose |
|---|---|---|---|
| Data (SPEND, COMPARE, TOPN, BALANCE, BUDGET-LEFT, BILLS-DUE, SAVED) | existing `chat_answer_*` | COMPARE + `llmAnswer_changePct`; "Open in Transactions" link as today | `tourGuide` |
| AVERAGE / INCOME / BREAKDOWN / SAFE-SPEND | `llmAnswer_*` | AVERAGE adds `llmAnswer_fullUnits`; SAFE-SPEND with no budget adds the budget action | `tourGuide` |
| WHATIF-CUT / SAVE | `whatIf_*` | caption `whatIf_basis`; `whatIf_capped` when amount > base; EC-23 → `whatIf_notEnough` | `proud` once |
| SUGGEST | `suggest_intro` + up to 3 rows (category tile · sentence · `suggest_saveLabel`) | `whatIf_basis` caption, `suggest_footer`; S4 adds `suggest_cashTip`; none → `suggest_none` | `tourGuide` / `proud` (none) |
| INVEST | `invest_lead` + instrument rows (gold, ≈ USD, certificate) with icons, stale badge, ≈ caption | disclaimer block, always visible, never collapsed | `professor` once |
| LLM template (OQ-ASK-07) | validated template, blanks filled by the phone | same footer | as plan |

**Investment bands (D-93, EGP S, G = 0.25 g of 21K):** S ≤ 0 → `invest_nothingSaved` + chip · 0 < S ≤ 100 → `invest_small` + chip, no instruments, no disclaimer · 100 < S < G → `invest_stocks` + USD/certificate rows + disclaimer, no gold row · S ≥ G → gold + USD/certificate rows + disclaimer · G unknown → no stocks, no gold row · non-EGP S → §3.4 per currency, `invest_noPrice` where no price. No index row (OQ-ASK-02).

**Disclaimer block:** `surfaceAlt` panel inside the bubble, info icon (not an emoji), `invest_disclaimerSummary` (body, ink) above `invest_disclaimer` (caption, `textMuted`). Contrast: `#4D695C` on `#E5F5EC` ≈ 5.4:1 (light); `#A8A8A8` on `#222222` ≈ 6.9:1 (dark). Read by screen readers as part of the bubble, after the figures.

## 2. "What I sent" disclosure (D-92)
Collapsed by default under each LLM answer. Expanded:
```
┌ اللي بعته ▴ ───────────────────────────────┐
│ ده سؤالك زي ما خرج من موبايلك:             │
│ «صرفت كام بكارت [كارت ١] في [مكان ١] من   │
│  حسابي في [بنك ١]؟»                       │
│ المربعات دي مكان الأسامي. معناها فضل على… │
│ ومعاه بس: لغة التطبيق وإصداره، …           │
└────────────────────────────────────────────┘
```
- The text is the **exact sent string** (after FR-LLM-03 scrub and FR-LLM-18 placeholders), kept in memory with the chat message for the session only. Each `⟦ACCOUNT_n⟧ / ⟦CARD_n⟧ / ⟦BANK_n⟧ / ⟦MERCHANT_n⟧` renders as an **input-chip-shaped, non-interactive** token `sent_chip` («حساب ١», «كارت ١», «بنك ١», «مكان ١»), `primaryContainer` fill, ink text (light) / `#2A2A2A` fill, white text (dark). Scrub tokens (phone, e-mail, InstaPay, long number) render as `sent_hidden` chips on `surfaceAlt` with `textMuted` text and an eye-off icon.
- **The map is never shown.** Chips do not say which card «كارت ١» was; that would put the map in chat history (FR-LLM-19). The user's own bubble above already shows what they typed.
- Direction: the block takes the direction of its first strong character (an English question in the Arabic UI reads LTR). Each chip is a bidi-isolated unit and never mirrors internally; chip digits follow the digits setting (they are labels, not card numbers).
- Screen reader: the block is one node, `sent_textA11y` with chips spoken via `sent_chipA11y`; the toggle announces expanded/collapsed.
- The same rendering is used for the preview in the consent sheet (before sending).

## 3. Settings → Privacy (S-71)
New C-16 row group under "What stays on your phone", visible only while `ask_llm` is on:
```
│ اسأل المساعد الأونلاين                          [ ⏽ ]  │  privacy_askLlm_label (switch)
│ بيبعت نص سؤالك بس، من غير أسماء حساباتك…               │  privacy_askLlm_sentence
│ فاضل ٣ أسئلة الشهر ده، والعداد بيرجع يوم ١ ديسمبر.      │  privacy_askLlm_quota (only while on)
│ إيه اللي بيتبعت؟                                       │  text button → consent sheet, read-only
```
- Switch on → opens the consent sheet without the preview (no question pending); its buttons are `common_action_confirm` and `common_action_cancel`, and Cancel leaves the switch off. Switch off → clears `ask.llm_consent` at once, snackbar `askLlm_turnedOff`; the next LLM-bound question shows the sheet again. "Delete everything" clears it too.
- The quota line shows the last backend value, `askLlm_quotaUnknown` before first contact, and is hidden while paused.
- "What Zaghlol's server knows" (§3.10 list) gains `privacy_server_itemAskLlm` while the flag is on.
- **Where the quota is shown:** beside the S-50 input (always while the flag is on and not paused), the counter's info sheet (`quota_infoTitle/Body`), and this S-71 line. Nowhere else (no Home badge).

## 4. Layout, components, accessibility
**S-50 input area (RTL reference; LTR mirrors):**
```
│ (أوفر منين؟) (صرفت كام الشهر ده؟) (الفواتير الجاية)   │ chips row, scrolls horizontally
│ 🔥 اقصف جبهتي ⏻                       فاضل ٣ أسئلة ⓘ │ roast toggle (start) · counter (end)
│ [ اسألني بكلامك عن فلوسك…                     ] [➤] │ field + Send (Stop while sending)
```
- Counter: L text, `textMuted`, tappable (48 dp hit area) → info sheet. "—" before first contact. At 130 % text scale the counter moves to its own line above the field, end-aligned.
- Send icon mirrors in RTL; Stop (square) does not. The thinking pose, clock-like spinners and card last-4 never mirror.
- Components reused: C-33 bubbles and chips, C-04 money (incl. masked and ≈), C-21 badges (online, stale, ≈), C-17 sheet, C-16 row with switch, C-03 buttons, C-19 snackbar, C-29 inline error, C-13 compact chart. Flutter families only: Material 3 (text field, `ActionChip`/`InputChip`, modal bottom sheet) on Android; Cupertino sheet and haptics on iOS where they differ.
- **Targets:** Send/Stop 48 dp; chips 48 dp hit area (34 dp visual); disclosure toggle full-row 48 dp; consent buttons 48 dp.
- **Screen reader:** status changes are polite live-region announcements (`llmStatus_thinkingA11y`, then the answer); counter label `quota_remainingA11y`; badge `sent_badgeA11y`; masked values `common_money_maskedA11y`; grams `invest_gramsHiddenA11y`; focus moves to the new answer only if the user has not moved focus since sending.
- **Text scale 1.3:** bubbles wrap; instrument rows stack figure under label; consent sheet scrolls with a sticky action bar; no truncation of copy (only of placeholder values such as long merchant names).
- **Colour:** apricot (`accent`) never as text on light (≈ 1.8:1); the Gold hint uses ink text with the crown icon; "See Gold" is a primary-colour text button. Spending stays ink. Errors use `danger` text only in dark (`#F2A08B`) and the C-29 pattern in light.
- **Light / dark:** bubble `zaghlol bg` `#FFF3E6` / `#2A2018` with text `#0F2A20` / `#FBE7D2`; badge `primaryContainer` `#D7F3E5` / `#2A2A2A`; no shadows in dark (True Black rule).
- **Haptics:** iOS light impact on Allow and on answer arrival; Android none beyond the default send click.

## 5. Example answers (blanks in ⟨⟩, synthetic data from ask-llm.md §10)
| # | Plan / key | AR | EN |
|---|---|---|---|
| 1 | PL-WHATIF-CUT · `whatIf_cutPercent` + `whatIf_basis` | لو قللت ⟨الأكل بره⟩ ⟨٥٠٪⟩، هتوفر حوالي ⟨١٬٦٠٠ ج.م⟩ في الشهر، يعني ⟨١٩٬٢٠٠ ج.م⟩ في ⟨١٢ شهر⟩. · على أساس متوسط آخر ⟨٣⟩ شهور كاملة | Cut ⟨Dining out⟩ by ⟨50%⟩ and you'd save about ⟨EGP 1,600⟩ a month, ⟨EGP 19,200⟩ over ⟨12 months⟩. · Based on the average of your last ⟨3⟩ full months |
| 2 | PL-AVERAGE · `llmAnswer_average` + `fullUnits` | متوسط صرفك على ⟨كل حاجة⟩ ⟨شهر المرتب اللي فات⟩: ⟨٦٦١٫٢٩ ج.م⟩ في اليوم. | Your average spend on ⟨everything⟩ ⟨last pay month⟩: ⟨EGP 661.29⟩ a day. |
| 3 | PL-SUGGEST · `suggest_cash`, `suggest_aboveAverage`, `suggest_subscription` | ⟨٢٬٤٠٠ ج.م⟩ كاش سحبته ومش متسجل راح فين. لو سجلته، ممكن توفر حوالي ⟨٦٠٠ ج.م⟩. · ⟨الدليفري⟩ الشهر اللي فات ⟨٢٬٣٠٠ ج.م⟩، يعني ⟨٥٠٠ ج.م⟩ فوق متوسطك… · اشتراك ⟨تطبيق الأفلام⟩ بـ ⟨٣٠٠ ج.م⟩ في الشهر… | ⟨EGP 2,400⟩ of withdrawn cash isn't logged anywhere. Log it and you could save about ⟨EGP 600⟩. · ⟨Delivery⟩ came to ⟨EGP 2,300⟩ last month, ⟨EGP 500⟩ above your average… · ⟨Movie app⟩ costs ⟨EGP 300⟩ a month… |
| 4 | PL-INVEST S ≥ G · `invest_lead` + `invest_gold` | الشهر اللي فات فضل معاك ⟨٤٬٥٠٠ ج.م⟩. كان ممكن يجيب حوالي ⟨١٫١٢ جرام⟩ دهب عيار ⟨٢١⟩، بسعر ⟨٤٬٠٠٠ ج.م⟩ للجرام يوم ⟨٢٥ نوفمبر⟩. + disclaimer | Last month you had ⟨EGP 4,500⟩ left over. It could have bought about ⟨1.12 g⟩ of ⟨21⟩K gold, at ⟨EGP 4,000⟩ per gram on ⟨25 Nov⟩. + disclaimer |
| 5 | PL-INVEST band 100 < S < G · `invest_lead` + `invest_stocks` | لو معاك ⟨٥٠٠ ج.م⟩: مبلغ زي ده ممكن يبقى بداية صغيرة في الأسهم عمومًا. اتعلم الأول، واتعامل مع جهة مرخصة. + USD/certificate rows + disclaimer | If you had ⟨EGP 500⟩: An amount like this could be a small start in stocks in general. Learn first, and use a licensed provider. + rows + disclaimer |
| 6 | PL-COMPARE · `chat_answer_compare` + `llmAnswer_changePct` | صرفت ⟨٣٬٤٠٠ ج.م⟩ ⟨شهر المرتب اللي فات⟩، أكتر من ⟨اللي قبله⟩ بـ ⟨٢٠٠ ج.م⟩. يعني فرق ⟨٦٪⟩. (USD block separately, never added) | You spent ⟨EGP 3,400⟩ ⟨last pay month⟩, ⟨EGP 200⟩ more than ⟨the month before⟩. That's a ⟨6%⟩ change. |

Digits follow the digits setting (Arabic-Indic shown); card last-4 always Western LTR (CARD-DIGITS). Merchant and subscription names are the phone's own data, never the LLM's.

## 6. Open design questions for the PO
| ID | Question | Recommended default |
|---|---|---|
| UX-ASK-01 | Show the masked preview inside the first-use consent sheet? | **Yes** — the strongest trust signal; costs one block |
| UX-ASK-02 | If the AI provider changes (remote config), ask for consent again? | **Yes** — store the consented provider ID with `ask.llm_consent`; a different one re-shows the sheet |
| UX-ASK-03 | Caption "Answered on your phone" on local answers while the flag is on? | **No** — keep local answers as today; the badge on LLM answers is enough (`sent_local` kept for later) |
| UX-ASK-04 | Warn before sending that a question will use one online question? | **No** — the engine decides only after Send; the counter is always visible |
| UX-ASK-05 | Stop pressed after the request left: may it still count? | **Backend decides; the copy promises nothing** (`llmStatus_stopped` says only "stopped") |
| UX-ASK-06 | With hide-amounts on, mask numbers the user typed in "What I sent"? | **No** — it is the user's own text, already visible in their bubble |
| UX-ASK-07 | Gold hint on every Free at-limit answer, or once a month? | **Every time, as one text line**; the paywall opens only on tap (FR-GOLD-05 counts only then) |
| UX-ASK-08 | "Online helper" naming (ar «المساعد الأونلاين») vs "Zaghlol online" | **«المساعد الأونلاين» / "online helper"** — says plainly that it is not on the phone |
