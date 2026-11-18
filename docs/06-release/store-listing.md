# Store listing skeleton (ar + en, T-176 / T-177)

Rules: copy comes from the voice guide (`docs/02-design/06-voice-and-tone.md`, Egyptian colloquial, standard Arabic only for legal text); no claim that is not true in code. **Allowed privacy claim:** "your financial data never leaves your phone". **Never** say "no server" or "no internet". No bank names or logos until trademark clearance (OQ-09). No price in the copy (OQ-11); no Zakah or Smart ROI mention while those flags are off. Final strings are UX-owned (placeholders below are structure, not copy). Character limits: Play title 30, short description 80, full 4000; App Store name 30, subtitle 30, promotional 170, keywords 100, description 4000.

| Slot | English skeleton | Arabic (Egyptian) skeleton |
|---|---|---|
| App name | Zaghlol | زغلول |
| Short description / subtitle | `{one line: tracks spending from your bank messages, on your phone}` | `{سطر واحد: بيتابع مصاريفك من رسايل البنك، على موبايلك}` |
| Opening paragraph | `{what it does: reads transaction messages and notifications, sorts spending, Captain Zaghlol coaches you}` | `{بيعمل إيه: بيقرا رسايل وإشعارات المعاملات، بيصنّف مصاريفك، والكابتن زغلول بيرشدك}` |
| Privacy paragraph | Your financial data never leaves your phone. It is stored encrypted on the device. | بياناتك المالية مبتسيبش موبايلك. متخزّنة مشفّرة على الجهاز. |
| What the server does | `{purchase verification, merchant catalog updates, gold and exchange-rate prices, feature flags}` | `{التأكد من الشراء، تحديث قايمة التجار، أسعار الدهب والعملات}` |
| Android SMS line (prodSms only) | `{reads only messages from known financial senders; ignores everything else}` | `{بيقرا بس رسايل الجهات المالية المعروفة، وبيتجاهل أي حاجة تانية}` |
| iOS input line | `{Shortcuts automations, share sheet, receipt scan, PDF, voice}` | `{أتمتة الاختصارات، المشاركة، مسح الإيصال، PDF، الصوت}` |
| Gold paragraph | `{what Gold unlocks: export, encrypted backup, all charts, wealth tracker; no prices here}` | `{اللي الدهب بيفتحه: التصدير، النسخ الاحتياطي المشفّر، كل الرسوم، متابعة الثروة}` |
| Subscription legal text | per `gold_paywall_renewal` (legal sign-off pending, Q-36) | نفس النص بعد المراجعة القانونية |
| Support / Privacy / Terms URLs | placeholders in `app/lib/app/app_config.dart` (FU-195) | same |
| Screenshots | 6.9" and 6.5" iPhone, phone + 7" / 10" tablet Play; ar (RTL) set and en set, from the golden-tested screens; no real data | same |
| Category | Finance | مالية |
| Age rating | answer questionnaire; no user-generated public content | |
| Keywords (App Store, en/ar) | `{budget, expenses, Egypt, EGP, InstaPay ...}` (words, not bank brand names until OQ-09) | `{ميزانية، مصاريف، مصر، جنيه}` |

Play-only: content rating, target audience (not for children), ads declaration: no ads, news / health / financial-features declaration (Play asks financial features: select "personal finance management", no loans or crypto), data safety (`play-data-safety.md`), SMS declaration (`play-sms-declaration.md`). Apple-only: App Privacy (`app-store-privacy.md`), review notes, export compliance.
