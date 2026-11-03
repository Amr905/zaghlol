# Zaghlol Spec v4 — Extracted Text

> Auto-extracted from `Zaghlol_Feature_and_Product_Specification_v4.docx` (repo root) for agent use. Table cells are flattened one-per-line. Images are in `spec-media/`. The .docx remains the source of truth.

Zaghlol زغلول (v3.0) — Complete Product Specification, 14 UI Screens, 8 Social Media Campaigns, 12 Charts & 38-Bank SMS Regex Lab100% On-Device Serverless Architecture 
• Full Extracted Content from Interactive Prototype & Specification
Specification Attribute
v3.0 Architectural Decision
Target Market & Scope
Implementation Standard
Project Title & Mascot
Zaghlol (زغلول) — 'Captain Zaghlol' Cartoon Pigeon Advisor
Egypt (EGP) — Bilingual (AR/EN + Egyptian Colloquial)
v3.0 Master Implementation Spec
Client Platform
Flutter 3.x (Android Broadcasts + iOS Shortcuts/AppIntents)
100% Serverless On-Device Execution (Zero Backend)
Zero Cloud Hosting Cost / 100% Offline
Database & Storage
Local Persistent Encrypted SQLite (Drift + SQLCipher)
On-Device Regex Engine + Seeded 600+ Merchant Map
FTS5 + Trigram/Jaro-Winkler Local Match
Monetization Model
Freemium + Zaghlol Gold (On-Device StoreKit 2 / Play Billing)
Paid Features: CSV Export/Import + Google Drive / iCloud Backup
Client-Side OAuth2 & AES-256 Backups
1. Brand Identity, Localization & 'Captain Zaghlol' Cartoon Mascot System
Zaghlol (زغلول) is an automated, 100% on-device personal finance and SMS expense analyzer built specifically for Egyptian consumers and households. Version 3.0 eliminates all backend servers (.NET Web APIs and PostgreSQL cloud databases are completely removed). Every regex parser, merchant normalizer, budget calculator, and chart explainer runs strictly on the user's phone.
- Official Brand Color Palette: Primary Dark Teal (#174C4F), Coin Gold (#F0B33A), Chart Green (#60B669), Sage Gray (#88A399), and Expense Rose (#F43F5E), with full Light Mode (#F8FAFC) and Dark Mode (#121E21) support.
- Full Bilingual & Colloquial Support: Supports English (LTR) and Arabic (RTL), with Captain Zaghlol delivering financial coaching and chart explanations in warm, easy Egyptian Arabic (عامية مصرية).
Figure 1: Captain Zaghlol (الكابتن زغلول) 4 Core Expressive Poses — (Top-Left) Tour Guide & Chart Explainer, (Top-Right) Proud Savings Coach, (Bottom-Left) Shocked Receipt Alert, (Bottom-Right) Subscription & Fee Detective.
Mascot State / Pose
Trigger Condition in App
UI Placement
Verbatim Egyptian Arabic Dialogue (عامية مصرية)
1. Tour Guide Zaghlol(زغلول المرشد)
First launch onboarding, SMS permission grant, & iOS Shortcut setup wizard.
Full-screen interactive walkthrough cards & tooltip bubbles.
«أهلاً بيك يا صاحبي! أنا زغلول، هلملك كل رسايل البنوك وإنستاباي في مكان واحد من غير ما تدخل باسورد ولا داتا تطلع بره تليفونك!»
2. Proud Coach Zaghlol(زغلول الفرحان)
User stays under daily safe burn rate, logs savings, or hits a monthly budget goal.
Dashboard hero header & Goal completion confetti modal.
«عاش يا وحش! إنت ماشي بالمسطرة الشهر ده، وفرت ٢,٤٠٠ جنيه زيادة عن الشهر اللي فات.. نشتري بيهم ربع جنيه دهب؟»
3. Shocked Zaghlol(زغلول المصدوم)
Category budget exceeds 85% before day 20, or dining/delivery spikes >30%.
Category warning banner & local push notification avatar.
«حاسب يا كبير! طلبات والأكل بره بلعوا ٣,٨٥٠ جنيه وإحنا لسه يوم ١٨ في الشهر.. إمسك إيدك شوية لأحسن نكمل الشهر فول وطعمية!»
4. Detective Zaghlol(زغلول المفتش)
Detects duplicate POS debit, forgotten subscription renewal, or self-transfer.
Subscription radar card & InstaPay self-transfer badge.
«قفشتك! فيه تحويلة ١,٠٠٠ جنيه من الأهلي لـ CIB بنفس المبلغ في دقيقتين.. حسبتها تحويلة داخلية عشان ميزانيتك متتظلمش!»
5. Chart Professor Zaghlol(زغلول شارح الشارتات)
User opens any of the 12 analytics charts or taps 'Explain This Chart' (اشرحلي يا زغلول).
Interactive speech bubble anchored directly below every chart.
«الشارت ده بيوريك فلوسك بتطير فين كل خميس وجمعة.. خروجة الويك إند لوحدها واخدة ٤٢٪ من مصروفك الأسبوعي!»
6. Voice Listener Zaghlol(زغلول بيسمعك)
User taps the microphone button to log a cash transaction via Egyptian Arabic voice.
Floating bottom sheet with animated soundwave wings.
«قولي دفعت كام وفي إيه وأنا هسجلها فوراً.. مثلاً قول: دفعت ١٥٠ جنيه خضار وفاكهة و ٤٠ جنيه تاكسي.»
2. Zero-Backend Architecture & 'Zaghlol Gold' Pay Model (CSV & Google Drive)
By running 100% locally on the phone, Zaghlol incurs zero server hosting costs. Core SMS tracking and budgeting are free for all users, while power features (CSV/Excel Export & Import, Encrypted Google Drive / iCloud Drive Auto-Backup, and Advanced Analytics) are monetized via on-device In-App Purchases:
Feature Dimension
Free Tier — Zaghlol Asaasy (زغلول أساسي)
Premium Tier — Zaghlol Gold (زغلول جولد)(49 EGP/mo 
• 399 EGP/yr 
• 899 EGP Lifetime)
On-Device SMS, Notification & Apple Pay Tracking
Unlimited automated local parsing across all 38 Egyptian banks, InstaPay, Wallets, and BNPLs.
Unlimited + Custom User Regex Builder for niche/corporate SMS senders.
Auto-Categorization & Manual Reclassification
14 pre-loaded categories, 600+ Egyptian merchant map, and manual single-transaction reclassification.
Unlimited custom categories/subcategories + 'Always Apply Rule' automated merchant mapping engine.
Export to CSV / Excel (تصدير CSV وإكسيل)
Locked (Preview table only; shows 'Upgrade to Zaghlol Gold' prompt).
Full UTF-8 BOM CSV & Excel (.xlsx) Export with custom date ranges, category filters, and Arabic encoding.
Import from CSV & Bank PDF Statements
Manual cash & voice entry supported (up to 15 voice logs/month).
Unlimited CSV Import/Restore + Local PDF Bank Statement Parser (CIB, NBE, QNB, Banque Misr) + Unlimited Voice.
Save to Google Drive & iCloud Drive (نسخ احتياطي سحابي)
Local on-device storage only (no cloud backup).
Automated (Daily/Weekly/Monthly) & 1-Tap Encrypted SQLite Backup (.zaghlol.enc) directly to user's Google Drive or iCloud Drive.
Analytics Charts & Egyptian Arabic Explanations
Core 4 charts (Monthly Cash Flow, Category Donut, Top 5 Merchants, Basic Budget Bar) + basic Zaghlol tips.
All 12 Interactive Charts (Burn-Rate Curve, Day/Hour Heatmap, BNPL Timeline, Subscription ×12 Radar, Price Creep) + Deep Zaghlol Coaching.
Net Worth, Gold (21K/24K) & Bank CDs Tracker
Tracks liquid bank cards, wallets, and cash balances.
Full Wealth Portfolio: Tracks 21K/24K Gold grams, Bank Certificates (شهادات ٢٧٪), Real Estate, and Multi-Currency (USD/SAR/EUR).
3. Competitor Benchmarking (Say & FinArt) & iOS Technical Deep-Dive
Capability / Dimension
Say App (sayapp.net)
FinArt App (finart.app)
Zaghlol v3.0 Strategy (How We Copy & Surpass Both)
Primary Ingestion Channels (Android)
Reads Bank SMS & App push notifications + Voice logging in Arabic/English.
Reads Bank SMS, App notifications, and transactional Emails.
Full Android BroadcastReceiver (READ_SMS, RECEIVE_SMS, NotificationListenerService) + Voice + Clipboard.
How It Works on iOS (Apple Sandbox)
Uses Apple Pay Wallet triggers, Shortcuts automation, and Voice logging (Arabic/English).
Combines 4 iOS channels: (1) Apple Pay tap capture, (2) Shared/Shortcut SMS, (3) Authorised Email alerts, (4) PDF Bank Statement import.
Implements a 5-Channel iOS Architecture: (1) Shortcuts 'When I get a message' + 'Transaction' silent automation, (2) ILMessageFilterExtension, (3) Action-Button/Back-Tap Screenshot OCR, (4) PDF Statement Import, (5) Egyptian Voice.
Privacy & Backend Model
Cloud account required; processes SMS momentarily to extract expense details.
Offers 'Private Mode' where data never leaves the phone; backups go to personal Google Drive / iCloud.
100% Private Mode by default for ALL users: Zero backend servers. Data never leaves the phone except to the user's own Google Drive/iCloud.
Voice Expense Entry (Cash Tracking)
Core feature: 'Just say it in English or Arabic' (e.g., 'vegetables 150').
Manual form entry; no Arabic colloquial voice parser.
Adopts Say's 1-sentence Egyptian Arabic Voice Logging ('قول لزغلول: دفعت ١٥٠ جنيه خضار و ٤٥ قهوة') using on-device speech recognition + local NLP.
Self-Transfer & Refund Intelligence
Auto-detects transfers between own accounts and nets refunds against original spend.
Supports manual transaction splitting across categories/people.
Combines both: Automatic InstaPay Self-Transfer pairing (<5 min window) + Refund offsetting + Friends Expense Splitting (شير وعزومات).
Wealth, Gold & Net Worth Tracking
Tracks Bank accounts, 21K/24K Gold & Silver by purity, Funds/Certificates, Apartment & Car.
Focuses on expenses, credit card bills, and monthly budgets.
Adopts Say's Net Worth & Egyptian Gold/Certificate tracker (21K/24K Gold grams, 27% Bank CDs, USD cash, Real Estate) inside the Wealth tab.
Conversational AI & Tone
'Ask your money anything' in AR/EN with in-chat charts + 'Ask it to roast you'.
Standard category trend reports and budget alerts.
Captain Zaghlol Cartoon Persona: Explains all 12 charts in witty Egyptian Arabic + 'إقصف جبهتي يا زغلول' (Roast My Spending) mode!
4. Categorization Architecture, User Rule Map & 14 Initial Categories
Zaghlol's 3-Tier local categorization engine checks: (Tier 1) User Custom Rules in 'UserMerchantRules', (Tier 2) 600+ Seeded Egyptian POS Mappings in 'CanonicalMerchants', and (Tier 3) Bilingual Keyword Heuristics + a 1-tap 'Needs Classification' swipe queue.
ID & Category (EN / AR)
Budget Bucket
Included Subcategories (AR / EN)
Pre-Mapped Egyptian Merchants & Keywords
Brand Color
1. Groceries & Supermarkets(خزين البيت والسوبرماركت)
Needs (أساسيات)
Supermarket (سوبرماركت), Vegetables & Fruit (خضار وفاكهة), Butcher & Poultry (لحوم ودواجن), Bakery & Dairy (مخبوزات وألبان), Quick Mart Delivery.
CARREFOUR, SPINNEYS, SEOUDI, GOURMET, KAZYON, BIM, FATHALLA, AWLAD RAGAB, HYPER ONE, TALABAT MART, BREADFAST, RABBIT, INSTASHOP.
#174C4F (Dark Teal)
2. Dining, Cafes & Delivery(أكل بره وكافيهات ودليفري)
Wants (رفاهيات)
Food Delivery (دليفري), Fast Food (فاست فود), Restaurants & Outings (مطاعم وعزومات), Coffee & Bakeries (قهوة وكافيهات), Street Food (فول وكشري).
TALABAT, ELMENUS, MCDONALDS, KFC, STARBUCKS, COSTA, TBS, CILANTRO, BUFFALO BURGER, HEART ATTACK, WAFFLE, ABOU TAREK, GAD, B.LABAN.
#F43F5E (Expense Rose)
3. Transport, Fuel & Rides(مواصلات وبنزين وعربية)
Needs (أساسيات)
Ride-Hailing (أوبر وكريم وإندرايف), Fuel & Gas Stations (بنزين), Car Maintenance & Spare Parts (صيانة وقطع غيار), Public Transit/Metro, Parking & Tolls.
UBER, CAREEM, INDRIVE, DIDI, CHILLOUT, WATANIYA, TOTAL PARCO, MOBIL, SHELL, EMARAT MISR, OLAYAN, SWVL, GOBUS, METRO.
#3B82F6 (Cobalt Blue)
4. Bills, Telecom & Utilities(فواتير وشحن ومرافق)
Needs (أساسيات)
Electricity (كهرباء), Home Internet & Landline (إنترنت أرضي), Mobile Recharge & Bills (شحن وفاتورة موبايل), Natural Gas (غاز), Water (مياه), Fawry Services.
WE EGYPT, TE DATA, VODAFONE, ORANGE, ETISALAT, E&, FAWRY, MYFAWRY, PETROTRADE, NATGAS, TAQA, Sahl, Khales.
#0EA5E9 (Sky Cyan)
5. Housing, Rent & Home(إيجار ومصاريف البيت)
Needs (أساسيات)
Monthly Rent (إيجار شهري), Compound Maintenance & Security (وديعة وصيانة وأمن), Home Appliances & Furniture (أثاث وأجهزة), Cleaning & Repairs.
IKEA EGYPT, HOMEWORKS, HOMZMART, B.TECH HOME, COMPOUND, EMAAR, SODIC, TMG, PALM HILLS, MADINATY.
#8B5CF6 (Royal Purple)
6. Shopping, Fashion & Tech(لبس وشوبينج وإلكترونيات)
Wants (رفاهيات)
Clothing & Shoes (لبس وجزم), Online Marketplaces (تسوق أونلاين), Electronics & Phones (موبايلات وإلكترونيات), Cosmetics & Personal Care.
AMAZON EG, NOON, JUMIA, ZARA, H&M, LC WAIKIKI, DEFACTO, MAX FASHION, ACTIV, B.TECH, TRADELINE, RAYA, 2B, DUBAI PHONE, FACES.
#EC4899 (Vibrant Pink)
7. BNPL, Installments & Debt(أقساط وجمعيات وكريدت)
Obligations (التزامات)
BNPL Installments (أقساط فاليو وتقسيط), Credit Card Settlement (سداد كريدت كارد), Monthly Gameya (جمعية شهرية), Bank Loan (قسط قرض).
VALU, SHAHRY, SYMPL, SOUHOOLA, AMAN, FORSA, CONTACT, CREDIT CARD PAYMENT, LOAN INSTALLMENT, جمعية.
#F59E0B (Amber Gold)
8. Subscriptions & Digital(اشتراكات وتطبيقات)
Wants (رفاهيات)
Streaming Video (نتفليكس وشاهد), Music & Podcasts (أنغامي وسبوتيفاي), Cloud & AI Tools (آي كلاود وجوجل), Gaming (بلايستيشن وستيم).
NETFLIX, SHAHID VIP, WATCH IT, OSN+, SPOTIFY, ANGHAMI, YOUTUBE, APPLE.COM/BILL, GOOGLE*ONE, OPENAI, PLAYSTATION, STEAM.
#6366F1 (Indigo)
9. Healthcare, Meds & Gym(صحة وأدوية وجيم)
Needs (أساسيات)
Pharmacies (صيدليات وأدوية), Doctors & Clinics (كشف دكتور), Labs & Scans (تحاليل وأشعة), Gym & Sports (جيم ورياضة), Dental & Optical.
EL EZABY, SEIF PHARMACY, 19011, ELEZABY, YODAWY, VEZEETA, AL BORG, ALFA SCAN, MOKHTABAR, GOLDS GYM, HERS GYM, LA7.
#10B981 (Emerald)
10. Education, Kids & Courses(تعليم ومدارس وكورسات)
Needs (أساسيات)
School & University Tuition (مصاريف مدارس وجامعات), Private Tutoring & Centers (دروس وسنتر), Online Courses (كورسات), Books & Stationery.
UDEMY, COURSERA, BRITISH COUNCIL, AUC, GUC, BUE, SAMIR & ALY, DIWAN BOOKSTORE, NURSERY, SCHOOL.
#14B8A6 (Teal Cyan)
11. Entertainment & Travel(فسح وسفر وخروجات)
Wants (رفاهيات)
Cinema & Events (سينما وحفلات), Domestic Travel (سفر ومصيف - الساحل/دهب/سخنة), Hotels & Flights (فنادق وطيران), Clubs & Activities (نادي).
VOX CINEMAS, RENAISSANCE, TAZKARTI, BOOKING.COM, AIRBNB, EGYPTAIR, AIR CAIRO, WADI DEGLA, GEZIRA CLUB.
#F97316 (Sunset Orange)
12. Family, Charity & Gifts(عيلة وهدايا وصدقات)
Wants / Giving
Family Allowance (مصروف البيت والوالدين), Charity & Zakat (زكاة وصدقات), Weddings & Nuqta (نقطة وهدايا ومناسبات), Tips (بقشيش وإكراميات).
MERSAL, RESALA, BAHEYA, 57357, MAGDI YACOUB, MISR EL KHEIR, FOOD BANK, FLOWER, TSEPPAS, EL ABD, SALE SUCRE.
#A855F7 (Plum)
13. Savings, Gold & Investing(تحويش ودهب واستثمار)
Savings (تحويش)
Gold Coins & Bullion (سبائك وجنيهات دهب), Bank Certificates (شهادات ادخار), Stocks & Funds (أسهم وصناديق استثمار), Emergency Fund (طوارئ).
THNDR, AZIMUT, MENTHUM, BTC GOLD, SAM GOLD, SELEMA GOLD, BANK CD, T-BILLS, SAVING DEPOSIT.
#60B669 (Chart Green)
14. Income, Salary & Refunds(مرتب ودخل وكاش باك)
Income (دخل)
Monthly Salary (المرتب الأساسي), Freelance & Side Hustle (فري لانس وشغل إضافي), Certificate Interest (عائد شهادات), Cashback & Friends Split Refund.
SALARY, PAYROLL, DIVIDEND, INTEREST CREDIT, INSTAPAY INBOUND, REFUND, CASHBACK.
#22C55E (Bright Green)
5. Complete Extracted Specifications & Content of All 14 Mobile UI Screens
This section contains the complete extracted content from the 14 interactive mobile UI screens in the Zaghlol v3.0 prototype—including each screen's Arabic & English title, Business Analysis goal, Local-First technical implementation, Captain Zaghlol's verbatim Egyptian Arabic dialogue, and the exact on-screen UI elements, metrics, and interactive controls.
Figure 2: Live Rendered View of the Zaghlol v3.0 Interactive 14-Screen Mobile Simulator & Business Analyst Specification Panel.
Screen # & Title (AR / EN)
BA Goal & Local-First Tech
Captain Zaghlol Verbatim Quote
Extracted On-Screen UI Content & Controls
Screen 1: ١. الترحيب ووعد الخصوصية ١٠٠٪(1. Zero-Backend Onboarding & Privacy)
BA Goal (الهدف التحليلي):بناء الثقة من أول ثانية وإلغاء الحاجة لأي تسجيل دخول سحابي أو سيرفر خارجي.Local-First Tech (التنفيذ التقني):حفظ الإعدادات محلياً في SQLite المشفر (SQLCipher) مع تفعيل بصمة الوجه FaceID / TouchID.
«أهلاً بيك يا صاحبي! أنا الكابتن زغلول.. هرتبلك كل مصاريفك ورسايل البنوك من غير ما داتا تطلع بره موبايلك ولا نطلب باسورد بنك أبداً!»

• Badge: بدون سيرفر 🔒 (Local 100%)
• Heading: أهلاً بيك في زغلول زيرو-سيرفر!
• Subtitle: أول مساعد مالي مصري شغال ١٠٠٪ جوه تليفونك. لا باسورد بنك، ولا سيرفرات خارجية، ولا إعلانات.
• Settings Card:  - 📅 يوم نزول المرتب: يوم ٢٥  - 💰 الدخل الشهري المستهدف: 32,000 ج.م  - 🔐 قفل التطبيق بـ FaceID: مفعل ✓
• Primary CTA: [يلا نبدأ يا زغلول 🚀]
Screen 2: ٢. ربط الرسايل الذكي (أندرويد وآيفون iOS)(2. Cross-Platform SMS & iOS Shortcut Wizard)
BA Goal (الهدف التحليلي):حل مشكلة قيود iOS عبر دمج 5 قنوات (Shortcuts Message/Transaction + Filter Extension + Back-Tap OCR) مثل تطبيقي Say و FinArt.Local-First Tech (التنفيذ التقني):Android READ_SMS BroadcastReceiver + iOS AppIntents (ParseSmsIntent & LogApplePayIntent) عبر Shared App Group.
«سواء معاك أندرويد أو آيفون، أنا بلقط رسايل الـ ٣٨ بنك وإنستاباي وآبل باي أوتوماتيك من غير ما تكتب حرف بإيدك!»

• Header: إعداد اللقط التلقائي (Android & iOS) — ندعم ٣٨ بنك مصري + إنستاباي + فودافون كاش + فاليو
• Card 1 — 🤖 أندرويد (Background SMS & Notif) [شغال تلقائي]: بيقرأ الرسايل القديمة والجديدة وإشعارات تطبيقات البنوك لحظياً.
• Card 2 — 🍏 آيفون iOS (5-Channel FinArt & Say Tech) [٣ خطوات بس]:  1. Shortcuts SMS Trigger: لقط فوري في الخلفية لرسايل البنوك.  2. Apple Pay Trigger: لقط لحظة الدفع بـ Apple Pay.  3. Double Back-Tap OCR: خبطتين ضهر الآيفون يقرا إيصال إنستاباي!
• Primary CTA: [⚡ تحميل اختصار الآيفون الجاهز (1-Tap)]
Screen 3: ٣. الشاشة الرئيسية ومؤشر الصرف اليومي(3. Multi-Account Home Dashboard)
BA Goal (الهدف التحليلي):تجميع كل الكروت والمحافظ والكاش في شاشة واحدة مع رقم واضح لـ (مسموحلك تصرف كام النهاردة).Local-First Tech (التنفيذ التقني):استعلام SQLite مجمع مع استبعاد التحويلات الداخلية (is_internal_transfer = 0).
«عاش يا بطل! إنت صارف ١٩,٨٠٠ ج من أصل ٢٢,٠٠٠ ج ميزانية الشهر.. مسموحلك تصرف ٣١٤ جنيه كل يوم لحد القبض الجاي!»

• Hero Balance Card: إجمالي السيولة المتاحة (٤ حسابات): 54,240 ج.م [باقي ٧ أيام عالقبض]
• KPI Strip: الدخل: 32,000 ج | المصروف: 19,800 ج | مسموحلك/يوم: 314 ج
• Mascot Banner: «ماشي بالمسطرة يا صاحبي! وفرت ٢,٢٠٠ ج لحد دلوقتي.»
• Recent Auto-Captured Feed (آخر حركات اتلقطت أوتوماتيك من الرسايل):  - 🛒 كارفور المعادي (Carrefour) | البنك الأهلي **4567 
• خزين البيت | -450 ج  - 🍔 طلبات (Talabat Egypt) | كارت CIB **1234 
• أكل بره ودليفري | -285 ج  - 🔄 تحويلة إنستاباي لنفسي | الأهلي ⬅️ CIB 
• مستبعدة من المصاريف | 1,000 ج
Screen 4: ٤. محلل الرسايل الذكي ولقطة الشاشة (OCR)(4. Live SMS Regex & InstaPay OCR Scanner)
BA Goal (الهدف التحليلي):عرض شفافية استخراج البيانات من رسائل البنوك الـ 38 وصور إيصالات إنستاباي.Local-First Tech (التنفيذ التقني):4-Stage Regex Pipeline + تطبيع الأرقام الهندية (٠-٩) + تنظيف أكواد ماكينات الـ POS.
«بص يا سيدي، حتى لو الرسالة جاية برموز غريبة زي CARREFOUR MAADI 041، عدستي بتنظف الاسم وتطلع المبلغ والرصيد المتبقي بالمللي!»

• Raw SMS Input Card (📩 نص الرسالة الخام اللي وصلت الموبايل):  'البنك الأهلي المصري: تم خصم 450.00 جم ببطاقة فيزا **4567 لدى CARREFOUR MAADI EG يوم 23/10. الرصيد المتاح 12400.00 جم'
• Extracted Tokens Grid (🔍 اللي الكابتن زغلول استخرجه في 2ms):  - البنك والكارت: الأهلي (**4567)  - المبلغ والعملة: 450.00 EGP  - اسم التاجر المنظف: Carrefour (كارفور)  - الرصيد المتاح بعدها: 12,400.00 EGP
• Action CTA: [🧪 افتح مختبر الـ ٣٨ بنك وجرب بنفسك]
Screen 5: ٥. التصنيف التلقائي وبناء قواعد التجار(5. Auto-Categorization & User Rule Map)
BA Goal (الهدف التحليلي):تمكين المستخدم من تعديل فئة أي معاملة وتدريب خريطة التصنيف المحلية الخاصة به.Local-First Tech (التنفيذ التقني):جدول UserMerchantRules له الأولوية القصوى فوق جدول CanonicalMerchants المدمج (١٤ فئة أساسية).
«لو غيرت تصنيف أي تاجر بإيدك مرة واحدة، هسألك: تحب نخلي التاجر ده في نفس الفئة دي على طول؟ وهحفظهولك في خريطتك الخاصة!»

• Needs Classification Card (⚡ حركة محتاجة تأكيد تصنيف): 350 ج.م — تحويل إنستاباي إلى: mohamed.tarek@instapay
• 1-Tap Quick Category Chips: [🏠 إيجار وصيانة] [🤝 جمعية شهرية] [🍔 شير عزومة]
• Rule Persistence Checkbox: ☑ احفظ القاعدة دي لأي تحويلة لـ mohamed.tarek مستقبلاً
• Pre-Loaded 14 Categories Grid Preview:  🛒 خزين البيت والسوبرماركت | 🍔 أكل بره وكافيهات ودليفري | 🚗 مواصلات وبنزين وأوبر | 💡 فواتير وشحن ومرافق | 💳 أقساط فاليو وجمعيات | 🪙 تحويش ودهب وشهادات
Screen 6: ٦. «قول لزغلول» — تسجيل الكاش بالصوت بالمصري(6. Egyptian Arabic Voice Cash Logger — Say Parity)
BA Goal (الهدف التحليلي):محاكاة أقوى ميزة في تطبيق Say لتسجيل المصاريف الكاش في مصر في أقل من ثانيتين بالصوت.Local-First Tech (التنفيذ التقني):On-device Speech-to-Text (ar-EG) مع مفسر الأرقام والكلمات المفتاحية المحلي.
«دفعت كاش للخضري أو التاكسي ومفيش رسالة بنك؟ دوس على المايك وقولي جملة واحدة بالمصري وأنا هفصصها وأسجلها!»

• Voice Mic Status: 🎙️ زغلول بيسمعك.. اتكلم بالمصري براحتك!
• Live Spoken Transcript:  «دفعت ١٥٠ جنيه خضار وفاكهة و ٤٥ جنيه قهوة و ٣٠ جنيه تاكسي»
• Auto-Split Multi-Item Output (✨ زغلول فهم الجملة وقسمها ٣ حركات كاش):  1. 🥬 خضار وفاكهة (خزين البيت): 150 ج.م  2. ☕ قهوة (كافيهات وأكل بره): 45 ج.م  3. 🚕 تاكسي (مواصلات وبنزين): 30 ج.م
• Primary CTA: [تأكيد وحفظ الـ ٣ حركات ✓]
Screen 7: ٧. مركز الشارتات وشرح زغلول بالعامية المصرية(7. 12 Interactive Charts & Colloquial Coaching)
BA Goal (الهدف التحليلي):تحويل الرسوم البيانية المعقدة إلى نصائح مصرية مفهومة لكل فئات المستخدمين.Local-First Tech (التنفيذ التقني):مكتبة fl_chart مع محرك القوالب النصية الديناميكية (Egyptian Arabic Insight Engine).
«الشارت من غير شرح ملوش لازمة! تحت كل رسم بياني هتلاقيني بشرحلك بالمصري البسيط إيه اللي زاد وإزاي توفر الشهر الجاي.»

• Active Chart Card: 📊 فطيرة المصاريف (أكتوبر ٢٠٢٦) — الإجمالي: 19,800 ج  - 🛒 خزين البيت والسوبرماركت (27%): 5,400 ج  - 🏠 إيجار وفواتير ومرافق (21%): 4,200 ج  - 🍔 أكل بره وطلبات وكافيهات (19%): 3,850 ج
• Captain Zaghlol Explainer Box:  «زغلول بيقولك: الدليفري والقهوة واخدين ٣,٨٥٠ جنيه! لو قللنا طلبات مرتين في الأسبوع هتوفر ١,٢٠٠ جنيه.»
• Action CTA: [📊 استعرض الـ ١٢ شارت كاملين]
Screen 8: ٨. كاشف التحويلات الذاتية وتقسيم العزومات(8. InstaPay Self-Transfer & Bill Split Offset)
BA Goal (الهدف التحليلي):منع تضخم المصروفات الوهمي بسبب التحويلات بين حسابات نفس الشخص أو دفع عزومة واسترداد حصة الأصدقاء.Local-First Tech (التنفيذ التقني):خوارزمية مطابقة المبلغ والفاصل الزمني (<5 دقائق) + جدول ExpenseSplits لخصم الكاش باك.
«حولت لنفسك ١,٠٠٠ جنيه بإنستاباي من الأهلي لـ CIB؟ متقلقش، لقطت الرسالتين وربطتهم ببعض عشان ميزانيتك متتحسبش مرتين!»

• Auto-Linked Internal Transfer Card (🔗 تحويلة داخلية مكتشفة تلقائياً) [0 ج مصروف]:  خصم 1,000 ج من الأهلي *4567 ⬅️ إيداع 1,000 ج في CIB *1234.
• Friends Bill Split Card (🍕 تقسيم خروجة / عزومة مع الصحاب):  - إجمالي الفاتورة المدفوعة بالكارت: 1,200 ج  - تحويلة واردة من أحمد وكريم (إنستاباي): +800 ج  - صافي مصروفك الشخصي الفعلي: 400 ج.م فقط!
Screen 9: ٩. مخطط ميزانية البيت ودورة يوم القبض(9. Family Budget & Payday Cycle Planner)
BA Goal (الهدف التحليلي):ربط الميزانية بيوم القبض الحقيقي في مصر (يوم ٢٥ مثلاً) مع تنبيهات محلية عند ٨٠٪ و ١٠٠٪.Local-First Tech (التنفيذ التقني):حساب فترة الفوترة المخصصة (Custom Cycle Day) مع إشعارات محلية flutter_local_notifications.
«حاسب يا كبير! ميزانية الأكل بره وصلت ٩٦٪ وإحنا لسه فاضل ٧ أيام عالقبض.. شد الفيشة شوية!»

• Custom Payday Cycle Header: دورة الميزانية المخصصة: ٢٥ أكتوبر ⬅️ ٢٤ نوفمبر [فاضل ٧ أيام]
• Category Budget Progress Bars:  - 🍔 أكل بره ودليفري (96% 🚨): 3,850 / 4,000 ج  - 🛒 خزين البيت (77% 👍): 5,400 / 7,000 ج  - 🚗 مواصلات وبنزين وأوبر (86% ⚠️): 2,150 / 2,500 ج
Screen 10: ١٠. رادار الاشتراكات (×١٢) وجدول أقساط فاليو(10. Subscriptions ×12 Radar & BNPL Timeline)
BA Goal (الهدف التحليلي):إظهار التكلفة السنوية الحقيقية للاشتراكات (×12) ومواعيد استحقاق أقساط BNPL والكريدت كارد لتجنب غرامات التأخير.Local-First Tech (التنفيذ التقني):كشف التكرار الزمني من الرسايل + تنبيه قبل ميعاد القسط بـ ٣ أيام.
«الاشتراكات الشهرية بتبان فكة، بس لما ضربتها في ١٢ شهر طلعت بتبلع ١٥,٦٠٠ جنيه في السنة! شوف إيه اللي مش بتفتحه والغيه.»

• Subscription Radar Card: 📡 الاشتراكات: 1,300 ج/شهر [×12 = 15,600 ج/سنة!]  - 🎬 Netflix + Shahid VIP: 320 ج/شهر (3,840 ج/سنة)  - 🏋️ اشتراك الجيم (Gold's): 750 ج/شهر (9,000 ج/سنة)
• Upcoming Installments Card (🗓️ الأقساط المستحقة الشهر ده — ٢,٩٠٠ ج):  - 🟠 قسط فاليو (تريدلاين - ٤ من ٦): 1,000 ج (يوم ٥)  - 🟢 قسط سيمبل (زارا - آخر قسط!): 450 ج (يوم ١٢)  - 💳 سداد كارت مشتريات HSBC: 1,450 ج (يوم ١٥)
Screen 11: ١١. متتبع صافي الثروة والدهب والشهادات(11. Net Worth, 21K/24K Gold & Bank CDs Tracker)
BA Goal (الهدف التحليلي):تغطية طريقة الادخار الفعلية للمصريين (جرامات الذهب عيار ٢١/٢٤، جنيهات الذهب، شهادات البنوك، والدولار) كما في تطبيق Say.Local-First Tech (التنفيذ التقني):جدول WealthAssets مع حاسبة العائد السنوي للشهادات وتقييم جرامات الذهب بالجرام والعيار.
«ما شاء الله يا معلم! صافي ثروتك كسر ٣٢٩,٠٠٠ جنيه.. السبايك وعيار ٢١ والشهادة الـ ٢٧٪ عاملين شغل عالي!»

• Net Worth Counter: 💎 إجمالي صافي الثروة (Net Worth): 329,000 ج.م (+7.2%)
• Portfolio Breakdown:  - 🪙 محفظة الدهب (24g عيار 21 + 5g سبيكة عيار 24): 112,000 ج  - 🏦 شهادات البنك الأهلي (عائد ٢٧٪ — العائد الشهري القادم +3,375 ج يوم ٢٨): 163,000 ج  - 💵 حسابات جارية وعملات (سيولة بالجنيه + 400 دولار): 54,000 ج
Screen 12: ١٢. شات «اسأل زغلول» ومود قصف الجبهة المالي(12. 'Ask Zaghlol' AI Chat & Roast Mode)
BA Goal (الهدف التحليلي):توفير شات ذكي محلي يجيب على أسئلة المستخدم المالية ويرسم شارتات لحظية مع أسلوب فكاهي مصري.Local-First Tech (التنفيذ التقني):تحليل الأسئلة الطبيعية محلياً وتحويلها إلى استعلامات SQLite مع رسم شارت مدمج داخل المحادثة.
«اسألني أي سؤال عن فلوسك بالعربي أو الإنجليزي وهرسملك شارت في الشات فوراً.. ولو قلبك جامد دوس على (إقصف جبهتي يا زغلول)!»

• User Query Bubble:  'يا زغلول إقصف جبهتي.. أنا صرفت كام على القهوة والدليفري آخر ٣ شهور؟ 😂'
• Captain Zaghlol Roast Bubble (الكابتن زغلول — مود قصف الجبهة 🔥):  «امسك أعصابك يا فنان! إنت في ٣ شهور دافع 11,420 جنيه في طلبات وستاربكس (٤٧ أوردر)! الفلوس دي كانت تجيبلك سبيكة دهب ٣ جرام عيار ٢٤ بدل ما شربتها لاتيه بارد!»
• In-Chat Mini Trend Strip: أغسطس: 3,620 ج | سبتمبر: 3,950 ج | أكتوبر: 3,850 ج
Screen 13: ١٣. باقة «زغلول جولد» (تصدير CSV وجوجل درايف)(13. Zaghlol Gold: CSV Export & Google Drive Backup)
BA Goal (الهدف التحليلي):نموذج الربح المحلي (Pay Model) بدون سيرفر: الدفع مقابل تصدير/استيراد CSV والنسخ الاحتياطي السحابي المشفر والشارتات المتقدمة.Local-First Tech (التنفيذ التقني):StoreKit 2 & Google Play Billing v7 + Google Drive API (drive.appdata) مع تشفير AES-256-GCM.
«التطبيق الأساسي مجاني للأبد! لكن لو عايز تصدر كل حساباتك لشيت إكسيل CSV أو تحفظ نسخة احتياطية مشفرة على Google Drive بتاعك، اشترك في زغلول جولد!»

• Gold Banner: 👑 باقة زغلول جولد (Zaghlol Gold) — 49 ج/شهر 
• 399 ج/سنة 
• أو 899 ج مدى الحياة
• Paid Feature 1: 📊 تصدير واستيراد شيت CSV / Excel — يدعم العربي بالكامل (UTF-8 BOM) [تصدير CSV]
• Paid Feature 2: ☁️ نسخ احتياطي مشفر على Google Drive / iCloud — نسخة مشفرة AES-256 على درايفك الشخصي [حفظ Drive]
Screen 14: ١٤. مشاركة الإنجاز وكروت السوشيال ميديا(14. Viral Social Share & Promo Card Studio)
BA Goal (الهدف التحليلي):خلق نمو فيروسي (Viral Growth Loop) عبر كروت مشاركة جذابة باللهجة المصرية مع إخفاء الأرقام الحساسة اختيارياً.Local-First Tech (التنفيذ التقني):تحويل ويدجت Flutter إلى صورة PNG عالية الجودة جاهزة للمشاركة عبر Share Sheet.
«حققت هدف التوفير الشهر ده؟ شير كارت إنجازك مع صحابك على إنستجرام وواتساب من غير ما أرقامك الخاصة تبان!»

• Shareable Certificate Card: 🏆 شهادة تقدير من الكابتن زغلول  «وفرت ٣٨٪ من مرتبي الشهر ده وقللت الدليفري للنص!»  #زغلول_ضبط_الميزانية 
• تطبيق زغلول المالي
• Primary CTA: [📣 استعرض الـ ٨ بوستات التسويقية الجاهزة]
6. Complete Extracted Egyptian Social Media Marketing Campaign Boxes (8 Ads)
Below is the complete, word-for-word extraction of all 8 Egyptian Arabic Social Media Marketing Boxes from the Marketing Studio—including each campaign's target platform, featured UI screen, Egyptian Arabic marketing hook, full multi-paragraph ad caption, hashtags, and CTA button:
Figure 3: Promotional Campaign Hero Artwork — Captain Zaghlol presenting the Dark-Teal (#174C4F) and Coin-Gold (#F0B33A) Mobile Analytics UI Suite.
Campaign Box #1 — Instagram / FB Carousel (معروض من جوه التطبيق: ٣. الشاشة الرئيسية ومؤشر الصرف اليومي)الهوك التسويقي (Marketing Hook):«القبض بينزل يوم ٢٥.. وبيتبخر يوم ٢٨؟ زغلول هيقولك العفريت اللي بيصرف فلوسك! 💸🕊️»النص الإعلاني الكامل بالعامية المصرية (Full Ad Copy):كل شهر نفس السؤال: هو المرتب راح فين؟ 🤔مع تطبيق (زغلول)، مش هتكتب ورقة وقلم ولا هتدخل باسورد حسابك البنكي!زغلول بيقرأ رسايل الـ ٣٨ بنك في مصر وإنستاباي وفودافون كاش وفاليو أوتوماتيك، ويقولك بالعامية المصرية كل جنيه طار فين، وفاضلك كام تصرفه كل يوم لحد القبض الجاي!✅ شغال ١٠٠٪ جوه تليفونك (خصوصية كاملة بدون سيرفر)✅ بيفهم العربي والإنجليزيالهاشتاجات (Hashtags): #زغلول #مصاريفك_تحت_السيطرة #إنستاباي #ميزانية_البيت #توفير #مصرزر الإعلان (CTA Button): [حمّل زغلول مجاناً]
Campaign Box #2 — TikTok / Reels Viral Video (معروض من جوه التطبيق: ١٢. شات «اسأل زغلول» ومود قصف الجبهة المالي)الهوك التسويقي (Marketing Hook):«لما تدوس على زرار (إقصف جبهتي يا زغلول) وتكتشف إنك شارب قهوة بـ ٤,٢٠٠ جنيه في شهر! 😱☕»النص الإعلاني الكامل بالعامية المصرية (Full Ad Copy):قلبك جامد؟ جرب مود (قصف الجبهة المالي) في أبلكيشن زغلول! 🔥😂اسأل الكابتن زغلول: «أنا صرفت كام على طلبات والقهوة الشهر ده؟» وهيرسملك شارت في ثانية ويقولك الفلوس دي كانت تجيبلك كام جرام دهب عيار ٢١ بدل ما بلعتها شاورما ولاتيه!منشن صاحبك اللي بيخلص مرتبه على الأكل بره أول أسبوع في الشهر 👇الهاشتاجات (Hashtags): #قصف_جبهة_مالي #زغلول #طلبات #قهوة #مرتب #تيك_توك_مصرزر الإعلان (CTA Button): [جرب مود قصف الجبهة]
Campaign Box #3 — Facebook / X Trust Post (معروض من جوه التطبيق: ١. الترحيب ووعد الخصوصية ١٠٠٪)الهوك التسويقي (Marketing Hook):«خايف تربط حسابك البنكي بأي أبلكيشن مصاريف؟ عندك حق.. عشان كدة زغلول شغال ١٠٠٪ جوه موبايلك وبس! 🔒📱»النص الإعلاني الكامل بالعامية المصرية (Full Ad Copy):أهم ميزة في (زغلول) إننا معملناش سيرفر أصلاً! 🛡️يعني لا بنطلب منك إيميل ولا رقم تليفون ولا باسورد بنك، وكل رسايلك ومعاملاتك بتتحلل وتتحفظ في قاعدة بيانات مشفرة جوه جهازك إنت وبس.حتى لما تحب تاخد نسخة احتياطية، بتتحفظ مشفرة على Google Drive أو iCloud الشخصي بتاعك مباشرة!الهاشتاجات (Hashtags): #خصوصيتك_أولاً #أمان_مالي #زغلول #بنوك_مصر #FinTechEgyptزر الإعلان (CTA Button): [اعرف أكتر عن الأمان]
Campaign Box #4 — Instagram Story / Feed (معروض من جوه التطبيق: ٨. كاشف التحويلات الذاتية وتقسيم العزومات)الهوك التسويقي (Marketing Hook):«بتحول لنفسك إنستاباي من بنك لبنك وميزانيتك بتتلخبط؟ زغلول بيلقطها لوحده! 🔄✨»النص الإعلاني الكامل بالعامية المصرية (Full Ad Copy):أكبر مشكلة في تطبيقات المصاريف التانية إنك لما تحول ١,٠٠٠ جنيه بإنستاباي من حسابك في الأهلي لحسابك في CIB، بيحسبها كأنك صرفت ١,٠٠٠ جنيه! 🤦‍♂️الكابتن زغلول بيلقط رسالة الخصم ورسالة الإيداع في نفس اللحظة ويربطهم ببعض كـ (تحويلة داخلية = صفر مصروف)!وكمان لو عزمت صحابك وحولولك نصيبهم إنستاباي، زغلول بيخصم تحويليتهم من الفاتورة عشان يحسبلك مصروفك الصافي بس!الهاشتاجات (Hashtags): #إنستاباي #InstaPayEgypt #زغلول #البنك_الأهلي #CIB #شير_العزومةزر الإعلان (CTA Button): [جرب ذكاء زغلول]
Campaign Box #5 — iOS / iPhone Carousel (معروض من جوه التطبيق: ٢. ربط الرسايل الذكي — أندرويد وآيفون iOS)الهوك التسويقي (Marketing Hook):«معاك آيفون وكنت فاكر مفيش تتبع تلقائي لرسايل البنوك و Apple Pay؟ زغلول حلها في دقيقة! 🍏⚡»النص الإعلاني الكامل بالعامية المصرية (Full Ad Copy):لكل مستخدمي الآيفون في مصر.. وداعاً للإدخال اليدوي الممل! 🎉أبلكيشن (زغلول) بيديك ٥ طرق ذكية على iOS:1️⃣ ربط تلقائي مع Apple Shortcuts بيلقط رسايل البنوك وإنستاباي في الخلفية.2️⃣ تسجيل فوري أول ما تدفع بـ Apple Pay.3️⃣ خبطتين على ضهر الآيفون (Back-Tap) يقرا أي سكرين شوت لتحويلة إنستاباي في ثانية!4️⃣ استيراد كشف حساب البنك PDF.الهاشتاجات (Hashtags): #آيفون_مصر #ApplePayEgypt #iOS18 #زغلول #تطبيقات_آيفونزر الإعلان (CTA Button): [فعل اختصار الآيفون]
Campaign Box #6 — TikTok / Reels Voice Demo (معروض من جوه التطبيق: ٦. «قول لزغلول» — تسجيل الكاش بالصوت بالمصري)الهوك التسويقي (Marketing Hook):«دفعت كاش في الخضار والفاكهة والتاكسي ومكسل تكتب؟ دوس المايك وقول لزغلول بالمصري! 🎙️🥬»النص الإعلاني الكامل بالعامية المصرية (Full Ad Copy):إحنا في مصر نص مصاريفنا كاش ومن غير رسايل بنك.. طب هنسجلها إزاي من غير وجع دماغ؟ 🤷‍♂️دوس على زرار (قول لزغلول) وقوله جملة واحدة بس:«دفعت ١٥٠ جنيه خضار وفاكهة و ٤٥ جنيه قهوة و ٣٠ جنيه تاكسي»في أقل من ثانيتين، زغلول هيفصص الجملة لـ ٣ حركات منفصلة ويحط كل واحدة في فئتها الصح!الهاشتاجات (Hashtags): #قول_لزغلول #مصاريف_البيت #خزين_البيت #كاش #زغلولزر الإعلان (CTA Button): [سجل بصوتك دلوقتي]
Campaign Box #7 — Facebook / Wealth Post (معروض من جوه التطبيق: ١١. متتبع صافي الثروة والدهب والشهادات)الهوك التسويقي (Marketing Hook):«حساباتك، سبايك وجنيهات الدهب، وشهادات الـ ٢٧٪.. اعرف صافي ثروتك الحقيقي في شاشة واحدة! 🪙📈»النص الإعلاني الكامل بالعامية المصرية (Full Ad Copy):الفلوس مش بس اللي في كارت المرتب! 💎زغلول بيجمعلك كل اللي حيلتك في مكان واحد:🔸 حساباتك البنكية والمحافظ والكاش🔸 جرامات الدهب (عيار ٢١ وعيار ٢٤ والجنيهات الدهب)🔸 شهادات الادخار البنكية ومواعيد نزول العائد الشهري🔸 الأقساط والالتزامات الجاية (فاليو، سهولة، سيمبل، الكريدت كارد)الهاشتاجات (Hashtags): #دهب_مصر #سعر_الدهب #شهادات_البنك #تحويش #استثمار #زغلولزر الإعلان (CTA Button): [احسب صافي ثروتك]
Campaign Box #8 — Zaghlol Gold Promo Card (معروض من جوه التطبيق: ١٣. باقة «زغلول جولد» — تصدير CSV وجوجل درايف)الهوك التسويقي (Marketing Hook):«عايز شيت إكسيل بكل مصاريفك أو نسخة احتياطية مشفرة على Google Drive بتاعك؟ خليك زغلول جولد! 👑☁️»النص الإعلاني الكامل بالعامية المصرية (Full Ad Copy):بتحب تراجع حساباتك على اللابتوب في شيت إكسيل؟ أو خايف تغير موبايلك وتضيع داتك؟ 💻📊مع باقة (زغلول جولد):✨ تصدير واستيراد كل معاملاتك لملف CSV أو Excel داعم للعربي بضغطة زرار.✨ نسخ احتياطي تلقائي (يومي/أسبوعي/شهري) مشفر بالكامل على Google Drive أو iCloud الخاص بيك.✨ فتح الـ ١٢ شارت المتقدمين ورادار الاشتراكات المنسية في ١٢ شهر!الهاشتاجات (Hashtags): #زغلول_جولد #إكسيل #GoogleDrive #محاسبة_شخصية #زغلولزر الإعلان (CTA Button): [اشترك في زغلول جولد]
7. Complete Extracted Catalog of All 12 Charts, Datasets & Zaghlol Explanations
All 12 interactive charts from the Zaghlol v3.0 Analytics Studio are rendered below across three 4-panel visual figures, followed by the complete extracted dataset values, Captain Zaghlol's verbatim Egyptian Arabic explanation (زغلول بيشرحلك الشارت بالمصري), and the actionable savings tip for each chart:
Figure 4: Visual Analytics Panel A (Charts 1–4) — Monthly Cash Flow, Category Breakdown, Payday Burn-Rate Curve, and Net Worth Growth.
Figure 5: Visual Analytics Panel B (Charts 5–8) — Day-of-Week Spending Pattern, Top Merchants Leaderboard, MoM Variance vs. 3-Month Average, and 6-Month BNPL Installment Timeline.
Figure 6: Visual Analytics Panel C (Charts 9–12) — Subscription Radar (Monthly vs. ×12 Annual), Multi-Card & Wallet Distribution, 50/30/20 Balance, and Personal Basket Inflation Tracker.
Chart # & Name (AR / EN)
Extracted Chart Dataset & Values
Captain Zaghlol's Verbatim Explanation (زغلول بيشرحلك بالمصري)
Actionable Savings Tip (النصيحة العملية)
1. شارت الداخل والخارج والصافي(Cash Flow Bar)
Months: [مايو, يونيو, يوليو, أغسطس, سبتمبر, أكتوبر]
• الدخل (EGP): [28000, 28000, 31500, 28000, 30000, 32000]
• المصاريف (EGP): [22400, 24100, 25800, 21900, 23200, 19800]
• الصافي المحوش (EGP): [5600, 3900, 5700, 6100, 6800, 12200]
«بص يا سيدي، العواميد الكحلي دي قبضك والفلوس اللي دخلتلك، والأحمر ده اللي اتصرف، والأخضر ده اللي اتبقى في جيبك. الشهر ده إنت موفر ١٢,٢٠٠ جنيه، يعني محوش ٣٨٪ من دخلك.. الله ينور!»
حول على الأقل ٨,٠٠٠ ج من الفائض ده فوراً لشهادة ادخار أو اشتري بيهم ربع جنيه دهب قبل ما يتصرفوا!
2. فطيرة المصاريف — فلوسك رايحة فين؟(Category Donut)
Total October Spend: 19,800 EGP
• خزين البيت: 5,400 ج (27%)
• إيجار وفواتير: 4,200 ج (21%)
• أكل بره وطلبات: 3,850 ج (19%)
• أقساط فاليو وكريدت: 2,900 ج (15%)
• مواصلات وبنزين: 2,150 ج (11%)
• اشتراكات: 1,300 ج (7%)
«الدائرة دي بتقولك كل قرش راح فين: خزين البيت واخد ٢٧٪ (٥,٤٠٠ ج)، وأكل بره وطلبات واخد ١٩٪ (٣,٨٥٠ ج). لو قللنا الدليفري مرتين في الأسبوع هتوفر ١,٢٠٠ جنيه مرتاح!»
حدد سقف ٣,٠٠٠ ج بس للأكل بره الشهر الجاي وهتوفر ٨٥٠ ج صافي.
3. منحنى الصرف لحد يوم القبض(Payday Burn-Rate Curve)
Cycle Days: [يوم 1, يوم 5, يوم 10, يوم 15, يوم 20, يوم 23 (النهاردة), يوم 30 (القبض)]
• الصرف الفعلي التراكمي: [1200, 4900, 8200, 13100, 17500, 19800, null]
• خط الأمان المثالي للميزانية: [733, 3666, 7333, 11000, 14666, 16866, 22000]
«الخط المنقط ده سرعتك المثالية عشان الميزانية (٢٢,٠٠٠ ج) تكفي لحد يوم ٢٥. طول ما الخط الأخضر بتاعك تحته، إنت في الأمان وليك تصرف ٣١٤ جنيه في اليوم لحد القبض الجاي!»
إنت دلوقتي في اليوم الـ ٢٣ من دورة المرتب وبقيلك ٢,٢٠٠ ج في الميزانية لـ ٧ أيام.
4. ميزان 50/30/20(الأساسيات والرفاهيات والتحويش)
Buckets: [الأساسيات (Needs), الرفاهيات (Wants), التحويش والأقساط (Savings)]
• النسبة المثالية: [50%, 30%, 20%]
• نسبتك الفعلية الشهر ده: [42%, 20%, 38%]
«القاعدة الذهبية بتقول ٥٠٪ أساسيات، ٣٠٪ رفاهيات، و٢٠٪ تحويش. إنت حالياً صارف ٤٢٪ أساسيات و٢٠٪ رفاهيات ومحوش ٣٨٪.. ميزانك مظبوط بالشعرة يا معلم!»
استمر على نسبة التحويش فوق ٣٠٪ وهتوصل لهدف الطوارئ قبل نهاية السنة.
5. خريطة أوقات الصرف وويك إند الخميس(Day-of-Week Spend)
Days: [السبت, الأحد, الإثنين, الثلاثاء, الأربعاء, الخميس 🔥, الجمعة 🔥]
• متوسط الصرف اليومي (ج.م): [520, 390, 410, 380, 460, 1450, 1280]
«بص على عمود يوم الخميس والجمعة! خروجة الويك إند لوحدها واخدة ٤٢٪ من مصروفك الأسبوعي، وأكتر وقت إيدك بتفرط فيه هو من ٩ بالليل لـ ١ الفجر في أوردرات الدليفري!»
حط سقف ٦٠٠ ج لخروجة الخميس الجاي، وبلاش تفتح تطبيقات الأكل بعد الساعة ١١ بالليل!
6. أكتر ١٠ أماكن بتبلع فلوسك(Top Merchants Leaderboard)
Merchants & Spend (EGP):
• Carrefour: 3,200 ج
• Talabat: 2,150 ج
• Seoudi Market: 1,400 ج
• valU Installment: 1,000 ج
• Uber Egypt: 980 ج
• ChillOut Fuel: 890 ج
• Starbucks: 640 ج
«دول أكتر تجار خدوا منك فلوس الشهر ده: كارفور في المركز الأول بـ ٣,٢٠٠ جنيه (٤ زيارات)، وبعده طلبات بـ ٢,١٥٠ جنيه (١١ أوردر)، وبعده سعودي بـ ١,٤٠٠ جنيه!»
جمع طلبات السوبرماركت في زيارة واحدة أسبوعياً عشان تقلل المشتريات العشوائية.
7. مقارنة الشهر ده بمتوسط آخر ٣ شهور(MoM Variance)
Categories: [خزين البيت, أكل بره, مواصلات وبنزين, لبس وشوبينج, فواتير]
• متوسط آخر ٣ شهور: [5200, 4100, 1820, 2400, 4000]
• الشهر الحالي: [5400, 3850, 2150, 1560, 4200]
«الشارت ده بيقارنك بنفسك: مصاريف البنزين والمواصلات زادت ١٨٪ عن متوسطك، بس برافو عليك نزلت مصاريف الشوبينج واللبس بـ ٣٥٪ الشهر ده!»
وفورات اللبس والشوبينج عوضت زيادة البنزين وخلتك كسبان ١,١٠٠ ج في الإجمالي.
8. جدول الأقساط والالتزامات الـ ٦ شهور الجايين(BNPL Timeline)
Months: [أكتوبر, نوفمبر, ديسمبر, يناير, فبراير, مارس]
• أقساط فاليو وسيمبل (BNPL): [1450, 1000, 1000, 0, 0, 0]
• كريدت كارد وجمعية شهرية: [1450, 1450, 1450, 1000, 1000, 1000]
«دي خريطة الأقساط اللي مربوطة في رقبتك الـ ٦ شهور الجايين! الشهر ده عليك ٢,٩٠٠ جنيه، بس الخبر الحلو إن قسط سيمبل هيخلص الشهر ده وقسط فاليو هيخلص في ديسمبر!»
متدخلش في أي تقسيط جديد قبل شهر يناير لحد ما تقفل قسط تريدلاين.
9. رادار الاشتراكات المنسية مضروبة في ١٢ شهر(×12 Radar)
Subscriptions: [الجيم, Netflix + Shahid, Home Internet WE, Spotify + iCloud]
• التكلفة الشهرية (ج.م): [750, 320, 420, 230]
• التكلفة السنوية ×12 (ج.م): [9000, 3840, 5040, 2760]
«الاشتراكات الصغيرة بتبان فكة، بس لما نضربها في ١٢ شهر بتعمل ١٥,٦٠٠ جنيه في السنة! راجع اشتراك OSN+ أو الجيم لو مش بتروح والغيه فوراً.»
إلغاء اشتراك واحد بـ ٢٠٠ ج/شهر بيوفرلك ٢,٤٠٠ ج في السنة!
10. توزيع الصرف على الكروت والمحافظ والكاش(Cards & Wallets)
Payment Methods (EGP):
• كارت البنك الأهلي Visa: 8,910 ج (45%)
• كارت CIB Credit: 4,950 ج (25%)
• تحويلات إنستاباي: 3,560 ج (18%)
• فودافون كاش: 1,180 ج (6%)
• كاش يدوي/صوت: 1,200 ج (6%)
«٤٥٪ من مصاريفك طالعة من كارت البنك الأهلي، و٢٥٪ من كارت مشتريات CIB، و١٨٪ إنستاباي، و١٢٪ كاش وفودافون كاش. كارت CIB مسحوب منه ٤٢٪ بس من الليميت وده ممتاز!»
خلي سحب الكريدت كارد دايماً أقل من ٥٠٪ وسدده بالكامل قبل يوم ١٥.
11. تطور صافي الثروة والدهب والشهادات(Net Worth Growth)
Months: [مايو, يونيو, يوليو, أغسطس, سبتمبر, أكتوبر]
• إجمالي صافي الثروة (ألف ج.م): [270, 277, 289, 299, 313, 329]
«ما شاء الله! صافي ثروتك زاد من ٢٧٠ ألف في مايو لـ ٣٢٩ ألف في أكتوبر بفضل تحويش الكاش وارتفاع قيمة جرامات الدهب عيار ٢١ وعائد الشهادة البنكية.»
إنت موزع ثروتك صح: ٥٠٪ شهادات بعائد ثابت، ٣٤٪ دهب لحفظ القيمة، و١٦٪ سيولة جاهزة.
12. مؤشر غلاء الأسعار الشخصي(Personal Inflation Tracker)
Months: [مايو, يونيو, يوليو, أغسطس, سبتمبر, أكتوبر]
• متوسط فاتورة السوبرماركت (ج.م): [620, 650, 690, 740, 780, 810]
• متوسط أوردر الدليفري (ج.م): [195, 210, 230, 250, 270, 285]
«الشارت ده بيقيس أثر الغلاء على سلتك الشخصية: متوسط زيارتك الواحدة للسوبرماركت كان ٦٢٠ جنيه في مايو، ودلوقتي بقى ٨١٠ جنيه لنفس الطلبات تقريباً!»
استبدل الماركات المستوردة ببدائل محلية في المنظفات والجبن هينزل فاتورة السوبرماركت ٢٠٪.
8. Complete Extracted Bilingual SMS Lab Dataset (53 Institutions) & Regex Code
Below are all 53 bilingual (Arabic and English) SMS templates extracted directly from the interactive SMS Regex Lab—covering all 38 Egyptian banks, 6 InstaPay scenarios, 6 Digital Wallets/Cards, and 3 BNPL installment groups—followed by the complete JavaScript/Dart Regex Extractor code:
# & Institution / Provider
Type
Arabic Sample SMS (نموذج الرسالة بالعربي)
English Sample SMS (نموذج الرسالة بالإنجليزي)
1. البنك الأهلي المصري (NBE)
BANK
البنك الأهلي المصري: تم خصم 200.00 جم ببطاقة فيزا **4567 لدى AMAZON EG يوم 23/10. الرصيد المتاح 12400.00 جم
NBE: Purchase of EGP 200.00 from NBE Visa **4567 at AMAZON EG on 23/10. Avl Bal EGP 12,400.00
2. بنك مصر (Banque Misr)
BANK
بنك مصر: عملية شراء بمبلغ 50.00 جم باستخدام بطاقة ****8901 لدى GOURMET. الرصيد المتاح 15200.50 جم
BM: Purchase of EGP 50.00 with card ****8901 at GOURMET. Avl Bal EGP 15,200.50
3. البنك التجاري الدولي (CIB)
BANK
البنك التجاري الدولي: عملية شراء بمبلغ 450.00 جم لدى UBER EG ببطاقة ينتهي رقمها بـ 1234. الرصيد 4500.20 جم
Purchase of EGP 450.00 at UBER EG with Card ending 1234. Avl Bal: EGP 4,500.20.
4. بنك قطر الوطني (QNB Egypt)
BANK
QNB: تم تنفيذ عملية شراء بقيمة 300.00 جم ببطاقة ****4321 لدى MCDONALDS. الرصيد المتاح 8100.00 جم
QNB: Purchase of EGP 300.00 made on 23/10 with Card ****4321 at MCDONALDS. Avl Bal EGP 8,100.00
5. بنك القاهرة (Banque du Caire)
BANK
بنك القاهرة: تم خصم 150.00 جم لعملية شراء لدى كارفور ببطاقة *5512. الرصيد المتاح 1000.00 جم
BDC: Purchase of EGP 150.00 at CARREFOUR on 23/10 using card *5512. Avl Bal: EGP 1,000.00
6. بنك الإسكندرية (ALEXBANK)
BANK
بنك الإسكندرية: تم دفع 120.00 جم لدى ستاربكس باستخدام بطاقة ينتهي رقمها بـ 7788. الرصيد 1500.00 جم
AlexBank: You paid EGP 120.00 at STARBUCKS using Card ending in 7788. Avl Bal EGP 1500.00
7. البنك العربي الأفريقي الدولي (AAIB)
BANK
البنك العربي الأفريقي الدولي: عملية شراء بمبلغ 600.00 جم باستخدام كارت ****4321 لدى SPINNEYS. الرصيد 5000.00 جم
AAIB: A purchase of EGP 600.00 was made with Card ****4321 at SPINNEYS. Avl Bal: EGP 5000.00
8. بنك كريدي أجريكول مصر (CAE)
BANK
كريدي أجريكول: تم خصم 80.00 جم لدى مترو ماركت باستخدام بطاقة ****2233. الرصيد المتاح 5400.00 جم
Credit Agricole: EGP 80.00 purchased at METRO MARKET using Card ****2233. Avl Bal EGP 5400.00
9. بنك إتش إس بي سي مصر (HSBC)
BANK
إتش إس بي سي: عملية شراء بمبلغ 850.00 جم لدى زارا القاهرة ببطاقة 5555. الحد المتاح 10000.00 جم
HSBC: Purchase of EGP 850.00 at ZARA CAIRO with card ending 5555. Avl limit: EGP 10,000.00.
10. بنك الإمارات دبي الوطني (Emirates NBD)
BANK
الإمارات دبي الوطني: خصم 450.00 جم لدى UBER EG بكارت ينتهي بـ 1234. الرصيد المتاح 4500.20 جم
EmiratesNBD: Purchase of EGP 450.00 at UBER EG with Card ending 1234. Avl Bal: EGP 4,500.20.
11. مصرف أبوظبي الإسلامي (ADIB)
BANK
مصرف أبوظبي الإسلامي: تم خصم 600.00 جم من بطاقتك المنتهية بـ 1122 لدى كارفور. الرصيد 4000 جم
ADIB: EGP 600.00 has been charged to your card ending 1122 at CARREFOUR. Avl bal EGP 4000.
12. بنك أبوظبي الأول مصر (FABMISR)
BANK
بنك أبوظبي الأول مصر: عملية شراء بقيمة 55.00 جم لدى كوستاكوفي باستخدام كارت 3344. الرصيد 950.00 جم
FABMISR: Purchase of EGP 55.00 at COSTA COFFEE using card 3344. Avl Balance: EGP 950.00
13. بنك التعمير والإسكان (HDB)
BANK
بنك التعمير والإسكان: تم خصم 320.00 جم ببطاقة **9012 لدى سعودي ماركت. الرصيد المتاح 6200.00 جم
HDB: Purchase of EGP 320.00 using card **9012 at SEOUDI MARKET. Available Bal: EGP 6,200.00
14. البنك المصري الخليجي (EG BANK)
BANK
إي جي بنك: تم استخدام بطاقة **6789 بمبلغ 190.00 جم لدى TALABAT EG. الرصيد المتاح 3410.00 جم
EGBANK: Card **6789 used for EGP 190.00 at TALABAT EG on 23/10. Avl Bal: EGP 3,410.00
15. بنك فيصل الإسلامي المصري (Faisal Bank)
BANK
بنك فيصل الإسلامي: تم خصم 750.00 جم ببطاقة *3310 لدى بي تك. الرصيد المتاح 9250.00 جم
Faisal Bank: Purchase of EGP 750.00 with Card *3310 at B.TECH. Avl Bal: EGP 9,250.00
16. بنك البركة مصر (Al Baraka)
BANK
بنك البركة: تم خصم مبلغ 410.00 جم من بطاقة **2045 لدى كازيون. الرصيد المتاح 5190.00 جم
Al Baraka: EGP 410.00 debited from Card **2045 at KAZYON on 23/10. Avl Bal EGP 5,190.00
17. بنك أبوظبي التجاري مصر (ADCB)
BANK
أبوظبي التجاري: تم استخدام بطاقتك المنتهية بـ 8821 بمبلغ 275.00 جم لدى صيدليات العزبي. الرصيد 7300.00 جم
ADCB: Your card ending 8821 was used for EGP 275.00 at EL EZABY. Avl Bal EGP 7,300.00
18. بيت التمويل الكويتي مصر (KFH / AUB)
BANK
بيت التمويل الكويتي: عملية شراء بمبلغ 520.00 جم ببطاقة ****1902 لدى IKEA EGYPT. الحد المتاح 14000.00 جم
KFH Egypt: Purchase of EGP 520.00 on Card ****1902 at IKEA EGYPT. Avl Limit EGP 14,000.00
19. بنك الكويت الوطني مصر (NBK)
BANK
بنك الكويت الوطني: تم خصم 1100.00 جم على بطاقة **4409 لدى تريدلاين. الرصيد المتاح 18900.00 جم
NBK: EGP 1,100.00 charged on Card **4409 at TRADELINE. Available Balance: EGP 18,900.00
20. البنك الأهلي الكويتي مصر (ABK)
BANK
الأهلي الكويتي: تم خصم 95.00 جم من بطاقة 7123 لدى TBS BAKERY. الرصيد المتاح 2805.00 جم
ABK-Egypt: Card ending 7123 charged EGP 95.00 at TBS BAKERY on 23/10. Avl Bal EGP 2,805.00
21. بنك قناة السويس (Suez Canal Bank)
BANK
بنك قناة السويس: عملية شراء بمبلغ 340.00 جم ببطاقة ****6011 لدى CHILLOUT. الرصيد المتاح 4660.00 جم
SCB: Purchase of EGP 340.00 using Card ****6011 at CHILLOUT. Avl Bal: EGP 4,660.00
22. المصرف المتحد (The United Bank)
BANK
المصرف المتحد: تم دفع 260.00 جم لدى هايبر وان ببطاقة **3098. الرصيد المتاح 3740.00 جم
The United Bank: EGP 260.00 paid at HYPER ONE with card **3098. Avl Bal: EGP 3,740.00
23. البنك المصري لتنمية الصادرات (EBank)
BANK
EBank: تم خصم 480.00 جم على بطاقة تنتهي بـ 5120 لدى بافلو برجر. الرصيد المتاح 6520.00 جم
EBank: Purchase of EGP 480.00 on Card ending 5120 at BUFFALO BURGER. Avl Bal EGP 6,520.00
24. بنك نكست (Bank NXT / aiBANK)
BANK
بنك نكست: تم خصم 175.00 جم لدى سيلانترو باستخدام بطاقة **8412. الرصيد المتاح 5825.00 جم
Bank NXT: EGP 175.00 spent at CILANTRO using Card **8412. Avl Bal: EGP 5,825.00
25. بنك الشركة المصرفية العربية (saib)
BANK
بنك saib: تم استخدام بطاقة **9931 للشراء بمبلغ 640.00 جم لدى H&M CAIRO. الرصيد المتاح 11360.00 جم
saib: Card **9931 used for purchase of EGP 640.00 at H&M CAIRO. Avl Bal EGP 11,360.00
26. ميد بنك (MIDBANK)
BANK
ميد بنك: عملية شراء بقيمة 210.00 جم لدى توتال إنرجيز ببطاقة ****4018. الرصيد المتاح 2790.00 جم
MIDBANK: Purchase of EGP 210.00 at TOTAL ENERGIES with Card ****4018. Avl Bal EGP 2,790.00
27. البنك الزراعي المصري (ABE)
BANK
البنك الزراعي المصري: تم خصم 500.00 جم ببطاقة **1104 لدى فتح الله. الرصيد المتاح 3200.00 جم
ABE: Purchase of EGP 500.00 from Card **1104 at FATHALLA on 23/10. Avl Bal: EGP 3,200.00
28. بنك التنمية الصناعية (IDB)
BANK
بنك التنمية الصناعية: تم خصم 390.00 جم ببطاقة 2209 لدى فتح الله ماركت. الرصيد المتاح 4110.00 جم
IDB: Purchase of EGP 390.00 with card ending 2209 at FATHALLA MARKET. Avl Bal EGP 4,110.00
29. البنك العقاري المصري العربي (EALB)
BANK
البنك العقاري المصري العربي: تم خصم 290.00 جم من بطاقة **7741 لدى صيدلية سيف. الرصيد 2410.00 جم
EALB: EGP 290.00 debited from Card **7741 at SEIF PHARMACY. Avl Bal: EGP 2,410.00
30. البنك العربي (Arab Bank)
BANK
البنك العربي: عملية شراء بمبلغ 920.00 جم على بطاقة *6610 لدى LC WAIKIKI. الرصيد المتاح 14080.00 جم
Arab Bank: Purchase of EGP 920.00 on Card *6610 at LC WAIKIKI. Avl Balance EGP 14,080.00
31. بنك المؤسسة العربية المصرفية (Bank ABC)
BANK
بنك ABC: تم خصم 145.00 جم من بطاقتك **3812 لدى SPOTIFY EGYPT. الرصيد المتاح 3855.00 جم
Bank ABC: Your card **3812 was charged EGP 145.00 at SPOTIFY EGYPT. Avl Bal EGP 3,855.00
32. التجاري وفا بنك إيجيبت (Attijariwafa)
BANK
التجاري وفا بنك: عملية شراء بقيمة 430.00 جم ببطاقة ****5901 لدى BREADFAST. الرصيد المتاح 6570.00 جم
Attijariwafa: Purchase of EGP 430.00 using card ****5901 at BREADFAST. Avl Bal EGP 6,570.00
33. بنك المشرق مصر (Mashreq NEO)
BANK
بنك المشرق: تم خصم 135.00 جم ببطاقة تنتهي بـ 9044 لدى CAREEM EGYPT. الرصيد المتاح 4865.00 جم
Mashreq: EGP 135.00 spent on Card ending 9044 at CAREEM EGYPT. Avl Bal: EGP 4,865.00
34. سيتي بنك مصر (Citibank)
BANK
سيتي بنك: تم خصم 1450.00 جم على البطاقة المنتهية بـ 3011 لدى BOOKING.COM. الحد المتاح 25000.00 جم
Citi Alert: Card ending 3011 charged EGP 1,450.00 at BOOKING.COM on 23/10. Avl Limit EGP 25,000.00
35. المصرف العربي الدولي (AIB)
BANK
المصرف العربي الدولي: تم خصم 310.00 جم ببطاقة **4820 لدى محطة موبيل. الرصيد المتاح 7690.00 جم
AIB: Purchase of EGP 310.00 with Card **4820 at MOBIL STATION. Avl Bal EGP 7,690.00
36. بنك الاستثمار العربي (AIBK)
BANK
بنك الاستثمار العربي: تم خصم 550.00 جم من بطاقة ****1590 لدى راية. الرصيد المتاح 8450.00 جم
AIBK: Card ****1590 debited EGP 550.00 at RAYA MEGA STORE. Avl Bal: EGP 8,450.00
37. بلوم بنك مصر (BLOM Bank)
BANK
بلوم بنك: عملية شراء بقيمة 225.00 جم ببطاقة **7012 لدى فوكس سينما. الرصيد المتاح 3775.00 جم
BLOM: Purchase of EGP 225.00 on Card **7012 at VOX CINEMAS. Avl Bal EGP 3,775.00
38. ون بنك / البريد المصري (OneBank / Yalla)
BANK
البريد المصري/يلا: تم دفع 160.00 جم لدى فوري باستخدام بطاقة *4102. الرصيد المتاح 1340.00 جم
Yalla/EgyptPost: EGP 160.00 paid at FAWRY E-PAYMENT using Card *4102. Avl Bal EGP 1,340.00
InstaPay 1: تحويل صادر لعنوان دفع (IPA)
INSTAPAY
إنستاباي: تم تحويل مبلغ 1250.00 جم بنجاح إلى ahmed.ali@instapay من حسابكم *4567. المرجع: 62910482112
InstaPay: You transferred EGP 1,250.00 to ahmed.ali@instapay from A/C *4567. Ref: 62910482112
InstaPay 2: تحويل صادر لرقم موبايل
INSTAPAY
إنستاباي: تم تحويل 500.00 جم بنجاح إلى 01012345678 من بطاقة *1234. المرجع: IPN90812345
InstaPay: EGP 500.00 transferred to 01012345678 from Card *1234. Ref: IPN90812345
InstaPay 3: تحويل لحظي وارد (إيداع)
INSTAPAY
إنستاباي: تم إضافة تحويل لحظي بمبلغ 3500.00 جم إلى حسابكم *1234 من سارة محمود. المرجع: 62910998123
InstaPay: You received EGP 3,500.00 from SARA MAHMOUD into A/C *1234. Ref: 62910998123
InstaPay 4: دفع فواتير عبر إنستاباي
INSTAPAY
إنستاباي: تم دفع 420.00 جم لدى WE Home Internet ببطاقة *4567. المرجع: IPNBILL44102
InstaPay: You paid EGP 420.00 at WE Home Internet using Card *4567. Ref: IPNBILL44102
InstaPay 5: سداد بطاقة ائتمان
INSTAPAY
إنستاباي: تم تحويل 4000.00 جم إلى بطاقة *5555 لدى HSBC. المرجع: IPNCC77129
InstaPay: EGP 4,000.00 transferred to Card *5555 at HSBC. Ref: IPNCC77129
InstaPay 6: استرداد عملية مرفوضة
INSTAPAY
إنستاباي: تم رد 800.00 جم لحسابكم *4567. الرصيد المتاح 5200.00 جم
InstaPay: EGP 800.00 refunded to A/C *4567. Avl Bal EGP 5,200.00
فودافون كاش (Vodafone Cash)
WALLET
فودافون كاش: تم تحويل 500.00 جنيه إلى 01098765432. رصيدك الحالي 1240.00 جنيه
Vodafone Cash: EGP 500.00 transferred to 01098765432. Avl Bal: EGP 1,240.00
أورنج كاش (Orange Cash)
WALLET
أورنج كاش: تم دفع 180.00 جنيه لدى FAWRY. الرصيد المتاح 820.00 جنيه
Orange Cash: You paid EGP 180.00 at FAWRY. Avl Bal: EGP 820.00
إي آند كاش (e& money / Etisalat Cash)
WALLET
إي آند كاش: تم تحويل 250.00 جم إلى 01123456789. رصيدك الحالي 650.00 جم
e& money: EGP 250.00 transferred to 01123456789. Avl Bal EGP 650.00
وي باي (WE Pay)
WALLET
WE Pay: عملية شراء بقيمة 115.00 جم لدى كازيون. الرصيد المتاح 485.00 جم
WE Pay: Purchase of EGP 115.00 at KAZYON. Avl Bal: EGP 485.00
بطاقة تيلدا (Telda Card)
WALLET
تيلدا: تم دفع 140.00 جم لدى STARBUCKS ببطاقة *9910. الرصيد المتاح 2360.00 جم
Telda: You paid EGP 140.00 at STARBUCKS with Card *9910. Avl Bal EGP 2,360.00
ماي فوري وكليفر (myfawry / Klivvr)
WALLET
ماي فوري: تم خصم 310.00 جم ببطاقة *2019 لدى BREADFAST. الرصيد المتاح 1190.00 جم
myfawry: Purchase of EGP 310.00 with Card *2019 at BREADFAST. Avl Bal EGP 1,190.00
فاليو للتقسيط (valU BNPL)
BNPL
فاليو: تم دفع 1200.00 جم لدى تريدلاين. الحد المتاح 20000.00 جم
valU: You paid EGP 1,200.00 at TRADELINE. Avl limit: EGP 20,000.00
سيمبل للتقسيط (Sympl BNPL)
BNPL
سيمبل: تم خصم 450.00 جم لدى ZARA ببطاقة *1234. الرصيد المتاح 1350.00 جم
Sympl: Purchase of EGP 450.00 at ZARA with Card *1234. Avl Bal EGP 1,350.00
سهولة / شهري / أمان / فرصة (Souhoola / Aman)
BNPL
سهولة: عملية شراء بمبلغ 850.00 جم لدى بي تك. الحد المتاح 15000.00 جم
Souhoola: Purchase of EGP 850.00 at B.TECH. Avl limit EGP 15,000.00
8.1 Extracted Live Regex Extractor & Merchant Categorizer Code
Complete Regex Extraction & Auto-Categorization Logic (Extracted from Interactive SMS Lab):function normalizeDigits(str) {  const ar = ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'];  let out = str;  for (let i = 0; i < 10; i++) out = out.replace(new RegExp(ar[i], 'g'), String(i));  return out.replace(/٫/g, '.').replace(/ـ/g, '').replace(/(\d),(\d{3})/g, '$1$2');}// Named Regex Patterns:
• Direction Classifier: /تم رفض|تم رد|refunded|reversed|declined/i -> Refund | /تم إضافة|تحويل لحظي بمبلغ|received|credited/i -> Income | /تم تحويل|transferred to|sent to/i -> Transfer | Default -> Expense
• Amount Pattern: /(?:مبلغ|بقيمة|بمبلغ|خصم|دفع|تحويل|شراء|إضافة|رد|of|charged|paid|spent|transferred|received|EGP)\s*(?:EGP|USD|جم|ج\.م|جنيه)?\s*(\d+(?:\.\d{1,2})?)/i
• Card/Account Last 4 Pattern: /(?:بطاقة|بطاقتك|كارت|ببطاقة|حسابكم|ينتهي رقمها بـ|ينتهي بـ|المنتهية بـ|تنتهي بـ|[Cc]ard(?: ending(?: in)?)?|A\/C)\s*(?:فيزا|فوري الأصفر|تيلدا|Visa)?\s*[\*xX#\-]*\s*(\d{4})\b/
• Merchant/Counterparty Pattern: /(?:لدى|لدي|لتاجر|إلى|من|at|to|from)\s+([A-Za-z0-9\u0600-\u06FF\s\.\*&\-\_/@]{2,34}?)(?=\s+(?:يوم|بتاريخ|ببطاقة|باستخدام|من حساب|مرجع|المرجع|الرصيد|الحد|on|using|with|from|Ref|Avl|Balance|\.|$))/i
• Available Balance Pattern: /(?:الرصيد المتاح|الرصيد الحالي|رصيدك الحالي|الرصيد|الحد المتاح|Avl\.?\s*Bal(?:ance)?|Available\s*Balance|Avl\s*limit)[\s:]*?(?:EGP|جم|ج\.م|جنيه)?\s*(\d+(?:\.\d{1,2})?)/i
9. On-Device Technical Stack & Local SQLite (Drift) Database Schema
Architecture Layer
Selected On-Device Technology
Implementation Details & Purpose
Mobile UI & State Management
Flutter 3.x (Dart 3) + Riverpod 2.x
Bilingual RTL/LTR layout engine, Impeller 60fps animations, custom Zaghlol mascot Rive/Lottie animations, and home/lock screen widgets.
Local Encrypted Database
Drift ORM + sqflite_sqlcipher + SQLite FTS5
100% on-device AES-256 encrypted relational storage with Full-Text Search (FTS5) for instant millisecond transaction lookup.
Android Ingestion Engine
Native Kotlin BroadcastReceiver + NotificationListener
Scans historical SMS inbox on initial setup (READ_SMS) and intercepts live SMS (RECEIVE_SMS) and banking push notifications in background.
iOS 5-Channel Ingestion Engine
Swift AppIntents + ILMessageFilterExtension + Vision OCR
Handles Apple Shortcuts silent SMS/Apple Pay automations, unknown-sender SMS filtering, Back-Tap screenshot OCR, and Share Sheet via Shared App Group.
Voice & NLP Engine
speech_to_text (On-Device) + Zaghlol Arabic Parser
Offline/on-device Egyptian Arabic voice recognition converting spoken phrases ('دفعت ١٥٠ جنيه خضار') into structured expenses.
In-App Purchases & Entitlements
in_app_purchase (StoreKit 2 JWS + Play Billing v7)
Cryptographically verifies 'Zaghlol Gold' subscriptions on-device without a custom backend server.
Personal Cloud Backup & CSV
googleapis (Drive v3) + iCloud Storage + csv/excel
Client-side encrypted database snapshots (.zaghlol.enc) uploaded directly to user's Google Drive or iCloud Drive + UTF-8 BOM CSV export.
- 1. LocalUserProfile: id, display_name, payday_cycle_day (1-28), monthly_income_target, preferred_dialect ('eg_ar', 'en'), biometric_lock_enabled, is_gold_subscriber, gold_plan_type, last_gdrive_backup_at, last_csv_export_at.
- 2. AccountsAndCards: id, institution_code, account_type ('Debit', 'Credit', 'Account', 'Wallet', 'BNPL', 'Cash'), card_last_four, custom_label, current_balance, credit_limit, statement_due_day, currency.
- 3. Categories: id, name_en, name_ar, parent_category_id, budget_bucket ('Needs', 'Wants', 'Savings', 'Income'), icon_key, color_hex, is_system_default, sort_order.
- 4. MerchantNormalizationMap: id, raw_pattern_prefix, canonical_name_en, canonical_name_ar, default_category_id, is_user_override (1 = User Custom Rule, 0 = Bundled Seed), match_priority.
- 5. Transactions: id, account_id, raw_sms_body, sms_hash (SHA-256 deduplication key), raw_merchant_str, canonical_merchant_name, category_id, tx_type, amount, currency, amount_in_egp, balance_after, counterparty_ipa_or_phone, reference_no, is_internal_transfer, linked_transfer_tx_id, ingestion_source, tx_timestamp, is_user_verified.
- 6. ExpenseSplits: id, parent_transaction_id, offset_inbound_tx_id, participant_name, split_amount, is_settled, settled_at.
- 7. Budgets: id, category_id, monthly_limit_egp, alert_threshold_pct (default 80%), is_annual, rollover_enabled.
- 8. SubscriptionsAndBills: id, merchant_name, category_id, expected_amount, billing_frequency, next_due_date, remaining_installments, total_installments, auto_detected_from_sms, reminder_days_before.
- 9. WealthAssets: id, asset_type ('Gold_24K', 'Gold_21K', 'Gold_Coin', 'Bank_CD', 'Foreign_Currency', 'Real_Estate', 'Stocks_Thndr'), asset_name, quantity_or_grams, purchase_price_egp, current_unit_price_egp, annual_yield_pct, maturity_date, updated_at.
10. Flutter iOS/Android UI Guidelines, Bottom Bar Architecture & Captain Zaghlol Animation Engine
10.1 Fixing the Bottom Navigation Bar: Flutter Material 3 & iOS HIG Best Practices
Flutter NavigationBar (Android Material 3) & CupertinoTabBar (iOS HIG) + SafeArea Standards:
• Proper 5-Destination Stacked Architecture: Instead of flat inline text, the bottom bar implements Flutter's Material 3 NavigationBar / iOS CupertinoTabBar with 24dp vector icons stacked above 10pt Arabic typography.
• Active Destination Pill Indicator: The active tab displays a 48x24dp stadium-shaped pill (#D1FAE5 fill with #60B669 border and #174C4F icon/text) so the user always knows their exact location in the hierarchy.
• Central Docked FloatingActionButton (+ سجل / أصل): A 40dp circular Gold gradient button (#F0B33A -> #D97706) docked in the center for 2-second voice expense logging or adding a new Gold/Stock/Currency asset.
• SafeArea Bottom Inset & Gesture Home Indicator: A dedicated 20dp SafeArea bottom region containing the 124x4.5dp rounded OS Home Indicator pill, preventing overlap with iOS Home Bar or Android Gesture Navigation.
• LTR System Status Bar + Dynamic Island: The top status bar keeps clock ('9:41') and signal/battery indicators in standard system orientation around the iOS Dynamic Island / Android punch-hole camera while the app body runs in native RTL (Directionality(textDirection: TextDirection.rtl)).
Tab Index & Arabic Label
Flutter Widget & Icon
Target Feature Module
Platform Behavior (Android M3 vs. iOS HIG)
Tab 1: الرئيسية (Home)
NavigationDestination(icon: Icons.home_rounded)
Unified Multi-Account Dashboard, SMS Parser & InstaPay Match
M3 stadium indicator pill on Android; translucent blur CupertinoTabBar tint on iOS.
Tab 2: التحليلات (Charts)
NavigationDestination(icon: Icons.bar_chart_rounded)
12 Interactive Egyptian Arabic Charts, Payday Cycle Budget & BNPL Radar
Supports horizontal swipe between Charts, Budget Planner, and Installments Calendar.
Tab 3 (FAB): + سجل / أصل
FloatingActionButton(onPressed: openQuickSheet)
2-Second Egyptian Voice Cash Logger & New Asset Entry Modal
Triggers HapticFeedback.mediumImpact() and opens bottom modal sheet with Mic & Asset tabs.
Tab 4: الأصول والزكاة (Assets & Zakah)
NavigationDestination(icon: Icons.account_balance_rounded)
Multi-Asset Portfolio (Gold, Stocks, Currencies) & Native-Unit Zakah Calculator
Displays live Nisab (85g 24K Gold) badge and Hawl lunar countdown indicator.
Tab 5: الزغلول الذكي (Smart Coach)
NavigationDestination(icon: Badge(label: Text('8')))
Smart ROI Installment-vs-Expense Advisor (Coffee Machine Rule) & Local AI Chat
Shows active count of unread Smart ROI saving opportunities on badge.
10.2 Captain Zaghlol Character Animation Architecture (Rive State Machine + Flutter Impeller 60fps)
Replacing Static Mascot Images with Live Rive/Lottie Skeletal & Vector Animations:Every screen replaces static image placeholders with a reusable ZaghlolAnimatedAvatar Flutter widget powered by Rive (assets/rive/captain_zaghlol.riv) running at 60fps on Flutter's Impeller engine:
• Multi-Layer Skeletal Rig: Independent bone/vector layers for Body Bobbing, Wing Flapping, Eye Blinking, Magnifying Glass Scan, Orbiting 3D Gold Coins, and Golden Zakah Aura Ring.
• Audio-Synchronized Speech Equalizer: 5 animated vertical waveform bars next to the Rive state badge pulse in real time while the Egyptian Arabic speech bubble types out Captain Zaghlol's advice.
• Bundled Animated GIFs in ZIP Archive: In addition to live CSS/SVG animations in the HTML prototype, the companion ZIP archive includes multi-frame animated .gif captures in folder 00_Animated_GIF_UI_Screens/.
Rive State Machine Trigger
Visual Animation Behavior (60fps)
Screens Using This Animation State
Egyptian Persona Emotion
State 1: Wing_Wave_Greeting
Captain Zaghlol waves right wing, blinks warmly, and floats gently up/down (±5px).
Screen 01 (Onboarding), Screen 04 (Categorization), Screen 07 (Payday Budget), Screen 11 (iOS Setup)
Welcoming, reassuring mentor ('أهلاً بيك يا فنان!')
State 2: Proud_Coin_Bounce
Thumbs-up wing pose while 3 golden coins orbit and bounce around a glowing green aura ring.
Screen 02 (Dashboard), Screen 12 (Zaghlol Pro), Screen 14 (Privacy & Share), Screen 15 (Assets)
Proud, celebratory coach ('ما شاء الله! عاش يا بطل!')
State 3: Detective_Magnify_Scan
Leans forward with magnifying glass sweeping across SMS/InstaPay text with radar pulse rings.
Screen 03 (SMS Regex), Screen 05 (InstaPay Split), Screen 08 (BNPL Radar), Screen 13 (AI Chat)
Sharp financial detective ('قفشت رسالة جديدة!')
State 4: Shocked_Wing_Flutter
Feathers puff up, eyes widen, and red/amber warning waves pulse behind the avatar.
Screen 06 (12 Charts Burn-Rate Alert) & Over-Budget Category Warnings
Humorous Egyptian shock ('يا نهار أبيض! الدليفري واكل المرتب!')
State 5: Smart_ROI_Bulb_Glow
Glowing golden lightbulb + coffee cup icon morphing into a stack of saved banknotes.
Screen 09 (Smart ROI & Coffee Machine Installment Advisor)
Clever investment strategist ('هات ماكينة بالتقسيط ووفر 14,400 ج!')
State 6: Zakah_Blessing_Aura
Serene emerald-and-gold geometric halo rotating smoothly with balance scale sparkle.
Screen 16 (Native-Unit Zakah & Hawl Calculator)
Trustworthy, precise advisor ('حسبتلك زكاة كل أصل بعملته وتكلفته!')
11. Multi-Asset Wealth Portfolio & Native-Unit Zakah Calculator (Zero Currency Conversion)
Core Requirement: Calculate Zakah Across Gold, Stocks & Multi-Currency Cash Without Forced Conversion:Users frequently hold diverse assets: Gold in different karats (24K bars, 21K coins/jewelry, 18K), Stocks (EGX in EGP, US stocks in USD), and Cash in multiple currencies (USD, SAR, EUR, EGP). Converting everything into a single currency confuses users who want to pay Zakah out of each asset class natively or know the exact Zakah cost of each individual item.How Zaghlol's Native-Unit Zakah Engine Works:1. Global Nisab Eligibility Check (نصاب الذهب الشرعي = 85 جرام ذهب عيار 24): Internally checks whether the user's combined net zakatable wealth (after subtracting immediate short-term due installments/debts) meets or exceeds the value of 85 grams of 24K Gold and whether each asset lot has completed 1 Hijri Lunar Year (الحول = 354 يوماً).2. Zero-Conversion Native Zakah Output (إخراج الزكاة من جنس كل أصل وبتكلفته الفردية): Once eligible, Zaghlol does NOT collapse the output into a single currency. Instead, it calculates 2.5% (ربع العشر) of each eligible item in its own native unit (grams of 24K/21K gold, USD, SAR, EUR, EGP) AND displays the exact market cost of that item's Zakah share side-by-side.
Asset Item & Native Holding
Hawl (354 Days) & Eligibility
Native Zakah Due (2.5% Without Currency Conversion)
Current Cost / Value of This Zakah Item
Shariah & Financial Calculation Rule
Gold 24K Bars (سبائك ذهب عيار 24)Holding: 50.0 Grams
✅ Eligible(Hawl: 390 days)
1.25 Grams of 24K Gold(50g × 2.5%)
5,350 EGP(at 4,280 EGP / gram 24K)
Evaluated in pure 24K grams; user can give 1.25g gold or its exact day-of-payment cash cost (5,350 EGP).
Gold 21K Coins/Savings (ذهب عيار 21)Holding: 120.0 Grams
✅ Eligible(Hawl: 410 days)
3.00 Grams of 21K Gold(120g × 2.5%)
11,250 EGP(at 3,750 EGP / gram 21K)
Preserves native 21K gram weight (equivalent to 105g of 24K pure gold for Nisab aggregation).
Gold 18K Savings (ذهب عيار 18)Holding: 40.0 Grams
⏳ Not Due Yet(Hawl: 120 / 354 days)
0.00 Grams Now(1.00g due in 234 Hijri days)
0 EGP Due Today(Future est.: 3,210 EGP)
Tracked in Hawl countdown ledger; excluded from immediate Zakah payout until 354 lunar days pass.
US Dollar Cash & US Trading StocksHolding: $8,000 Cash + $4,000 Stocks = $12,000 USD
✅ Eligible(Hawl: 365+ days)
$300.00 USD($12,000 × 2.5%)
$300.00 USD natively(or 14,850 EGP at 49.50)
Computed directly in US Dollars ($200 USD cash Zakah + $100 USD stock Zakah) without forced EGP conversion.
Saudi Riyal Cash Savings (ريال سعودي)Holding: 12,000 SAR
✅ Eligible(Hawl: 360 days)
300.00 SAR(12,000 SAR × 2.5%)
300.00 SAR natively(or 3,960 EGP at 13.20)
Computed directly in Saudi Riyals (300 SAR) so user can pay Zakah directly from SAR wallet/cash.
EGX Trading Stocks (أسهم البورصة - Thndr)Holding: 100,000 EGP Market Value
✅ Eligible(Active Trading Portfolio)
2,500.00 EGP(100,000 EGP × 2.5%)
2,500.00 EGP(Market Value × 2.5%)
Trading stocks (أسهم المضاربة) are zakatable at 2.5% of current market value; long-term yield stocks use dividend/liquid-asset ratio.
EGP Cash & Bank Accounts (كاش وودائع)Gross: 240,000 EGP − 20,000 EGP Due Debt = 220,000 EGP
✅ Eligible(Net of Short-Term Debt)
5,500.00 EGP(220,000 EGP × 2.5%)
5,500.00 EGP(After deducting due BNPL/bills)
Automatically deducts immediate due liabilities (20,000 EGP) before computing 2.5% net cash Zakah.
11.1 Extended SQLite Schema for Multi-Asset Portfolio & Native Zakah Ledger
Table Name
Columns & Types
Local Zakah & Asset Calculation Purpose
WealthAssets_v2
id, asset_category ('GOLD','CURRENCY','STOCK','FUND'), sub_type ('24K','21K','18K','USD','SAR','EUR','EGP','EGX_TRADING','US_TRADING'), title, quantity_native, unit_label ('gram','USD','SAR','EUR','EGP','shares'), current_unit_price_in_native, local_egp_reference_price, acquisition_date_gregorian, acquisition_date_hijri, hawl_days_elapsed, is_zakatable_intent (1/0).
Stores each asset in its exact native unit and currency without forcing conversion into a single base currency.
ZakahCalculationItems
id, snapshot_date, asset_id, is_nisab_reached (1/0), is_hawl_completed (1/0), native_zakah_amount (quantity_native * 0.025), native_unit_label, item_zakah_cost_in_native, item_zakah_cost_in_egp, payment_status ('PENDING','PAID_PARTIAL','PAID_FULL').
Outputs the per-item Zakah breakdown showing both native Zakah units (e.g., 3.0g 21K Gold, $300 USD) and each item's exact cost.
12. Captain Zaghlol Smart ROI & Installment-vs-Expense Financial Advice Engine
Behavioral FinTech Innovation: Converting High Recurring Expenses into Owned Assets via Installments (CapEx vs. OpEx):Traditional expense trackers only say 'You spent too much on coffee.' Captain Zaghlol acts as a proactive financial analyst: when recurring spending in a category exceeds an algorithmic threshold, the engine calculates how buying a home appliance, pass, or asset on monthly installments costs LESS per month than the habit itself—and generates a shareable 1-Year & 2-Year Net Savings Projection!
# & Smart Advice Rule
SMS / Spending Detection Trigger
Current Habit Cost (1 Year)
Smart Installment / Asset Alternative
Net Savings After 1 Year (& Year 2)
1. The Coffee Machine Installment Rule(قاعدة ماكينة القهوة بالتقسيط)
Monthly spend at cafes (Starbucks, Costa, Cilantro, TBS) > 2,000 EGP/mo (Detected: 2,450 EGP/mo)
29,400 EGP / year(2,450 EGP × 12 mos)
Buy a De'Longhi / Nespresso machine (9,600 EGP) on 12-mo 0% installment (800 EGP/mo) + specialty beans & milk (450 EGP/mo) = 1,250 EGP/mo.
Save +14,400 EGP in Year 1 + own the 9,600 EGP machine!(Save +24,000 EGP/yr in Year 2!)
2. The Air Fryer & Meal-Prep Rule(قاعدة الإيرفراير بدل الدليفري اليومي)
Monthly fast-food & Talabat/Breadfast delivery > 3,500 EGP/mo (Detected: 3,800 EGP/mo + 14 delivery fees)
45,600 EGP / year(3,800 EGP × 12 mos)
Buy a Dual-Zone Air Fryer (5,400 EGP on 6-mo 0% installment = 900 EGP/mo for 6 mos) + premium home groceries (1,500 EGP/mo).
Save +19,500 EGP in Year 1 + own the Air Fryer!(Save +27,600 EGP/yr in Year 2!)
3. The 7-Stage RO Water Filter Rule(قاعدة فلتر المياه بدل القوارير)
Monthly bottled water & gallon delivery > 600 EGP/mo (Detected: 700 EGP/mo)
8,400 EGP / year(700 EGP × 12 mos)
Install a 7-Stage RO Water Filter (4,200 EGP on 6-mo installment = 700 EGP/mo for 6 mos + 800 EGP annual filter candles).
Break even in Month 6; Save +3,400 EGP in Year 1!(Save +7,600 EGP/yr in Year 2!)
4. The Idle Cash Daily-Yield Rule(قاعدة تشغيل الكاش الراكد في صندوق يومي)
Debit/current account holds > 30,000 EGP idle above monthly budget for >20 days at 0% return
0 EGP return(Loses purchasing power to inflation)
Move 35,000 EGP surplus into a Shariah-compliant Daily Cumulative Money Market Fund (~22% annual yield, instant daily liquidity).
Earn +7,700 EGP after 1 Year in passive halal yield with zero lock-up!
5. The Commuter E-Scooter / Pass Rule(قاعدة مشاوير أوبر اليومية المتكررة)
Monthly Uber / Careem / InDrive short trips > 4,500 EGP/mo (Detected: 4,800 EGP/mo)
57,600 EGP / year(4,800 EGP × 12 mos)
Acquire an Electric Scooter / Micro-Mobility plan on 12-mo installment (1,650 EGP/mo) + Metro/Carpool for long routes (800 EGP/mo).
Save +28,200 EGP after 1 Year + own the scooter debt-free!
6. Credit Card Revolving Interest Trap(قاعدة سداد الكريدت كارد من الكاش الفائض)
Paying 5% minimum on Credit Card (12,000 EGP revolving balance at ~3.5%/mo) while holding >15k EGP cash
-5,040 EGP / yearin wasted bank interest
Immediately settle the 12,000 EGP credit card statement in full using idle debit balance before statement due day.
Save +5,040 EGP after 1 Year in avoided compounding bank penalties!
7. Duplicate Streaming & Gym Annual Rule(قاعدة تجميع الاشتراكات والباقات السنوية)
Paying 4 separate monthly media/gym renewals > 950 EGP/mo (11,400 EGP/yr)
11,400 EGP / yearin fragmented monthly renewals
Switch to 1 shared Family Annual Plan + annual gym membership on 0% installment (500 EGP/mo equivalent).
Save +5,400 EGP after 1 Year for the exact same access!
8. Payday Wholesale Staples Hedge(قاعدة خزين البيت بالجملة يوم القبض)
6+ small convenience-store grocery runs/month for oil, rice, detergents at +22% retail markup (4,200 EGP/mo)
50,400 EGP / yearat neighborhood retail prices
Buy non-perishable household staples once on Payday (Day 25) from wholesale hypermarkets (Kazyon/HyperOne) for 3,500 EGP/mo.
Save +8,400 EGP after 1 Year on identical family consumption!
13. High-Resolution Rendered UI Screens (01–16) & Egyptian Social Media Marketing Cards (01–10)
All 16 redesigned mobile UI screens below feature the Animated Captain Zaghlol Rive/Lottie stage (with live state-machine badges, golden aura rings, orbiting coin particles, and audio waveform bars) and the corrected Flutter Material 3 NavigationBar / iOS CupertinoTabBar + SafeArea Home Indicator bar. All images and multi-frame animated GIFs are also packaged in Zaghlol_UI_Screens_and_Marketing_Images.zip.
13.1 Complete 16-Screen Mobile UI Visual Gallery (2×2 Presentation Sheets)
Figure 13.1 — Screens 01 to 04: Onboarding & Permissions, Unified Multi-Account Dashboard, Live SMS Regex Inspector, and Smart Categorization Rules (with Animated Captain Zaghlol & Flutter M3/HIG Bottom Navigation Bar).
Figure 13.2 — Screens 05 to 08: InstaPay Self-Transfer & Dish Party Split, 12 Interactive Charts Gallery, Custom Payday Cycle Planner, and Subscriptions/BNPL/Gameya Radar.
Figure 13.3 — Screens 09 to 12: Smart ROI & Coffee Machine Installment Advisor (>2k EGP Coffee Rule saving 14,400 EGP/yr), 2-Second Voice Cash Logger, iOS Auto-Sync Wizard, and Zaghlol Pro Paywall.
Figure 13.4 — Screens 13 to 16: Ask Captain Zaghlol AI Chat, Biometric Privacy & 1-Year Coffee Savings Share Card, Multi-Asset Wealth Portfolio (Gold, Stocks, Currencies), and Native-Unit Zakah & Hawl Calculator.
13.2 Side-by-Side Individual Mobile Screen Renders (All 16 Screens)
Screen 01: Screen 01 Onboarding Permissions
Screen 02: Screen 02 Unified Dashboard
Screen 03: Screen 03 Sms Regex Inspector
Screen 04: Screen 04 Smart Categorization
Screen 05: Screen 05 Instapay Reconciliation
Screen 06: Screen 06 Egyptian Charts Gallery
Screen 07: Screen 07 Payday Budget Planner
Screen 08: Screen 08 Subscriptions Bnpl Radar
Screen 09: Screen 09 Captain Zaghlol Coach
Screen 10: Screen 10 Voice Manual Cash Logger
Screen 11: Screen 11 Ios Setup Clipboard Wizard
Screen 12: Screen 12 Zaghlol Pro Paywall
Screen 13: Screen 13 Local Ai Chat Assistant
Screen 14: Screen 14 Security Viral Share
Screen 15: Screen 15 Multi Asset Wealth Portfolio
Screen 16: Screen 16 Native Zakah Calculator
13.3 Egyptian Arabic Social Media Marketing Campaign Cards (01–10)
Figure 13.5 — Social Media Marketing Campaign Sheet 1 (Egyptian Arabic Promotional Cards 01–04).
Figure 13.6 — Social Media Marketing Campaign Sheet 2 (Egyptian Arabic Promotional Cards 05–08).
Figure 13.7 — Social Media Marketing Campaign Sheet 3 (Egyptian Arabic Promotional Cards 09–10 (Coffee Machine ROI & Native Zakah)).
Campaign Card 01: Social Box 01 Salary Mystery
Campaign Card 02: Social Box 02 Instapay Detective
Campaign Card 03: Social Box 03 Zero Server Privacy
Campaign Card 04: Social Box 04 Coffee Delivery Shock
Campaign Card 05: Social Box 05 All 38 Banks
Campaign Card 06: Social Box 06 Gameya Installments
Campaign Card 07: Social Box 07 Voice Cash Logger
Campaign Card 08: Social Box 08 Pro Excel Drive
Campaign Card 09: Social Box 09 Coffee Machine Roi
Campaign Card 10: Social Box 10 Native Zakah Calculator