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
| `transactions_detail_deleteTitle` | تمسح الحركة دي؟ | Delete this transaction?" | T · C-18 destructive |
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

<!-- PART 1 CONTINUES -->
