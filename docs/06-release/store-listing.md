# Store listing copy (ar + en, T-176 / T-177) — draft for PO review

Status: **Draft ready — PO review** (batch 54). Native Egyptian review per `06-voice-and-tone.md` §6 still applies (T-058 reviewer).

Rules applied: voice guide (`docs/02-design/06-voice-and-tone.md`): Egyptian colloquial, simple standard Arabic only for the legal line. Only claims that are true in code. **Privacy claim used:** "your financial data never leaves your phone" / «بياناتك المالية مبتسيبش موبايلك». The copy never says "no server" or "no internet" and names the server's jobs. No bank names or logos (OQ-09); **InstaPay** is named as a payment rail, as in the app (confirm under OQ-09). No price (OQ-11). No Zakah or Smart ROI (flags off). **No voice entry** claim (voice logger T-120 deferred; add it back when it ships). **No charts-tier claim** (CHARTS-FREE switch can move charts back to Gold). Emoji: none (store copy).

Limits checked by hand (characters, spaces included); recount after any edit.

## 1. Short fields

| Field | Limit | English | Len | Arabic | Len |
|---|---|---|---|---|---|
| Play title / App Store name | 30 | Zaghlol: Expense Tracker | 24 | زغلول - متابعة مصاريفك | 22 |
| Play short description | 80 | Spending tracked from bank alerts; your financial data never leaves your phone. | 79 | مصاريفك بتتسجل لوحدها من رسايل البنك، وبياناتك المالية مبتسيبش موبايلك. | 71 |
| App Store subtitle | 30 | Your spending, on your phone | 28 | مصاريفك على موبايلك وبس | 23 |
| App Store keywords | 100 | `budget,expenses,spending,money,egypt,EGP,InstaPay,wallet,salary,bills,savings,gold,finance,tracker` | 98 | `ميزانية,مصاريف,مصروف,فلوس,جنيه,مصر,محفظة,مرتب,فواتير,توفير,دهب,حسابات,ادخار` | 75 |
| App Store promotional text | 170 | Captain Zaghlol turns your bank messages into a clear picture and tells you what's safe to spend today. Your financial data never leaves your phone. | 148 | الكابتن زغلول بيحوّل رسايل البنك لصورة واضحة وبيقولك تقدر تصرف كام النهارده. وبياناتك المالية مبتسيبش موبايلك. | 98 |

Keywords: Apple already indexes the app name, so "Zaghlol" / «زغلول» are not repeated. Drop `InstaPay` if OQ-09 clearance says so (then 89 chars).

## 2. Google Play full description (Android)

The SMS paragraph is for the `prodSms` build only. If Google refuses the SMS declaration and `prodNoSms` ships, delete the paragraph marked **[SMS]** and keep the rest.

### English (about 1,750 characters)

```
Zaghlol logs your spending by itself and shows you where your money goes, in Egyptian Arabic or English. Your financial data never leaves your phone.

LOGS SPENDING FOR YOU
• [SMS] Reads transaction messages from banks, InstaPay, mobile wallets and instalment providers. It checks only the sender: messages from anyone else are ignored and never saved.
• Reads notifications from your bank and wallet apps (when you turn on notification access).
• Share a message, scan a receipt or import a statement, or add a transaction by hand.
• Not sure about a message? Zaghlol asks you instead of guessing.

KNOW WHERE YOU STAND
• Safe to spend today and what's left until payday.
• Budgets per category with calm alerts before you hit the limit.
• Bills, subscriptions and instalments, with reminders.
• Charts that explain your spending in plain words.
• Every card and account on its own, and every currency kept in its own currency.

CAPTAIN ZAGHLOL
A cheeky pigeon who cheers you on when you save and nudges you when delivery gets out of hand. Never about you, only about the spending.

PRIVATE BY DESIGN
• Your messages, transactions, balances and budgets are stored encrypted on your phone only.
• Zaghlol's server does only non-financial jobs: verifying Gold purchases, updating the merchant list, gold and exchange-rate prices, and feature switches. It never receives your messages or transactions.
• No ads, no analytics, no tracking.
• Settings show exactly what the server knows about you, and you can delete everything at any time.

ZAGHLOL GOLD (optional)
Export to CSV and Excel, import bank statements, automatic encrypted backups to your own Google Drive with five versions kept, gold, certificates and assets tracking, and your own categories and message templates. Free users get one encrypted backup.

Zaghlol is not a bank and doesn't give financial advice. It never asks for your bank password.
```

### Arabic (حوالي ١٤٠٠ حرف)

