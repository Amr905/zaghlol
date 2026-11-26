# Multi-currency, hybrid design: screen plan (D-86)

| | |
|---|---|
| Decision | D-86 (PO, 2026-11-26): option C "Hybrid" from `multi-currency-options.md` |
| Status | **IN BUILD (slice 2)** — slice 1 merged (batch 78); slice 2 built on the Lead assumptions Q1–Q4 pending the PO |
| Fixed rules | CLAUDE.md §2.4, D-28, D-29, D-81, D-82, D-84, D-85; FR-CUR-*, FR-TXN-04, FR-PAR-12 |

**In one line:** EGP stays the main view. Each other currency you actually use gets a small card that opens its own view. One optional "≈ total in EGP" line gives the whole picture and always says it is approximate. Stored amounts never change.

---

## 1. What the user sees, screen by screen

"Today" means what is in `main` now (Home `home_read_model.dart`, Money `money_tab.dart`, the ≈ service `wealth/domain/approx_view.dart`, charts `charts_providers.dart`, the `transfer_pairs` table).

| Screen | Today | With the hybrid design |
|---|---|---|
| **Home (S-10)** | Each currency with activity or a budget this month gets a **full page of its own**. You switch pages with chips (EGP, USD) and dots. Home has no ≈ line. A user with only EGP sees no currency UI. | The **EGP page is always the main page**, with the same hero (safe to spend, income, spent, left). Under it is a row of **small currency cards**, e.g. `USD ٤٠٠٫٠٠ · فاضل`. Under the cards is the **≈ total line** (optional). A user with only EGP still sees no currency UI. |
| **Currency cards (new)** | — | A currency gets a card if it **had any activity this month** (spending, income or an exchange) **or has a non-zero balance** on any account. Each card shows the currency, what is left in it, and this month's in/out. Cards are ordered by most recent activity. If there are more than 3, a `+٢` chip opens the rest. Tapping a card opens that currency's view. |
| **Per-currency view (new screen, reuses the Home page)** | That currency's full page on Home. | It opens from the card. It has the same layout as Home in that currency: hero, income/spent/left, its own feed and its own budget if one exists. It never shows another currency's numbers. |
| **"≈ total in EGP" line** | Exists only on the Money tab (net worth), off by default (A-54). | Home shows **one line**: `≈ ٤٩٬٥٤٠ ج.م دخلك كله تقريباً`, with the rate date under it. It is **always** marked "≈" and "تقريبي". **Hidden** if any currency on screen has no rate. Hidden when the setting is off. Tapping it opens a sheet that shows each currency, the rate used and where the rate came from. |
| **Month / Budget (S-22)** | Budgets are per currency (FR-BUD-02). Each budget counts only its own currency. | Same, plus: the **EGP month grows by the EGP you actually received** when you exchange (see §2). A currency with real activity this month gets a small offer: «تعمل ميزانية بالدولار؟». No currency gets a budget unless the user says yes. |
| **Transactions (S-11)** | Mixed currencies in one list, each row in its own currency. Day headers show one total per currency. | Same list. An exchange shows as **one row with both legs**: `غيّرت ٦٠٠ USD ← ٢٩٬٧٠٠ ج.م` with the bank's rate under it. It is labelled "not spending". A currency card filters the list to that currency. |
| **Money / accounts (S-40)** | Net worth is shown per currency, never summed. The ≈ net-worth line appears when the setting is on (T-115). Accounts show their own currency. | No change in layout. The ≈ line uses the same rate rule as Home (§3). A multi-currency account (Wise, Revolut) keeps one balance per currency. |
| **Insights charts (S-20)** | Currency chips. Each chart uses one currency at a time. I found no ≈ option in the chart providers. | Same chips, **EGP first**. Exchanges are never counted as spending or income in any chart. The cash-flow chart shows "exchanged in" as its own colour in the EGP view. The ≈ chip stays off unless the setting is on, and it is labelled "تقريبي". |
| **Ask Zaghlol (S-50)** | Answers give one figure per currency (FR-CHAT-01). | Same, plus one new question: «غيّرت كام دولار الشهر ده؟», which answers in both currencies and gives the rate. An answer never adds currencies unless the user asks for "≈", and then it says it is approximate. |
| **Widgets (W-01)** | Safe to spend and days to payday. | Shows EGP figures plus a small `+USD` hint when other currency cards exist. Never shows a mixed sum. Hide-amounts rules still apply. |
| **Export (S-67)** | Currency code on every row. Amounts never converted (FR-EXP-07). | Same, plus a "pair" column so both legs of an exchange can be matched in Excel. No converted column. |

**Arabic money format:** Arabic-Indic digits by default, Western when the user chooses 123 (A-29). EGP is `ج.م` in figures and `جنيه` in sentences. Other currencies use the ISO code (`USD`), with `دولار` in sentences. In English: Western digits, `EGP 29,700`, `USD 400.00`. Each currency keeps its own decimals (KWD 3, JPY 0).

---

## 2. The salary-in-USD story, end to end

