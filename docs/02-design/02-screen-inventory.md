# 02 — Screen Inventory

One canonical numbering for the app (`S-##`). Groups are numbered by tens so related screens stay together. Type: **Screen** (full page, pushed), **Sheet** (bottom sheet / modal), **Overlay** (full-screen modal), **Tab** (bottom-nav root).

Tier: F = Free, G = Gold, F/G = both with limits. Flag = hidden unless remote feature flag on.

| ID | Name (EN) | الاسم (AR) | Type | Tier | Main requirements | Spec screen (§13 / §5) |
|----|-----------|-----------|------|------|-------------------|------------------------|
| **Onboarding & security** ||||||| 
| S-01 | Welcome & privacy | أهلاً بيك | Screen | F | FR-ONB-01/02/12 | 13-01 / 5-1 |
| S-02 | Capture setup — Android | إعداد اللقط — أندرويد | Screen (stepper) | F | FR-ONB-05/06, FR-ING-A-01…05 | 13-01 / 5-2 |
| S-03 | Capture setup — iOS | إعداد اللقط — آيفون | Screen (stepper) | F | FR-ONB-05, FR-ING-I-01…08 | 13-11 / 5-2 |
| S-04 | Restore from backup | استرجاع نسخة | Screen | F/G | FR-BAK-03/07, FR-ONB-12 | — |
| S-06 | Scan results — cards found | دي كروتك؟ | Screen / sheet | F | FR-ONB-06, FR-ACC-01/05, FR-CAP-01, FR-ING-A-06 | — (see 07-flows) |
| S-05 | App lock | قفل التطبيق | Overlay | F | FR-SEC-02, FR-ONB-04 | 13-14 / 5-1 |
| **Home & transactions** ||||||| 
| S-10 | Home | الرئيسية | Tab | F | FR-HOME-01…05, FR-CUR-03/04, FR-CARD-01 | 13-02 / 5-3 |
| S-11 | Transactions (list & search) | الحركات | Screen | F | FR-TXN-01/03, FR-CARD-01/04 | — |
| S-12 | Transaction detail | تفاصيل الحركة | Screen | F | FR-TXN-02…05, FR-XFR-02/06/09, FR-CAT-05 | 13-03 / 5-4 |
| S-13 | Add / edit transaction | إضافة / تعديل حركة | Sheet (full-height) | F | FR-TXN-02/04, FR-CARD-05 | — |
| S-14 | Review queue | محتاج مراجعة | Screen | F | FR-CAT-04, FR-ING-A-06, FR-PAR-06/13/14, BR-XFR-02 | 13-04 / 5-5 |
| S-15 | Split & reimbursements | تقسيم وفلوس راجعة | Sheet | F | FR-XFR-04…09 | 13-05 / 5-8 |
| S-16 | Link as my transfer | ربط تحويلة لنفسي | Sheet | F | FR-XFR-02, FR-CUR-06 | 13-05 / 5-8 |
| **Insights (tab 2)** ||||||| 
| S-20 | Charts | الشارتات | Tab segment | F/G | FR-CHT-01/02/04/05 | 13-06 / 5-7 |
| S-21 | Chart detail & explanation | شرح الشارت | Screen | F/G | FR-CHT-03/05/06, FR-MAS-01 | 13-06 / 5-7 |
| S-22 | Budget | الميزانية | Tab segment | F | FR-BUD-01…06 | 13-07 / 5-9 |
| S-23 | Edit budgets | تعديل الميزانية | Screen | F | FR-BUD-02/03/05/06 | 13-07 |
| S-24 | Bills & installments | الفواتير والأقساط | Tab segment | F | FR-SUB-01…05 | 13-08 / 5-10 |
| S-25 | Add / edit bill or installment | إضافة قسط / اشتراك | Sheet | F | FR-SUB-03/04 | 13-08 |
| **Quick add (FAB)** ||||||| 
| S-30 | Quick add | سجل بسرعة | Sheet | F | FR-HOME-04 | 13-10 |
| S-31 | Voice logger | قول لزغلول | Overlay | F/G | FR-VOI-01…05 | 13-10 / 5-6 |
| S-32 | Scan screenshot / receipt | قراءة سكرين شوت | Screen | F | FR-ING-I-04 | 13-11 |
| **Money (tab 4)** ||||||| 
| S-40 | Money overview | فلوسي | Tab | F/G | FR-WLT-01/05, FR-ACC-01…06 | 13-15 / 5-11 |
| S-41 | Card / account detail | تفاصيل الكارت | Screen | F | FR-CARD-02/04, FR-ACC-02/05/06 | — |
| S-42 | Compare cards | مقارنة الكروت | Screen | F | FR-CARD-03 | — |
| S-43 | Edit card / account | تعديل الحساب | Sheet | F | FR-ACC-01/04/05 | — |
| S-44 | Add / edit asset | إضافة أصل | Screen | G | FR-WLT-02/04 | 13-15 / 5-11 |
| S-45 | Prices (gold & currencies) | الأسعار | Screen | G | FR-WLT-03 | 13-15 |
| S-46 | Zakah | الزكاة | Screen | G · Flag | FR-ZAK-01…06 | 13-16 |
| **Zaghlol (tab 5)** ||||||| 
| S-50 | Ask Zaghlol | اسأل زغلول | Tab | F | FR-CHAT-01…05 | 13-13 / 5-12 |
| S-51 | Smart ROI tips | نصايح زغلول الذكية | Tab segment | G · Flag | FR-ROI-01…04 | 13-09 |
| **Settings & utilities** ||||||| 
| S-60 | Settings | الإعدادات | Screen | F | FR-ONB-07 | — |
| S-61 | Capture settings | إعدادات اللقط | Screen | F | FR-CAP-03/05/06/07, FR-ING-A-05, FR-ING-I-07, FR-PAR-14 | 13-11 |
| S-62 | Card capture controls | لقط الكارت | Sheet | F | FR-CAP-01/02/04 | — |
| S-63 | Categories & rules | الفئات والقواعد | Screen | F/G | FR-CAT-07/08/09 | 13-04 |
| S-64 | Edit category | تعديل فئة | Sheet | G | FR-CAT-07 | — |
| S-65 | Custom message template | قالب رسالة مخصص | Screen | G | FR-PAR-07 | — |
| S-66 | Backup & restore | النسخ الاحتياطي | Screen | F/G | FR-BAK-01…09 | 13-12 / 5-13 |
| S-67 | Export & import | تصدير واستيراد | Screen | F/G | FR-EXP-01…07 | 13-12 / 5-13 |
| S-68 | Zaghlol Gold (paywall) | زغلول جولد | Overlay | — | FR-GOLD-01…05 | 13-12 / 5-13 |
| S-69 | Account & subscription | الحساب والاشتراك | Screen | — | FR-ACCT-01…04, FR-GOLD-03/06/07 | — |
| S-70 | Notifications | الإشعارات | Screen | F | FR-NTF-01…03 | — |
| S-71 | Privacy & data | الخصوصية وبياناتك | Screen | F | FR-ONB-08, FR-CAT-09, NFR-PRIV | 13-14 |
| S-72 | Preferences | التفضيلات | Screen | F | FR-ONB-03/04, FR-L10N-01/03, FR-CUR-02/04/05 | — |
| S-73 | Share studio | شارك إنجازك | Overlay | F | FR-SHR-01…03 | 13-14 / 5-14 |
| S-74 | About | عن زغلول | Screen | F | FR-SYNC-06 | — |

