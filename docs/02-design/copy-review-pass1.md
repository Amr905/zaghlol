# T-058 — Arabic copy review, pass 1 (expert pre-review)

| | |
|---|---|
| Date | 2026-11-18 |
| Scope | Every value in `app/lib/core/l10n/app_ar.arb`, checked against `app_en.arb`, `copy-deck.md` and `06-voice-and-tone.md` |
| Status | **Pre-review only.** This doesn't replace the native Egyptian-speaker sign-off that FR-L10N-02 requires. |
| Checked for | Egyptian colloquial outside legal text and disclaimers; natural Cairene wording; the same word for the same thing; consistent form of address; ICU plurals and placeholders; meaning matches EN; length; tone |

How to use this file: section 1 lists what pass 1 already changed, so the reviewer can confirm or undo each change. Section 2 lists the judgement calls that pass 1 left alone; each row needs a decision. Section 3 lists places where the deck and the ARB files disagree.

---

## 1. Fixed in pass 1 (54 keys)

Every change keeps the key, the placeholders and the plural/select structure. The matching AR cell in `copy-deck.md` was updated wherever the deck has a row for the key.

| Key | Before | After | Why |
|---|---|---|---|
| commonActionMore | المزيد | أكتر | MSA |
| commonActionShow | اظهر | اعرض | «اظهر» means "appear" (intransitive), not "show it" |
| commonErrorSaveFailed | محصلش حفظ. … | مقدرتش أحفظ. … | Unnatural; now matches the other "couldn't save" lines |
| onboardingIosSetupFirstTypeHint | المبلغ والفئة | المبلغ والتصنيف | «فئة» is MSA; the glossary term is «التصنيف» |
| onboardingIosSetupFirstStatementSub | ضيف شهور فاتت مرة واحدة | … مع جولد | EN and the note say Gold (F-8); AR left it out, which promises Free users a Gold feature |
| onboardingAndroidSetupSmsPointSenders | بنقرا … | بقرا … | EN says "I"; Zaghlol speaks in the first person singular on this screen |
| onboardingAndroidSetupSmsAllow | اسمح بقراءة رسايل البنك | اسمح بقراية الرسايل | MSA «قراءة»; now matches the deck |
| onboardingAndroidSetupSmsPointOnPhone | كل حاجة بتفضل على الموبايل ده | بيانات فلوسك بتفضل على الموبايل ده | **Privacy claim was too broad** (tone gate 4, R-11). Now matches the deck |
| onboardingIosSetupShortcutTitle | الآيفون مش بيسمح … فهنستخدم الاختصارات | هنستخدم الاختصارات | Repeated `shortcutWhy` word for word; the deck shortened it (F-7). **EN ARB is still the long form; align it to "We'll use Shortcuts".** |
| onboardingIosSetupHowItWorks | (٣٠ ثانية) | (نص دقيقة) | No digits in AR copy (§0.3); matches the deck |
| onboardingIosSetupFixStep1 | افتح Shortcuts ← Automation | افتح Shortcuts وبعدين Automation | No arrows in AR text (§0.6); matches the deck |
| onboardingIosSetupFirstSayHint | «دفعت ٤٥ قهوة» | «دفعت خمسة وأربعين قهوة» | Spoken example must use number words (§0.3); matches the deck |
| onboardingIosSetupFirstOnlineBanksSub | تسجلهم | تتابعهم | Matches the deck and EN ("track") |
| homeHeroDaysToPayday | يوم على القبض … | فاضل يوم على القبض … | Fragment without «فاضل» reads oddly; matches the deck |
| transfersSplitErrorShareZero | النصيب لازم … | كل نصيب لازم … | EN "Each share" |
| accountsOverviewCashSub | يدوي وصوت | بإيدك وبصوتك | MSA «يدوي»; the app uses «بإيدك» elsewhere |
| insightsChartTitleVsAverage | … ضد متوسط … | … قصاد متوسط … | «ضد» is a calque of "vs" |
| insightsChartA11yVsAverage | … ضد متوسطك | … قصاد متوسطك | Same as above |
| insightsChartsEmptyCycle | بيحيا بعد أول دورة كاملة | هيشتغل بعد أول دورة كاملة | Literal "comes alive"; not natural |
| insightsExplainCashFlowTip | … هيساعدك ده تقفل الفرق / للادخار | … ، ده هيساعدك تقفل الفرق / للتحويش | Word order; MSA «ادخار» → «تحويش» (chart legend term) |
| insightsExplainCategoriesDeepTip | خفّض | قلّل | MSA |
| insightsExplainBurnRateDeepTip | لو خفضت | لو قللت | MSA |
| insightsExplainSubscriptionsTip | إلغاؤه بيوفر | الغيه وهتوفر | MSA verbal noun with hamza |
| insightsExplainNetWorthDeep (up) | نموك الإجمالي {percent} | اللي حيلتك زاد {percent} | MSA; now the same wording as the `down` branch and the glossary |
| homeQuickAddVoiceLeft | باقيلك | فاضلك | Glossary «فاضلك» |
| captureScanTitle | قراءة سكرين شوت | اقرا سكرين شوت | MSA; matches `homeQuickAddScanA11y` |
| captureScanUnavailableBody | اكتب العملية | اكتب الحركة | Transaction = «حركة» everywhere else |
| chatMainRoast | إقصف جبهتي | اقصف جبهتي | Spelling: the imperative takes no hamza |
| chatAnswerBalanceCredit | المتاح في … | فاضل في … | Glossary «فاضل في الكارت» |
| roiRuleCoffeeBody | الحليب | اللبن | «حليب» isn't the Egyptian word for milk |
| roiRuleWaterTitle | فلتر مياه بدل القوارير | فلتر مية بدل الإزايز | «قوارير / مياه» aren't Egyptian; Egyptians say «إزايز المية» |
| roiRuleWaterBody | القوارير … فلتر مياه | إزايز المية … فلتر مية | Same as above |
| categoriesEditBucketNeeds | ضروريات | أساسيات | Same bucket as chart 4, which says «أساسيات» |
| categoriesEditBucketWants | رغبات | رفاهيات | Same bucket as chart 4, which says «رفاهيات» |
| categoriesEditBucketSavings | ادخار | تحويش | Same bucket as chart 4, which says «تحويش»; MSA |
| categoriesEditTitleEdit | تعديل التصنيف | عدّل التصنيف | Every other edit title is an imperative («عدّل الحركة») |
| backupSettingsAuto | نسخة تلقائي | نسخ تلقائي | Gender agreement; matches `backupSettingsAutoLocked` |
| backupPassphraseMismatch | كلمتين السر مش زي بعض | كلمة السر في الخانتين مش زي بعض | Ungrammatical |
| exportsImportUntracked (many/other) | كارت مش متتبعة (هتتخطى) | كارت مش متتبعين (هيتخطوا) | «كارت» is masculine; the plural count takes a plural verb |
| exportsImportLockedBody | فاتتة | فاتت | Typo |
| goldPaywallPlanRequired | اختار خطة | اختار باقة | The app says «باقة» for a plan everywhere else |
| goldSeatAccountRequiredBody | اعمل تسجيل دخول | سجّل دخول | Clunky; matches `commonActionSignIn` |
| goldSeatPausedBody | اعمل تسجيل دخول | سجّل دخول | Same as above |
| goldSeatHeldElsewhereAccount | اعمل تسجيل دخول | سجّل دخول | Same as above |
| notificationsSettingsDueDays (=0) | يوم الاستحقاق نفسه | يوم الميعاد نفسه | MSA; matches `recurringBillEditRemind` |
| notificationsSettingsDaysRange | يوم الاستحقاق | يوم الميعاد | Same as above |
| notificationsAlertDue (=1) | بكره | بكرة | Same spelling as every other «بكرة» in the app |
| notificationsAlertDuplicate | بُص | بص | Stray diacritic; no other string uses it |
| privacyDeleteFailed | افتح الأبلكيشن | افتح زغلول | The app never says «الأبلكيشن» anywhere else |
| shareStudioShowAmounts | اظهر المبالغ | اعرض المبالغ | Same issue as `commonActionShow` |
| errorsStorageIo | قراءة | قراية | MSA spelling; the app uses «قراية» elsewhere |
| transactionsEditLinksRemoved | بالمعاملة دي | بالحركة دي | Transaction = «حركة» |
| homeFeedExcludedFromSpending | المصروفات | المصاريف | Same phrase is «المصاريف» in `transactionsRowInternalSubtitle` |
| transactionsReimbUnassigned | only `=1` and `other` | added `=2`, `few`, `many`; `other` → «مبلغ» | Arabic plurals were incomplete («١٥ مبالغ» was wrong) |