Ahmed's payday is the 24th. His three latest salaries came in USD on the 24th, so Zaghlol set his payday to 24 by itself (D-81, D-85, already built in T-271). A month that starts on 24 Nov is called **December** (D-82).

| Step | What happens | What Ahmed sees |
|---|---|---|
| 1. **24 Nov: salary USD 1,000 arrives** | It is stored as **income, category Salary, in USD**. Nothing is converted. It starts the December month. | A **USD card** appears on Home: `USD ١٬٠٠٠٫٠٠ دخل`. The EGP page does not change. The ≈ line (if on) reads `≈ ٤٩٬٦٠٠ ج.م دخلك كله تقريباً · سعر النهارده`, using the daily rate of 49.60. |
| 2. **26 Nov: he exchanges USD 600 → EGP at the bank** | The bank SMS gives both amounts: −USD 600, +EGP 29,700. They are saved as **one exchange (a transfer pair)**. The bank's rate is 29,700 ÷ 600 = **49.50**. | The transactions list shows one row: `غيّرت ٦٠٠ USD ← ٢٩٬٧٠٠ ج.م · سعر البنك ٤٩٫٥٠`, labelled "not spending". |
| 3. **The EGP month grows** (PO decision) | The **EGP 29,700 received** counts as EGP money for December. It is shown as "from your dollars", **not** as a second salary. | EGP page: income `٢٩٬٧٠٠ ج.م`, with «منهم ٢٩٬٧٠٠ ج.م من الدولار» under it. "Left" and "safe to spend" grow to match. |
| 4. **USD 400 stays on its card** | The USD side shows salary +1,000, exchanged −600, left **400**. The exchange is not USD spending. | The USD card reads `USD ٤٠٠٫٠٠ فاضل`. Tapping it opens the USD view with the salary and the exchange. |
| 5. **Nothing is counted twice** | In the ≈ line, the exchanged part counts **once, at the bank's real rate**, and only the USD still held uses the daily rate: 29,700 + (400 × 49.60 = 19,840) = **≈ 49,540**. The salary is income once, in USD. The exchange is never income, never spending. | `≈ ٤٩٬٥٤٠ ج.م دخلك كله تقريباً · سعر البنك + سعر ٢٦ نوفمبر`. Turn the ≈ line off and every combined number disappears. |

---

## 3. Rules in plain words

| Topic | Rule |
|---|---|
| **Which rate "≈" uses** | (1) For money you already exchanged: **the bank's own rate**, taken from the two amounts in the SMS. (2) For money still in its own currency: the **daily rate** from the Zaghlol server (FR-BE-04). It is marked "old rate" after 24 h. (3) If any currency on screen has **no rate at all, the ≈ line is hidden**. We never show a partial total. |
| **Budgets** | By default the budget is **in EGP** and counts only EGP. A currency with **real activity this month** can get its own budget, offered once and never created automatically. Foreign spending on an Egyptian card counts in EGP, the billed amount (BR-FX-03). |
| **Exchange** | An exchange is a **transfer pair**, never income and never spending. The EGP received adds to the EGP month. The foreign amount sent leaves that currency's card. Same-bank exchanges (Wise, Revolut, a bank "converted" SMS) are paired automatically (FR-PAR-12). Exchanges between two banks, or cash at an exchange office, are **suggested** and confirmed with one tap, or entered with "غيّرت عملة". |
| **Payday (D-81, D-85)** | A salary in any currency is salary income. The first salary of the calendar month sets the payday rule. A month that starts on day 21–28 is named after the next month (D-82). In Arabic the period is always **شهر**. |
| **What never happens** | No amount is converted when it is saved. No screen adds two currencies unless it shows "≈" and "تقريبي". The ≈ line never appears without a rate. A salary is never counted again when it is exchanged. Zaghlol never creates a foreign-currency budget by itself. |

---

## 4. What needs building

Packages 1–4 and 7 ship as **slice 1 without the server rate feed**: cards, the per-currency view and correct exchanges all work with no rates. Package 5 adds the ≈ line. It can start with bank rates only and gets complete with the feed.

