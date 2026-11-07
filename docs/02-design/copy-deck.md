# Copy deck — زغلول / Zaghlol

| | |
|---|---|
| Status | **DRAFT — Part 1 (T-026)**. Parts 2 (T-027) and 3 (T-028) append below their markers. |
| Voice | `06-voice-and-tone.md` (D-34): Egyptian colloquial everywhere; simple standard Arabic only for legal text and disclaimers (Part 3). |
| Sources | SRS `docs/01-requirements/requirements.md`; screens `02-screen-inventory.md`, `screens/10…70-*.md`, `07-flows-onboarding-cards-import.md`; mascot `04-design-system.md` §4 and `08-mascot-motion-and-bank-logos.md` (D-35); mockup copy in `mockups/source/*.py` (reused where it already fit the voice). |
| Consumers | T-029 (ARB part 1), T-058 (native Egyptian-speaker review), T-087 (ARB parts 2–3). Keys map 1:1 to ARB keys (ADR-017). |

---

## 0. Conventions (all parts)

### 0.1 Key naming
`<feature>_<screen>_<element>` (`project-structure.md`), exactly three underscore-separated segments, all camelCase within a segment. Example: `home_hero_safeToSpend`.
- **feature**: an app feature folder from `architecture.md` (`onboarding`, `capture`, `ingestion`, `home`, `transactions`, `transfers`, `accounts`, `backup`, `security`, …). There are two extras: `common` for strings shared by several features, and `mascot` for Captain Zaghlol lines that aren't tied to one screen.
- **screen**: the screen, sheet or region inside the feature, e.g. `welcome`, `androidSetup`, `hero`, `detail`. On Home the middle segment names the region (`hero`, `banner`, `mascot`, …), following the `home_hero_safeToSpend` precedent.
- **element**: what the string is, e.g. `title`, `body`, `smsAllow`, `errorNetwork`, `a11yRow`. Screen-reader-only strings end in `A11y`.
- Keys are stable. If wording changes, keep the key. If meaning changes, add a new key and retire the old one in the changelog at the end of the part.

### 0.2 Table format
Each section has a table: **Key | AR (عامية مصرية) | EN | Notes**. Notes hold the length class (§0.7), the placeholders and, for mascot lines, the Rive state and trigger.

### 0.3 Placeholders
- Every placeholder is a **String that code has already formatted** (`MoneyFormat` / digits layer / date formatter). The ARB text never formats numbers itself, because the Arabic UI can show either Arabic-Indic or Western digits (A-29, FR-L10N-03), and ICU number formatting can't follow that preference.
- `{amount}` is a complete money string including the currency, per `04-design-system.md` §2.3. AR: `٤٥٠ ج.م`, `١٬٢٠٠ USD`. EN: `EGP 450`, `USD 1,200`. Signs (`−`/`+`) are added by the money layer, never written in copy.
- `{percent}` includes its sign (`٩٦٪` / `96%`). `{date}`, `{time}`, `{when}` are locale-formatted (`٢٣ أكتوبر` / `23 Oct`).
- `{card}` is the card label plus last-4 (`الأهلي فيزا •4567`). `{merchant}`, `{bank}`, `{sender}`, `{counterparty}` are data values and may be Latin.
- **No literal digits in Arabic strings.** Fixed small numbers are written as words («آخر أربع أرقام», «نص دقيقة»). Any other number is a placeholder. English strings may contain literal digits, because English always uses Western digits.

### 0.4 Plurals (ICU, gen-l10n)
- A plural message takes two placeholders. `count` (**int**) only selects the form and is **never printed**. `n` (**String**, formatted by the digits layer) is printed.
- **Arabic must supply all six forms**: `=0`, `=1`, `=2`, `few` (3–10, 103–110, …), `many` (11–99, …), `other` (100–102, …). Egyptian noun forms used throughout:

| Noun | =1 | =2 | few | many / other |
|---|---|---|---|---|
| حركة | حركة واحدة | حركتين | {n} حركات | {n} حركة |
| كارت | كارت واحد | كارتين | {n} كروت | {n} كارت |
| يوم | يوم | يومين | {n} أيام | {n} يوم |
| شهر | شهر | شهرين | {n} شهور | {n} شهر |
| دقيقة | دقيقة | دقيقتين | {n} دقايق | {n} دقيقة |
| خطوة | خطوة واحدة | خطوتين | {n} خطوات | {n} خطوة |
| رسالة | رسالة واحدة | رسالتين | {n} رسايل | {n} رسالة |
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
- **Every placeholder that can hold Latin text or numbers** (`amount`, `card`, `merchant`, `sender`, `counterparty`, `bank`, `percent`, `date`, `time`, `n`) is wrapped in a Unicode first-strong isolate (U+2068 … U+2069) by the presentation layer, **not** in the ARB text. That keeps `−٤٥٠ ج.م` and `•4567` from reordering inside Arabic sentences (`04-design-system.md` §2.3 "Bidi").
- Latin brand names written literally in Arabic strings (Wise, Revolut, Payoneer, Apple Pay, Google Drive, iCloud, Shortcuts, Face ID) are single runs and safe without isolates. If a string ends with a Latin word followed by punctuation, check it in the RTL golden test.
- Elements that **do not mirror**: the mascot, checkmarks ✓, clock icons, card last-4, phone numbers, chart values. **Chart time axes do mirror** (UX-D-01).

### 0.7 Length classes (Notes column)
Measured in characters, including spaces, at 100% text scale. Layouts must still survive 130% (NFR-UX-02).

| Class | Use | AR max | EN max |
|---|---|---|---|
| **B** | Button (≤ 3 words, `06-voice-and-tone.md` §1.3) | 20 | 22 |
| **C** | Chip, badge, tab, segment | 16 | 16 |
| **L** | Field label, list-row title, KPI label | 28 | 30 |
| **T** | Screen or sheet title, headline | 40 | 44 |
| **S** | Sentence or body (one to two lines) | 120 | 130 |
| **M** | Mascot bubble (C-14) | 120 | 130 |
| **N** | Snackbar, toast or banner (one line plus action) | 70 | 75 |
| **A** | Screen-reader only (not shown) | — | — |

