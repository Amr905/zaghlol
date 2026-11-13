// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'زغلول';

  @override
  String get commonNavHome => 'الرئيسية';

  @override
  String get commonNavInsights => 'الحسبة';

  @override
  String get commonNavMoney => 'فلوسي';

  @override
  String get commonNavZaghlol => 'زغلول';

  @override
  String get commonNavAddA11y => 'سجّل بسرعة';

  @override
  String get appLockTitle => 'زغلول مقفول';

  @override
  String get appLockUnlock => 'افتح';

  @override
  String get appLockReason => 'اتأكد إنك إنت عشان تفتح زغلول';

  @override
  String get appLockFailed => 'مظبطتش. جرّب تاني.';

  @override
  String get appLockUnavailable =>
      'فعّل قفل الشاشة (PIN أو نمط أو باسورد) في تليفونك وبعدين جرّب تاني.';

  @override
  String get appLockLockedOut => 'حاولت كتير. استنى شوية وجرّب تاني.';

  @override
  String get appLockRootedTitle => 'حماية تليفونك أضعف';

  @override
  String get appLockRootedBody =>
      'التليفون ده شكله معمول له روت أو جيلبريك، فحماية بياناتك عليه أضعف. التطبيق شغال عادي، بس خد بالك.';

  @override
  String get appLockRootedOk => 'تمام';

  @override
  String get homeQuickAddTitle => 'عايز تسجل إيه؟';

  @override
  String get homeQuickAddSay => 'قول';

  @override
  String get homeQuickAddType => 'اكتب';

  @override
  String get homeQuickAddScan => 'صوّر';

  @override
  String get homeQuickAddAsset => 'أصل';

  @override
  String get homeQuickAddSayA11y => 'قول لزغلول';

  @override
  String get homeQuickAddTypeA11y => 'اكتب حركة';

  @override
  String get homeQuickAddScanA11y => 'اقرا سكرين شوت';

  @override
  String get homeQuickAddAssetA11y => 'ضيف أصل';

  @override
  String get ingestionReviewTitle => 'مستني رأيك 👀';

  @override
  String get notificationsChannelName => 'التنبيهات';

  @override
  String get commonActionSave => 'احفظ';

  @override
  String get commonActionCancel => 'إلغاء';

  @override
  String get commonActionDone => 'تمام';

  @override
  String get commonActionConfirm => 'تمام';

  @override
  String get commonActionDismiss => 'سيبها';

  @override
  String get commonActionUndo => 'تراجع';

  @override
  String get commonActionTryAgain => 'جرّب تاني';

  @override
  String get commonActionSkip => 'تخطّي';

  @override
  String get commonActionContinue => 'كمّل';

  @override
  String get commonActionNotNow => 'مش دلوقتي';

  @override
  String get commonActionLater => 'بعدين';

  @override
  String get commonActionEdit => 'عدّل';

  @override
  String get commonActionDelete => 'امسح';

  @override
  String get commonActionClose => 'اقفل';

  @override
  String get commonActionBackA11y => 'رجوع';

  @override
  String get commonActionMoreA11y => 'اختيارات تانية';

  @override
  String get commonActionSeeAll => 'شوف الكل';

  @override
  String get commonActionClearFilter => 'شيل الفلتر';

  @override
  String get commonActionOpenSettings => 'افتح الإعدادات';

  @override
  String get commonActionFix => 'صلّحها';

  @override
  String get commonActionYes => 'أيوه';

  @override
  String get commonActionNo => 'لأ';

  @override
  String get commonActionSelect => 'اختار';

  @override
  String get commonActionSelectAll => 'اختار الكل';

  @override
  String get commonActionSend => 'ابعت';

  @override
  String get commonActionLink => 'اربط';

  @override
  String get commonActionUnlink => 'فك الربط';

  @override
  String get commonActionMore => 'المزيد';

  @override
  String get commonActionShow => 'اظهر';

  @override
  String get commonActionHide => 'اخفي';

  @override
  String get commonActionLearnMore => 'اعرف أكتر';

  @override
  String get commonActionSearchA11y => 'دوّر';

  @override
  String get commonDiscardTitle => 'تسيب اللي كتبته؟';

  @override
  String get commonDiscardBody => 'اللي ما اتحفظش هيروح.';

  @override
  String get commonDiscardConfirm => 'متحفظش';

  @override
  String get commonDiscardKeep => 'كمّل تعديل';

  @override
  String get commonNavSettingsA11y => 'الإعدادات';

  @override
  String get commonCardFilterAll => 'كل الكروت';

  @override
  String commonCardFilterCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n كارت',
      many: '$n كارت',
      few: '$n كروت',
      two: 'كارتين',
      one: 'كارت واحد',
    );
    return '$_temp0';
  }

  @override
  String get commonCardFilterSheetTitle => 'تشوف أنهي كروت؟';

  @override
  String get commonCardFilterClearA11y => 'شيل فلتر الكروت';

  @override
  String commonCardFilterActiveA11y(String cards) {
    return 'الفلتر شغال: $cards';
  }

  @override
  String commonCurrencyApproxChip(String currency) {
    return '≈ $currency';
  }

  @override
  String commonCurrencyApproxCaption(String date) {
    return 'تقريبي بسعر $date';
  }

  @override
  String get commonCurrencyApproxA11y => 'تقريباً';

  @override
  String get commonBadgeStale => 'سعر قديم';

  @override
  String get commonBadgeStaleA11y => 'السعر ده عدى عليه أكتر من يوم';

  @override
  String get commonMoneyMaskedA11y => 'المبلغ مخفي';

  @override
  String commonMoneyCurrencyPagerA11y(
    String currency,
    String index,
    String total,
  ) {
    return 'صفحة $index من $total: $currency';
  }

  @override
  String get commonSourceSms => 'رسالة SMS';

  @override
  String get commonSourceNotification => 'إشعار';

  @override
  String get commonSourceApplePay => 'Apple Pay';

  @override
  String get commonSourceShortcut => 'اختصار';

  @override
  String get commonSourceScan => 'صورة';

  @override
  String get commonSourceStatement => 'كشف حساب';

  @override
  String get commonSourceCsv => 'ملف CSV';

  @override
  String get commonSourceVoice => 'صوت';

  @override
  String get commonSourceManual => 'بإيدك';

  @override
  String get commonSourceShared => 'رسالة اتبعتت';

  @override
  String get commonTxnTypeExpense => 'مصروف';

  @override
  String get commonTxnTypeIncome => 'دخل';

  @override
  String get commonTxnTypeTransfer => 'تحويل';

  @override
  String get commonTxnTypeInternal => 'تحويلة لنفسك';

  @override
  String get commonTxnTypeRefund => 'مرتجع';

  @override
  String get commonTxnTypeReimbursement => 'فلوس راجعة';

  @override
  String get commonTxnTypeDeclined => 'اترفضت';

  @override
  String get commonAccountTypeDebit => 'ديبت';

  @override
  String get commonAccountTypeCredit => 'كريدت';

  @override
  String get commonAccountTypeAccount => 'حساب بنك';

  @override
  String get commonAccountTypeWallet => 'محفظة';

  @override
  String get commonAccountTypeBnpl => 'تقسيط';

  @override
  String get commonAccountTypeCash => 'كاش';

  @override
  String get commonAccountTypeMultiCurrency => 'أكتر من عملة';

  @override
  String get commonChannelSms => 'رسايل البنك';

  @override
  String get commonChannelSmsShort => 'الرسايل';

  @override
  String get commonChannelNotifications => 'إشعارات التطبيقات';

  @override
  String get commonChannelNotificationsShort => 'الإشعارات';

  @override
  String get commonChannelApplePay => 'Apple Pay';

  @override
  String get commonChannelOnA11y => 'شغال';

  @override
  String get commonChannelOffA11y => 'مقفول';

  @override
  String get commonDateToday => 'النهارده';

  @override
  String get commonDateYesterday => 'امبارح';

  @override
  String get commonDateJustNow => 'دلوقتي';

  @override
  String commonDateMinutesAgo(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'من $n دقيقة',
      many: 'من $n دقيقة',
      few: 'من $n دقايق',
      two: 'من دقيقتين',
      one: 'من دقيقة',
      zero: 'دلوقتي',
    );
    return '$_temp0';
  }

  @override
  String commonDateHoursAgo(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'من $n ساعة',
      many: 'من $n ساعة',
      few: 'من $n ساعات',
      two: 'من ساعتين',
      one: 'من ساعة',
    );
    return '$_temp0';
  }

  @override
  String commonDateDateTime(String date, String time) {
    return '$date، $time';
  }

  @override
  String commonDateRange(String end, String start) {
    return '$start – $end';
  }

  @override
  String get commonPeriodThisCycle => 'الدورة دي';

  @override
  String get commonPeriodLastCycle => 'الدورة اللي فاتت';

  @override
  String get commonPeriodThisMonth => 'الشهر ده';

  @override
  String get commonPeriodPickMonth => 'شهر معين';

  @override
  String get commonPeriodCustom => 'من تاريخ لتاريخ';

  @override
  String commonPeriodLastMonths(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'آخر $n شهر',
      many: 'آخر $n شهر',
      few: 'آخر $n شهور',
      two: 'آخر شهرين',
      one: 'آخر شهر',
    );
    return '$_temp0';
  }

  @override
  String commonPeriodInLastMonths(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'في آخر $n شهر',
      many: 'في آخر $n شهر',
      few: 'في آخر $n شهور',
      two: 'في آخر شهرين',
      one: 'في آخر شهر',
    );
    return '$_temp0';
  }

  @override
  String commonProgressPercent(String n) {
    return '$n٪';
  }

  @override
  String commonFileSizeMb(String n) {
    return '$n ميجا';
  }

  @override
  String commonFileSizeKb(String n) {
    return '$n كيلو';
  }

  @override
  String get commonPlatformAndroid => 'أندرويد';

  @override
  String get commonPlatformIos => 'آيفون';

  @override
  String get commonValidationAmountRequired => 'اكتب مبلغ أكبر من صفر';

  @override
  String get commonValidationAmountTooLarge => 'المبلغ ده كبير أوي، راجعه';

  @override
  String commonValidationAmountDecimals(int count, String currency, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$currency بيقبل $n رقم بعد العلامة',
      many: '$currency بيقبل $n رقم بعد العلامة',
      few: '$currency بيقبل $n أرقام بس بعد العلامة',
      two: '$currency بيقبل رقمين بس بعد العلامة',
      one: '$currency بيقبل رقم واحد بعد العلامة',
      zero: '$currency مفيهوش كسور',
    );
    return '$_temp0';
  }

  @override
  String get commonValidationCurrencyRequired => 'اختار العملة';

  @override
  String get commonValidationDateFuture => 'التاريخ ميكونش في المستقبل';

  @override
  String get commonValidationDateRange => 'تاريخ البداية لازم يبقى قبل النهاية';

  @override
  String get commonValidationLast4 => 'اكتب آخر أربع أرقام';

  @override
  String get commonValidationNameRequired => 'اكتب اسم';

  @override
  String commonValidationNameLength(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الاسم ميزيدش عن $n حرف',
      many: 'الاسم ميزيدش عن $n حرف',
      few: 'الاسم ميزيدش عن $n حروف',
      two: 'الاسم ميزيدش عن حرفين',
      one: 'الاسم ميزيدش عن حرف واحد',
    );
    return '$_temp0';
  }

  @override
  String get commonValidationNameTaken => 'الاسم ده مستخدم قبل كده';

  @override
  String commonValidationNoteLength(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الملاحظة ميزيدش عن $n حرف',
      many: 'الملاحظة ميزيدش عن $n حرف',
      few: 'الملاحظة ميزيدش عن $n حروف',
      two: 'الملاحظة ميزيدش عن حرفين',
      one: 'الملاحظة ميزيدش عن حرف واحد',
    );
    return '$_temp0';
  }

  @override
  String get commonValidationCategoryRequired => 'اختار التصنيف';

  @override
  String get commonValidationAccountRequired => 'اختار الحساب';

  @override
  String get commonValidationChoiceRequired => 'اختار واحدة';

  @override
  String get commonErrorLoadFailed =>
      'مقدرتش أفتح ده دلوقتي. بياناتك في أمان على موبايلك.';

  @override
  String get commonErrorSaveFailed =>
      'محصلش حفظ. جرّب تاني، واللي كتبته لسه موجود.';

  @override
  String get commonErrorNetwork =>
      'مش قادر أوصل للسيرفر دلوقتي. فلوسك في أمان على موبايلك، جرّب تاني كمان شوية.';

  @override
  String get commonGoldBadge => 'جولد';

  @override
  String get commonGoldUnlock => 'افتحها مع جولد';

  @override
  String get commonGoldLockedA11y => 'متاحة في زغلول جولد';

  @override
  String get mascotAvatarLabelA11y => 'الكابتن زغلول';

  @override
  String get mascotPullRefreshingA11y => 'بحدّث…';

  @override
  String get mascotSavedLine1 => 'اتسجلت ✓';

  @override
  String get mascotSavedLine2 => 'تمام، حطيتها في الحسبة ✓';

  @override
  String get mascotSavedLine3 => 'اتقيدت يا كبير ✓';

  @override
  String get mascotTapLine1 => 'إيه يا عم، بتزغزغني؟ 😄';

  @override
  String get mascotTapLine2 => 'أنا هنا يا كبير، وفلوسك في عينيّا';

  @override
  String get mascotTapLine3 => 'كل قرش بتحوشه بيطلّعلي ريشة جديدة 🪶';

  @override
  String get mascotTapLine4 => 'الكابتن جاهز، وإنت القائد';

  @override
  String get mascotTapLine5 => 'اللي يحوش النهارده يتفسح بكره';

  @override
  String get mascotTapLine6 => 'أنا بقرا رسايل البنوك بس، الباقي مش شغلي';

  @override
  String get mascotTapLine7 => 'حمامة ولا محاسب؟ الاتنين!';

  @override
  String get mascotTapLine8 => 'جناحي سريع وحساباتي مظبوطة';

  @override
  String get onboardingWelcomeLanguageToggle => 'English';

  @override
  String get onboardingWelcomeLanguageToggleA11y => 'غيّر اللغة للإنجليزي';

  @override
  String get onboardingWelcomeTitle => 'أهلاً بيك! أنا الكابتن زغلول';

  @override
  String get onboardingWelcomeSubtitle =>
      'هعرفك فلوسك بتروح فين من رسايل البنك، من غير ما تكتب حاجة.';

  @override
  String get onboardingWelcomePointOnPhone => 'بيانات فلوسك بتفضل على موبايلك';

  @override
  String get onboardingWelcomePointNoPassword => 'مش هنطلب باسورد البنك أبداً';

  @override
  String get onboardingWelcomePointNoAds => 'من غير إعلانات';

  @override
  String get onboardingWelcomeStart => 'يلا نبدأ';

  @override
  String get onboardingWelcomeRestore => 'استخدمت زغلول قبل كده';

  @override
  String get onboardingWelcomePrivacyLink => 'تفاصيل الخصوصية';

  @override
  String onboardingAndroidSetupStep(String step, String total) {
    return 'خطوة $step من $total';
  }

  @override
  String get onboardingAndroidSetupSmsTitle => 'خليني أقرا رسايل البنك';

  @override
  String get onboardingAndroidSetupSmsSubtitle => 'وهرتبلك كل مصاريفك لوحدي.';

  @override
  String get onboardingAndroidSetupSmsPointSenders =>
      'بقرا رسايل البنوك والمحافظ وإنستاباي بس';

  @override
  String get onboardingAndroidSetupSmsPointPersonal =>
      'رسايلك الشخصية عمرها ما بتتقري ولا بتتحفظ';

  @override
  String get onboardingAndroidSetupSmsPointOnPhone =>
      'بيانات فلوسك بتفضل على الموبايل ده';

  @override
  String get onboardingAndroidSetupSmsAllow => 'اسمح بقراية الرسايل';

  @override
  String get onboardingAndroidSetupSmsGranted => 'الرسايل اتسمحت ✓';

  @override
  String get onboardingAndroidSetupScanTitle => 'بقرا رسايلك القديمة…';

  @override
  String onboardingAndroidSetupScanDepth(String period) {
    return '$period · كمّل وأنا شغال';
  }

  @override
  String onboardingAndroidSetupScanCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'لقيت $n حركة',
      many: 'لقيت $n حركة',
      few: 'لقيت $n حركات',
      two: 'لقيت حركتين',
      one: 'لقيت حركة واحدة',
      zero: 'لسه بدوّر…',
    );
    return '$_temp0';
  }

  @override
  String get onboardingAndroidSetupScanBanks => 'البنوك اللي لقيتها:';

  @override
  String get onboardingAndroidSetupNotifTitle =>
      'وكمان إشعارات تطبيقات البنوك؟';

  @override
  String get onboardingAndroidSetupNotifBody =>
      'في بنوك ومحافظ بتبعت إشعار في التطبيق بس من غير SMS، زي Wise وRevolut وPayoneer.';

  @override
  String get onboardingAndroidSetupNotifPrivacy =>
      'بقرا إشعارات تطبيقات البنوك والمحافظ بس، مش الواتساب ولا أي حاجة تانية.';

  @override
  String get onboardingAndroidSetupNotifTurnOn => 'شغّل الإشعارات';

  @override
  String get onboardingAndroidSetupNotifOsHint =>
      'في الشاشة الجاية، دوّر على «زغلول» وشغّله.';

  @override
  String get onboardingAndroidSetupNotifGranted => 'الإشعارات اشتغلت ✓';

  @override
  String get onboardingAndroidSetupNotifStillOff =>
      'لسه مقفولة. تقدر تشغلها بعدين من الإعدادات.';

  @override
  String get onboardingAndroidSetupDegradedTitle => 'قراية الرسايل مقفولة';

  @override
  String get onboardingAndroidSetupDegradedBody =>
      'لسه تقدر تتابع مصاريفك بطرق تانية:';

  @override
  String get onboardingAndroidSetupDegradedNotif => 'إشعارات تطبيقات البنوك';

  @override
  String get onboardingAndroidSetupDegradedNotifOn => 'شغّلها';

  @override
  String get onboardingAndroidSetupDegradedShare =>
      'ابعت أو الزق رسالة البنك لزغلول';

  @override
  String get onboardingAndroidSetupDegradedShareHow => 'إزاي؟';

  @override
  String get onboardingAndroidSetupDegradedManual =>
      'سجّل الكاش بصوتك أو بإيدك';

  @override
  String get onboardingAndroidSetupDegradedRetry => 'اسمح تاني';

  @override
  String get onboardingAndroidSetupDegradedSettingsHint =>
      'علشان تشغلها، افتح الإعدادات واسمح لزغلول بالرسايل.';

  @override
  String get onboardingAndroidSetupPlayUnavailable =>
      'النسخة دي من زغلول مش بتقرا SMS، بس الإشعارات والمشاركة شغالين تمام.';

  @override
  String onboardingIosSetupStep(String step, String total) {
    return 'خطوة $step من $total';
  }

  @override
  String get onboardingIosSetupShortcutTitle => 'هنستخدم الاختصارات';

  @override
  String get onboardingIosSetupShortcutWhy =>
      'الآيفون مش بيسمح للتطبيقات تقرا الرسايل، فالاختصارات هي اللي هتبعتهالي.';

  @override
  String get onboardingIosSetupShortcutLead => 'ضغطة واحدة بتضيف:';

  @override
  String get onboardingIosSetupShortcutSmsTitle => 'رسايل البنك';

  @override
  String get onboardingIosSetupShortcutSmsSub =>
      'بيلقط رسايل البنوك وإنستاباي، عربي وإنجليزي';

  @override
  String get onboardingIosSetupShortcutApplePayTitle => 'مدفوعات Apple Pay';

  @override
  String get onboardingIosSetupShortcutApplePaySub =>
      'بيسجل أي دفع بالموبايل في ساعتها';

  @override
  String get onboardingIosSetupShortcutOnce =>
      'مرة واحدة بس، وبعدها كل حاجة بتتسجل لوحدها.';

  @override
  String get onboardingIosSetupShortcutAdd => 'ضيف اختصار زغلول';

  @override
  String get onboardingIosSetupHowItWorks => 'إزاي بيشتغل؟ (نص دقيقة)';

  @override
  String get onboardingIosSetupHowStep1 =>
      'لما توصلك رسالة من بنك، الآيفون بيشغّل الاختصار لوحده.';

  @override
  String get onboardingIosSetupHowStep2 =>
      'الاختصار بيدّي نص الرسالة لزغلول على نفس الموبايل، مش بيبعته لأي حد.';

  @override
  String get onboardingIosSetupHowStep3 =>
      'زغلول يقرا المبلغ والتاجر ويسجلها. خلاص كده.';

  @override
  String get onboardingIosSetupChecking =>
      'ثانية، بشوف الاختصارات اتضافت ولا لأ…';

  @override
  String get onboardingIosSetupShortcutsMissing =>
      'مقدرتش أفتح تطبيق الاختصارات. نزّله من الـ App Store وجرّب تاني.';

  @override
  String get onboardingIosSetupCheckTitle => 'تعالى نتأكد إن كله تمام';

  @override
  String get onboardingIosSetupCheckSubtitle =>
      'زغلول بيبص على الاختصارات اللي اتضافت.';

  @override
  String get onboardingIosSetupCheckSmsAr => 'رسايل البنوك (عربي)';

  @override
  String get onboardingIosSetupCheckSmsEn => 'رسايل البنوك (إنجليزي)';

  @override
  String get onboardingIosSetupCheckApplePay => 'مدفوعات Apple Pay';

  @override
  String onboardingIosSetupCheckCount(int count, String done, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$done من $n أوتوميشن',
      many: '$done من $n أوتوميشن',
      few: '$done من $n أوتوميشن',
      two: '$done من $n أوتوميشن',
      one: '$done من $n أوتوميشن',
    );
    return '$_temp0';
  }

  @override
  String get onboardingIosSetupCheckNeedsRun => 'محتاجة «Run Immediately»';

  @override
  String get onboardingIosSetupCheckOkA11y => 'شغال';

  @override
  String get onboardingIosSetupCheckMissingA11y => 'ناقص';

  @override
  String get onboardingIosSetupFixTitle => 'إزاي تصلحها؟';

  @override
  String get onboardingIosSetupFixStep1 => 'افتح Shortcuts وبعدين Automation';

  @override
  String onboardingIosSetupFixStep2(String automationName) {
    return 'اختار «$automationName»';
  }

  @override
  String get onboardingIosSetupFixStep3 => 'شغّل «Run Immediately»';

  @override
  String get onboardingIosSetupCheckUnknown =>
      'مش متأكدين لسه؟ هنعرف أول ما توصلك رسالة بنك.';

  @override
  String get onboardingIosSetupCheckAgain => 'اتأكد تاني';

  @override
  String get onboardingIosSetupCheckAllGood => 'كله تمام ✓ زغلول جاهز';

  @override
  String get onboardingIosSetupFirstTitle => 'يلا نسجل أول مصروف!';

  @override
  String get onboardingIosSetupFirstBody =>
      'لحد ما توصل أول رسالة بنك، قولي صرفت إيه النهارده.';

  @override
  String get onboardingIosSetupFirstSay => 'قولها';

  @override
  String get onboardingIosSetupFirstSayHint => '«دفعت خمسة وأربعين قهوة»';

  @override
  String get onboardingIosSetupFirstType => 'اكتبها';

  @override
  String get onboardingIosSetupFirstTypeHint => 'المبلغ والتصنيف';

  @override
  String get onboardingIosSetupFirstOnlineBanks =>
      'بتستخدم Wise أو Revolut أو Payoneer؟';

  @override
  String get onboardingIosSetupFirstOnlineBanksSub =>
      'شوف إزاي تتابعهم على الآيفون';

  @override
  String get onboardingIosSetupFirstStatement => 'عندك كشف حساب؟';

  @override
  String get onboardingIosSetupFirstStatementSub =>
      'ضيف شهور فاتت مرة واحدة مع جولد';

  @override
  String get backupRestoreTitle => 'استرجاع نسخة';

  @override
  String get backupRestoreWhereTitle => 'النسخة بتاعتك فين؟';

  @override
  String get backupRestoreOptionDrive => 'Google Drive';

  @override
  String get backupRestoreOptionICloud => 'iCloud';

  @override
  String backupRestoreSigningIn(String provider) {
    return 'بدخل على $provider…';
  }

  @override
  String get backupRestoreSearching => 'بدوّر على نسخة زغلول…';

  @override
  String get backupRestoreFoundTitle => 'لقيت نسخة';

  @override
  String backupRestoreFoundMeta(String date, String size) {
    return '$date · $size';
  }

  @override
  String backupRestoreFoundFrom(String appVersion, String platform) {
    return 'من: $platform · إصدار $appVersion';
  }

  @override
  String get backupRestoreVersionsTitle => 'النسخ اللي عندك';

  @override
  String get backupRestoreVersionNewest => 'الأحدث';

  @override
  String get backupRestorePassphraseLabel => 'كلمة سر النسخة';

  @override
  String get backupRestoreRestore => 'استرجع';

  @override
  String get backupRestorePassphraseRequired => 'اكتب كلمة السر';

  @override
  String get backupRestorePassphraseWrong => 'كلمة السر دي مش بتفتح النسخة دي';

  @override
  String get backupRestoreForgotLink => 'نسيت كلمة السر؟';

  @override
  String get backupRestoreForgotBody =>
      'للأسف مش هينفع نرجّعها. النسخة مبتتفتحش غير بكلمة السر دي، ومحدش يقدر يفتحها من غيرها، ولا حتى إحنا. تقدر تبدأ من جديد.';

  @override
  String get backupRestoreRestoring => 'بسترجع بياناتك…';

  @override
  String get backupRestoreKeepOpen => 'سيب زغلول مفتوح لحد ما يخلص';

  @override
  String get backupRestoreEmptyTitle => 'مفيش نسخة زغلول على الحساب ده';

  @override
  String get backupRestoreTryAnotherAccount => 'جرّب حساب تاني';

  @override
  String get backupRestoreStartFresh => 'ابدأ من جديد';

  @override
  String backupRestoreErrorNetwork(String provider) {
    return 'مش قادر أوصل لـ $provider دلوقتي. اتأكد من النت وجرّب تاني.';
  }

  @override
  String backupRestoreErrorSignIn(String provider) {
    return 'الدخول على $provider ما كملش. جرّب تاني.';
  }

  @override
  String get backupRestoreErrorNewer =>
      'النسخة دي معمولة بإصدار أحدث من زغلول. حدّث التطبيق الأول.';

  @override
  String get backupRestoreUpdate => 'حدّث زغلول';

  @override
  String get backupRestoreErrorCorrupted => 'النسخة دي مش بتتقري.';

  @override
  String get backupRestoreTryOlder => 'جرّب نسخة أقدم';

  @override
  String get backupRestoreDoneBanner =>
      'بياناتك رجعت ✓ دلوقتي اسمح لزغلول يقرا على الموبايل ده.';

  @override
  String get backupRestoreDoneAction => 'يلا نظبطها';

  @override
  String get securityLockTitle => 'زغلول مقفول';

  @override
  String securityLockUnlock(String method) {
    String _temp0 = intl.Intl.selectLogic(method, {
      'faceId': 'افتح بالـ Face ID',
      'touchId': 'افتح بالـ Touch ID',
      'fingerprint': 'افتح ببصمتك',
      'face': 'افتح ببصمة الوش',
      'other': 'افتح القفل',
    });
    return '$_temp0';
  }

  @override
  String securityLockUsePasscode(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'استخدم كود الآيفون',
      'other': 'استخدم قفل الموبايل',
    });
    return '$_temp0';
  }

  @override
  String get securityLockPromptReason => 'افتح زغلول';

  @override
  String get securityLockPromptSubtitle => 'علشان محدش يشوف فلوسك غيرك';

  @override
  String get securityLockFailed => 'مفتحش. جرّب تاني.';

  @override
  String get securityLockBiometricsGone =>
      'البصمة مش متاحة دلوقتي، افتح بقفل الموبايل.';

  @override
  String get onboardingScanResultsTitle => 'خلصت! 🎉';

  @override
  String onboardingScanResultsFound(int count, String n, String period) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'لقيت $n حركة $period',
      many: 'لقيت $n حركة $period',
      few: 'لقيت $n حركات $period',
      two: 'لقيت حركتين $period',
      one: 'لقيت حركة واحدة $period',
    );
    return '$_temp0';
  }

  @override
  String get onboardingScanResultsStatAuto => 'اتصنفوا لوحدهم';

  @override
  String get onboardingScanResultsStatReview => 'مستنيين رأيك';

  @override
  String get onboardingScanResultsStatCards => 'كروت وحسابات';

  @override
  String get onboardingScanResultsCardsTitle => 'دي كروتك؟';

  @override
  String onboardingScanResultsCardSubtitle(int count, String n, String type) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$type · $n حركة',
      many: '$type · $n حركة',
      few: '$type · $n حركات',
      two: '$type · حركتين',
      one: '$type · حركة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get onboardingScanResultsGuessCredit => 'شكله كريدت كارد';

  @override
  String get onboardingScanResultsCreditBadge => 'كريدت؟';

  @override
  String onboardingScanResultsCreditPrompt(String card) {
    return '$card شكله كريدت كارد. قولي الليميت وميعاد السداد عشان أفكرك قبلها.';
  }

  @override
  String get onboardingScanResultsCreditYes => 'أيوه، ظبطه';

  @override
  String get onboardingScanResultsNotMineHint =>
      'كارت مش بتاعك أو كارت شغل؟ دوس عليه واقفل قرايته.';

  @override
  String get onboardingScanResultsShowMe => 'ورّيني فلوسي';

  @override
  String onboardingScanResultsRescanToast(String card, int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ضفت $n حركة لـ $card',
      many: 'ضفت $n حركة لـ $card',
      few: 'ضفت $n حركات لـ $card',
      two: 'ضفت حركتين لـ $card',
      one: 'ضفت حركة واحدة لـ $card',
      zero: 'ملقيتش حركات جديدة لـ $card',
    );
    return '$_temp0';
  }

  @override
  String homeGreetingByTime(String part) {
    String _temp0 = intl.Intl.selectLogic(part, {
      'morning': 'صباح الفل يا كبير ☀️',
      'afternoon': 'مساء الفل يا كبير ☀️',
      'evening': 'مساء الفل يا كبير 🌙',
      'other': 'أهلاً يا كبير 👋',
    });
    return '$_temp0';
  }

  @override
  String get homeGreetingFirstVisit => 'أهلاً يا كبير 👋';

  @override
  String get homeHeroSafeToSpend => 'مسموحلك تصرف النهارده';

  @override
  String get homeHeroPerDay => 'في اليوم';

  @override
  String homeHeroDaysToPayday(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'فاضل $n يوم على القبض',
      many: 'فاضل $n يوم على القبض',
      few: 'فاضل $n أيام على القبض',
      two: 'فاضل يومين على القبض',
      one: 'فاضل يوم على القبض',
      zero: 'القبض النهارده',
    );
    return '$_temp0';
  }

  @override
  String get homeHeroCalendarMonth => 'لحد ما تقولي ميعاد قبضك';

  @override
  String get homeHeroSpentThisMonth => 'صرفت الشهر ده';

  @override
  String get homeHeroSpentThisCycle => 'صرفت الدورة دي';

  @override
  String get homeHeroSetBudgetHint => 'حط ميزانية عشان تعرف تصرف كام في اليوم';

  @override
  String get homeHeroSetBudget => 'حط ميزانية';

  @override
  String get homeHeroBudgetUsedUp => 'ميزانية الدورة دي خلصت، حاسب على الباقي';

  @override
  String get homeHeroKpiIncome => 'دخلك';

  @override
  String get homeHeroKpiSpent => 'صرفت';

  @override
  String get homeHeroKpiLeft => 'فاضلك';

  @override
  String homeHeroApproxTitle(String currency) {
    return 'كله تقريباً بالـ $currency';
  }

  @override
  String homeHeroSummaryA11y(
    String amount,
    String income,
    String left,
    String payday,
    String spent,
  ) {
    return 'مسموحلك تصرف $amount النهارده. $payday. دخلك $income، صرفت $spent، فاضلك $left.';
  }

  @override
  String homeMascotShockedCategory(String category, String percent) {
    return 'حاسب يا كبير! $category وصل $percent من ميزانيته ولسه بدري في الدورة.';
  }

  @override
  String homeMascotShockedCategoryAlt(String category, String percent) {
    return '$category قرّب يخلص يا كبير، $percent راحوا ولسه بدري. نهدّي شوية؟';
  }

  @override
  String homeMascotShockedDining(String percent) {
    return 'الأكل بره والدليفري زايدين $percent عن العادي بتاعك. المطبخ وحشك؟ 🍳';
  }

  @override
  String homeMascotDetectiveDuplicate(String amount, String merchant) {
    return 'اتخصم منك $amount مرتين من $merchant في دقايق. بص عليها كده.';
  }

  @override
  String get homeMascotDetectiveDuplicateAction => 'بص عليها';

  @override
  String homeMascotDetectiveSubscription(String amount, String merchant) {
    return 'شكلها اشتراك شهري: $merchant بـ $amount. أتابعهولك؟';
  }

  @override
  String get homeMascotDetectiveSubscriptionTrack => 'تابعه';

  @override
  String get homeMascotDetectiveSubscriptionNot => 'مش اشتراك';

  @override
  String homeMascotDetectiveSelfTransfer(
    String amount,
    String fromCard,
    String toCard,
  ) {
    return '$amount راحوا من $fromCard لـ $toCard. دي تحويلة لنفسك، فمش هحسبها مصروف 👌';
  }

  @override
  String get homeMascotProudOnTrack =>
      'عاش يا وحش! صارف أقل من خطتك لحد دلوقتي 👏';

  @override
  String homeMascotProudSavedMore(String amount) {
    return 'عاش يا وحش! وفرت $amount زيادة عن الدورة اللي فاتت 👏';
  }

  @override
  String get homeMascotProudGoal => 'هدف الدورة اتحقق! 🎯 إنت قدها';

  @override
  String homeMascotPayday(String amount) {
    return 'المرتب نزل! $amount 🎉 يلا نخطط له من أوله';
  }

  @override
  String get homeMascotDismissA11y => 'اقفل الرسالة';

  @override
  String homePromptPayday(String amount, String day) {
    return 'لقيت مرتب $amount بينزل يوم $day كل شهر. ده ميعاد قبضك؟';
  }

  @override
  String homePromptPaydayYes(String day) {
    return 'أيوه، يوم $day';
  }

  @override
  String homePromptPaydayMonthStart(String amount) {
    return 'لقيت مرتب $amount بينزل آخر الشهر. نحسب الدورة من أول الشهر لآخره؟';
  }

  @override
  String get homePromptPaydayMonthStartYes => 'أيوه، من أول الشهر';

  @override
  String get homePromptBudget =>
      'خلصت أول دورة معايا! تحب نحط ميزانية للدورة الجاية؟';

  @override
  String get homePromptBudgetYes => 'يلا';

  @override
  String get homePromptBackup =>
      'بقالك أسبوع بتسجل معايا. اعمل نسخة احتياطية ببلاش عشان بياناتك تفضل في أمان لو حصل حاجة للموبايل.';

  @override
  String get homePromptBackupYes => 'اعمل نسخة';

  @override
  String homePromptAppLockTitle(String method) {
    String _temp0 = intl.Intl.selectLogic(method, {
      'faceId': 'اقفل زغلول بالـ Face ID؟',
      'touchId': 'اقفل زغلول بالـ Touch ID؟',
      'fingerprint': 'اقفل زغلول ببصمتك؟',
      'face': 'اقفل زغلول ببصمة الوش؟',
      'other': 'اقفل زغلول بقفل الموبايل؟',
    });
    return '$_temp0';
  }

  @override
  String get homePromptAppLockSub => 'محدش يشوف فلوسك غيرك';

  @override
  String get homePromptAppLockOn => 'القفل اشتغل ✓';

  @override
  String get homePromptFinishSetup => 'كمّل الإعداد';

  @override
  String homePromptFinishSetupSteps(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'فاضل $n خطوة',
      many: 'فاضل $n خطوة',
      few: 'فاضل $n خطوات',
      two: 'فاضل خطوتين',
      one: 'فاضل خطوة واحدة',
    );
    return '$_temp0';
  }

  @override
  String homeBannerReview(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n حركة مستنية رأيك 👀',
      many: '$n حركة مستنية رأيك 👀',
      few: '$n حركات مستنية رأيك 👀',
      two: 'حركتين مستنيين رأيك 👀',
      one: 'حركة واحدة مستنية رأيك 👀',
    );
    return '$_temp0';
  }

  @override
  String homeBannerScanning(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بقرا رسايلك… لقيت $n حركة لحد دلوقتي',
      many: 'بقرا رسايلك… لقيت $n حركة لحد دلوقتي',
      few: 'بقرا رسايلك… لقيت $n حركات لحد دلوقتي',
      two: 'بقرا رسايلك… لقيت حركتين لحد دلوقتي',
      one: 'بقرا رسايلك… لقيت حركة واحدة لحد دلوقتي',
      zero: 'بقرا رسايلك…',
    );
    return '$_temp0';
  }

  @override
  String get homeBannerScanFailed => 'مقدرتش أقرا رسايلك';

  @override
  String get homeBannerSmsOff =>
      'قراية رسايل البنك مقفولة، فممكن حركات تفوتني.';

  @override
  String get homeBannerNotifOff =>
      'إشعارات تطبيقات البنوك اتقفلت، فممكن حركات تفوتني.';

  @override
  String get homeBannerShortcutsBroken =>
      'الاختصارات محتاجة تتظبط عشان ميفوتنيش حاجة.';

  @override
  String homeBannerShortcutsQuiet(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'مفيش رسايل بنك اتسجلت من $n يوم. الاختصارات لسه شغالة؟',
      many: 'مفيش رسايل بنك اتسجلت من $n يوم. الاختصارات لسه شغالة؟',
      few: 'مفيش رسايل بنك اتسجلت من $n أيام. الاختصارات لسه شغالة؟',
      two: 'مفيش رسايل بنك اتسجلت من يومين. الاختصارات لسه شغالة؟',
      one: 'مفيش رسايل بنك اتسجلت من امبارح. الاختصارات لسه شغالة؟',
    );
    return '$_temp0';
  }

  @override
  String get homeBannerShortcutsCheck => 'اتأكد';

  @override
  String homeBannerRooted(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'الآيفون ده متعمله جيلبريك، فحماية بياناتك أضعف.',
      'other': 'الموبايل ده متعمله روت، فحماية بياناتك أضعف.',
    });
    return '$_temp0';
  }

  @override
  String get homeFeedTitle => 'اللي اتصرف قريب';

  @override
  String get homeEmptyTitle => 'لسه مفيش حركات';

  @override
  String get homeEmptyBodyWaiting => 'أول ما توصلك رسالة بنك هتظهر هنا لوحدها.';

  @override
  String get homeEmptyBodyAdd => 'سجّل أول مصروف وأنا أكمّل معاك.';

  @override
  String get homeEmptyAdd => 'ضيف أول مصروف';

  @override
  String homeEmptyFilter(String cards) {
    return 'مفيش حركات لـ $cards في الدورة دي';
  }

  @override
  String transactionsRowSubtitle(String card, String source, String time) {
    return '$card · $time · $source';
  }

  @override
  String get transactionsRowInternalTitle => 'تحويلة لنفسك';

  @override
  String transactionsRowInternalSubtitle(String fromCard, String toCard) {
    return '$fromCard لـ $toCard · مش محسوبة في المصاريف';
  }

  @override
  String get transactionsRowDeclined => 'اترفضت · مش محسوبة';

  @override
  String transactionsRowReimbursed(String back, String paid) {
    return 'دفعت $paid · رجعلك $back';
  }

  @override
  String transactionsRowRefund(String merchant) {
    return 'مرتجع من $merchant';
  }

  @override
  String get transactionsRowNeedsReviewA11y => 'مستنية رأيك';

  @override
  String transactionsRowLabelA11y(
    String amount,
    String card,
    String category,
    String merchant,
    String time,
  ) {
    return '$merchant، $amount، $category، $card، $time';
  }

  @override
  String get transactionsRowSwipeCategory => 'غيّر التصنيف';

  @override
  String get transactionsRowSwipeSplit => 'تقسيم / فلوس راجعة';

  @override
  String get transactionsListTitle => 'الحركات';

  @override
  String get transactionsListSearchHint => 'تاجر، ملاحظة أو مبلغ…';

  @override
  String get transactionsListFilterPeriod => 'المدة';

  @override
  String get transactionsListFilterCategory => 'التصنيف';

  @override
  String get transactionsListFilterType => 'النوع';

  @override
  String get transactionsListFilterSource => 'جت منين';

  @override
  String transactionsListFilterCount(String label, String n) {
    return '$label · $n';
  }

  @override
  String get transactionsListRangeTitle => 'اختار المدة';

  @override
  String get transactionsListRangeFrom => 'من';

  @override
  String get transactionsListRangeTo => 'لحد';

  @override
  String transactionsListDayTotalA11y(String amount) {
    return 'إجمالي اليوم $amount';
  }

  @override
  String get transactionsListEmptyTitle => 'حركاتك هتظهر هنا';

  @override
  String get transactionsListEmptyBody => 'من رسايل البنك، أو سجّلها بإيدك.';

  @override
  String get transactionsListEmptyAdd => 'ضيف مصروف';

  @override
  String transactionsListNoResults(String query) {
    return 'مفيش حاجة شبه «$query»';
  }

  @override
  String get transactionsListNoResultsFilters => 'مفيش حركات بالفلاتر دي';

  @override
  String get transactionsListClearAll => 'امسح البحث والفلاتر';

  @override
  String transactionsListSelectedTitle(String n) {
    return 'اخترت $n';
  }

  @override
  String get transactionsListBulkCategory => 'التصنيف';

  @override
  String get transactionsListBulkAccount => 'الكارت';

  @override
  String get transactionsListBulkRule => 'استخدم ده دايماً للتجار دول';

  @override
  String transactionsListBulkChanged(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'اتغيرت $n حركة',
      many: 'اتغيرت $n حركة',
      few: 'اتغيرت $n حركات',
      two: 'اتغيرت حركتين',
      one: 'اتغيرت حركة واحدة',
    );
    return '$_temp0';
  }

  @override
  String transactionsListBulkDeleteTitle(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمسح $n حركة؟',
      many: 'تمسح $n حركة؟',
      few: 'تمسح $n حركات؟',
      two: 'تمسح الحركتين؟',
      one: 'تمسح حركة واحدة؟',
    );
    return '$_temp0';
  }

  @override
  String get transactionsListBulkDeleteBody => 'مش هتقدر ترجعها بعد كده.';

  @override
  String transactionsListBulkDeleted(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'اتمسحت $n حركة',
      many: 'اتمسحت $n حركة',
      few: 'اتمسحت $n حركات',
      two: 'اتمسحت حركتين',
      one: 'اتمسحت حركة واحدة',
    );
    return '$_temp0';
  }

  @override
  String transactionsListSelectRowA11y(String merchant) {
    return 'اختار $merchant';
  }

  @override
  String transactionsDetailOriginal(String amount) {
    return 'الأصلي: $amount';
  }

  @override
  String get transactionsDetailFieldCard => 'الكارت';

  @override
  String get transactionsDetailFieldDate => 'إمتى';

  @override
  String get transactionsDetailFieldBalance => 'فاضل في الحساب';

  @override
  String get transactionsDetailFieldSource => 'جت منين';

  @override
  String get transactionsDetailFieldReference => 'رقم العملية';

  @override
  String get transactionsDetailFieldNote => 'ملاحظة';

  @override
  String get transactionsDetailNoteAdd => 'ضيف ملاحظة';

  @override
  String get transactionsDetailNoteHint => 'اكتب ملاحظة…';

  @override
  String get transactionsDetailSplit => 'تقسيم / فلوس راجعة';

  @override
  String get transactionsDetailLinkTransfer => 'دي تحويلة لنفسي';

  @override
  String get transactionsDetailMoneyBackFor => 'دي فلوس راجعة عن…';

  @override
  String transactionsDetailLinkedWith(String amount, String card) {
    return 'مربوطة مع $amount في $card';
  }

  @override
  String get transactionsDetailInternalBanner =>
      'تحويلة لنفسك، مش محسوبة لا مصروف ولا دخل';

  @override
  String get transactionsDetailDeclinedBanner => 'العملية اترفضت، مش محسوبة';

  @override
  String transactionsDetailRefundCard(
    String date,
    String merchant,
    String net,
  ) {
    return 'مرتجع من $merchant عن مشتريات $date · الصافي $net';
  }

  @override
  String get transactionsDetailRefundView => 'شوف الأصلية';

  @override
  String get transactionsDetailRefundNotRelated => 'مش مرتبطة';

  @override
  String transactionsDetailReimbSuggest(String merchant) {
    return 'دي من فاتورة $merchant؟';
  }

  @override
  String transactionsDetailDuplicate(String date) {
    return 'شكلها مكررة مع حركة $date بنفس المبلغ';
  }

  @override
  String get transactionsDetailDuplicateKeep => 'سيب الاتنين';

  @override
  String get transactionsDetailDuplicateDelete => 'امسح دي';

  @override
  String transactionsDetailReimbSummary(
    String back,
    String paid,
    String share,
  ) {
    return 'دفعت $paid · رجعلك $back · نصيبك $share';
  }

  @override
  String get transactionsDetailHowTitle => 'إزاي زغلول قرا الرسالة';

  @override
  String get transactionsDetailHowRawA11y => 'نص الرسالة الأصلي';

  @override
  String transactionsDetailHowAmount(String amount) {
    return 'المبلغ $amount';
  }

  @override
  String transactionsDetailHowMerchant(String merchant) {
    return 'التاجر $merchant';
  }

  @override
  String transactionsDetailHowConfidence(String percent) {
    return 'ثقة $percent';
  }

  @override
  String transactionsDetailHowTemplate(String templateId) {
    return 'القالب $templateId';
  }

  @override
  String get transactionsDetailHowNone => 'مفيش رسالة للحركة دي.';

  @override
  String get transactionsDetailCategoryChanged => 'اتغير التصنيف';

  @override
  String get transactionsDetailDeleteTitle => 'تمسح الحركة دي؟';

  @override
  String transactionsDetailDeleteBodyAuto(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'مش هتقدر ترجعها بعد كده.',
      'other': 'جت من رسالة، ومش هترجع غير لو دوّرت في الرسايل من جديد.',
    });
    return '$_temp0';
  }

  @override
  String get transactionsDetailDeleteBodyManual => 'مش هتقدر ترجعها بعد كده.';

  @override
  String get transactionsDetailDeleted => 'اتمسحت';

  @override
  String get transactionsDetailGone => 'الحركة دي مبقتش موجودة';

  @override
  String categorizationRuleTitle(String category, String merchant) {
    return 'أستخدم $category دايماً لـ $merchant؟';
  }

  @override
  String get categorizationRuleAlways => 'دايماً';

  @override
  String get categorizationRuleOnce => 'المرة دي بس';

  @override
  String categorizationRuleApplyPast(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'وكمان غيّر الـ $n حركة القديمة',
      many: 'وكمان غيّر الـ $n حركة القديمة',
      few: 'وكمان غيّر الـ $n حركات القديمة',
      two: 'وكمان غيّر الحركتين القدام',
      one: 'وكمان غيّر الحركة القديمة',
    );
    return '$_temp0';
  }

  @override
  String get categorizationRuleSaved => 'تمام، هفتكر ده ✓';

  @override
  String transactionsEditTitleAdd(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'income': 'دخل جديد',
      'transfer': 'تحويل جديد',
      'other': 'مصروف جديد',
    });
    return '$_temp0';
  }

  @override
  String get transactionsEditTitleEdit => 'عدّل الحركة';

  @override
  String get transactionsEditTypeA11y => 'نوع الحركة';

  @override
  String get transactionsEditAmountA11y => 'المبلغ';

  @override
  String get transactionsEditCurrency => 'العملة';

  @override
  String get transactionsEditCurrencySearch => 'دوّر على عملة';

  @override
  String get transactionsEditCurrencyFeatured => 'الأكتر استخدام';

  @override
  String get transactionsEditCurrencyAll => 'كل العملات';

  @override
  String get transactionsEditCategory => 'التصنيف';

  @override
  String get transactionsEditChoose => 'اختار';

  @override
  String get transactionsEditMerchant => 'التاجر أو الشخص';

  @override
  String get transactionsEditAccount => 'الحساب';

  @override
  String get transactionsEditFrom => 'من حساب';

  @override
  String get transactionsEditTo => 'لحساب';

  @override
  String get transactionsEditWhichBalance => 'من أنهي رصيد؟';

  @override
  String get transactionsEditDate => 'إمتى';

  @override
  String get transactionsEditNote => 'ملاحظة';

  @override
  String get transactionsEditSameAccount => 'اختار حسابين مختلفين';

  @override
  String get transactionsEditFromShared =>
      'ده اللي فهمته من الرسالة اللي بعتها. راجعه واحفظ.';

  @override
  String get transactionsEditRawTitle => 'نص الرسالة';

  @override
  String ingestionReviewFilterAll(String n) {
    return 'الكل $n';
  }

  @override
  String get ingestionReviewFilterCategory => 'تصنيف';

  @override
  String get ingestionReviewFilterMessages => 'رسايل جديدة';

  @override
  String get ingestionReviewFilterTransfers => 'تحويلات';

  @override
  String ingestionReviewCatOut(String amount, String counterparty) {
    return '$amount لـ $counterparty';
  }

  @override
  String ingestionReviewCatIn(String amount, String counterparty) {
    return '$amount من $counterparty';
  }

  @override
  String ingestionReviewCatAt(String amount, String merchant) {
    return '$amount عند $merchant';
  }

  @override
  String get ingestionReviewCatQuestion => 'كانت إيه دي؟';

  @override
  String ingestionReviewRememberCounterparty(String counterparty) {
    return 'افتكر ده لأي تحويلة لـ $counterparty';
  }

  @override
  String ingestionReviewRememberMerchant(String merchant) {
    return 'افتكر ده لـ $merchant على طول';
  }

  @override
  String ingestionReviewCategorized(String category) {
    return 'اتحطت في $category';
  }

  @override
  String get ingestionReviewNewBank => 'بنك جديد';

  @override
  String ingestionReviewGenFrom(String sender) {
    return 'من $sender';
  }

  @override
  String ingestionReviewGenGuessOut(String amount, String merchant) {
    return 'توقعنا: $amount عند $merchant';
  }

  @override
  String ingestionReviewGenGuessNoMerchant(String amount) {
    return 'توقعنا: $amount';
  }

  @override
  String ingestionReviewGenGuessIn(String amount) {
    return 'توقعنا: $amount دخلوا';
  }

  @override
  String get ingestionReviewGenLowConfidence =>
      'مش متأكد أوي، بص عليها قبل ما أسجلها';

  @override
  String get ingestionReviewRequestBank => 'اطلب دعم البنك ده';

  @override
  String ingestionReviewUnreadTitle(String sender) {
    return 'رسالة من $sender مقدرتش أفهمها';
  }

  @override
  String get ingestionReviewUnreadShow => 'شوف الرسالة';

  @override
  String get ingestionReviewUnreadEnter => 'اكتب التفاصيل';

  @override
  String ingestionReviewXferTitle(String amount, String card) {
    return '$amount في $card، تبع أنهي تحويلة؟';
  }

  @override
  String ingestionReviewXferOption(String amount, String card, String time) {
    return '$amount من $card · $time';
  }

  @override
  String get ingestionReviewXferNotMine => 'مش تحويلة مني';

  @override
  String get ingestionReviewSwipeAcceptA11y => 'وافق على الاقتراح';

  @override
  String get ingestionReviewSwipeDismissA11y => 'سيبها';

  @override
  String get ingestionReviewDismissed => 'اتشالت من المراجعة';

  @override
  String get ingestionReviewEmptyTitle => 'كله تمام! مفيش حاجة مستنية رأيك ✨';

  @override
  String ingestionAlwaysSenderTitle(String sender) {
    return 'أقرا رسايل $sender على طول؟';
  }

  @override
  String ingestionAlwaysSenderBody(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'هتفضل توصلك هنا للمراجعة لحد ما تأكد $n رسالة منه، وبعد كده هسجلها لوحدي.',
      many:
          'هتفضل توصلك هنا للمراجعة لحد ما تأكد $n رسالة منه، وبعد كده هسجلها لوحدي.',
      few:
          'هتفضل توصلك هنا للمراجعة لحد ما تأكد $n رسايل منه، وبعد كده هسجلها لوحدي.',
      two: 'هتفضل توصلك هنا للمراجعة لحد ما تأكد رسالتين منه، وبعد كده هسجلها لوحدي.',
      one: 'هتفضل توصلك هنا للمراجعة لحد ما تأكد رسالة واحدة منه، وبعد كده هسجلها لوحدي.',
      zero: 'من هنا ورايح هسجل رسايله لوحدي.',
    );
    return '$_temp0';
  }

  @override
  String get ingestionAlwaysSenderYes => 'أيوه، على طول';

  @override
  String get ingestionRequestBankTitle => 'اطلب دعم بنكك';

  @override
  String get ingestionRequestBankName => 'اسم البنك';

  @override
  String get ingestionRequestBankCountry => 'البلد';

  @override
  String get ingestionRequestBankChannel => 'تنبيهاته بتوصل إزاي؟';

  @override
  String get ingestionRequestBankPrivacy =>
      'هنبعت اسم البنك وبلده ونوع التنبيه بس. عمرنا ما هنبعت الرسالة نفسها.';

  @override
  String get ingestionRequestBankSent => 'وصل طلبك ✓ شكراً!';

  @override
  String get ingestionRequestBankFailed =>
      'مقدرتش أبعته دلوقتي. حفظته، وتقدر تبعته تاني بعدين.';

  @override
  String ingestionRequestBankNameLength(String max, String min) {
    return 'اسم البنك لازم يكون من $min لـ $max حرف';
  }

  @override
  String get ingestionRequestBankCountryRequired => 'اختار البلد';

  @override
  String get transfersSplitTitle => 'تقسيم العزومة';

  @override
  String transfersSplitHeader(String amount, String merchant) {
    return '$merchant · $amount';
  }

  @override
  String get transfersSplitPeople => 'الناس';

  @override
  String get transfersSplitAddPerson => 'ضيف حد';

  @override
  String get transfersSplitPersonHint => 'الاسم';

  @override
  String transfersSplitShareA11y(String name) {
    return 'نصيب $name';
  }

  @override
  String transfersSplitRemovePerson(String name) {
    return 'شيل $name';
  }

  @override
  String get transfersSplitEqual => 'قسّم بالتساوي';

  @override
  String get transfersSplitPaidBack => 'رجع';

  @override
  String get transfersSplitWaiting => 'مستني';

  @override
  String transfersSplitPaidDetail(String amount, String date, String source) {
    return '$amount · $source · $date';
  }

  @override
  String get transfersSplitYourShare => 'دفعت إنت فعلاً';

  @override
  String get transfersSplitSuggestions => 'اقتراحات';

  @override
  String transfersSplitSuggestion(String amount, String date, String person) {
    return '$amount من $person · $date، من العزومة دي؟';
  }

  @override
  String get transfersSplitUnassign => 'شيلها من العزومة دي';

  @override
  String get transfersSplitUnassigned => 'اتشالت، ورجعت تتحسب دخل عادي';

  @override
  String get transfersSplitSaved => 'اتحفظ التقسيم ✓';

  @override
  String transfersAssignHeader(String amount, String person) {
    return '$amount من $person';
  }

  @override
  String get transfersAssignTitle => 'وزّعها على مصاريف';

  @override
  String get transfersAssignSearch => 'دوّر في المصاريف الأخيرة';

  @override
  String transfersAssignUnassigned(String amount) {
    return 'مش متوزع: $amount، هيفضل دخل';
  }

  @override
  String transfersAssignEmpty(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'مفيش مصاريف في آخر $n يوم',
      many: 'مفيش مصاريف في آخر $n يوم',
      few: 'مفيش مصاريف في آخر $n أيام',
      two: 'مفيش مصاريف في آخر يومين',
      one: 'مفيش مصاريف من امبارح',
    );
    return '$_temp0';
  }

  @override
  String get transfersAssignSearchAll => 'دوّر في كل المصاريف';

  @override
  String get transfersAssignSaved => 'اتوزعت ✓';

  @override
  String get transfersSplitErrorShareZero => 'النصيب لازم يكون أكبر من صفر';

  @override
  String get transfersSplitErrorSharesExceed => 'مجموع الأنصبة أكبر من المصروف';

  @override
  String get transfersAssignErrorExceedsIncoming =>
      'وزعت أكتر من المبلغ اللي جالك';

  @override
  String get transfersAssignErrorExceedsExpense =>
      'الفلوس الراجعة أكتر من المصروف نفسه';

  @override
  String get transfersSplitErrorCurrency => 'عملة مختلفة، مينفعش تربطهم';

  @override
  String get transfersLinkTitle => 'ربط تحويلة لنفسي';

  @override
  String transfersLinkSource(String amount, String card, String date) {
    return '$amount · $card · $date';
  }

  @override
  String get transfersLinkPick => 'اختار الحركة اللي تقابلها';

  @override
  String transfersLinkAfterMinutes(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بعدها بـ $n دقيقة',
      many: 'بعدها بـ $n دقيقة',
      few: 'بعدها بـ $n دقايق',
      two: 'بعدها بدقيقتين',
      one: 'بعدها بدقيقة',
      zero: 'في نفس الدقيقة',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkBeforeMinutes(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبلها بـ $n دقيقة',
      many: 'قبلها بـ $n دقيقة',
      few: 'قبلها بـ $n دقايق',
      two: 'قبلها بدقيقتين',
      one: 'قبلها بدقيقة',
      zero: 'في نفس الدقيقة',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkAfterHours(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بعدها بـ $n ساعة',
      many: 'بعدها بـ $n ساعة',
      few: 'بعدها بـ $n ساعات',
      two: 'بعدها بساعتين',
      one: 'بعدها بساعة',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkBeforeHours(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبلها بـ $n ساعة',
      many: 'قبلها بـ $n ساعة',
      few: 'قبلها بـ $n ساعات',
      two: 'قبلها بساعتين',
      one: 'قبلها بساعة',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkAfterDays(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بعدها بـ $n يوم',
      many: 'بعدها بـ $n يوم',
      few: 'بعدها بـ $n أيام',
      two: 'بعدها بيومين',
      one: 'بعدها بيوم',
      zero: 'في نفس اليوم',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkBeforeDays(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبلها بـ $n يوم',
      many: 'قبلها بـ $n يوم',
      few: 'قبلها بـ $n أيام',
      two: 'قبلها بيومين',
      one: 'قبلها بيوم',
      zero: 'في نفس اليوم',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkImpliedRate(String fromCurrency, String rate) {
    return 'سعر التحويل ≈ $rate لكل $fromCurrency';
  }

  @override
  String get transfersLinkLinked => 'اتربطوا ✓ ومش هيتحسبوا مصروف';

  @override
  String get transfersLinkEmptyTitle => 'ملقيتش حركة تقابلها';

  @override
  String get transfersLinkEmptyBody =>
      'ممكن البنك التاني مش بيبعت رسايل. تقدر تعلّمها تحويلة لنفسك برضه، ومش هتتحسب مصروف.';

  @override
  String get transfersLinkMarkAnyway => 'علّمها تحويلة لنفسي';

  @override
  String get transfersLinkErrorAmounts => 'المبلغين لازم يكونوا زي بعض';

  @override
  String get transfersLinkErrorAccount => 'اختار حساب تاني';

  @override
  String get transfersLinkErrorDirection => 'لازم واحدة خارجة وواحدة داخلة';

  @override
  String get accountsOverviewTitle => 'فلوسي';

  @override
  String get accountsOverviewAdd => 'ضيف';

  @override
  String get accountsOverviewAddAccount => 'كارت أو حساب';

  @override
  String get accountsOverviewAddAsset => 'أصل (دهب، شهادة…)';

  @override
  String get accountsOverviewNetWorth => 'اللي حيلتك كله';

  @override
  String get accountsOverviewOtherCurrenciesA11y => 'عملات تانية';

  @override
  String get accountsOverviewAccountsTitle => 'كروتك وحساباتك';

  @override
  String get accountsOverviewCompare => 'قارن';

  @override
  String accountsOverviewAsOf(String when) {
    return 'آخر تحديث $when';
  }

  @override
  String accountsOverviewCreditAvailable(String limit) {
    return 'متاح من $limit';
  }

  @override
  String accountsOverviewMoreCurrencies(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'وكمان $n عملة',
      many: 'وكمان $n عملة',
      few: 'وكمان $n عملات',
      two: 'وكمان عملتين',
      one: 'وكمان عملة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get accountsOverviewCashSub => 'يدوي وصوت';

  @override
  String get accountsOverviewNotTracked => 'مش متتبع';

  @override
  String get accountsOverviewHiddenEntry => 'الحسابات المخفية';

  @override
  String get accountsOverviewAssetsTitle => 'دهبك وشهاداتك';

  @override
  String get accountsOverviewPrices => 'الأسعار';

  @override
  String get accountsOverviewAssetsLocked =>
      'تابع دهبك وشهاداتك وكل أصولك في مكان واحد';

  @override
  String get accountsOverviewZakah => 'الزكاة';

  @override
  String get accountsOverviewEmptyTitle =>
      'الحسابات بتظهر لوحدها من رسايل البنك';

  @override
  String get accountsOverviewEmptyAdd => 'ضيف حساب بإيدك';

  @override
  String get accountsAddTypeTitle => 'تضيف إيه؟';

  @override
  String get accountsAddTypeInfo =>
      'الكروت بتتضاف لوحدها أول ما توصل رسالة. ضيف بإيدك لو لسه مفيش رسايل.';

  @override
  String get accountsAddTypeCredit => 'كريدت كارد';

  @override
  String get accountsAddTypeCreditSub => 'الليميت وميعاد السداد';

  @override
  String get accountsAddTypeDebit => 'كارت ديبت / حساب بنك';

  @override
  String get accountsAddTypeDebitSub => 'مرتب ومصاريف';

  @override
  String get accountsAddTypeWallet => 'محفظة';

  @override
  String get accountsAddTypeWalletSub => 'فودافون كاش، أورانج كاش، إي آند كاش';

  @override
  String get accountsAddTypeMulti => 'حساب بأكتر من عملة';

  @override
  String get accountsAddTypeMultiSub => 'Wise، Revolut، Payoneer';

  @override
  String get accountsAddTypeBnpl => 'تقسيط';

  @override
  String get accountsAddTypeBnplSub => 'فاليو، سيمبل، كونتكت';

  @override
  String get accountsAddBankTitle => 'من أنهي بنك؟';

  @override
  String get accountsAddBankSearch => 'دوّر على بنك…';

  @override
  String get accountsAddBankEgypt => 'بنوك مصر';

  @override
  String get accountsAddBankAbroad => 'بنوك برّه وأونلاين';

  @override
  String get accountsAddBankNotListed => 'بنكي مش موجود';

  @override
  String get accountsAddBankNotListedSub =>
      'ضيفه باسمه، وزغلول هيحاول يفهم رسايله';

  @override
  String get accountsAddBankNoResults => 'مفيش بنك بالاسم ده';

  @override
  String get accountsAddBankRequired => 'اختار بنك';

  @override
  String get accountsAddedTitle => 'الكارت اتضاف! ✨';

  @override
  String accountsAddedDueDay(String day) {
    return 'السداد يوم $day كل شهر';
  }

  @override
  String get accountsAddedWaitingBalance =>
      'هيتحدث مع أول رسالة فيها الرصيد المتاح';

  @override
  String accountsAddedEmptyBody(String bank, String last4) {
    return 'أول ما توصلك رسالة من $bank على $last4 هتظهر هنا لوحدها.';
  }

  @override
  String get accountsAddedImport => 'ضيف كشف حساب الكارت';

  @override
  String get accountsAddedImportSub => 'PDF من تطبيق البنك';

  @override
  String get accountsAddedManual => 'سجّل حركة بإيدك';

  @override
  String get accountsAddedManualSub => 'على الكارت ده';

  @override
  String get accountsDetailAvailable => 'فاضل في الكارت';

  @override
  String accountsDetailAvailableOf(String available, String limit) {
    return '$available من $limit';
  }

  @override
  String accountsDetailLimitUsed(String percent) {
    return 'مستخدم $percent من الليميت';
  }

  @override
  String get accountsDetailBalance => 'الرصيد';

  @override
  String accountsDetailAsOf(String when) {
    return 'آخر تحديث $when';
  }

  @override
  String get accountsDetailBalanceUnknown => 'هيظهر مع أول رسالة فيها رصيد';

  @override
  String accountsDetailDue(String date) {
    return 'ميعاد السداد $date';
  }

  @override
  String get accountsDetailSpent => 'صرفت';

  @override
  String get accountsDetailDonutA11y => 'توزيع الصرف على التصنيفات';

  @override
  String get accountsDetailTopMerchants => 'أكتر أماكن صرفت فيها';

  @override
  String get accountsDetailTrend => 'الصرف شهر بشهر';

  @override
  String get accountsDetailIncomeRefunds => 'دخل ومرتجعات';

  @override
  String get accountsDetailRecent => 'آخر الحركات';

  @override
  String get accountsDetailAllTransactions => 'كل حركات الكارت';

  @override
  String get accountsDetailCapture => 'زغلول بيقرا إيه';

  @override
  String get accountsDetailMenuCapture => 'زغلول يقرا إيه من الكارت';

  @override
  String get accountsDetailMenuMerge => 'ادمجه مع كارت تاني';

  @override
  String get accountsDetailMenuHide => 'اخفي الحساب';

  @override
  String get accountsDetailEmpty => 'مفيش صرف على الكارت ده في الفترة دي';

  @override
  String accountsDetailIgnoredBanner(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'مش متتبع: الرسايل وApple Pay مقفولين للكارت ده',
      'other': 'مش متتبع: الرسايل والإشعارات مقفولة للكارت ده',
    });
    return '$_temp0';
  }

  @override
  String get accountsDetailTrackAgain => 'تابعه تاني';

  @override
  String get accountsCompareTitle => 'مقارنة الكروت';

  @override
  String get accountsCompareTotal => 'الإجمالي';

  @override
  String get accountsCompareChoose => 'اختار الكروت';

  @override
  String accountsCompareMax(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تقدر تختار لحد $n كارت',
      many: 'تقدر تختار لحد $n كارت',
      few: 'تقدر تختار لحد $n كروت',
      two: 'تقدر تختار لحد كارتين',
      one: 'تقدر تختار كارت واحد',
    );
    return '$_temp0';
  }

  @override
  String get accountsCompareOtherCurrency =>
      'الكروت اللي بعملة تانية بتظهر لما تختار عملتها';

  @override
  String get accountsCompareEmpty =>
      'المقارنة محتاجة كارتين على الأقل فيهم صرف';

  @override
  String accountsCompareCellA11y(String amount, String card, String category) {
    return '$category، $card: $amount';
  }

  @override
  String get accountsEditTitleEdit => 'تفاصيل الكارت';

  @override
  String get accountsEditTitleNew => 'كارت جديد';

  @override
  String get accountsEditName => 'اسم الكارت';

  @override
  String get accountsEditBank => 'البنك';

  @override
  String get accountsEditBankAuto => 'اتعرف من الرسايل';

  @override
  String get accountsEditLast4 => 'آخر أربع أرقام';

  @override
  String accountsEditLast4Hint(String sample) {
    return 'في الرسالة بيبان كده: «$sample»، عشان زغلول يعرف الكارت.';
  }

  @override
  String get accountsEditType => 'النوع';

  @override
  String get accountsEditCurrency => 'العملة';

  @override
  String get accountsEditBalances => 'الأرصدة';

  @override
  String get accountsEditAddCurrency => 'ضيف عملة';

  @override
  String get accountsEditLimit => 'الليميت';

  @override
  String get accountsEditDueDay => 'يوم السداد';

  @override
  String accountsEditDueReminder(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'هفكرك قبل ميعاد السداد بـ $n يوم.',
      many: 'هفكرك قبل ميعاد السداد بـ $n يوم.',
      few: 'هفكرك قبل ميعاد السداد بـ $n أيام.',
      two: 'هفكرك قبل ميعاد السداد بيومين.',
      one: 'هفكرك قبل ميعاد السداد بيوم.',
      zero: 'هفكرك يوم السداد نفسه.',
    );
    return '$_temp0';
  }

  @override
  String get accountsEditCaptureTitle => 'زغلول يقرا إيه من الكارت ده؟';

  @override
  String get accountsEditCaptureLink => 'زغلول بيقرا إيه';

  @override
  String get accountsEditMerge => 'ادمجه مع كارت تاني';

  @override
  String get accountsEditHide => 'اخفي الحساب ده';

  @override
  String get accountsEditHideHint =>
      'مش هيظهر في القوايم، بس حركاته لسه محسوبة في الأرقام والميزانية والشارتات.';

  @override
  String get accountsEditHidden => 'الحساب اتخفى. حركاته لسه محسوبة.';

  @override
  String get accountsEditDuplicate => 'الكارت ده موجود، افتحه؟';

  @override
  String get accountsEditOpenExisting => 'افتحه';

  @override
  String get accountsEditErrorLimit => 'الليميت ميكونش بالسالب';

  @override
  String accountsEditErrorDueDay(String max, String min) {
    return 'اختار يوم من $min لـ $max';
  }

  @override
  String get accountsEditSaved => 'اتحفظ ✓';

  @override
  String get accountsMergePickTitle => 'تدمجه مع أنهي كارت؟';

  @override
  String accountsMergeConfirmTitle(
    int count,
    String fromCard,
    String n,
    String toCard,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تنقل $n حركة من $fromCard لـ $toCard؟',
      many: 'تنقل $n حركة من $fromCard لـ $toCard؟',
      few: 'تنقل $n حركات من $fromCard لـ $toCard؟',
      two: 'تنقل حركتين من $fromCard لـ $toCard؟',
      one: 'تنقل حركة واحدة من $fromCard لـ $toCard؟',
      zero: 'تدمج $fromCard في $toCard؟',
    );
    return '$_temp0';
  }

  @override
  String get accountsMergeConfirmBody => 'الكارتين هيبقوا كارت واحد.';

  @override
  String get accountsMergeCopyCapture => 'انقل إعدادات القراية كمان';

  @override
  String get accountsMergeConfirm => 'ادمج';

  @override
  String get accountsMergeDifferentBank =>
      'الكارتين من بنكين مختلفين. متأكد إنهم نفس الكارت؟';

  @override
  String get accountsMergeDifferentBankConfirm => 'أيوه، ادمج';

  @override
  String get accountsMergeErrorSelf => 'مينفعش تدمج الكارت في نفسه';

  @override
  String get accountsMergeDone => 'اتدمجوا ✓';

  @override
  String get captureSettingsTitle => 'زغلول بيقرا منين';

  @override
  String get captureSettingsSources => 'المصادر';

  @override
  String get captureSettingsOn => 'شغال';

  @override
  String get captureSettingsOff => 'مقفول';

  @override
  String get captureSettingsActive => 'شغال';

  @override
  String get captureSettingsUnknown => 'لسه مش متأكدين';

  @override
  String get captureSettingsSmsIos => 'عن طريق الاختصارات';

  @override
  String get captureSettingsCheckSetup => 'اتأكد من الإعداد';

  @override
  String get captureSettingsShare => 'ابعت أو الزق رسالة';

  @override
  String get captureSettingsNotTracked => 'مش متتبعين';

  @override
  String get captureSettingsNotTrackedEmpty => 'كل كروتك متتبعة';

  @override
  String captureSettingsIgnoredChannels(String channels) {
    return '$channels مقفولة';
  }

  @override
  String get captureSettingsAddIgnore => 'متتابعش كارت أو بنك';

  @override
  String get captureSettingsTools => 'أدوات';

  @override
  String get captureSettingsRescan => 'دوّر في الرسايل القديمة تاني';

  @override
  String get captureSettingsBanks => 'البنوك اللي زغلول بيفهمها';

  @override
  String get captureSettingsRequestBank => 'اطلب دعم بنكك';

  @override
  String get captureSettingsTemplates => 'قوالب رسايل خاصة بيك';

  @override
  String get captureSettingsUnreadable =>
      'في رسايل مقدرتش أقراها. دوّر في الرسايل تاني عشان ميفوتكش حاجة.';

  @override
  String get captureIgnoreTitle => 'متتابعش كارت أو بنك';

  @override
  String get captureIgnoreBank => 'البنك';

  @override
  String get captureIgnoreLast4 => 'آخر أربع أرقام (اختياري)';

  @override
  String get captureIgnoreLast4Hint => 'سيبه فاضي عشان تبطّل تتابع البنك كله';

  @override
  String get captureIgnoreChannels => 'متقراش من:';

  @override
  String get captureIgnorePrivacy =>
      'اللي تقفله، زغلول هيتجاهل رسايله ومش هيحفظ منها حاجة.';

  @override
  String get captureIgnoreErrorBank => 'اختار البنك';

  @override
  String get captureIgnoreErrorChannel => 'اختار مصدر واحد على الأقل';

  @override
  String get captureIgnoreErrorLast4 => 'سيبه فاضي أو اكتب أربع أرقام';

  @override
  String get captureIgnoreSaved => 'تمام، مش هتابعه';

  @override
  String get captureRescanTitle => 'دوّر في الرسايل القديمة';

  @override
  String get captureRescanDepth => 'لحد إمتى؟';

  @override
  String get captureRescanStart => 'ابدأ';

  @override
  String captureRescanRunning(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بدوّر… لقيت $n حركة جديدة',
      many: 'بدوّر… لقيت $n حركة جديدة',
      few: 'بدوّر… لقيت $n حركات جديدة',
      two: 'بدوّر… لقيت حركتين جداد',
      one: 'بدوّر… لقيت حركة جديدة',
      zero: 'بدوّر…',
    );
    return '$_temp0';
  }

  @override
  String captureRescanDone(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ضفت $n حركة جديدة ✓',
      many: 'ضفت $n حركة جديدة ✓',
      few: 'ضفت $n حركات جديدة ✓',
      two: 'ضفت حركتين جداد ✓',
      one: 'ضفت حركة جديدة ✓',
      zero: 'ملقيتش حركات جديدة ✓',
    );
    return '$_temp0';
  }

  @override
  String get captureRescanNoDuplicates => 'اللي اتسجل قبل كده مش هيتكرر';

  @override
  String captureRescanOfferTitle(String card) {
    return 'أدوّر في الرسايل القديمة على حركات $card؟';
  }

  @override
  String get captureRescanOfferBody =>
      'الرسايل اللي اتقفلت قبل كده متحفظتش، بس ممكن ألاقيها لسه في صندوق الرسايل.';

  @override
  String get captureRescanOfferYes => 'دوّر';

  @override
  String get captureBanksTitle => 'البنوك اللي زغلول بيفهمها';

  @override
  String get captureBanksSearch => 'دوّر على بنك…';

  @override
  String get captureBanksNoResults => 'مفيش بنك بالاسم ده';

  @override
  String captureBanksChannels(String channels) {
    return 'بيتسجل من: $channels';
  }

  @override
  String captureBanksIosNote(String bank) {
    return 'على الآيفون، $bank بيتسجل من Apple Pay والسكرين شوت، وكشوف الحساب مع جولد. الآيفون مش بيسمح لزغلول يقرا إشعارات التطبيقات التانية.';
  }

  @override
  String get captureShareHowTitle => 'إزاي تبعت رسالة لزغلول';

  @override
  String get captureShareHowStep1 => 'افتح رسالة البنك في تطبيق الرسايل';

  @override
  String get captureShareHowStep2 => 'دوس عليها شوية واختار «مشاركة» أو «نسخ»';

  @override
  String get captureShareHowStep3 => 'اختار زغلول، أو افتح زغلول والزقها';

  @override
  String get captureShareHowNote => 'هتشوفها قبل ما تتسجل.';

  @override
  String captureCardControlsTitle(String card) {
    return 'زغلول يقرا إيه من $card؟';
  }

  @override
  String get captureCardControlsSubtitle =>
      'اختار براحتك، وتقدر تغير في أي وقت';

  @override
  String get captureCardControlsSmsIos => 'عن طريق اختصارات الآيفون';

  @override
  String get captureCardControlsApplePaySub => 'الدفع بالموبايل';

  @override
  String get captureCardControlsInfo =>
      'لما تقفل حاجة هنا، رسايل الكارت ده هتتجاهل ومش هتتحفظ.';

  @override
  String captureStopTrackingTitle(String card) {
    return 'تبطّل تتابع $card؟';
  }

  @override
  String get captureStopTrackingExisting => 'الحركات اللي اتسجلت قبل كده:';

  @override
  String get captureStopTrackingKeep => 'سيبهم زي ما هم';

  @override
  String captureStopTrackingDelete(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'امسح الـ $n حركة',
      many: 'امسح الـ $n حركة',
      few: 'امسح الـ $n حركات',
      two: 'امسح الحركتين',
      one: 'امسح حركة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get captureStopTrackingConfirm => 'بطّل المتابعة';

  @override
  String captureStopTrackingDeleteTitle(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمسح $n حركة نهائي؟',
      many: 'تمسح $n حركة نهائي؟',
      few: 'تمسح $n حركات نهائي؟',
      two: 'تمسح الحركتين نهائي؟',
      one: 'تمسح حركة واحدة نهائي؟',
    );
    return '$_temp0';
  }

  @override
  String get captureStopTrackingDeleteBody =>
      'مفيش رجوع. الحركات دي هتتمسح من الموبايل وكل الأرقام هتتحدث.';

  @override
  String get captureStopTrackingDeleteConfirm => 'امسح نهائي';

  @override
  String captureStopTrackingDone(String card) {
    return 'مش هتابع $card تاني';
  }
}
