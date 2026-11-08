# Copy deck — زغلول / Zaghlol

| | |
|---|---|
| Status | **DRAFT — Parts 1 (T-026) and 2 (T-027)**. Part 3 (T-028) appends below its marker. |
| Voice | `06-voice-and-tone.md` (D-34): Egyptian colloquial everywhere; simple standard Arabic only for legal text and disclaimers (Part 3). |
| Sources | SRS `docs/01-requirements/requirements.md`; screens `02-screen-inventory.md`, `screens/10…70-*.md`, `07-flows-onboarding-cards-import.md`; mascot `04-design-system.md` §4 and `08-mascot-motion-and-bank-logos.md` (D-35); mockup copy in `mockups/source/*.py` (reused where it already fit the voice). |
| Consumers | T-029 (ARB part 1), T-058 (native Egyptian-speaker review), T-087 (ARB parts 2–3). Keys map 1:1 to ARB keys (ADR-017). |

---

## 0. Conventions (all parts)

### 0.1 Key naming
`<feature>_<screen>_<element>` (`project-structure.md`), exactly three underscore-separated segments, all camelCase within a segment. Example: `home_hero_safeToSpend`.
- **feature**: an app feature folder from `architecture.md` (`onboarding`, `capture`, `ingestion`, `home`, `transactions`, `transfers`, `accounts`, `backup`, `security`, …). There are two extras: `common` for strings shared by several features, and `mascot` for Captain Zaghlol lines that aren't tied to one screen.
- **screen**: the screen, sheet or region inside the feature, e.g. `welcome`, `androidSetup`, `hero`, `detail`. On Home the middle segment names the region (`hero`, `banner`, `mascot`, …), following the `home_hero_safeToSpend` precedent.
- **element**: what the string is, e.g. `title`, `body`, `smsAllow`, `errorNetwork`, `labelA11y`. Screen-reader-only strings always end in `A11y`; a bare `a11y` element is not allowed.
- **native** strings (§1.23) use the reserved feature `native` and live outside the ARB files.
- Keys are stable. If wording changes, keep the key. If meaning changes, add a new key and retire the old one in the changelog at the end of the part.

### 0.2 Table format
Each section has a table: **Key | AR (عامية مصرية) | EN | Notes**. Notes hold the length class (§0.7), the placeholders and, for mascot lines, the Rive state and trigger.

### 0.3 Placeholders
- Every placeholder except a plural's `count` is a **String that code has already formatted**. The ARB text never formats numbers itself, because the Arabic UI can show either Arabic-Indic or Western digits (A-29, FR-L10N-03), and ICU number formatting can't follow that preference.
- **The registry in §0.3a is the single source** for each placeholder's ARB type, its formatter and whether it needs a bidi isolate. T-029 generates `@key.placeholders` from the ICU text plus this registry. A new placeholder name in any part must be added to the registry first.
- **No literal digits in Arabic strings.** Fixed small numbers are written as words («آخر أربع أرقام», «نص دقيقة»). Any other number is a placeholder. English strings may contain literal digits, because English always uses Western digits.
- Money: signs (`−`/`+`) are added by `MoneyFormat`, never written in copy. Money placeholders follow `04-design-system.md` §2.3 (AR `٤٥٠ ج.م`, `١٬٢٠٠ USD`; EN `EGP 450`, `USD 1,200`).

### 0.3a Placeholder registry (all parts)
Formatters:
- **Money** = `MoneyFormat`: amount plus currency, sign, per-currency exponent, digits mode.
- **Digits** = the digits layer: an integer or decimal formatted per `DigitsMode`, with no unit.
- **Date** = the locale date/time formatter, with digits per `DigitsMode`.
- **Data** = a raw user or registry value, inserted unchanged.
- **Copy** = another copy-deck string, already resolved by the caller.
- **Select** = a fixed enum value that only chooses a branch and is never displayed.

Isolate = the presentation layer wraps the value in FSI U+2068 … PDI U+2069 (§0.6).