**Home-screen widget** (FR-WID-01/02) is specified in `screens/80-widget.md` as W-01/W-02.

**Total:** 46 screens/sheets + 2 widgets (S-06 added in 07-flows-onboarding-cards-import.md). Flagged: S-46, S-51.

## Spec screens → this inventory
| Spec §13 | → |
|---|---|
| 01 Onboarding & permissions | S-01, S-02, S-05 |
| 02 Unified dashboard | S-10 |
| 03 SMS regex inspector | S-12 ("How Zaghlol read this" section) |
| 04 Smart categorization | S-14, S-63 |
| 05 InstaPay reconciliation & split | S-15, S-16 |
| 06 Charts gallery | S-20, S-21 |
| 07 Payday budget planner | S-22, S-23 |
| 08 Subscriptions / BNPL / gameya radar | S-24, S-25 |
| 09 Captain Zaghlol coach (Smart ROI) | S-51 (flag) |
| 10 Voice & manual cash logger | S-30, S-31, S-13 |
| 11 iOS setup & clipboard wizard | S-03, S-61 |
| 12 Zaghlol Pro paywall | S-68 (named Zaghlol Gold) |
| 13 Local AI chat | S-50 |
| 14 Security & viral share | S-05, S-71, S-73 |
| 15 Multi-asset wealth | S-40, S-44, S-45 |
| 16 Native Zakah | S-46 (flag) |

Spec §5's "SMS regex lab — try 38 banks yourself" demo is **not** included: no approved requirement asks for a parser playground (the parsing transparency need is met by S-12's "How Zaghlol read this").