Placeholder values aren't counted. Where a placeholder is long (a merchant or card name), the UI truncates the placeholder, not the copy.

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
- **Part 3** owns the error catalogue that maps `Failure` codes to copy. The three `common_error_*` keys in Part 1 are the generic fallbacks used by Part 1 screens, and Part 3 may point Failure codes at them.

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
| `common_source_shared` | رسالة اتبعتت | Shared message | C · share/paste, FR-ING-A-04. See Q-02 |

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
| `common_date_minutesAgo` | `{count, plural, =1{من دقيقة} =2{من دقيقتين} few{من {n} دقايق} many{من {n} دقيقة} other{من {n} دقيقة}}` | `{count, plural, =1{1 min ago} other{{n} min ago}}` | C · count:int, n |
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
| `mascot_avatar_a11y` | الكابتن زغلول | Captain Zaghlol | A · label on every `ZaghlolAvatar` |
| `mascot_pull_refreshingA11y` | بحدّث… | Refreshing… | A · Rive `pull`, pull to refresh on Home and lists |
| `mascot_saved_line1` | اتسجلت ✓ | Saved ✓ | N · Rive `saved` · after saving a transaction (S-13 or Quick add). Picked at random from line1…3 |
| `mascot_saved_line2` | تمام، حطيتها في الحسبة ✓ | Done — it's in the books ✓ | N · Rive `saved` |
| `mascot_saved_line3` | اتقيدت يا كبير ✓ | Logged it ✓ | N · Rive `saved` |
| `mascot_tap_line1` | إيه يا عم، بتزغزغني؟ 😄 | Hey, that tickles! 😄 | M · Rive `tap` · user taps Zaghlol. The next unused line rotates each tap |
| `mascot_tap_line2` | أنا هنا يا كبير، وفلوسك في عينيّا | Still here, keeping an eye on your money | M · Rive `tap` |
| `mascot_tap_line3` | كل جنيه بتحوشه بيطلّعلي ريشة جديدة 🪶 | Every pound you save grows me a new feather 🪶 | M · Rive `tap` |
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
| `onboarding_welcome_pointOnPhone` | بيانات فلوسك بتفضل على موبايلك | Your money data stays on your phone | L · FR-ONB-01, with a lock icon (not an emoji) |
| `onboarding_welcome_pointNoPassword` | مش هنطلب باسورد البنك أبداً | We'll never ask for your bank password | L |
| `onboarding_welcome_pointNoAds` | من غير إعلانات | No ads | L |
| `onboarding_welcome_start` | يلا نبدأ | Let's go | B · primary. Opens S-02 or S-03 |
| `onboarding_welcome_restore` | أنا مستخدم زغلول قبل كده | I already use Zaghlol | B · text button, opens S-04 (FR-ONB-12) |
| `onboarding_welcome_privacyLink` | تفاصيل الخصوصية | Privacy details | B · text link, opens S-71 read-only |

## 1.4 S-02 Capture setup — Android — `onboarding_androidSetup_*`
States: step 1 (SMS) · granted · denied/degraded · Play-unavailable · step 2 (notifications + live scan) · notification access returned on/off · scan error (shown on Home).

| Key | AR | EN | Notes |
|---|---|---|---|
| `onboarding_androidSetup_step` | خطوة {step} من {total} | Step {step} of {total} | C · C-26 stepper header |
| `onboarding_androidSetup_smsTitle` | خليني أقرا رسايل البنك | Let me read your bank texts | T · M · Rive `tourGuide`, setup step |
| `onboarding_androidSetup_smsSubtitle` | وهرتبلك كل مصاريفك لوحدي. | I'll sort out all your spending for you. | S |
| `onboarding_androidSetup_smsPointSenders` | بقرا رسايل البنوك والمحافظ وإنستاباي بس | I only read messages from banks, wallets and InstaPay | S · what is read (FR-ING-A-02) |
| `onboarding_androidSetup_smsPointPersonal` | رسايلك الشخصية عمرها ما بتتقري ولا بتتحفظ | Your personal messages are never read or saved | S |
| `onboarding_androidSetup_smsPointOnPhone` | كل حاجة بتفضل على الموبايل ده | Everything stays on this phone | S · financial data, true per CLAUDE.md §2.1 |
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
| `onboarding_androidSetup_degradedShare` | ابعت أو الزق رسالة البنك لزغلول | Share or paste a bank message | L · row action `onboarding_androidSetup_degradedShareHow` |
| `onboarding_androidSetup_degradedShareHow` | إزاي؟ | How? | B · opens the `capture_shareHow_*` sheet |
| `onboarding_androidSetup_degradedManual` | سجّل الكاش بصوتك أو بإيدك | Log cash by voice or typing | L |
| `onboarding_androidSetup_degradedRetry` | اسمح تاني | Ask again | B · when the OS still allows a prompt |
| `onboarding_androidSetup_degradedSettingsHint` | علشان تشغلها، افتح الإعدادات واسمح لزغلول بالرسايل. | To turn it on, open Settings and allow Zaghlol to read SMS. | S · when the OS blocks re-prompting; with `common_action_openSettings` |
| `onboarding_androidSetup_playUnavailable` | النسخة دي من زغلول مش بتقرا SMS، بس الإشعارات والمشاركة شغالين تمام. | This version of Zaghlol can't read SMS, but notifications and sharing work fine. | S · when the build doesn't have the Play SMS exception (FR-ING-A-05). See Q-03 |

## 1.5 S-03 Capture setup — iOS — `onboarding_iosSetup_*`
States: step 1 · returned and checking (≤ 2 s) · Shortcuts app missing · step 2 all good / something missing / can't tell · step 3 first expense. iOS labels such as "Run Immediately" stay in English (see Q-04).