```
زغلول بيسجّل مصاريفك لوحده وبيوريك فلوسك بتروح فين، بالمصري أو بالإنجليزي. وبياناتك المالية مبتسيبش موبايلك.

بيسجّل عنك
• [SMS] بيقرا رسايل الحركات من البنوك وإنستاباي والمحافظ وشركات التقسيط. بيبص على المرسل بس: أي رسالة من حد تاني بيسيبها ومبيحفظهاش.
• بيقرا إشعارات تطبيقات البنك والمحفظة (لما تشغّل الوصول للإشعارات).
• شارك رسالة، أو صوّر إيصال، أو استورد كشف حساب، أو ضيف الحركة بإيدك.
• مش متأكد من رسالة؟ زغلول بيسألك بدل ما يخمّن.

اعرف إنت فين
• تقدر تصرف كام النهارده، وفاضلك قد إيه لحد القبض.
• ميزانية لكل تصنيف، وتنبيه هادي قبل ما توصل للحد.
• الفواتير والاشتراكات والأقساط، مع تفكير بميعادها.
• شارتات بتشرحلك صرفك بكلام بسيط.
• كل كارت وحساب لوحده، وكل عملة بعملتها.

الكابتن زغلول
حمامة دمها خفيف، بتشجعك لما توفّر وبتقرصك في ودنك لما الدليفري يزيد. الكلام دايماً على الصرف، مش عليك.

خصوصيتك الأول
• رسايلك وحركاتك وأرصدتك وميزانياتك متخزّنة مشفّرة على موبايلك بس.
• سيرفر زغلول بيعمل حاجات مش مالية بس: يتأكد من شراء جولد، ويحدّث قايمة التجار، ويجيب أسعار الدهب والعملات، ويشغّل المزايا. عمره ما بيستلم رسايلك ولا حركاتك.
• مفيش إعلانات ولا تحليلات ولا تتبّع.
• في الإعدادات تشوف بالظبط السيرفر يعرف إيه عنك، وتقدر تمسح كل حاجة في أي وقت.

زغلول جولد (اختياري)
تصدير لـ CSV وExcel، واستيراد كشوف البنوك، ونسخ احتياطي مشفّر تلقائي على Google Drive بتاعك بخمس نسخ محفوظة، ومتابعة الدهب والشهادات والأصول، وتصنيفات وقوالب رسايل خاصة بيك. المجاني فيه نسخة احتياطية مشفّرة واحدة.

زغلول مش بنك ومبيقدمش نصايح مالية، وعمره ما هيطلب منك باسورد البنك.
```

## 3. App Store description (iPhone)

### English (about 1,650 characters)

```
Zaghlol logs your spending and shows you where your money goes, in Egyptian Arabic or English. Your financial data never leaves your phone.

LOGS SPENDING FOR YOU
• Shortcuts automations: a short in-app guide sets up Messages and Wallet automations, so bank messages and Apple Pay payments reach Zaghlol by themselves.
• Share a message, scan a receipt or import a PDF statement, or add a transaction by hand.
• Not sure about a message? Zaghlol asks you instead of guessing.

KNOW WHERE YOU STAND
• Safe to spend today and what's left until payday.
• Budgets per category with calm alerts before you hit the limit.
• Bills, subscriptions and instalments, with reminders.
• Charts that explain your spending in plain words.
• Every card and account on its own, and every currency kept in its own currency.

CAPTAIN ZAGHLOL
A cheeky pigeon who cheers you on when you save and nudges you when delivery gets out of hand. Never about you, only about the spending.

PRIVATE BY DESIGN
• Your transactions, balances and budgets are stored encrypted on your iPhone only.
• Zaghlol's server does only non-financial jobs: verifying Gold purchases, updating the merchant list, gold and exchange-rate prices, and feature switches. It never receives your messages or transactions.
• No ads, no analytics, no tracking.
• Optional Face ID app lock.

ZAGHLOL GOLD (optional)
Export to CSV and Excel, import bank statements, automatic encrypted backups to your own iCloud with five versions kept, gold, certificates and assets tracking, and your own categories and message templates. Free users get one encrypted backup.

Gold is available monthly, yearly or as a one-time lifetime purchase. The subscription renews automatically unless cancelled before the period ends, in your Apple account settings.

Terms: https://zaghlol.app/terms
Privacy: https://zaghlol.app/privacy
```

### Arabic