| # | Work package | Size | Needs FX feed? | Order |
|---|---|---|---|---|
| WP-1 | **Exchange counted once, correctly.** An exchange pair (`fx_conversion` / `cross_currency`) stays out of spending and income. The EGP received is added to the EGP month as "from your dollars". The foreign amount sent lowers that currency's "left". Covers the domain plus tests for the §2 numbers. | M | No | 1 |
| WP-2 | **Home: EGP main + currency cards.** Replace the equal-pages pager with the EGP page and a card row. Card rule: activity this month or a non-zero balance. Order by recent activity, with a `+N` overflow. | M | No | 2 |
| WP-3 | **Per-currency view.** The card opens the existing per-currency page as its own screen: feed filtered to that currency, own budget, and the "budget in USD?" offer. | S | No | 3 |
| WP-4 | **"I exchanged money" and pairing.** A manual exchange entry from Add (sent amount + received amount, rate shown). A one-tap "is this your exchanged USD?" suggestion for cross-bank pairs. The exchange row in the list and in the detail screen. | M | No (the rate comes from the two amounts) | 4 |
| WP-5 | **≈ line on Home + rate sheet.** Reuse the T-115 service. Rate order: bank rate for exchanged money, then the daily feed. Hide the line when any rate is missing. Show the "old rate" label. The same rule applies to the Money ≈ net worth. | M | **Yes** (works partly with bank rates only) | 5 |
| WP-6 | **Insights, Ask, widget, export.** The "exchanged in" colour in cash flow, the Ask "how much did I exchange" question, the `+USD` hint on the widget, the pair column in export. | M | No | 6 |
| WP-7 | **Copy, accessibility, goldens.** AR/EN keys (samples below), screen-reader labels («تقريبي» is read aloud), ar/en light/dark goldens, RTL and 1.3× text checks. | S | No | with each package |
| WP-8 | **Doc updates.** SRS FR-HOME-01 (cards instead of swipeable pages), FR-CUR-04 and BR-FX-01 (bank rate first), FR-CUR-06 (exchange adds to the EGP month), A-54 (per Q2), and S-10 / S-22 / S-11 / S-40 specs. | S | No | 0 (first) |

---

## 5. Questions for the PO (each has a recommendation)

| # | Question | Recommended answer |
|---|---|---|
| Q1 | If you typed a **fixed EGP budget** (e.g. 25,000), should an exchange raise it too? | **No.** Exchanged EGP always adds to the month's money in and to "left". A budget you typed stays as you set it. Zaghlol offers once: «زوّد ميزانية الشهر بـ ٢٩٬٧٠٠؟». |
| Q2 | The ≈ line is **off by default** today (A-54). Should it turn on by itself when a second currency appears? | **Yes, once, with a notice:** the first time a second currency card appears, the ≈ line turns on with one Captain Zaghlol line and a "turn off" link. Users with only EGP never see it. |
| Q3 | What should the Home ≈ line add up: **money in** this month, or **what's left**? | **Money in** («دخلك كله تقريباً»). It tells the salary story clearly and doesn't move when you exchange. "Left" stays exact per currency. |
| Q4 | Exchanges **between two banks** or at an exchange office: pair them automatically or ask? | **Ask, one tap.** Only same-bank conversions pair automatically. Cross-bank exchanges are suggested when the amounts happen within 3 days (A-61), and never paired silently. |

---

## 6. Sample copy (Egyptian colloquial; the period is always شهر)

| Key | AR | EN | Max |
|---|---|---|---|
| `home.currencyCards.title` | فلوسك بعملات تانية | Other currencies | 24 |
| `home.currencyCard.left` | فاضل {amount} | {amount} left | 18 |
| `home.currencyCard.more` | +{count} | +{count} | 4 |
| `home.approx.line` | ≈ {amount} دخلك كله تقريباً | ≈ {amount} in, all currencies | 36 |
| `home.approx.rateNote` | سعر البنك + سعر {date} | Bank rate + rate of {date} | 32 |
| `home.approx.stale` | سعر قديم | Old rate | 10 |
| `home.approx.sheet.title` | الحسبة دي تقريبية | This total is approximate | 28 |
| `home.approx.sheet.body` | بنحسبها بسعر البنك للي غيّرته، وبسعر النهارده للباقي. فلوسك متسجلة بعملتها زي ما هي. | We use your bank's rate for what you exchanged and today's rate for the rest. Your money stays saved in its own currency. | 120 |
| `home.kpi.income.fromExchange` | منهم {amount} من الدولار | incl. {amount} from your USD | 30 |
| `currencyView.title` | الشهر ده بالـ{currency} | This month in {currency} | 24 |
| `budget.offer.foreign` | تعمل ميزانية بالـ{currency}؟ | Want a {currency} budget? | 28 |
| `budget.offer.raise` | زوّد ميزانية الشهر بـ {amount}؟ | Add {amount} to this month's budget? | 40 |
| `txn.exchange.title` | غيّرت {from} ← {to} | Exchanged {from} → {to} | 32 |
| `txn.exchange.rate` | سعر البنك {rate} · مش مصروف | Bank rate {rate} · not spending | 32 |
| `add.exchange.entry` | غيّرت عملة | I exchanged currency | 16 |
| `add.exchange.sent` / `.received` | دفعت / وصلني | You gave / You got | 12 |
| `pair.exchange.prompt` | دول الدولارات اللي غيّرتها؟ | Is this your exchanged USD? | 32 |
| `pair.exchange.yes` / `.no` | أيوه / لأ | Yes / No | 6 |
| `mascot.fx.firstForeign` (Captain, Proud coach) | قبضت بالدولار يا معلم! سايبهولك في كارته، ولما تحوّل هزوّد شهر الجنيه باللي وصلك بالظبط. | Paid in dollars! They stay on their own card. When you exchange, your EGP month grows by exactly what you got. | 110 |

The arrow `←` in the AR exchange title points from the sent currency to the received one in RTL. It mirrors to `→` in English. Amounts and ISO codes inside it stay LTR runs.