| Key | AR | EN | Notes |
|---|---|---|---|
| `onboarding_iosSetup_step` | خطوة {step} من {total} | Step {step} of {total} | C |
| `onboarding_iosSetup_shortcutTitle` | الآيفون مش بيسمح للتطبيقات تقرا الرسايل… فهنستخدم الاختصارات | iPhone doesn't let apps read texts — so we use Shortcuts | T · M · Rive `tourGuide` |
| `onboarding_iosSetup_shortcutLead` | ضغطة واحدة بتضيف: | One tap adds: | L |
| `onboarding_iosSetup_shortcutSmsTitle` | رسايل البنك | Bank texts | L |
| `onboarding_iosSetup_shortcutSmsSub` | بيلقط رسايل البنوك وإنستاباي، عربي وإنجليزي | Catches bank and InstaPay texts, in Arabic and English | S |
| `onboarding_iosSetup_shortcutApplePayTitle` | مدفوعات Apple Pay | Apple Pay payments | L |
| `onboarding_iosSetup_shortcutApplePaySub` | بيسجل أي دفع بالموبايل في ساعتها | Logs every tap-to-pay as it happens | S |
| `onboarding_iosSetup_shortcutOnce` | مرة واحدة بس، وبعدها كل حاجة بتتسجل لوحدها. | Just once — then everything logs itself. | S |
| `onboarding_iosSetup_shortcutAdd` | ضيف اختصار زغلول | Add Zaghlol shortcut | B · primary, opens the Shortcuts import |
| `onboarding_iosSetup_howItWorks` | إزاي بيشتغل؟ (نص دقيقة) | How it works (30 sec) | B · text, expands the steps below |
| `onboarding_iosSetup_howStep1` | لما توصلك رسالة من بنك، الآيفون بيشغّل الاختصار لوحده. | When a bank text arrives, your iPhone runs the shortcut by itself. | S · list numbers are drawn by the UI, not the copy |
| `onboarding_iosSetup_howStep2` | الاختصار بيدّي نص الرسالة لزغلول على نفس الموبايل، مش بيبعته لأي حد. | The shortcut hands the text to Zaghlol on this same phone — it isn't sent anywhere. | S · precise claim about the message, not "no server" |
| `onboarding_iosSetup_howStep3` | زغلول يقرا المبلغ والتاجر ويسجلها. خلاص كده. | Zaghlol reads the amount and merchant and logs it. That's it. | S |
| `onboarding_iosSetup_checking` | ثانية، بشوف الاختصارات اتضافت ولا لأ… | One sec — checking your shortcuts… | L · spinner, ≤ 2 s |
| `onboarding_iosSetup_shortcutsMissing` | مقدرتش أفتح تطبيق الاختصارات. نزّله من الـ App Store وجرّب تاني. | Couldn't open the Shortcuts app. Get it from the App Store and try again. | S · error, no joke |
| `onboarding_iosSetup_checkTitle` | تعالى نتأكد إن كله تمام | Let's make sure it all works | T |
| `onboarding_iosSetup_checkSubtitle` | زغلول بيبص على الاختصارات اللي اتضافت. | Zaghlol is checking which automations were added. | S |
| `onboarding_iosSetup_checkSmsAr` | رسايل البنوك (عربي) | Bank texts (Arabic) | L |
| `onboarding_iosSetup_checkSmsEn` | رسايل البنوك (إنجليزي) | Bank texts (English) | L |
| `onboarding_iosSetup_checkApplePay` | مدفوعات Apple Pay | Apple Pay payments | L |
| `onboarding_iosSetup_checkCount` | `{count, plural, =1{{done} من {n} أوتوميشن} other{{done} من {n} أوتوميشن}}` | `{count, plural, =1{{done} of 1 automation} other{{done} of {n} automations}}` | L · count:int = total, n, done. «أوتوميشن» doesn't change in AR, but the plural is kept so both locales share placeholders |
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
| `onboarding_iosSetup_firstSayHint` | «دفعت خمسة وأربعين قهوة» | "45 on coffee" | C · spoken example. AR uses number words (§0.3) |
| `onboarding_iosSetup_firstType` | اكتبها | Type it | B · opens S-13 |
| `onboarding_iosSetup_firstTypeHint` | المبلغ والتصنيف | Amount and category | C |
| `onboarding_iosSetup_firstOnlineBanks` | بتستخدم Wise أو Revolut أو Payoneer؟ | Use Wise, Revolut or Payoneer? | L · opens S-61 supported banks (FR-ING-I-08) |
| `onboarding_iosSetup_firstOnlineBanksSub` | شوف إزاي تتابعهم على الآيفون | See how to track them on iPhone | S |
| `onboarding_iosSetup_firstStatement` | عندك كشف حساب؟ | Got a bank statement? | L · with the Gold badge (FR-EXP-06); Free opens S-68 |
| `onboarding_iosSetup_firstStatementSub` | ضيف شهور فاتت مرة واحدة | Add past months in one go | S |

## 1.6 S-04 Restore from backup — `backup_restore_*`
States: choose storage · signing in · searching · found (Free: one; Gold: up to 5) · passphrase wrong · restoring · empty · network error · newer version (EC-26) · corrupted · forgot passphrase (EC-27) · done (shown on Home). No jokes anywhere on this screen.

| Key | AR | EN | Notes |
|---|---|---|---|
| `backup_restore_title` | استرجاع نسخة | Restore from backup | T |
| `backup_restore_whereTitle` | النسخة بتاعتك فين؟ | Where's your backup? | T |
| `backup_restore_optionDrive` | Google Drive | Google Drive | L |
| `backup_restore_optionICloud` | iCloud | iCloud | L · iOS only |
| `backup_restore_searching` | بدوّر على نسخة زغلول… | Looking for your Zaghlol backup… | L · spinner |
| `backup_restore_foundTitle` | لقيت نسخة | Backup found | T |
| `backup_restore_foundMeta` | {date} · {size} | {date} · {size} | L · size = `common_fileSize_mb` |
| `backup_restore_foundFrom` | من: {platform} · إصدار {appVersion} | From: {platform} · v{appVersion} | L · appVersion stays Latin, e.g. `1.0` |
| `backup_restore_versionsTitle` | النسخ اللي عندك | Your backups | L · Gold list, newest first |
| `backup_restore_versionNewest` | الأحدث | Newest | C |
| `backup_restore_passphraseLabel` | كلمة سر النسخة | Backup passphrase | L · C-32, single field |
| `backup_restore_restore` | استرجع | Restore | B · primary |
| `backup_restore_passphraseRequired` | اكتب كلمة السر | Enter the passphrase | S |
| `backup_restore_passphraseWrong` | كلمة السر دي مش بتفتح النسخة دي | That passphrase doesn't open this backup | S · unlimited retries |
| `backup_restore_forgotLink` | نسيت كلمة السر؟ | Forgot the passphrase? | B · text |
| `backup_restore_forgotBody` | للأسف مفيش طريقة نرجّعها. النسخة متقفلة بكلمة السر دي بس، ومحدش، ولا حتى إحنا، يقدر يفتحها من غيرها. تقدر تبدأ من جديد. | Sorry — there's no way to recover it. The backup is locked with that passphrase only, and nobody, not even us, can open it without it. You can start fresh. | S · EC-27, calm and plain |
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
| `security_lock_unlock` | `{method, select, faceId{افتح بالـ Face ID} touchId{افتح بالـ Touch ID} fingerprint{افتح ببصمتك} face{افتح ببصمة الوش} other{افتح القفل}}` | `{method, select, faceId{Unlock with Face ID} touchId{Unlock with Touch ID} fingerprint{Unlock with fingerprint} face{Unlock with face} other{Unlock}}` | B · method from the available biometric |
| `security_lock_usePasscode` | `{platform, select, ios{استخدم كود الآيفون} other{استخدم قفل الموبايل}}` | `{platform, select, ios{Use passcode} other{Use phone lock}}` | B · text (A-08) |
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
| `home_hero_budgetUsedUp` | ميزانية الدورة دي خلصت، حاسب على الباقي | This cycle's budget is used up — go easy on the rest | S · safe-to-spend ≤ 0. Calm, no joke. See Q-06 |
| `home_hero_kpiIncome` | دخلك | Income | C · C-10 |
| `home_hero_kpiSpent` | صرفت | Spent | C · tap opens S-11 filtered |
| `home_hero_kpiLeft` | فاضلك | Left | C |
| `home_hero_approxTitle` | كله تقريباً بالـ {currency} | Everything, roughly in {currency} | L · last pager page, only when the ≈ view is on (FR-CUR-04) |
| `home_hero_a11y` | مسموحلك تصرف {amount} النهارده. {payday}. دخلك {income}، صرفت {spent}، فاضلك {left}. | Safe to spend today: {amount}. {payday}. Income {income}, spent {spent}, left {left}. | A · payday = `home_hero_daysToPayday` text |

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
| `home_mascot_payday` | المرتب نزل! {amount} 🎉 يلا نخطط له من أوله | Payday! {amount} just landed 🎉 Let's plan it from day one | M · Rive `payday` · salary detected (D-35), once per payday |
| `home_mascot_dismissA11y` | اقفل الرسالة | Dismiss message | A · × on C-14 |