```
زغلول بيسجّل مصاريفك وبيوريك فلوسك بتروح فين، بالمصري أو بالإنجليزي. وبياناتك المالية مبتسيبش موبايلك.

بيسجّل عنك
• أتمتة الاختصارات: دليل قصير في التطبيق بيظبطلك أتمتة للرسايل وللمحفظة، فرسايل البنك ومدفوعات Apple Pay توصل لزغلول لوحدها.
• شارك رسالة، أو صوّر إيصال، أو استورد كشف PDF، أو ضيف الحركة بإيدك.
• مش متأكد من رسالة؟ زغلول بيسألك بدل ما يخمّن.

اعرف إنت فين
• تقدر تصرف كام النهارده، وفاضلك قد إيه لحد القبض.
• ميزانية لكل تصنيف، وتنبيه هادي قبل ما توصل للحد.
• الفواتير والاشتراكات والأقساط، مع تفكير بميعادها.
• شارتات بتشرحلك صرفك بكلام بسيط.
• كل كارت وحساب لوحده، وكل عملة بعملتها.

الكابتن زغلول
حمامة دمها خفيف، بتشجعك لما توفّر وبتقرصك في ودنك لما الدليفري يزيد. الكلام دايماً على الصرف، مش عليك.

خصوصيتك الأول
• حركاتك وأرصدتك وميزانياتك متخزّنة مشفّرة على الآيفون بتاعك بس.
• سيرفر زغلول بيعمل حاجات مش مالية بس: يتأكد من شراء جولد، ويحدّث قايمة التجار، ويجيب أسعار الدهب والعملات، ويشغّل المزايا. عمره ما بيستلم رسايلك ولا حركاتك.
• مفيش إعلانات ولا تحليلات ولا تتبّع.
• قفل اختياري بـ Face ID.

زغلول جولد (اختياري)
تصدير لـ CSV وExcel، واستيراد كشوف البنوك، ونسخ احتياطي مشفّر تلقائي على iCloud بتاعك بخمس نسخ محفوظة، ومتابعة الدهب والشهادات والأصول، وتصنيفات وقوالب رسايل خاصة بيك. المجاني فيه نسخة احتياطية مشفّرة واحدة.

جولد متاح شهري أو سنوي أو مدى الحياة بدفعة واحدة. يتجدد الاشتراك تلقائياً ما لم يُلغَ قبل نهاية الفترة من إعدادات حساب Apple.

الشروط: https://zaghlol.app/terms
الخصوصية: https://zaghlol.app/privacy
```

The renewal line is `gold_paywall_renewal` (simple standard Arabic, legal sign-off pending Q-36). Apple requires the Terms (EULA) and Privacy links in the description or the EULA field for auto-renewable subscriptions.

## 4. Other listing fields

| Field | Value |
|---|---|
| Category | Finance / مالية |
| Support URL | https://zaghlol.app/support/ |
| Privacy policy URL | https://zaghlol.app/privacy/ |
| Marketing URL (Apple, optional) | https://zaghlol.app/ |
| Contact e-mail (Play, public) | `{{SUPPORT_EMAIL}}` |
| Age rating | Answer the questionnaires; no user-generated public content, no gambling, no ads |
| Play: ads | No ads |
| Play: target audience | 18+ (not for children) — confirm with `{{MIN_AGE}}` in the privacy policy |
| Play: financial features | Personal finance management only; no loans, no crypto, no payments |
| Play: Data safety | `play-data-safety.md` (fix the contradictions listed in PO_DECISIONS FU-195-legal first) |
| Play: SMS declaration | `play-sms-declaration.md` |
| Apple: App Privacy, review notes | `app-store-privacy.md` |

## 5. Screenshot shot list

Capture from the golden-tested screens with **synthetic data only** (no real names, card digits or messages; EGP amounts; institutions shown as generic sample banks until OQ-09 clears names and logos; the D-74 acronym badges also count as bank names). Light theme (DESIGN-0 default). Arabic set: Arabic UI, RTL, Arabic-Indic digits. English set: English UI, LTR. Sizes: App Store 6.9" (1320×2868) and 6.5" (1284×2778); Play phone (1080×1920 or larger, 9:16) plus 7" and 10" tablet. Caption above the phone frame, apricot accent on mint background (brand tokens, CLAUDE.md §8).

| # | Screen (spec) | Platform | Caption (ar) | Caption (en) |
|---|---|---|---|---|
| 1 | Home: safe-to-spend hero + Captain Zaghlol banner (S-10) | both | اعرف تقدر تصرف كام النهارده | Know what's safe to spend today |
| 2 | Transactions list with auto-captured rows and source badges (S-11) | both | مصاريفك بتتسجل لوحدها | Your spending, logged by itself |
| 3 | Review queue card ("needs your review") (S-14) | both | مش متأكد؟ زغلول بيسألك | Not sure? Zaghlol asks you |
| 4 | Insights: category donut with the explanation bubble (S-20/S-21) | both | شوف فلوسك راحت فين | See where your money went |
| 5 | Budgets with progress and alert (S-22) | both | ميزانية من غير وجع دماغ | Budgets without the headache |
| 6 | Bills and instalments (S-24) | both | فواتيرك وأقساطك في ميعادها | Bills and instalments on time |
| 7 | Privacy: "What Zaghlol's server knows" (S-71) | both | بياناتك المالية مبتسيبش موبايلك | Your financial data never leaves your phone |
| 8a | Capture settings: SMS + notifications on (S-61) | Android | بيقرا رسايل البنك بس، وبيسيب الباقي | Reads bank messages only, ignores the rest |
| 8b | iOS setup guide: Shortcuts automations (S-03) | iOS | ظبط الاختصارات مرة واحدة وخلاص | Set up Shortcuts once, and you're done |

Play `prodNoSms` build: replace 8a with the notification-access step and the caption «بيقرا إشعارات البنك على موبايلك» / "Reads bank notifications on your phone".
Feature graphic (Play, 1024×500): Captain Zaghlol holding coins (`docs/02-design/brand/`) with the short description line; no text over 15 % of the area.