---

## 2. Judgement calls for the reviewer (not changed)

| Key | Current | Suggested | Why |
|---|---|---|---|
| commonActionCancel | إلغاء | الغي | MSA verbal noun on a button; but «إلغاء» is the term every Egyptian app uses. Keep or change? |
| commonActionSkip | تخطي | فوّت | MSA |
| commonActionUndo | تراجع | رجّعها | MSA; snackbar action |
| commonActionManage, goldAccountManage | إدارة / إدارة الاشتراك | ظبّط / ظبّط الاشتراك | MSA noun on an action |
| homeQuickAddAsset, homeQuickAddAssetA11y, accountsOverviewAddAsset, wealthAssetTitleAdd, wealthAssetTitleEdit, wealthAssetSaved, zakahMainEmptyAdd | أصل | e.g. «دهب أو شهادة» / keep «أصل» | Glossary avoids «الأصول» in favour of «دهبك وشهاداتك», but a short singular noun is still needed. Pick one and use it everywhere |
| backupRestoreTitle, backupSettingsRestore | استرجاع نسخة | رجّع نسخة | MSA verbal noun |
| appLockUnavailable, appLockRootedTitle, appLockRootedBody | تليفون | موبايل | Every other string says «موبايل» |
| appLockFailed / securityLockFailed | مظبطتش / مفتحش | Use one wording in both | Same moment, two different lines |
| onboardingWelcomePointNoPassword, appLockUnavailable vs backup*Passphrase* | باسورد / كلمة السر | Keep both? | Bank password = «باسورد», backup passphrase = «كلمة السر». Fine if the difference is intentional; please confirm |
| captureIgnoreChannels | متقراش من: | وقّف القراية من: | Reads as an order to the user ("don't you read") when Zaghlol is the one reading |
| transfersSplitErrorSharesExceed | مجموع الأنصبة أكبر من المصروف | اللي على الناس أكبر من المصروف | «الأنصبة» is heavy MSA |
| transfersLinkTitle | ربط تحويلة لنفسي | اربط تحويلة لنفسي | Other titles are imperatives |
| insightsChartDetailLegendRowA11y, insightsChartDetailCardRowA11y, accountsHiddenRowA11y | اضغط | دوس | Visible copy says «دوس» (`onboardingScanResultsNotMineHint`, `captureShareHowStep2`, `templatesBuilderTapHint`). Pick one verb |
| insightsExplainCashFlowDeepTip | ثبّت هدف تحوّش {target} كل دورة | خلّي هدفك تحوّش {target} كل دورة | Awkward noun phrase |
| transactionsDetailHowConfidence | ثقة {percent} | متأكد بنسبة {percent} | «ثقة» reads as MSA/technical |
| recurringBillsSummary | {due} مستحقة | عليك {due} | MSA «مستحقة» |
| settingsMainCaptureSub (attention) | محتاج انتباه | محتاج تبص عليه | Calque of "needs attention" |
| categoriesEditBucketGiving | عطاء | صدقات وهدايا | MSA; also touches religious giving, so it needs a careful choice |
| templatesBuilderSender, templatesBuilderErrorSender | اسم المرسل | اسم الراسل / جاية من مين | MSA |
| backupSettingsErrorAuth | الدخول على {provider} خلص. | لازم تسجّل دخول على {provider} تاني. | EN says "expired"; «خلص» can read as "sign-in finished" |
| wealthPricesFetchFailed | … شايف آخر سعر معروف. | … اللي ظاهر آخر سعر عرفناه. | «شايف» could mean "I see" or "you see" |
| privacyDeleteTypePrompt | اكتب «احذف» أو DELETE | «امسح» | MSA, and the button says «امسح» (Q-39). **The accepted word is checked in code**, so changing it needs a code change |
| privacyDeleteTypeMismatch | الكلمة مش مطابقة | الكلمة مش هي | «مطابقة» is formal |
| shareStudioHashtag | #زغلول_ضبط_الميزانية | #زغلول_ظبط_الميزانية | Colloquial spelling is «ظبط»; this is a marketing choice |
| exportsImportDuplicates (few/many/other) | … موجودة عندك (هتتخطى) | … موجودين عندك (هيتخطوا) | Agreement; the `=2` form already uses the plural verb |
| transactionsReimbUnassigned | prints `{count}` | add an `n` placeholder | **Digits issue, not wording**: `{count}` is printed raw, so Arabic-Indic digits are never used (§0.4). Needs a code change and both ARB files |
| ingestionReviewGenGuessOut, …NoMerchant, …In | توقعنا: | توقعي: / أظن: | «We» while Zaghlol says «I» in the same card (`genLowConfidence`) |
| insightsExplainCashFlowBasic (other) | الله ينور! | عاش! | Common praise, not a joke; flagged only because the voice rules ask for care around religious phrases |
| roiRuleCommuteBody | وسيلة مواصلات بالتقسيط | موتوسيكل أو عربية بالتقسيط | Vague. D-38 bans brands, not product types |
| mascotTapLine5 | بكره | بكرة | Spelling consistency (the rest of the app uses «بكرة») |
| commonKaratLabel and the karat lines | عيار {karat} (digits) | — | Q-28: Egyptians say «عيار واحد وعشرين»; confirm digits are fine |