### Contextual prompts (each appears once and can be dismissed for good, FR-ONB-10 / FR-ONB-04)
| Key | AR | EN | Notes |
|---|---|---|---|
| `home_prompt_payday` | لقيت مرتب {amount} بينزل يوم {day} كل شهر. ده ميعاد قبضك؟ | I spotted a salary of {amount} landing on day {day} each month. Is that your payday? | M · Rive `detective` · salary-like credit detected |
| `home_prompt_paydayYes` | أيوه، يوم {day} | Yes, day {day} | B · day 1–28 only, see Q-07 |
| `home_prompt_paydayNo` | لأ | No | B |
| `home_prompt_budget` | خلصت أول دورة معايا! تحب نحط ميزانية للدورة الجاية؟ | First full cycle done! Want to set a budget for the next one? | M · Rive `tourGuide` · first full cycle completed |
| `home_prompt_budgetYes` | يلا | Let's do it | B · opens S-23 |
| `home_prompt_backup` | بقالك أسبوع بتسجل معايا. اعمل نسخة احتياطية ببلاش عشان بياناتك تفضل في أمان لو حصل حاجة للموبايل. | A week of data so far. Make a free backup so it's safe if anything happens to your phone. | M · Rive `tourGuide` · A-65, 7 days of data |
| `home_prompt_backupYes` | اعمل نسخة | Back up | B · opens S-66 |
| `home_prompt_appLockTitle` | `{method, select, faceId{اقفل زغلول بالـ Face ID؟} touchId{اقفل زغلول بالـ Touch ID؟} fingerprint{اقفل زغلول ببصمتك؟} face{اقفل زغلول ببصمة الوش؟} other{اقفل زغلول بقفل الموبايل؟}}` | `{method, select, faceId{Lock Zaghlol with Face ID?} touchId{Lock Zaghlol with Touch ID?} fingerprint{Lock Zaghlol with your fingerprint?} face{Lock Zaghlol with face unlock?} other{Lock Zaghlol with your phone lock?}}` | L · FR-ONB-04, a one-tap switch, offered only once transactions are visible |
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
| `transactions_row_a11y` | {merchant}، {amount}، {category}، {card}، {time} | {merchant}, {amount}, {category}, {card}, {time} | A · whole-row label |
| `transactions_row_swipeCategory` | غيّر التصنيف | Change category | C · swipe from the start edge; also an a11y action |
| `transactions_row_swipeSplit` | تقسيم / فلوس راجعة | Split / money back | C · swipe from the end edge; also an a11y action |

## 1.11 S-11 Transactions — `transactions_list_*`
States: loading (skeleton) · empty · no results · filtered · selection mode · bulk delete confirm · error (`common_error_loadFailed`).

| Key | AR | EN | Notes |
|---|---|---|---|
| `transactions_list_title` | الحركات | Transactions | T |
| `transactions_list_searchHint` | دوّر على تاجر، ملاحظة أو مبلغ | Search merchant, note or amount | L · FTS, debounced 250 ms; Arabic-Indic digits accepted (CLAUDE.md §2.5) |
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
| `transactions_list_bulkAccount` | الكارت | Card | C |
| `transactions_list_bulkDelete` | امسح | Delete | C |
| `transactions_list_bulkCancel` | إلغاء | Cancel | C |
| `transactions_list_bulkRule` | استخدم ده دايماً للتجار دول | Always use this for these merchants | L · switch after a category change; creates rules (FR-CAT) |
| `transactions_list_bulkChanged` | `{count, plural, =1{اتغيرت حركة واحدة} =2{اتغيرت حركتين} few{اتغيرت {n} حركات} many{اتغيرت {n} حركة} other{اتغيرت {n} حركة}}` | `{count, plural, =1{1 transaction updated} other{{n} transactions updated}}` | N · count:int, n + `common_action_undo` (restores all) |
| `transactions_list_bulkDeleteTitle` | `{count, plural, =1{تمسح حركة واحدة؟} =2{تمسح الحركتين؟} few{تمسح {n} حركات؟} many{تمسح {n} حركة؟} other{تمسح {n} حركة؟}}` | `{count, plural, =1{Delete 1 transaction?} other{Delete {n} transactions?}}` | T · count:int, n · C-18 destructive |
| `transactions_list_bulkDeleteBody` | مش هتقدر ترجعها بعد كده. | You won't be able to get them back. | S · see Q-08 |
| `transactions_list_bulkDeleted` | `{count, plural, =1{اتمسحت حركة واحدة} =2{اتمسحت حركتين} few{اتمسحت {n} حركات} many{اتمسحت {n} حركة} other{اتمسحت {n} حركة}}` | `{count, plural, =1{1 transaction deleted} other{{n} transactions deleted}}` | N · count:int, n · no Undo |
| `transactions_list_selectRowA11y` | اختار {merchant} | Select {merchant} | A · check circle |

