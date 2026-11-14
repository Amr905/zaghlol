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
  String get backupRestoreReplaceConfirm =>
      'كده كل اللي على التليفون ده هيتمسح وينزل مكانه اللي في النسخة. نكمّل؟';

  @override
  String get backupRestoreReplaceAction => 'استبدل';

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

  @override
  String get commonActionTypeInstead => 'اكتبها بإيدك';

  @override
  String commonUnitGrams(String n) {
    return '$n جرام';
  }

  @override
  String commonUnitPerMonth(String amount) {
    return '$amount في الشهر';
  }

  @override
  String commonUnitPerYear(String amount) {
    return '$amount في السنة';
  }

  @override
  String commonUnitPerDay(String amount) {
    return '$amount في اليوم';
  }

  @override
  String commonUnitVisits(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n زيارة',
      many: '$n زيارة',
      few: '$n زيارات',
      two: 'زيارتين',
      one: 'زيارة واحدة',
    );
    return '$_temp0';
  }

  @override
  String commonUnitOrders(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n أوردر',
      many: '$n أوردر',
      few: '$n أوردرات',
      two: 'أوردرين',
      one: 'أوردر واحد',
    );
    return '$_temp0';
  }

  @override
  String get commonCadenceWeekly => 'كل أسبوع';

  @override
  String get commonCadenceMonthly => 'كل شهر';

  @override
  String get commonCadenceQuarterly => 'كل تلات شهور';

  @override
  String get commonCadenceSemiannual => 'كل ستة شهور';

  @override
  String get commonCadenceYearly => 'كل سنة';

  @override
  String get commonAssetTypeGold => 'دهب';

  @override
  String get commonAssetTypeCertificate => 'شهادة بنك';

  @override
  String get commonAssetTypeForeignCash => 'كاش بعملة';

  @override
  String get commonAssetTypeStocks => 'أسهم وصناديق';

  @override
  String get commonAssetTypeProperty => 'عقار';

  @override
  String get commonAssetTypeCar => 'عربية';

  @override
  String commonKaratLabel(String karat) {
    return 'عيار $karat';
  }

  @override
  String get commonKaratCoin => 'جنيه دهب';

  @override
  String get mascotTapLine9 => 'عايز تعرف فلوسك راحت فين؟ افتح الحسبة';

  @override
  String get mascotTapLine10 => 'أنا بحسب والدهب بيلمع، وإنت بتحوّش';

  @override
  String get insightsTabsCharts => 'الشارتات';

  @override
  String get insightsTabsBudget => 'الميزانية';

  @override
  String get insightsTabsBills => 'الفواتير';

  @override
  String get insightsPeriodTitle => 'الفترة';

  @override
  String get insightsPeriodStart => 'من';

  @override
  String get insightsPeriodEnd => 'لحد';

  @override
  String insightsChartsContext(String cards, String currency, String period) {
    return '$cards · $currency · $period';
  }

  @override
  String get insightsChartsExplain => 'اشرحلي يا زغلول';

  @override
  String get insightsChartsLockedSub => 'شوف الشارت كله مع جولد';

  @override
  String get insightsChartsEmptyCycle => 'بيحيا بعد أول دورة كاملة';

  @override
  String get insightsChartsEmptyNetWorth =>
      'ضيف حسابات أو أصول علشان الشارت ده يشتغل';

  @override
  String get insightsChartsEmptyNetWorthAction => 'افتح فلوسي';

  @override
  String get insightsChartsEmptyFilter => 'مفيش بيانات للفلتر ده في الفترة دي';

  @override
  String get insightsChartsCardError => 'الشارت ده مفتحش. باقي الشارتات تمام.';

  @override
  String get insightsChartsLoadingA11y => 'بحمّل الشارتات';

  @override
  String get insightsChartsOtherSlice => 'حاجات تانية';

  @override
  String get insightsChartTitleCashFlow => 'الداخل والخارج والصافي';

  @override
  String get insightsChartTitleCategories => 'فلوسك رايحة فين؟';

  @override
  String get insightsChartTitleBurnRate => 'سرعة الصرف لحد القبض';

  @override
  String get insightsChartTitleRule503020 => 'ميزان خمسين تلاتين عشرين';

  @override
  String get insightsChartTitleWeekPattern => 'إمتى بتصرف؟';

  @override
  String get insightsChartTitleMerchants => 'أكتر الأماكن اللي بتاخد فلوسك';

  @override
  String get insightsChartTitleVsAverage => 'الدورة دي ضد متوسط تلات دورات';

  @override
  String get insightsChartTitleInstallments => 'أقساطك في الستة شهور الجايين';

  @override
  String get insightsChartTitleSubscriptions => 'الاشتراكات في السنة كلها';

  @override
  String get insightsChartTitleCards => 'الصرف على كروتك ومحافظك';

  @override
  String get insightsChartTitleNetWorth => 'نمو اللي حيلتك كله';

  @override
  String get insightsChartTitleInflation => 'الغلاء على سلتك إنت';

  @override
  String get insightsLegendIncome => 'دخلك';

  @override
  String get insightsLegendSpent => 'صرفت';

  @override
  String get insightsLegendSaved => 'حوشت';

  @override
  String get insightsLegendActual => 'فعلي';

  @override
  String get insightsLegendIdeal => 'الخط المثالي';

  @override
  String get insightsLegendToday => 'النهارده';

  @override
  String get insightsLegendPayday => 'القبض';

  @override
  String get insightsLegendNeeds => 'أساسيات';

  @override
  String get insightsLegendWants => 'رفاهيات';

  @override
  String get insightsLegendSavings => 'تحويش';

  @override
  String get insightsLegendTarget => 'المثالي';

  @override
  String get insightsLegendAverage => 'متوسطك';

  @override
  String get insightsLegendThisCycle => 'الدورة دي';

  @override
  String get insightsLegendInstallments => 'أقساط';

  @override
  String get insightsLegendCardDues => 'كروت وجمعية';

  @override
  String get insightsLegendMonthly => 'في الشهر';

  @override
  String get insightsLegendYearly => 'في السنة';

  @override
  String get insightsLegendSupermarket => 'متوسط فاتورة السوبرماركت';

  @override
  String get insightsLegendDelivery => 'متوسط أوردر الدليفري';

  @override
  String insightsChartA11yCashFlow(String income, String spent, String saved) {
    return 'الداخل والخارج: دخلك $income، صرفت $spent، وحوشت $saved';
  }

  @override
  String insightsChartA11yCategories(
    String category,
    String amount,
    String percent,
  ) {
    return 'فلوسك رايحة فين: $category الأكبر بـ $amount، يعني $percent';
  }

  @override
  String insightsChartA11yBurnRate(
    String spent,
    String budget,
    String cycleDay,
  ) {
    return 'سرعة الصرف: صرفت $spent من $budget في اليوم $cycleDay';
  }

  @override
  String insightsChartA11yRule503020(
    String needsPct,
    String wantsPct,
    String savingsPct,
  ) {
    return 'ميزان خمسين تلاتين عشرين: $needsPct أساسيات، $wantsPct رفاهيات، $savingsPct تحويش';
  }

  @override
  String insightsChartA11yWeekPattern(String peakDay, String amount) {
    return 'إمتى بتصرف: أعلى يوم $peakDay بمتوسط $amount';
  }

  @override
  String insightsChartA11yMerchants(String merchant, String amount) {
    return 'أكتر الأماكن: $merchant الأول بـ $amount';
  }

  @override
  String insightsChartA11yVsAverage(String category, String percent) {
    return 'الدورة دي ضد متوسطك: أكبر زيادة في $category بـ $percent';
  }

  @override
  String insightsChartA11yInstallments(String sum) {
    return 'الأقساط: الشهر ده $sum';
  }

  @override
  String insightsChartA11ySubscriptions(String monthly, String yearly) {
    return 'الاشتراكات: $monthly في الشهر، يعني $yearly في السنة';
  }

  @override
  String insightsChartA11yCards(String card, String percent) {
    return 'الكروت: $card الأكبر بـ $percent من الصرف';
  }

  @override
  String insightsChartA11yNetWorth(String startAmount, String endAmount) {
    return 'اللي حيلتك كله: من $startAmount لـ $endAmount';
  }

  @override
  String insightsChartA11yInflation(String startAmount, String endAmount) {
    return 'الغلاء: فاتورة السوبرماركت من $startAmount لـ $endAmount';
  }

  @override
  String insightsChartDetailLegendRowA11y(
    String category,
    String amount,
    String percent,
  ) {
    return '$category: $amount، $percent. اضغط تشوف الحركات';
  }

  @override
  String insightsChartDetailCardRowA11y(String card, String amount) {
    return '$card: $amount. اضغط تفتح الكارت';
  }

  @override
  String get insightsChartDetailTypingA11y => 'زغلول بيكتب';

  @override
  String get insightsChartDetailTipLabel => 'نصيحة';

  @override
  String get insightsChartDetailDeepLabel => 'تحليل أعمق';

  @override
  String get insightsChartDetailDeepUpsell =>
      'عايز تحليل أعمق؟ جولد بيقارن بالدورة اللي فاتت ويتوقع آخر الدورة.';

  @override
  String insightsChartDetailNeedsData(String need) {
    String _temp0 = intl.Intl.selectLogic(need, {
      'cycle': 'محتاج دورة كاملة علشان أشرحلك الشارت ده',
      'months': 'محتاج تلات دورات علشان أقارنك بنفسك',
      'accounts': 'ضيف حسابات أو أصول وأنا أشرحلك',
      'installments': 'ضيف قسط أو التزام وأنا أشرحلك',
      'subscriptions': 'لسه مفيش اشتراكات. أول ما ألاقي واحد هشرحلك',
      'other': 'محتاج بيانات أكتر علشان أشرح الشارت ده',
    });
    return '$_temp0';
  }

  @override
  String get insightsChartDetailExplainFailed => 'معرفتش أشرح الشارت ده دلوقتي';

  @override
  String get insightsChartDetailLockedTitle => 'الشارت ده في جولد';

  @override
  String get insightsChartDetailLockedBody =>
      'اتفرج على شكله، وافتحه كله مع جولد';

  @override
  String insightsDeepProjection(String state, String projected) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'over': 'بالسرعة دي هتقفل الدورة على $projected، يعني فوق ميزانيتك',
      'other': 'بالسرعة دي هتقفل الدورة على $projected، يعني في حدود ميزانيتك',
    });
    return '$_temp0';
  }

  @override
  String insightsDeepDrivers(
    String merchant,
    String merchant2,
    String merchant3,
  ) {
    return 'أكتر التجار اللي ورا التغيير: $merchant و$merchant2 و$merchant3';
  }

  @override
  String insightsExplainCashFlowBasic(
    String state,
    String income,
    String spent,
    String gap,
    String saved,
    String percent,
  ) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'short':
          'الدورة دي دخلك $income وصرفت $spent، يعني صرفت أكتر من دخلك بـ $gap. خلينا نظبطها سوا.',
      'other':
          'الدورة دي دخلك $income وصرفت $spent، يعني حوشت $saved. ده $percent من دخلك. الله ينور!',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCashFlowTip(
    String state,
    String category,
    String target,
  ) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'short': 'قلل $category بـ $target الدورة الجاية وهتقفل بفايض.',
      'other': 'حوّل $target على الأقل من الفايض ده للادخار قبل ما يتصرف.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCashFlowDeep(String trend, String delta) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'صافي الدورة دي أحسن من الدورة اللي فاتت بـ $delta.',
      'down': 'صافي الدورة دي أقل من الدورة اللي فاتت بـ $delta.',
      'other': 'صافي الدورة دي زي الدورة اللي فاتت تقريباً.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCashFlowDeepTip(String target, String yearly) {
    return 'ثبّت هدف تحوّش $target كل دورة، يعني $yearly في السنة.';
  }

  @override
  String insightsExplainCategoriesBasic(
    String category,
    String percent,
    String amount,
    String category2,
    String percent2,
  ) {
    return '$category واخد $percent من صرفك، يعني $amount. وبعده $category2 بـ $percent2.';
  }

  @override
  String insightsExplainCategoriesTip(String category, String target) {
    return 'حط سقف لـ$category أقل بـ $target من الدورة دي، وهتوفر الفرق.';
  }

  @override
  String insightsExplainCategoriesDeep(
    String trend,
    String category,
    String delta,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': '$category زاد عن الدورة اللي فاتت بـ $delta.',
      'down': '$category قل عن الدورة اللي فاتت بـ $delta.',
      'other': '$category تقريباً زي الدورة اللي فاتت.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCategoriesDeepTip(
    String category,
    String target,
    String yearly,
  ) {
    return 'خفّض $category بـ $target كل دورة، يعني $yearly في السنة.';
  }

  @override
  String insightsExplainBurnRateBasic(
    String state,
    String cycleDay,
    String spent,
    String budget,
    String perDay,
  ) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'over':
          'إنت في اليوم $cycleDay من الدورة وصارف $spent من $budget، يعني فوق الخط المثالي. الباقي يكفي $perDay في اليوم بس.',
      'other':
          'إنت في اليوم $cycleDay من الدورة وصارف $spent من $budget، يعني تحت الخط المثالي. مسموحلك $perDay في اليوم.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainBurnRateTip(String state, String perDay) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'over': 'نزّل صرفك اليومي لـ $perDay لحد القبض علشان الميزانية تكفي.',
      'other':
          'كمّل على نفس الإيقاع، والفرق ده هيبقى فايض آخر الدورة. تقدر تصرف $perDay في اليوم.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainBurnRateDeep(String trend, String delta) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'في نفس اليوم الدورة اللي فاتت كنت صارف أقل بـ $delta.',
      'down': 'في نفس اليوم الدورة اللي فاتت كنت صارف أكتر بـ $delta.',
      'other': 'صرفك زي نفس اليوم في الدورة اللي فاتت تقريباً.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainBurnRateDeepTip(String target) {
    return 'لو خفضت $target من صرفك اليومي هتفضل تحت الخط لحد القبض.';
  }

  @override
  String insightsExplainRule503020Basic(
    String state,
    String needsPct,
    String wantsPct,
    String savingsPct,
  ) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'wantsHigh':
          'صرفك الدورة دي: $needsPct أساسيات و$wantsPct رفاهيات و$savingsPct تحويش. الرفاهيات أعلى من القاعدة المعروفة.',
      'savingsLow':
          'صرفك الدورة دي: $needsPct أساسيات و$wantsPct رفاهيات و$savingsPct تحويش. التحويش أقل من القاعدة المعروفة.',
      'other':
          'صرفك الدورة دي: $needsPct أساسيات و$wantsPct رفاهيات و$savingsPct تحويش. ده قريب من القاعدة المعروفة.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainRule503020Tip(String state, String target) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'wantsHigh': 'نزّل الرفاهيات $target الدورة الجاية وحوّلهم للتحويش.',
      'savingsLow': 'حاول تزود التحويش $target الدورة الجاية.',
      'other': 'حافظ على التحويش ده، وزوده $target لو قدرت.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainRule503020Deep(String trend, String savingsPct) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'التحويش زاد عن الدورة اللي فاتت لـ $savingsPct.',
      'down': 'التحويش نزل عن الدورة اللي فاتت لـ $savingsPct.',
      'other': 'التحويش ثابت تقريباً عن الدورة اللي فاتت.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainRule503020DeepTip(String percent, String yearly) {
    return 'لو التحويش وصل لـ $percent، هتحوّش $yearly في السنة.';
  }

  @override
  String insightsExplainWeekPatternBasic(
    String peakDay,
    String peakDay2,
    String percent,
    String time,
  ) {
    return 'يوم $peakDay و$peakDay2 واخدين $percent من صرفك الأسبوعي، وأكتر وقت إيدك بتفرط فيه حوالين $time.';
  }

  @override
  String insightsExplainWeekPatternTip(String target, String peakDay) {
    return 'حط سقف $target ليوم $peakDay الجاي.';
  }

  @override
  String insightsExplainWeekPatternDeep(
    String trend,
    String peakDay,
    String amount,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'متوسط صرفك يوم $peakDay $amount، وده أعلى من الدورة اللي فاتت.',
      'down': 'متوسط صرفك يوم $peakDay $amount، وده أقل من الدورة اللي فاتت.',
      'other': 'متوسط صرفك يوم $peakDay $amount، زي الدورة اللي فاتت تقريباً.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainWeekPatternDeepTip(
    String peakDay,
    String target,
    String yearly,
  ) {
    return 'لو قللت خروجة $peakDay بـ $target كل أسبوع، هتوفر $yearly في السنة.';
  }

  @override
  String insightsExplainMerchantsBasic(
    String merchant,
    String amount,
    String visits,
    String merchant2,
    String amount2,
  ) {
    return '$merchant في المركز الأول بـ $amount ($visits)، وبعده $merchant2 بـ $amount2.';
  }

  @override
  String insightsExplainMerchantsTip(String merchant) {
    return 'جمّع مشترياتك من $merchant في زيارة واحدة كل أسبوع.';
  }

  @override
  String insightsExplainMerchantsDeep(
    String percent,
    String trend,
    String merchant,
    String delta,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'و$merchant زاد عن الدورة اللي فاتت بـ $delta.',
      'down': 'و$merchant قل عن الدورة اللي فاتت بـ $delta.',
      'other': 'و$merchant زي الدورة اللي فاتت تقريباً.',
    });
    return 'أول تلات تجار واخدين $percent من صرفك. $_temp0';
  }

  @override
  String insightsExplainMerchantsDeepTip(
    String merchant,
    String target,
    String yearly,
  ) {
    return 'لو قللت $merchant بالربع هتوفر $target في الدورة، يعني $yearly في السنة.';
  }

  @override
  String insightsExplainVsAverageBasic(
    String state,
    String category,
    String percent,
    String category2,
    String percent2,
  ) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'both':
          '$category زاد $percent عن متوسط آخر تلات دورات، لكن $category2 نزل $percent2. برافو على ده.',
      'rise': '$category زاد $percent عن متوسط آخر تلات دورات.',
      'drop': '$category2 نزل $percent2 عن متوسط آخر تلات دورات. برافو عليك.',
      'other': 'صرفك الدورة دي قريب من متوسط آخر تلات دورات.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainVsAverageTip(
    String state,
    String category,
    String target,
    String category2,
  ) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'both': 'لو رجّعت $category لمتوسطك هتوفر $target.',
      'rise': 'لو رجّعت $category لمتوسطك هتوفر $target.',
      'drop': 'كمّل على نفس النظام في $category2.',
      'other': 'كمّل على نفس الإيقاع.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainVsAverageDeep(String trend, String delta) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'في الإجمالي إنت فوق متوسطك بـ $delta.',
      'down': 'في الإجمالي إنت تحت متوسطك بـ $delta.',
      'other': 'في الإجمالي إنت على متوسطك تقريباً.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainVsAverageDeepTip(String category, String target) {
    return 'حط حد لـ $category على قد متوسطك، يعني $target في الدورة.';
  }

  @override
  String insightsExplainInstallmentsBasic(
    String sum,
    String item,
    String month,
  ) {
    return 'الشهر ده عليك $sum أقساط والتزامات. $item هيخلص في $month.';
  }

  @override
  String insightsExplainInstallmentsTip(String item) {
    return 'متدخلش في قسط جديد قبل ما $item يخلص.';
  }

  @override
  String insightsExplainInstallmentsDeep(String amount, String average) {
    return 'في الستة شهور الجايين هتدفع $amount كلهم، بمتوسط $average في الشهر.';
  }

  @override
  String insightsExplainInstallmentsDeepTip(String item, String monthly) {
    return 'لما $item يخلص هيفضل لك $monthly كل شهر.';
  }

  @override
  String insightsExplainSubscriptionsBasic(String monthly, String yearly) {
    return 'الاشتراكات $monthly في الشهر، يعني $yearly في السنة. الصغير بيبان فكة، بس لما بيتجمع بيفرق.';
  }

  @override
  String insightsExplainSubscriptionsTip(String item, String target) {
    return 'راجع $item، ولو مش بتستخدمه إلغاؤه بيوفر $target في السنة.';
  }

  @override
  String insightsExplainSubscriptionsDeep(String trend, String delta) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'الاشتراكات زادت $delta في الشهر عن تلات شهور فاتت.',
      'down': 'الاشتراكات قلت $delta في الشهر عن تلات شهور فاتت.',
      'other': 'الاشتراكات ثابتة عن تلات شهور فاتت.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainSubscriptionsDeepTip(String target) {
    return 'لو ألغيت أغلى اتنين مش بتستخدمهم هتوفر $target في السنة.';
  }

  @override
  String insightsExplainCardsBasic(
    String state,
    String percent,
    String card,
    String card2,
    String percent2,
    String utilisation,
  ) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'credit':
          '$percent من صرفك طلع من $card، وبعده $card2 بـ $percent2. استخدامك من ليميت الكريدت $utilisation.',
      'other': '$percent من صرفك طلع من $card، وبعده $card2 بـ $percent2.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCardsTip(String state) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'credit': 'خلّي استخدام الكريدت تحت النص وسدّده قبل ميعاده.',
      'other': 'ركّز مصاريفك اليومية على كارت واحد علشان تتابعها أسهل.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCardsDeep(String trend, String card) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'نصيب $card من صرفك زاد عن الدورة اللي فاتت.',
      'down': 'نصيب $card من صرفك قل عن الدورة اللي فاتت.',
      'other': 'نصيب $card من صرفك ثابت عن الدورة اللي فاتت.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCardsDeepTip(
    String amount,
    String card,
    String target,
  ) {
    return 'صرفت $amount من $card الدورة دي. حط له سقف $target للدورة الجاية.';
  }

  @override
  String insightsExplainNetWorthBasic(
    String trend,
    String startAmount,
    String month,
    String endAmount,
    String month2,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up':
          'اللي حيلتك زاد من $startAmount في $month لـ $endAmount في $month2.',
      'down':
          'اللي حيلتك نزل من $startAmount في $month لـ $endAmount في $month2.',
      'other': 'اللي حيلتك ثابت تقريباً حوالين $endAmount.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainNetWorthTip(String assetType, String percent) {
    return '$assetType هو أكبر جزء من اللي حيلتك بـ $percent. خد بالك لو كله في حاجة واحدة.';
  }

  @override
  String insightsExplainNetWorthDeep(
    String trend,
    String percent,
    String assetType2,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'نموك الإجمالي $percent، وأكتر حاجة زوّدته $assetType2.',
      'down': 'اللي حيلتك نزل $percent، وأكتر حاجة أثرت فيه $assetType2.',
      'other': 'مفيش تغيير كبير في الفترة دي.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainNetWorthDeepTip(String projected) {
    return 'بنفس المعدل ده ممكن توصل لـ $projected بعد سنة. ده تقدير بس.';
  }

  @override
  String insightsExplainInflationBasic(
    String trend,
    String startAmount,
    String month,
    String endAmount,
    String percent,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up':
          'متوسط فاتورة السوبرماركت كان $startAmount في $month ودلوقتي $endAmount، يعني زاد $percent.',
      'down':
          'متوسط فاتورة السوبرماركت كان $startAmount في $month ودلوقتي $endAmount، يعني نزل $percent.',
      'other': 'متوسط فاتورة السوبرماركت ثابت حوالين $endAmount.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainInflationTip(String category) {
    return 'جرّب بدائل أرخص في $category، هي أكتر حاجة سعرها زاد عليك.';
  }

  @override
  String insightsExplainInflationDeep(String average, String previous) {
    return 'متوسط أوردر الدليفري بقى $average بدل $previous.';
  }

  @override
  String insightsExplainInflationDeepTip(String target, String yearly) {
    return 'لو نزّلت متوسط الفاتورة $target، هتوفر $yearly في السنة بنفس عدد الزيارات.';
  }

  @override
  String budgetOverviewCycle(String start, String end) {
    return '$start لحد $end';
  }

  @override
  String budgetOverviewDaysLeft(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'فاضل $n يوم',
      many: 'فاضل $n يوم',
      few: 'فاضل $n أيام',
      two: 'فاضل يومين',
      one: 'آخر يوم',
    );
    return '$_temp0';
  }

  @override
  String get budgetOverviewCalendarMonth => 'الشهر الميلادي';

  @override
  String get budgetOverviewSetPayday => 'حدد يوم القبض';

  @override
  String budgetOverviewOverall(String spent, String budget) {
    return '$spent من $budget';
  }

  @override
  String budgetOverviewSafePerDay(String perDay) {
    return 'مسموحلك $perDay في اليوم';
  }

  @override
  String budgetOverviewCurrencyNote(String currency) {
    return 'الميزانية دي بـ$currency بس';
  }

  @override
  String budgetOverviewRowAmounts(String spent, String limit) {
    return '$spent / $limit';
  }

  @override
  String get budgetOverviewStatusNear => 'قربت تخلص';

  @override
  String get budgetOverviewStatusFull => 'خلصت';

  @override
  String budgetOverviewStatusOver(String gap) {
    return 'عدّت بـ $gap';
  }

  @override
  String budgetOverviewRowA11y(
    String category,
    String spent,
    String limit,
    String percent,
  ) {
    return '$category: صرفت $spent من $limit، $percent';
  }

  @override
  String get budgetOverviewNotBudgeted => 'من غير ميزانية';

  @override
  String get budgetOverviewNotBudgetedSub => 'صرف في تصنيفات ملهاش حد';

  @override
  String get budgetOverviewEdit => 'عدّل الميزانية';

  @override
  String get budgetOverviewPrevA11y => 'الدورة اللي قبلها';

  @override
  String get budgetOverviewNextA11y => 'الدورة اللي بعدها';

  @override
  String get budgetOverviewEmptyTitle => 'حط حدود وشوف مسموحلك تصرف كام';

  @override
  String get budgetOverviewEmptyBody =>
      'صرف الدورة دي ظاهر تحت لحد ما تحط ميزانية.';

  @override
  String get budgetOverviewEmptyAction => 'حط ميزانية';

  @override
  String get budgetOverviewLoadingA11y => 'بحمّل الميزانية';

  @override
  String get budgetEditTitle => 'الميزانية';

  @override
  String get budgetEditCurrency => 'عملة الميزانية';

  @override
  String get budgetEditOverall => 'الإجمالي';

  @override
  String get budgetEditOverallSum => 'مجموع التصنيفات';

  @override
  String get budgetEditOverallSet => 'إجمالي أحدده أنا';

  @override
  String get budgetEditCategories => 'حد كل تصنيف';

  @override
  String get budgetEditLimitHint => 'سيبه فاضي لو مش عايز حد';

  @override
  String get budgetEditAlerts => 'نبّهني لما أوصل لـ';

  @override
  String get budgetEditAlertFirst => 'التنبيه الأول';

  @override
  String get budgetEditAlertSecond => 'التنبيه التاني';

  @override
  String get budgetEditRollover => 'رحّل اللي فاضل للدورة الجاية';

  @override
  String get budgetEditRolloverHint =>
      'اللي ما اتصرفش بيتضاف لميزانية الدورة الجاية.';

  @override
  String get budgetEditAnnual => 'ميزانيات سنوية';

  @override
  String get budgetEditAnnualHint =>
      'للحاجات اللي بتتدفع مرة في السنة، زي المصاريف المدرسية';

  @override
  String get budgetEditPayday => 'يوم القبض';

  @override
  String get budgetEditErrorLimit => 'الحد مينفعش يكون بالسالب';

  @override
  String budgetEditErrorThreshold(String min, String max) {
    return 'النسبة لازم تبقى بين $min و$max';
  }

  @override
  String get budgetEditErrorOrder => 'التنبيه الأول لازم يبقى أقل من التاني';

  @override
  String get budgetEditSaved => 'الميزانية اتحفظت ✓';

  @override
  String get budgetAnnualTitle => 'ميزانيات سنوية';

  @override
  String get budgetAnnualEmpty => 'لسه مفيش ميزانيات سنوية';

  @override
  String get budgetAnnualAdd => 'ضيف ميزانية سنوية';

  @override
  String recurringBillsSummary(String due, String subs) {
    return 'الشهر ده: $due مستحقة · $subs اشتراكات في الشهر';
  }

  @override
  String recurringBillsDetected(String merchant, String amount) {
    return 'لقيت اشتراك: $merchant بـ $amount في الشهر';
  }

  @override
  String get recurringBillsTrack => 'تابعه';

  @override
  String get recurringBillsNotSub => 'مش اشتراك';

  @override
  String get recurringBillsUpcoming => 'اللي جاي';

  @override
  String recurringBillsInstallmentRow(String name, String index, String total) {
    return '$name · القسط $index من $total';
  }

  @override
  String get recurringBillsLastOne => 'آخر قسط';

  @override
  String get recurringBillsMarkPaid => 'اتدفع';

  @override
  String get recurringBillsPaid => 'اتدفع ✓';

  @override
  String get recurringBillsAutoPaid => 'اتسجل لوحده من الحركة';

  @override
  String get recurringBillsDueToday => 'النهارده';

  @override
  String recurringBillsDueIn(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بعد $n يوم',
      many: 'بعد $n يوم',
      few: 'بعد $n أيام',
      two: 'بعد يومين',
      one: 'بكرة',
    );
    return '$_temp0';
  }

  @override
  String recurringBillsOverdue(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'متأخر $n يوم',
      many: 'متأخر $n يوم',
      few: 'متأخر $n أيام',
      two: 'متأخر يومين',
      one: 'متأخر يوم',
    );
    return '$_temp0';
  }

  @override
  String get recurringBillsKindSubscription => 'اشتراك';

  @override
  String get recurringBillsKindInstallment => 'قسط';

  @override
  String get recurringBillsKindCard => 'سداد كارت';

  @override
  String get recurringBillsKindGameya => 'جمعية';

  @override
  String get recurringBillsGameyaManual => 'الجمعية بتتسجل بإيدك';

  @override
  String get recurringBillsSubsTitle => 'الاشتراكات';

  @override
  String get recurringBillsSubsYear => 'في السنة كلها';

  @override
  String recurringBillsSubRow(String monthly, String yearly) {
    return '$monthly في الشهر · $yearly في السنة';
  }

  @override
  String recurringBillsSubsTotal(String monthly, String yearly) {
    return 'المجموع $monthly في الشهر، يعني $yearly في السنة';
  }

  @override
  String get recurringBillsAdd => 'ضيف فاتورة أو قسط';

  @override
  String get recurringBillsEmptyTitle => 'لسه مفيش فواتير ولا أقساط';

  @override
  String get recurringBillsEmptyBody =>
      'هلاقي الاشتراكات لوحدي من حركاتك، وتقدر تضيف أي قسط بإيدك.';

  @override
  String recurringBillsPaidSnack(String name) {
    return 'اتسجل إن $name اتدفع ✓';
  }

  @override
  String recurringBillsRowA11y(String name, String amount, String status) {
    return '$name، $amount، $status';
  }

  @override
  String get recurringBillEditTitleAdd => 'ضيف فاتورة أو قسط';

  @override
  String get recurringBillEditTitleEdit => 'عدّل الفاتورة';

  @override
  String get recurringBillEditType => 'النوع';

  @override
  String get recurringBillEditName => 'الاسم';

  @override
  String get recurringBillEditNamePlaceholder => 'مثلاً: قسط التلاجة';

  @override
  String get recurringBillEditAmount => 'المبلغ';

  @override
  String get recurringBillEditRepeats => 'بيتكرر';

  @override
  String get recurringBillEditNextDue => 'الدفعة الجاية';

  @override
  String get recurringBillEditPaid => 'اتدفع';

  @override
  String get recurringBillEditPaidOf => 'من';

  @override
  String recurringBillEditRemind(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'فكّرني قبلها بـ $n يوم',
      many: 'فكّرني قبلها بـ $n يوم',
      few: 'فكّرني قبلها بـ $n أيام',
      two: 'فكّرني قبلها بيومين',
      one: 'فكّرني قبلها بيوم',
      zero: 'فكّرني يوم الميعاد',
    );
    return '$_temp0';
  }

  @override
  String get recurringBillEditAccount => 'الحساب (اختياري)';

  @override
  String recurringBillEditDeleteTitle(String name) {
    return 'تمسح $name؟';
  }

  @override
  String get recurringBillEditDeleteBody =>
      'هتتشال من الفواتير. الحركات اللي اتسجلت قبل كده مش هتتمسح.';

  @override
  String get recurringBillEditErrorPaid => 'اللي اتدفع مينفعش يزيد عن الإجمالي';

  @override
  String recurringBillEditErrorTotal(String max) {
    return 'عدد الدفعات لازم يبقى من واحد لـ $max';
  }

  @override
  String recurringBillEditErrorRemind(String max) {
    return 'التذكير من صفر لـ $max يوم';
  }

  @override
  String get recurringBillEditErrorDue => 'اختار ميعاد الدفعة الجاية';

  @override
  String get recurringBillEditSaved => 'الفاتورة اتحفظت ✓';

  @override
  String homeQuickAddVoiceLeft(String remaining, String max) {
    return 'فاضل $remaining من $max تسجيل صوتي الشهر ده';
  }

  @override
  String get voiceLoggerTitle => 'قول اللي دفعته';

  @override
  String get voiceLoggerExampleLabel => 'مثلاً';

  @override
  String get voiceLoggerExample =>
      'دفعت ميت وخمسين جنيه خضار وخمسة وأربعين قهوة وتلاتين تاكسي';

  @override
  String get voiceLoggerListening => 'بسمعك…';

  @override
  String get voiceLoggerDone => 'خلصت';

  @override
  String get voiceLoggerStopA11y => 'وقّف التسجيل';

  @override
  String voiceLoggerTranscriptA11y(String text) {
    return 'اللي سمعته لحد دلوقتي: $text';
  }

  @override
  String get voiceLoggerUnderstanding => 'بفهم اللي قلته…';

  @override
  String voiceLoggerParsedTitle(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'فهمت $n حاجة',
      many: 'فهمت $n حاجة',
      few: 'فهمت $n حاجات',
      two: 'فهمت حاجتين',
      one: 'فهمت حاجة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get voiceLoggerAccount => 'الحساب';

  @override
  String get voiceLoggerWhen => 'إمتى';

  @override
  String get voiceLoggerApplyAll => 'بينطبق على الكل';

  @override
  String get voiceLoggerAmountMissing => 'المبلغ كام؟';

  @override
  String get voiceLoggerEditA11y => 'عدّل البند ده';

  @override
  String get voiceLoggerRemoveA11y => 'شيل البند ده';

  @override
  String voiceLoggerSave(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'احفظ $n',
      many: 'احفظ $n',
      few: 'احفظ $n',
      two: 'احفظ الاتنين',
      one: 'احفظ',
    );
    return '$_temp0';
  }

  @override
  String voiceLoggerSaved(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'اتسجلوا $n حركة ✓',
      many: 'اتسجلوا $n حركة ✓',
      few: 'اتسجلوا $n حركات ✓',
      two: 'اتسجلت حركتين ✓',
      one: 'اتسجلت حركة واحدة ✓',
    );
    return '$_temp0';
  }

  @override
  String get voiceLoggerEmptyTitle => 'مسمعتش مبلغ';

  @override
  String get voiceLoggerEmptyBody => 'جرّب تقول: «ميت وخمسين خضار»';

  @override
  String get voiceLoggerUnavailable => 'الصوت بالعربي مش شغال على الموبايل ده';

  @override
  String get voiceLoggerUnavailableBody => 'تقدر تكتب الحركة بإيدك في ثواني.';

  @override
  String get voiceLoggerOnlineTitle => 'نستخدم التعرف على الصوت أونلاين؟';

  @override
  String voiceLoggerOnlineBody(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'آبل',
      'other': 'جوجل',
    });
    return 'موبايلك مفيهوش تعرّف على العربي من غير نت. لو وافقت، خدمة الكلام بتاعة $_temp0 هتحوّل صوتك لنص أونلاين. زغلول مش بيحتفظ بالتسجيل.';
  }

  @override
  String get voiceLoggerOnlineAllow => 'وافق';

  @override
  String get voiceLoggerOnlineDeny => 'لأ، هكتب';

  @override
  String get voiceLoggerMicTitle => 'محتاج الميكروفون';

  @override
  String get voiceLoggerMicBody =>
      'علشان أسمع اللي بتقوله. مش بحتفظ بتسجيل صوتك.';

  @override
  String get voiceLoggerLimitTitle => 'خلّصت تسجيلاتك الصوتية الشهر ده';

  @override
  String voiceLoggerLimitBody(String max) {
    return 'استخدمت $max تسجيل صوتي الشهر ده، وبيرجعوا أول الشهر الجاي. جولد من غير حدود.';
  }

  @override
  String get captureScanTitle => 'قراءة سكرين شوت';

  @override
  String get captureScanChoose => 'اختار صورة';

  @override
  String get captureScanChooseAnother => 'اختار صورة تانية';

  @override
  String get captureScanReading => 'بقرا الصورة…';

  @override
  String get captureScanOnDevice => 'الصورة بتتقري على موبايلك.';

  @override
  String get captureScanFound => 'ده اللي لقيته';

  @override
  String get captureScanAmount => 'المبلغ';

  @override
  String get captureScanParty => 'لمين / من مين';

  @override
  String get captureScanReference => 'رقم العملية';

  @override
  String get captureScanDate => 'إمتى';

  @override
  String get captureScanCategory => 'التصنيف';

  @override
  String get captureScanAccount => 'الحساب';

  @override
  String get captureScanEditA11y => 'عدّل';

  @override
  String get captureScanFromShare =>
      'ده اللي فهمته من الصورة اللي بعتها. راجعه واحفظ.';

  @override
  String get captureScanEmptyTitle => 'مش لاقي دفعة في الصورة دي';

  @override
  String get captureScanEmptyBody => 'جرّب صورة أوضح، أو اكتب الحركة بإيدك.';

  @override
  String get captureScanDuplicateTitle => 'اتسجلت قبل كده من رسالة البنك';

  @override
  String get captureScanDuplicateView => 'شوفها';

  @override
  String get captureScanDuplicateSave => 'احفظها برضه';

  @override
  String get captureScanUnsupported => 'الملف ده مش صورة أقدر أقراها';

  @override
  String get captureScanPhotoTitle => 'محتاج أشوف صورك';

  @override
  String get captureScanPhotoBody =>
      'علشان تختار السكرين شوت. ببص على الصورة اللي تختارها بس.';

  @override
  String wealthOverviewUnitGold(String karat, String grams) {
    return 'دهب عيار $karat: $grams';
  }

  @override
  String wealthOverviewUnitCoins(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n جنيه دهب',
      many: '$n جنيه دهب',
      few: '$n جنيهات دهب',
      two: 'جنيهين دهب',
      one: 'جنيه دهب واحد',
    );
    return '$_temp0';
  }

  @override
  String wealthOverviewUnitsA11y(String list) {
    return 'اللي حيلتك كله: $list';
  }

  @override
  String wealthOverviewGoldTitle(String karat) {
    return 'دهب عيار $karat';
  }

  @override
  String wealthOverviewGoldSub(String grams, String value) {
    return '$grams · ≈ $value';
  }

  @override
  String wealthOverviewCertTitle(String bank) {
    return 'شهادة $bank';
  }

  @override
  String wealthOverviewCertSub(String percent, String principal) {
    return 'عائد $percent · $principal';
  }

  @override
  String wealthOverviewCertPayout(String date, String payout) {
    return 'الصرف الجاي $date: $payout';
  }

  @override
  String get wealthOverviewManualValue => 'قيمة تقديرية';

  @override
  String wealthOverviewNoRate(String currency) {
    return 'مفيش سعر لـ $currency لسه، فهو ظاهر بعملته بس';
  }

  @override
  String get wealthOverviewAssetsEmpty =>
      'لسه ماضفتش أصول. ضيف دهبك أو شهاداتك.';

  @override
  String wealthOverviewAssetRowA11y(String name, String value) {
    return '$name، $value';
  }

  @override
  String accountsOverviewHiddenCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n حساب',
      many: '$n حساب',
      few: '$n حسابات',
      two: 'حسابين',
      one: 'حساب واحد',
    );
    return '$_temp0';
  }

  @override
  String get accountsHiddenTitle => 'الحسابات المخفية';

  @override
  String get accountsHiddenIntro =>
      'الحسابات دي مش ظاهرة في القوايم، بس حركاتها لسه محسوبة في الأرقام والميزانية والشارتات.';

  @override
  String get accountsHiddenUnhide => 'رجّعه';

  @override
  String get accountsHiddenUnhidden => 'الحساب رجع للقايمة';

  @override
  String get accountsHiddenEmpty => 'مفيش حسابات مخفية';

  @override
  String accountsHiddenRowA11y(String card) {
    return '$card، مخفي. اضغط تفتح الحساب';
  }

  @override
  String get wealthAssetTitleAdd => 'ضيف أصل';

  @override
  String get wealthAssetTitleEdit => 'عدّل الأصل';

  @override
  String get wealthAssetType => 'النوع';

  @override
  String get wealthAssetOptional => 'اختياري';

  @override
  String get wealthAssetGoldKarat => 'العيار';

  @override
  String get wealthAssetGoldGrams => 'الوزن بالجرام';

  @override
  String get wealthAssetGoldGramsHint => 'لحد تلات أرقام بعد العلامة';

  @override
  String get wealthAssetCoinCount => 'عدد الجنيهات';

  @override
  String get wealthAssetBoughtOn => 'اشتريته إمتى';

  @override
  String get wealthAssetPricePaid => 'دفعت فيه كام';

  @override
  String get wealthAssetCertBank => 'البنك';

  @override
  String get wealthAssetCertPrincipal => 'المبلغ';

  @override
  String get wealthAssetCertRate => 'نسبة العائد';

  @override
  String get wealthAssetCertPayout => 'العائد بيتصرف';

  @override
  String get wealthAssetCertMaturity => 'بتخلص إمتى';

  @override
  String get wealthAssetCashCurrency => 'العملة';

  @override
  String get wealthAssetCashAmount => 'المبلغ';

  @override
  String get wealthAssetName => 'الاسم';

  @override
  String get wealthAssetStocksCurrency => 'عملة التداول';

  @override
  String get wealthAssetValue => 'القيمة الحالية';

  @override
  String get wealthAssetValueHint => 'اكتبها بإيدك وحدّثها من وقت للتاني.';

  @override
  String get wealthAssetDeleteTitle => 'تمسح الأصل ده؟';

  @override
  String get wealthAssetDeleteBody =>
      'هيتشال من اللي حيلتك كله ومن أي حساب مبني عليه.';

  @override
  String get wealthAssetSaved => 'الأصل اتحفظ ✓';

  @override
  String get wealthAssetErrorType => 'اختار نوع الأصل';

  @override
  String get wealthAssetErrorGrams => 'الوزن لازم يبقى أكبر من صفر';

  @override
  String get wealthAssetErrorGramsDecimals => 'لحد تلات أرقام بعد العلامة بس';

  @override
  String wealthAssetErrorRate(String max) {
    return 'العائد من صفر لـ $max٪';
  }

  @override
  String get wealthAssetErrorMaturity =>
      'تاريخ الانتهاء لازم يبقى بعد تاريخ الشراء';

  @override
  String get wealthPricesTitle => 'الأسعار';

  @override
  String wealthPricesUpdated(String when) {
    return 'اتحدثت $when';
  }

  @override
  String get wealthPricesGoldSection => 'الدهب (سعر الجرام)';

  @override
  String wealthPricesCurrenciesSection(String currency) {
    return 'العملات مقابل $currency';
  }

  @override
  String wealthPricesGoldRowA11y(String karat, String price) {
    return 'عيار $karat: $price للجرام';
  }

  @override
  String wealthPricesCurrencyRowA11y(String currency, String rate) {
    return '$currency: $rate';
  }

  @override
  String get wealthPricesOverride => 'غيّر السعر';

  @override
  String get wealthPricesOverrideTitle => 'سعرك إنت';

  @override
  String wealthPricesOverrideField(String currency) {
    return 'السعر بـ $currency';
  }

  @override
  String get wealthPricesOverrideUse => 'استخدم سعري';

  @override
  String get wealthPricesOverrideNote =>
      'السعر اللي بتحطه بيتستخدم لحد ما ترجّع الأصلي.';

  @override
  String get wealthPricesYours => 'سعرك';

  @override
  String get wealthPricesReset => 'رجّع الأصلي';

  @override
  String get wealthPricesNeverTitle => 'لسه ما نزّلتش الأسعار';

  @override
  String get wealthPricesNeverBody => 'اتصل بالنت مرة، أو اكتب السعر بإيدك.';

  @override
  String get wealthPricesEnterManually => 'اكتب السعر بإيدك';

  @override
  String get wealthPricesFetchFailed =>
      'مقدرتش أحدّث الأسعار. شايف آخر سعر معروف.';

  @override
  String get wealthPricesPrivacy =>
      'تحديث الأسعار مبيبعتش أي حاجة عن فلوسك أو أصولك.';

  @override
  String get zakahMainTitle => 'الزكاة';

  @override
  String get zakahMainDisclaimerSummary =>
      'ده تقدير تقريبي مش فتوى. اسأل أهل العلم قبل ما تخرج زكاتك.';

  @override
  String get zakahMainDisclaimer =>
      'هذا الحساب تقديري وليس فتوى. يُرجى مراجعة أهل العلم قبل إخراج الزكاة.';

  @override
  String get zakahMainNisabReached => 'النصاب اتحقق';

  @override
  String get zakahMainNisabNotReached => 'لسه مفيش نصاب';

  @override
  String zakahMainNisabInfo(String grams, String karat, String value) {
    return 'النصاب $grams من الدهب عيار $karat، يعني حوالين $value';
  }

  @override
  String get zakahMainNisabNotReachedBody =>
      'حسابك تحت النصاب دلوقتي، فالتقدير مفيهوش مبلغ مستحق. هفضل أتابع معاك.';

  @override
  String zakahMainLotGold(String karat, String grams) {
    return 'دهب عيار $karat · $grams';
  }

  @override
  String zakahMainLotCash(String currency, String amount) {
    return 'كاش وأرصدة بـ$currency: $amount';
  }

  @override
  String zakahMainLotInvest(String currency, String amount) {
    return 'أسهم وصناديق بـ$currency: $amount';
  }

  @override
  String zakahMainLotCertificate(String amount) {
    return 'شهادات بنك: $amount';
  }

  @override
  String zakahMainDebtsLine(String debts) {
    return 'بعد خصم الديون المستحقة $debts';
  }

  @override
  String zakahMainHawlProgress(String done, String total) {
    return 'الحول: $done من $total يوم';
  }

  @override
  String get zakahMainHawlDone => 'الحول تم';

  @override
  String zakahMainDueIn(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'هتستحق بعد $n يوم',
      many: 'هتستحق بعد $n يوم',
      few: 'هتستحق بعد $n أيام',
      two: 'هتستحق بعد يومين',
      one: 'هتستحق بكرة',
    );
    return '$_temp0';
  }

  @override
  String zakahMainDueHijri(String hijri) {
    return 'هجري: $hijri';
  }

  @override
  String zakahMainDue(String dueNative) {
    return 'المستحق: $dueNative';
  }

  @override
  String zakahMainDueCost(String cost) {
    return 'تقريباً $cost';
  }

  @override
  String get zakahMainStatusLabel => 'حالة الدفع';

  @override
  String get zakahMainStatusPending => 'لسه';

  @override
  String get zakahMainStatusPartial => 'اتدفع جزء';

  @override
  String get zakahMainStatusPaid => 'اتدفعت';

  @override
  String zakahMainPaidOn(String date) {
    return 'اتدفعت يوم $date';
  }

  @override
  String get zakahMainStaleNote => 'الأسعار قديمة، فالمبالغ بالجنيه تقريبية.';

  @override
  String get zakahMainEmptyTitle => 'ضيف أصل علشان نحسب الزكاة';

  @override
  String get zakahMainEmptyAdd => 'ضيف أصل';

  @override
  String get zakahMainHowTitle => 'بتتحسب إزاي؟';

  @override
  String zakahMainHowNisab(String grams, String karat) {
    return 'النصاب $grams دهب عيار $karat، بسعر النهارده.';
  }

  @override
  String zakahMainHowHawl(String days) {
    return 'الحول سنة هجرية، يعني $days يوم من يوم ما حصلت على الأصل.';
  }

  @override
  String zakahMainHowRate(String percent) {
    return 'المستحق $percent من كل أصل بوحدته: الدهب بالجرام والكاش بعملته.';
  }

  @override
  String zakahMainHowPurity(String karat, String percent) {
    return 'دهب عيار $karat بيتحسب بنسبة $percent ناحية النصاب.';
  }

  @override
  String get zakahMainHowDebts =>
      'الديون اللي ميعادها جه بتتخصم من الكاش قبل الحساب.';

  @override
  String zakahMainLotA11y(String lot, String status, String dueNative) {
    return '$lot، $status، المستحق $dueNative';
  }

  @override
  String get chatMainSegAsk => 'اسأل';

  @override
  String get chatMainSegTips => 'نصايح';

  @override
  String get chatMainGreeting =>
      'اسألني أي حاجة عن فلوسك، بالمصري أو بالإنجليزي. بجاوبك من بياناتك اللي على موبايلك.';

  @override
  String get chatMainInputHint => 'اسألني أي حاجة عن فلوسك…';

  @override
  String get chatMainSendA11y => 'ابعت السؤال';

  @override
  String chatMainTooLong(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'السؤال ميزيدش عن $n حرف',
      many: 'السؤال ميزيدش عن $n حرف',
      few: 'السؤال ميزيدش عن $n حروف',
      two: 'السؤال ميزيدش عن حرفين',
      one: 'السؤال ميزيدش عن حرف واحد',
    );
    return '$_temp0';
  }

  @override
  String chatMainFilterNote(String cards) {
    return 'الإجابات على $cards';
  }

  @override
  String get chatMainRoast => 'إقصف جبهتي';

  @override
  String get chatMainRoastHint => 'بيغيّر الأسلوب بس، والأرقام زي ما هي.';

  @override
  String get chatMainClear => 'امسح المحادثة';

  @override
  String get chatMainCleared => 'المحادثة اتمسحت';

  @override
  String get chatMainOpenTransactions => 'افتح في الحركات';

  @override
  String get chatMainTypingA11y => 'زغلول بيكتب';

  @override
  String chatMainUserA11y(String text) {
    return 'إنت قلت: $text';
  }

  @override
  String chatMainZaghlolA11y(String text) {
    return 'زغلول رد: $text';
  }

  @override
  String get chatMainChartA11y => 'رسم صغير بيقارن الأرقام اللي فوق';

  @override
  String get chatChipCoffee => 'صرفت كام على القهوة؟';

  @override
  String get chatChipTopMerchants => 'أكتر أماكن بصرف فيها';

  @override
  String get chatChipDues => 'إيه الفواتير الجاية؟';

  @override
  String get chatChipBudgetLeft => 'فاضلي كام في الميزانية؟';

  @override
  String get chatChipBiggest => 'إيه أكبر حاجة صرفتها؟';

  @override
  String get chatChipSavings => 'حوشت كام الشهر ده؟';

  @override
  String get chatChipCompare => 'قارن الشهر ده باللي فات';

  @override
  String chatChipCard(String card) {
    return 'صرفت كام بكارت $card؟';
  }

  @override
  String get chatFallbackText => 'لسه مبعرفش أجاوب على ده. جرّب واحد من دول:';

  @override
  String get chatAnswerPickOne => 'تقصد أنهي واحد؟';

  @override
  String get chatPeriodToday => 'النهارده';

  @override
  String get chatPeriodYesterday => 'امبارح';

  @override
  String get chatPeriodThisWeek => 'الأسبوع ده';

  @override
  String get chatPeriodLastWeek => 'الأسبوع اللي فات';

  @override
  String get chatPeriodThisCycle => 'الدورة دي';

  @override
  String get chatPeriodLastCycle => 'الدورة اللي فاتت';

  @override
  String get chatPeriodThisMonth => 'الشهر ده';

  @override
  String get chatPeriodLastMonth => 'الشهر اللي فات';

  @override
  String get chatPeriodSinceYearStart => 'من أول السنة';

  @override
  String chatPeriodLastMonths(int count, String n) {
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
  String chatPeriodRange(String start, String end) {
    return 'من $start لحد $end';
  }

  @override
  String chatPeriodNextDays(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'في الـ $n يوم الجايين',
      many: 'في الـ $n يوم الجايين',
      few: 'في الـ $n أيام الجايين',
      two: 'في اليومين الجايين',
      one: 'بكرة',
    );
    return '$_temp0';
  }

  @override
  String get chatPeriodUntilPayday => 'لحد القبض';

  @override
  String chatAnswerCurrencyLead(String currency) {
    return 'بـ$currency:';
  }

  @override
  String chatAnswerSpendOn(String amount, String subject, String span) {
    return 'صرفت $amount على $subject $span.';
  }

  @override
  String chatAnswerSpendOnCount(
    String amount,
    String subject,
    String span,
    String times,
  ) {
    return 'صرفت $amount على $subject $span في $times.';
  }

  @override
  String chatAnswerCompare(
    String amount,
    String span,
    String trend,
    String spanB,
    String delta,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'أكتر من $spanB بـ $delta',
      'down': 'أقل من $spanB بـ $delta',
      'other': 'زي $spanB تقريباً',
    });
    return 'صرفت $amount $span، $_temp0.';
  }

  @override
  String chatAnswerTopMerchants(String span, String list) {
    return 'أكتر الأماكن $span: $list.';
  }

  @override
  String chatAnswerBalance(String account, String amount, String when) {
    return 'رصيد $account $amount، آخر تحديث $when.';
  }

  @override
  String chatAnswerBalanceCredit(
    String account,
    String available,
    String limit,
  ) {
    return 'المتاح في $account $available من $limit.';
  }

  @override
  String chatAnswerBalanceUnknown(String account) {
    return 'لسه معرفش رصيد $account. هيظهر مع أول رسالة فيها الرصيد.';
  }

  @override
  String chatAnswerBudgetLeft(String left, String subject) {
    return 'فاضلك $left من ميزانية $subject.';
  }

  @override
  String chatAnswerBudgetLeftPerDay(String left, String perDay) {
    return 'فاضلك $left من الميزانية، يعني $perDay في اليوم لحد القبض.';
  }

  @override
  String chatAnswerBudgetOver(String subject, String gap) {
    return '$subject عدّى ميزانيته بـ $gap.';
  }

  @override
  String chatAnswerBudgetNone(String subject) {
    return 'مفيش ميزانية متحطة لـ $subject. تحب تحطها؟';
  }

  @override
  String chatAnswerDues(
    int count,
    String span,
    String list,
    String amount,
    String n,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'عليك $n دفعة $span: $list، المجموع $amount.',
      many: 'عليك $n دفعة $span: $list، المجموع $amount.',
      few: 'عليك $n دفعات $span: $list، المجموع $amount.',
      two: 'عليك دفعتين $span: $list، المجموع $amount.',
      one: 'عليك دفعة واحدة $span: $list.',
      zero: 'مفيش فواتير ولا أقساط $span.',
    );
    return '$_temp0';
  }

  @override
  String chatAnswerBiggest(
    String span,
    String amount,
    String merchant,
    String date,
  ) {
    return 'أكبر حاجة صرفتها $span كانت $amount عند $merchant يوم $date.';
  }

  @override
  String chatAnswerSavings(
    String state,
    String span,
    String gap,
    String saved,
    String percent,
  ) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'short': '$span صرفت أكتر من دخلك بـ $gap.',
      'other': '$span حوشت $saved، يعني $percent من دخلك.',
    });
    return '$_temp0';
  }

  @override
  String chatAnswerSpendCard(String amount, String card, String span) {
    return 'صرفت $amount بكارت $card $span.';
  }

  @override
  String chatAnswerNoData(String subject, String start, String end) {
    return 'مفيش صرف على $subject من $start لحد $end.';
  }

  @override
  String get chatAnswerNoDataGeneric => 'مفيش بيانات للفترة دي.';

  @override
  String get chatAnswerError => 'حصلت مشكلة وأنا بقرا بياناتك. جرّب تاني.';

  @override
  String get chatRoastOn =>
      'تمام، قلبي جامد وإنت كمان! هقصف على الصرف بس، مش عليك.';

  @override
  String get chatRoastOff => 'رجعنا للجد. الأرقام زي ما هي.';

  @override
  String get chatRoastOfferToggle => 'ده كان قصف سريع. تحب أفتح مود القصف؟';

  @override
  String chatRoastDelivery(String orders, String amount, String span) {
    return '$orders بـ $amount دليفري $span؟ السواق حافظ عنوانك أكتر مني! 😄';
  }

  @override
  String chatRoastDeliveryAlt(String amount, String span) {
    return '$amount دليفري $span.. المطبخ مستني زيارة منك!';
  }

  @override
  String chatRoastCoffee(String amount, String span) {
    return '$amount قهوة $span؟ كده إنت شريك في مزرعة البن! ☕';
  }

  @override
  String chatRoastCoffeeAlt(String span, String amount) {
    return 'القهوة $span بـ $amount. للأسف الكافيين مبيدفعش فواتيرك 😄';
  }

  @override
  String chatRoastTopCategory(String category, String percent) {
    return '$category واخد $percent من صرفك. ده مش بند، ده هواية!';
  }

  @override
  String chatRoastTopCategoryAlt(String category, String percent) {
    return '$category واخد $percent من صرفك ولسه بيطلب كمان!';
  }

  @override
  String chatRoastSplurge(String amount, String merchant) {
    return '$amount مرة واحدة عند $merchant؟ ده مش مشوار، ده قرار كبير!';
  }

  @override
  String chatRoastSplurgeAlt(String amount, String merchant, String span) {
    return '$amount عند $merchant دفعة واحدة $span. ده يوم تاريخي في المحفظة!';
  }

  @override
  String chatRoastWeekend(String peakDay) {
    return 'محفظتك بتخاف من يوم $peakDay، وعندها حق!';
  }

  @override
  String chatRoastWeekendAlt(String peakDay, String amount) {
    return 'يوم $peakDay بتصرف في المتوسط $amount. باقي الأيام بتغير منه!';
  }

  @override
  String chatRoastSubscriptions(String yearly) {
    return 'اشتراكاتك بتاخد $yearly في السنة. فيهم حاجة بتفتحها فعلاً؟';
  }

  @override
  String chatRoastSubscriptionsAlt(String yearly) {
    return 'اشتراكاتك بـ $yearly في السنة شغالة حتى وإنت نايم!';
  }

  @override
  String chatRoastLateNight(String time) {
    return 'أوردرات بعد الساعة $time؟ التطبيق صاحي أكتر منك!';
  }

  @override
  String chatRoastGoldEquivalent(
    String amount,
    String category,
    String grams,
    String karat,
  ) {
    return '$amount على $category كانوا يجيبوا $grams دهب عيار $karat. بس كانت حلوة، صح؟';
  }

  @override
  String get chatRoastGentle =>
      'النهارده مش هقصف جبهتك، الأرقام محتاجة جد. تحب نبص على أكبر بند سوا؟';

  @override
  String get chatRoastClean =>
      'دورت على حاجة أقصفك بيها ومالقيتش! إنت منظم غصب عني 👏';

  @override
  String get roiTipsDisclaimerSummary => 'دي أفكار عامة مش نصيحة مالية.';

  @override
  String get roiTipsDisclaimer =>
      'هذه اقتراحات عامة وليست نصيحة مالية أو استثمارية. الأرقام تقديرية وقد تختلف عن الواقع.';

  @override
  String roiTipsProjection(String years, String year1, String year2) {
    String _temp0 = intl.Intl.selectLogic(years, {
      'two': 'السنة الأولى: توفير حوالين $year1. السنة التانية: حوالين $year2.',
      'other': 'السنة الأولى: توفير حوالين $year1.',
    });
    return '$_temp0';
  }

  @override
  String get roiTipsShare => 'شارك';

  @override
  String get roiTipsNotForMe => 'مش ليّا';

  @override
  String get roiTipsDismissed => 'اتشالت. مش هتظهرلك تاني.';

  @override
  String roiTipsBadgeA11y(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n نصيحة جديدة',
      many: '$n نصيحة جديدة',
      few: '$n نصايح جديدة',
      two: 'نصيحتين جداد',
      one: 'نصيحة جديدة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get roiTipsEmptyTitle => 'مفيش نصايح دلوقتي';

  @override
  String get roiTipsEmptyBody => 'هقولك أول ما ألاقي حاجة تفيدك.';

  @override
  String get roiTipsLockedBody => 'نصايح مبنية على صرفك إنت، مع جولد';

  @override
  String get roiRuleCoffeeTitle => 'ماكينة قهوة بدل الكافيهات';

  @override
  String roiRuleCoffeeBody(String monthly, String alt) {
    return 'بتصرف $monthly في الشهر في الكافيهات. ماكينة بالتقسيط مع البن والحليب تقريباً $alt في الشهر.';
  }

  @override
  String get roiRuleDeliveryTitle => 'أكل البيت بدل الدليفري كل يوم';

  @override
  String roiRuleDeliveryBody(String monthly, String alt) {
    return 'الدليفري واخد $monthly في الشهر. جهاز طبخ صغير بالتقسيط وأكل البيت تقريباً $alt في الشهر.';
  }

  @override
  String get roiRuleWaterTitle => 'فلتر مياه بدل القوارير';

  @override
  String roiRuleWaterBody(String monthly, String alt) {
    return 'القوارير والجراكن بـ $monthly في الشهر. فلتر مياه بالتقسيط مع تغيير الشمعات تقريباً $alt في الشهر.';
  }

  @override
  String get roiRuleIdleCashTitle => 'فلوسك واقفة من غير عائد';

  @override
  String roiRuleIdleCashBody(String idle, String exampleRate) {
    return 'في حسابك $idle زيادة عن ميزانيتك بقالهم أكتر من عشرين يوم من غير عائد. صندوق نقدي أو شهادة ممكن يشغّلوهم. معدل مثال للتوضيح: $exampleRate.';
  }

  @override
  String get roiRuleCommuteTitle => 'مشاويرك المتكررة بالتطبيقات';

  @override
  String roiRuleCommuteBody(String monthly, String alt) {
    return 'مشاويرك بتطبيقات التوصيل بـ $monthly في الشهر. وسيلة مواصلات بالتقسيط مع مواصلات عامة للمشاوير الطويلة تقريباً $alt في الشهر.';
  }

  @override
  String get roiRuleCardInterestTitle => 'سدد الكريدت كارد كله';

  @override
  String roiRuleCardInterestBody(String balance, String exampleRate) {
    return 'عليك $balance على الكريدت كارد وعندك كاش أكتر منه. السداد الكامل قبل ميعاد الكشف بيوفر الفوايد. معدل مثال للتوضيح: $exampleRate في الشهر.';
  }

  @override
  String get roiRuleSubscriptionsTitle => 'اشتراك سنوي واحد بدل كذا اشتراك';

  @override
  String roiRuleSubscriptionsBody(String monthly, String alt) {
    return 'بتدفع $monthly في الشهر على اشتراكات كتير. باقة سنوية مشتركة ممكن تنزلها لحوالين $alt في الشهر.';
  }

  @override
  String get roiRuleStaplesTitle => 'اشتري الأساسيات مرة واحدة يوم القبض';

  @override
  String roiRuleStaplesBody(String monthly, String alt) {
    return 'بتشتري الأساسيات على مرات صغيرة بـ $monthly في الشهر. شراء بالجملة مرة واحدة يوم القبض ممكن يخليها حوالين $alt.';
  }

  @override
  String get commonActionCopy => 'انسخ';

  @override
  String get commonActionContactSupport => 'كلّم الدعم';

  @override
  String get commonActionSignIn => 'سجّل دخول';

  @override
  String get commonActionSignOut => 'اخرج من الحساب';

  @override
  String get commonActionManage => 'إدارة';

  @override
  String get commonSupportCodeLabel => 'كود الدعم';

  @override
  String commonSupportCodeValue(String supportCode) {
    return '$supportCode';
  }

  @override
  String get commonSupportCodeCopied => 'اتنسخ ✓';

  @override
  String commonSupportCodeCopyA11y(String supportCode) {
    return 'انسخ كود الدعم $supportCode';
  }

  @override
  String get commonSupportHint => 'ادّي كود الدعم ده للدعم عشان يلاقي موبايلك.';

  @override
  String get settingsMainTitle => 'الإعدادات';

  @override
  String settingsMainFinishSetup(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'فاضل $n خطوة في الإعداد',
      many: 'فاضل $n خطوة في الإعداد',
      few: 'فاضل $n خطوات في الإعداد',
      two: 'فاضل خطوتين في الإعداد',
      one: 'فاضل خطوة واحدة في الإعداد',
    );
    return '$_temp0';
  }

  @override
  String get settingsMainGoldFree => 'الباقة المجانية';

  @override
  String settingsMainGoldActive(String plan) {
    String _temp0 = intl.Intl.selectLogic(plan, {
      'monthly': 'جولد · شهري',
      'yearly': 'جولد · سنوي',
      'lifetime': 'جولد · مدى الحياة',
      'other': 'جولد',
    });
    return '$_temp0';
  }

  @override
  String get settingsMainSeeGold => 'شوف جولد';

  @override
  String get settingsMainSectionGeneral => 'عام';

  @override
  String get settingsMainSectionData => 'بياناتك';

  @override
  String get settingsMainPreferences => 'التفضيلات';

  @override
  String get settingsMainNotifications => 'التنبيهات';

  @override
  String get settingsMainCapture => 'زغلول بيقرا منين';

  @override
  String settingsMainCaptureSub(String state) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'ok': 'كله شغال',
      'attention': 'محتاج انتباه',
      'other': 'لسه متظبطش',
    });
    return '$_temp0';
  }

  @override
  String get settingsMainCategories => 'التصنيفات';

  @override
  String get settingsMainBackup => 'نسخة احتياطية';

  @override
  String settingsMainBackupSub(String state, String date) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'never': 'لسه مفيش نسخة',
      'other': 'آخر نسخة $date',
    });
    return '$_temp0';
  }

  @override
  String get settingsMainExports => 'إكسيل وكشوف البنوك';

  @override
  String get settingsMainPrivacy => 'خصوصيتك';

  @override
  String get settingsMainAbout => 'عن زغلول';

  @override
  String get categoriesListTitle => 'التصنيفات';

  @override
  String get categoriesListTabCategories => 'التصنيفات';

  @override
  String get categoriesListTabRules => 'القواعد';

  @override
  String categoriesListSubCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n تصنيف فرعي',
      many: '$n تصنيف فرعي',
      few: '$n تصنيفات فرعية',
      two: 'تصنيفين فرعيين',
      one: 'تصنيف فرعي واحد',
    );
    return '$_temp0';
  }

  @override
  String get categoriesListSystemNote =>
      'دي تصنيفات زغلول الأساسية. جولد بيخليك تضيف تصنيفات فرعية.';

  @override
  String get categoriesListNew => 'تصنيف جديد';

  @override
  String get categoriesListNewSub => 'تصنيف فرعي جديد';

  @override
  String categoriesListRulesCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n قاعدة',
      many: '$n قاعدة',
      few: '$n قواعد',
      two: 'قاعدتين',
      one: 'قاعدة واحدة',
      zero: 'مفيش قواعد',
    );
    return '$_temp0';
  }

  @override
  String get categoriesListRulesSearch => 'دوّر في القواعد';

  @override
  String categoriesListRuleA11y(String merchant, String category) {
    return '$merchant بيتصنف $category';
  }

  @override
  String get categoriesListRuleEditA11y => 'غيّر تصنيف القاعدة';

  @override
  String get categoriesListRuleDeleteA11y => 'امسح القاعدة';

  @override
  String get categoriesListRulesEmpty =>
      'لما تصلّح تصنيف، هسألك لو عايزني أفتكره.';

  @override
  String get categoriesListRuleDeleteTitle => 'تمسح القاعدة دي؟';

  @override
  String get categoriesListRuleDeleteBody =>
      'زغلول مش هيطبّقها على الحركات الجاية.';

  @override
  String get categoriesListRuleDeleted => 'القاعدة اتمسحت';

  @override
  String get categoriesListNoResults => 'مفيش قاعدة بالاسم ده';

  @override
  String get categoriesEditTitleNew => 'تصنيف جديد';

  @override
  String get categoriesEditTitleEdit => 'تعديل التصنيف';

  @override
  String get categoriesEditName => 'اسم التصنيف';

  @override
  String get categoriesEditParent => 'تحت تصنيف';

  @override
  String get categoriesEditParentNone => 'مفيش (تصنيف رئيسي)';

  @override
  String get categoriesEditBucket => 'النوع';

  @override
  String get categoriesEditBucketNeeds => 'ضروريات';

  @override
  String get categoriesEditBucketWants => 'رغبات';

  @override
  String get categoriesEditBucketObligations => 'التزامات';

  @override
  String get categoriesEditBucketSavings => 'ادخار';

  @override
  String get categoriesEditBucketIncome => 'دخل';

  @override
  String get categoriesEditBucketGiving => 'عطاء';

  @override
  String get categoriesEditBucketRequired => 'اختار النوع';

  @override
  String get categoriesEditIcon => 'الأيقونة';

  @override
  String get categoriesEditColor => 'اللون';

  @override
  String get categoriesEditDelete => 'امسح التصنيف';

  @override
  String categoriesEditDeleteTitle(String category) {
    return 'تمسح \"$category\"؟';
  }

  @override
  String get categoriesEditDeleteBody =>
      'اختار تصنيف تتنقل له حركاته قبل ما نمسحه.';

  @override
  String get categoriesEditMoveTo => 'انقل الحركات لـ';

  @override
  String get categoriesEditMoveRequired => 'اختار تصنيف تتنقل له الحركات';

  @override
  String get categoriesEditDeleteConfirm => 'امسح وانقل';

  @override
  String get categoriesEditDeleted => 'التصنيف اتمسح والحركات اتنقلت';

  @override
  String get categoriesEditLockedBody => 'التصنيفات الخاصة بيك مع جولد';

  @override
  String get templatesBuilderTitle => 'قالب رسالة جديد';

  @override
  String get templatesBuilderPickTitle => 'الصق رسالة أو اختار واحدة';

  @override
  String get templatesBuilderFromReview => 'من اللي مستني رأيك';

  @override
  String get templatesBuilderPaste => 'الصق رسالة';

  @override
  String get templatesBuilderEmpty => 'الصق رسالة من البنك عشان نبدأ';

  @override
  String get templatesBuilderPrivate =>
      'الرسالة بتفضل على موبايلك ومش بتتبعت لحد.';

  @override
  String get templatesBuilderTagTitle => 'علّم الأجزاء';

  @override
  String get templatesBuilderTapHint => 'دوس على الجزء وبعدين اختار هو إيه.';

  @override
  String get templatesBuilderTagAmount => 'المبلغ';

  @override
  String get templatesBuilderTagCurrency => 'العملة';

  @override
  String get templatesBuilderTagMerchant => 'التاجر';

  @override
  String get templatesBuilderTagLast4 => 'آخر أربع أرقام';

  @override
  String get templatesBuilderTagBalance => 'الرصيد';

  @override
  String get templatesBuilderTagDate => 'التاريخ';

  @override
  String get templatesBuilderDirection => 'الاتجاه';

  @override
  String get templatesBuilderSender => 'اسم المرسل';

  @override
  String get templatesBuilderSenderHint => 'زي ما بيظهر على الرسايل';

  @override
  String get templatesBuilderTestTitle => 'جرّب القالب';

  @override
  String templatesBuilderTestResult(String done, String total) {
    return 'الرسايل الشبه دي اللي القالب فهمها: $done من $total';
  }

  @override
  String get templatesBuilderTestFailTitle => 'في رسالة مافهمتهاش';

  @override
  String templatesBuilderTestFailReason(String state) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'amount': 'مش لاقي المبلغ فيها.',
      'direction': 'مش عارف دي صرف ولا دخل.',
      'other': 'شكلها مختلف عن القالب.',
    });
    return '$_temp0';
  }

  @override
  String get templatesBuilderSave => 'احفظ القالب';

  @override
  String get templatesBuilderSaved => 'القالب اتحفظ ✓';

  @override
  String get templatesBuilderErrorAmount => 'علّم المبلغ الأول';

  @override
  String get templatesBuilderErrorSender => 'اكتب اسم المرسل';

  @override
  String get templatesBuilderErrorSelfParse =>
      'القالب لازم يقرا الرسالة اللي عملته عليها';

  @override
  String get templatesBuilderLockedBody =>
      'علّم زغلول يفهم رسايل بنك مش مدعوم، مع جولد';

  @override
  String get backupSettingsTitle => 'نسخة احتياطية';

  @override
  String get backupSettingsWhere => 'النسخة تتحفظ فين؟';

  @override
  String get backupSettingsAccount => 'الحساب';

  @override
  String get backupSettingsAccountChange => 'غيّر';

  @override
  String backupSettingsLast(String date, String size) {
    return 'آخر نسخة: $date · $size';
  }

  @override
  String get backupSettingsNever => 'لسه ما عملتش نسخة';

  @override
  String get backupSettingsFreeNudge =>
      'النسخة الأولى ببلاش، وبتحمي بياناتك لو الموبايل ضاع.';

  @override
  String get backupSettingsNow => 'اعمل نسخة دلوقتي';

  @override
  String get backupSettingsFreeReplaces => 'النسخة الجديدة بتحل محل القديمة.';

  @override
  String get backupSettingsAuto => 'نسخة تلقائي';

  @override
  String get backupSettingsAutoOff => 'مقفول';

  @override
  String get backupSettingsAutoDaily => 'كل يوم';

  @override
  String get backupSettingsAutoWeekly => 'كل أسبوع';

  @override
  String get backupSettingsAutoMonthly => 'كل شهر';

  @override
  String get backupSettingsAutoLocked => 'النسخ التلقائي مع جولد';

  @override
  String get backupSettingsVersions => 'النسخ المحفوظة';

  @override
  String get backupSettingsVersionsLocked => 'جولد بيحتفظ بخمس نسخ';

  @override
  String get backupSettingsGoldKeeps =>
      'لو بقيت جولد، نسختك الحالية بتبقى أول نسخة في السجل.';

  @override
  String get backupSettingsPassphrase => 'كلمة سر النسخة';

  @override
  String get backupSettingsPassphraseChange => 'غيّر';

  @override
  String get backupSettingsRestore => 'استرجاع نسخة';

  @override
  String get backupSettingsIncludes =>
      'في النسخة: حركاتك وإعداداتك وتصنيفاتك وقواعدك والكروت اللي مش بتتابعها.';

  @override
  String get backupSettingsExcludes =>
      'مفيهاش مفاتيح الحماية ولا أذونات الموبايل. هتفعّلهم من جديد بعد الاسترجاع.';

  @override
  String backupSettingsStale(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'آخر نسخة بقالها $n يوم',
      many: 'آخر نسخة بقالها $n يوم',
      few: 'آخر نسخة بقالها $n أيام',
      two: 'آخر نسخة بقالها يومين',
      one: 'آخر نسخة بقالها يوم',
    );
    return '$_temp0';
  }

  @override
  String get backupSettingsRunning => 'بعمل النسخة…';

  @override
  String get backupSettingsCancelNote => 'تقدر تلغي قبل ما الرفع يخلص.';

  @override
  String get backupSettingsDone => 'النسخة اتعملت ✓';

  @override
  String get backupSettingsErrorNetwork =>
      'النسخة ماتعملتش لأن النت مش ثابت. النسخة اللي فاتت لسه موجودة.';

  @override
  String backupSettingsErrorStorage(String provider) {
    return 'المساحة على $provider خلصت. فضّي مساحة وجرّب تاني. النسخة اللي فاتت لسه موجودة.';
  }

  @override
  String backupSettingsErrorAuth(String provider) {
    return 'الدخول على $provider خلص. سجّل دخول تاني وجرّب تاني.';
  }

  @override
  String get backupSettingsErrorIcloud =>
      'iCloud مش شغال على الموبايل ده. سجّل دخول بحساب Apple من إعدادات الآيفون وشغّل iCloud Drive.';

  @override
  String get backupSettingsErrorGeneric =>
      'النسخة الاحتياطية ماتعملتش. جرّب تاني.';

  @override
  String get backupPassphraseTitle => 'اختار كلمة سر للنسخة';

  @override
  String get backupPassphraseNew => 'كلمة السر';

  @override
  String get backupPassphraseConfirm => 'اكتبها تاني';

  @override
  String get backupPassphraseWeak => 'ضعيفة';

  @override
  String get backupPassphraseFair => 'كويسة';

  @override
  String get backupPassphraseStrong => 'قوية';

  @override
  String get backupPassphraseWarning =>
      'لو نسيت كلمة السر، محدش يقدر يفتح نسختك، ولا حتى إحنا.';

  @override
  String get backupPassphraseUnderstand => 'فاهم إنها مش بتترجّع';

  @override
  String get backupPassphraseTooShort => 'استخدم عشرة حروف على الأقل';

  @override
  String get backupPassphraseMismatch => 'كلمتين السر مش زي بعض';

  @override
  String get backupPassphraseAckRequired => 'علّم إنك فاهم الأول';

  @override
  String get backupPassphraseSave => 'احفظ وابدأ النسخة';

  @override
  String get backupPassphraseChangeTitle => 'غيّر كلمة سر النسخة';

  @override
  String get backupPassphraseCurrent => 'كلمة السر الحالية';

  @override
  String get backupPassphraseCurrentWrong => 'كلمة السر الحالية مش صح';

  @override
  String get backupPassphraseChanged => 'كلمة السر اتغيرت ✓';

  @override
  String get exportsMainTitle => 'إكسيل وكشوف البنوك';

  @override
  String get exportsMainExportSection => 'تصدير';

  @override
  String get exportsMainFormat => 'الصيغة';

  @override
  String get exportsMainFormatCsv => 'CSV';

  @override
  String get exportsMainFormatExcel => 'Excel';

  @override
  String get exportsMainDates => 'الفترة';

  @override
  String get exportsMainCategories => 'التصنيفات';

  @override
  String get exportsMainCategoriesAll => 'كل التصنيفات';

  @override
  String get exportsMainCards => 'الكروت';

  @override
  String get exportsMainPreview => 'معاينة أول عشرين صف';

  @override
  String get exportsMainPreviewEmpty => 'مفيش حركات في الفترة دي';

  @override
  String get exportsMainFreePreview => 'المعاينة ببلاش. التصدير مع جولد.';

  @override
  String get exportsMainExport => 'صدّر';

  @override
  String get exportsMainCurrencyNote =>
      'كل صف فيه عملته، ومفيش أي تحويل بين العملات.';

  @override
  String get exportsMainUnencrypted =>
      'الملف اللي بتصدّره مش متشفّر. احفظه في مكان بتثق فيه.';

  @override
  String get exportsMainPreparing => 'بجهّز الملف…';

  @override
  String get exportsMainReady => 'الملف جاهز ✓';

  @override
  String get exportsMainSave => 'احفظ الملف';

  @override
  String get exportsMainFailed => 'معرفتش أجهّز الملف. جرّب تاني.';

  @override
  String get exportsImportSection => 'استيراد';

  @override
  String get exportsImportZaghlolCsv => 'ملف زغلول CSV';

  @override
  String get exportsImportPdfTitle => 'كشف حساب PDF';

  @override
  String exportsImportPdfBanks(String banks) {
    return '$banks';
  }

  @override
  String get exportsImportOnlineTitle => 'كشف بنك أونلاين';

  @override
  String exportsImportOnlineBanks(String banks) {
    return '$banks';
  }

  @override
  String get exportsImportPick => 'اختار الملف';

  @override
  String get exportsImportParsing => 'بقرا الملف…';

  @override
  String get exportsImportPasswordTitle => 'الكشف محمي بكلمة سر';

  @override
  String get exportsImportPasswordBody =>
      'اكتب كلمة السر. بتتستخدم على موبايلك بس ومش بتتحفظ.';

  @override
  String get exportsImportPasswordLabel => 'كلمة سر الكشف';

  @override
  String get exportsImportPasswordWrong => 'كلمة السر دي غلط';

  @override
  String exportsImportFound(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'لقيت $n حركة',
      many: 'لقيت $n حركة',
      few: 'لقيت $n حركات',
      two: 'لقيت حركتين',
      one: 'لقيت حركة واحدة',
    );
    return '$_temp0';
  }

  @override
  String exportsImportDuplicates(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n حركة موجودة عندك (هتتخطى)',
      many: '$n حركة موجودة عندك (هتتخطى)',
      few: '$n حركات موجودة عندك (هتتخطى)',
      two: 'حركتين موجودين عندك (هيتخطوا)',
      one: 'حركة واحدة موجودة عندك (هتتخطى)',
    );
    return '$_temp0';
  }

  @override
  String exportsImportUntracked(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n كارت مش متتبعة (هتتخطى)',
      many: '$n كارت مش متتبعة (هتتخطى)',
      few: '$n كروت مش متتبعة (هتتخطى)',
      two: 'كارتين مش متتبعين (هيتخطوا)',
      one: 'كارت واحد مش متتبع (هيتخطى)',
    );
    return '$_temp0';
  }

  @override
  String exportsImportImportButton(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'استورد $n حركة',
      many: 'استورد $n حركة',
      few: 'استورد $n حركات',
      two: 'استورد حركتين',
      one: 'استورد حركة',
    );
    return '$_temp0';
  }

  @override
  String get exportsImportNothingNew => 'كل الحركات دي موجودة عندك قبل كده';

  @override
  String get exportsImportImporting => 'بضيف الحركات…';

  @override
  String exportsImportDone(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'اتضافت $n حركة ✓',
      many: 'اتضافت $n حركة ✓',
      few: 'اتضافت $n حركات ✓',
      two: 'اتضافت حركتين ✓',
      one: 'اتضافت حركة ✓',
    );
    return '$_temp0';
  }

  @override
  String get exportsImportEmptyTitle => 'مفيش حركات في الملف ده';

  @override
  String get exportsImportUnsupportedTitle => 'الملف ده مش كشف مدعوم';

  @override
  String exportsImportUnsupportedBody(String banks) {
    return 'دي الجهات المدعومة: $banks';
  }

  @override
  String get exportsImportWrongType => 'نوع الملف مش اللي اخترته';

  @override
  String get exportsImportFailed => 'معرفتش أقرا الملف. جرّب ملف تاني.';

  @override
  String get exportsImportLockedBody => 'ضيف شهور فاتتة وكشوف البنوك مع جولد';

  @override
  String get goldPaywallTitle => 'زغلول جولد';

  @override
  String get goldPaywallCloseA11y => 'اقفل';

  @override
  String get goldPaywallHeadline => 'كل أدواتك في مكان واحد';

  @override
  String get goldPaywallBenefitCharts => 'كل الشارتات الاتناشر مع تحليل أعمق';

  @override
  String get goldPaywallBenefitVoice => 'تسجيل بالصوت من غير حدود';

  @override
  String get goldPaywallBenefitExport => 'تصدير واستيراد وكشوف البنوك';

  @override
  String get goldPaywallBenefitBackup => 'نسخ تلقائي بخمس نسخ محفوظة';

  @override
  String get goldPaywallBenefitAssets => 'دهب وشهادات وأصول';

  @override
  String get goldPaywallBenefitCustom => 'تصنيفات وقوالب رسايل خاصة بيك';

  @override
  String goldPaywallPlanName(String plan) {
    String _temp0 = intl.Intl.selectLogic(plan, {
      'monthly': 'شهري',
      'yearly': 'سنوي',
      'lifetime': 'مدى الحياة',
      'other': 'جولد',
    });
    return '$_temp0';
  }

  @override
  String goldPaywallPlanPrice(String plan, String storePrice) {
    String _temp0 = intl.Intl.selectLogic(plan, {
      'monthly': '$storePrice في الشهر',
      'yearly': '$storePrice في السنة',
      'lifetime': '$storePrice مرة واحدة',
      'other': '$storePrice',
    });
    return '$_temp0';
  }

  @override
  String get goldPaywallBestValue => 'الأوفر';

  @override
  String get goldPaywallContinue => 'يلا نشترك';

  @override
  String get goldPaywallPlanRequired => 'اختار خطة الأول';

  @override
  String get goldPaywallRestore => 'استرجع مشترياتي';

  @override
  String get goldPaywallTerms => 'الشروط';

  @override
  String get goldPaywallPrivacy => 'الخصوصية';

  @override
  String goldPaywallRenewal(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'يتجدد الاشتراك تلقائياً ما لم يُلغَ قبل نهاية الفترة من إعدادات حساب Apple.',
      'other': 'يتجدد الاشتراك تلقائياً ما لم يُلغَ قبل نهاية الفترة من Google Play.',
    });
    return '$_temp0';
  }

  @override
  String get goldPaywallRenewalSummary =>
      'بيتجدد لوحده وتقدر تلغيه من المتجر في أي وقت.';

  @override
  String get goldPaywallLifetimeNote => 'الدفع مرة واحدة ومن غير تجديد.';

  @override
  String get goldPaywallPricesLoading => 'بحمّل الأسعار…';

  @override
  String get goldPaywallPricesFailed =>
      'مش قادر أحمّل الأسعار. اتأكد من النت وجرّب تاني.';

  @override
  String get goldPaywallPurchasing => 'بفتح المتجر…';

  @override
  String get goldPaywallPending => 'الدفع لسه معلّق. جولد هيشتغل أول ما يتم.';

  @override
  String get goldPaywallVerifying => 'بتأكد من الدفع…';

  @override
  String get goldPaywallVerifyOffline => 'هكمّل التأكد أول ما النت يرجع.';

  @override
  String get goldPaywallSuccess => 'جولد اشتغل ✓';

  @override
  String get goldPaywallSuccessMascot =>
      'ألف مبروك. جولد اشتغل وكل حاجة اتفتحت.';

  @override
  String get goldPaywallCancelled => 'الشراء اتلغى. مفيش حاجة اتخصمت.';

  @override
  String get goldPaywallInvalid =>
      'مقدرناش نتأكد من الشراء. جرّب «استرجع مشترياتي»، ولو لسه كلّم الدعم.';

  @override
  String get goldPaywallStoreError => 'المتجر رجّع مشكلة. جرّب تاني كمان شوية.';

  @override
  String goldPaywallAlreadyGold(String plan) {
    String _temp0 = intl.Intl.selectLogic(plan, {
      'monthly': 'إنت جولد: شهري',
      'yearly': 'إنت جولد: سنوي',
      'lifetime': 'إنت جولد: مدى الحياة',
      'other': 'إنت جولد',
    });
    return '$_temp0';
  }

  @override
  String get goldPaywallProtectNote =>
      'بعد الشراء، سجّل دخول على الموبايل ده عشان تحمي الجولد.';

  @override
  String get goldAccountTitle => 'جولد وحسابك';

  @override
  String goldAccountPlan(String plan, String date) {
    String _temp0 = intl.Intl.selectLogic(plan, {
      'monthly': 'جولد · شهري · بيتجدد $date',
      'yearly': 'جولد · سنوي · بيتجدد $date',
      'lifetime': 'جولد · مدى الحياة',
      'other': 'الباقة المجانية',
    });
    return '$_temp0';
  }

  @override
  String get goldAccountSeeGold => 'شوف جولد';

  @override
  String get goldAccountManage => 'إدارة الاشتراك';

  @override
  String get goldAccountRestore => 'استرجع مشترياتي';

  @override
  String get goldAccountRestoring => 'بدوّر على مشترياتك…';

  @override
  String get goldAccountRestoreDone => 'الجولد رجع ✓';

  @override
  String get goldAccountRestoreNone =>
      'مفيش مشتريات أقدر أرجّعها على الحساب ده';

  @override
  String get goldAccountEndedTitle => 'الجولد خلص';

  @override
  String get goldAccountEndedBody =>
      'بياناتك كلها لسه موجودة، وتقدر ترجع جولد في أي وقت.';

  @override
  String get goldAccountOtherPhone => 'استخدم جولد على موبايل تاني (اختياري)';

  @override
  String get goldAccountGoogle => 'كمّل بحساب Google';

  @override
  String get goldAccountApple => 'كمّل بحساب Apple';

  @override
  String get goldAccountPrivacy =>
      'بنربط باقة جولد بس. بيانات فلوسك عمرها ما بتتبعت.';

  @override
  String get goldAccountSigningIn => 'بدخل…';

  @override
  String get goldAccountSignInCancelled => 'الدخول اتلغى.';

  @override
  String get goldAccountSignInFailed => 'الدخول ما كملش. جرّب تاني.';

  @override
  String get goldAccountSignInAgain => 'سجّل دخول تاني عشان تكمّل';

  @override
  String goldAccountSignedInAs(String email) {
    return 'داخل بـ $email';
  }

  @override
  String goldAccountNextMove(String date) {
    return 'تقدر تنقل الجولد تاني يوم $date';
  }

  @override
  String get goldAccountSignOutTitle => 'تخرج من الحساب؟';

  @override
  String goldAccountSignOutBody(String state) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'linked': 'بياناتك كلها هتفضل على الموبايل. الجولد هيقف على الموبايل ده لحد ما تسجّل دخول تاني بنفس الحساب.',
      'other': 'بياناتك كلها هتفضل على الموبايل، والجولد هيفضل شغال.',
    });
    return '$_temp0';
  }

  @override
  String get goldAccountReplaceTitle => 'الموبايل ده مربوط بحساب تاني';

  @override
  String get goldAccountReplaceBody =>
      'تربطه بالحساب ده بدله؟ باقة الجولد بس هي اللي بتتربط.';

  @override
  String get goldAccountReplaceConfirm => 'اربطه بالحساب ده';

  @override
  String get goldAccountLostPhone =>
      'موبايلك القديم ضاع أو اتباع؟ كلّم الدعم وهنساعدك.';

  @override
  String get goldAccountDeleteRow => 'امسح الحساب';

  @override
  String get goldAccountDeleteTitle => 'تمسح حسابك؟';

  @override
  String get goldAccountDeleteBody =>
      'هنمسح حسابك والربط بالجولد من عندنا. مشترياتك هتفضل على حساب المتجر بتاعك.';

  @override
  String get goldAccountDeleteConfirm => 'امسح الحساب';

  @override
  String get goldAccountDeleted => 'الحساب اتمسح';

  @override
  String get goldSeatCooldownTitle => 'نقلت الجولد من قريب';

  @override
  String goldSeatCooldownBody(String date) {
    return 'تقدر تنقله تاني يوم $date، أو كلّم الدعم.';
  }

  @override
  String get goldSeatAttestTitle => 'مقدرناش نتأكد من الموبايل ده';

  @override
  String get goldSeatAttestBody =>
      'جرّب تاني بعد شوية. لو لسه، سجّل دخول بالحساب اللي اشتريت بيه، أو كلّم الدعم.';

  @override
  String get goldSeatAttestPlayServices =>
      'حدّث خدمات Google Play من المتجر وجرّب تاني.';

  @override
  String get goldSeatAttestUnavailable =>
      'التأكد من الموبايل مش متاح دلوقتي. سجّل دخول بالحساب اللي اشتريت بيه، أو كلّم الدعم.';

  @override
  String get goldSeatAccountRequiredTitle => 'سجّل دخول الأول';

  @override
  String get goldSeatAccountRequiredBody =>
      'اعمل تسجيل دخول بالحساب اللي اشتريت بيه.';

  @override
  String get goldSeatMovedUserTitle => 'الجولد اتنقل لموبايل تاني';

  @override
  String get goldSeatMovedUserBody =>
      'لو عايزه على الموبايل ده، استرجع مشترياتك أو سجّل دخول.';

  @override
  String get goldSeatMovedSupportTitle => 'الدعم نقل الجولد لموبايل تاني';

  @override
  String get goldSeatMovedSupportBody =>
      'لو ده مش اللي طلبته، كلّم الدعم وادّيهم كود الدعم.';

  @override
  String get goldSeatPausedTitle => 'الجولد واقف مؤقتاً';

  @override
  String get goldSeatPausedBody =>
      'اعمل تسجيل دخول عشان تستخدم الجولد على الموبايل ده. مكانك محفوظ ومش هيتحسب نقلة.';

  @override
  String get goldSeatTamperedTitle => 'اتصل بالنت عشان نتأكد من الجولد';

  @override
  String get goldSeatTamperedBody =>
      'ساعة الموبايل اتغيّرت. أول ما النت يشتغل هنتأكد، وبياناتك كلها لسه موجودة.';

  @override
  String goldSeatHeldElsewhere(String date) {
    return 'الدفع تم. الجولد لسه على الموبايل التاني، وتقدر تنقله يوم $date.';
  }

  @override
  String get goldSeatHeldElsewhereAccount =>
      'الدفع تم. عشان الجولد ييجي هنا، اعمل تسجيل دخول بالحساب اللي عليه الجولد.';

  @override
  String get goldSeatSupportNoticeTitle => 'الدعم ربط الجولد بحساب';

  @override
  String get goldSeatSupportNoticeBody =>
      'الدعم ربط الجولد بتاعك بحساب. لو ده مش إنت، كلّم الدعم.';

  @override
  String get goldSeatSignInLinked =>
      'الحساب اتربط، بس الجولد لسه مجاش على الموبايل ده.';

  @override
  String get goldSeatRestoreSuggested =>
      'جرّب «استرجع مشترياتي»، والجولد هيرجع على الموبايل ده.';

  @override
  String get goldSeatRestoreAction => 'استرجع مشترياتي';

  @override
  String goldSeatSupportPath(String date) {
    return 'الجولد مش هينفع ينتقل للموبايل ده قبل يوم $date. كلّم الدعم وهنساعدك.';
  }

  @override
  String get goldSeatProtectTitle => 'سجّل دخول هنا عشان تحمي الجولد';

  @override
  String get goldSeatProtectBody =>
      'الربط بيتعمل من الموبايل اللي اشتريت عليه بس. بعدها تقدر تنقل الجولد لموبايل جديد بحسابك.';

  @override
  String get goldSeatProtectDone => 'الجولد اتربط بحسابك ✓';

  @override
  String goldSeatDeleteWarning(String state, String date) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'cooldown':
          'لو مسحت كل حاجة، هيتحسب إن الجولد اتنقل، ومش هتقدر ترجّعه على الموبايل ده قبل يوم $date.',
      'other': 'لو مسحت كل حاجة ورجعت الجولد، ده هيتحسب نقلة الشهر ده.',
    });
    return '$_temp0';
  }

  @override
  String get notificationsSettingsTitle => 'التنبيهات';

  @override
  String get notificationsSettingsBudget => 'تنبيهات الميزانية';

  @override
  String get notificationsSettingsSpikes => 'لما الصرف يزيد';

  @override
  String get notificationsSettingsDues => 'الأقساط والفواتير';

  @override
  String notificationsSettingsDueDays(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'قبلها بـ $n يوم',
      many: 'قبلها بـ $n يوم',
      few: 'قبلها بـ $n أيام',
      two: 'قبلها بيومين',
      one: 'قبلها بيوم',
      zero: 'يوم الاستحقاق نفسه',
    );
    return '$_temp0';
  }

  @override
  String get notificationsSettingsDuplicates => 'حركة اتسجلت مرتين';

  @override
  String get notificationsSettingsRenewals => 'تجديد الاشتراكات';

  @override
  String get notificationsSettingsBackup => 'مشاكل النسخة الاحتياطية';

  @override
  String get notificationsSettingsWeekly => 'ملخص الأسبوع';

  @override
  String get notificationsSettingsWeeklySub => 'كل جمعة الصبح';

  @override
  String get notificationsSettingsQuiet => 'ساعات الهدوء';

  @override
  String notificationsSettingsQuietRange(String start, String end) {
    return 'من $start لحد $end';
  }

  @override
  String get notificationsSettingsHideAmounts => 'اخفي المبالغ على شاشة القفل';

  @override
  String get notificationsSettingsHideAmountsHint =>
      'التنبيه بيوصل من غير مبلغ ولا اسم تاجر.';

  @override
  String get notificationsSettingsDaysRange =>
      'اختار من يوم الاستحقاق لحد تلاتين يوم قبله';

  @override
  String get notificationsSettingsQuietSame =>
      'بداية ونهاية ساعات الهدوء لازم يختلفوا';

  @override
  String get notificationsSettingsOsOffTitle => 'التنبيهات مقفولة لزغلول';

  @override
  String get notificationsSettingsOsOffBody =>
      'شغّلها من إعدادات الموبايل عشان توصلك.';

  @override
  String get notificationsAlertBudgetNearTitle => 'قربت توصل لحد الميزانية';

  @override
  String notificationsAlertBudgetNear(
    String percent,
    String category,
    String left,
  ) {
    return 'صرفت $percent من ميزانية $category، وفاضلك $left.';
  }

  @override
  String notificationsAlertBudgetNearHidden(String category) {
    return 'ميزانية $category قربت تخلص.';
  }

  @override
  String get notificationsAlertBudgetReachedTitle => 'وصلت لحد الميزانية';

  @override
  String notificationsAlertBudgetReached(
    String category,
    String spent,
    String budget,
  ) {
    return 'ميزانية $category خلصت: صرفت $spent من $budget.';
  }

  @override
  String notificationsAlertBudgetReachedHidden(String category) {
    return 'ميزانية $category خلصت.';
  }

  @override
  String get notificationsAlertSpikeTitle => 'صرفك النهارده أكتر من المعتاد';

  @override
  String notificationsAlertSpike(String spent, String delta) {
    return 'صرفت النهارده $spent، أكتر من المعتاد بـ $delta.';
  }

  @override
  String get notificationsAlertSpikeHidden =>
      'صرفك النهارده أكتر من المعتاد. افتح زغلول وراجع.';

  @override
  String get notificationsAlertDueTitle => 'قسط أو فاتورة قربت';

  @override
  String notificationsAlertDue(
    int count,
    String item,
    String amount,
    String n,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$item بيستحق بعد $n يوم: $amount',
      many: '$item بيستحق بعد $n يوم: $amount',
      few: '$item بيستحق بعد $n أيام: $amount',
      two: '$item بيستحق بعد يومين: $amount',
      one: '$item بيستحق بكره: $amount',
      zero: '$item بيستحق النهارده: $amount',
    );
    return '$_temp0';
  }

  @override
  String get notificationsAlertDueHidden => 'عندك قسط أو فاتورة بتستحق قريب.';

  @override
  String get notificationsAlertDuplicateTitle => 'ممكن حركة تكون اتسجلت مرتين';

  @override
  String notificationsAlertDuplicate(String merchant, String amount) {
    return '$merchant: $amount ظهرت مرتين تقريباً في نفس الوقت. بُص عليها.';
  }

  @override
  String get notificationsAlertDuplicateHidden =>
      'في حركة ممكن تكون مكررة. افتح زغلول وراجعها.';

  @override
  String get notificationsAlertRenewalTitle => 'اشتراك هيتجدد';

  @override
  String notificationsAlertRenewal(
    String merchant,
    String date,
    String amount,
  ) {
    return '$merchant هيتجدد يوم $date بـ $amount.';
  }

  @override
  String get notificationsAlertRenewalHidden => 'في اشتراك هيتجدد قريب.';

  @override
  String get notificationsAlertBackupTitle => 'النسخة الاحتياطية ماتعملتش';

  @override
  String get notificationsAlertBackupBody =>
      'جرّب تاني من الإعدادات. بياناتك لسه على الموبايل.';

  @override
  String get notificationsAlertWeeklyTitle => 'ملخص أسبوعك جاهز';

  @override
  String notificationsAlertWeekly(String spent, String category) {
    return 'صرفت $spent الأسبوع ده، وأكتر حاجة كانت $category.';
  }

  @override
  String get notificationsAlertWeeklyHidden =>
      'ملخص أسبوعك جاهز. افتح زغلول تشوفه.';

  @override
  String get privacyMainTitle => 'خصوصيتك';

  @override
  String get privacyMainStaysTitle => 'اللي بيفضل على موبايلك';

  @override
  String get privacyMainStaysBody =>
      'رسايلك وحركاتك وأرصدتك وميزانياتك وأصولك وقواعدك. كله متشفّر.';

  @override
  String get privacyMainAppLock => 'قفل التطبيق';

  @override
  String get privacyMainServerRow => 'اللي سيرفر زغلول يعرفه عنك';

  @override
  String get privacyServerTitle => 'اللي سيرفر زغلول يعرفه عنك';

  @override
  String get privacyServerSummary =>
      'فلوسك وحركاتك عمرها ما بتسيب موبايلك. السيرفر بيعرف الحاجات دي بس:';

  @override
  String get privacyServerItemId =>
      'رقم عشوائي للتطبيق، مش اسمك ولا رقم موبايلك';

  @override
  String get privacyServerItemPurchase => 'شراء الجولد بتاعك، عشان نتأكد منه';

  @override
  String get privacyServerItemSignIn => 'تسجيل دخولك، لو استخدمته بس';

  @override
  String get privacyServerItemMerchants => 'أسماء التجار، لو سمحت بس';

  @override
  String get privacyServerItemVersion =>
      'نوع الموبايل وإصدار التطبيق وإصدار قايمة التجار';

  @override
  String get privacyServerItemAttest =>
      'إثبات إن الموبايل حقيقي (Play Integrity أو App Attest) وقت الاسترجاع، وأحياناً وقت الشراء';

  @override
  String get privacyServerItemBankRequest =>
      'طلب دعم بنك، لو طلبته بس: اسم البنك وبلده ونوع التنبيه';

  @override
  String get privacyServerSeatKeysSummary =>
      'على الآيفون بس: زغلول بيعرف إن التثبيتات القديمة كانت على نفس الموبايل.';

  @override
  String get privacyServerSeatKeys =>
      'على الآيفون، يرسل التطبيق عند الاسترجاع أو تسجيل الدخول إثباتاً من هذا التثبيت ومن حتى أربعة تثبيتات سابقة، ليعرف الخادم أنها على الجهاز نفسه. يحفظ الخادم صورة مشفّرة فقط، ولا يسجّل المفاتيح.';

  @override
  String get privacyServerDeleteKeepsSummary =>
      'لو مسحت كل حاجة من الآيفون، الجولد يقدر يرجع عليه من غير نقلة.';

  @override
  String get privacyServerDeleteKeeps =>
      'يُبقي «امسح كل حاجة» على الآيفون مفاتيح التعريف على الجهاز، ليعود الجولد إليه دون احتساب نقلة. ويحتفظ الخادم بتجزئة مفتاحية للمفتاح مع الشراء حتى يُحذف الشراء. مسح الآيفون بالكامل يزيلها.';

  @override
  String get privacyServerTimeNonceSummary =>
      'رقم عشوائي بيتأكد بيه السيرفر من الوقت، ومفيهوش أي حاجة عنك.';

  @override
  String get privacyServerTimeNonce =>
      'تحمل بعض الطلبات رقماً عشوائياً يُستخدم مرة واحدة للتحقق من الوقت. لا يتضمن أي معلومة عن الجهاز أو المستخدم، ولا يُخزَّن.';

  @override
  String get privacyServerSupportNoticeSummary =>
      'لو الدعم ربط الجولد بحساب، موبايلك اللي اشتريت عليه بيتبلّغ.';

  @override
  String get privacyServerSupportNotice =>
      'إذا ربط الدعم الجولد بحساب، يُبلَّغ الهاتف الذي اشتُري عليه عند اتصاله التالي. يكرّر الخادم الإشعار حتى تؤكد مزامنة ذلك الهاتف استلامه، حتى لا يضيع إن فُقدت الاستجابة.';

  @override
  String get privacyServerSupportRowsSummary =>
      'لما تمسح حسابك، بنمسح كل حاجة، وأثر الدعم بيتمسح بعد سنة.';

  @override
  String get privacyServerSupportRows =>
      'عند حذف الحساب تُحذف بياناته من الخادم، عدا سجلات تدقيق الدعم التي تحمل بصمة مشفّرة للبريد ومعرّف الحساب، وتُحذف تلقائياً بعد سنة من إنشائها.';

  @override
  String get privacyContributeLabel => 'ساعد في تحسين قايمة التجار';

  @override
  String get privacyContributeSentence =>
      'لو شغّلتها، بنبعت اسم التاجر والتصنيف اللي اخترته بس.';

  @override
  String get privacyContributeInfoTitle => 'بالظبط إيه اللي بيتبعت؟';

  @override
  String get privacyContributeSends =>
      'بنبعت: اسم التاجر بعد تنضيفه، وكود البنك، والتصنيف اللي اخترته.';

  @override
  String get privacyContributeNeverSends =>
      'مبنبعتش: مبالغ، ولا تواريخ، ولا أرقام كروت، ولا أرقام تليفونات، ولا حسابات إنستاباي، ولا أسماء ناس.';

  @override
  String get privacyContributeFilters =>
      'بنستبعد أي اسم شكله اسم شخص، والتصنيفات الخاصة بيك عمرها ما بتتبعت.';

  @override
  String get privacyContributeOffHint => 'تقدر تقفلها في أي وقت.';

  @override
  String get privacyContributeTurnedOn =>
      'شكراً. هنبعت اسم التاجر والتصنيف بس.';

  @override
  String privacyRootedRow(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'الآيفون ده متعمله جيلبريك، فحماية بياناتك أضعف.',
      'other': 'الموبايل ده متعمله روت، فحماية بياناتك أضعف.',
    });
    return '$_temp0';
  }

  @override
  String get privacyRootedTitle => 'يعني إيه حماية أضعف؟';

  @override
  String get privacyRootedBody =>
      'على موبايل متعدّل، تطبيق تاني ممكن يوصل لملفات زغلول بسهولة أكتر. بياناتك لسه متشفّرة، بس الأمان مش كامل.';

  @override
  String get privacyDeleteRow => 'امسح كل حاجة';

  @override
  String get privacyDeleteTitle => 'تمسح كل حاجة من على الموبايل ده؟';

  @override
  String get privacyDeleteBody =>
      'هنمسح كل حركاتك وإعداداتك ومفاتيح الحماية من على الموبايل ده. مفيش رجوع.';

  @override
  String privacyDeleteLastBackup(String date) {
    return 'آخر نسخة احتياطية: $date';
  }

  @override
  String get privacyDeleteNoBackup =>
      'مفيش نسخة احتياطية. اللي هتمسحه مش هيرجع.';

  @override
  String get privacyDeleteIosKeys =>
      'على الآيفون، مفاتيح تعريف الموبايل بتفضل عليه عشان الجولد يرجع من غير نقلة، ومفيهاش أي بيانات مالية. مسح الآيفون كله بيشيلها.';

  @override
  String get privacyDeleteIosServer =>
      'والسيرفر بيحتفظ بصورة مشفّرة من المفتاح مع الشراء لحد ما الشراء يتمسح.';

  @override
  String get privacyDeleteTypePrompt => 'اكتب «احذف» أو DELETE عشان تأكد';

  @override
  String get privacyDeleteTypeLabel => 'كلمة التأكيد';

  @override
  String get privacyDeleteTypeMismatch => 'الكلمة مش مطابقة';

  @override
  String get privacyDeleteConfirm => 'امسح كل حاجة';

  @override
  String get privacyDeleteWorking => 'بمسح…';

  @override
  String get privacyDeleteServerCopy =>
      'النسخة اللي على السيرفر هتنتهي لوحدها.';

  @override
  String get widgetOpenZaghlol => 'افتح زغلول';

  @override
  String get privacyDeleteBackupsKept =>
      'النسخ الاحتياطية اللي على Google Drive أو iCloud هتفضل زي ما هي. لو عايز تمسحها، امسحها من هناك.';

  @override
  String get privacyDeleteFailed =>
      'مقدرناش نمسح كل حاجة. افتح الأبلكيشن تاني وهنكمّل.';

  @override
  String get settingsPrefsTitle => 'التفضيلات';

  @override
  String get settingsPrefsLanguage => 'اللغة';

  @override
  String get settingsPrefsLanguageAr => 'العربية';

  @override
  String get settingsPrefsLanguageEn => 'English';

  @override
  String get settingsPrefsDigits => 'الأرقام';

  @override
  String get settingsPrefsDigitsArabic => 'عربي';

  @override
  String get settingsPrefsDigitsWestern => 'إنجليزي';

  @override
  String get settingsPrefsTheme => 'الشكل';

  @override
  String get settingsPrefsThemeSystem => 'زي الموبايل';

  @override
  String get settingsPrefsThemeLight => 'فاتح';

  @override
  String get settingsPrefsThemeDark => 'غامق';

  @override
  String get settingsPrefsCurrency => 'العملة الأساسية';

  @override
  String get settingsPrefsApprox => 'اعرض مجموع تقريبي (≈)';

  @override
  String get settingsPrefsApproxHint =>
      'بيتحسب بسعر تقريبي ومكتوب عليه كده. مفيش حاجة بتتحوّل فعلاً.';

  @override
  String get settingsPrefsCombineInto => 'حوّل المجموع لـ';

  @override
  String get settingsPrefsPayday => 'يوم القبض';

  @override
  String settingsPrefsPaydayDay(String day) {
    return 'يوم $day';
  }

  @override
  String get settingsPrefsPaydayMonth => 'أول الشهر';

  @override
  String get settingsPrefsPaydayRange =>
      'اختار يوم من أول الشهر لحد تمانية وعشرين';

  @override
  String get settingsPrefsPaydayChangeTitle => 'تغيّر يوم القبض في نص الدورة؟';

  @override
  String get settingsPrefsPaydayChangeBody =>
      'الدورة الحالية هتخلص بدري، وهتبدأ دورة جديدة من يوم القبض الجديد.';

  @override
  String get settingsPrefsIncome => 'هدف الدخل الشهري';

  @override
  String get settingsPrefsIncomeOptional => 'اختياري';

  @override
  String get settingsPrefsIncomeNegative => 'المبلغ ميكونش بالسالب';

  @override
  String get settingsPrefsAppLock => 'قفل التطبيق';

  @override
  String get settingsPrefsLockAfter => 'اقفل بعد';

  @override
  String get settingsPrefsLockImmediately => 'على طول';

  @override
  String settingsPrefsLockAfterMinutes(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n دقيقة',
      many: '$n دقيقة',
      few: '$n دقايق',
      two: 'دقيقتين',
      one: 'دقيقة',
    );
    return '$_temp0';
  }

  @override
  String settingsPrefsBiometricsUnavailable(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'البصمة مش متاحة. هنستخدم كود الآيفون بدلها.',
      'other': 'البصمة مش متاحة. هنستخدم قفل الموبايل بدلها.',
    });
    return '$_temp0';
  }

  @override
  String get shareStudioTitle => 'شارك إنجازك';

  @override
  String get shareStudioCloseA11y => 'اقفل';

  @override
  String get shareStudioTemplateSavings => 'التحويش';

  @override
  String get shareStudioTemplateDelivery => 'تقليل الدليفري';

  @override
  String get shareStudioTemplateBudget => 'تحت الميزانية';

  @override
  String get shareStudioShowAmounts => 'اظهر المبالغ';

  @override
  String get shareStudioShowAmountsHint => 'وإنت مقفلها بتظهر النسب بس.';

  @override
  String get shareStudioCertificate => 'شهادة تقدير من الكابتن زغلول';

  @override
  String shareStudioCardSavings(String percent) {
    return 'وفرت $percent من مرتبي الشهر ده!';
  }

  @override
  String shareStudioCardSavingsAmount(String amount) {
    return 'وفرت $amount الشهر ده!';
  }

  @override
  String shareStudioCardDelivery(String percent) {
    return 'قللت الدليفري $percent الشهر ده!';
  }

  @override
  String shareStudioCardDeliveryAmount(String amount) {
    return 'قللت الدليفري $amount الشهر ده!';
  }

  @override
  String shareStudioCardBudget(String percent) {
    return 'خلصت الدورة تحت الميزانية بـ $percent!';
  }

  @override
  String shareStudioCardBudgetAmount(String amount) {
    return 'خلصت الدورة تحت الميزانية بـ $amount!';
  }

  @override
  String get shareStudioHashtag => '#زغلول_ضبط_الميزانية';

  @override
  String get shareStudioShare => 'شارك';

  @override
  String shareStudioPreviewA11y(String text) {
    return 'معاينة الكارت: $text';
  }

  @override
  String get shareStudioUnencrypted =>
      'الصورة مش متشفّرة، ولما تشاركها بتبقى بره زغلول.';

  @override
  String get shareStudioEmptyTitle => 'لسه مفيش إنجاز تشاركه';

  @override
  String get shareStudioEmptyBody => 'كمّل تسجيل وهتلاقي إنجازات هنا.';

  @override
  String get shareStudioRendering => 'بجهّز الكارت…';

  @override
  String get shareStudioRenderFailed => 'معرفتش أجهّز الصورة. جرّب تاني.';

  @override
  String get aboutMainTitle => 'عن زغلول';

  @override
  String aboutMainVersion(String appVersion, String build) {
    return 'الإصدار $appVersion (رقم $build)';
  }

  @override
  String aboutMainCatalog(String date) {
    return 'قايمة التجار اتحدّثت $date';
  }

  @override
  String aboutMainPrices(String date) {
    return 'الأسعار اتحدّثت $date';
  }

  @override
  String get aboutMainNeverSynced => 'لسه ما اتحدّثتش (شغال من غير نت)';

  @override
  String get aboutMainTerms => 'الشروط';

  @override
  String get aboutMainPrivacy => 'سياسة الخصوصية';

  @override
  String get aboutMainLicenses => 'تراخيص المصدر المفتوح';

  @override
  String get aboutMainDisclaimers => 'تنبيهات مهمة';

  @override
  String get aboutMainSupport => 'كلّم الدعم';

  @override
  String get aboutMainSupportSubject => 'مساعدة في زغلول';

  @override
  String get aboutDiagTitle => 'بيانات تشخيص';

  @override
  String get aboutDiagBody =>
      'ملف فيه أكواد أعطال بس، من غير رسايل ولا مبالغ ولا أسماء. تبعته للدعم لو احتجت.';

  @override
  String get aboutDiagShare => 'ابعت الملف';

  @override
  String get aboutDiagEmpty => 'مفيش أعطال مسجلة.';

  @override
  String get legalTermsSummary =>
      'الشروط باختصار: بتستخدم زغلول لإدارة فلوسك بنفسك، وقرارك المالي مسؤوليتك.';

  @override
  String get legalTermsOpen => 'اقرا الشروط كاملة';

  @override
  String get legalPrivacySummary =>
      'الخصوصية باختصار: بيانات فلوسك بتفضل على موبايلك، والسيرفر مبيعرفش غير اللي مكتوب في «خصوصيتك».';

  @override
  String get legalPrivacyOpen => 'اقرا السياسة كاملة';

  @override
  String get legalLicensesSummary =>
      'زغلول بيستخدم برامج مفتوحة المصدر، وده ترخيص كل واحد منها.';

  @override
  String get legalLicensesTitle => 'تراخيص المصدر المفتوح';

  @override
  String get legalDisclaimerTitle => 'تنبيهات مهمة';

  @override
  String get legalDisclaimerCoachingSummary =>
      'نصايح زغلول أفكار عامة، مش نصيحة مالية.';

  @override
  String get legalDisclaimerCoaching =>
      'توجيهات الكابتن زغلول وتفسيرات الرسوم البيانية واقتراحاته أفكار عامة للتوعية، وليست نصيحة مالية أو استثمارية أو قانونية. القرار النهائي لك.';

  @override
  String get legalDisclaimerEstimatesSummary =>
      'الأرقام تقريبية، وكشف البنك هو المرجع.';

  @override
  String get legalDisclaimerEstimates =>
      'الأرقام المعروضة تقديرية، ومبنية على الرسائل التي يقرؤها التطبيق وعلى ما تدخله بنفسك، وقد تختلف عن كشوف حساباتك الرسمية.';

  @override
  String get legalDisclaimerPricesSummary =>
      'أسعار الدهب والعملات إرشادية، وممكن تتأخر عن السوق.';

  @override
  String get legalDisclaimerPrices =>
      'أسعار الذهب والعملات المعروضة إرشادية فقط، وقد تتأخر أو تختلف عن سعر السوق وقت التنفيذ.';

  @override
  String get legalDisclaimerZakahRef =>
      'حساب الزكاة تقدير مش فتوى. التفاصيل في شاشة الزكاة.';

  @override
  String get legalDisclaimerRoiRef =>
      'نصايح الاستثمار أفكار عامة مش نصيحة مالية. التفاصيل في شاشة النصايح.';

  @override
  String get legalDisclaimerFooter => 'زغلول بيدّي أفكار عامة، مش نصيحة مالية.';

  @override
  String get errorsGenericUnexpectedTitle => 'حصلت مشكلة صغيرة';

  @override
  String get errorsGenericUnexpectedBody =>
      'مش بسببك، وبياناتك في أمان على موبايلك. ارجع للرئيسية وجرّب تاني.';

  @override
  String get errorsGenericGoHome => 'ارجع للرئيسية';

  @override
  String get errorsGenericActionFailed =>
      'الحاجة دي ماتمتش. جرّب تاني كمان شوية.';

  @override
  String get errorsNetworkOffline =>
      'مفيش نت دلوقتي. اللي بتشوفه محفوظ على موبايلك.';

  @override
  String get errorsNetworkTimeout => 'الاتصال أخد وقت طويل. جرّب تاني.';

  @override
  String get errorsNetworkServer => 'السيرفر مشغول دلوقتي. هنجرّب تاني لوحدنا.';

  @override
  String get errorsNetworkRateLimited =>
      'الطلبات كتير شوية. استنى شوية وجرّب تاني.';

  @override
  String get errorsStorageOpenTitle => 'مقدرناش نفتح بياناتك';

  @override
  String get errorsStorageOpenBody =>
      'ممكن ترجّعها من نسخة احتياطية أو تبدأ من جديد. الملف القديم هيفضل لحد ما تختار.';

  @override
  String get errorsStorageRestore => 'استرجع من نسخة';

  @override
  String get errorsStorageStartFreshWarn =>
      'هنمسح الملف القديم اللي مش بيتفتح. مفيش رجوع.';

  @override
  String get errorsStorageFull =>
      'المساحة على الموبايل خلصت. فضّي مساحة وجرّب تاني. الرسايل اللي وصلت متحفظة.';

  @override
  String get errorsStorageMigrationTitle => 'التحديث ماكملش';

  @override
  String get errorsStorageMigrationBody =>
      'رجّعنا بياناتك زي ما كانت. جرّب تاني.';

  @override
  String get errorsStorageIo => 'حصلت مشكلة في قراءة أو حفظ ملف. جرّب تاني.';

  @override
  String get errorsCapturePermission =>
      'الإذن ده مقفول. شغّله من إعدادات الموبايل.';

  @override
  String get errorsCaptureUnavailable => 'الحاجة دي مش متاحة على الموبايل ده.';

  @override
  String get errorsCaptureSpool =>
      'في رسايل مقدرتش أقراها. دوّر في الرسايل القديمة تاني.';

  @override
  String get errorsCaptureKeyChanged =>
      'الحماية على الموبايل اتجدّدت بعد تغيير القفل، ورسايل مستنية ممكن تكون ضاعت. دوّر في الرسايل القديمة تاني.';

  @override
  String get errorsCaptureConfig =>
      'بظبّط إعدادات اللقط لوحدي. مفيش حاجة مطلوبة منك.';

  @override
  String get errorsCaptureOcr =>
      'معرفتش أقرا الصورة. جرّب صورة أوضح أو اكتب الحركة بإيدك.';

  @override
  String get errorsMoneyCurrency => 'العملتين مختلفتين، مينفعش نجمعهم.';

  @override
  String get errorsMoneyOffset => 'المبلغ الراجع أكبر من الحركة نفسها.';

  @override
  String get errorsAccountTokenExpired => 'سجّل دخول تاني عشان تكمّل.';

  @override
  String get errorsAccountFailed => 'العملية ماتمتش. جرّب تاني كمان شوية.';

  @override
  String accountsOverviewApproxNotIncluded(String currencies) {
    return 'مش محسوبة في التقريبي: $currencies';
  }

  @override
  String get accountsOverviewApproxLabel => 'تقريبي';

  @override
  String get goldSeatTamperedClockBody =>
      'ظبّط التاريخ والوقت في موبايلك على تلقائي، وبعدها افتح زغلول تاني.';

  @override
  String get transactionsEditLinksRemoved =>
      'المبلغ اتغيّر، فالروابط اتشالت: الفلوس الراجعة والتقسيم المرتبطين بالمعاملة دي اتفكّوا.';

  @override
  String get goldAccountSignedIn => 'مسجّل دخول';

  @override
  String insightsChartsPeakHour(String time) {
    return 'أكتر ساعة بتصرف فيها حوالين $time';
  }

  @override
  String get homeFeedExcludedFromSpending => 'مش محسوبة في المصروفات';

  @override
  String get notificationsAlertBackupReminderTitle => 'وقت النسخة الاحتياطية';

  @override
  String get notificationsAlertBackupReminderBody =>
      'خد نسخة احتياطية من الإعدادات عشان بياناتك تفضل في أمان.';

  @override
  String transactionsReimbUnassigned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مبالغ اتفكّت لأن المصروف قلّ',
      one: 'مبلغ واحد اتفكّ لأن المصروف قلّ',
    );
    return '$_temp0';
  }
}