---

## 3. Deck and ARB files disagree (not changed)

These keys have different text in `copy-deck.md` and `app_ar.arb` (often in `app_en.arb` too). In most cases the ARB looks newer (changes made during implementation). The reviewer should review the **ARB** text, since that is what ships. A scripted deck↔ARB diff before sign-off would find any I missed.

| Key | Deck AR | ARB AR |
|---|---|---|
| transactionsDetailSplit | تقسيم / فلوس راجعة | تقسيم / فلوس راجعة من صحابك |
| homeQuickAddTitle | عايز تسجل إيه؟ | تحب تسجل إيه؟ |
| homeQuickAddSay / Type / Scan | قول / اكتب / صوّر | قولها / اكتبها / صوّرها |
| insightsChartTitleCashFlow | الداخل والخارج والصافي | الداخل والخارج |
| insightsChartTitleCategories (+ A11y) | فلوسك رايحة فين؟ | فلوسك راحت فين؟ |
| insightsChartsExplain | اشرحلي يا زغلول | اشرحلي |
| insightsLegendSaved | حوشت | اللي اتحوش |
| recurringBillsDetected | لقيت اشتراك: … | شكلها اشتراك شهري: … |
| recurringBillsUpcoming | اللي جاي | الجاي |
| recurringBillsLastOne | آخر قسط | آخر قسط! 🎉 |
| recurringBillsKindCard | سداد كارت | كريدت كارد |
| zakahMainHowDebts | الديون اللي ميعادها جه بتتخصم … | الديون لسه مش بتتخصم … |
| privacyDeleteBody | … ومفاتيح الحماية … | (no mention of keys) |
| goldPaywallBenefitCharts | كل الشارتات الاتناشر مع تحليل أعمق | تحليل أعمق للشارتات: … |
| settingsMainGoldFree / settingsMainSeeGold | deck keys | ARB has `settingsMainGoldCardTitle`, `settingsMainFreePlanNote` instead |

ARB keys that have no deck row (added during implementation): `appLock*`, `ingestionReviewShowOriginal/HideOriginal/Keep*`, `reviewErrorSaveFailed`, `commonValidationNameTooLong`, `insightsCoveredEarlier`, `privacyDeleteFailed/BackupsKept`, `widgetOpenZaghlol`, `goldAccountSignedIn`, `insightsChartsPeakHour`, `homeFeedExcludedFromSpending`, `notificationsAlertBackupReminder*`, `transactionsReimbUnassigned`, `iosSetupNudge*`, `chatMainTitle/RoastTag`, `insightsChartsSavedFootnote/MonthsCount/SpendLabel`, `budgetOverviewZaghlolWarn/OfLimit`, `recurringBills*Kpi*/AddShort/InstallmentOf/GameyaMonth`, `importFlow*`. The native-speaker review should cover these too.

---

## 4. Notes for the Lead
- Tests that assert exact Arabic strings (widget or golden tests) may need updating for the 54 changes in §1.
- `app_en.arb` `onboardingIosSetupShortcutTitle` should become "We'll use Shortcuts" to match the shortened AR title and the deck.
- After the reviewer signs off, record the sign-off in `copy-deck.md` (T-058 acceptance criterion).