## 1.12 S-12 Transaction detail — `transactions_detail_*` and rule sheet `transactions_rule_*`
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
| `transactions_detail_noteAdd` | ضيف ملاحظة | Add a note | B · text |
| `transactions_detail_noteHint` | اكتب ملاحظة… | Write a note… | L · ≤ 200 (`common_validation_noteLength`) |
| `transactions_detail_split` | تقسيم / فلوس راجعة من صحابك | Split / money back from friends | L · expenses, opens S-15 Mode A |
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
| `transactions_detail_deleteBodyAuto` | `{platform, select, android{جت من رسالة، ومش هترجع غير لو دوّرت في الرسايل من جديد.} other{مش هتقدر ترجعها بعد كده.}}` | `{platform, select, android{It came from a message and won't come back unless you re-scan.} other{You won't be able to get it back.}}` | S · auto-captured; re-scan is Android only |
| `transactions_detail_deleteBodyManual` | مش هتقدر ترجعها بعد كده. | You won't be able to get it back. | S |
| `transactions_detail_deleted` | اتمسحت | Deleted | N |
| `transactions_detail_gone` | الحركة دي مبقتش موجودة | This transaction no longer exists | N · deleted elsewhere; goes back |
| `transactions_rule_title` | أستخدم {category} دايماً لـ {merchant}؟ | Always use {category} for {merchant}? | T · FR-CAT-05 sheet |
| `transactions_rule_always` | دايماً | Always | B |
| `transactions_rule_once` | المرة دي بس | Just this once | B |
| `transactions_rule_applyPast` | `{count, plural, =1{وكمان غيّر الحركة القديمة} =2{وكمان غيّر الحركتين القدام} few{وكمان غيّر الـ {n} حركات القديمة} many{وكمان غيّر الـ {n} حركة القديمة} other{وكمان غيّر الـ {n} حركة القديمة}}` | `{count, plural, =1{Also update 1 past transaction} other{Also update {n} past transactions}}` | L · count:int, n · checkbox (A-13), hidden when count = 0 |
| `transactions_rule_saved` | تمام، هفتكر ده ✓ | Got it — I'll remember ✓ | N + `common_action_undo` |

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
| `ingestion_review_title` | مستني رأيك 👀 | Needs your review | T · glossary (emoji only in AR, where the glossary has it) |
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
| `ingestion_review_genLowConfidence` | مش متأكد أوي، بص عليها قبل ما أسجلها | Not totally sure — check it before I log it | S · FR-PAR-06 |
| `ingestion_review_genConfirm` | تمام | Confirm | B |
| `ingestion_review_genEdit` | عدّل | Edit | B · opens S-13 prefilled |
| `ingestion_review_genDismiss` | سيبها | Dismiss | B |
| `ingestion_review_requestBank` | اطلب دعم البنك ده | Ask us to support this bank | B · text (FR-PAR-14) |
| `ingestion_review_unreadTitle` | رسالة من {sender} مقدرتش أفهمها | A message from {sender} I couldn't read | L · FR-ING-A-06 |
| `ingestion_review_unreadShow` | شوف الرسالة | Show message | B · raw text on screen only |
| `ingestion_review_unreadEnter` | اكتب التفاصيل | Enter details | B · opens S-13 with `transactions_edit_rawTitle` |
| `ingestion_review_xferTitle` | {amount} في {card}، تبع أنهي تحويلة؟ | {amount} into {card} — which transfer was it? | L · BR-XFR-02 / EC-16 |
| `ingestion_review_xferOption` | {amount} من {card} · {time} | {amount} from {card} · {time} | L · radio |
| `ingestion_review_xferNotMine` | مش تحويلة مني | Not my transfer | L · radio |
| `ingestion_review_swipeAcceptA11y` | وافق على الاقتراح | Accept suggestion | A · swipe from the start edge; the button is always visible |
| `ingestion_review_swipeDismissA11y` | سيبها | Dismiss | A · swipe from the end edge, with undo |
| `ingestion_review_dismissed` | اتشالت من المراجعة | Removed from review | N + `common_action_undo` |
| `ingestion_review_emptyTitle` | كله تمام! مفيش حاجة مستنية رأيك ✨ | All clear! Nothing to review ✨ | T · C-28, Rive `proud` |
| `ingestion_alwaysSender_title` | أقرا رسايل {sender} على طول؟ | Always capture messages from {sender}? | T · A-66 sheet, after confirming a generic parse |
| `ingestion_alwaysSender_body` | `{count, plural, =1{هتفضل توصلك هنا للمراجعة لحد ما تأكد رسالة واحدة منه، وبعد كده هسجلها لوحدي.} =2{هتفضل توصلك هنا للمراجعة لحد ما تأكد رسالتين منه، وبعد كده هسجلها لوحدي.} few{هتفضل توصلك هنا للمراجعة لحد ما تأكد {n} رسايل منه، وبعد كده هسجلها لوحدي.} many{هتفضل توصلك هنا للمراجعة لحد ما تأكد {n} رسالة منه، وبعد كده هسجلها لوحدي.} other{هتفضل توصلك هنا للمراجعة لحد ما تأكد {n} رسالة منه، وبعد كده هسجلها لوحدي.}}` | `{count, plural, =1{They'll still come here for review until you've confirmed 1, then I'll log them myself.} other{They'll still come here for review until you've confirmed {n}, then I'll log them myself.}}` | S · count:int = remaining confirmations (A-66: 3), n |
| `ingestion_alwaysSender_yes` | أيوه، على طول | Yes, always | B |
| `ingestion_requestBank_title` | اطلب دعم بنكك | Request your bank | T · shared by S-14 and S-61 |
| `ingestion_requestBank_name` | اسم البنك | Bank name | L · prefilled with the sender in S-14 |
| `ingestion_requestBank_country` | البلد | Country | L |
| `ingestion_requestBank_channel` | تنبيهاته بتوصل إزاي؟ | How do its alerts arrive? | L · options `common_source_sms` / `common_source_notification` |
| `ingestion_requestBank_privacy` | هنبعت اسم البنك وبلده ونوع التنبيه بس. عمرنا ما هنبعت الرسالة نفسها. | We send only the bank's name, country and alert type — never the message itself. | S · FR-PAR-14 / BR-SYNC-03 (SRS adds the channel, see Q-09) |
| `ingestion_requestBank_send` | ابعت | Send | B |
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
| `transfers_split_shareA11y` | نصيب {name} | {name}'s share | A |
| `transfers_split_equal` | قسّم بالتساوي | Split evenly | B · this is the default |
| `transfers_split_paidBack` | رجع | Paid back | C · status |
| `transfers_split_waiting` | مستني | Waiting | C · status (FR-XFR-05) |
| `transfers_split_paidDetail` | {amount} · {source} · {date} | {amount} · {source} · {date} | L |
| `transfers_split_yourShare` | دفعت إنت فعلاً | Your share | L · glossary «دفعت إنت فعلاً» (BR-XFR-04) |
| `transfers_split_suggestions` | اقتراحات | Suggestions | L |
| `transfers_split_suggestion` | {amount} من {person} · {date}، من العزومة دي؟ | {amount} from {person} · {date} — from this bill? | S · + `common_action_link`; never auto (FR-XFR-08) |
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
| `transfers_link_afterMinutes` | `{count, plural, =1{بعدها بدقيقة} =2{بعدها بدقيقتين} few{بعدها بـ {n} دقايق} many{بعدها بـ {n} دقيقة} other{بعدها بـ {n} دقيقة}}` | `{count, plural, =1{1 min later} other{{n} min later}}` | C · count:int, n |
| `transfers_link_beforeMinutes` | `{count, plural, =1{قبلها بدقيقة} =2{قبلها بدقيقتين} few{قبلها بـ {n} دقايق} many{قبلها بـ {n} دقيقة} other{قبلها بـ {n} دقيقة}}` | `{count, plural, =1{1 min earlier} other{{n} min earlier}}` | C |
| `transfers_link_afterDays` | `{count, plural, =1{بعدها بيوم} =2{بعدها بيومين} few{بعدها بـ {n} أيام} many{بعدها بـ {n} يوم} other{بعدها بـ {n} يوم}}` | `{count, plural, =1{1 day later} other{{n} days later}}` | C |
| `transfers_link_beforeDays` | `{count, plural, =1{قبلها بيوم} =2{قبلها بيومين} few{قبلها بـ {n} أيام} many{قبلها بـ {n} يوم} other{قبلها بـ {n} يوم}}` | `{count, plural, =1{1 day earlier} other{{n} days earlier}}` | C |
| `transfers_link_impliedRate` | سعر التحويل ≈ {rate} لكل {fromCurrency} | Implied rate ≈ {rate} per {fromCurrency} | L · cross-currency (A-61); rate includes the target currency |
| `transfers_link_link` | اربط | Link | B |
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
| `accounts_overview_compare` | قارن | Compare | B · text, opens S-42 |
| `accounts_overview_asOf` | آخر تحديث {when} | as of {when} | C · when = `common_date_minutesAgo` or a date (FR-ACC-02) |
| `accounts_overview_creditAvailable` | متاح من {limit} | available of {limit} | C |
| `accounts_overview_moreCurrencies` | `{count, plural, =1{وكمان عملة واحدة} =2{وكمان عملتين} few{وكمان {n} عملات} many{وكمان {n} عملة} other{وكمان {n} عملة}}` | `{count, plural, =1{+1 more currency} other{+{n} more currencies}}` | C · count:int, n · multi-currency row (FR-ACC-06) |
| `accounts_overview_cashSub` | يدوي وصوت | Manual & voice | C |
| `accounts_overview_notTracked` | مش متتبع | Not tracked | C · ignored card (C-07) |
| `accounts_overview_assetsTitle` | دهبك وشهاداتك | Your assets | L · glossary, + `common_gold_badge` |
| `accounts_overview_prices` | الأسعار | Prices | B · text, opens S-45 |
| `accounts_overview_assetsLocked` | تابع دهبك وشهاداتك وكل أصولك في مكان واحد | Track your gold, certificates and more in one place | S · locked preview + `common_gold_unlock` |
| `accounts_overview_zakah` | الزكاة | Zakah | L · only when the `zakah` flag is on |
| `accounts_overview_emptyTitle` | الحسابات بتظهر لوحدها من رسايل البنك | Accounts show up by themselves from your bank messages | T · C-28, Rive `sleep` |
| `accounts_overview_emptyAdd` | ضيف حساب بإيدك | Add one yourself | B |
| `accounts_addType_title` | تضيف إيه؟ | What are you adding? | T · sheet |
| `accounts_addType_info` | الكروت بتتضاف لوحدها أول ما توصل رسالة. ضيف بإيدك لو لسه مفيش رسايل. | Cards are added automatically when a message arrives. Add one yourself if none has come yet. | S |
| `accounts_addType_credit` | كريدت كارد | Credit card | L |
| `accounts_addType_creditSub` | الليميت وميعاد السداد | Limit and due date | S |
| `accounts_addType_debit` | كارت ديبت / حساب بنك | Debit card / bank account | L |
| `accounts_addType_debitSub` | مرتب ومصاريف | Salary and spending | S |
| `accounts_addType_wallet` | محفظة | Wallet | L |
| `accounts_addType_walletSub` | فودافون كاش، إنستاباي، فوري | Vodafone Cash, InstaPay, Fawry | S · examples, see Q-10 |
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
| `accounts_detail_limitUsed` | مستخدم {percent} من الليميت | {percent} of your limit used | C |
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
| `accounts_detail_menuHide` | اخفي الحساب | Hide account | L · see Q-11 |
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
| `accounts_edit_bankAuto` | اتعرف من الرسايل | Detected from messages | C · read-only when auto-created |
| `accounts_edit_last4` | آخر أربع أرقام | Last four digits | L · LTR input, Western digits shown |
| `accounts_edit_last4Hint` | في الرسالة بيبان كده: «{sample}»، عشان زغلول يعرف الكارت. | In messages it looks like "{sample}" — that's how Zaghlol spots the card. | S · sample = a synthetic pattern from the institution template, e.g. `**1234` (never a real SMS) |
| `accounts_edit_type` | النوع | Type | L · `common_accountType_*` |
| `accounts_edit_currency` | العملة | Currency | L |
| `accounts_edit_balances` | الأرصدة | Balances | L · multi-currency |
| `accounts_edit_addCurrency` | ضيف عملة | Add currency | B |
| `accounts_edit_limit` | الليميت | Credit limit | L · credit only, ≥ 0 |
| `accounts_edit_dueDay` | يوم السداد | Statement due day | L · credit only, 1–31 |
| `accounts_edit_dueReminder` | `{count, plural, =0{هفكرك يوم السداد نفسه.} =1{هفكرك قبل ميعاد السداد بيوم.} =2{هفكرك قبل ميعاد السداد بيومين.} few{هفكرك قبل ميعاد السداد بـ {n} أيام.} many{هفكرك قبل ميعاد السداد بـ {n} يوم.} other{هفكرك قبل ميعاد السداد بـ {n} يوم.}}` | `{count, plural, =0{I'll remind you on the due day.} =1{I'll remind you 1 day before it's due.} other{I'll remind you {n} days before it's due.}}` | S · count:int (default 3, BR-SUB-03), n |
| `accounts_edit_captureTitle` | زغلول يقرا إيه من الكارت ده؟ | What should Zaghlol read for this card? | L · create mode inline toggles (`common_channel_*`) |
| `accounts_edit_captureLink` | زغلول بيقرا إيه | What Zaghlol reads | L · edit mode, opens S-62 |
| `accounts_edit_merge` | ادمجه مع كارت تاني | Merge with another card | L |
| `accounts_edit_hide` | اخفي الحساب ده | Hide this account | L · switch |
| `accounts_edit_hideHint` | مش هيظهر في قايمة الكروت | It won't appear in your card list | S · see Q-11 |
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
| `capture_settings_on` | شغال | On | C |
| `capture_settings_off` | مقفول | Off | C · + `common_action_fix` when a permission is revoked |
| `capture_settings_smsIos` | عن طريق الاختصارات | Via Shortcuts | C · iOS SMS row subtitle |
| `capture_settings_checkSetup` | اتأكد من الإعداد | Check setup | B · iOS, opens S-03 step 2 |
| `capture_settings_share` | ابعت أو الزق رسالة | Share or paste a message | L · opens `capture_shareHow_*` |
| `capture_settings_notTracked` | مش متتبعين | Not tracked | L · section (FR-CAP-06) |
| `capture_settings_notTrackedEmpty` | كل كروتك متتبعة | All your cards are tracked | S |
| `capture_settings_ignoredChannels` | {channels} مقفولة | {channels} off | C · channels = list of `common_channel_*Short` joined by the locale's list format. Row title = card or bank. + `common_action_undo` |
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
| `capture_ignore_privacy` | اللي تقفله، زغلول مش هيبص عليه خالص ولا هيحفظ منه حاجة. | Whatever you switch off, Zaghlol won't look at or save — at all. | S · BR-CAP-01 |
| `capture_ignore_errorBank` | اختار البنك | Choose the bank | S |
| `capture_ignore_errorChannel` | اختار مصدر واحد على الأقل | Pick at least one source | S |
| `capture_ignore_errorLast4` | سيبه فاضي أو اكتب أربع أرقام | Leave it empty or enter four digits | S |
| `capture_ignore_saved` | تمام، مش هتابعه | Done — no longer tracking it | N + `common_action_undo` |
| `capture_rescan_title` | دوّر في الرسايل القديمة | Re-scan old messages | T · FR-CAP-07 |
| `capture_rescan_depth` | لحد إمتى؟ | How far back? | L · options `common_period_lastMonths` 6–24 (A-11) |
| `capture_rescan_start` | ابدأ | Start | B |
| `capture_rescan_running` | `{count, plural, =0{بدوّر…} =1{بدوّر… لقيت حركة جديدة} =2{بدوّر… لقيت حركتين جداد} few{بدوّر… لقيت {n} حركات جديدة} many{بدوّر… لقيت {n} حركة جديدة} other{بدوّر… لقيت {n} حركة جديدة}}` | `{count, plural, =0{Searching…} =1{Searching… 1 new found} other{Searching… {n} new found}}` | L · Rive `scanning`, C-27 with cancel |
| `capture_rescan_done` | `{count, plural, =0{ملقيتش حركات جديدة ✓} =1{ضفت حركة جديدة ✓} =2{ضفت حركتين جداد ✓} few{ضفت {n} حركات جديدة ✓} many{ضفت {n} حركة جديدة ✓} other{ضفت {n} حركة جديدة ✓}}` | `{count, plural, =0{No new transactions ✓} =1{Added 1 new transaction ✓} other{Added {n} new transactions ✓}}` | N |
| `capture_rescan_noDuplicates` | اللي اتسجل قبل كده مش هيتكرر | Nothing already saved will be added twice | S |
| `capture_rescanOffer_title` | أدوّر في الرسايل القديمة على حركات {card}؟ | Look through old messages for {card}? | T · after un-ignoring (Android) |
| `capture_rescanOffer_body` | الرسايل اللي اتقفلت قبل كده متحفظتش، بس ممكن ألاقيها لسه في صندوق الرسايل. | Messages were not saved while it was off, but they may still be in your inbox. | S · BR-CAP-04 |
| `capture_rescanOffer_yes` | دوّر | Search | B |
| `capture_banks_title` | البنوك اللي زغلول بيفهمها | Supported banks | T |
| `capture_banks_search` | دوّر على بنك… | Search banks… | L |
| `capture_banks_noResults` | مفيش بنك بالاسم ده | No bank by that name | S · + `capture_settings_requestBank` |
| `capture_banks_iosNote` | على الآيفون، {bank} بيتسجل من Apple Pay والسكرين شوت وكشوف الحساب. الآيفون مش بيسمح لزغلول يقرا إشعارات التطبيقات التانية. | On iPhone, {bank} is tracked through Apple Pay, screenshots and statements. iOS doesn't let Zaghlol read other apps' notifications. | S · FR-ING-I-08 |
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
| `capture_cardControls_smsIos` | عن طريق اختصارات الآيفون | Through iPhone Shortcuts | C |
| `capture_cardControls_applePaySub` | الدفع بالموبايل | Phone payments | C |
| `capture_cardControls_info` | اللي تقفله، زغلول مش هيبص عليه خالص ولا هيحفظ منه حاجة. | Whatever you switch off, Zaghlol won't look at or save — at all. | S · BR-CAP-01 |
| `capture_stopTracking_title` | تبطّل تتابع {card}؟ | Stop tracking {card}? | T · last channel switched off (FR-CAP-04). Serious, no emoji |
| `capture_stopTracking_existing` | الحركات اللي اتسجلت قبل كده: | Transactions already saved: | L |
| `capture_stopTracking_keep` | سيبهم زي ما هم | Keep them | L · radio, default |
| `capture_stopTracking_delete` | `{count, plural, =1{امسح حركة واحدة} =2{امسح الحركتين} few{امسح الـ {n} حركات} many{امسح الـ {n} حركة} other{امسح الـ {n} حركة}}` | `{count, plural, =1{Delete 1 transaction} other{Delete {n} transactions}}` | L · radio; count:int, n |
| `capture_stopTracking_confirm` | بطّل المتابعة | Stop tracking | B |
| `capture_stopTracking_deleteTitle` | `{count, plural, =1{تمسح حركة واحدة نهائي؟} =2{تمسح الحركتين نهائي؟} few{تمسح {n} حركات نهائي؟} many{تمسح {n} حركة نهائي؟} other{تمسح {n} حركة نهائي؟}}` | `{count, plural, =1{Delete 1 transaction for good?} other{Delete {n} transactions for good?}}` | T · second confirmation |
| `capture_stopTracking_deleteBody` | مفيش رجوع. الحركات دي هتتمسح من الموبايل وكل الأرقام هتتحدث. | This can't be undone. These transactions will be deleted from this phone and every total will update. | S |
| `capture_stopTracking_deleteConfirm` | امسح نهائي | Delete for good | B · destructive |
| `capture_stopTracking_done` | مش هتابع {card} تاني | No longer tracking {card} | N + `common_action_undo` (restores the switches only; deleted data stays deleted) |