| Name | ARB type | Formatter | Isolate | Meaning / example |
|---|---|---|---|---|
| `amount` | String | Money | yes | any money value: `−٤٥٠ ج.م` / `EGP −450` |
| `available` | String | Money | yes | credit available |
| `back` | String | Money | yes | money received back |
| `income` | String | Money | yes | cycle income (KPI) |
| `left` | String | Money | yes | left this cycle (KPI) |
| `limit` | String | Money | yes | credit limit |
| `net` | String | Money | yes | net after refund |
| `paid` | String | Money | yes | amount the user paid |
| `rate` | String | Money | yes | implied FX rate in the target currency, e.g. `٤٩٫٩ ج.م` |
| `share` | String | Money | yes | the user's net share |
| `spent` | String | Money | yes | cycle spend (KPI) |
| `percent` | String | Digits (+ `٪`/`%`) | yes | `٩٦٪` / `96%` |
| `n` | String | Digits | yes | the printed number of a plural (§0.4) |
| `count` | **int** | — | — | plural selector only, never printed |
| `day` | String | Digits | yes | day of month, 1–31 |
| `done` | String | Digits | yes | automations found |
| `index` | String | Digits | yes | pager position |
| `max` | String | Digits | yes | upper bound in a validation message |
| `min` | String | Digits | yes | lower bound in a validation message |
| `step` | String | Digits | yes | stepper position |
| `total` | String | Digits | yes | stepper / pager total |
| `size` | String | Copy (`common_fileSize_*`) | yes | `٢٫٤ ميجا` / `2.4 MB` |
| `date` | String | Date | yes | `٢٣ أكتوبر` / `23 Oct` |
| `start` | String | Date | yes | range start |
| `end` | String | Date | yes | range end |
| `time` | String | Date | yes | `٢:١٤ م` / `2:14 pm` |
| `when` | String | Date or Copy (`common_date_minutesAgo`) | yes | "as of" moment |
| `period` | String | Copy (`common_period_*`) | no | Arabic or English words only |
| `payday` | String | Copy (`home_hero_daysToPayday`) | yes | contains a number |
| `cards` | String | Copy or Data: a card label, or `common_cardFilter_count` | yes | — |
| `type` | String | Copy (`common_accountType_*`) in S-06; **Select** (`expense`/`income`/`transfer`) in S-13 | no | — |
| `category` | String | Data (catalog name, already localized) | yes | may be a custom Latin name |
| `channels` | String | Copy: `common_channel_*Short` joined with the locale list format (AR «و», EN "and") | yes | contains "Apple Pay" |
| `label` | String | Copy (a filter chip label) | no | — |
| `card` | String | Data: card label + `•` + last-4 | yes | `الأهلي فيزا •4567` |
| `fromCard` | String | Data, as `card` | yes | — |
| `toCard` | String | Data, as `card` | yes | — |
| `last4` | String | Data, as `•4567`, Western digits always | yes | never mirrored |
| `bank` | String | Data (registry name per locale, or user-typed) | yes | — |
| `sender` | String | Data (SMS sender ID / app name) | yes | Latin |
| `merchant` | String | Data | yes | often Latin |
| `counterparty` | String | Data: IPA handle, wallet number or name | yes | LTR |
| `person` | String | Data (sender name or a split participant) | yes | — |
| `name` | String | Data (a split participant's name) | yes | — |
| `query` | String | Data (the user's search text) | yes | — |
| `currency` | String | Data: ISO code, or `ج.م` for EGP in AR | yes | — |
| `fromCurrency` | String | Data: ISO code | yes | — |
| `provider` | String | Data: `Google Drive` / `iCloud` | yes | brand, never translated |
| `automationName` | String | Data: the shortcut automation name, e.g. `Zaghlol – Wallet` | yes | Latin |
| `templateId` | String | Data: e.g. `nbe.card_purchase.ar.v2` | yes | Latin, LTR |
| `appVersion` | String | Data: e.g. `1.0`, Western digits always | yes | — |
| `sample` | String | Data: a synthetic last-4 pattern from the institution template, e.g. `**1234` | yes | never a real SMS |
| `source` | String | Copy (`common_source_*`) or Data (`InstaPay`) | yes | — |
| `platform` | String | **Select** (`ios` / `other`) | — | — |
| `method` | String | **Select** (`faceId` / `touchId` / `fingerprint` / `face` / `other`) | — | — |
| `part` | String | **Select** (`morning` / `afternoon` / `evening` / `other`) | — | — |
| `account` | String | Data: an account label (a card without its last-4, or Cash / Wallet) | yes | Part 2 |
| `alt` | String | Money | yes | Smart ROI: the alternative's monthly cost |
| `amount2` | String | Money | yes | second amount in a sentence |
| `assetType` | String | Copy (`common_assetType_*`) | no | words only |
| `assetType2` | String | Copy (`common_assetType_*`) | no | words only |
| `average` | String | Money | yes | an average for a period |
| `balance` | String | Money | yes | a card balance owed |
| `budget` | String | Money | yes | a budget total |
| `card2` | String | Data, as `card` | yes | second card in a sentence |
| `category2` | String | Data, as `category` | yes | second category in a sentence |
| `cost` | String | Money | yes | EGP cost of a Zakah amount |
| `cycleDay` | String | Digits | yes | day number inside the cycle |
| `days` | String | Digits | yes | a length in days (the hawl) |
| `debts` | String | Money | yes | debts due now |
| `delta` | String | Money | yes | an absolute difference. The direction comes from `trend` |
| `due` | String | Money | yes | amount due |
| `dueNative` | String | Copy (`common_unit_grams`) or Money | yes | a Zakah amount in its own unit |
| `endAmount` | String | Money | yes | end of a range |
| `startAmount` | String | Money | yes | start of a range |
| `exampleRate` | String | Digits (+ `٪`/`%`) | yes | Smart ROI example rate, never a quote |
| `gap` | String | Money | yes | how far over a limit or an income |
| `grams` | String | Copy (`common_unit_grams`) | yes | a weight of gold |
| `hijri` | String | Date (Hijri calendar, digits per mode) | yes | a Hijri date |
| `idle` | String | Money | yes | idle cash |
| `item` | String | Data (a bill or installment name) | yes | — |
| `karat` | String | Digits | yes | `24`, `21` or `18` |
| `list` | String | Copy: items joined with the locale list format | yes | "name amount" items |
| `lot` | String | Copy (`zakah_main_lot*`) | yes | one asset line |
| `merchant2` | String | Data, as `merchant` | yes | — |
| `merchant3` | String | Data, as `merchant` | yes | — |
| `month` | String | Date (month name) | yes | — |
| `month2` | String | Date (month name) | yes | — |
| `monthly` | String | Money | yes | a monthly amount |
| `needsPct` | String | Digits (+ `٪`/`%`) | yes | share of needs |
| `savingsPct` | String | Digits (+ `٪`/`%`) | yes | share of savings |
| `wantsPct` | String | Digits (+ `٪`/`%`) | yes | share of wants |
| `percent2` | String | Digits (+ `٪`/`%`) | yes | second percentage in a sentence |
| `utilisation` | String | Digits (+ `٪`/`%`) | yes | credit limit use |
| `orders` | String | Copy (`common_unit_orders`) | yes | contains a number |
| `visits` | String | Copy (`common_unit_visits`) | yes | contains a number |
| `times` | String | Copy (`common_unit_visits` or `common_unit_orders`) | yes | contains a number |
| `payout` | String | Money | yes | a certificate payout |
| `peakDay` | String | Date (weekday name) | yes | — |
| `peakDay2` | String | Date (weekday name) | yes | — |
| `perDay` | String | Money | yes | per-day amount |
| `previous` | String | Money | yes | the same figure in the previous period |
| `price` | String | Money | yes | a price per gram |
| `principal` | String | Money | yes | a certificate principal |
| `projected` | String | Money | yes | an end-of-period projection |
| `remaining` | String | Digits | yes | uses left |
| `saved` | String | Money | yes | amount saved |
| `span` | String | Copy (`chat_period_*`) | yes | a period inside a sentence (can contain a number) |
| `spanB` | String | Copy (`chat_period_*`) | yes | the period compared against |
| `status` | String | Copy (`recurring_bills_*` or `zakah_main_status*`) | yes | — |
| `subject` | String | Data: a category, a merchant, or the word for "overall" | yes | — |
| `subs` | String | Money | yes | subscription cost |
| `sum` | String | Money | yes | a sum of one currency |
| `target` | String | Money | yes | a suggested amount |
| `text` | String | Data (a chat bubble's text) | yes | screen-reader labels |
| `value` | String | Money | yes | a valuation |
| `year1` | String | Money | yes | Smart ROI, year one |
| `year2` | String | Money | yes | Smart ROI, year two |
| `yearly` | String | Money | yes | a yearly amount |
| `need` | String | **Select** (`cycle` / `months` / `accounts` / `installments` / `subscriptions` / `other`) | — | S-21 empty explainer |
| `state` | String | **Select**, branches listed in each key's note | — | wording variant |
| `trend` | String | **Select** (`up` / `down` / `other`) | — | direction against a comparison; `other` = about the same |
| `years` | String | **Select** (`two` / `other`) | — | Smart ROI projection length |

ARB type for every Select placeholder is String (gen-l10n requirement).

### 0.4 Plurals (ICU, gen-l10n)
- A plural message takes two placeholders. `count` (**int**) only selects the form and is **never printed**. `n` (**String**, formatted by the digits layer) is printed.
- **Arabic must supply `=1`, `=2`, `few` (3–10, 103–110, …), `many` (11–99, …) and `other` (100–102, …)** on every plural. Write `=1`/`=2` as exact matches rather than CLDR `one`/`two`. gen-l10n maps `=0`/`=1`/`=2` to `Intl.plural`'s zero/one/two arguments, which match exactly before CLDR rules apply.
- **`=0` is required, in both AR and EN, on every plural whose count can be 0.** Without it, zero falls through to `other` («٠ حركة» / "0 transactions").
- **Plurals where 0 can't occur** (no `=0` branch, and the T-029 parity test exempts them from the zero check):

| Key | Why 0 is impossible |
|---|---|
| `common_cardFilter_count` | shown only when 2+ cards are selected |
| `common_period_lastMonths`, `common_period_inLastMonths` | depth 6–24 (A-11); trend window 6 |
| `common_validation_nameLength`, `common_validation_noteLength` | count = the fixed maximum (30 / 200) |
| `onboarding_iosSetup_checkCount` | count = automations in the package, ≥ 1 |
| `onboarding_scanResults_found` | S-06 is skipped when the scan found 0 |
| `onboarding_scanResults_cardSubtitle` | a card is auto-created from ≥ 1 message |
| `home_prompt_finishSetupSteps` | the card shows only while ≥ 1 step is skipped |
| `home_banner_review` | the pill shows only when count > 0 |
| `home_banner_shortcutsQuiet` | shown only after ≥ 7 quiet days (FR-ING-I-07) |
| `transactions_list_bulkChanged`, `transactions_list_bulkDeleteTitle`, `transactions_list_bulkDeleted` | selection mode needs ≥ 1 selected row |
| `categorization_rule_applyPast` | the checkbox is hidden when count = 0 |
| `transfers_assign_empty` | count = the fixed window (60 days) |
| `accounts_overview_moreCurrencies` | shown only when an account holds 2+ currencies |
| `accounts_compare_max` | count = the fixed maximum (6, UX-A-03) |
| `common_date_hoursAgo`, `transfers_link_afterHours`, `transfers_link_beforeHours` | hours are used only for gaps of 1–23 h; a smaller gap uses minutes |
| `capture_stopTracking_delete`, `capture_stopTracking_deleteTitle` | the delete option is hidden when the card has no transactions |
| `common_unit_visits`, `common_unit_orders` | inserted only for a count of 1 or more |
| `budget_overview_daysLeft` | the cycle includes today, so at least 1 |
| `recurring_bills_dueIn`, `recurring_bills_overdue` | 0 days is `recurring_bills_dueToday`; overdue starts at 1 |
| `voice_logger_parsedTitle`, `voice_logger_save`, `voice_logger_saved` | a save needs at least 1 item |
| `wealth_overview_unitCoins` | the line shows only when coins are held |
| `accounts_overview_hiddenCount` | the row exists only while 1 or more accounts are hidden |
| `zakah_main_dueIn` | 0 days shows `zakah_main_hawlDone` instead |
| `chat_main_tooLong` | count = the fixed maximum (300) |
| `chat_period_lastMonths`, `chat_period_nextDays` | a window of 1 or more |
| `roi_tips_badgeA11y` | the badge shows only when count > 0 |

- Every plural row's note states `count:int, n` plus its other placeholders.
- Egyptian noun forms used throughout:

| Noun | =1 | =2 | few | many / other |
|---|---|---|---|---|
| حركة | حركة واحدة | حركتين | {n} حركات | {n} حركة |
| كارت | كارت واحد | كارتين | {n} كروت | {n} كارت |
| يوم | يوم | يومين | {n} أيام | {n} يوم |
| شهر | شهر | شهرين | {n} شهور | {n} شهر |
| دقيقة | دقيقة | دقيقتين | {n} دقايق | {n} دقيقة |
| خطوة | خطوة واحدة | خطوتين | {n} خطوات | {n} خطوة |
| رسالة | رسالة واحدة | رسالتين | {n} رسايل | {n} رسالة |
| ساعة | ساعة | ساعتين | {n} ساعات | {n} ساعة |
| حرف | حرف واحد | حرفين | {n} حروف | {n} حرف |
| عملة | عملة واحدة | عملتين | {n} عملات | {n} عملة |

- English supplies `=1` and `other`, plus `=0` where the zero case reads differently.
- **AR and EN use the same placeholder set for every key.** gen-l10n declares placeholders once, in the template (`app_ar.arb`). If one language doesn't need a placeholder, it still uses the same ICU structure.
- `select` is used for platform (`ios` / `other`), biometric method and time of day. Every select has an `other` branch.

### 0.5 Digits, money, dates
- **AR**: Arabic-Indic digits by default (`٠-٩`, decimal `٫`, grouping `٬`); Western when the user picks «123» (A-29). **EN**: Western always.
- Currency: `ج.م` after the amount in figures and «جنيه» in sentences. Other currencies use the ISO code (`USD`). **EN**: `EGP 1,200`. Symbols (`$ £ €`) appear only in a transaction's original-amount line.
- Converted figures start with `≈` and carry the caption `common_currency_approxCaption`. Copy never adds amounts in different currencies (CLAUDE.md §2.4).
- Card last-4, IPA handles, ISO codes, template IDs and app versions always stay in Western digits and Latin script, and are never mirrored (`04-design-system.md` §2.8).

### 0.6 RTL and bidi
- Arabic is the reference layout. Copy that sits inside a mirrored layout must not depend on the direction of arrows. Avoid `←`/`→` in Arabic body text: write «وبعدين» or «لـ» instead. English may use `→`.
- Every placeholder marked **Isolate: yes** in the registry (§0.3a) is wrapped in a Unicode first-strong isolate (U+2068 … U+2069) by the presentation layer, **not** in the ARB text. That keeps `−٤٥٠ ج.م` and `•4567` from reordering inside Arabic sentences (`04-design-system.md` §2.3 "Bidi").
- Latin brand names written literally in Arabic strings (Wise, Revolut, Payoneer, Apple Pay, Google Drive, iCloud, Shortcuts, Face ID) are single runs and safe without isolates. If a string ends with a Latin word followed by punctuation, check it in the RTL golden test.
- Elements that **do not mirror**: the mascot, checkmarks ✓, clock icons, card last-4, phone numbers, chart values. **Chart time axes do mirror** (UX-D-01).

### 0.7 Length classes (Notes column)
Measured in characters, including spaces, at 100% text scale. Layouts must still survive 130% (NFR-UX-02).

| Class | Use | AR max | EN max |
|---|---|---|---|
| **B** | Filled or outlined button (≤ 3 words, `06-voice-and-tone.md` §1.3) | 20 | 22 |
| **C** | Chip, badge, tab, segment | 16 | 16 |
| **L** | Field label, list-row title, KPI label | 28 | 30 |
| **T** | Screen or sheet title, headline | 40 | 44 |
| **S** | Sentence or body (one to two lines) | 120 | 130 |
| **M** | Mascot bubble (C-14) | 120 | 130 |
| **N** | Snackbar, toast or banner (one line plus action) | 70 | 75 |
| **E** | Chart explanation, chat answer, consent or rule text (two to three sentences, Part 2) | 220 | 240 |
| **A** | Screen-reader only (not shown) | — | — |

Text buttons and links (no fill or outline) use class **L**. A string tagged with two classes ("T · M") must fit the smaller limit. Placeholder values aren't counted. Where a placeholder is long (a merchant or card name), the UI truncates the placeholder, not the copy.

### 0.8 Tone gates (checked per string in review)
1. **No jokes and no emoji** on errors, permissions, payments or money confirmations, destructive dialogs, backup passphrases, or the Gold purchase (FR-L10N-04).
2. **At most one emoji per string**, and only in mascot lines, greetings, success messages and empty states (`06-voice-and-tone.md` §4). `✓` counts as a symbol, not an emoji.
3. Humour targets **spending, never the person**: nothing about the user's body, family, religion, region, gender or politics.
4. Never claim "no server". The claim is always about **financial data** staying on the phone (R-11, CLAUDE.md §9).
5. Use the masculine-generic forms Egyptians commonly use («إنت», «يا كبير»), and prefer a neutral wording where an easy one exists.

### 0.9 Mascot lines
A mascot line names its **Rive state** (`ZaghlolAvatar` input: `tourGuide`, `proud`, `shocked`, `detective`, `professor`, `listening`, plus the D-35 motion states `thinking`, `scanning`, `counting`, `saved`, `payday`, `oops`, `sleep`, `pull`, `tap`) and its **trigger** (an SRS rule ID or a UI event). Only one Zaghlol appears per screen. With reduce motion on, the same line shows next to the still pose (FR-MAS-03). The `oops` state never carries a joke: it shows the error copy of the screen it appears on.

### 0.10 How the parts fit together
- **Part 1 (T-026)** owns §0, the `common_*` and `mascot_*` keys defined below, and screens S-01…S-06, S-10…S-16, S-40…S-43, S-61, S-62.
- **Part 2 (T-027)** and **Part 3 (T-028)** append their sections below their markers. They reuse `common_*` keys and don't redefine them; a new shared key goes into that part's own `common_*` subsection.
- **Reuse rule:** a generic action ("Save", "Cancel", "Delete", "Confirm", "Edit", "Dismiss", "Send", "Link", "Yes/No", "Undo", "Try again") always uses its `common_action_*` key. A screen key with the same text as a common key is allowed only for a **field, section or bar label that belongs to that screen** and may be reworded separately (e.g. `transactions_edit_category` and `transactions_list_bulkCategory` both read «التصنيف»).
- **Part 3** owns the error catalogue that maps `Failure` codes to copy.
- **ARB generation (T-029/T-087):** keep gen-l10n `use-escaping: false` (the default), so apostrophes in EN ("doesn't", "{name}'s") stay literal. Run `flutter gen-l10n` early on `transfers_split_shareA11y`, which puts an apostrophe right after a closing brace. The three `common_error_*` keys in Part 1 are the generic fallbacks used by Part 1 screens, and Part 3 may point Failure codes at them.

---

# PART 1 — T-026: onboarding, capture, Home, transactions, review, accounts

## 1.0 Approach (design note, C3)
- **Scope**: every user-visible string on S-01…S-06 (there is no S-07…S-09 in the inventory), S-10…S-16, S-40…S-43, S-61 and S-62. That includes the sub-steps those specs define: S-43 create mode (type, then bank, then details, then "added"), S-41's empty state, the request-bank sheet, the "don't track" sheet, the re-scan sheet, the supported-banks list and the share/paste how-to.
- Each string covers every state in its spec: first-run or empty, loading, populated, error, offline, permission denied and Gold-locked.
- **Not in scope**: category names (catalog data, FR-CAT-01, localized in the catalog seed); bank and merchant names (registry data); the Failure-code error catalogue, Gold, backup settings, legal text and notifications (Part 3); and chart, budget, voice and chat copy (Part 2).
- **Sources**: wording from the approved mockups is reused when it already follows the voice. Where a screen spec and the SRS differ, the SRS wins, and each such case is listed in §1.Q.
- **No new features.** Where a state needs copy that no spec has written yet (for example a safe-to-spend of zero), the string is drafted and flagged in §1.Q.
- **Machine-friendly**: one key per row, ICU text written out in full, and placeholder types per §0.3/§0.4, so T-029 can transcribe the tables mechanically.

---

## 1.1 Shared — `common_*`

### Actions
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_action_save` | احفظ | Save | B |
| `common_action_cancel` | إلغاء | Cancel | B |
| `common_action_done` | تمام | Done | B · closes a sheet |
| `common_action_confirm` | تمام | Confirm | B · glossary «تمام» |
| `common_action_dismiss` | سيبها | Dismiss | B · glossary «سيبها» |
| `common_action_undo` | تراجع | Undo | B · snackbar action, 5 s (C-19) |
| `common_action_tryAgain` | جرّب تاني | Try again | B |
| `common_action_skip` | تخطّي | Skip | B · stepper header |
| `common_action_continue` | كمّل | Continue | B |
| `common_action_notNow` | مش دلوقتي | Not now | B |
| `common_action_later` | بعدين | Later | B |
| `common_action_edit` | عدّل | Edit | B |
| `common_action_delete` | امسح | Delete | B · destructive variant |
| `common_action_close` | اقفل | Close | B |
| `common_action_backA11y` | رجوع | Back | A |
| `common_action_moreA11y` | اختيارات تانية | More options | A · ⋮ menu |
| `common_action_seeAll` | شوف الكل | See all | B · glossary |
| `common_action_clearFilter` | شيل الفلتر | Clear filter | B |
| `common_action_openSettings` | افتح الإعدادات | Open settings | B · opens OS settings |
| `common_action_fix` | صلّحها | Fix | B |
| `common_action_yes` | أيوه | Yes | B |
| `common_action_no` | لأ | No | B |
| `common_action_select` | اختار | Select | B · S-11 nav bar |
| `common_action_selectAll` | اختار الكل | Select all | B |
| `common_action_send` | ابعت | Send | B |
| `common_action_link` | اربط | Link | B |
| `common_action_unlink` | فك الربط | Unlink | B |
| `common_action_more` | المزيد | More | C |
| `common_action_show` | اظهر | Show | C · passphrase reveal |
| `common_action_hide` | اخفي | Hide | C |
| `common_action_learnMore` | اعرف أكتر | Learn more | B |
| `common_action_searchA11y` | دوّر | Search | A |

### Discard dialog (N-03)
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_discard_title` | تسيب اللي كتبته؟ | Discard changes? | T |
| `common_discard_body` | اللي ما اتحفظش هيروح. | Anything you haven't saved will be lost. | S |
| `common_discard_confirm` | متحفظش | Discard | B · destructive |
| `common_discard_keep` | كمّل تعديل | Keep editing | B |

### Navigation and app bar
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_nav_home` | الرئيسية | Home | C · tab 1 |
| `common_nav_insights` | الحسبة | Insights | C · tab 2. Glossary (D-34) replaces «التحليلات» in `03-navigation.md`, see Q-01 |
| `common_nav_money` | فلوسي | Money | C · tab 4 |
| `common_nav_zaghlol` | زغلول | Zaghlol | C · tab 5 |
| `common_nav_addA11y` | سجّل بسرعة | Quick add | A · gold Add button (C-02) |
| `common_nav_settingsA11y` | الإعدادات | Settings | A · Home gear |

### Card filter (C-08) and currency switcher (C-09)
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_cardFilter_all` | كل الكروت | All cards | C |
| `common_cardFilter_count` | `{count, plural, =1{كارت واحد} =2{كارتين} few{{n} كروت} many{{n} كارت} other{{n} كارت}}` | `{count, plural, =1{1 card} other{{n} cards}}` | C · count:int, n · shown when 2+ cards are selected |
| `common_cardFilter_sheetTitle` | تشوف أنهي كروت؟ | Show which cards? | T |
| `common_cardFilter_clearA11y` | شيل فلتر الكروت | Clear card filter | A |
| `common_cardFilter_activeA11y` | الفلتر شغال: {cards} | Filter on: {cards} | A |
| `common_currency_approxChip` | ≈ {currency} | ≈ {currency} | C · currency = ISO code or «ج.م» |
| `common_currency_approxCaption` | تقريبي بسعر {date} | Approx. at {date} rate | L · FR-CUR-04 |
| `common_currency_approxA11y` | تقريباً | approximately | A · read before a ≈ amount |
| `common_badge_stale` | سعر قديم | Out of date | C · C-21, older than 24 h |
| `common_badge_staleA11y` | السعر ده عدى عليه أكتر من يوم | This rate is more than a day old | A |
| `common_money_maskedA11y` | المبلغ مخفي | Amount hidden | A · C-04 masked `•••` |
| `common_money_currencyPagerA11y` | صفحة {index} من {total}: {currency} | Page {index} of {total}: {currency} | A · C-11 pager |

### Sources (C-21 badge, FR-TXN-03)
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_source_sms` | رسالة SMS | SMS | C |
| `common_source_notification` | إشعار | Notification | C |
| `common_source_applePay` | Apple Pay | Apple Pay | C |
| `common_source_shortcut` | اختصار | Shortcut | C |
| `common_source_scan` | صورة | Scan | C · OCR |
| `common_source_statement` | كشف حساب | Statement | C · PDF / online-bank file |
| `common_source_csv` | ملف CSV | CSV | C |
| `common_source_voice` | صوت | Voice | C |
| `common_source_manual` | بإيدك | Manual | C |
| `common_source_shared` | رسالة اتبعتت | Shared message | C · share/paste, FR-ING-A-04. Maps to DB `source = 'share'` (`database-schema.md`; Q-02 closed) |

### Transaction types
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_txnType_expense` | مصروف | Expense | C |
| `common_txnType_income` | دخل | Income | C |
| `common_txnType_transfer` | تحويل | Transfer | C |
| `common_txnType_internal` | تحويلة لنفسك | To yourself | C |
| `common_txnType_refund` | مرتجع | Refund | C · from a merchant (BR-XFR-08) |
| `common_txnType_reimbursement` | فلوس راجعة | Money back | C · from people (BR-XFR-08) |
| `common_txnType_declined` | اترفضت | Declined | C |

### Account types (FR-ACC-01)
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_accountType_debit` | ديبت | Debit | C |
| `common_accountType_credit` | كريدت | Credit | C |
| `common_accountType_account` | حساب بنك | Bank account | C |
| `common_accountType_wallet` | محفظة | Wallet | C |
| `common_accountType_bnpl` | تقسيط | Pay later | C |
| `common_accountType_cash` | كاش | Cash | C · default account FR-ACC-03 |
| `common_accountType_multiCurrency` | أكتر من عملة | Multi-currency | C |

### Capture channels (shared by S-41, S-43, S-61, S-62)
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_channel_sms` | رسايل البنك | Bank SMS | L |
| `common_channel_smsShort` | الرسايل | SMS | C · compact status row |
| `common_channel_notifications` | إشعارات التطبيقات | App notifications | L · Android only |
| `common_channel_notificationsShort` | الإشعارات | Notifications | C |
| `common_channel_applePay` | Apple Pay | Apple Pay | L · iOS only |
| `common_channel_onA11y` | شغال | on | A |
| `common_channel_offA11y` | مقفول | off | A |

### Dates, periods, progress, units
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_date_today` | النهارده | Today | C |
| `common_date_yesterday` | امبارح | Yesterday | C |
| `common_date_justNow` | دلوقتي | Just now | C |
| `common_date_minutesAgo` | `{count, plural, =0{دلوقتي} =1{من دقيقة} =2{من دقيقتين} few{من {n} دقايق} many{من {n} دقيقة} other{من {n} دقيقة}}` | `{count, plural, =0{Just now} =1{1 min ago} other{{n} min ago}}` | C · count:int, n · whole minutes, 0–59. `=0` (under one minute) reads the same as `common_date_justNow`, so callers pass 0 rather than switching keys. 60 or more → `common_date_hoursAgo` |
| `common_date_hoursAgo` | `{count, plural, =1{من ساعة} =2{من ساعتين} few{من {n} ساعات} many{من {n} ساعة} other{من {n} ساعة}}` | `{count, plural, =1{1 hr ago} other{{n} hr ago}}` | C · count:int, n · whole hours, 1–23; 24 or more → `{date}`. 0 can't occur (that's minutes), so no `=0` (listed in §0.4) |
| `common_date_dateTime` | {date}، {time} | {date}, {time} | L |
| `common_date_range` | {start} – {end} | {start} – {end} | L · en dash; RTL reads start first (from the right) |
| `common_period_thisCycle` | الدورة دي | This cycle | C |
| `common_period_lastCycle` | الدورة اللي فاتت | Last cycle | C |
| `common_period_thisMonth` | الشهر ده | This month | C |
| `common_period_pickMonth` | شهر معين | A month | C |
| `common_period_custom` | من تاريخ لتاريخ | Custom range | C |
| `common_period_lastMonths` | `{count, plural, =1{آخر شهر} =2{آخر شهرين} few{آخر {n} شهور} many{آخر {n} شهر} other{آخر {n} شهر}}` | `{count, plural, =1{Last month} other{Last {n} months}}` | C · count:int, n · scan depth A-11 |
| `common_period_inLastMonths` | `{count, plural, =1{في آخر شهر} =2{في آخر شهرين} few{في آخر {n} شهور} many{في آخر {n} شهر} other{في آخر {n} شهر}}` | `{count, plural, =1{in the last month} other{in the last {n} months}}` | L · count:int, n · inserted mid-sentence as `{period}` |
| `common_progress_percent` | {n}٪ | {n}% | C · n = formatted number without its sign |
| `common_fileSize_mb` | {n} ميجا | {n} MB | C |
| `common_fileSize_kb` | {n} كيلو | {n} KB | C |
| `common_platform_android` | أندرويد | Android | C |
| `common_platform_ios` | آيفون | iPhone | C |

### Validation (`04-design-system.md` §5.6; inline under the field)
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_validation_amountRequired` | اكتب مبلغ أكبر من صفر | Enter an amount above zero | S |
| `common_validation_amountTooLarge` | المبلغ ده كبير أوي، راجعه | That amount looks too big — check it | S · more than 12 integer digits |
| `common_validation_amountDecimals` | `{count, plural, =0{{currency} مفيهوش كسور} =1{{currency} بيقبل رقم واحد بعد العلامة} =2{{currency} بيقبل رقمين بس بعد العلامة} few{{currency} بيقبل {n} أرقام بس بعد العلامة} many{{currency} بيقبل {n} رقم بعد العلامة} other{{currency} بيقبل {n} رقم بعد العلامة}}` | `{count, plural, =0{{currency} doesn't use decimals} =1{{currency} allows 1 decimal} other{{currency} allows {n} decimals}}` | S · count:int = currency exponent, n, currency |
| `common_validation_currencyRequired` | اختار العملة | Choose a currency | S |
| `common_validation_dateFuture` | التاريخ ميكونش في المستقبل | Date can't be in the future | S |
| `common_validation_dateRange` | تاريخ البداية لازم يبقى قبل النهاية | Start date must be before the end date | S |
| `common_validation_last4` | اكتب آخر أربع أرقام | Enter the last four digits | S |
| `common_validation_nameRequired` | اكتب اسم | Enter a name | S |
| `common_validation_nameLength` | `{count, plural, =1{الاسم ميزيدش عن حرف واحد} =2{الاسم ميزيدش عن حرفين} few{الاسم ميزيدش عن {n} حروف} many{الاسم ميزيدش عن {n} حرف} other{الاسم ميزيدش عن {n} حرف}}` | `{count, plural, =1{Keep it to 1 character} other{Keep it to {n} characters}}` | S · count:int = max (30), n |
| `common_validation_nameTaken` | الاسم ده مستخدم قبل كده | That name's already used | S |
| `common_validation_noteLength` | `{count, plural, =1{الملاحظة ميزيدش عن حرف واحد} =2{الملاحظة ميزيدش عن حرفين} few{الملاحظة ميزيدش عن {n} حروف} many{الملاحظة ميزيدش عن {n} حرف} other{الملاحظة ميزيدش عن {n} حرف}}` | `{count, plural, =1{Notes can be up to 1 character} other{Notes can be up to {n} characters}}` | S · count:int = 200, n |
| `common_validation_categoryRequired` | اختار التصنيف | Choose a category | S |
| `common_validation_accountRequired` | اختار الحساب | Choose an account | S |
| `common_validation_choiceRequired` | اختار واحدة | Pick one | S · radio groups |

### Generic errors (fallbacks; Part 3 maps Failure codes)
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_error_loadFailed` | مقدرتش أفتح ده دلوقتي. بياناتك في أمان على موبايلك. | Couldn't load this right now. Your data is safe on this phone. | S · C-29, DB read failure; uses `common_action_tryAgain` |
| `common_error_saveFailed` | محصلش حفظ. جرّب تاني، واللي كتبته لسه موجود. | Couldn't save. Try again — what you entered is still here. | S · the form is kept |
| `common_error_network` | مش قادر أوصل للسيرفر دلوقتي. فلوسك في أمان على موبايلك، جرّب تاني كمان شوية. | Can't reach the server right now. Your money data is safe on this phone — try again in a bit. | S · `06-voice-and-tone.md` §2 |

### Gold lock (C-16 / C-13 locked, `04-design-system.md` §5.4)
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_gold_badge` | جولد | Gold | C · always paired with the crown icon |
| `common_gold_unlock` | افتحها مع جولد | Unlock with Gold | B · opens S-68 |
| `common_gold_lockedA11y` | متاحة في زغلول جولد | Available with Zaghlol Gold | A |

## 1.2 Shared mascot lines — `mascot_*`
| Key | AR | EN | Notes |
|---|---|---|---|
| `mascot_avatar_labelA11y` | الكابتن زغلول | Captain Zaghlol | A · label on every `ZaghlolAvatar` |
| `mascot_pull_refreshingA11y` | بحدّث… | Refreshing… | A · Rive `pull`, pull to refresh on Home and lists |
| `mascot_saved_line1` | اتسجلت ✓ | Saved ✓ | N · Rive `saved` · after saving a transaction (S-13 or Quick add). Picked at random from line1…3 |
| `mascot_saved_line2` | تمام، حطيتها في الحسبة ✓ | Done — it's in the books ✓ | N · Rive `saved` |
| `mascot_saved_line3` | اتقيدت يا كبير ✓ | Logged it ✓ | N · Rive `saved` |
| `mascot_tap_line1` | إيه يا عم، بتزغزغني؟ 😄 | Hey, that tickles! 😄 | M · Rive `tap` · user taps Zaghlol. The next unused line rotates each tap |
| `mascot_tap_line2` | أنا هنا يا كبير، وفلوسك في عينيّا | Still here, keeping an eye on your money | M · Rive `tap` |
| `mascot_tap_line3` | كل قرش بتحوشه بيطلّعلي ريشة جديدة 🪶 | Every bit you save grows me a new feather 🪶 | M · Rive `tap` · currency-neutral (F-20) |
| `mascot_tap_line4` | الكابتن جاهز، وإنت القائد | Captain reporting. You're the boss. | M · Rive `tap` |
| `mascot_tap_line5` | اللي يحوش النهارده يتفسح بكره | Save today, treat yourself tomorrow | M · Rive `tap` |
| `mascot_tap_line6` | أنا بقرا رسايل البنوك بس، الباقي مش شغلي | I only read bank messages. The rest is none of my business. | M · Rive `tap` · also restates the privacy promise |
| `mascot_tap_line7` | حمامة ولا محاسب؟ الاتنين! | Pigeon or accountant? Both. | M · Rive `tap` |
| `mascot_tap_line8` | جناحي سريع وحساباتي مظبوطة | Quick wings, tidy numbers | M · Rive `tap` |

Part 2 may append `mascot_tap_line9` onward. The motion states `scanning`, `counting`, `payday`, `oops` and `sleep` carry no copy of their own: they use the line of the screen they appear on (scan banner, restore progress, Home payday banner, error copy, empty state).

---

## 1.3 S-01 Welcome & privacy — `onboarding_welcome_*`
States: static. Language switches immediately (FR-L10N-01). No "no server" claim (R-11).

| Key | AR | EN | Notes |
|---|---|---|---|
| `onboarding_welcome_languageToggle` | English | عربي | C · each locale shows the **other** language's name, in that language's own script |
| `onboarding_welcome_languageToggleA11y` | غيّر اللغة للإنجليزي | Switch to Arabic | A |
| `onboarding_welcome_title` | أهلاً بيك! أنا الكابتن زغلول | Hi! I'm Captain Zaghlol. | T · M · Rive `tourGuide`, first launch (FR-MAS-01). Waves once; still pose with reduce motion |
| `onboarding_welcome_subtitle` | هعرفك فلوسك بتروح فين من رسايل البنك، من غير ما تكتب حاجة. | I'll show you where your money goes — straight from your bank messages, no typing needed. | S |
| `onboarding_welcome_pointOnPhone` | بيانات فلوسك بتفضل على موبايلك | Your money data stays on your phone | S · FR-ONB-01, with a lock icon (not an emoji) |
| `onboarding_welcome_pointNoPassword` | مش هنطلب باسورد البنك أبداً | We'll never ask for your bank password | S |
| `onboarding_welcome_pointNoAds` | من غير إعلانات | No ads | L |
| `onboarding_welcome_start` | يلا نبدأ | Let's go | B · primary. Opens S-02 or S-03 |
| `onboarding_welcome_restore` | استخدمت زغلول قبل كده | I already use Zaghlol | L · text button, opens S-04 (FR-ONB-12). Gender-neutral (F-15) |
| `onboarding_welcome_privacyLink` | تفاصيل الخصوصية | Privacy details | L · text link, opens S-71 read-only |

## 1.4 S-02 Capture setup — Android — `onboarding_androidSetup_*`
States: step 1 (SMS) · granted · denied/degraded · Play-unavailable · step 2 (notifications + live scan) · notification access returned on/off · scan error (shown on Home).

| Key | AR | EN | Notes |
|---|---|---|---|
| `onboarding_androidSetup_step` | خطوة {step} من {total} | Step {step} of {total} | C · C-26 stepper header |
| `onboarding_androidSetup_smsTitle` | خليني أقرا رسايل البنك | Let me read your bank texts | T · M · Rive `tourGuide`, setup step |
| `onboarding_androidSetup_smsSubtitle` | وهرتبلك كل مصاريفك لوحدي. | I'll sort out all your spending for you. | S |
| `onboarding_androidSetup_smsPointSenders` | بقرا رسايل البنوك والمحافظ وإنستاباي بس | I only read messages from banks, wallets and InstaPay | S · what is read (FR-ING-A-02) |
| `onboarding_androidSetup_smsPointPersonal` | رسايلك الشخصية عمرها ما بتتقري ولا بتتحفظ | Your personal messages are never read or saved | S |
| `onboarding_androidSetup_smsPointOnPhone` | بيانات فلوسك بتفضل على الموبايل ده | Your money data stays on this phone | S · claim limited to financial data (tone gate 4, R-11, BR-SYNC-03) |
| `onboarding_androidSetup_smsAllow` | اسمح بقراية الرسايل | Allow bank texts | B · primary, opens the system SMS dialog |
| `onboarding_androidSetup_smsGranted` | الرسايل اتسمحت ✓ | SMS allowed ✓ | N · success |
| `onboarding_androidSetup_scanTitle` | بقرا رسايلك القديمة… | Reading your past messages… | L · Rive `scanning` (loops while the scan runs) |
| `onboarding_androidSetup_scanDepth` | {period} · كمّل وأنا شغال | {period} · carry on, I'm on it | S · period = `common_period_lastMonths` (A-11 default 6) |
| `onboarding_androidSetup_scanCount` | `{count, plural, =0{لسه بدوّر…} =1{لقيت حركة واحدة} =2{لقيت حركتين} few{لقيت {n} حركات} many{لقيت {n} حركة} other{لقيت {n} حركة}}` | `{count, plural, =0{Still looking…} =1{Found 1 transaction} other{Found {n} transactions}}` | L · count:int, n · polite live region, announced at most every 5 s |
| `onboarding_androidSetup_scanBanks` | البنوك اللي لقيتها: | Banks found so far: | L · followed by bank chips (data) |
| `onboarding_androidSetup_notifTitle` | وكمان إشعارات تطبيقات البنوك؟ | Catch bank app notifications too? | T |
| `onboarding_androidSetup_notifBody` | في بنوك ومحافظ بتبعت إشعار في التطبيق بس من غير SMS، زي Wise وRevolut وPayoneer. | Some banks and wallets only send in-app alerts, not SMS — like Wise, Revolut and Payoneer. | S · FR-ING-A-03/07 |
| `onboarding_androidSetup_notifPrivacy` | بقرا إشعارات تطبيقات البنوك والمحافظ بس، مش الواتساب ولا أي حاجة تانية. | I only read notifications from bank and wallet apps — never WhatsApp or anything else. | S · what is read (FR-ING-A-03: registry apps only) |
| `onboarding_androidSetup_notifTurnOn` | شغّل الإشعارات | Turn on notifications | B · primary, opens OS notification access |
| `onboarding_androidSetup_notifOsHint` | في الشاشة الجاية، دوّر على «زغلول» وشغّله. | On the next screen, find Zaghlol and switch it on. | S · shown under the button |
| `onboarding_androidSetup_notifGranted` | الإشعارات اشتغلت ✓ | Notifications on ✓ | N · success, on return from OS |
| `onboarding_androidSetup_notifStillOff` | لسه مقفولة. تقدر تشغلها بعدين من الإعدادات. | Still off. You can turn it on later in Settings. | N · on return, still off. No blame |
| `onboarding_androidSetup_degradedTitle` | قراية الرسايل مقفولة | SMS reading is off | T · C-20 warning (FR-ING-A-05) |
| `onboarding_androidSetup_degradedBody` | لسه تقدر تتابع مصاريفك بطرق تانية: | You can still track your spending: | S |
| `onboarding_androidSetup_degradedNotif` | إشعارات تطبيقات البنوك | Bank app notifications | L · row action `onboarding_androidSetup_degradedNotifOn` |
| `onboarding_androidSetup_degradedNotifOn` | شغّلها | Turn on | B |
| `onboarding_androidSetup_degradedShare` | ابعت أو الزق رسالة البنك لزغلول | Share or paste a bank message | S · row action `onboarding_androidSetup_degradedShareHow` |
| `onboarding_androidSetup_degradedShareHow` | إزاي؟ | How? | L · text button · opens the `capture_shareHow_*` sheet |
| `onboarding_androidSetup_degradedManual` | سجّل الكاش بصوتك أو بإيدك | Log cash by voice or typing | L |
| `onboarding_androidSetup_degradedRetry` | اسمح تاني | Ask again | B · when the OS still allows a prompt |
| `onboarding_androidSetup_degradedSettingsHint` | علشان تشغلها، افتح الإعدادات واسمح لزغلول بالرسايل. | To turn it on, open Settings and allow Zaghlol to read SMS. | S · when the OS blocks re-prompting; with `common_action_openSettings` |
| `onboarding_androidSetup_playUnavailable` | النسخة دي من زغلول مش بتقرا SMS، بس الإشعارات والمشاركة شغالين تمام. | This version of Zaghlol can't read SMS, but notifications and sharing work fine. | S · `prodNoSms` flavour (ADR-004, `deployment.md`) (FR-ING-A-05). Where it appears is open, see Q-03 |

## 1.5 S-03 Capture setup — iOS — `onboarding_iosSetup_*`
States: step 1 · returned and checking (≤ 2 s) · Shortcuts app missing · step 2 all good / something missing / can't tell · step 3 first expense. iOS labels such as "Run Immediately" stay in English (see Q-04).

| Key | AR | EN | Notes |
|---|---|---|---|
| `onboarding_iosSetup_step` | خطوة {step} من {total} | Step {step} of {total} | C |
| `onboarding_iosSetup_shortcutTitle` | هنستخدم الاختصارات | We'll use Shortcuts | T · M · Rive `tourGuide` |
| `onboarding_iosSetup_shortcutWhy` | الآيفون مش بيسمح للتطبيقات تقرا الرسايل، فالاختصارات هي اللي هتبعتهالي. | iPhone doesn't let apps read texts, so Shortcuts pass them to me. | S · under the title. Split out of the title for length (F-7) |
| `onboarding_iosSetup_shortcutLead` | ضغطة واحدة بتضيف: | One tap adds: | L |
| `onboarding_iosSetup_shortcutSmsTitle` | رسايل البنك | Bank texts | L |
| `onboarding_iosSetup_shortcutSmsSub` | بيلقط رسايل البنوك وإنستاباي، عربي وإنجليزي | Catches bank and InstaPay texts, in Arabic and English | S |
| `onboarding_iosSetup_shortcutApplePayTitle` | مدفوعات Apple Pay | Apple Pay payments | L |
| `onboarding_iosSetup_shortcutApplePaySub` | بيسجل أي دفع بالموبايل في ساعتها | Logs every tap-to-pay as it happens | S |
| `onboarding_iosSetup_shortcutOnce` | مرة واحدة بس، وبعدها كل حاجة بتتسجل لوحدها. | Just once — then everything logs itself. | S |
| `onboarding_iosSetup_shortcutAdd` | ضيف اختصار زغلول | Add Zaghlol shortcut | B · primary, opens the Shortcuts import |
| `onboarding_iosSetup_howItWorks` | إزاي بيشتغل؟ (نص دقيقة) | How it works (30 sec) | L · text button, expands the steps below |
| `onboarding_iosSetup_howStep1` | لما توصلك رسالة من بنك، الآيفون بيشغّل الاختصار لوحده. | When a bank text arrives, your iPhone runs the shortcut by itself. | S · list numbers are drawn by the UI, not the copy |
| `onboarding_iosSetup_howStep2` | الاختصار بيدّي نص الرسالة لزغلول على نفس الموبايل، مش بيبعته لأي حد. | The shortcut hands the text to Zaghlol on this same phone — it isn't sent anywhere. | S · precise claim about the message, not "no server" |
| `onboarding_iosSetup_howStep3` | زغلول يقرا المبلغ والتاجر ويسجلها. خلاص كده. | Zaghlol reads the amount and merchant and logs it. That's it. | S |
| `onboarding_iosSetup_checking` | ثانية، بشوف الاختصارات اتضافت ولا لأ… | One sec — checking your shortcuts… | S · spinner, ≤ 2 s |
| `onboarding_iosSetup_shortcutsMissing` | مقدرتش أفتح تطبيق الاختصارات. نزّله من الـ App Store وجرّب تاني. | Couldn't open the Shortcuts app. Get it from the App Store and try again. | S · error, no joke |
| `onboarding_iosSetup_checkTitle` | تعالى نتأكد إن كله تمام | Let's make sure it all works | T |
| `onboarding_iosSetup_checkSubtitle` | زغلول بيبص على الاختصارات اللي اتضافت. | Zaghlol is checking which automations were added. | S |
| `onboarding_iosSetup_checkSmsAr` | رسايل البنوك (عربي) | Bank texts (Arabic) | L |
| `onboarding_iosSetup_checkSmsEn` | رسايل البنوك (إنجليزي) | Bank texts (English) | L |
| `onboarding_iosSetup_checkApplePay` | مدفوعات Apple Pay | Apple Pay payments | L |
| `onboarding_iosSetup_checkCount` | `{count, plural, =1{{done} من {n} أوتوميشن} =2{{done} من {n} أوتوميشن} few{{done} من {n} أوتوميشن} many{{done} من {n} أوتوميشن} other{{done} من {n} أوتوميشن}}` | `{count, plural, =1{{done} of 1 automation} other{{done} of {n} automations}}` | L · count:int = total, n, done. «أوتوميشن» doesn't change in AR; every form is written out for the parity test. Can't be 0 (§0.4) |
| `onboarding_iosSetup_checkNeedsRun` | محتاجة «Run Immediately» | Needs "Run Immediately" | L |
| `onboarding_iosSetup_checkOkA11y` | شغال | Working | A |
| `onboarding_iosSetup_checkMissingA11y` | ناقص | Missing | A |
| `onboarding_iosSetup_fixTitle` | إزاي تصلحها؟ | How to fix it | L |
| `onboarding_iosSetup_fixStep1` | افتح Shortcuts وبعدين Automation | Open Shortcuts, then Automation | S |
| `onboarding_iosSetup_fixStep2` | اختار «{automationName}» | Choose "{automationName}" | S · automationName is the Latin automation name, e.g. `Zaghlol – Wallet` |
| `onboarding_iosSetup_fixStep3` | شغّل «Run Immediately» | Turn on "Run Immediately" | S |
| `onboarding_iosSetup_checkUnknown` | مش متأكدين لسه؟ هنعرف أول ما توصلك رسالة بنك. | Can't tell yet — we'll know when your next bank text arrives. | S · no false failure (FR-ING-I-07) |
| `onboarding_iosSetup_checkAgain` | اتأكد تاني | Check again | B |
| `onboarding_iosSetup_checkAllGood` | كله تمام ✓ زغلول جاهز | All set ✓ Zaghlol is ready | N · success |
| `onboarding_iosSetup_firstTitle` | يلا نسجل أول مصروف! | Let's log your first expense! | T · M · Rive `tourGuide` (FR-ONB-09) |
| `onboarding_iosSetup_firstBody` | لحد ما توصل أول رسالة بنك، قولي صرفت إيه النهارده. | Until your first bank text comes in, tell me what you spent today. | S |
| `onboarding_iosSetup_firstSay` | قولها | Say it | B · opens S-31 |
| `onboarding_iosSetup_firstSayHint` | «دفعت خمسة وأربعين قهوة» | "45 on coffee" | L · spoken example. AR uses number words (§0.3) |
| `onboarding_iosSetup_firstType` | اكتبها | Type it | B · opens S-13 |
| `onboarding_iosSetup_firstTypeHint` | المبلغ والتصنيف | Amount and category | L |
| `onboarding_iosSetup_firstOnlineBanks` | بتستخدم Wise أو Revolut أو Payoneer؟ | Use Wise, Revolut or Payoneer? | S · opens S-61 supported banks (FR-ING-I-08) |
| `onboarding_iosSetup_firstOnlineBanksSub` | شوف إزاي تتابعهم على الآيفون | See how to track them on iPhone | S |
| `onboarding_iosSetup_firstStatement` | عندك كشف حساب؟ | Got a bank statement? | L · the `common_gold_badge` must show on this row (FR-EXP-04/06); Free opens S-68 |
| `onboarding_iosSetup_firstStatementSub` | ضيف شهور فاتت مرة واحدة مع جولد | Add past months in one go with Gold | S · says Gold in the text too, so Free users aren't promised it (F-8) |

## 1.6 S-04 Restore from backup — `backup_restore_*`
States: choose storage · signing in · searching · found (Free: one; Gold: up to 5) · passphrase wrong · restoring · empty · network error · newer version (EC-26) · corrupted · forgot passphrase (EC-27) · done (shown on Home). No jokes anywhere on this screen.

| Key | AR | EN | Notes |
|---|---|---|---|
| `backup_restore_title` | استرجاع نسخة | Restore from backup | T |
| `backup_restore_whereTitle` | النسخة بتاعتك فين؟ | Where's your backup? | T |
| `backup_restore_optionDrive` | Google Drive | Google Drive | L |
| `backup_restore_optionICloud` | iCloud | iCloud | L · iOS only |
| `backup_restore_signingIn` | بدخل على {provider}… | Signing in to {provider}… | S · button loading state during provider sign-in (F-5a) |
| `backup_restore_searching` | بدوّر على نسخة زغلول… | Looking for your Zaghlol backup… | S · spinner |
| `backup_restore_foundTitle` | لقيت نسخة | Backup found | T |
| `backup_restore_foundMeta` | {date} · {size} | {date} · {size} | L · size = `common_fileSize_mb` |
| `backup_restore_foundFrom` | من: {platform} · إصدار {appVersion} | From: {platform} · v{appVersion} | L · appVersion stays Latin, e.g. `1.0` |
| `backup_restore_versionsTitle` | النسخ اللي عندك | Your backups | L · Gold list, newest first |
| `backup_restore_versionNewest` | الأحدث | Newest | C |
| `backup_restore_passphraseLabel` | كلمة سر النسخة | Backup passphrase | L · C-32, single field |
| `backup_restore_restore` | استرجع | Restore | B · primary |
| `backup_restore_passphraseRequired` | اكتب كلمة السر | Enter the passphrase | S |
| `backup_restore_passphraseWrong` | كلمة السر دي مش بتفتح النسخة دي | That passphrase doesn't open this backup | S · unlimited retries |
| `backup_restore_forgotLink` | نسيت كلمة السر؟ | Forgot the passphrase? | L · text button |
| `backup_restore_forgotBody` | للأسف مش هينفع نرجّعها. النسخة مبتتفتحش غير بكلمة السر دي، ومحدش يقدر يفتحها من غيرها، ولا حتى إحنا. تقدر تبدأ من جديد. | Sorry, it can't be recovered. Only that passphrase opens this backup — nobody else can, not even us. You can start fresh. | S · EC-27, calm and plain |
| `backup_restore_restoring` | بسترجع بياناتك… | Restoring your data… | L · Rive `counting` + C-27 with `common_progress_percent` |
| `backup_restore_keepOpen` | سيب زغلول مفتوح لحد ما يخلص | Keep Zaghlol open until this finishes | S · no cancel once decryption has started |
| `backup_restore_emptyTitle` | مفيش نسخة زغلول على الحساب ده | No Zaghlol backup on this account | T · C-28 |
| `backup_restore_tryAnotherAccount` | جرّب حساب تاني | Try another account | B |
| `backup_restore_startFresh` | ابدأ من جديد | Start fresh | B · opens S-02 or S-03 |
| `backup_restore_errorNetwork` | مش قادر أوصل لـ {provider} دلوقتي. اتأكد من النت وجرّب تاني. | Can't reach {provider} right now. Check your connection and try again. | S · offline / network. provider = Google Drive or iCloud |
| `backup_restore_errorSignIn` | الدخول على {provider} ما كملش. جرّب تاني. | Signing in to {provider} didn't finish. Try again. | S |
| `backup_restore_errorNewer` | النسخة دي معمولة بإصدار أحدث من زغلول. حدّث التطبيق الأول. | This backup was made with a newer Zaghlol. Update the app to restore it. | S · EC-26 |
| `backup_restore_update` | حدّث زغلول | Update Zaghlol | B · store link |
| `backup_restore_errorCorrupted` | النسخة دي مش بتتقري. | This backup can't be read. | S |
| `backup_restore_tryOlder` | جرّب نسخة أقدم | Try an older backup | B · Gold only (versions) |
| `backup_restore_doneBanner` | بياناتك رجعت ✓ دلوقتي اسمح لزغلول يقرا على الموبايل ده. | Your data's back ✓ Now let Zaghlol read on this phone. | N · Home C-20 after restore |
| `backup_restore_doneAction` | يلا نظبطها | Set it up | B · opens S-02 or S-03 |

## 1.7 S-05 App lock — `security_lock_*`
States: prompt on appear · failed · biometrics removed (passcode only). The app-switcher blank variant has no text.

| Key | AR | EN | Notes |
|---|---|---|---|
| `security_lock_title` | زغلول مقفول | Zaghlol is locked | T |
| `security_lock_unlock` | `{method, select, faceId{افتح بالـ Face ID} touchId{افتح بالـ Touch ID} fingerprint{افتح ببصمتك} face{افتح ببصمة الوش} other{افتح القفل}}` | `{method, select, faceId{Unlock with Face ID} touchId{Unlock with Touch ID} fingerprint{Use fingerprint} face{Use face unlock} other{Unlock}}` | B · method from the available biometric |
| `security_lock_usePasscode` | `{platform, select, ios{استخدم كود الآيفون} other{استخدم قفل الموبايل}}` | `{platform, select, ios{Use passcode} other{Use phone lock}}` | L · text button (A-08) |
| `security_lock_promptReason` | افتح زغلول | Unlock Zaghlol | L · OS biometric prompt title / iOS localizedReason |
| `security_lock_promptSubtitle` | علشان محدش يشوف فلوسك غيرك | So only you can see your money | S · Android BiometricPrompt subtitle |
| `security_lock_failed` | مفتحش. جرّب تاني. | Didn't unlock. Try again. | N · OS shows its own detail |
| `security_lock_biometricsGone` | البصمة مش متاحة دلوقتي، افتح بقفل الموبايل. | Biometrics aren't available — use your phone lock instead. | S |

## 1.8 S-06 Scan results — «دي كروتك؟» — `onboarding_scanResults_*`
States: populated · credit-card prompt · shown as a sheet if the scan finishes after Home is reached. If the scan found nothing, the screen is skipped and Home shows its empty state. If the scan failed, the screen is skipped and Home shows `home_banner_scanFailed`. A re-scan of one card shows a toast instead of this screen.

| Key | AR | EN | Notes |
|---|---|---|---|
| `onboarding_scanResults_title` | خلصت! 🎉 | All done! 🎉 | T · M · Rive `proud`, scan finished (FR-ONB-06) |
| `onboarding_scanResults_found` | `{count, plural, =1{لقيت حركة واحدة {period}} =2{لقيت حركتين {period}} few{لقيت {n} حركات {period}} many{لقيت {n} حركة {period}} other{لقيت {n} حركة {period}}}` | `{count, plural, =1{Found 1 transaction {period}} other{Found {n} transactions {period}}}` | S · count:int, n, period = `common_period_inLastMonths` |
| `onboarding_scanResults_statAuto` | اتصنفوا لوحدهم | Sorted for you | C · under a number |
| `onboarding_scanResults_statReview` | مستنيين رأيك | Waiting for you | C · tap opens S-14 |
| `onboarding_scanResults_statCards` | كروت وحسابات | Cards & accounts | C |
| `onboarding_scanResults_cardsTitle` | دي كروتك؟ | Are these your cards? | T |
| `onboarding_scanResults_cardSubtitle` | `{count, plural, =1{{type} · حركة واحدة} =2{{type} · حركتين} few{{type} · {n} حركات} many{{type} · {n} حركة} other{{type} · {n} حركة}}` | `{count, plural, =1{{type} · 1 transaction} other{{type} · {n} transactions}}` | L · count:int, n, type = `common_accountType_*` or `onboarding_scanResults_guessCredit` |
| `onboarding_scanResults_guessCredit` | شكله كريدت كارد | Looks like a credit card | L |
| `onboarding_scanResults_creditBadge` | كريدت؟ | Credit? | C |
| `onboarding_scanResults_creditPrompt` | {card} شكله كريدت كارد. قولي الليميت وميعاد السداد عشان أفكرك قبلها. | {card} looks like a credit card. Tell me the limit and due date and I'll remind you before it's due. | M · Rive `detective` · auto-created account that looks like a credit card (FR-ACC-05) |
| `onboarding_scanResults_creditYes` | أيوه، ظبطه | Yes, set it up | B · opens S-43 credit fields |
| `onboarding_scanResults_notMineHint` | كارت مش بتاعك أو كارت شغل؟ دوس عليه واقفل قرايته. | Not yours, or a work card? Tap it to stop tracking it. | S · leads to S-62 |
| `onboarding_scanResults_showMe` | ورّيني فلوسي | Show me my money | B · primary, opens S-10 |
| `onboarding_scanResults_rescanToast` | `{count, plural, =0{ملقيتش حركات جديدة لـ {card}} =1{ضفت حركة واحدة لـ {card}} =2{ضفت حركتين لـ {card}} few{ضفت {n} حركات لـ {card}} many{ضفت {n} حركة لـ {card}} other{ضفت {n} حركة لـ {card}}}` | `{count, plural, =0{No new transactions for {card}} =1{Added 1 transaction to {card}} other{Added {n} transactions to {card}}}` | N · count:int, n, card · FR-CAP-07 re-scan |

## 1.9 S-10 Home — `home_*`
States: loading (skeleton, no copy) · scanning · empty · no budget · budget used up · filter empty · capture limited · finish setup · contextual prompts (once each, FR-ONB-10) · mascot banner (at most one; priority shocked > detective > proud > tourGuide) · error.

### Greeting (large title; the tab label stays `common_nav_home`)
| Key | AR | EN | Notes |
|---|---|---|---|
| `home_greeting_byTime` | `{part, select, morning{صباح الفل يا كبير ☀️} afternoon{مساء الفل يا كبير ☀️} evening{مساء الفل يا كبير 🌙} other{أهلاً يا كبير 👋}}` | `{part, select, morning{Good morning ☀️} afternoon{Good afternoon ☀️} evening{Good evening 🌙} other{Hello 👋}}` | T · part: morning 05:00–11:59, afternoon 12:00–16:59, evening 17:00–04:59 (local time). See Q-05 |
| `home_greeting_firstVisit` | أهلاً يا كبير 👋 | Welcome aboard 👋 | T · first Home visit after onboarding |

### Hero (C-11, one page per currency)
| Key | AR | EN | Notes |
|---|---|---|---|
| `home_hero_safeToSpend` | مسموحلك تصرف النهارده | Safe to spend today | L |
| `home_hero_perDay` | في اليوم | a day | C · suffix after the display amount |
| `home_hero_daysToPayday` | `{count, plural, =0{القبض النهارده} =1{فاضل يوم على القبض} =2{فاضل يومين على القبض} few{فاضل {n} أيام على القبض} many{فاضل {n} يوم على القبض} other{فاضل {n} يوم على القبض}}` | `{count, plural, =0{Payday is today} =1{1 day to payday} other{{n} days to payday}}` | L · count:int, n · followed by ` · ` and `common_date_range` |
| `home_hero_calendarMonth` | لحد ما تقولي ميعاد قبضك | until you tell me your payday | S · A-43, replaces the payday line when no payday is set |
| `home_hero_spentThisMonth` | صرفت الشهر ده | Spent this month | L · no payday and no budget (first visit, mockup 25) |
| `home_hero_spentThisCycle` | صرفت الدورة دي | Spent this cycle | L · payday set, no budget (EC-24) |
| `home_hero_setBudgetHint` | حط ميزانية عشان تعرف تصرف كام في اليوم | Set a budget to see what's safe to spend each day | S · replaces safe-to-spend, never shows zeros |
| `home_hero_setBudget` | حط ميزانية | Set a budget | B · opens S-23 |
| `home_hero_budgetUsedUp` | ميزانية الدورة دي خلصت، حاسب على الباقي | This cycle's budget is used up — go easy on the rest | S · safe-to-spend = 0 with budget > 0 (BR-BUD-03 clamps it with `max(0, …)`, so it's never negative). The hero still shows the amount `0`, with this as its caption. Calm, no joke. See Q-06 |
| `home_hero_kpiIncome` | دخلك | Income | C · C-10 |
| `home_hero_kpiSpent` | صرفت | Spent | C · tap opens S-11 filtered |
| `home_hero_kpiLeft` | فاضلك | Left | C |
| `home_hero_approxTitle` | كله تقريباً بالـ {currency} | Everything, roughly in {currency} | L · last pager page, only when the ≈ view is on (FR-CUR-04) |
| `home_hero_summaryA11y` | مسموحلك تصرف {amount} النهارده. {payday}. دخلك {income}، صرفت {spent}، فاضلك {left}. | Safe to spend today: {amount}. {payday}. Income {income}, spent {spent}, left {left}. | A · payday = `home_hero_daysToPayday` text |

### Mascot banner (C-14, one at a time, dismissible per message ID, at most once per cycle)
| Key | AR | EN | Notes |
|---|---|---|---|
| `home_mascot_shockedCategory` | حاسب يا كبير! {category} وصل {percent} من ميزانيته ولسه بدري في الدورة. | Heads up! {category} is at {percent} of its budget and the cycle's still young. | M · Rive `shocked` · BR-MAS-01a: category ≥ 85% before day 20 |
| `home_mascot_shockedCategoryAlt` | {category} قرّب يخلص يا كبير، {percent} راحوا ولسه بدري. نهدّي شوية؟ | {category} is nearly gone — {percent} used already. Ease off a little? | M · Rive `shocked` · same trigger, alternate line |
| `home_mascot_shockedDining` | الأكل بره والدليفري زايدين {percent} عن العادي بتاعك. المطبخ وحشك؟ 🍳 | Eating out and delivery are up {percent} on your usual. Missing your kitchen? 🍳 | M · Rive `shocked` · BR-MAS-01b: more than 30% above the 3-cycle average |
| `home_mascot_detectiveDuplicate` | اتخصم منك {amount} مرتين من {merchant} في دقايق. بص عليها كده. | {merchant} charged you {amount} twice within minutes. Worth a look. | M · Rive `detective` · BR-MAS-03 duplicate POS (A-34). Money alert, so no emoji |
| `home_mascot_detectiveDuplicateAction` | بص عليها | Take a look | B · opens S-12 |
| `home_mascot_detectiveSubscription` | شكلها اشتراك شهري: {merchant} بـ {amount}. أتابعهولك؟ | Looks like a monthly subscription: {merchant}, {amount}. Want me to track it? | M · Rive `detective` · BR-MAS-03 subscription detected |
| `home_mascot_detectiveSubscriptionTrack` | تابعه | Track it | B · confirms the recurring item (S-24) |
| `home_mascot_detectiveSubscriptionNot` | مش اشتراك | Not a subscription | B |
| `home_mascot_detectiveSelfTransfer` | {amount} راحوا من {fromCard} لـ {toCard}. دي تحويلة لنفسك، فمش هحسبها مصروف 👌 | {amount} moved from {fromCard} to {toCard}. That's you paying you, so it's not spending 👌 | M · Rive `detective` · BR-MAS-03 / BR-XFR-01 self-transfer paired |
| `home_mascot_proudOnTrack` | عاش يا وحش! صارف أقل من خطتك لحد دلوقتي 👏 | Nice one! You're spending under plan so far 👏 | M · Rive `proud` · BR-MAS-02: under the ideal burn line, ≥ 7 days into the cycle |
| `home_mascot_proudSavedMore` | عاش يا وحش! وفرت {amount} زيادة عن الدورة اللي فاتت 👏 | Look at you! {amount} more saved than last cycle 👏 | M · Rive `proud` · BR-MAS-02, only when the computed delta is > 0 |
| `home_mascot_proudGoal` | هدف الدورة اتحقق! 🎯 إنت قدها | Goal hit this cycle! 🎯 You've got this | M · Rive `proud` · BR-MAS-02 goal met |
| `home_mascot_payday` | المرتب نزل! {amount} 🎉 يلا نخطط له من أوله | Payday! {amount} just landed 🎉 Let's plan it from day one | M · Rive `payday` · salary detected (D-35), once per payday. `domain-algorithms.md` §7 treats `payday` as motion-only, and the C-14 priority list has no payday slot. Proposed slot: above `proud`, below `detective`. See Q-18 |
| `home_mascot_dismissA11y` | اقفل الرسالة | Dismiss message | A · × on C-14 |

### Contextual prompts (each appears once and can be dismissed for good, FR-ONB-10 / FR-ONB-04)
| Key | AR | EN | Notes |
|---|---|---|---|
| `home_prompt_payday` | لقيت مرتب {amount} بينزل يوم {day} كل شهر. ده ميعاد قبضك؟ | I spotted a salary of {amount} landing on day {day} each month. Is that your payday? | M · Rive `detective` · salary-like credit detected |
| `home_prompt_paydayYes` | أيوه، يوم {day} | Yes, day {day} | B · only when the detected day is 1–28 (BR-BUD-01). The second button is `common_action_no` |
| `home_prompt_paydayMonthStart` | لقيت مرتب {amount} بينزل آخر الشهر. نحسب الدورة من أول الشهر لآخره؟ | I spotted a salary of {amount} arriving at the end of the month. Shall we track each calendar month, from the 1st? | M · Rive `detective` · D-68: salary detected on day 29, 30 or 31 → suggest payday = 1 (calendar month). The salary counts in the month it arrives; no copy needed for that |
| `home_prompt_paydayMonthStartYes` | أيوه، من أول الشهر | Yes, from the 1st | B · D-68; the second button is `common_action_no` |
| `home_prompt_budget` | خلصت أول دورة معايا! تحب نحط ميزانية للدورة الجاية؟ | First full cycle done! Want to set a budget for the next one? | M · Rive `tourGuide` · first full cycle completed |
| `home_prompt_budgetYes` | يلا | Let's do it | B · opens S-23 |
| `home_prompt_backup` | بقالك أسبوع بتسجل معايا. اعمل نسخة احتياطية ببلاش عشان بياناتك تفضل في أمان لو حصل حاجة للموبايل. | A week of data so far. Make a free backup so it's safe if anything happens to your phone. | M · Rive `tourGuide` · A-65, 7 days of data |
| `home_prompt_backupYes` | اعمل نسخة | Back up | B · opens S-66 |
| `home_prompt_appLockTitle` | `{method, select, faceId{اقفل زغلول بالـ Face ID؟} touchId{اقفل زغلول بالـ Touch ID؟} fingerprint{اقفل زغلول ببصمتك؟} face{اقفل زغلول ببصمة الوش؟} other{اقفل زغلول بقفل الموبايل؟}}` | `{method, select, faceId{Lock Zaghlol with Face ID?} touchId{Lock Zaghlol with Touch ID?} fingerprint{Lock Zaghlol with your fingerprint?} face{Lock Zaghlol with face unlock?} other{Lock Zaghlol with your phone lock?}}` | S · card title, may wrap · FR-ONB-04, a one-tap switch, offered only once transactions are visible |
| `home_prompt_appLockSub` | محدش يشوف فلوسك غيرك | Keep your money for your eyes only | S |
| `home_prompt_appLockOn` | القفل اشتغل ✓ | App lock is on ✓ | N · success |
| `home_prompt_finishSetup` | كمّل الإعداد | Finish setup | L · card at the top, FR-ONB-11 |
| `home_prompt_finishSetupSteps` | `{count, plural, =1{فاضل خطوة واحدة} =2{فاضل خطوتين} few{فاضل {n} خطوات} many{فاضل {n} خطوة} other{فاضل {n} خطوة}}` | `{count, plural, =1{1 step left} other{{n} steps left}}` | C · count:int, n |

### Review pill and banners (C-20)
| Key | AR | EN | Notes |
|---|---|---|---|
| `home_banner_review` | `{count, plural, =1{حركة واحدة مستنية رأيك 👀} =2{حركتين مستنيين رأيك 👀} few{{n} حركات مستنية رأيك 👀} many{{n} حركة مستنية رأيك 👀} other{{n} حركة مستنية رأيك 👀}}` | `{count, plural, =1{1 waiting for your review 👀} other{{n} waiting for your review 👀}}` | N · count:int, n · only when count > 0; opens S-14 |
| `home_banner_scanning` | `{count, plural, =0{بقرا رسايلك…} =1{بقرا رسايلك… لقيت حركة واحدة لحد دلوقتي} =2{بقرا رسايلك… لقيت حركتين لحد دلوقتي} few{بقرا رسايلك… لقيت {n} حركات لحد دلوقتي} many{بقرا رسايلك… لقيت {n} حركة لحد دلوقتي} other{بقرا رسايلك… لقيت {n} حركة لحد دلوقتي}}` | `{count, plural, =0{Reading your messages…} =1{Reading your messages… 1 found so far} other{Reading your messages… {n} found so far}}` | N · count:int, n · C-20 info with C-27 progress; the feed fills live |
| `home_banner_scanFailed` | مقدرتش أقرا رسايلك | Couldn't read your messages | N · C-20 error + `common_action_tryAgain` |
| `home_banner_smsOff` | قراية رسايل البنك مقفولة، فممكن حركات تفوتني. | Bank SMS reading is off, so I might miss some transactions. | N · Android "capture limited" (EC-13) + `common_action_fix` (opens S-61) |
| `home_banner_notifOff` | إشعارات تطبيقات البنوك اتقفلت، فممكن حركات تفوتني. | Bank app notifications are off, so I might miss some transactions. | N · Android, notification access revoked + `common_action_fix` |
| `home_banner_shortcutsBroken` | الاختصارات محتاجة تتظبط عشان ميفوتنيش حاجة. | Your shortcuts need a fix so nothing slips past me. | N · iOS checker failing + `common_action_fix` (opens S-03 step 2) |
| `home_banner_shortcutsQuiet` | `{count, plural, =1{مفيش رسايل بنك اتسجلت من امبارح. الاختصارات لسه شغالة؟} =2{مفيش رسايل بنك اتسجلت من يومين. الاختصارات لسه شغالة؟} few{مفيش رسايل بنك اتسجلت من {n} أيام. الاختصارات لسه شغالة؟} many{مفيش رسايل بنك اتسجلت من {n} يوم. الاختصارات لسه شغالة؟} other{مفيش رسايل بنك اتسجلت من {n} يوم. الاختصارات لسه شغالة؟}}` | `{count, plural, =1{No bank texts logged since yesterday. Are your shortcuts still on?} other{No bank texts logged in {n} days. Are your shortcuts still on?}}` | N · count:int, n · FR-ING-I-07 (7 days while active) |
| `home_banner_shortcutsCheck` | اتأكد | Check | B · opens S-03 step 2 |
| `home_banner_rooted` | `{platform, select, ios{الآيفون ده متعمله جيلبريك، فحماية بياناتك أضعف.} other{الموبايل ده متعمله روت، فحماية بياناتك أضعف.}}` | `{platform, select, ios{This iPhone is jailbroken, so your data is less protected.} other{This phone is rooted, so your data is less protected.}}` | N · FR-SEC-07, shown once + `common_action_learnMore` (opens S-71). Warning only, never blocks |

### Feed, empty and error
| Key | AR | EN | Notes |
|---|---|---|---|
| `home_feed_title` | اللي اتصرف قريب | Recent | L · glossary; + `common_action_seeAll` |
| `home_empty_title` | لسه مفيش حركات | No transactions yet | T · C-28, Rive `sleep` |
| `home_empty_bodyWaiting` | أول ما توصلك رسالة بنك هتظهر هنا لوحدها. | They'll show up here as soon as a bank message arrives. | S · Android with SMS on: no button |
| `home_empty_bodyAdd` | سجّل أول مصروف وأنا أكمّل معاك. | Log your first expense and I'll take it from there. | S · every other case |
| `home_empty_add` | ضيف أول مصروف | Add first expense | B · opens S-30 |
| `home_empty_filter` | مفيش حركات لـ {cards} في الدورة دي | No transactions for {cards} this cycle | S · filter-caused empty + `common_action_clearFilter`. cards = a card label or `common_cardFilter_count` |

## 1.10 Transaction row (C-05, used on S-10, S-11, S-41) — `transactions_row_*`
| Key | AR | EN | Notes |
|---|---|---|---|
| `transactions_row_subtitle` | {card} · {time} · {source} | {card} · {time} · {source} | L · source = `common_source_*`; separators are not mirrored |
| `transactions_row_internalTitle` | تحويلة لنفسك | To yourself | L · ⇄ icon, muted |
| `transactions_row_internalSubtitle` | {fromCard} لـ {toCard} · مش محسوبة في المصاريف | {fromCard} → {toCard} · Excluded from spending | L · FR-HOME-03; colour is never the only cue |
| `transactions_row_declined` | اترفضت · مش محسوبة | Declined · not counted | L · BR-TXN-03, strikethrough amount |
| `transactions_row_reimbursed` | دفعت {paid} · رجعلك {back} | You paid {paid} · got back {back} | L |
| `transactions_row_refund` | مرتجع من {merchant} | Refund from {merchant} | L |
| `transactions_row_needsReviewA11y` | مستنية رأيك | Needs your review | A · dot indicator |
| `transactions_row_labelA11y` | {merchant}، {amount}، {category}، {card}، {time} | {merchant}, {amount}, {category}, {card}, {time} | A · whole-row label |
| `transactions_row_swipeCategory` | غيّر التصنيف | Change category | C · swipe from the start edge; also an a11y action |
| `transactions_row_swipeSplit` | تقسيم / فلوس راجعة | Split / money back | L · swipe from the end edge; also an a11y action |

## 1.11 S-11 Transactions — `transactions_list_*`
States: loading (skeleton) · empty · no results · filtered · selection mode · bulk delete confirm · error (`common_error_loadFailed`).

| Key | AR | EN | Notes |
|---|---|---|---|
| `transactions_list_title` | الحركات | Transactions | T |
| `transactions_list_searchHint` | تاجر، ملاحظة أو مبلغ… | Merchant, note or amount… | L · next to a search icon, whose label is `common_action_searchA11y` · FTS, debounced 250 ms; Arabic-Indic digits accepted (CLAUDE.md §2.5) |
| `transactions_list_filterPeriod` | المدة | Dates | C · chip; shows the selected `common_period_*` once set |
| `transactions_list_filterCategory` | التصنيف | Category | C |
| `transactions_list_filterType` | النوع | Type | C · options = `common_txnType_*` |
| `transactions_list_filterSource` | جت منين | Source | C · options = `common_source_*` |
| `transactions_list_filterCount` | {label} · {n} | {label} · {n} | C · chip with a multi-selection count |
| `transactions_list_rangeTitle` | اختار المدة | Pick dates | T · custom range sheet |
| `transactions_list_rangeFrom` | من | From | L |
| `transactions_list_rangeTo` | لحد | To | L · end ≤ today |
| `transactions_list_dayTotalA11y` | إجمالي اليوم {amount} | Day total {amount} | A · day header, one per currency |
| `transactions_list_emptyTitle` | حركاتك هتظهر هنا | Your transactions will show up here | T · C-28, Rive `sleep` |
| `transactions_list_emptyBody` | من رسايل البنك، أو سجّلها بإيدك. | From your bank messages — or add them yourself. | S |
| `transactions_list_emptyAdd` | ضيف مصروف | Add expense | B · opens S-13 |
| `transactions_list_noResults` | مفيش حاجة شبه «{query}» | Nothing matches "{query}" | S · query is isolated |
| `transactions_list_noResultsFilters` | مفيش حركات بالفلاتر دي | No transactions match these filters | S |
| `transactions_list_clearAll` | امسح البحث والفلاتر | Clear search & filters | B |
| `transactions_list_selectedTitle` | اخترت {n} | {n} selected | T · selection mode; n = formatted count |
| `transactions_list_bulkCategory` | التصنيف | Category | C · bottom action bar |
| `transactions_list_bulkAccount` | الكارت | Card | C · the bar's other actions are `common_action_delete` and `common_action_cancel` (§0.10 reuse rule) |
| `transactions_list_bulkRule` | استخدم ده دايماً للتجار دول | Always use this for these merchants | S · switch after a category change; creates rules (FR-CAT) |
| `transactions_list_bulkChanged` | `{count, plural, =1{اتغيرت حركة واحدة} =2{اتغيرت حركتين} few{اتغيرت {n} حركات} many{اتغيرت {n} حركة} other{اتغيرت {n} حركة}}` | `{count, plural, =1{1 transaction updated} other{{n} transactions updated}}` | N · count:int, n + `common_action_undo` (restores all) |
| `transactions_list_bulkDeleteTitle` | `{count, plural, =1{تمسح حركة واحدة؟} =2{تمسح الحركتين؟} few{تمسح {n} حركات؟} many{تمسح {n} حركة؟} other{تمسح {n} حركة؟}}` | `{count, plural, =1{Delete 1 transaction?} other{Delete {n} transactions?}}` | T · count:int, n · C-18 destructive |
| `transactions_list_bulkDeleteBody` | مش هتقدر ترجعها بعد كده. | You won't be able to get them back. | S · delete asks first and has no Undo; other bulk changes have Undo (FR-TXN-06; Q-08 closed) |
| `transactions_list_bulkDeleted` | `{count, plural, =1{اتمسحت حركة واحدة} =2{اتمسحت حركتين} few{اتمسحت {n} حركات} many{اتمسحت {n} حركة} other{اتمسحت {n} حركة}}` | `{count, plural, =1{1 transaction deleted} other{{n} transactions deleted}}` | N · count:int, n · no Undo |
| `transactions_list_selectRowA11y` | اختار {merchant} | Select {merchant} | A · check circle |

## 1.12 S-12 Transaction detail — `transactions_detail_*` and rule sheet `categorization_rule_*`
States: loading · populated · foreign currency · internal transfer · declined · refund linked · reimbursement suggestion · duplicate warning · reimbursed summary · deleted elsewhere · error.

| Key | AR | EN | Notes |
|---|---|---|---|
| `transactions_detail_original` | الأصلي: {amount} | Original: {amount} | L · foreign only; symbols allowed here (§0.5) |
| `transactions_detail_fieldCard` | الكارت | Card | L · opens S-41 |
| `transactions_detail_fieldDate` | إمتى | When | L · value = `common_date_dateTime` |
| `transactions_detail_fieldBalance` | فاضل في الحساب | Balance after | L |
| `transactions_detail_fieldSource` | جت منين | Source | L |
| `transactions_detail_fieldReference` | رقم العملية | Reference | L · empty shows "—" (not localized) |
| `transactions_detail_fieldNote` | ملاحظة | Note | L |
| `transactions_detail_noteAdd` | ضيف ملاحظة | Add a note | L · text button |
| `transactions_detail_noteHint` | اكتب ملاحظة… | Write a note… | L · ≤ 200 (`common_validation_noteLength`) |
| `transactions_detail_split` | تقسيم / فلوس راجعة | Split / money back | L · expenses, opens S-15 Mode A |
| `transactions_detail_linkTransfer` | دي تحويلة لنفسي | This is my own transfer | L · opens S-16 |
| `transactions_detail_moneyBackFor` | دي فلوس راجعة عن… | This is money back for… | L · incoming only, opens S-15 Mode B (FR-XFR-06) |
| `transactions_detail_linkedWith` | مربوطة مع {amount} في {card} | Linked with {amount} on {card} | L · internal; + `common_action_unlink` |
| `transactions_detail_internalBanner` | تحويلة لنفسك، مش محسوبة لا مصروف ولا دخل | Transfer to yourself — not counted as spending or income | N |
| `transactions_detail_declinedBanner` | العملية اترفضت، مش محسوبة | Declined — not counted | N · BR-TXN-03 |
| `transactions_detail_refundCard` | مرتجع من {merchant} عن مشتريات {date} · الصافي {net} | Refund from {merchant} for your {date} purchase · net {net} | S · FR-XFR-03 |
| `transactions_detail_refundView` | شوف الأصلية | View original | B |
| `transactions_detail_refundNotRelated` | مش مرتبطة | Not related | B |
| `transactions_detail_reimbSuggest` | دي من فاتورة {merchant}؟ | Is this from the {merchant} bill? | S · FR-XFR-08, never auto-applied; + yes/no |
| `transactions_detail_duplicate` | شكلها مكررة مع حركة {date} بنفس المبلغ | Looks like a duplicate of a {date} transaction for the same amount | S |
| `transactions_detail_duplicateKeep` | سيب الاتنين | Keep both | B |
| `transactions_detail_duplicateDelete` | امسح دي | Delete this one | B · destructive |
| `transactions_detail_reimbSummary` | دفعت {paid} · رجعلك {back} · نصيبك {share} | Paid {paid} · back {back} · your share {share} | L |
| `transactions_detail_howTitle` | إزاي زغلول قرا الرسالة | How Zaghlol read this | L · collapsible (spec "SMS inspector") |
| `transactions_detail_howRawA11y` | نص الرسالة الأصلي | Original message text | A · raw text is shown on screen only, never logged (CLAUDE.md §2.6) |
| `transactions_detail_howAmount` | المبلغ {amount} | Amount {amount} | C |
| `transactions_detail_howMerchant` | التاجر {merchant} | Merchant {merchant} | C |
| `transactions_detail_howConfidence` | ثقة {percent} | Confidence {percent} | C · FR-PAR-06 |
| `transactions_detail_howTemplate` | القالب {templateId} | Template {templateId} | C · Latin ID, e.g. `nbe.card_purchase.ar.v2` |
| `transactions_detail_howNone` | مفيش رسالة للحركة دي. | There's no message for this one. | S · manual, voice, CSV |
| `transactions_detail_categoryChanged` | اتغير التصنيف | Category changed | N + `common_action_undo` |
| `transactions_detail_deleteTitle` | تمسح الحركة دي؟ | Delete this transaction? | T · C-18 destructive |
| `transactions_detail_deleteBodyAuto` | `{platform, select, ios{مش هتقدر ترجعها بعد كده.} other{جت من رسالة، ومش هترجع غير لو دوّرت في الرسايل من جديد.}}` | `{platform, select, ios{You won't be able to get it back.} other{It came from a message and won't come back unless you re-scan.}}` | S · auto-captured; re-scan is Android only. Uses the standard `ios`/`other` select (§0.4) |
| `transactions_detail_deleteBodyManual` | مش هتقدر ترجعها بعد كده. | You won't be able to get it back. | S |
| `transactions_detail_deleted` | اتمسحت | Deleted | N |
| `transactions_detail_gone` | الحركة دي مبقتش موجودة | This transaction no longer exists | N · deleted elsewhere; goes back |
| `categorization_rule_title` | أستخدم {category} دايماً لـ {merchant}؟ | Always use {category} for {merchant}? | T · FR-CAT-05 sheet, owned by the `categorization` module (F-19) |
| `categorization_rule_always` | دايماً | Always | B |
| `categorization_rule_once` | المرة دي بس | Just this once | B |
| `categorization_rule_applyPast` | `{count, plural, =1{وكمان غيّر الحركة القديمة} =2{وكمان غيّر الحركتين القدام} few{وكمان غيّر الـ {n} حركات القديمة} many{وكمان غيّر الـ {n} حركة القديمة} other{وكمان غيّر الـ {n} حركة القديمة}}` | `{count, plural, =1{Also update 1 past transaction} other{Also update {n} past transactions}}` | S · count:int, n · checkbox (A-13), hidden when count = 0 (§0.4) |
| `categorization_rule_saved` | تمام، هفتكر ده ✓ | Got it — I'll remember ✓ | N + `common_action_undo` |

## 1.13 S-13 Add / edit transaction — `transactions_edit_*`
States: add (per type) · edit · prefilled from a shared message · prefilled from the review queue · validation · save failed (`common_error_saveFailed`) · unsaved changes (`common_discard_*`) · saved (`mascot_saved_*`).

| Key | AR | EN | Notes |
|---|---|---|---|
| `transactions_edit_titleAdd` | `{type, select, income{دخل جديد} transfer{تحويل جديد} other{مصروف جديد}}` | `{type, select, income{Add income} transfer{Add transfer} other{Add expense}}` | T |
| `transactions_edit_titleEdit` | عدّل الحركة | Edit transaction | T |
| `transactions_edit_typeA11y` | نوع الحركة | Transaction type | A · segments use `common_txnType_expense/income/transfer` |
| `transactions_edit_amountA11y` | المبلغ | Amount | A · C-22; numeric pad; Arabic-Indic and Western input accepted |
| `transactions_edit_currency` | العملة | Currency | L |
| `transactions_edit_currencySearch` | دوّر على عملة | Search currencies | L |
| `transactions_edit_currencyFeatured` | الأكتر استخدام | Most used | L · section |
| `transactions_edit_currencyAll` | كل العملات | All currencies | L · section |
| `transactions_edit_category` | التصنيف | Category | L |
| `transactions_edit_choose` | اختار | Choose | C · empty picker |
| `transactions_edit_merchant` | التاجر أو الشخص | Merchant or person | L |
| `transactions_edit_account` | الحساب | Account | L · default `common_accountType_cash` (FR-CARD-05) |
| `transactions_edit_from` | من حساب | From | L · transfer |
| `transactions_edit_to` | لحساب | To | L · transfer |
| `transactions_edit_whichBalance` | من أنهي رصيد؟ | Which balance? | L · multi-currency account |
| `transactions_edit_date` | إمتى | When | L · default `common_date_today` |
| `transactions_edit_note` | ملاحظة | Note | L |
| `transactions_edit_sameAccount` | اختار حسابين مختلفين | Pick two different accounts | S · validation, transfer from ≠ to |
| `transactions_edit_fromShared` | ده اللي فهمته من الرسالة اللي بعتها. راجعه واحفظ. | Here's what I got from the message you shared. Check it and save. | S · FR-ING-A-04 confirm-before-save |
| `transactions_edit_rawTitle` | نص الرسالة | Message text | L · prefilled from S-14 "Enter details" |

## 1.14 S-14 Review queue — `ingestion_review_*`, `ingestion_alwaysSender_*`, `ingestion_requestBank_*`
States: loading (skeleton) · populated (category card, generic-parser card, unreadable-message card, ambiguous transfer) · empty · request-bank sheet: sending, sent, failed or offline (kept as a draft).

| Key | AR | EN | Notes |
|---|---|---|---|
| `ingestion_review_title` | مستني رأيك 👀 | Needs your review 👀 | T · glossary. The spec's "(5)" count isn't in the title: the "All" chip (`ingestion_review_filterAll`) shows it instead (F-5f) |
| `ingestion_review_filterAll` | الكل {n} | All {n} | C · n = formatted count |
| `ingestion_review_filterCategory` | تصنيف | Category | C |
| `ingestion_review_filterMessages` | رسايل جديدة | New messages | C · unread or unrecognized |
| `ingestion_review_filterTransfers` | تحويلات | Transfers | C |
| `ingestion_review_catOut` | {amount} لـ {counterparty} | {amount} to {counterparty} | L · counterparty may be an IPA handle (LTR, isolated) |
| `ingestion_review_catIn` | {amount} من {counterparty} | {amount} from {counterparty} | L |
| `ingestion_review_catAt` | {amount} عند {merchant} | {amount} at {merchant} | L |
| `ingestion_review_catQuestion` | كانت إيه دي؟ | What was this? | L · followed by category chips (catalog names) and `common_action_more` |
| `ingestion_review_rememberCounterparty` | افتكر ده لأي تحويلة لـ {counterparty} | Remember this for {counterparty} | L · checkbox |
| `ingestion_review_rememberMerchant` | افتكر ده لـ {merchant} على طول | Always use this for {merchant} | L · checkbox |
| `ingestion_review_categorized` | اتحطت في {category} | Filed under {category} | N + `common_action_undo` |
| `ingestion_review_newBank` | بنك جديد | New bank | C · badge |
| `ingestion_review_genFrom` | من {sender} | From {sender} | L |
| `ingestion_review_genGuessOut` | توقعنا: {amount} عند {merchant} | Our guess: {amount} at {merchant} | S · FR-PAR-13 |
| `ingestion_review_genGuessNoMerchant` | توقعنا: {amount} | Our guess: {amount} | S |
| `ingestion_review_genGuessIn` | توقعنا: {amount} دخلوا | Our guess: {amount} in | S |
| `ingestion_review_genLowConfidence` | مش متأكد أوي، بص عليها قبل ما أسجلها | Not totally sure — check it before I log it | S · FR-PAR-06. The card's buttons are `common_action_confirm`, `common_action_edit` (opens S-13 prefilled) and `common_action_dismiss` |
| `ingestion_review_requestBank` | اطلب دعم البنك ده | Ask us to support this bank | L · text button (FR-PAR-14) |
| `ingestion_review_unreadTitle` | رسالة من {sender} مقدرتش أفهمها | A message from {sender} I couldn't read | S · FR-ING-A-06 |
| `ingestion_review_unreadShow` | شوف الرسالة | Show message | B · raw text on screen only |
| `ingestion_review_unreadEnter` | اكتب التفاصيل | Enter details | B · opens S-13 with `transactions_edit_rawTitle` |
| `ingestion_review_xferTitle` | {amount} في {card}، تبع أنهي تحويلة؟ | {amount} into {card} — which transfer was it? | S · BR-XFR-02 / EC-16; confirm with `common_action_confirm` |
| `ingestion_review_xferOption` | {amount} من {card} · {time} | {amount} from {card} · {time} | L · radio |
| `ingestion_review_xferNotMine` | مش تحويلة مني | Not my transfer | L · radio |
| `ingestion_review_swipeAcceptA11y` | وافق على الاقتراح | Accept suggestion | A · swipe from the start edge; the button is always visible |
| `ingestion_review_swipeDismissA11y` | سيبها | Dismiss | A · swipe from the end edge, with undo |
| `ingestion_review_dismissed` | اتشالت من المراجعة | Removed from review | N + `common_action_undo` |
| `ingestion_review_emptyTitle` | كله تمام! مفيش حاجة مستنية رأيك ✨ | All clear! Nothing to review ✨ | T · C-28, Rive `proud` |
| `ingestion_alwaysSender_title` | أقرا رسايل {sender} على طول؟ | Always capture messages from {sender}? | T · A-66 sheet, after confirming a generic parse |
| `ingestion_alwaysSender_body` | `{count, plural, =0{من هنا ورايح هسجل رسايله لوحدي.} =1{هتفضل توصلك هنا للمراجعة لحد ما تأكد رسالة واحدة منه، وبعد كده هسجلها لوحدي.} =2{هتفضل توصلك هنا للمراجعة لحد ما تأكد رسالتين منه، وبعد كده هسجلها لوحدي.} few{هتفضل توصلك هنا للمراجعة لحد ما تأكد {n} رسايل منه، وبعد كده هسجلها لوحدي.} many{هتفضل توصلك هنا للمراجعة لحد ما تأكد {n} رسالة منه، وبعد كده هسجلها لوحدي.} other{هتفضل توصلك هنا للمراجعة لحد ما تأكد {n} رسالة منه، وبعد كده هسجلها لوحدي.}}` | `{count, plural, =0{From now on I'll log its messages myself.} =1{They'll still come here for review until you've confirmed 1, then I'll log them myself.} other{They'll still come here for review until you've confirmed {n}, then I'll log them myself.}}` | S · count:int, n · count = confirmations still needed (A-66: 3 in total); 0 once all are done |
| `ingestion_alwaysSender_yes` | أيوه، على طول | Yes, always | B |
| `ingestion_requestBank_title` | اطلب دعم بنكك | Request your bank | T · shared by S-14 and S-61 |
| `ingestion_requestBank_name` | اسم البنك | Bank name | L · prefilled with the sender in S-14 |
| `ingestion_requestBank_country` | البلد | Country | L |
| `ingestion_requestBank_channel` | تنبيهاته بتوصل إزاي؟ | How do its alerts arrive? | L · options `common_source_sms` / `common_source_notification` |
| `ingestion_requestBank_privacy` | هنبعت اسم البنك وبلده ونوع التنبيه بس. عمرنا ما هنبعت الرسالة نفسها. | We send only the bank's name, country and alert type — never the message itself. | S · FR-PAR-14 / BR-SYNC-03 (SRS adds the channel, see Q-09). Sent with `common_action_send` |
| `ingestion_requestBank_sent` | وصل طلبك ✓ شكراً! | Request sent ✓ Thanks! | N · no promise of a date |
| `ingestion_requestBank_failed` | مقدرتش أبعته دلوقتي. حفظته، وتقدر تبعته تاني بعدين. | Couldn't send it right now. I've kept it so you can send it later. | S · network or offline; draft kept |
| `ingestion_requestBank_nameLength` | اسم البنك لازم يكون من {min} لـ {max} حرف | Bank name must be {min}–{max} characters | S · min = 2, max = 60, both formatted Strings |
| `ingestion_requestBank_countryRequired` | اختار البلد | Choose a country | S |

## 1.15 S-15 Split & reimbursements — `transfers_split_*` (Mode A), `transfers_assign_*` (Mode B)
States: Mode A editing · suggestion · Mode B assigning · no candidate expenses · validation · save failed (`common_error_saveFailed`) · saved.

| Key | AR | EN | Notes |
|---|---|---|---|
| `transfers_split_title` | تقسيم العزومة | Split the bill | T · glossary |
| `transfers_split_header` | {merchant} · {amount} | {merchant} · {amount} | L |
| `transfers_split_people` | الناس | People | L |
| `transfers_split_addPerson` | ضيف حد | Add person | B |
| `transfers_split_personHint` | الاسم | Name | L · 1–30 characters |
| `transfers_split_shareA11y` | نصيب {name} | {name}'s share | A · apostrophe right after a brace: see §0.10 ARB note |
| `transfers_split_removePerson` | شيل {name} | Remove {name} | L · row action / a11y action (F-5d) |
| `transfers_split_equal` | قسّم بالتساوي | Split evenly | B · this is the default |
| `transfers_split_paidBack` | رجع | Paid back | C · status |
| `transfers_split_waiting` | مستني | Waiting | C · status (FR-XFR-05) |
| `transfers_split_paidDetail` | {amount} · {source} · {date} | {amount} · {source} · {date} | L |
| `transfers_split_yourShare` | دفعت إنت فعلاً | Your share | L · glossary «دفعت إنت فعلاً» (BR-XFR-04) |
| `transfers_split_suggestions` | اقتراحات | Suggestions | L |
| `transfers_split_suggestion` | {amount} من {person} · {date}، من العزومة دي؟ | {amount} from {person} · {date} — from this bill? | S · + `common_action_link`; never auto (FR-XFR-08) |
| `transfers_split_unassign` | شيلها من العزومة دي | Remove from this bill | L · on a linked repayment (FR-XFR-09) (F-5d) |
| `transfers_split_unassigned` | اتشالت، ورجعت تتحسب دخل عادي | Removed — it counts as income again | N + `common_action_undo` · FR-XFR-09 |
| `transfers_split_saved` | اتحفظ التقسيم ✓ | Split saved ✓ | N |
| `transfers_assign_header` | {amount} من {person} | {amount} from {person} | L |
| `transfers_assign_title` | وزّعها على مصاريف | Assign to expenses | T |
| `transfers_assign_search` | دوّر في المصاريف الأخيرة | Search recent expenses | L |
| `transfers_assign_unassigned` | مش متوزع: {amount}، هيفضل دخل | Not assigned: {amount} — stays as income | S · BR-XFR-06 |
| `transfers_assign_empty` | `{count, plural, =1{مفيش مصاريف من امبارح} =2{مفيش مصاريف في آخر يومين} few{مفيش مصاريف في آخر {n} أيام} many{مفيش مصاريف في آخر {n} يوم} other{مفيش مصاريف في آخر {n} يوم}}` | `{count, plural, =1{No expenses since yesterday} other{No expenses in the last {n} days}}` | S · count:int = 60, n |
| `transfers_assign_searchAll` | دوّر في كل المصاريف | Search all expenses | B |
| `transfers_assign_saved` | اتوزعت ✓ | Assigned ✓ | N |
| `transfers_split_errorShareZero` | النصيب لازم يكون أكبر من صفر | Each share must be more than zero | S |
| `transfers_split_errorSharesExceed` | مجموع الأنصبة أكبر من المصروف | Shares add up to more than the expense | S |
| `transfers_assign_errorExceedsIncoming` | وزعت أكتر من المبلغ اللي جالك | You've assigned more than you received | S |
| `transfers_assign_errorExceedsExpense` | الفلوس الراجعة أكتر من المصروف نفسه | Money back can't be more than the expense | S · BR-XFR-06 |
| `transfers_split_errorCurrency` | عملة مختلفة، مينفعش تربطهم | Different currency — can't link these | S · amounts are never converted |

## 1.16 S-16 Link as my transfer — `transfers_link_*`
States: candidates · cross-currency candidate · empty (EC-15) · validation · linked.

| Key | AR | EN | Notes |
|---|---|---|---|
| `transfers_link_title` | ربط تحويلة لنفسي | Link my own transfer | T |
| `transfers_link_source` | {amount} · {card} · {date} | {amount} · {card} · {date} | L |
| `transfers_link_pick` | اختار الحركة اللي تقابلها | Pick the matching transaction | L |
| `transfers_link_afterMinutes` | `{count, plural, =0{في نفس الدقيقة} =1{بعدها بدقيقة} =2{بعدها بدقيقتين} few{بعدها بـ {n} دقايق} many{بعدها بـ {n} دقيقة} other{بعدها بـ {n} دقيقة}}` | `{count, plural, =0{Same minute} =1{1 min later} other{{n} min later}}` | C · count:int, n · gap under 60 min (0 = same minute) |
| `transfers_link_beforeMinutes` | `{count, plural, =0{في نفس الدقيقة} =1{قبلها بدقيقة} =2{قبلها بدقيقتين} few{قبلها بـ {n} دقايق} many{قبلها بـ {n} دقيقة} other{قبلها بـ {n} دقيقة}}` | `{count, plural, =0{Same minute} =1{1 min earlier} other{{n} min earlier}}` | C · count:int, n · gap under 60 min |
| `transfers_link_afterHours` | `{count, plural, =1{بعدها بساعة} =2{بعدها بساعتين} few{بعدها بـ {n} ساعات} many{بعدها بـ {n} ساعة} other{بعدها بـ {n} ساعة}}` | `{count, plural, =1{1 hr later} other{{n} hr later}}` | C · count:int, n · gap of 1–23 h (F-5e); can't be 0 (§0.4) |
| `transfers_link_beforeHours` | `{count, plural, =1{قبلها بساعة} =2{قبلها بساعتين} few{قبلها بـ {n} ساعات} many{قبلها بـ {n} ساعة} other{قبلها بـ {n} ساعة}}` | `{count, plural, =1{1 hr earlier} other{{n} hr earlier}}` | C · count:int, n · gap of 1–23 h |
| `transfers_link_afterDays` | `{count, plural, =0{في نفس اليوم} =1{بعدها بيوم} =2{بعدها بيومين} few{بعدها بـ {n} أيام} many{بعدها بـ {n} يوم} other{بعدها بـ {n} يوم}}` | `{count, plural, =0{Same day} =1{1 day later} other{{n} days later}}` | C · count:int, n · whole calendar days, gap of 24 h or more. `=0` covers a calendar-day count of 0 if a caller passes it |
| `transfers_link_beforeDays` | `{count, plural, =0{في نفس اليوم} =1{قبلها بيوم} =2{قبلها بيومين} few{قبلها بـ {n} أيام} many{قبلها بـ {n} يوم} other{قبلها بـ {n} يوم}}` | `{count, plural, =0{Same day} =1{1 day earlier} other{{n} days earlier}}` | C · count:int, n · as above |
| `transfers_link_impliedRate` | سعر التحويل ≈ {rate} لكل {fromCurrency} | Implied rate ≈ {rate} per {fromCurrency} | L · cross-currency (A-61); rate includes the target currency. The sheet's button is `common_action_link` |
| `transfers_link_linked` | اتربطوا ✓ ومش هيتحسبوا مصروف | Linked ✓ Not counted as spending | N + `common_action_undo` |
| `transfers_link_emptyTitle` | ملقيتش حركة تقابلها | No matching transaction found | T · C-28 |
| `transfers_link_emptyBody` | ممكن البنك التاني مش بيبعت رسايل. تقدر تعلّمها تحويلة لنفسك برضه، ومش هتتحسب مصروف. | The other bank may not send messages. You can still mark this as your own transfer so it isn't counted as spending. | S · EC-15 |
| `transfers_link_markAnyway` | علّمها تحويلة لنفسي | Mark as my transfer | B · one-sided internal |
| `transfers_link_errorAmounts` | المبلغين لازم يكونوا زي بعض | Amounts must match | S · same currency |
| `transfers_link_errorAccount` | اختار حساب تاني | Pick a different account | S |
| `transfers_link_errorDirection` | لازم واحدة خارجة وواحدة داخلة | One must be money out, the other money in | S |

## 1.17 S-40 Money overview — `accounts_overview_*`, add flow `accounts_addType_*`, `accounts_addBank_*`, `accounts_added_*`
States: loading (skeleton) · empty · populated · multi-currency · ≈ view · stale prices (`common_badge_stale`) · Free assets locked · Zakah entry (flag only) · error. Asset row content (karat, grams, certificates) belongs to Part 2 (S-44/45).

| Key | AR | EN | Notes |
|---|---|---|---|
| `accounts_overview_title` | فلوسي | Money | T |
| `accounts_overview_add` | ضيف | Add | B · opens menu |
| `accounts_overview_addAccount` | كارت أو حساب | Card or account | L · opens `accounts_addType_*` |
| `accounts_overview_addAsset` | أصل (دهب، شهادة…) | Asset (gold, certificate…) | L · with `common_gold_badge`; Free opens S-68 |
| `accounts_overview_netWorth` | اللي حيلتك كله | Net worth | L · glossary; one figure per currency, no cross-currency sum |
| `accounts_overview_otherCurrenciesA11y` | عملات تانية | Other currencies | A |
| `accounts_overview_accountsTitle` | كروتك وحساباتك | Cards & accounts | L |
| `accounts_overview_compare` | قارن | Compare | L · text button, opens S-42 |
| `accounts_overview_asOf` | آخر تحديث {when} | as of {when} | C · when = `common_date_minutesAgo` or a date (FR-ACC-02) |
| `accounts_overview_creditAvailable` | متاح من {limit} | available of {limit} | C |
| `accounts_overview_moreCurrencies` | `{count, plural, =1{وكمان عملة واحدة} =2{وكمان عملتين} few{وكمان {n} عملات} many{وكمان {n} عملة} other{وكمان {n} عملة}}` | `{count, plural, =1{+1 more currency} other{+{n} more currencies}}` | L · count:int, n · multi-currency row (FR-ACC-06) |
| `accounts_overview_cashSub` | يدوي وصوت | Manual & voice | C |
| `accounts_overview_notTracked` | مش متتبع | Not tracked | C · ignored card (C-07) |
| `accounts_overview_hiddenEntry` | الحسابات المخفية | Hidden accounts | L · row at the end of the list, only when at least one account is hidden. Opens the hidden list (S-40 spec, `accounts_hidden_*`, §2.12), where each account can be unhidden or opened in S-43 (D-69). Trailing count: `accounts_overview_hiddenCount` |
| `accounts_overview_assetsTitle` | دهبك وشهاداتك | Your assets | L · glossary, + `common_gold_badge` |
| `accounts_overview_prices` | الأسعار | Prices | L · text button, opens S-45 |
| `accounts_overview_assetsLocked` | تابع دهبك وشهاداتك وكل أصولك في مكان واحد | Track your gold, certificates and more in one place | S · locked preview + `common_gold_unlock` |
| `accounts_overview_zakah` | الزكاة | Zakah | L · only when the `zakah` flag is on |
| `accounts_overview_emptyTitle` | الحسابات بتظهر لوحدها من رسايل البنك | Accounts appear from your bank messages | T · C-28, Rive `sleep` |
| `accounts_overview_emptyAdd` | ضيف حساب بإيدك | Add one yourself | B |
| `accounts_addType_title` | تضيف إيه؟ | What are you adding? | T · sheet |
| `accounts_addType_info` | الكروت بتتضاف لوحدها أول ما توصل رسالة. ضيف بإيدك لو لسه مفيش رسايل. | Cards are added automatically when a message arrives. Add one yourself if none has come yet. | S |
| `accounts_addType_credit` | كريدت كارد | Credit card | L |
| `accounts_addType_creditSub` | الليميت وميعاد السداد | Limit and due date | S |
| `accounts_addType_debit` | كارت ديبت / حساب بنك | Debit card / bank account | L |
| `accounts_addType_debitSub` | مرتب ومصاريف | Salary and spending | S |
| `accounts_addType_wallet` | محفظة | Wallet | L |
| `accounts_addType_walletSub` | فودافون كاش، أورانج كاش، إي آند كاش | Vodafone Cash, Orange Cash, e& cash | S · mobile-wallet examples; InstaPay removed because it's a transfer rail (Q-10). Brand names still need OQ-09 clearance |
| `accounts_addType_multi` | حساب بأكتر من عملة | Multi-currency account | L |
| `accounts_addType_multiSub` | Wise، Revolut، Payoneer | Wise, Revolut, Payoneer | S |
| `accounts_addType_bnpl` | تقسيط | Buy now, pay later | L |
| `accounts_addType_bnplSub` | فاليو، سيمبل، كونتكت | valU, Sympl, Contact | S |
| `accounts_addBank_title` | من أنهي بنك؟ | Which bank? | T |
| `accounts_addBank_search` | دوّر على بنك… | Search banks… | L |
| `accounts_addBank_egypt` | بنوك مصر | Banks in Egypt | L · section |
| `accounts_addBank_abroad` | بنوك برّه وأونلاين | Foreign & online banks | L · section |
| `accounts_addBank_notListed` | بنكي مش موجود | My bank isn't listed | L |
| `accounts_addBank_notListedSub` | ضيفه باسمه، وزغلول هيحاول يفهم رسايله | Add it by name — Zaghlol will try to read its messages | S · generic parser (FR-PAR-13); no promise |
| `accounts_addBank_noResults` | مفيش بنك بالاسم ده | No bank by that name | S · + not-listed row |
| `accounts_addBank_required` | اختار بنك | Choose a bank | S |
| `accounts_added_title` | الكارت اتضاف! ✨ | Card added! ✨ | N · success |
| `accounts_added_dueDay` | السداد يوم {day} كل شهر | Due on day {day} each month | L |
| `accounts_added_waitingBalance` | هيتحدث مع أول رسالة فيها الرصيد المتاح | Updates with the first message that shows your available balance | S · value shows "—" |
| `accounts_added_emptyBody` | أول ما توصلك رسالة من {bank} على {last4} هتظهر هنا لوحدها. | As soon as {bank} messages you about {last4}, it'll show up here. | S · S-41 empty state, Rive `sleep` |
| `accounts_added_import` | ضيف كشف حساب الكارت | Import this card's statement | L · `common_gold_badge`; Free opens S-68 |
| `accounts_added_importSub` | PDF من تطبيق البنك | A PDF from your bank's app | S |
| `accounts_added_manual` | سجّل حركة بإيدك | Add a transaction | L · opens S-13 on this card (FR-CARD-05) |
| `accounts_added_manualSub` | على الكارت ده | On this card | S |

## 1.18 S-41 Card / account detail — `accounts_detail_*`
States: loading · populated · multi-currency (C-09 chips) · empty period · ignored card · balance unknown · error. The trend chart's time axis mirrors in AR (UX-D-01).

| Key | AR | EN | Notes |
|---|---|---|---|
| `accounts_detail_available` | فاضل في الكارت | Available | L · glossary, credit |
| `accounts_detail_availableOf` | {available} من {limit} | {available} of {limit} | L |
| `accounts_detail_limitUsed` | مستخدم {percent} من الليميت | {percent} of your limit used | L |
| `accounts_detail_balance` | الرصيد | Balance | L · debit / account |
| `accounts_detail_asOf` | آخر تحديث {when} | As of {when} | C |
| `accounts_detail_balanceUnknown` | هيظهر مع أول رسالة فيها رصيد | Shows up with the first message that has a balance | S |
| `accounts_detail_due` | ميعاد السداد {date} | Statement due {date} | L |
| `accounts_detail_spent` | صرفت | Spent | L · + period chip `common_period_*` |
| `accounts_detail_donutA11y` | توزيع الصرف على التصنيفات | Spending by category | A |
| `accounts_detail_topMerchants` | أكتر أماكن صرفت فيها | Top merchants | L |
| `accounts_detail_trend` | الصرف شهر بشهر | Monthly trend | L · subtitle `common_period_lastMonths` |
| `accounts_detail_incomeRefunds` | دخل ومرتجعات | Income & refunds | L |
| `accounts_detail_recent` | آخر الحركات | Recent | L |
| `accounts_detail_allTransactions` | كل حركات الكارت | All card transactions | L · sets the card filter, opens S-11 |
| `accounts_detail_capture` | زغلول بيقرا إيه | What Zaghlol reads | L · value lists `common_channel_*Short` + ✓/✗, opens S-62 |
| `accounts_detail_menuCapture` | زغلول يقرا إيه من الكارت | Capture controls | L · ⋮ menu |
| `accounts_detail_menuMerge` | ادمجه مع كارت تاني | Merge with another card | L |
| `accounts_detail_menuHide` | اخفي الحساب | Hide account | L · D-69: hides from lists and pickers only |
| `accounts_detail_empty` | مفيش صرف على الكارت ده في الفترة دي | No spending on this card in this period | S · Rive `sleep` |
| `accounts_detail_ignoredBanner` | `{platform, select, ios{مش متتبع: الرسايل وApple Pay مقفولين للكارت ده} other{مش متتبع: الرسايل والإشعارات مقفولة للكارت ده}}` | `{platform, select, ios{Not tracked: messages and Apple Pay are off for this card} other{Not tracked: messages and notifications are off for this card}}` | N |
| `accounts_detail_trackAgain` | تابعه تاني | Track again | B · Android then offers `capture_rescanOffer_*` |

## 1.19 S-42 Compare cards — `accounts_compare_*`
| Key | AR | EN | Notes |
|---|---|---|---|
| `accounts_compare_title` | مقارنة الكروت | Compare cards | T |
| `accounts_compare_total` | الإجمالي | Total | L · same currency only |
| `accounts_compare_choose` | اختار الكروت | Choose cards | B |
| `accounts_compare_max` | `{count, plural, =1{تقدر تختار كارت واحد} =2{تقدر تختار لحد كارتين} few{تقدر تختار لحد {n} كروت} many{تقدر تختار لحد {n} كارت} other{تقدر تختار لحد {n} كارت}}` | `{count, plural, =1{Pick 1 card} other{Pick up to {n} cards}}` | S · count:int = 6 (UX-A-03), n |
| `accounts_compare_otherCurrency` | الكروت اللي بعملة تانية بتظهر لما تختار عملتها | Cards in other currencies appear when you pick that currency | S |
| `accounts_compare_empty` | المقارنة محتاجة كارتين على الأقل فيهم صرف | Compare needs at least two cards with spending | S · C-28 |
| `accounts_compare_cellA11y` | {category}، {card}: {amount} | {category}, {card}: {amount} | A |

## 1.20 S-43 Edit card / account — `accounts_edit_*`, `accounts_merge_*`
States: edit · create (after type and bank) · credit fields · multi-currency balances · duplicate last-4 · merge picker / confirm / different-bank warning · validation · saved · error.

| Key | AR | EN | Notes |
|---|---|---|---|
| `accounts_edit_titleEdit` | تفاصيل الكارت | Card details | T |
| `accounts_edit_titleNew` | كارت جديد | New card | T |
| `accounts_edit_name` | اسم الكارت | Card name | L · 1–30, unique |
| `accounts_edit_bank` | البنك | Bank | L |
| `accounts_edit_bankAuto` | اتعرف من الرسايل | Detected from messages | L · read-only when auto-created |
| `accounts_edit_last4` | آخر أربع أرقام | Last four digits | L · LTR input, Western digits shown |
| `accounts_edit_last4Hint` | في الرسالة بيبان كده: «{sample}»، عشان زغلول يعرف الكارت. | In messages it looks like "{sample}" — that's how Zaghlol spots the card. | S · sample = a synthetic pattern from the institution template, e.g. `**1234` (never a real SMS) |
| `accounts_edit_type` | النوع | Type | L · `common_accountType_*` |
| `accounts_edit_currency` | العملة | Currency | L |
| `accounts_edit_balances` | الأرصدة | Balances | L · multi-currency |
| `accounts_edit_addCurrency` | ضيف عملة | Add currency | B |
| `accounts_edit_limit` | الليميت | Credit limit | L · credit only, ≥ 0 |
| `accounts_edit_dueDay` | يوم السداد | Statement due day | L · credit only, 1–31 |
| `accounts_edit_dueReminder` | `{count, plural, =0{هفكرك يوم السداد نفسه.} =1{هفكرك قبل ميعاد السداد بيوم.} =2{هفكرك قبل ميعاد السداد بيومين.} few{هفكرك قبل ميعاد السداد بـ {n} أيام.} many{هفكرك قبل ميعاد السداد بـ {n} يوم.} other{هفكرك قبل ميعاد السداد بـ {n} يوم.}}` | `{count, plural, =0{I'll remind you on the due day.} =1{I'll remind you 1 day before it's due.} other{I'll remind you {n} days before it's due.}}` | S · count:int (default 3, BR-SUB-03), n |
| `accounts_edit_captureTitle` | زغلول يقرا إيه من الكارت ده؟ | What should Zaghlol read for this card? | T · section heading, create mode inline toggles (`common_channel_*`) |
| `accounts_edit_captureLink` | زغلول بيقرا إيه | What Zaghlol reads | L · edit mode, opens S-62 |
| `accounts_edit_merge` | ادمجه مع كارت تاني | Merge with another card | L |
| `accounts_edit_hide` | اخفي الحساب ده | Hide this account | L · switch |
| `accounts_edit_hideHint` | مش هيظهر في القوايم، بس حركاته لسه محسوبة في الأرقام والميزانية والشارتات. | It won't appear in lists, but its transactions still count in totals, budgets and charts. | S · D-69 |
| `accounts_edit_hidden` | الحساب اتخفى. حركاته لسه محسوبة. | Account hidden. Its transactions still count. | N + `common_action_undo` · D-69 |
| `accounts_edit_duplicate` | الكارت ده موجود، افتحه؟ | This card already exists — open it? | S · same bank + last-4 |
| `accounts_edit_openExisting` | افتحه | Open it | B |
| `accounts_edit_errorLimit` | الليميت ميكونش بالسالب | The limit can't be negative | S |
| `accounts_edit_errorDueDay` | اختار يوم من {min} لـ {max} | Pick a day from {min} to {max} | S · min = 1, max = 31 |
| `accounts_edit_saved` | اتحفظ ✓ | Saved ✓ | N |
| `accounts_merge_pickTitle` | تدمجه مع أنهي كارت؟ | Merge into which card? | T |
| `accounts_merge_confirmTitle` | `{count, plural, =0{تدمج {fromCard} في {toCard}؟} =1{تنقل حركة واحدة من {fromCard} لـ {toCard}؟} =2{تنقل حركتين من {fromCard} لـ {toCard}؟} few{تنقل {n} حركات من {fromCard} لـ {toCard}؟} many{تنقل {n} حركة من {fromCard} لـ {toCard}؟} other{تنقل {n} حركة من {fromCard} لـ {toCard}؟}}` | `{count, plural, =0{Merge {fromCard} into {toCard}?} =1{Move 1 transaction from {fromCard} into {toCard}?} other{Move {n} transactions from {fromCard} into {toCard}?}}` | T · count:int, n · see Q-12 |
| `accounts_merge_confirmBody` | الكارتين هيبقوا كارت واحد. | The two cards will become one. | S |
| `accounts_merge_copyCapture` | انقل إعدادات القراية كمان | Also copy capture settings | L · checkbox (EC-60) |
| `accounts_merge_confirm` | ادمج | Merge | B |
| `accounts_merge_differentBank` | الكارتين من بنكين مختلفين. متأكد إنهم نفس الكارت؟ | These cards are from different banks. Sure they're the same card? | S · warning dialog |
| `accounts_merge_differentBankConfirm` | أيوه، ادمج | Yes, merge | B |
| `accounts_merge_errorSelf` | مينفعش تدمج الكارت في نفسه | A card can't be merged into itself | S |
| `accounts_merge_done` | اتدمجوا ✓ | Merged ✓ | N |

## 1.21 S-61 Capture settings — `capture_settings_*`, `capture_ignore_*`, `capture_rescan_*`, `capture_rescanOffer_*`, `capture_banks_*`, `capture_shareHow_*`
States: all on · permission revoked (✖ + Fix) · iOS checker result · not-tracked list / empty · re-scan running / done · some messages unreadable · Gold-locked templates · error.

| Key | AR | EN | Notes |
|---|---|---|---|
| `capture_settings_title` | زغلول بيقرا منين | Capture | T · glossary |
| `capture_settings_sources` | المصادر | Sources | L · section |
| `capture_settings_on` | شغال | On | C · Android permission granted |
| `capture_settings_off` | مقفول | Off | C · + `common_action_fix` when a permission is revoked |
| `capture_settings_active` | شغال | Active | C · iOS Apple Pay / Shortcuts row when the setup checker passes (F-5b) |
| `capture_settings_unknown` | لسه مش متأكدين | Not sure yet | C · iOS checker can't tell (FR-ING-I-07). Never shown as a failure; + `capture_settings_checkSetup` |
| `capture_settings_smsIos` | عن طريق الاختصارات | Via Shortcuts | C · iOS SMS row subtitle |
| `capture_settings_checkSetup` | اتأكد من الإعداد | Check setup | B · iOS, opens S-03 step 2 |
| `capture_settings_share` | ابعت أو الزق رسالة | Share or paste a message | L · opens `capture_shareHow_*` |
| `capture_settings_notTracked` | مش متتبعين | Not tracked | L · section (FR-CAP-06) |
| `capture_settings_notTrackedEmpty` | كل كروتك متتبعة | All your cards are tracked | S |
| `capture_settings_ignoredChannels` | {channels} مقفولة | {channels} off | L · channels = list of `common_channel_*Short` joined by the locale's list format. Row title = card or bank. + `common_action_undo` |
| `capture_settings_addIgnore` | متتابعش كارت أو بنك | Don't track a card or bank | L · FR-CAP-03 |
| `capture_settings_tools` | أدوات | Tools | L · section |
| `capture_settings_rescan` | دوّر في الرسايل القديمة تاني | Re-scan SMS inbox | L · Android |
| `capture_settings_banks` | البنوك اللي زغلول بيفهمها | Supported banks | L |
| `capture_settings_requestBank` | اطلب دعم بنكك | Request my bank | L · opens `ingestion_requestBank_*` |
| `capture_settings_templates` | قوالب رسايل خاصة بيك | Custom message templates | L · `common_gold_badge`; Free opens S-68 |
| `capture_settings_unreadable` | في رسايل مقدرتش أقراها. دوّر في الرسايل تاني عشان ميفوتكش حاجة. | Some messages couldn't be read. Re-scan so nothing's missed. | N · Android `SPOOL_DECRYPT_FAILED` |
| `capture_ignore_title` | متتابعش كارت أو بنك | Don't track a card or bank | T · sheet |
| `capture_ignore_bank` | البنك | Bank | L |
| `capture_ignore_last4` | آخر أربع أرقام (اختياري) | Last four digits (optional) | L |
| `capture_ignore_last4Hint` | سيبه فاضي عشان تبطّل تتابع البنك كله | Leave it empty to stop tracking the whole bank | S · FR-CAP-05 |
| `capture_ignore_channels` | متقراش من: | Stop reading: | L · `common_channel_*` checkboxes |
| `capture_ignore_privacy` | اللي تقفله، زغلول هيتجاهل رسايله ومش هيحفظ منها حاجة. | Messages for anything you switch off are ignored and never saved. | S · BR-CAP-01; spec wording (`screens/70`). It doesn't claim "won't look", because the institution and card are identified in memory before the message is discarded (F-4) |
| `capture_ignore_errorBank` | اختار البنك | Choose the bank | S |
| `capture_ignore_errorChannel` | اختار مصدر واحد على الأقل | Pick at least one source | S |
| `capture_ignore_errorLast4` | سيبه فاضي أو اكتب أربع أرقام | Leave it empty or enter four digits | S |
| `capture_ignore_saved` | تمام، مش هتابعه | Done — no longer tracking it | N + `common_action_undo` |
| `capture_rescan_title` | دوّر في الرسايل القديمة | Re-scan old messages | T · FR-CAP-07 |
| `capture_rescan_depth` | لحد إمتى؟ | How far back? | L · options `common_period_lastMonths` 6–24 (A-11) |
| `capture_rescan_start` | ابدأ | Start | B |
| `capture_rescan_running` | `{count, plural, =0{بدوّر…} =1{بدوّر… لقيت حركة جديدة} =2{بدوّر… لقيت حركتين جداد} few{بدوّر… لقيت {n} حركات جديدة} many{بدوّر… لقيت {n} حركة جديدة} other{بدوّر… لقيت {n} حركة جديدة}}` | `{count, plural, =0{Searching…} =1{Searching… 1 new found} other{Searching… {n} new found}}` | L · count:int, n · Rive `scanning`, C-27 with cancel |
| `capture_rescan_done` | `{count, plural, =0{ملقيتش حركات جديدة ✓} =1{ضفت حركة جديدة ✓} =2{ضفت حركتين جداد ✓} few{ضفت {n} حركات جديدة ✓} many{ضفت {n} حركة جديدة ✓} other{ضفت {n} حركة جديدة ✓}}` | `{count, plural, =0{No new transactions ✓} =1{Added 1 new transaction ✓} other{Added {n} new transactions ✓}}` | N · count:int, n |
| `capture_rescan_noDuplicates` | اللي اتسجل قبل كده مش هيتكرر | Nothing already saved will be added twice | S |
| `capture_rescanOffer_title` | أدوّر في الرسايل القديمة على حركات {card}؟ | Look through old messages for {card}? | T · after un-ignoring (Android) |
| `capture_rescanOffer_body` | الرسايل اللي اتقفلت قبل كده متحفظتش، بس ممكن ألاقيها لسه في صندوق الرسايل. | Messages were not saved while it was off, but they may still be in your inbox. | S · BR-CAP-04 |
| `capture_rescanOffer_yes` | دوّر | Search | B |
| `capture_banks_title` | البنوك اللي زغلول بيفهمها | Supported banks | T |
| `capture_banks_search` | دوّر على بنك… | Search banks… | L |
| `capture_banks_noResults` | مفيش بنك بالاسم ده | No bank by that name | S · + `capture_settings_requestBank` |
| `capture_banks_channels` | بيتسجل من: {channels} | Tracked via: {channels} | L · per-bank line on both platforms. channels = `common_channel_*Short` from the registry (F-5c) |
| `capture_banks_iosNote` | على الآيفون، {bank} بيتسجل من Apple Pay والسكرين شوت، وكشوف الحساب مع جولد. الآيفون مش بيسمح لزغلول يقرا إشعارات التطبيقات التانية. | On iPhone, {bank} is tracked through Apple Pay and screenshots, and statements with Gold. iOS doesn't let Zaghlol read other apps' notifications. | S · FR-ING-I-08. Statements are Gold (FR-EXP-04/06), so the copy says so (F-8) |
| `capture_shareHow_title` | إزاي تبعت رسالة لزغلول | How to share a message | T · shared by S-02 and S-61 |
| `capture_shareHow_step1` | افتح رسالة البنك في تطبيق الرسايل | Open the bank message in your messages app | S |
| `capture_shareHow_step2` | دوس عليها شوية واختار «مشاركة» أو «نسخ» | Long-press it and choose Share or Copy | S · OS labels may differ, see Q-04 |
| `capture_shareHow_step3` | اختار زغلول، أو افتح زغلول والزقها | Pick Zaghlol — or open Zaghlol and paste it | S |
| `capture_shareHow_note` | هتشوفها قبل ما تتسجل. | You'll check it before it's saved. | S · FR-ING-A-04 |

## 1.22 S-62 Card capture controls — `capture_cardControls_*`, `capture_stopTracking_*`
| Key | AR | EN | Notes |
|---|---|---|---|
| `capture_cardControls_title` | زغلول يقرا إيه من {card}؟ | What should Zaghlol read from {card}? | T · sheet; switches use `common_channel_*` |
| `capture_cardControls_subtitle` | اختار براحتك، وتقدر تغير في أي وقت | Your choice — change it any time | S |
| `capture_cardControls_smsIos` | عن طريق اختصارات الآيفون | Through iPhone Shortcuts | L · switch subtitle |
| `capture_cardControls_applePaySub` | الدفع بالموبايل | Phone payments | C |
| `capture_cardControls_info` | لما تقفل حاجة هنا، رسايل الكارت ده هتتجاهل ومش هتتحفظ. | When a switch is off, messages for this card are ignored and never saved. | S · BR-CAP-01; spec wording (`screens/70:60-61`) (F-4) |
| `capture_stopTracking_title` | تبطّل تتابع {card}؟ | Stop tracking {card}? | T · last channel switched off (FR-CAP-04). Serious, no emoji |
| `capture_stopTracking_existing` | الحركات اللي اتسجلت قبل كده: | Transactions already saved: | L |
| `capture_stopTracking_keep` | سيبهم زي ما هم | Keep them | L · radio, default |
| `capture_stopTracking_delete` | `{count, plural, =1{امسح حركة واحدة} =2{امسح الحركتين} few{امسح الـ {n} حركات} many{امسح الـ {n} حركة} other{امسح الـ {n} حركة}}` | `{count, plural, =1{Delete 1 transaction} other{Delete {n} transactions}}` | L · radio; count:int, n · hidden when the card has no transactions (§0.4) |
| `capture_stopTracking_confirm` | بطّل المتابعة | Stop tracking | B |
| `capture_stopTracking_deleteTitle` | `{count, plural, =1{تمسح حركة واحدة نهائي؟} =2{تمسح الحركتين نهائي؟} few{تمسح {n} حركات نهائي؟} many{تمسح {n} حركة نهائي؟} other{تمسح {n} حركة نهائي؟}}` | `{count, plural, =1{Delete 1 transaction for good?} other{Delete {n} transactions for good?}}` | T · count:int, n · second confirmation |
| `capture_stopTracking_deleteBody` | مفيش رجوع. الحركات دي هتتمسح من الموبايل وكل الأرقام هتتحدث. | This can't be undone. These transactions will be deleted from this phone and every total will update. | S |
| `capture_stopTracking_deleteConfirm` | امسح نهائي | Delete for good | B · destructive |
| `capture_stopTracking_done` | مش هتابع {card} تاني | No longer tracking {card} | N + `common_action_undo` (restores the switches only; deleted data stays deleted) |

## 1.23 Native (OS-surfaced) strings — `native_*` (not in ARB)
These strings are shown by iOS or Android, outside Flutter. **T-029 skips this table.** The native capture/security tasks transcribe them into `InfoPlist.strings` / AppIntents string catalogs (iOS) and `res/values{,-ar}/strings.xml` (Android). Same rules as the rest of the deck: no digits in AR, financial-data-only privacy claim, no jokes. Shortcut-package automation names (e.g. `Zaghlol – Wallet`) live in the signed `.shortcut` file and stay Latin (Q-04).

| Key | AR | EN | Notes |
|---|---|---|---|
| `native_ios_faceIdUsage` | زغلول بيستخدم Face ID عشان يفتح التطبيق، ومحدش يشوف فلوسك غيرك. | Zaghlol uses Face ID to unlock the app, so only you can see your money. | S · `NSFaceIDUsageDescription` (S-05, app lock) |
| `native_ios_shareExtensionName` | زغلول | Zaghlol | C · share-extension display name (FR-ING-A-04 on iOS) |
| `native_ios_intentLogMessageTitle` | سجّل رسالة بنك في زغلول | Log bank message in Zaghlol | L · `LogBankMessageIntent` title (S-03) |
| `native_ios_intentLogMessageDesc` | بيدّي نص رسالة البنك لزغلول على الموبايل ده عشان يسجل الحركة. | Hands a bank message to Zaghlol on this phone so it can log it. | S · intent description shown in Shortcuts |
| `native_ios_intentMessageParam` | نص الرسالة | Message text | L · intent parameter |
| `native_ios_intentLogWalletTitle` | سجّل دفع Apple Pay في زغلول | Log Apple Pay payment in Zaghlol | L · `LogWalletTransactionIntent` title |
| `native_ios_intentLogWalletDesc` | بيدّي تفاصيل دفع Apple Pay لزغلول على الموبايل ده عشان يسجله. | Hands an Apple Pay payment to Zaghlol on this phone so it can log it. | S |
| `native_ios_intentMerchantParam` | التاجر | Merchant | L · Wallet automation parameter |
| `native_ios_intentAmountParam` | المبلغ | Amount | L |
| `native_ios_intentCardParam` | الكارت | Card | L |
| `native_android_notifListenerLabel` | زغلول: إشعارات البنوك | Zaghlol: bank notifications | L · `NotificationListenerService` label; this is the row that `onboarding_androidSetup_notifOsHint` tells the user to find |
| `native_android_notifListenerDesc` | بيقرا إشعارات تطبيقات البنوك والمحافظ بس، وبيانات فلوسك بتفضل على الموبايل ده. | Reads notifications from bank and wallet apps only. Your money data stays on this phone. | S · service description where the OS shows one. Financial-data-only claim (tone gate 4) |

---

## 1.K Key count (Part 1)
| Section | Screens | Keys |
|---|---|---|
| 1.1 `common_*` | shared | 124 |
| 1.2 `mascot_*` | shared | 13 |
| 1.3 Welcome | S-01 | 10 |
| 1.4 Android setup | S-02 | 29 |
| 1.5 iOS setup | S-03 | 42 |
| 1.6 Restore | S-04 | 30 |
| 1.7 App lock | S-05 | 7 |
| 1.8 Scan results | S-06 | 14 |
| 1.9 Home | S-10 | 58 |
| 1.10 Transaction row | C-05 | 10 |
| 1.11 Transactions | S-11 | 26 |
| 1.12 Detail + rule sheet (`categorization_rule_*`) | S-12 | 41 |
| 1.13 Add / edit | S-13 | 20 |
| 1.14 Review queue + request bank | S-14 | 41 |
| 1.15 Split & reimbursements | S-15 | 29 |
| 1.16 Link transfer | S-16 | 17 |
| 1.17 Money overview + add flow | S-40, S-43 create | 48 |
| 1.18 Card detail | S-41 | 21 |
| 1.19 Compare | S-42 | 7 |
| 1.20 Edit card + merge | S-43 | 34 |
| 1.21 Capture settings | S-61 | 48 |
| 1.22 Card capture controls | S-62 | 14 |
| **ARB total** | | **683** |
| 1.23 Native (not ARB) | S-03, S-05, S-02 | 12 |

Plural messages: 38 (15 with `=0`, 23 on the no-zero list in §0.4). Select messages: 8. Each ARB row is one key in both `app_ar.arb` and `app_en.arb`. Note for scripted counts: the §0.4 no-zero table also starts rows with backticked key names. Count only rows that have four cells.

## 1.Q Open questions and spec gaps (Part 1)
| ID | Where | Issue | Draft used | Needs |
|---|---|---|---|---|
| Q-01 | Tab 2 label | `03-navigation.md` says «التحليلات»; the glossary (D-34) says «الحسبة». | «الحسبة» | Confirm the glossary wins and update `03-navigation.md` |
| Q-02 | Source badge | **Closed.** `database-schema.md` already has `source = 'share'` (channel `share`/`paste`). | `common_source_shared` maps to `share` | Requirements analyst: wording fix in FR-TXN-03 only |
| Q-03 | S-02 | **Narrowed.** The `prodNoSms` flavour exists (ADR-004, `deployment.md`). Still open: the S-02 flow in that flavour, i.e. whether step 1 is skipped and where `playUnavailable` appears. | `onboarding_androidSetup_playUnavailable` | Architect + UX: the S-02 flow for `prodNoSms` |
| Q-04 | S-03, share how-to | iOS and Android OS labels ("Shortcuts", "Automation", "Run Immediately", "Share") differ by device language and OEM. | English OS labels kept in Latin | Verify on Arabic-language iOS; decide whether to show localized OS labels |
| Q-05 | Home greeting | Spec gives only «صباح الفل / مساء الفل» by time. Hour boundaries and the English afternoon form aren't defined. | Morning 05–12, afternoon 12–17, evening 17–05 | Confirm the boundaries |
| Q-06 | Home hero | **Narrowed.** BR-BUD-03 clamps safe-to-spend at 0. The only open point is the display: the amount `0` with a caption. | `home_hero_budgetUsedUp` as the caption under `0` | UX: confirm the "0 + caption" display |
| Q-07 | Payday prompt | **Closed by D-68.** A salary on day 29–31 → suggest payday = 1 (calendar month); the salary counts in the month it arrives; payday stays 1–28. | `home_prompt_paydayMonthStart` / `…MonthStartYes` | — |
| Q-08 | S-11 bulk delete | **Closed, not a gap.** FR-TXN-06: changes get Undo; delete asks first and can't be undone. The deck already matches. | — | — |
| Q-09 | S-14 request bank | The screen spec says "only the bank's name and country"; FR-PAR-14 also sends the channel type. | The SRS (name, country, alert type) | Update the S-14 spec text |
| Q-10 | Add type sheet | InstaPay is a transfer rail, not a wallet. | Replaced with Vodafone Cash, Orange Cash, e& cash | PO/legal: brand clearance (OQ-09, already open) |
| Q-11 | S-41/S-43 Hide | **Closed by D-69.** Hiding removes the account from lists and pickers only; its transactions still count in totals, budgets and charts; unhiding restores it to lists. | `accounts_edit_hideHint`, `accounts_edit_hidden`, `accounts_overview_hiddenEntry` | **Confirmed in Part 2 (R2-4):** the S-40 spec now has the row and the list; keys are in §2.12 |
| Q-12 | S-43 Merge | Whether a merge can be undone isn't specified. | No undo claimed, no "can't undo" claimed | Architect (`merged_into_id`, reversible?) + UX |
| Q-13 | C-05 / S-12 | Wider than first stated: EC-06, A-63 and the schema's `status IN ('posted','pending','declined','reversed')` mean pending and reversed rows can exist. The S-12 spec says pending is n/a. | No copy for pending/reversed | Architect + UX: define the row and detail states; the copy follows in a later Part 1 revision |
| Q-14 | Process | The task asks for the design note in the task file, but the brief limited edits to `copy-deck.md`. | Design note in §1.0 | Lead to copy it into `T-026.md` if wanted |
| Q-15 | Plural/digits convention | §0.3/§0.4 make every number a pre-formatted String and use `count` only to select. That needs the architect to confirm it against `DigitsMode` (ADR-017). | As written | Architect confirmation before T-029 |
| Q-16 | Bidi isolates | §0.6 puts FSI/PDI wrapping in the presentation layer, not in ARB text; the §0.3a registry marks which placeholders get it. | As written | Architect confirmation (`MoneyFormat` / l10n helper) |
| Q-17 | Glossary | `06-voice-and-tone.md` §3 maps Notifications → «التنبيهات», but the deck uses «الإشعارات». | **Proposed split:** «التنبيهات» for Zaghlol's own notifications (S-70, Part 3); «الإشعارات» for other apps' notifications that Zaghlol captures, because that's the OS term users see in Android settings. Part 1 strings are all of the second kind. | UX lead / PO: confirm the split, then add it to the glossary |
| Q-18 | Home payday banner | `home_mascot_payday` is a C-14 banner, but `domain-algorithms.md` §7 treats `payday` as motion-only, and the priority list (shocked > detective > proud > tourGuide) has no payday slot. | Proposed: shocked > detective > payday > proud > tourGuide | Architect: place `payday` in `MascotPolicy`, or move the line off the banner |

## 1.C Changelog (Part 1)
- 2026-11-07 — first draft (T-026), 676 keys.
- 2026-11-07 — round 2 (code review F-1…F-20, test check D-1…D-6, PO decisions D-68/D-69), 683 ARB keys plus 12 native. Nothing had shipped yet (T-029 not started), so keys were retired and renamed in place.
  - **Retired** (now use `common_action_*`, per the §0.10 reuse rule): `transactions_list_bulkDelete`, `transactions_list_bulkCancel`, `ingestion_review_genConfirm`, `ingestion_review_genEdit`, `ingestion_review_genDismiss`, `ingestion_requestBank_send`, `transfers_link_link`, `home_prompt_paydayNo`.
  - **Renamed:**
    - `mascot_avatar_a11y` → `mascot_avatar_labelA11y`
    - `home_hero_a11y` → `home_hero_summaryA11y`
    - `transactions_row_a11y` → `transactions_row_labelA11y`
    - `transactions_rule_{title,always,once,applyPast,saved}` → `categorization_rule_*`
  - **Added:**
    - `common_date_hoursAgo`, `onboarding_iosSetup_shortcutWhy`, `backup_restore_signingIn`
    - `home_prompt_paydayMonthStart`, `home_prompt_paydayMonthStartYes`
    - `transfers_split_removePerson`, `transfers_split_unassign`, `transfers_split_unassigned`
    - `transfers_link_afterHours`, `transfers_link_beforeHours`
    - `accounts_overview_hiddenEntry`, `accounts_edit_hidden`
    - `capture_settings_active`, `capture_settings_unknown`, `capture_banks_channels`
    - §1.23 `native_*` (12)
  - **Conventions:** §0.3a placeholder registry; zero-form rule in §0.4; text buttons use class L.

<!-- ===================== PART 2 (T-027) appends below ===================== -->

---

# PART 2 — T-027: insights, budget, bills, quick add, voice, scan, assets, prices, Zakah, chat, roast, Smart ROI

## 2.0 Approach (design note, C3)
- **Scope**: every user-visible string on S-20…S-25 (S-25 is the bill editor that S-24 opens, so it travels with it), S-30…S-32, S-44…S-46, S-50 and S-51, plus the S-40 pieces Part 1 deferred (F-18): the assets section, the net-worth unit lines and the hidden-accounts row and list (R2-4). Each string covers every state in its spec: empty, loading, populated, error, offline, permission denied and Gold-locked.
- **Not in scope** (Part 3): the paywall S-68, notification text (budget-threshold and bill-reminder alerts included), settings, legal pages, the Failure-code catalogue and share-card text. The Zakah and Smart ROI disclaimers are screen-bound (FR-ZAK-05, FR-ROI-02), so they live here.
- **Reuse, not repeats**: Home already owns the budget and subscription mascot banners (`home_mascot_shockedCategory`, `…shockedDining`, `…detectiveSubscription*`, `…proudOnTrack`). S-22 and S-24 show those same C-14 messages and add no copy of their own. The generic `common_action_*`, `common_validation_*`, `common_discard_*`, `common_gold_*`, `common_badge_stale` and `common_currency_*` keys are used as they are.
- **Key families**: `insights_*` (S-20/21 and explanations), `budget_*` (S-22/23), `recurring_*` (S-24/25), `home_quickAdd_*` (S-30), `voice_logger_*` (S-31), `capture_scan_*` (S-32), `wealth_*` (S-40 assets, S-44, S-45), `accounts_hidden_*` (hidden list), `zakah_*`, `roi_*`, `chat_*`. They follow the module map in `architecture.md` §4.2.

### 2.0.1 Chart explanations: Free "basic" vs Gold "deep" (resolves OQ-07)
`domain-algorithms.md` §8 drafted the split. This deck makes it final and testable.

| | **Basic** (Free and Gold) | **Deep coaching** (Gold only) |
|---|---|---|
| Parts shown | one fact (`…_basic`) and one tip (`…_tip`) | the basic fact, then `…_deep` and `…_deepTip` **instead of** the basic tip |
| What the fact says | what this chart shows for the selected period, card and currency | the same fact, then how it compares with the **previous cycle** (or the 3-cycle average where the chart needs one) |
| What the tip says | one action with one computed figure | a sized action: a target amount per cycle and what it adds up to over a year |
| Extras | none | on charts 1, 2, 3, 5 and 7 the engine may append `insights_deep_projection` (end-of-cycle projection at the current burn) and `insights_deep_drivers` (the top three merchants behind the change) |

Rules for both tiers:
1. Free is never less *accurate* than Gold, only narrower. Every number is computed from the user's data. If the engine can't compute a value, it drops the whole sentence and never shows a placeholder or a guess.
2. Templates are chosen by rules, not generated by a model. The most salient fact wins (largest share, biggest rise, longest streak), and a `state` or `trend` select picks the wording.
3. The explanation is one Zaghlol bubble (C-15) in the `professor` pose. It uses class **E** (§0.7). Money alerts in a chart (overspending, a short month) use calm wording and no emoji.
4. Free users see `insights_chartDetail_deepUpsell` once under the basic tip. It is a normal locked-feature prompt and counts toward the one-unsolicited-paywall-a-week rule (A-22) only when it first appears.
5. The placeholders `trend` and `state` are selects. Each key's note lists its branches. `other` is always the branch named last in the note.

### 2.0.2 Roast rules (A-18): the checklist every roast line passed
Roast mode (FR-CHAT-04) only appends a line after the normal, exact answer, so the numbers are identical with it on or off (C-33). A line passes only if all of these are true:

| # | Rule |
|---|---|
| R1 | It targets **spending**: a category, a merchant, a habit, a day. Never the person. |
| R2 | Nothing about body, health, family, religion, region, gender, age, looks, intelligence, income, debt or politics. No jokes about Zakah, charity, Ramadan or giving. |
| R3 | Never roast essentials: rent, bills, groceries, health, education, fees, debt payments, transport to work. The engine skips those categories. |
| R4 | Never roast hardship. If the user spent more than they earned this cycle, or has an overdue bill, the engine uses `chat_roast_gentle` and nothing else. |
| R5 | No comparison to other people ("your neighbour saves more"). Comparing to the user's own past is fine. |
| R6 | It is affectionate: playful exaggeration, not contempt. Words like «غبي» «فاشل» «مفلس» «بخيل» and their English equivalents are banned. |
| R7 | At most one emoji per line. None in the gentle line. |
| R8 | A line is only used when its fact is **true and computed** (orders, amount, day, time). A line that needs a value the engine doesn't have is not eligible. |
| R9 | Roast mode is off by default, can be turned off at any moment, and never starts by itself. The toggle says in plain words that only the style changes. |

### 2.0.3 Chat answer rules
- Every answer is a template filled with figures from a local query. Nothing is estimated, rounded up for effect or invented (FR-CHAT-03).
- **One figure per currency** (FR-CHAT-01): the engine renders the same template once per currency and puts `chat_answer_currencyLead` in front of each when there is more than one.
- A period in a sentence is a `span`: a copy string from `chat_period_*`, resolved by the caller. Money, dates and merchant names arrive formatted, as in §0.3.
- An answer never contains a phrase like "tap here". The "open in Transactions" action is a separate button.

### 2.0.4 New length class and registry rows
- Class **E** (explanation or chat answer, two or three sentences) is added to §0.7.
- Part 2's new placeholders are added to the §0.3a registry in this commit (listed in the changelog, §2.C).
- Unit and cadence words that several screens share are in `common_*` below (§2.1) and are not redefined.

### 2.0.5 Spec edits made with this part
`screens/50-money.md` (S-40) now describes the assets rows, the unit lines and the hidden-accounts row and list (R2-4). The `accounts_overview_hiddenEntry` note and Q-11 are updated to match.

---

## 2.1 Shared (Part 2) — `common_*` and `mascot_*`

### Shared actions
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_action_typeInstead` | اكتبها بإيدك | Type it instead | B · S-31 and S-32 fallback |

### Units, cadence and asset types
| Key | AR | EN | Notes |
|---|---|---|---|
| `common_unit_grams` | {n} جرام | {n} g | C · n = grams, up to three decimals (FR-WLT-02) |
| `common_unit_perMonth` | {amount} في الشهر | {amount}/mo | L |
| `common_unit_perYear` | {amount} في السنة | {amount}/yr | L |
| `common_unit_perDay` | {amount} في اليوم | {amount}/day | L |
| `common_unit_visits` | `{count, plural, =1{زيارة واحدة} =2{زيارتين} few{{n} زيارات} many{{n} زيارة} other{{n} زيارة}}` | `{count, plural, =1{1 visit} other{{n} visits}}` | C · count:int, n · inserted into sentences as `{visits}` |
| `common_unit_orders` | `{count, plural, =1{أوردر واحد} =2{أوردرين} few{{n} أوردرات} many{{n} أوردر} other{{n} أوردر}}` | `{count, plural, =1{1 order} other{{n} orders}}` | C · count:int, n · inserted as `{orders}` |
| `common_cadence_weekly` | كل أسبوع | Weekly | L |
| `common_cadence_monthly` | كل شهر | Monthly | L |
| `common_cadence_quarterly` | كل تلات شهور | Every 3 months | L |
| `common_cadence_semiannual` | كل ستة شهور | Every 6 months | L |
| `common_cadence_yearly` | كل سنة | Yearly | L |
| `common_assetType_gold` | دهب | Gold | C · asset type (FR-WLT-02) |
| `common_assetType_certificate` | شهادة بنك | Bank certificate | C |
| `common_assetType_foreignCash` | كاش بعملة | Foreign cash | C |
| `common_assetType_stocks` | أسهم وصناديق | Stocks & funds | C |
| `common_assetType_property` | عقار | Property | C |
| `common_assetType_car` | عربية | Car | C |
| `common_karat_label` | عيار {karat} | {karat}K | C · karat = 24, 21 or 18 from the digits layer |
| `common_karat_coin` | جنيه دهب | Gold coin | C · the gold pound |

### Mascot tap lines (continued from Part 1)
| Key | AR | EN | Notes |
|---|---|---|---|
| `mascot_tap_line9` | عايز تعرف فلوسك راحت فين؟ افتح الحسبة | Wondering where it all went? Try Insights | M · Rive `tap` |
| `mascot_tap_line10` | أنا بحسب والدهب بيلمع، وإنت بتحوّش | I count, the gold shines, you save | M · Rive `tap` |

---

## 2.2 S-20 Charts — `insights_tabs_*`, `insights_period_*`, `insights_charts_*`, `insights_chartTitle_*`, `insights_legend_*`, `insights_chartA11y_*`
States: loading (chart-shaped skeletons) · populated · empty (less than one full cycle, EC-23) · ≈ view · Gold-locked card · per-card error (one chart failing never blanks the page) · filter-caused empty. The 12 charts appear in the fixed order of FR-CHT-01, Free charts first (A-06). Chart titles are class T and appear on the card and on S-21.

| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_tabs_charts` | الشارتات | Charts | C · C-35 segment 1 |
| `insights_tabs_budget` | الميزانية | Budget | C · segment 2 |
| `insights_tabs_bills` | الفواتير | Bills | C · segment 3 |
| `insights_period_title` | الفترة | Period | T · period sheet. Items use `common_period_*`; Apply uses `common_action_done` |
| `insights_period_start` | من | From | L · custom range |
| `insights_period_end` | لحد | To | L · custom range. Validation: `common_validation_dateRange` |
| `insights_charts_context` | {cards} · {currency} · {period} | {cards} · {currency} · {period} | L · filter context line under each chart title (C-13). period = `common_period_*` or `common_date_range` |
| `insights_charts_explain` | اشرحلي يا زغلول | Explain this | B · the FR-CHT-03 name. Also the S-21 button |
| `insights_charts_lockedSub` | شوف الشارت كله مع جولد | See the full chart with Gold | S · C-13 locked, blurred preview + `common_gold_unlock` |
| `insights_charts_emptyCycle` | بيحيا بعد أول دورة كاملة | Comes alive after your first full cycle | S · C-13 empty (EC-23) |
| `insights_charts_emptyNetWorth` | ضيف حسابات أو أصول علشان الشارت ده يشتغل | Add accounts or assets to bring this chart to life | S · charts 8 and 11 when they have nothing to show |
| `insights_charts_emptyNetWorthAction` | افتح فلوسي | Open Money | B · opens S-40 |
| `insights_charts_emptyFilter` | مفيش بيانات للفلتر ده في الفترة دي | No data for this filter in this period | S · plus `common_action_clearFilter` |
| `insights_charts_cardError` | الشارت ده مفتحش. باقي الشارتات تمام. | This chart didn't load. The others are fine. | S · C-29 inline; plus `common_action_tryAgain` |
| `insights_charts_loadingA11y` | بحمّل الشارتات | Loading charts | A |
| `insights_charts_otherSlice` | حاجات تانية | Other | C · donut remainder slice |
| `insights_chartTitle_cashFlow` | الداخل والخارج والصافي | Cash flow | T · chart 1 (Free) |
| `insights_chartTitle_categories` | فلوسك رايحة فين؟ | Where your money went | T · chart 2 (Free) |
| `insights_chartTitle_burnRate` | سرعة الصرف لحد القبض | Burn rate to payday | T · chart 3 (Gold) |
| `insights_chartTitle_rule503020` | ميزان خمسين تلاتين عشرين | 50/30/20 balance | T · chart 4 (Gold) |
| `insights_chartTitle_weekPattern` | إمتى بتصرف؟ | When you spend | T · chart 5 (Gold), day of week and hour |
| `insights_chartTitle_merchants` | أكتر الأماكن اللي بتاخد فلوسك | Top merchants | T · chart 6 (Free, top five) |
| `insights_chartTitle_vsAverage` | الدورة دي ضد متوسط تلات دورات | This cycle vs your 3-cycle average | T · chart 7 (Gold) |
| `insights_chartTitle_installments` | أقساطك في الستة شهور الجايين | Installments, next 6 months | T · chart 8 (Gold) |
| `insights_chartTitle_subscriptions` | الاشتراكات في السنة كلها | Subscriptions over a year | T · chart 9 (Gold) |
| `insights_chartTitle_cards` | الصرف على كروتك ومحافظك | Cards & wallets | T · chart 10 (Gold) |
| `insights_chartTitle_netWorth` | نمو اللي حيلتك كله | Net worth growth | T · chart 11 (Gold) |
| `insights_chartTitle_inflation` | الغلاء على سلتك إنت | Your personal inflation | T · chart 12 (Gold) |
| `insights_legend_income` | دخلك | Income | C |
| `insights_legend_spent` | صرفت | Spent | C |
| `insights_legend_saved` | حوشت | Saved | C |
| `insights_legend_actual` | فعلي | Actual | C · chart 3 |
| `insights_legend_ideal` | الخط المثالي | Ideal pace | C · chart 3 dotted line |
| `insights_legend_today` | النهارده | Today | C · chart 3 marker |
| `insights_legend_payday` | القبض | Payday | C · chart 3 end marker |
| `insights_legend_needs` | أساسيات | Needs | C · chart 4 |
| `insights_legend_wants` | رفاهيات | Wants | C |
| `insights_legend_savings` | تحويش | Savings | C |
| `insights_legend_target` | المثالي | Target | C · chart 4 target mark |
| `insights_legend_average` | متوسطك | Your average | C · chart 7 |
| `insights_legend_thisCycle` | الدورة دي | This cycle | C · chart 7 |
| `insights_legend_installments` | أقساط | Installments | C · chart 8 |
| `insights_legend_cardDues` | كروت وجمعية | Cards & gameya | C · chart 8 |
| `insights_legend_monthly` | في الشهر | Per month | C · chart 9 |
| `insights_legend_yearly` | في السنة | Per year | C · chart 9, the ×12 bars |
| `insights_legend_supermarket` | متوسط فاتورة السوبرماركت | Avg supermarket basket | L · chart 12 |
| `insights_legend_delivery` | متوسط أوردر الدليفري | Avg delivery order | L · chart 12 |
| `insights_chartA11y_cashFlow` | الداخل والخارج: دخلك {income}، صرفت {spent}، وحوشت {saved} | Cash flow: income {income}, spent {spent}, saved {saved} | A |
| `insights_chartA11y_categories` | فلوسك رايحة فين: {category} الأكبر بـ {amount}، يعني {percent} | Where your money went: {category} is the largest at {amount}, {percent} | A |
| `insights_chartA11y_burnRate` | سرعة الصرف: صرفت {spent} من {budget} في اليوم {cycleDay} | Burn rate: spent {spent} of {budget} on day {cycleDay} | A |
| `insights_chartA11y_rule503020` | ميزان خمسين تلاتين عشرين: {needsPct} أساسيات، {wantsPct} رفاهيات، {savingsPct} تحويش | 50/30/20: {needsPct} needs, {wantsPct} wants, {savingsPct} savings | A |
| `insights_chartA11y_weekPattern` | إمتى بتصرف: أعلى يوم {peakDay} بمتوسط {amount} | When you spend: busiest day is {peakDay}, averaging {amount} | A |
| `insights_chartA11y_merchants` | أكتر الأماكن: {merchant} الأول بـ {amount} | Top merchants: {merchant} first with {amount} | A |
| `insights_chartA11y_vsAverage` | الدورة دي ضد متوسطك: أكبر زيادة في {category} بـ {percent} | This cycle vs average: biggest rise is {category} at {percent} | A |
| `insights_chartA11y_installments` | الأقساط: الشهر ده {sum} | Installments: {sum} due this month | A |
| `insights_chartA11y_subscriptions` | الاشتراكات: {monthly} في الشهر، يعني {yearly} في السنة | Subscriptions: {monthly} a month, {yearly} a year | A |
| `insights_chartA11y_cards` | الكروت: {card} الأكبر بـ {percent} من الصرف | Cards: {card} is the largest at {percent} of spending | A |
| `insights_chartA11y_netWorth` | اللي حيلتك كله: من {startAmount} لـ {endAmount} | Net worth: from {startAmount} to {endAmount} | A |
| `insights_chartA11y_inflation` | الغلاء: فاتورة السوبرماركت من {startAmount} لـ {endAmount} | Inflation: supermarket basket from {startAmount} to {endAmount} | A |

## 2.3 S-21 Chart detail and explainer — `insights_chartDetail_*`, `insights_deep_*`
States: populated · explainer closed (button) · typing (≤ 600 ms) · explained (basic or deep) · Gold-locked chart · empty · explainer error (bubble hidden, chart stays). Chart 10 lists spend per card per currency (FR-CHT-06).

| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_chartDetail_legendRowA11y` | {category}: {amount}، {percent}. اضغط تشوف الحركات | {category}: {amount}, {percent}. Tap to see the transactions | A · opens S-11 filtered |
| `insights_chartDetail_cardRowA11y` | {card}: {amount}. اضغط تفتح الكارت | {card}: {amount}. Tap to open the card | A · chart 10, opens S-41 |
| `insights_chartDetail_typingA11y` | زغلول بيكتب | Zaghlol is typing | A · Rive `professor`, typing dots |
| `insights_chartDetail_tipLabel` | نصيحة | Tip | C · label on the tip line |
| `insights_chartDetail_deepLabel` | تحليل أعمق | Deeper look | C · with `common_gold_badge`; shown on the deep part |
| `insights_chartDetail_deepUpsell` | عايز تحليل أعمق؟ جولد بيقارن بالدورة اللي فاتت ويتوقع آخر الدورة. | Want a deeper look? Gold compares with last cycle and projects your cycle's end. | S · Free only, once under the basic tip, plus `common_gold_unlock` |
| `insights_chartDetail_needsData` | `{need, select, cycle{محتاج دورة كاملة علشان أشرحلك الشارت ده} months{محتاج تلات دورات علشان أقارنك بنفسك} accounts{ضيف حسابات أو أصول وأنا أشرحلك} installments{ضيف قسط أو التزام وأنا أشرحلك} subscriptions{لسه مفيش اشتراكات. أول ما ألاقي واحد هشرحلك} other{محتاج بيانات أكتر علشان أشرح الشارت ده}}` | `{need, select, cycle{I need one full cycle before I can explain this chart} months{I need three cycles to compare you with yourself} accounts{Add accounts or assets and I'll explain} installments{Add an installment or commitment and I'll explain} subscriptions{No subscriptions yet. I'll explain once I spot one} other{I need more data to explain this chart}}` | M · `need:select` (cycle/months/accounts/installments/subscriptions/other) · empty explainer |
| `insights_chartDetail_explainFailed` | معرفتش أشرح الشارت ده دلوقتي | Couldn't explain this chart right now | N · bubble hidden, chart stays |
| `insights_chartDetail_lockedTitle` | الشارت ده في جولد | This chart is part of Gold | T · whole-screen locked state + `common_gold_unlock` |
| `insights_chartDetail_lockedBody` | اتفرج على شكله، وافتحه كله مع جولد | Take a look, then unlock it with Gold | S |
| `insights_deep_projection` | `{state, select, over{بالسرعة دي هتقفل الدورة على {projected}، يعني فوق ميزانيتك} other{بالسرعة دي هتقفل الدورة على {projected}، يعني في حدود ميزانيتك}}` | `{state, select, over{At this pace you'll finish the cycle at {projected}, over your budget} other{At this pace you'll finish the cycle at {projected}, within your budget}}` | S · Gold deep, charts 1, 2, 3, 5, 7 · `state:select(over/other)`. Only when a budget exists |
| `insights_deep_drivers` | أكتر التجار اللي ورا التغيير: {merchant} و{merchant2} و{merchant3} | The merchants behind the change: {merchant}, {merchant2} and {merchant3} | S · Gold deep · only when three merchants qualify |

## 2.4 Chart explanation templates — `insights_explain<Chart>_*`
Twelve charts, four keys each. Free shows `basic` + `tip`. Gold shows `basic` + `deep` + `deepTip` (§2.0.1). Rive `professor`, trigger "Explain" (S-21, C-15). Bubble class **E** for `basic` and `deep`, **S** for tips. Values are computed per the selected period, card and currency. `trend` is `up` / `down` / `other` (other = about the same). Every sentence is dropped whole if one of its values is missing.

### Chart 1 — Cash flow
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainCashFlow_basic` | `{state, select, short{الدورة دي دخلك {income} وصرفت {spent}، يعني صرفت أكتر من دخلك بـ {gap}. خلينا نظبطها سوا.} other{الدورة دي دخلك {income} وصرفت {spent}، يعني حوشت {saved}. ده {percent} من دخلك. الله ينور!}}` | `{state, select, short{This cycle you earned {income} and spent {spent}, so you're {gap} over your income. Let's sort it out together.} other{This cycle you earned {income} and spent {spent}, so you saved {saved}. That's {percent} of your income. Well done!}}` | E · `state:select(short/other)`: short = spent more than earned. No emoji in the short branch |
| `insights_explainCashFlow_tip` | `{state, select, short{قلل {category} بـ {target} الدورة الجاية وهتقفل بفايض.} other{حوّل {target} على الأقل من الفايض ده للادخار قبل ما يتصرف.}}` | `{state, select, short{Trim {category} by {target} next cycle and you'll finish in the black.} other{Move at least {target} of this surplus into savings before it gets spent.}}` | S · `state`, category = largest category, target |
| `insights_explainCashFlow_deep` | `{trend, select, up{صافي الدورة دي أحسن من الدورة اللي فاتت بـ {delta}.} down{صافي الدورة دي أقل من الدورة اللي فاتت بـ {delta}.} other{صافي الدورة دي زي الدورة اللي فاتت تقريباً.}}` | `{trend, select, up{This cycle's net is {delta} better than last cycle.} down{This cycle's net is {delta} lower than last cycle.} other{This cycle's net is about the same as last cycle.}}` | E · Gold · `trend` (up = better) |
| `insights_explainCashFlow_deepTip` | ثبّت هدف تحوّش {target} كل دورة، يعني {yearly} في السنة. | Set a goal of saving {target} every cycle. That's {yearly} a year. | S · Gold |

### Chart 2 — Where your money went
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainCategories_basic` | {category} واخد {percent} من صرفك، يعني {amount}. وبعده {category2} بـ {percent2}. | {category} takes {percent} of your spending, that's {amount}. {category2} is next at {percent2}. | E |
| `insights_explainCategories_tip` | حط سقف لـ{category} أقل بـ {target} من الدورة دي، وهتوفر الفرق. | Cap {category} {target} below this cycle and keep the difference. | S |
| `insights_explainCategories_deep` | `{trend, select, up{{category} زاد عن الدورة اللي فاتت بـ {delta}.} down{{category} قل عن الدورة اللي فاتت بـ {delta}.} other{{category} تقريباً زي الدورة اللي فاتت.}}` | `{trend, select, up{{category} is up {delta} on last cycle.} down{{category} is down {delta} on last cycle.} other{{category} is about the same as last cycle.}}` | E · Gold |
| `insights_explainCategories_deepTip` | خفّض {category} بـ {target} كل دورة، يعني {yearly} في السنة. | Bring {category} down by {target} each cycle. That's {yearly} a year. | S · Gold |

### Chart 3 — Burn rate to payday
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainBurnRate_basic` | `{state, select, over{إنت في اليوم {cycleDay} من الدورة وصارف {spent} من {budget}، يعني فوق الخط المثالي. الباقي يكفي {perDay} في اليوم بس.} other{إنت في اليوم {cycleDay} من الدورة وصارف {spent} من {budget}، يعني تحت الخط المثالي. مسموحلك {perDay} في اليوم.}}` | `{state, select, over{You're on day {cycleDay} of the cycle and have spent {spent} of {budget}, above the ideal pace. What's left covers {perDay} a day.} other{You're on day {cycleDay} of the cycle and have spent {spent} of {budget}, under the ideal pace. You can spend {perDay} a day.}}` | E · `state:select(over/other)`. perDay = BR-BUD-03 |
| `insights_explainBurnRate_tip` | `{state, select, over{نزّل صرفك اليومي لـ {perDay} لحد القبض علشان الميزانية تكفي.} other{كمّل على نفس الإيقاع، والفرق ده هيبقى فايض آخر الدورة. تقدر تصرف {perDay} في اليوم.}}` | `{state, select, over{Bring your daily spending down to {perDay} until payday so the budget lasts.} other{Keep this pace and the gap becomes surplus at the end of the cycle. You can spend {perDay} a day.}}` | S |
| `insights_explainBurnRate_deep` | `{trend, select, up{في نفس اليوم الدورة اللي فاتت كنت صارف أقل بـ {delta}.} down{في نفس اليوم الدورة اللي فاتت كنت صارف أكتر بـ {delta}.} other{صرفك زي نفس اليوم في الدورة اللي فاتت تقريباً.}}` | `{trend, select, up{At this point last cycle you had spent {delta} less.} down{At this point last cycle you had spent {delta} more.} other{Your spending is about the same as this point last cycle.}}` | E · Gold · `trend` (up = spending more than last cycle) |
| `insights_explainBurnRate_deepTip` | لو خفضت {target} من صرفك اليومي هتفضل تحت الخط لحد القبض. | Cut {target} from your daily spending and you'll stay under the line until payday. | S · Gold |

### Chart 4 — 50/30/20 balance
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainRule503020_basic` | `{state, select, wantsHigh{صرفك الدورة دي: {needsPct} أساسيات و{wantsPct} رفاهيات و{savingsPct} تحويش. الرفاهيات أعلى من القاعدة المعروفة.} savingsLow{صرفك الدورة دي: {needsPct} أساسيات و{wantsPct} رفاهيات و{savingsPct} تحويش. التحويش أقل من القاعدة المعروفة.} other{صرفك الدورة دي: {needsPct} أساسيات و{wantsPct} رفاهيات و{savingsPct} تحويش. ده قريب من القاعدة المعروفة.}}` | `{state, select, wantsHigh{This cycle: {needsPct} needs, {wantsPct} wants, {savingsPct} savings. Wants are above the usual rule.} savingsLow{This cycle: {needsPct} needs, {wantsPct} wants, {savingsPct} savings. Savings are below the usual rule.} other{This cycle: {needsPct} needs, {wantsPct} wants, {savingsPct} savings. That's close to the usual rule.}}` | E · `state:select(wantsHigh/savingsLow/other)`. The rule is fifty, thirty, twenty; the chart title carries it |
| `insights_explainRule503020_tip` | `{state, select, wantsHigh{نزّل الرفاهيات {target} الدورة الجاية وحوّلهم للتحويش.} savingsLow{حاول تزود التحويش {target} الدورة الجاية.} other{حافظ على التحويش ده، وزوده {target} لو قدرت.}}` | `{state, select, wantsHigh{Trim wants by {target} next cycle and move it to savings.} savingsLow{Try to add {target} to your savings next cycle.} other{Keep this up, and add {target} more if you can.}}` | S |
| `insights_explainRule503020_deep` | `{trend, select, up{التحويش زاد عن الدورة اللي فاتت لـ {savingsPct}.} down{التحويش نزل عن الدورة اللي فاتت لـ {savingsPct}.} other{التحويش ثابت تقريباً عن الدورة اللي فاتت.}}` | `{trend, select, up{Savings rose from last cycle to {savingsPct}.} down{Savings fell from last cycle to {savingsPct}.} other{Savings are about the same as last cycle.}}` | E · Gold |
| `insights_explainRule503020_deepTip` | لو التحويش وصل لـ {percent}، هتحوّش {yearly} في السنة. | If savings reach {percent}, you'll save {yearly} a year. | S · Gold · percent = the next 5-point step |

### Chart 5 — When you spend
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainWeekPattern_basic` | يوم {peakDay} و{peakDay2} واخدين {percent} من صرفك الأسبوعي، وأكتر وقت إيدك بتفرط فيه حوالين {time}. | {peakDay} and {peakDay2} take {percent} of your weekly spending, and your busiest hour is around {time}. | E |
| `insights_explainWeekPattern_tip` | حط سقف {target} ليوم {peakDay} الجاي. | Set a {target} limit for next {peakDay}. | S |
| `insights_explainWeekPattern_deep` | `{trend, select, up{متوسط صرفك يوم {peakDay} {amount}، وده أعلى من الدورة اللي فاتت.} down{متوسط صرفك يوم {peakDay} {amount}، وده أقل من الدورة اللي فاتت.} other{متوسط صرفك يوم {peakDay} {amount}، زي الدورة اللي فاتت تقريباً.}}` | `{trend, select, up{Your average on {peakDay} is {amount}, higher than last cycle.} down{Your average on {peakDay} is {amount}, lower than last cycle.} other{Your average on {peakDay} is {amount}, about the same as last cycle.}}` | E · Gold |
| `insights_explainWeekPattern_deepTip` | لو قللت خروجة {peakDay} بـ {target} كل أسبوع، هتوفر {yearly} في السنة. | Spend {target} less each {peakDay} and you'll save {yearly} a year. | S · Gold |

### Chart 6 — Top merchants
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainMerchants_basic` | {merchant} في المركز الأول بـ {amount} ({visits})، وبعده {merchant2} بـ {amount2}. | {merchant} is first with {amount} ({visits}), then {merchant2} with {amount2}. | E · visits = `common_unit_visits` |
| `insights_explainMerchants_tip` | جمّع مشترياتك من {merchant} في زيارة واحدة كل أسبوع. | Group your {merchant} shopping into one visit a week. | S |
| `insights_explainMerchants_deep` | `أول تلات تجار واخدين {percent} من صرفك. {trend, select, up{و{merchant} زاد عن الدورة اللي فاتت بـ {delta}.} down{و{merchant} قل عن الدورة اللي فاتت بـ {delta}.} other{و{merchant} زي الدورة اللي فاتت تقريباً.}}` | `Your top three merchants take {percent} of your spending. {trend, select, up{{merchant} is up {delta} on last cycle.} down{{merchant} is down {delta} on last cycle.} other{{merchant} is about the same as last cycle.}}` | E · Gold |
| `insights_explainMerchants_deepTip` | لو قللت {merchant} بالربع هتوفر {target} في الدورة، يعني {yearly} في السنة. | Cut {merchant} by a quarter and you'll save {target} a cycle, {yearly} a year. | S · Gold |

### Chart 7 — This cycle vs your 3-cycle average
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainVsAverage_basic` | `{state, select, both{{category} زاد {percent} عن متوسط آخر تلات دورات، لكن {category2} نزل {percent2}. برافو على ده.} rise{{category} زاد {percent} عن متوسط آخر تلات دورات.} drop{{category2} نزل {percent2} عن متوسط آخر تلات دورات. برافو عليك.} other{صرفك الدورة دي قريب من متوسط آخر تلات دورات.}}` | `{state, select, both{{category} is up {percent} on your 3-cycle average, but {category2} is down {percent2}. Nice work on that.} rise{{category} is up {percent} on your 3-cycle average.} drop{{category2} is down {percent2} on your 3-cycle average. Nice work.} other{This cycle is close to your 3-cycle average.}}` | E · `state:select(both/rise/drop/other)`. Needs three earlier cycles (`insights_chartDetail_needsData`) |
| `insights_explainVsAverage_tip` | `{state, select, both{لو رجّعت {category} لمتوسطك هتوفر {target}.} rise{لو رجّعت {category} لمتوسطك هتوفر {target}.} drop{كمّل على نفس النظام في {category2}.} other{كمّل على نفس الإيقاع.}}` | `{state, select, both{Bring {category} back to your average and you'll save {target}.} rise{Bring {category} back to your average and you'll save {target}.} drop{Keep doing what you're doing with {category2}.} other{Keep this pace.}}` | S |
| `insights_explainVsAverage_deep` | `{trend, select, up{في الإجمالي إنت فوق متوسطك بـ {delta}.} down{في الإجمالي إنت تحت متوسطك بـ {delta}.} other{في الإجمالي إنت على متوسطك تقريباً.}}` | `{trend, select, up{Overall you're {delta} above your average.} down{Overall you're {delta} below your average.} other{Overall you're right on your average.}}` | E · Gold |
| `insights_explainVsAverage_deepTip` | حط حد لـ {category} على قد متوسطك، يعني {target} في الدورة. | Set {category}'s limit at your average, that's {target} a cycle. | S · Gold |

### Chart 8 — Installments, next 6 months
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainInstallments_basic` | الشهر ده عليك {sum} أقساط والتزامات. {item} هيخلص في {month}. | You owe {sum} in installments and commitments this month. {item} ends in {month}. | E · item = the next installment to finish |
| `insights_explainInstallments_tip` | متدخلش في قسط جديد قبل ما {item} يخلص. | Hold off on a new installment until {item} is done. | S |
| `insights_explainInstallments_deep` | في الستة شهور الجايين هتدفع {amount} كلهم، بمتوسط {average} في الشهر. | Over the next six months you'll pay {amount} in total, averaging {average} a month. | E · Gold |
| `insights_explainInstallments_deepTip` | لما {item} يخلص هيفضل لك {monthly} كل شهر. | When {item} ends, {monthly} a month frees up. | S · Gold |

### Chart 9 — Subscriptions over a year
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainSubscriptions_basic` | الاشتراكات {monthly} في الشهر، يعني {yearly} في السنة. الصغير بيبان فكة، بس لما بيتجمع بيفرق. | Subscriptions cost {monthly} a month, {yearly} a year. Small ones look like loose change until they add up. | E |
| `insights_explainSubscriptions_tip` | راجع {item}، ولو مش بتستخدمه إلغاؤه بيوفر {target} في السنة. | Check {item}. If you don't use it, cancelling saves {target} a year. | S |
| `insights_explainSubscriptions_deep` | `{trend, select, up{الاشتراكات زادت {delta} في الشهر عن تلات شهور فاتت.} down{الاشتراكات قلت {delta} في الشهر عن تلات شهور فاتت.} other{الاشتراكات ثابتة عن تلات شهور فاتت.}}` | `{trend, select, up{Subscriptions are up {delta} a month on three months ago.} down{Subscriptions are down {delta} a month on three months ago.} other{Subscriptions are unchanged from three months ago.}}` | E · Gold |
| `insights_explainSubscriptions_deepTip` | لو ألغيت أغلى اتنين مش بتستخدمهم هتوفر {target} في السنة. | Cancel the two priciest ones you don't use and you'll save {target} a year. | S · Gold |

### Chart 10 — Cards & wallets
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainCards_basic` | `{state, select, credit{{percent} من صرفك طلع من {card}، وبعده {card2} بـ {percent2}. استخدامك من ليميت الكريدت {utilisation}.} other{{percent} من صرفك طلع من {card}، وبعده {card2} بـ {percent2}.}}` | `{state, select, credit{{percent} of your spending came from {card}, then {card2} at {percent2}. You've used {utilisation} of your credit limit.} other{{percent} of your spending came from {card}, then {card2} at {percent2}.}}` | E · `state:select(credit/other)`: credit when the top card is a credit card with a limit |
| `insights_explainCards_tip` | `{state, select, credit{خلّي استخدام الكريدت تحت النص وسدّده قبل ميعاده.} other{ركّز مصاريفك اليومية على كارت واحد علشان تتابعها أسهل.}}` | `{state, select, credit{Keep credit use under half the limit and pay it before the due date.} other{Keep daily spending on one card so it's easier to follow.}}` | S |
| `insights_explainCards_deep` | `{trend, select, up{نصيب {card} من صرفك زاد عن الدورة اللي فاتت.} down{نصيب {card} من صرفك قل عن الدورة اللي فاتت.} other{نصيب {card} من صرفك ثابت عن الدورة اللي فاتت.}}` | `{trend, select, up{{card}'s share of your spending rose since last cycle.} down{{card}'s share of your spending fell since last cycle.} other{{card}'s share of your spending is unchanged since last cycle.}}` | E · Gold · the apostrophe after a brace needs the early gen-l10n check (§0.10) |
| `insights_explainCards_deepTip` | صرفت {amount} من {card} الدورة دي. حط له سقف {target} للدورة الجاية. | You spent {amount} on {card} this cycle. Set a {target} limit for the next one. | S · Gold |

### Chart 11 — Net worth growth
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainNetWorth_basic` | `{trend, select, up{اللي حيلتك زاد من {startAmount} في {month} لـ {endAmount} في {month2}.} down{اللي حيلتك نزل من {startAmount} في {month} لـ {endAmount} في {month2}.} other{اللي حيلتك ثابت تقريباً حوالين {endAmount}.}}` | `{trend, select, up{Your net worth grew from {startAmount} in {month} to {endAmount} in {month2}.} down{Your net worth dropped from {startAmount} in {month} to {endAmount} in {month2}.} other{Your net worth is steady at about {endAmount}.}}` | E · one currency or unit at a time, no cross-currency sum |
| `insights_explainNetWorth_tip` | {assetType} هو أكبر جزء من اللي حيلتك بـ {percent}. خد بالك لو كله في حاجة واحدة. | {assetType} is your biggest slice at {percent}. Keep an eye on it if it's all in one place. | S · assetType = `common_assetType_*` |
| `insights_explainNetWorth_deep` | `{trend, select, up{نموك الإجمالي {percent}، وأكتر حاجة زوّدته {assetType2}.} down{اللي حيلتك نزل {percent}، وأكتر حاجة أثرت فيه {assetType2}.} other{مفيش تغيير كبير في الفترة دي.}}` | `{trend, select, up{You're up {percent} overall, mostly thanks to {assetType2}.} down{You're down {percent} overall, mostly because of {assetType2}.} other{No big change over this period.}}` | E · Gold |
| `insights_explainNetWorth_deepTip` | بنفس المعدل ده ممكن توصل لـ {projected} بعد سنة. ده تقدير بس. | At this rate you could reach {projected} in a year. That's an estimate only. | S · Gold |

### Chart 12 — Your personal inflation
| Key | AR | EN | Notes |
|---|---|---|---|
| `insights_explainInflation_basic` | `{trend, select, up{متوسط فاتورة السوبرماركت كان {startAmount} في {month} ودلوقتي {endAmount}، يعني زاد {percent}.} down{متوسط فاتورة السوبرماركت كان {startAmount} في {month} ودلوقتي {endAmount}، يعني نزل {percent}.} other{متوسط فاتورة السوبرماركت ثابت حوالين {endAmount}.}}` | `{trend, select, up{Your average supermarket basket was {startAmount} in {month} and is {endAmount} now, up {percent}.} down{Your average supermarket basket was {startAmount} in {month} and is {endAmount} now, down {percent}.} other{Your average supermarket basket is steady at about {endAmount}.}}` | E |
| `insights_explainInflation_tip` | جرّب بدائل أرخص في {category}، هي أكتر حاجة سعرها زاد عليك. | Try cheaper alternatives for {category}, where your prices rose the most. | S |
| `insights_explainInflation_deep` | متوسط أوردر الدليفري بقى {average} بدل {previous}. | Your average delivery order is now {average}, up from {previous}. | E · Gold · only when the delivery average rose; otherwise the sentence is dropped |
| `insights_explainInflation_deepTip` | لو نزّلت متوسط الفاتورة {target}، هتوفر {yearly} في السنة بنفس عدد الزيارات. | Bring your average basket down {target} and you'll save {yearly} a year at the same number of visits. | S · Gold |

---

## 2.5 S-22 Budget — `budget_overview_*`
States: loading · populated · empty (no budgets, spending still shown) · no payday set (calendar month, A-43) · past cycle (read-only) · error. The Home mascot messages for a category near its limit are reused (`home_mascot_shockedCategory`, `…Alt`, `…shockedDining`, `…proudOnTrack`); S-22 adds none. A bar's state is always spelled out in words next to the colour (C-12). Budget-threshold notifications belong to Part 3.

| Key | AR | EN | Notes |
|---|---|---|---|
| `budget_overview_cycle` | {start} لحد {end} | {start} to {end} | L · cycle header, dates per `common_date_*` |
| `budget_overview_daysLeft` | `{count, plural, =1{آخر يوم} =2{فاضل يومين} few{فاضل {n} أيام} many{فاضل {n} يوم} other{فاضل {n} يوم}}` | `{count, plural, =1{Last day} other{{n} days left}}` | C · count:int, n · includes today, so 0 can't occur |
| `budget_overview_calendarMonth` | الشهر الميلادي | Calendar month | L · shown when no payday is set (A-43) |
| `budget_overview_setPayday` | حدد يوم القبض | Set payday | L · text link, opens S-72 |
| `budget_overview_overall` | {spent} من {budget} | {spent} of {budget} | L · overall bar, with `common_progress_percent` |
| `budget_overview_safePerDay` | مسموحلك {perDay} في اليوم | You can spend {perDay} a day | L · BR-BUD-03. At 0 use `home_hero_budgetUsedUp` |
| `budget_overview_currencyNote` | الميزانية دي بـ{currency} بس | This budget counts {currency} only | S · FR-BUD-02, shown when the currency switcher is not EGP |
| `budget_overview_rowAmounts` | {spent} / {limit} | {spent} / {limit} | L · C-12 |
| `budget_overview_statusNear` | قربت تخلص | Nearly used | C · 80–99% (default threshold) |
| `budget_overview_statusFull` | خلصت | Used up | C · exactly 100% |
| `budget_overview_statusOver` | عدّت بـ {gap} | Over by {gap} | C · above 100%, danger colour plus these words |
| `budget_overview_rowA11y` | {category}: صرفت {spent} من {limit}، {percent} | {category}: spent {spent} of {limit}, {percent} | A |
| `budget_overview_notBudgeted` | من غير ميزانية | Not budgeted | L |
| `budget_overview_notBudgetedSub` | صرف في تصنيفات ملهاش حد | Spending in categories with no limit | S · opens S-11 filtered |
| `budget_overview_edit` | عدّل الميزانية | Edit budgets | B · opens S-23 |
| `budget_overview_prevA11y` | الدورة اللي قبلها | Previous cycle | A · arrow mirrors in RTL |
| `budget_overview_nextA11y` | الدورة اللي بعدها | Next cycle | A · arrow mirrors in RTL |
| `budget_overview_emptyTitle` | حط حدود وشوف مسموحلك تصرف كام | Set limits and see what's safe to spend | T · C-28, Rive `tourGuide` |
| `budget_overview_emptyBody` | صرف الدورة دي ظاهر تحت لحد ما تحط ميزانية. | Your spending shows below until you set a budget. | S |
| `budget_overview_emptyAction` | حط ميزانية | Set budgets | B · opens S-23 |
| `budget_overview_loadingA11y` | بحمّل الميزانية | Loading budget | A |

## 2.6 S-23 Edit budgets — `budget_edit_*`, `budget_annual_*`
States: clean · unsaved (discard dialog uses `common_discard_*`) · validation errors · save error (`common_error_saveFailed`). A budget is set in one currency (D-28).

| Key | AR | EN | Notes |
|---|---|---|---|
| `budget_edit_title` | الميزانية | Budgets | T |
| `budget_edit_currency` | عملة الميزانية | Budget currency | L · picker, required (`common_validation_currencyRequired`) |
| `budget_edit_overall` | الإجمالي | Overall | L · section |
| `budget_edit_overallSum` | مجموع التصنيفات | Sum of categories | L · radio |
| `budget_edit_overallSet` | إجمالي أحدده أنا | A total I set | L · radio, shows an amount field |
| `budget_edit_categories` | حد كل تصنيف | Limit per category | L · section |
| `budget_edit_limitHint` | سيبه فاضي لو مش عايز حد | Leave empty for no limit | S · under the fields, zero or blank = no budget |
| `budget_edit_alerts` | نبّهني لما أوصل لـ | Alert me at | L · FR-BUD-03 |
| `budget_edit_alertFirst` | التنبيه الأول | First alert | L · percentage field |
| `budget_edit_alertSecond` | التنبيه التاني | Second alert | L · percentage field |
| `budget_edit_rollover` | رحّل اللي فاضل للدورة الجاية | Roll over what's left | L · switch, FR-BUD-05 |
| `budget_edit_rolloverHint` | اللي ما اتصرفش بيتضاف لميزانية الدورة الجاية. | Unspent budget is added to the next cycle. | S |
| `budget_edit_annual` | ميزانيات سنوية | Annual budgets | L · opens the annual list, FR-BUD-06 |
| `budget_edit_annualHint` | للحاجات اللي بتتدفع مرة في السنة، زي المصاريف المدرسية | For once-a-year costs like school fees | S |
| `budget_edit_payday` | يوم القبض | Payday | L · opens the S-72 stepper |
| `budget_edit_errorLimit` | الحد مينفعش يكون بالسالب | A limit can't be negative | S |
| `budget_edit_errorThreshold` | النسبة لازم تبقى بين {min} و{max} | The percentage must be between {min} and {max} | S · min/max = 1 and 150 |
| `budget_edit_errorOrder` | التنبيه الأول لازم يبقى أقل من التاني | The first alert must be lower than the second | S |
| `budget_edit_saved` | الميزانية اتحفظت ✓ | Budget saved ✓ | N · success |
| `budget_annual_title` | ميزانيات سنوية | Annual budgets | T |
| `budget_annual_empty` | لسه مفيش ميزانيات سنوية | No annual budgets yet | S · C-28 with `budget_annual_add` |
| `budget_annual_add` | ضيف ميزانية سنوية | Add an annual budget | B |

## 2.7 S-24 Bills & installments — `recurring_bills_*`
States: loading · populated · empty · detected subscription (FR-SUB-01) · overdue · paid · error. The Home detective banner for a new subscription is reused. The reminder notification is Part 3.

| Key | AR | EN | Notes |
|---|---|---|---|
| `recurring_bills_summary` | الشهر ده: {due} مستحقة · {subs} اشتراكات في الشهر | This month: {due} due · {subs} in subscriptions a month | S · due and subs are Money, one line per currency |
| `recurring_bills_detected` | لقيت اشتراك: {merchant} بـ {amount} في الشهر | Found a subscription: {merchant}, {amount} a month | M · Rive `detective` · BR-SUB-01 |
| `recurring_bills_track` | تابعه | Track it | B |
| `recurring_bills_notSub` | مش اشتراك | Not a subscription | B |
| `recurring_bills_upcoming` | اللي جاي | Coming up | L · C-36 timeline |
| `recurring_bills_installmentRow` | {name} · القسط {index} من {total} | {name} · payment {index} of {total} | L |
| `recurring_bills_lastOne` | آخر قسط | Last payment | C |
| `recurring_bills_markPaid` | اتدفع | Mark paid | B · glossary «اتدفع» |
| `recurring_bills_paid` | اتدفع ✓ | Paid ✓ | C |
| `recurring_bills_autoPaid` | اتسجل لوحده من الحركة | Marked from a captured payment | L · FR-SUB-05 |
| `recurring_bills_dueToday` | النهارده | Today | C |
| `recurring_bills_dueIn` | `{count, plural, =1{بكرة} =2{بعد يومين} few{بعد {n} أيام} many{بعد {n} يوم} other{بعد {n} يوم}}` | `{count, plural, =1{Tomorrow} other{In {n} days}}` | C · count:int, n · 0 is `recurring_bills_dueToday` |
| `recurring_bills_overdue` | `{count, plural, =1{متأخر يوم} =2{متأخر يومين} few{متأخر {n} أيام} many{متأخر {n} يوم} other{متأخر {n} يوم}}` | `{count, plural, =1{1 day overdue} other{{n} days overdue}}` | C · count:int, n · danger colour plus these words, no emoji |
| `recurring_bills_kindSubscription` | اشتراك | Subscription | C |
| `recurring_bills_kindInstallment` | قسط | Installment | C |
| `recurring_bills_kindCard` | سداد كارت | Card payment | C |
| `recurring_bills_kindGameya` | جمعية | Gameya | C |
| `recurring_bills_gameyaManual` | الجمعية بتتسجل بإيدك | Gameya payments are logged by hand | S · A-17 |
| `recurring_bills_subsTitle` | الاشتراكات | Subscriptions | L |
| `recurring_bills_subsYear` | في السنة كلها | Over a full year | C · the ×12 column header (FR-SUB-02) |
| `recurring_bills_subRow` | {monthly} في الشهر · {yearly} في السنة | {monthly}/mo · {yearly}/yr | S |
| `recurring_bills_subsTotal` | المجموع {monthly} في الشهر، يعني {yearly} في السنة | Total {monthly} a month, {yearly} a year | S |
| `recurring_bills_add` | ضيف فاتورة أو قسط | Add a bill or installment | L · text button, opens S-25 |
| `recurring_bills_emptyTitle` | لسه مفيش فواتير ولا أقساط | No bills or installments yet | T · C-28, Rive `tourGuide` |
| `recurring_bills_emptyBody` | هلاقي الاشتراكات لوحدي من حركاتك، وتقدر تضيف أي قسط بإيدك. | I'll spot subscriptions from your transactions, and you can add any installment yourself. | S |
| `recurring_bills_paidSnack` | اتسجل إن {name} اتدفع ✓ | Marked {name} as paid ✓ | N + `common_action_undo` |
| `recurring_bills_rowA11y` | {name}، {amount}، {status} | {name}, {amount}, {status} | A · status = `recurring_bills_dueToday` / `dueIn` / `overdue` / `paid` |

## 2.8 S-25 Add / edit bill or installment — `recurring_billEdit_*`
States: add · edit (with Delete) · unsaved (`common_discard_*`) · validation errors · save error.

| Key | AR | EN | Notes |
|---|---|---|---|
| `recurring_billEdit_titleAdd` | ضيف فاتورة أو قسط | Add a bill or installment | T |
| `recurring_billEdit_titleEdit` | عدّل الفاتورة | Edit bill | T |
| `recurring_billEdit_type` | النوع | Type | L · segments use `recurring_bills_kind*` |
| `recurring_billEdit_name` | الاسم | Name | L |
| `recurring_billEdit_namePlaceholder` | مثلاً: قسط التلاجة | e.g. Fridge installment | L · hint text |
| `recurring_billEdit_amount` | المبلغ | Amount | L · C-22, currency picker beside it |
| `recurring_billEdit_repeats` | بيتكرر | Repeats | L · options `common_cadence_*` |
| `recurring_billEdit_nextDue` | الدفعة الجاية | Next payment | L · may be in the future |
| `recurring_billEdit_paid` | اتدفع | Paid | L · installments and gameya only |
| `recurring_billEdit_paidOf` | من | of | C · between the two number fields |
| `recurring_billEdit_remind` | `{count, plural, =0{فكّرني يوم الميعاد} =1{فكّرني قبلها بيوم} =2{فكّرني قبلها بيومين} few{فكّرني قبلها بـ {n} أيام} many{فكّرني قبلها بـ {n} يوم} other{فكّرني قبلها بـ {n} يوم}}` | `{count, plural, =0{Remind me on the day} =1{Remind me 1 day before} other{Remind me {n} days before}}` | L · count:int, n · stepper 0–30, default 3 (BR-SUB-03) |
| `recurring_billEdit_account` | الحساب (اختياري) | Account (optional) | L |
| `recurring_billEdit_deleteTitle` | تمسح {name}؟ | Delete {name}? | T · destructive, no emoji |
| `recurring_billEdit_deleteBody` | هتتشال من الفواتير. الحركات اللي اتسجلت قبل كده مش هتتمسح. | It will be removed from Bills. Transactions already recorded stay. | S · confirm button `common_action_delete`, cancel `common_action_cancel`. Assumption, see Q-22 |
| `recurring_billEdit_errorPaid` | اللي اتدفع مينفعش يزيد عن الإجمالي | Paid can't be more than the total | S |
| `recurring_billEdit_errorTotal` | عدد الدفعات لازم يبقى من واحد لـ {max} | The number of payments must be from 1 to {max} | S · max = 120 |
| `recurring_billEdit_errorRemind` | التذكير من صفر لـ {max} يوم | Reminder: 0 to {max} days | S · max = 30 |
| `recurring_billEdit_errorDue` | اختار ميعاد الدفعة الجاية | Pick the next payment date | S |
| `recurring_billEdit_saved` | الفاتورة اتحفظت ✓ | Bill saved ✓ | N · success |

---

## 2.9 S-30 Quick add — `home_quickAdd_*`
States: Free (voice counter and Gold badge on Asset) · Gold (no counter). A static sheet, so no loading or error.

| Key | AR | EN | Notes |
|---|---|---|---|
| `home_quickAdd_title` | عايز تسجل إيه؟ | What do you want to add? | T · sheet |
| `home_quickAdd_say` | قول | Say | L · opens S-31 |
| `home_quickAdd_type` | اكتب | Type | L · opens S-13 |
| `home_quickAdd_scan` | صوّر | Scan | L · opens S-32 |
| `home_quickAdd_asset` | أصل | Asset | L · with `common_gold_badge`; Free opens S-68 |
| `home_quickAdd_sayA11y` | قول لزغلول | Tell Zaghlol | A |
| `home_quickAdd_typeA11y` | اكتب حركة | Type a transaction | A |
| `home_quickAdd_scanA11y` | اقرا سكرين شوت | Scan a screenshot | A |
| `home_quickAdd_assetA11y` | ضيف أصل | Add an asset | A |
| `home_quickAdd_voiceLeft` | فاضل {remaining} من {max} تسجيل صوتي الشهر ده | {remaining} of {max} voice logs left this month | S · Free only (FR-VOI-04) |

## 2.10 S-31 Voice logger — `voice_logger_*`
States: listening · understanding · parsed · empty (nothing recognised) · Arabic recognition unavailable (EC-32) · online-recognition consent (D-42, OQ-06) · microphone denied · Free limit reached. Rive `listening` while recording. Nothing is saved before the user confirms (FR-VOI-03). Money confirmations carry no emoji beyond the success tick.

| Key | AR | EN | Notes |
|---|---|---|---|
| `voice_logger_title` | قول اللي دفعته | Tell me what you paid | T |
| `voice_logger_exampleLabel` | مثلاً | For example | C |
| `voice_logger_example` | دفعت ميت وخمسين جنيه خضار وخمسة وأربعين قهوة وتلاتين تاكسي | Paid 150 pounds for vegetables, 45 for coffee and 30 for a taxi | S · FR-VOI-02/05. Egyptian number words, so the Arabic has no digits |
| `voice_logger_listening` | بسمعك… | Listening… | L |
| `voice_logger_done` | خلصت | Done | B · stop button, the record icon doesn't mirror |
| `voice_logger_stopA11y` | وقّف التسجيل | Stop recording | A |
| `voice_logger_transcriptA11y` | اللي سمعته لحد دلوقتي: {text} | Heard so far: {text} | A |
| `voice_logger_understanding` | بفهم اللي قلته… | Understanding… | L · up to 2 s (NFR-PERF-05), Rive `thinking` |
| `voice_logger_parsedTitle` | `{count, plural, =1{فهمت حاجة واحدة} =2{فهمت حاجتين} few{فهمت {n} حاجات} many{فهمت {n} حاجة} other{فهمت {n} حاجة}}` | `{count, plural, =1{I understood 1 item} other{I understood {n} items}}` | T · count:int, n |
| `voice_logger_account` | الحساب | Account | L · applies to all items |
| `voice_logger_when` | إمتى | When | L · applies to all items |
| `voice_logger_applyAll` | بينطبق على الكل | Applies to all | C |
| `voice_logger_amountMissing` | المبلغ كام؟ | Amount? | C · error state on an item (EC-30). Save is disabled until it is fixed or removed |
| `voice_logger_editA11y` | عدّل البند ده | Edit this item | A |
| `voice_logger_removeA11y` | شيل البند ده | Remove this item | A |
| `voice_logger_save` | `{count, plural, =1{احفظ} =2{احفظ الاتنين} few{احفظ {n}} many{احفظ {n}} other{احفظ {n}}}` | `{count, plural, =1{Save} other{Save {n}}}` | B · count:int, n |
| `voice_logger_saved` | `{count, plural, =1{اتسجلت حركة واحدة ✓} =2{اتسجلت حركتين ✓} few{اتسجلوا {n} حركات ✓} many{اتسجلوا {n} حركة ✓} other{اتسجلوا {n} حركة ✓}}` | `{count, plural, =1{1 expense saved ✓} other{{n} expenses saved ✓}}` | N + `common_action_undo` · count:int, n · one voice log counts once (A-14) |
| `voice_logger_emptyTitle` | مسمعتش مبلغ | I didn't catch an amount | T · actions `common_action_tryAgain` and `common_action_typeInstead` |
| `voice_logger_emptyBody` | جرّب تقول: «ميت وخمسين خضار» | Try saying: "150 vegetables" | S |
| `voice_logger_unavailable` | الصوت بالعربي مش شغال على الموبايل ده | Arabic voice isn't available on this phone | T · EC-32, Rive `oops`. Action `common_action_typeInstead` |
| `voice_logger_unavailableBody` | تقدر تكتب الحركة بإيدك في ثواني. | You can type the transaction in a few seconds. | S |
| `voice_logger_onlineTitle` | نستخدم التعرف على الصوت أونلاين؟ | Use online speech recognition? | T · D-42, only if on-device Arabic isn't available |
| `voice_logger_onlineBody` | `موبايلك مفيهوش تعرّف على العربي من غير نت. لو وافقت، خدمة الكلام بتاعة {platform, select, ios{آبل} other{جوجل}} هتحوّل صوتك لنص أونلاين. زغلول مش بيحتفظ بالتسجيل.` | `{platform, select, ios{This phone can't recognise Arabic offline. If you agree, Apple's speech service converts your voice to text online. Zaghlol doesn't keep the recording.} other{This phone can't recognise Arabic offline. If you agree, Google's speech service converts your voice to text online. Zaghlol doesn't keep the recording.}}` | E · `platform:select(ios/other)` · explicit consent, no jokes. Privacy review of the wording: Q-21 |
| `voice_logger_onlineAllow` | وافق | Allow | B |
| `voice_logger_onlineDeny` | لأ، هكتب | No, I'll type | B |
| `voice_logger_micTitle` | محتاج الميكروفون | I need the microphone | T · C-25 |
| `voice_logger_micBody` | علشان أسمع اللي بتقوله. مش بحتفظ بتسجيل صوتك. | So I can hear you. I don't keep a recording of your voice. | S · plus `common_action_openSettings` and `common_action_typeInstead` |
| `voice_logger_limitTitle` | خلّصت تسجيلاتك الصوتية الشهر ده | You've used this month's voice logs | T · Free, 15 used (A-15) |
| `voice_logger_limitBody` | استخدمت {max} تسجيل صوتي الشهر ده، وبيرجعوا أول الشهر الجاي. جولد من غير حدود. | You've used all {max} voice logs this month. They reset next month. Gold has no limit. | S · plus `common_gold_unlock` and `common_action_typeInstead` |

## 2.11 S-32 Scan screenshot or receipt — `capture_scan_*`
States: choose image · reading · found · duplicate · empty (nothing found) · unsupported file · photo permission denied. The image is read on the phone. When the screen is opened from the share sheet or Back-Tap, `capture_scan_fromShare` replaces the picker prompt.

| Key | AR | EN | Notes |
|---|---|---|---|
| `capture_scan_title` | قراءة سكرين شوت | Scan a screenshot | T |
| `capture_scan_choose` | اختار صورة | Choose an image | B |
| `capture_scan_chooseAnother` | اختار صورة تانية | Choose another image | B |
| `capture_scan_reading` | بقرا الصورة… | Reading the image… | L · Rive `scanning` |
| `capture_scan_onDevice` | الصورة بتتقري على موبايلك. | The image is read on this phone. | S |
| `capture_scan_found` | ده اللي لقيته | Here's what I found | L |
| `capture_scan_amount` | المبلغ | Amount | L |
| `capture_scan_party` | لمين / من مين | To / From | L · counterparty, often an IPA handle (LTR) |
| `capture_scan_reference` | رقم العملية | Reference | L |
| `capture_scan_date` | إمتى | When | L · validation `common_validation_dateFuture` |
| `capture_scan_category` | التصنيف | Category | L · required |
| `capture_scan_account` | الحساب | Account | L · required (`common_validation_accountRequired`) |
| `capture_scan_editA11y` | عدّل | Edit | A · pencil next to each found field |
| `capture_scan_fromShare` | ده اللي فهمته من الصورة اللي بعتها. راجعه واحفظ. | Here's what I read from the image you sent. Check it and save. | S |
| `capture_scan_emptyTitle` | مش لاقي دفعة في الصورة دي | I couldn't find a payment in this image | T · Rive `oops`; actions `capture_scan_chooseAnother` and `common_action_typeInstead` |
| `capture_scan_emptyBody` | جرّب صورة أوضح، أو اكتب الحركة بإيدك. | Try a clearer image, or type the transaction. | S |
| `capture_scan_duplicateTitle` | اتسجلت قبل كده من رسالة البنك | Already captured from a bank message | T · same amount and reference or time |
| `capture_scan_duplicateView` | شوفها | View | B |
| `capture_scan_duplicateSave` | احفظها برضه | Save anyway | B |
| `capture_scan_unsupported` | الملف ده مش صورة أقدر أقراها | I can't read this kind of file | S |
| `capture_scan_photoTitle` | محتاج أشوف صورك | I need access to your photos | T |
| `capture_scan_photoBody` | علشان تختار السكرين شوت. ببص على الصورة اللي تختارها بس. | So you can pick the screenshot. I only look at the image you choose. | S · plus `common_action_openSettings` |

---

## 2.12 S-40 additions — assets, net-worth unit lines, hidden accounts: `wealth_overview_*`, `accounts_hidden_*`
These close F-18 and R2-4. Part 1's S-40 keys (`accounts_overview_*`) stay as they are. States: Gold populated · Gold empty · stale prices (`common_badge_stale`) · no rate for a currency (EC-35) · Free locked (`accounts_overview_assetsLocked`) · hidden list populated and empty. The net-worth hero shows **one line per currency or unit and never a sum** (FR-WLT-01, D-29). Currency lines are plain `{amount}` values with no copy of their own.

| Key | AR | EN | Notes |
|---|---|---|---|
| `wealth_overview_unitGold` | دهب عيار {karat}: {grams} | Gold {karat}K: {grams} | L · one hero line per karat. grams = `common_unit_grams` |
| `wealth_overview_unitCoins` | `{count, plural, =1{جنيه دهب واحد} =2{جنيهين دهب} few{{n} جنيهات دهب} many{{n} جنيه دهب} other{{n} جنيه دهب}}` | `{count, plural, =1{1 gold coin} other{{n} gold coins}}` | L · count:int, n · hero line, shown only when coins are held |
| `wealth_overview_unitsA11y` | اللي حيلتك كله: {list} | Net worth: {list} | A · list = the hero lines joined with the locale list format |
| `wealth_overview_goldTitle` | دهب عيار {karat} | Gold {karat}K | L · asset row |
| `wealth_overview_goldSub` | {grams} · ≈ {value} | {grams} · ≈ {value} | L · value = grams × price. Stale price adds `common_badge_stale` |
| `wealth_overview_certTitle` | شهادة {bank} | {bank} certificate | L |
| `wealth_overview_certSub` | عائد {percent} · {principal} | {percent} rate · {principal} | L |
| `wealth_overview_certPayout` | الصرف الجاي {date}: {payout} | Next payout {date}: {payout} | L · FR-WLT-04 |
| `wealth_overview_manualValue` | قيمة تقديرية | Estimated value | C · stocks, property and car rows |
| `wealth_overview_noRate` | مفيش سعر لـ {currency} لسه، فهو ظاهر بعملته بس | No rate for {currency} yet, so it's shown in its own currency only | S · EC-35 |
| `wealth_overview_assetsEmpty` | لسه ماضفتش أصول. ضيف دهبك أو شهاداتك. | No assets yet. Add your gold or certificates. | S · Gold, plus `accounts_overview_addAsset` |
| `wealth_overview_assetRowA11y` | {name}، {value} | {name}, {value} | A |
| `accounts_overview_hiddenCount` | `{count, plural, =1{حساب واحد} =2{حسابين} few{{n} حسابات} many{{n} حساب} other{{n} حساب}}` | `{count, plural, =1{1 account} other{{n} accounts}}` | C · count:int, n · trailing text on the `accounts_overview_hiddenEntry` row, which exists only while 1 or more accounts are hidden |
| `accounts_hidden_title` | الحسابات المخفية | Hidden accounts | T · the hidden list's title (same words as `accounts_overview_hiddenEntry`) |
| `accounts_hidden_intro` | الحسابات دي مش ظاهرة في القوايم، بس حركاتها لسه محسوبة في الأرقام والميزانية والشارتات. | These accounts are out of your lists, but their transactions still count in totals, budgets and charts. | S · D-69 |
| `accounts_hidden_unhide` | رجّعه | Unhide | B · on each row, no confirmation needed |
| `accounts_hidden_unhidden` | الحساب رجع للقايمة | The account is back in your list | N + `common_action_undo` |
| `accounts_hidden_empty` | مفيش حسابات مخفية | No hidden accounts | S · C-28, shown if the user unhides the last one while the list is open |
| `accounts_hidden_rowA11y` | {card}، مخفي. اضغط تفتح الحساب | {card}, hidden. Tap to open the account | A · opens S-43 |

## 2.13 S-44 Add / edit asset — `wealth_asset_*`
Gold feature; a Free tap opens S-68, so there is no locked copy here. Fields shown depend on the type chosen with `common_assetType_*`. States: add · edit · unsaved (`common_discard_*`) · validation errors · save error.

| Key | AR | EN | Notes |
|---|---|---|---|
| `wealth_asset_titleAdd` | ضيف أصل | Add an asset | T |
| `wealth_asset_titleEdit` | عدّل الأصل | Edit asset | T |
| `wealth_asset_type` | النوع | Type | L |
| `wealth_asset_optional` | اختياري | Optional | C |
| `wealth_asset_goldKarat` | العيار | Karat | L · options `common_karat_label` and `common_karat_coin` |
| `wealth_asset_goldGrams` | الوزن بالجرام | Weight in grams | L |
| `wealth_asset_goldGramsHint` | لحد تلات أرقام بعد العلامة | Up to three decimals | S |
| `wealth_asset_coinCount` | عدد الجنيهات | Number of coins | L · when the karat option is the coin |
| `wealth_asset_boughtOn` | اشتريته إمتى | Bought on | L · hawl start for Zakah |
| `wealth_asset_pricePaid` | دفعت فيه كام | Price paid | L · optional, with a currency picker |
| `wealth_asset_certBank` | البنك | Bank | L |
| `wealth_asset_certPrincipal` | المبلغ | Principal | L |
| `wealth_asset_certRate` | نسبة العائد | Rate | L · percent field |
| `wealth_asset_certPayout` | العائد بيتصرف | Payout | L · options `common_cadence_*` |
| `wealth_asset_certMaturity` | بتخلص إمتى | Matures on | L |
| `wealth_asset_cashCurrency` | العملة | Currency | L · any ISO currency |
| `wealth_asset_cashAmount` | المبلغ | Amount | L |
| `wealth_asset_name` | الاسم | Name | L · stocks, property, car |
| `wealth_asset_stocksCurrency` | عملة التداول | Trading currency | L |
| `wealth_asset_value` | القيمة الحالية | Current value | L · entered by hand |
| `wealth_asset_valueHint` | اكتبها بإيدك وحدّثها من وقت للتاني. | Enter it yourself and update it now and then. | S |
| `wealth_asset_deleteTitle` | تمسح الأصل ده؟ | Delete this asset? | T · destructive, no emoji |
| `wealth_asset_deleteBody` | هيتشال من اللي حيلتك كله ومن أي حساب مبني عليه. | It will be removed from your net worth and anything worked out from it. | S |
| `wealth_asset_saved` | الأصل اتحفظ ✓ | Asset saved ✓ | N · success |
| `wealth_asset_errorType` | اختار نوع الأصل | Choose an asset type | S |
| `wealth_asset_errorGrams` | الوزن لازم يبقى أكبر من صفر | Weight must be above zero | S |
| `wealth_asset_errorGramsDecimals` | لحد تلات أرقام بعد العلامة بس | Up to three decimals only | S |
| `wealth_asset_errorRate` | العائد من صفر لـ {max}٪ | The rate must be from 0 to {max}% | S · max = 100 |
| `wealth_asset_errorMaturity` | تاريخ الانتهاء لازم يبقى بعد تاريخ الشراء | Maturity must be after the purchase date | S |

## 2.14 S-45 Prices — `wealth_prices_*`
States: populated · stale (older than 24 h, `common_badge_stale`) · overridden rows · never fetched (EC-34) · fetch failed (last known price shown). Validation: a price must be above zero (`common_validation_amountRequired`).

| Key | AR | EN | Notes |
|---|---|---|---|
| `wealth_prices_title` | الأسعار | Prices | T |
| `wealth_prices_updated` | اتحدثت {when} | Updated {when} | L · when = date and time or `common_date_hoursAgo` |
| `wealth_prices_goldSection` | الدهب (سعر الجرام) | Gold (per gram) | L · rows use `common_karat_label` |
| `wealth_prices_currenciesSection` | العملات مقابل {currency} | Currencies to {currency} | L · only currencies the user holds, plus featured ones |
| `wealth_prices_goldRowA11y` | عيار {karat}: {price} للجرام | {karat}K: {price} per gram | A |
| `wealth_prices_currencyRowA11y` | {currency}: {rate} | {currency}: {rate} | A |
| `wealth_prices_override` | غيّر السعر | Change price | L · text button on each row |
| `wealth_prices_overrideTitle` | سعرك إنت | Your price | T · sheet |
| `wealth_prices_overrideField` | السعر بـ {currency} | Price in {currency} | L |
| `wealth_prices_overrideUse` | استخدم سعري | Use my price | B |
| `wealth_prices_overrideNote` | السعر اللي بتحطه بيتستخدم لحد ما ترجّع الأصلي. | Your price is used until you reset it. | S |
| `wealth_prices_yours` | سعرك | Your price | C · badge on overridden rows |
| `wealth_prices_reset` | رجّع الأصلي | Reset | B |
| `wealth_prices_neverTitle` | لسه ما نزّلتش الأسعار | Prices haven't been downloaded yet | T · Rive `sleep` |
| `wealth_prices_neverBody` | اتصل بالنت مرة، أو اكتب السعر بإيدك. | Connect once, or enter a price yourself. | S |
| `wealth_prices_enterManually` | اكتب السعر بإيدك | Enter manually | B |
| `wealth_prices_fetchFailed` | مقدرتش أحدّث الأسعار. شايف آخر سعر معروف. | Couldn't update prices. Showing the last known ones. | N · EC-34 |
| `wealth_prices_privacy` | تحديث الأسعار مبيبعتش أي حاجة عن فلوسك أو أصولك. | Updating prices doesn't send anything about your money or assets. | S · NFR-PRIV-03. It speaks about financial data only |

## 2.15 S-46 Zakah — `zakah_main_*` (Gold, hidden unless the `zakah` flag is on)
Calm, respectful tone: **no jokes, no emoji, no mascot line** (the `zakahAura` pose is silent). The wording is Egyptian colloquial, with the **disclaimer in simple standard Arabic** and an Egyptian one-line summary above it (`06-voice-and-tone.md` §1). All rules below are subject to scholar review before the flag is turned on (D-07, BR-ZAK-05). States: populated · nisab not reached · empty · stale prices · payment status per item.

| Key | AR | EN | Notes |
|---|---|---|---|
| `zakah_main_title` | الزكاة | Zakah | T |
| `zakah_main_disclaimerSummary` | ده تقدير تقريبي مش فتوى. اسأل أهل العلم قبل ما تخرج زكاتك. | This is an estimate, not a ruling. Ask a scholar before you pay Zakah. | S · always visible (FR-ZAK-05), above the disclaimer |
| `zakah_main_disclaimer` | هذا الحساب تقديري وليس فتوى. يُرجى مراجعة أهل العلم قبل إخراج الزكاة. | This calculation is an estimate and not a religious ruling. Please consult a qualified scholar before paying Zakah. | S · **simple standard Arabic** (disclaimer exception). Legal and scholar sign-off: Q-23 |
| `zakah_main_nisabReached` | النصاب اتحقق | Nisab reached | L |
| `zakah_main_nisabNotReached` | لسه مفيش نصاب | Nisab not reached | L |
| `zakah_main_nisabInfo` | النصاب {grams} من الدهب عيار {karat}، يعني حوالين {value} | The nisab is {grams} of {karat}K gold, about {value} | S · grams = `common_unit_grams` (BR-ZAK-01) |
| `zakah_main_nisabNotReachedBody` | حسابك تحت النصاب دلوقتي، فالتقدير مفيهوش مبلغ مستحق. هفضل أتابع معاك. | You're under the nisab now, so the estimate shows nothing due. I'll keep watching with you. | S |
| `zakah_main_lotGold` | دهب عيار {karat} · {grams} | Gold {karat}K · {grams} | L |
| `zakah_main_lotCash` | كاش وأرصدة بـ{currency}: {amount} | Cash and balances in {currency}: {amount} | L |
| `zakah_main_lotInvest` | أسهم وصناديق بـ{currency}: {amount} | Stocks and funds in {currency}: {amount} | L |
| `zakah_main_lotCertificate` | شهادات بنك: {amount} | Bank certificates: {amount} | L |
| `zakah_main_debtsLine` | بعد خصم الديون المستحقة {debts} | After due debts of {debts} | L · BR-ZAK-04 |
| `zakah_main_hawlProgress` | الحول: {done} من {total} يوم | Hawl: day {done} of {total} | L · BR-ZAK-02 |
| `zakah_main_hawlDone` | الحول تم | Hawl complete | C |
| `zakah_main_dueIn` | `{count, plural, =1{هتستحق بكرة} =2{هتستحق بعد يومين} few{هتستحق بعد {n} أيام} many{هتستحق بعد {n} يوم} other{هتستحق بعد {n} يوم}}` | `{count, plural, =1{Due tomorrow} other{Due in {n} days}}` | L · count:int, n |
| `zakah_main_dueHijri` | هجري: {hijri} | Hijri: {hijri} | C · the due date in the Hijri calendar |
| `zakah_main_due` | المستحق: {dueNative} | Due: {dueNative} | L · native unit (grams of gold, or the currency), FR-ZAK-03 |
| `zakah_main_dueCost` | تقريباً {cost} | ≈ {cost} | L · cost in EGP, with `common_currency_approxCaption` |
| `zakah_main_statusLabel` | حالة الدفع | Payment status | L |
| `zakah_main_statusPending` | لسه | Pending | C |
| `zakah_main_statusPartial` | اتدفع جزء | Partly paid | C |
| `zakah_main_statusPaid` | اتدفعت | Paid | C |
| `zakah_main_paidOn` | اتدفعت يوم {date} | Paid on {date} | L |
| `zakah_main_staleNote` | الأسعار قديمة، فالمبالغ بالجنيه تقريبية. | Prices are out of date, so the EGP amounts are approximate. | S |
| `zakah_main_emptyTitle` | ضيف أصل علشان نحسب الزكاة | Add assets to work out Zakah | T · C-28 |
| `zakah_main_emptyAdd` | ضيف أصل | Add an asset | B · opens S-44 |
| `zakah_main_howTitle` | بتتحسب إزاي؟ | How is it worked out? | T |
| `zakah_main_howNisab` | النصاب {grams} دهب عيار {karat}، بسعر النهارده. | The nisab is {grams} of {karat}K gold at today's price. | S |
| `zakah_main_howHawl` | الحول سنة هجرية، يعني {days} يوم من يوم ما حصلت على الأصل. | The hawl is one lunar year, {days} days from when you got the asset. | S |
| `zakah_main_howRate` | المستحق {percent} من كل أصل بوحدته: الدهب بالجرام والكاش بعملته. | What's due is {percent} of each asset in its own unit: gold in grams, cash in its currency. | S |
| `zakah_main_howPurity` | دهب عيار {karat} بيتحسب بنسبة {percent} ناحية النصاب. | {karat}K gold counts at {percent} toward the nisab. | S · BR-ZAK-03 |
| `zakah_main_howDebts` | الديون اللي ميعادها جه بتتخصم من الكاش قبل الحساب. | Debts that are due now are deducted from cash first. | S |
| `zakah_main_lotA11y` | {lot}، {status}، المستحق {dueNative} | {lot}, {status}, due {dueNative} | A · status = `zakah_main_status*` |

---

## 2.16 S-50 Ask Zaghlol — `chat_main_*`, `chat_chip_*`, `chat_period_*`, `chat_answer_*`, `chat_roast_*`
States: first-time (greeting plus three chips) · typing · answer (text, optional mini chart C-33) · multi-currency · no data (EC-33) · unsupported question (FR-CHAT-03) · slot ambiguous · error · roast on. The "Tips" segment appears only when the `smart_roi` flag is on. A conversation lives on the phone for the session; "Clear chat" is in the overflow menu (UX-A-04). Validation: 1–300 characters, Send disabled when empty.

### Screen
| Key | AR | EN | Notes |
|---|---|---|---|
| `chat_main_segAsk` | اسأل | Ask | C |
| `chat_main_segTips` | نصايح | Tips | C · flag only |
| `chat_main_greeting` | اسألني أي حاجة عن فلوسك، بالمصري أو بالإنجليزي. بجاوبك من بياناتك اللي على موبايلك. | Ask me anything about your money, in Arabic or English. I answer from the data on your phone. | M · Rive `tourGuide`, first open |
| `chat_main_inputHint` | اسألني أي حاجة عن فلوسك… | Ask me about your money… | L · glossary. EN is shorter than the AR |
| `chat_main_sendA11y` | ابعت السؤال | Send question | A |
| `chat_main_tooLong` | `{count, plural, =1{السؤال ميزيدش عن حرف واحد} =2{السؤال ميزيدش عن حرفين} few{السؤال ميزيدش عن {n} حروف} many{السؤال ميزيدش عن {n} حرف} other{السؤال ميزيدش عن {n} حرف}}` | `{count, plural, =1{Keep the question to 1 character} other{Keep the question to {n} characters}}` | S · count:int = 300, n |
| `chat_main_filterNote` | الإجابات على {cards} | Answers cover {cards} | L · the card filter applies to answers |
| `chat_main_roast` | إقصف جبهتي | Roast me | L · toggle. The 🔥 is an icon, not text |
| `chat_main_roastHint` | بيغيّر الأسلوب بس، والأرقام زي ما هي. | Changes the style only. The numbers stay the same. | S · R9 |
| `chat_main_clear` | امسح المحادثة | Clear chat | L · overflow menu |
| `chat_main_cleared` | المحادثة اتمسحت | Chat cleared | N |
| `chat_main_openTransactions` | افتح في الحركات | Open in Transactions | L · opens S-11 with the same filters |
| `chat_main_typingA11y` | زغلول بيكتب | Zaghlol is typing | A |
| `chat_main_userA11y` | إنت قلت: {text} | You said: {text} | A |
| `chat_main_zaghlolA11y` | زغلول رد: {text} | Zaghlol replied: {text} | A |
| `chat_main_chartA11y` | رسم صغير بيقارن الأرقام اللي فوق | A small chart comparing the figures above | A |

### Suggestion chips (FR-CHAT-05)
Tapping a chip sends its text as the question. The default period is the current cycle. The first-time screen shows `chat_chip_card` (if the user has a card), `chat_chip_topMerchants` and `chat_chip_dues`; the engine picks others by what the user has asked and what data exists.

| Key | AR | EN | Notes |
|---|---|---|---|
| `chat_chip_coffee` | صرفت كام على القهوة؟ | How much on coffee? | L |
| `chat_chip_topMerchants` | أكتر أماكن بصرف فيها | Where do I spend most? | L |
| `chat_chip_dues` | إيه الفواتير الجاية؟ | What bills are coming? | L |
| `chat_chip_budgetLeft` | فاضلي كام في الميزانية؟ | What's left in my budget? | L |
| `chat_chip_biggest` | إيه أكبر حاجة صرفتها؟ | What was my biggest expense? | L |
| `chat_chip_savings` | حوشت كام الشهر ده؟ | How much did I save? | L |
| `chat_chip_compare` | قارن الشهر ده باللي فات | This month vs last | L |
| `chat_chip_card` | صرفت كام بكارت {card}؟ | How much on {card}? | L · only for a card the user has |
| `chat_fallback_text` | لسه مبعرفش أجاوب على ده. جرّب واحد من دول: | I can't answer that yet. Try one of these: | M · FR-CHAT-03; three chips follow. No number is ever made up |
| `chat_answer_pickOne` | تقصد أنهي واحد؟ | Which one do you mean? | M · slot ambiguous; candidates appear as chips |

### Periods in a sentence (`span`)
| Key | AR | EN | Notes |
|---|---|---|---|
| `chat_period_today` | النهارده | today | C |
| `chat_period_yesterday` | امبارح | yesterday | C |
| `chat_period_thisWeek` | الأسبوع ده | this week | C |
| `chat_period_lastWeek` | الأسبوع اللي فات | last week | C |
| `chat_period_thisCycle` | الدورة دي | this cycle | C |
| `chat_period_lastCycle` | الدورة اللي فاتت | last cycle | C |
| `chat_period_thisMonth` | الشهر ده | this month | C |
| `chat_period_lastMonth` | الشهر اللي فات | last month | C |
| `chat_period_sinceYearStart` | من أول السنة | since the start of the year | L |
| `chat_period_lastMonths` | `{count, plural, =1{في آخر شهر} =2{في آخر شهرين} few{في آخر {n} شهور} many{في آخر {n} شهر} other{في آخر {n} شهر}}` | `{count, plural, =1{in the last month} other{in the last {n} months}}` | L · count:int, n |
| `chat_period_range` | من {start} لحد {end} | from {start} to {end} | L |
| `chat_period_nextDays` | `{count, plural, =1{بكرة} =2{في اليومين الجايين} few{في الـ {n} أيام الجايين} many{في الـ {n} يوم الجايين} other{في الـ {n} يوم الجايين}}` | `{count, plural, =1{tomorrow} other{in the next {n} days}}` | L · count:int, n · for upcoming dues |
| `chat_period_untilPayday` | لحد القبض | until payday | C |

### Answer templates (class E)
`list` is a set of "name amount" items joined with the locale list format. `span` and `spanB` come from `chat_period_*`. Compare questions are limited to a cycle-or-month pair, so `spanB` always reads naturally after "than".

| Key | AR | EN | Notes |
|---|---|---|---|
| `chat_answer_currencyLead` | بـ{currency}: | In {currency}: | L · printed before each answer when there are 2+ currencies |
| `chat_answer_spendOn` | صرفت {amount} على {subject} {span}. | You spent {amount} on {subject} {span}. | E · spend_on |
| `chat_answer_spendOnCount` | صرفت {amount} على {subject} {span} في {times}. | You spent {amount} on {subject} {span} across {times}. | E · times = `common_unit_visits` or `common_unit_orders` |
| `chat_answer_compare` | `صرفت {amount} {span}، {trend, select, up{أكتر من {spanB} بـ {delta}} down{أقل من {spanB} بـ {delta}} other{زي {spanB} تقريباً}}.` | `You spent {amount} {span}, {trend, select, up{{delta} more than {spanB}} down{{delta} less than {spanB}} other{about the same as {spanB}}}.` | E · `trend:select(up/down/other)` |
| `chat_answer_topMerchants` | أكتر الأماكن {span}: {list}. | Your top merchants {span}: {list}. | E |
| `chat_answer_balance` | رصيد {account} {amount}، آخر تحديث {when}. | {account} has {amount}, as of {when}. | E |
| `chat_answer_balanceCredit` | المتاح في {account} {available} من {limit}. | {account} has {available} available of {limit}. | E |
| `chat_answer_balanceUnknown` | لسه معرفش رصيد {account}. هيظهر مع أول رسالة فيها الرصيد. | I don't know the balance of {account} yet. It'll show up with the first message that includes it. | E |
| `chat_answer_budgetLeft` | فاضلك {left} من ميزانية {subject}. | You have {left} left in your {subject} budget. | E · budget_remaining |
| `chat_answer_budgetLeftPerDay` | فاضلك {left} من الميزانية، يعني {perDay} في اليوم لحد القبض. | You have {left} left in your budget, that's {perDay} a day until payday. | E · overall budget |
| `chat_answer_budgetOver` | {subject} عدّى ميزانيته بـ {gap}. | {subject} is {gap} over its budget. | E · calm, no emoji |
| `chat_answer_budgetNone` | مفيش ميزانية متحطة لـ {subject}. تحب تحطها؟ | There's no budget set for {subject}. Want to set one? | E · plus `budget_overview_emptyAction` |
| `chat_answer_dues` | `{count, plural, =0{مفيش فواتير ولا أقساط {span}.} =1{عليك دفعة واحدة {span}: {list}.} =2{عليك دفعتين {span}: {list}، المجموع {amount}.} few{عليك {n} دفعات {span}: {list}، المجموع {amount}.} many{عليك {n} دفعة {span}: {list}، المجموع {amount}.} other{عليك {n} دفعة {span}: {list}، المجموع {amount}.}}` | `{count, plural, =0{No bills or installments {span}.} =1{You have 1 payment {span}: {list}.} other{You have {n} payments {span}: {list}, {amount} in total.}}` | E · count:int, n · upcoming_dues. `=0` is the no-data case for dues |
| `chat_answer_biggest` | أكبر حاجة صرفتها {span} كانت {amount} عند {merchant} يوم {date}. | Your biggest expense {span} was {amount} at {merchant} on {date}. | E |
| `chat_answer_savings` | `{state, select, short{{span} صرفت أكتر من دخلك بـ {gap}.} other{{span} حوشت {saved}، يعني {percent} من دخلك.}}` | `{state, select, short{{span} you spent {gap} more than you earned.} other{{span} you saved {saved}, that's {percent} of your income.}}` | E · `state:select(short/other)`. |
| `chat_answer_spendCard` | صرفت {amount} بكارت {card} {span}. | You spent {amount} on {card} {span}. | E · spend_on_card |
| `chat_answer_noData` | مفيش صرف على {subject} من {start} لحد {end}. | There's no spending on {subject} between {start} and {end}. | E · EC-33 |
| `chat_answer_noDataGeneric` | مفيش بيانات للفترة دي. | There's no data for that period. | E · EC-33 |
| `chat_answer_error` | حصلت مشكلة وأنا بقرا بياناتك. جرّب تاني. | Something went wrong while reading your data. Try again. | E · with `common_action_tryAgain` |

### Roast lines (class M, A-18 checklist in §2.0.2)
Each line is eligible only when its fact is true and computed, and its category is not an essential (R3, R8). The engine appends one line after the exact answer and varies between the plain and `…Alt` versions. Rive: the chat avatar is `tourGuide`; a roast line switches it to `shocked` for the length of the bubble (trigger: the engine picked a roast fact); `chat_roast_gentle` stays on `tourGuide` and `chat_roast_clean` uses `proud`. With reduce motion on, the still pose is used (FR-MAS-03).

| Key | AR | EN | Notes |
|---|---|---|---|
| `chat_roast_on` | تمام، قلبي جامد وإنت كمان! هقصف على الصرف بس، مش عليك. | Fine, I'm game if you are! I'll roast the spending, never you. | M · Rive `tourGuide`, when the toggle is switched on |
| `chat_roast_off` | رجعنا للجد. الأرقام زي ما هي. | Back to serious. The numbers are as they were. | M |
| `chat_roast_offerToggle` | ده كان قصف سريع. تحب أفتح مود القصف؟ | That was a quick roast. Want me to turn roast mode on? | M · after a typed "roast me" while the toggle is off |
| `chat_roast_delivery` | {orders} بـ {amount} دليفري {span}؟ السواق حافظ عنوانك أكتر مني! 😄 | {orders} worth {amount} of delivery {span}? Your courier knows your door better than I do 😄 | M · fact: delivery orders and amount |
| `chat_roast_deliveryAlt` | {amount} دليفري {span}.. المطبخ مستني زيارة منك! | {amount} on delivery {span}.. Your kitchen is waiting for a visit! | M |
| `chat_roast_coffee` | {amount} قهوة {span}؟ كده إنت شريك في مزرعة البن! ☕ | {amount} on coffee {span}? You're practically a partner in the bean farm! ☕ | M |
| `chat_roast_coffeeAlt` | القهوة {span} بـ {amount}. للأسف الكافيين مبيدفعش فواتيرك 😄 | Coffee cost {amount} {span}. Sadly, caffeine doesn't pay your bills 😄 | M |
| `chat_roast_topCategory` | {category} واخد {percent} من صرفك. ده مش بند، ده هواية! | {category} takes {percent} of your spending. That's not a budget line, that's a hobby! | M · never an essential category |
| `chat_roast_topCategoryAlt` | {category} واخد {percent} من صرفك ولسه بيطلب كمان! | {category} takes {percent} of your spending and is still asking for more! | M |
| `chat_roast_splurge` | {amount} مرة واحدة عند {merchant}؟ ده مش مشوار، ده قرار كبير! | {amount} in one go at {merchant}? That's not an errand, that's a big decision! | M · fact: biggest single non-essential expense |
| `chat_roast_splurgeAlt` | {amount} عند {merchant} دفعة واحدة {span}. ده يوم تاريخي في المحفظة! | {amount} at {merchant} in one go {span}. A historic day for your wallet! | M |
| `chat_roast_weekend` | محفظتك بتخاف من يوم {peakDay}، وعندها حق! | Your wallet is scared of {peakDay}, and it has a point! | M · fact: peak spending day (chart 5) |
| `chat_roast_weekendAlt` | يوم {peakDay} بتصرف في المتوسط {amount}. باقي الأيام بتغير منه! | You average {amount} on {peakDay}. The other days are jealous! | M |
| `chat_roast_subscriptions` | اشتراكاتك بتاخد {yearly} في السنة. فيهم حاجة بتفتحها فعلاً؟ | Your subscriptions take {yearly} a year. Do you actually open any of them? | M |
| `chat_roast_subscriptionsAlt` | اشتراكاتك بـ {yearly} في السنة شغالة حتى وإنت نايم! | Your {yearly} a year in subscriptions keep running even while you sleep! | M |
| `chat_roast_lateNight` | أوردرات بعد الساعة {time}؟ التطبيق صاحي أكتر منك! | Orders after {time}? The app is more awake than you are! | M · fact: delivery orders after the hour in chart 5 |
| `chat_roast_goldEquivalent` | {amount} على {category} كانوا يجيبوا {grams} دهب عيار {karat}. بس كانت حلوة، صح؟ | {amount} on {category} could have bought {grams} of {karat}K gold. But it was fun, right? | M · only when a gold price exists (R8). grams = `common_unit_grams` |
| `chat_roast_gentle` | النهارده مش هقصف جبهتك، الأرقام محتاجة جد. تحب نبص على أكبر بند سوا؟ | I'll skip the roast today. These numbers deserve a serious look. Want to go through the biggest item together? | M · R4: the only line used when spending exceeds income or a bill is overdue. No emoji |
| `chat_roast_clean` | دورت على حاجة أقصفك بيها ومالقيتش! إنت منظم غصب عني 👏 | I looked for something to roast and found nothing! You're annoyingly organised 👏 | M · no eligible fact |

## 2.17 S-51 Smart ROI tips — `roi_tips_*`, `roi_rule<Name>_*` (Gold, hidden unless the `smart_roi` flag is on)
D-38 and FR-ROI-05: **general advice only**. Every rule names a kind of product (an installment plan, a savings certificate, a money-market fund, a yearly plan) and never a bank, fund, brand or product, and uses a clearly labelled example rate. The `roi_named_products` flag stays off. The disclaimer is always visible (FR-ROI-02), in simple standard Arabic with an Egyptian summary above it. The rule texts follow spec §12 with the brand names removed (the spec's brand examples are not used). States: populated · empty · Free-locked · dismissed. The mascot's `roiBulb` pose is silent.

| Key | AR | EN | Notes |
|---|---|---|---|
| `roi_tips_disclaimerSummary` | دي أفكار عامة مش نصيحة مالية. | These are general ideas, not financial advice. | S · above the disclaimer, always visible |
| `roi_tips_disclaimer` | هذه اقتراحات عامة وليست نصيحة مالية أو استثمارية. الأرقام تقديرية وقد تختلف عن الواقع. | These are general suggestions, not financial or investment advice. The figures are estimates and may differ in practice. | S · **simple standard Arabic** (disclaimer exception). Legal sign-off: Q-23 |
| `roi_tips_projection` | `{years, select, two{السنة الأولى: توفير حوالين {year1}. السنة التانية: حوالين {year2}.} other{السنة الأولى: توفير حوالين {year1}.}}` | `{years, select, two{Year 1: save about {year1}. Year 2: about {year2}.} other{Year 1: save about {year1}.}}` | S · `years:select(two/other)`. Figures are rough examples from the user's own spending |
| `roi_tips_share` | شارك | Share | B · opens S-73 |
| `roi_tips_notForMe` | مش ليّا | Not for me | B · hides the tip |
| `roi_tips_dismissed` | اتشالت. مش هتظهرلك تاني. | Removed. It won't show again. | N + `common_action_undo` |
| `roi_tips_badgeA11y` | `{count, plural, =1{نصيحة جديدة واحدة} =2{نصيحتين جداد} few{{n} نصايح جديدة} many{{n} نصيحة جديدة} other{{n} نصيحة جديدة}}` | `{count, plural, =1{1 new tip} other{{n} new tips}}` | A · count:int, n · the badge on the Tips segment |
| `roi_tips_emptyTitle` | مفيش نصايح دلوقتي | No tips right now | T · C-28 |
| `roi_tips_emptyBody` | هقولك أول ما ألاقي حاجة تفيدك. | I'll tell you when I spot something useful. | S |
| `roi_tips_lockedBody` | نصايح مبنية على صرفك إنت، مع جولد | Tips built on your own spending, with Gold | S · plus `common_gold_unlock` |
| `roi_ruleCoffee_title` | ماكينة قهوة بدل الكافيهات | A coffee machine instead of cafés | T |
| `roi_ruleCoffee_body` | بتصرف {monthly} في الشهر في الكافيهات. ماكينة بالتقسيط مع البن والحليب تقريباً {alt} في الشهر. | You spend {monthly} a month at cafés. A machine on installments plus beans and milk comes to about {alt} a month. | E · alt = installment + running cost |
| `roi_ruleDelivery_title` | أكل البيت بدل الدليفري كل يوم | Home cooking instead of daily delivery | T |
| `roi_ruleDelivery_body` | الدليفري واخد {monthly} في الشهر. جهاز طبخ صغير بالتقسيط وأكل البيت تقريباً {alt} في الشهر. | Delivery takes {monthly} a month. A small cooking appliance on installments plus home groceries comes to about {alt} a month. | E |
| `roi_ruleWater_title` | فلتر مياه بدل القوارير | A water filter instead of bottles | T |
| `roi_ruleWater_body` | القوارير والجراكن بـ {monthly} في الشهر. فلتر مياه بالتقسيط مع تغيير الشمعات تقريباً {alt} في الشهر. | Bottled water costs {monthly} a month. A filter on installments plus new cartridges comes to about {alt} a month. | E |
| `roi_ruleIdleCash_title` | فلوسك واقفة من غير عائد | Your cash is sitting idle | T |
| `roi_ruleIdleCash_body` | في حسابك {idle} زيادة عن ميزانيتك بقالهم أكتر من عشرين يوم من غير عائد. صندوق نقدي أو شهادة ممكن يشغّلوهم. معدل مثال للتوضيح: {exampleRate}. | {idle} in your account above your budget has sat there for over twenty days earning nothing. A money-market fund or a savings certificate could put it to work. Example rate, for illustration only: {exampleRate}. | E · the rate is an example, not an offer and not guaranteed |
| `roi_ruleCommute_title` | مشاويرك المتكررة بالتطبيقات | Your regular app rides | T |
| `roi_ruleCommute_body` | مشاويرك بتطبيقات التوصيل بـ {monthly} في الشهر. وسيلة مواصلات بالتقسيط مع مواصلات عامة للمشاوير الطويلة تقريباً {alt} في الشهر. | Ride-hailing costs you {monthly} a month. A vehicle on installments plus public transport for long trips comes to about {alt} a month. | E |
| `roi_ruleCardInterest_title` | سدد الكريدت كارد كله | Pay your credit card in full | T |
| `roi_ruleCardInterest_body` | عليك {balance} على الكريدت كارد وعندك كاش أكتر منه. السداد الكامل قبل ميعاد الكشف بيوفر الفوايد. معدل مثال للتوضيح: {exampleRate} في الشهر. | You owe {balance} on your credit card and hold more cash than that. Paying in full before the statement date saves the interest. Example rate, for illustration only: {exampleRate} a month. | E |
| `roi_ruleSubscriptions_title` | اشتراك سنوي واحد بدل كذا اشتراك | One yearly plan instead of several | T |
| `roi_ruleSubscriptions_body` | بتدفع {monthly} في الشهر على اشتراكات كتير. باقة سنوية مشتركة ممكن تنزلها لحوالين {alt} في الشهر. | You pay {monthly} a month across several subscriptions. A shared yearly plan could bring that to about {alt} a month. | E |
| `roi_ruleStaples_title` | اشتري الأساسيات مرة واحدة يوم القبض | Buy staples once, on payday | T |
| `roi_ruleStaples_body` | بتشتري الأساسيات على مرات صغيرة بـ {monthly} في الشهر. شراء بالجملة مرة واحدة يوم القبض ممكن يخليها حوالين {alt}. | You buy staples in many small trips for {monthly} a month. One bulk shop on payday could bring that to about {alt}. | E |

---

## 2.K Key count (Part 2)
| Section | Screens | Keys |
|---|---|---|
| 2.1 `common_*` and `mascot_*` additions | shared | 22 |
| 2.2 Charts | S-20 | 59 |
| 2.3 Chart detail and explainer | S-21 | 12 |
| 2.4 Chart explanation templates | S-21 (12 charts × 4) | 48 |
| 2.5 Budget | S-22 | 21 |
| 2.6 Edit budgets, annual budgets | S-23 | 22 |
| 2.7 Bills and installments | S-24 | 27 |
| 2.8 Add / edit bill | S-25 | 19 |
| 2.9 Quick add | S-30 | 10 |
| 2.10 Voice logger | S-31 | 29 |
| 2.11 Scan screenshot | S-32 | 22 |
| 2.12 S-40 additions (assets, unit lines, hidden accounts) | S-40 | 19 |
| 2.13 Add / edit asset | S-44 | 29 |
| 2.14 Prices | S-45 | 18 |
| 2.15 Zakah | S-46 | 33 |
| 2.16 Ask Zaghlol (screen 16, chips 10, periods 13, answers 19, roast 19) | S-50 | 77 |
| 2.17 Smart ROI | S-51 | 26 |
| **Part 2 ARB total** | | **493** |
| **Deck total (Parts 1 + 2)** | | **1,176 ARB keys + 12 native** |

Plural messages in Part 2: 17 (2 with `=0`: `recurring_billEdit_remind`, `chat_answer_dues`; 15 on the no-zero list in §0.4). Select messages in Part 2: 28. The deck as a whole now has 55 plural and 36 select messages. The T-029 counting note in §1.K still applies: count only rows with four cells.

## 2.Q Open questions and spec gaps (Part 2)
Nothing here blocks T-029 or T-087. Drafts are used where a question is open.

| ID | Where | Issue | Draft used | Needs |
|---|---|---|---|---|
| Q-19 | S-21 explanations | OQ-07 is **decided here** (§2.0.1): Free = one fact + one tip; Gold = fact + previous-cycle comparison + sized tip, with a projection and top-3 merchants on charts 1, 2, 3, 5 and 7. `domain-algorithms.md` §8 lists the same split but not which charts get the extras. | As in §2.0.1 | Architect: confirm the per-chart extras fit `ExplanationTemplate`; requirements analyst: close OQ-07 in the SRS |
| Q-20 | S-21 tips | Some basic tips are mild advice ("move part of the surplus to savings", "keep an eye on a concentrated slice"). Smart ROI has a "not financial advice" line, but charts do not. | No disclaimer on S-21 | PO / legal: whether a short disclaimer line is needed under chart tips |
| Q-21 | S-31 consent | `voice_logger_onlineBody` tells the user their voice goes to Apple's or Google's speech service when on-device Arabic isn't available (D-42, OQ-06). The wording is accurate about Zaghlol ("doesn't keep the recording") and does not describe what the OS vendor keeps. | As written | Security/privacy reviewer: confirm the wording and whether the vendor's retention needs a mention |
| Q-22 | S-25 delete | `recurring_billEdit_deleteBody` says already-recorded transactions stay. That matches the schema (`recurring_occurrences.txn_id` points at a transaction), but no spec states it. | "Transactions already recorded stay" | Architect: confirm |
| Q-23 | S-46, S-51 disclaimers | The Zakah and Smart ROI disclaimers are written in simple standard Arabic (the disclaimer exception). They are drafts. Zakah rules (nisab, hawl, 21K purity) also need scholar review before the flag turns on (D-07, BR-ZAK-05). | Drafts in `zakah_main_disclaimer` and `roi_tips_disclaimer` | PO / legal for the wording; scholar for the Zakah text; T-058 for naturalness |
| Q-24 | S-51 rule 4 | The spec's idle-cash rule says "Shariah-compliant" and quotes about 22%. D-38 bans named yields and products, and a halal claim would need scholar sign-off. | General wording, a labelled example rate, no halal claim | PO: whether a halal mention is wanted; who owns the example-rate table (operator catalog) |
| Q-25 | S-50 roast | The engine needs a list of "essential" categories that are never roasted (R3) and the exact conditions for `chat_roast_gentle` (R4). | Rent, bills, groceries, health, education, fees, debt payments, work transport; overspend or an overdue bill | Product owner to approve the list; architect to implement |
| Q-26 | S-50 periods | Chips and the default period say «الشهر ده», while the app's period is the payday cycle. For a user with payday on the 25th, "this month" is ambiguous. | «الشهر ده» in chips; the engine treats it as the current cycle when a payday is set, and says the dates in the answer if they differ | UX / PO: confirm, or switch the chips to «الدورة دي» |
| Q-27 | `hijri` formatter | S-46 shows a Hijri due date. `hijri` is a Date-type placeholder with digits per `DigitsMode`, and the engine uses the Umm al-Qura table (`domain-algorithms.md` §12). The ARB layer has no ICU Hijri formatting. | Registry row `hijri` (Date) | Architect: confirm the formatter, together with Q-15 |
| Q-28 | S-21, S-50 digits | `karat` is a plain integer from the digits layer (24, 21, 18), and `grams` uses up to three decimals through `common_unit_grams`. Egyptians say «عيار واحد وعشرين»; the numeral form is used here. | Numerals | T-058: native-speaker check |
| Q-29 | S-40 hidden list | The spec now describes the hidden list as a plain list. Whether it is a full screen or a sheet is a layout choice. | Full screen (back arrow), title `accounts_hidden_title` | UX: confirm in the golden tests |

## 2.C Changelog (Part 2)
- 2026-11-08 — first draft (T-027), 493 ARB keys.
  - **Conventions added:** class **E** and a fixed B/C row in §0.7 (R2-2); 66 placeholder rows in §0.3a; 15 no-zero rows in §0.4; the Free/Gold explanation rule (§2.0.1); the roast checklist (§2.0.2).
  - **Part 1 rows touched:** the note on `accounts_overview_hiddenEntry` and the Q-11 row now point at §2.12 (R2-4); the deck header status line.
  - **Spec edited:** `screens/50-money.md` S-40 (unit lines, asset rows, hidden-accounts row and list).
  - **Not touched on purpose:** the three Part 1 length overruns (R2-1) and the other T-029 carry-overs from the T-026 review, which belong to that task.

<!-- ===================== PART 3 (T-028) appends below ===================== -->