---

## 1.K Key count (Part 1)
| Section | Screens | Keys |
|---|---|---|
| 1.1 `common_*` | shared | 123 |
| 1.2 `mascot_*` | shared | 13 |
| 1.3 Welcome | S-01 | 10 |
| 1.4 Android setup | S-02 | 29 |
| 1.5 iOS setup | S-03 | 41 |
| 1.6 Restore | S-04 | 29 |
| 1.7 App lock | S-05 | 7 |
| 1.8 Scan results | S-06 | 14 |
| 1.9 Home | S-10 | 57 |
| 1.10 Transaction row | C-05 | 10 |
| 1.11 Transactions | S-11 | 28 |
| 1.12 Detail + rule sheet | S-12 | 41 |
| 1.13 Add / edit | S-13 | 20 |
| 1.14 Review queue + request bank | S-14 | 45 |
| 1.15 Split & reimbursements | S-15 | 26 |
| 1.16 Link transfer | S-16 | 16 |
| 1.17 Money overview + add flow | S-40, S-43 create | 47 |
| 1.18 Card detail | S-41 | 21 |
| 1.19 Compare | S-42 | 7 |
| 1.20 Edit card + merge | S-43 | 33 |
| 1.21 Capture settings | S-61 | 45 |
| 1.22 Card capture controls | S-62 | 14 |
| **Total** | | **676** |

Plural messages: 35. Select messages: 8. Each row is one ARB key in both `app_ar.arb` and `app_en.arb`.

## 1.Q Open questions and spec gaps (Part 1)
| ID | Where | Issue | Draft used | Needs |
|---|---|---|---|---|
| Q-01 | Tab 2 label | `03-navigation.md` says «التحليلات»; the glossary (D-34) says «الحسبة». | «الحسبة» | Confirm the glossary wins and update `03-navigation.md` |
| Q-02 | Source badge | FR-TXN-03's source list has no value for share/paste (FR-ING-A-04). | `common_source_shared` «رسالة اتبعتت» | Confirm a separate source value, or reuse SMS / Notification |
| Q-03 | S-02 | No screen spec covers the build without the Play SMS exception (FR-ING-A-05 "not granted by Play"). | `onboarding_androidSetup_playUnavailable` | Confirm the state exists (a store flavour without SMS?) and whether S-02 step 1 is skipped there |
| Q-04 | S-03, share how-to | iOS and Android OS labels ("Shortcuts", "Automation", "Run Immediately", "Share") differ by device language and OEM. | English OS labels kept in Latin | Verify on Arabic-language iOS; decide whether to show localized OS labels |
| Q-05 | Home greeting | Spec gives only «صباح الفل / مساء الفل» by time. Hour boundaries and the English afternoon form aren't defined. | Morning 05–12, afternoon 12–17, evening 17–05 | Confirm the boundaries |
| Q-06 | Home hero | No spec state for safe-to-spend ≤ 0 (budget used up). | `home_hero_budgetUsedUp` (calm, no joke) | Confirm the state and its copy |
| Q-07 | Payday prompt | A salary detected on day 29–31 can't be set (payday is 1–28, BR-BUD-01). | Not handled | Decide: suggest 28, use calendar month, or skip the prompt |
| Q-08 | S-11 bulk delete | The spec says every bulk change shows Undo, but bulk delete says it can't be undone. | Delete: confirmation, no Undo. Other bulk changes: Undo | Confirm |
| Q-09 | S-14 request bank | The screen spec says "only the bank's name and country"; FR-PAR-14 also sends the channel type. | The SRS (name, country, alert type) | Update the S-14 spec text |
| Q-10 | Add type sheet | The mockup lists InstaPay as a wallet example; InstaPay is a transfer rail, not a wallet. | Kept as mocked | Confirm the examples (and that brand names are cleared, OQ-09) |
| Q-11 | S-41/S-43 Hide | It isn't specified whether a hidden account's transactions still count in totals (FR-ACC-04). | Hint says only "won't appear in your card list" | Define what hiding does |
| Q-12 | S-43 Merge | Whether a merge can be undone isn't specified. | No undo claimed, no "can't undo" claimed | Decide: Undo snackbar, or a "can't be undone" line |
| Q-13 | C-05 | The design system lists a "pending verification" row variant but no spec defines it for transactions. | No copy | Define or remove the variant |
| Q-14 | Process | The task asks for the design note in the task file, but the brief limited edits to `copy-deck.md`. | Design note in §1.0 | Lead to copy it into `T-026.md` if wanted |
| Q-15 | Plural/digits convention | §0.3/§0.4 make every number a pre-formatted String and use `count` only to select. That needs the architect to confirm it against `DigitsMode` (ADR-017). | As written | Architect confirmation before T-029 |
| Q-16 | Bidi isolates | §0.6 puts FSI/PDI wrapping in the presentation layer, not in ARB text. | As written | Architect confirmation (`MoneyFormat` / l10n helper) |

## 1.C Changelog (Part 1)
- 2026-11-07 — first draft (T-026).

<!-- ===================== PART 2 (T-027) appends below ===================== -->

<!-- ===================== PART 3 (T-028) appends below ===================== -->
