import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// Brand name, shown as the app title.
  ///
  /// In ar, this message translates to:
  /// **'زغلول'**
  String get appName;

  /// No description provided for @commonNavHome.
  ///
  /// In ar, this message translates to:
  /// **'الرئيسية'**
  String get commonNavHome;

  /// No description provided for @commonNavInsights.
  ///
  /// In ar, this message translates to:
  /// **'الحسبة'**
  String get commonNavInsights;

  /// No description provided for @commonNavMoney.
  ///
  /// In ar, this message translates to:
  /// **'فلوسي'**
  String get commonNavMoney;

  /// No description provided for @commonNavZaghlol.
  ///
  /// In ar, this message translates to:
  /// **'زغلول'**
  String get commonNavZaghlol;

  /// No description provided for @commonNavAddA11y.
  ///
  /// In ar, this message translates to:
  /// **'سجّل بسرعة'**
  String get commonNavAddA11y;

  /// Title of the app lock screen (S-05).
  ///
  /// In ar, this message translates to:
  /// **'زغلول مقفول'**
  String get appLockTitle;

  /// Button that opens the phone's biometric or passcode prompt.
  ///
  /// In ar, this message translates to:
  /// **'افتح'**
  String get appLockUnlock;

  /// Reason shown inside the OS biometric prompt.
  ///
  /// In ar, this message translates to:
  /// **'اتأكد إنك إنت عشان تفتح زغلول'**
  String get appLockReason;

  /// Shown after a failed unlock.
  ///
  /// In ar, this message translates to:
  /// **'مظبطتش. جرّب تاني.'**
  String get appLockFailed;

  /// Shown when the phone has no screen lock.
  ///
  /// In ar, this message translates to:
  /// **'فعّل قفل الشاشة (PIN أو نمط أو باسورد) في تليفونك وبعدين جرّب تاني.'**
  String get appLockUnavailable;

  /// Shown when the OS blocks the prompt after too many wrong tries.
  ///
  /// In ar, this message translates to:
  /// **'حاولت كتير. استنى شوية وجرّب تاني.'**
  String get appLockLockedOut;

  /// Title of the rooted or jailbroken warning (FR-SEC-07).
  ///
  /// In ar, this message translates to:
  /// **'حماية تليفونك أضعف'**
  String get appLockRootedTitle;

  /// Body of the rooted or jailbroken warning. It warns and never blocks.
  ///
  /// In ar, this message translates to:
  /// **'التليفون ده شكله معمول له روت أو جيلبريك، فحماية بياناتك عليه أضعف. التطبيق شغال عادي، بس خد بالك.'**
  String get appLockRootedBody;

  /// Button that closes the rooted warning.
  ///
  /// In ar, this message translates to:
  /// **'تمام'**
  String get appLockRootedOk;

  /// No description provided for @homeQuickAddTitle.
  ///
  /// In ar, this message translates to:
  /// **'عايز تسجل إيه؟'**
  String get homeQuickAddTitle;

  /// No description provided for @homeQuickAddSay.
  ///
  /// In ar, this message translates to:
  /// **'قول'**
  String get homeQuickAddSay;

  /// No description provided for @homeQuickAddType.
  ///
  /// In ar, this message translates to:
  /// **'اكتب'**
  String get homeQuickAddType;

  /// No description provided for @homeQuickAddScan.
  ///
  /// In ar, this message translates to:
  /// **'صوّر'**
  String get homeQuickAddScan;

  /// No description provided for @homeQuickAddAsset.
  ///
  /// In ar, this message translates to:
  /// **'أصل'**
  String get homeQuickAddAsset;

  /// No description provided for @homeQuickAddSayA11y.
  ///
  /// In ar, this message translates to:
  /// **'قول لزغلول'**
  String get homeQuickAddSayA11y;

  /// No description provided for @homeQuickAddTypeA11y.
  ///
  /// In ar, this message translates to:
  /// **'اكتب حركة'**
  String get homeQuickAddTypeA11y;

  /// No description provided for @homeQuickAddScanA11y.
  ///
  /// In ar, this message translates to:
  /// **'اقرا سكرين شوت'**
  String get homeQuickAddScanA11y;

  /// No description provided for @homeQuickAddAssetA11y.
  ///
  /// In ar, this message translates to:
  /// **'ضيف أصل'**
  String get homeQuickAddAssetA11y;

  /// No description provided for @ingestionReviewTitle.
  ///
  /// In ar, this message translates to:
  /// **'مستني رأيك 👀'**
  String get ingestionReviewTitle;

  /// No description provided for @notificationsChannelName.
  ///
  /// In ar, this message translates to:
  /// **'التنبيهات'**
  String get notificationsChannelName;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'احفظ'**
  String get commonActionSave;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get commonActionCancel;

  /// B · closes a sheet
  ///
  /// In ar, this message translates to:
  /// **'تمام'**
  String get commonActionDone;

  /// B · glossary «تمام»
  ///
  /// In ar, this message translates to:
  /// **'تمام'**
  String get commonActionConfirm;

  /// B · glossary «سيبها»
  ///
  /// In ar, this message translates to:
  /// **'سيبها'**
  String get commonActionDismiss;

  /// B · snackbar action, 5 s (C-19)
  ///
  /// In ar, this message translates to:
  /// **'تراجع'**
  String get commonActionUndo;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'جرّب تاني'**
  String get commonActionTryAgain;

  /// B · stepper header
  ///
  /// In ar, this message translates to:
  /// **'تخطّي'**
  String get commonActionSkip;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'كمّل'**
  String get commonActionContinue;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'مش دلوقتي'**
  String get commonActionNotNow;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'بعدين'**
  String get commonActionLater;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'عدّل'**
  String get commonActionEdit;

  /// B · destructive variant
  ///
  /// In ar, this message translates to:
  /// **'امسح'**
  String get commonActionDelete;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اقفل'**
  String get commonActionClose;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'رجوع'**
  String get commonActionBackA11y;

  /// A · ⋮ menu
  ///
  /// In ar, this message translates to:
  /// **'اختيارات تانية'**
  String get commonActionMoreA11y;

  /// B · glossary
  ///
  /// In ar, this message translates to:
  /// **'شوف الكل'**
  String get commonActionSeeAll;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'شيل الفلتر'**
  String get commonActionClearFilter;

  /// B · opens OS settings
  ///
  /// In ar, this message translates to:
  /// **'افتح الإعدادات'**
  String get commonActionOpenSettings;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'صلّحها'**
  String get commonActionFix;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'أيوه'**
  String get commonActionYes;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'لأ'**
  String get commonActionNo;

  /// B · S-11 nav bar
  ///
  /// In ar, this message translates to:
  /// **'اختار'**
  String get commonActionSelect;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اختار الكل'**
  String get commonActionSelectAll;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'ابعت'**
  String get commonActionSend;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اربط'**
  String get commonActionLink;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'فك الربط'**
  String get commonActionUnlink;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'المزيد'**
  String get commonActionMore;

  /// C · passphrase reveal
  ///
  /// In ar, this message translates to:
  /// **'اظهر'**
  String get commonActionShow;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'اخفي'**
  String get commonActionHide;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اعرف أكتر'**
  String get commonActionLearnMore;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'دوّر'**
  String get commonActionSearchA11y;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تسيب اللي كتبته؟'**
  String get commonDiscardTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اللي ما اتحفظش هيروح.'**
  String get commonDiscardBody;

  /// B · destructive
  ///
  /// In ar, this message translates to:
  /// **'متحفظش'**
  String get commonDiscardConfirm;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'كمّل تعديل'**
  String get commonDiscardKeep;

  /// A · Home gear
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get commonNavSettingsA11y;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'كل الكروت'**
  String get commonCardFilterAll;

  /// C · count:int, n · shown when 2+ cards are selected
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{كارت واحد} =2{كارتين} few{{n} كروت} many{{n} كارت} other{{n} كارت}}'**
  String commonCardFilterCount(int count, String n);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تشوف أنهي كروت؟'**
  String get commonCardFilterSheetTitle;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'شيل فلتر الكروت'**
  String get commonCardFilterClearA11y;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'الفلتر شغال: {cards}'**
  String commonCardFilterActiveA11y(String cards);

  /// C · currency = ISO code or «ج.م»
  ///
  /// In ar, this message translates to:
  /// **'≈ {currency}'**
  String commonCurrencyApproxChip(String currency);

  /// L · FR-CUR-04
  ///
  /// In ar, this message translates to:
  /// **'تقريبي بسعر {date}'**
  String commonCurrencyApproxCaption(String date);

  /// A · read before a ≈ amount
  ///
  /// In ar, this message translates to:
  /// **'تقريباً'**
  String get commonCurrencyApproxA11y;

  /// C · C-21, older than 24 h
  ///
  /// In ar, this message translates to:
  /// **'سعر قديم'**
  String get commonBadgeStale;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'السعر ده عدى عليه أكتر من يوم'**
  String get commonBadgeStaleA11y;

  /// A · C-04 masked •••
  ///
  /// In ar, this message translates to:
  /// **'المبلغ مخفي'**
  String get commonMoneyMaskedA11y;

  /// A · C-11 pager
  ///
  /// In ar, this message translates to:
  /// **'صفحة {index} من {total}: {currency}'**
  String commonMoneyCurrencyPagerA11y(
    String currency,
    String index,
    String total,
  );

  /// C
  ///
  /// In ar, this message translates to:
  /// **'رسالة SMS'**
  String get commonSourceSms;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'إشعار'**
  String get commonSourceNotification;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'Apple Pay'**
  String get commonSourceApplePay;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'اختصار'**
  String get commonSourceShortcut;

  /// C · OCR
  ///
  /// In ar, this message translates to:
  /// **'صورة'**
  String get commonSourceScan;

  /// C · PDF / online-bank file
  ///
  /// In ar, this message translates to:
  /// **'كشف حساب'**
  String get commonSourceStatement;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'ملف CSV'**
  String get commonSourceCsv;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'صوت'**
  String get commonSourceVoice;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'بإيدك'**
  String get commonSourceManual;

  /// C · share/paste, FR-ING-A-04. Maps to DB source = 'share' (database-schema.md; Q-02 closed)
  ///
  /// In ar, this message translates to:
  /// **'رسالة اتبعتت'**
  String get commonSourceShared;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'مصروف'**
  String get commonTxnTypeExpense;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'دخل'**
  String get commonTxnTypeIncome;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'تحويل'**
  String get commonTxnTypeTransfer;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'تحويلة لنفسك'**
  String get commonTxnTypeInternal;

  /// C · from a merchant (BR-XFR-08)
  ///
  /// In ar, this message translates to:
  /// **'مرتجع'**
  String get commonTxnTypeRefund;

  /// C · from people (BR-XFR-08)
  ///
  /// In ar, this message translates to:
  /// **'فلوس راجعة'**
  String get commonTxnTypeReimbursement;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'اترفضت'**
  String get commonTxnTypeDeclined;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'ديبت'**
  String get commonAccountTypeDebit;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'كريدت'**
  String get commonAccountTypeCredit;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'حساب بنك'**
  String get commonAccountTypeAccount;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'محفظة'**
  String get commonAccountTypeWallet;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'تقسيط'**
  String get commonAccountTypeBnpl;

  /// C · default account FR-ACC-03
  ///
  /// In ar, this message translates to:
  /// **'كاش'**
  String get commonAccountTypeCash;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'أكتر من عملة'**
  String get commonAccountTypeMultiCurrency;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'رسايل البنك'**
  String get commonChannelSms;

  /// C · compact status row
  ///
  /// In ar, this message translates to:
  /// **'الرسايل'**
  String get commonChannelSmsShort;

  /// L · Android only
  ///
  /// In ar, this message translates to:
  /// **'إشعارات التطبيقات'**
  String get commonChannelNotifications;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الإشعارات'**
  String get commonChannelNotificationsShort;

  /// L · iOS only
  ///
  /// In ar, this message translates to:
  /// **'Apple Pay'**
  String get commonChannelApplePay;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'شغال'**
  String get commonChannelOnA11y;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'مقفول'**
  String get commonChannelOffA11y;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'النهارده'**
  String get commonDateToday;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'امبارح'**
  String get commonDateYesterday;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'دلوقتي'**
  String get commonDateJustNow;

  /// C · count:int, n · whole minutes, 0–59. =0 (under one minute) reads the same as common_date_justNow, so callers pass 0 rather than switching keys. 60 or more → common_date_hoursAgo
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{دلوقتي} =1{من دقيقة} =2{من دقيقتين} few{من {n} دقايق} many{من {n} دقيقة} other{من {n} دقيقة}}'**
  String commonDateMinutesAgo(int count, String n);

  /// C · count:int, n · whole hours, 1–23; 24 or more → {date}. 0 can't occur (that's minutes), so no =0 (listed in §0.4)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{من ساعة} =2{من ساعتين} few{من {n} ساعات} many{من {n} ساعة} other{من {n} ساعة}}'**
  String commonDateHoursAgo(int count, String n);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{date}، {time}'**
  String commonDateDateTime(String date, String time);

  /// L · en dash; RTL reads start first (from the right)
  ///
  /// In ar, this message translates to:
  /// **'{start} – {end}'**
  String commonDateRange(String end, String start);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الدورة دي'**
  String get commonPeriodThisCycle;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الدورة اللي فاتت'**
  String get commonPeriodLastCycle;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الشهر ده'**
  String get commonPeriodThisMonth;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'شهر معين'**
  String get commonPeriodPickMonth;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'من تاريخ لتاريخ'**
  String get commonPeriodCustom;

  /// C · count:int, n · scan depth A-11
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{آخر شهر} =2{آخر شهرين} few{آخر {n} شهور} many{آخر {n} شهر} other{آخر {n} شهر}}'**
  String commonPeriodLastMonths(int count, String n);

  /// L · count:int, n · inserted mid-sentence as {period}
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{في آخر شهر} =2{في آخر شهرين} few{في آخر {n} شهور} many{في آخر {n} شهر} other{في آخر {n} شهر}}'**
  String commonPeriodInLastMonths(int count, String n);

  /// C · n = formatted number without its sign
  ///
  /// In ar, this message translates to:
  /// **'{n}٪'**
  String commonProgressPercent(String n);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'{n} ميجا'**
  String commonFileSizeMb(String n);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'{n} كيلو'**
  String commonFileSizeKb(String n);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'أندرويد'**
  String get commonPlatformAndroid;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'آيفون'**
  String get commonPlatformIos;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اكتب مبلغ أكبر من صفر'**
  String get commonValidationAmountRequired;

  /// S · more than 12 integer digits
  ///
  /// In ar, this message translates to:
  /// **'المبلغ ده كبير أوي، راجعه'**
  String get commonValidationAmountTooLarge;

  /// S · count:int = currency exponent, n, currency
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{{currency} مفيهوش كسور} =1{{currency} بيقبل رقم واحد بعد العلامة} =2{{currency} بيقبل رقمين بس بعد العلامة} few{{currency} بيقبل {n} أرقام بس بعد العلامة} many{{currency} بيقبل {n} رقم بعد العلامة} other{{currency} بيقبل {n} رقم بعد العلامة}}'**
  String commonValidationAmountDecimals(int count, String currency, String n);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار العملة'**
  String get commonValidationCurrencyRequired;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'التاريخ ميكونش في المستقبل'**
  String get commonValidationDateFuture;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'تاريخ البداية لازم يبقى قبل النهاية'**
  String get commonValidationDateRange;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اكتب آخر أربع أرقام'**
  String get commonValidationLast4;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اكتب اسم'**
  String get commonValidationNameRequired;

  /// S · count:int = max (30), n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{الاسم ميزيدش عن حرف واحد} =2{الاسم ميزيدش عن حرفين} few{الاسم ميزيدش عن {n} حروف} many{الاسم ميزيدش عن {n} حرف} other{الاسم ميزيدش عن {n} حرف}}'**
  String commonValidationNameLength(int count, String n);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الاسم ده مستخدم قبل كده'**
  String get commonValidationNameTaken;

  /// S · count:int = 200, n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{الملاحظة ميزيدش عن حرف واحد} =2{الملاحظة ميزيدش عن حرفين} few{الملاحظة ميزيدش عن {n} حروف} many{الملاحظة ميزيدش عن {n} حرف} other{الملاحظة ميزيدش عن {n} حرف}}'**
  String commonValidationNoteLength(int count, String n);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار التصنيف'**
  String get commonValidationCategoryRequired;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار الحساب'**
  String get commonValidationAccountRequired;

  /// S · radio groups
  ///
  /// In ar, this message translates to:
  /// **'اختار واحدة'**
  String get commonValidationChoiceRequired;

  /// S · C-29, DB read failure; uses common_action_tryAgain
  ///
  /// In ar, this message translates to:
  /// **'مقدرتش أفتح ده دلوقتي. بياناتك في أمان على موبايلك.'**
  String get commonErrorLoadFailed;

  /// S · the form is kept
  ///
  /// In ar, this message translates to:
  /// **'محصلش حفظ. جرّب تاني، واللي كتبته لسه موجود.'**
  String get commonErrorSaveFailed;

  /// S · 06-voice-and-tone.md §2
  ///
  /// In ar, this message translates to:
  /// **'مش قادر أوصل للسيرفر دلوقتي. فلوسك في أمان على موبايلك، جرّب تاني كمان شوية.'**
  String get commonErrorNetwork;

  /// C · always paired with the crown icon
  ///
  /// In ar, this message translates to:
  /// **'جولد'**
  String get commonGoldBadge;

  /// B · opens S-68
  ///
  /// In ar, this message translates to:
  /// **'افتحها مع جولد'**
  String get commonGoldUnlock;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'متاحة في زغلول جولد'**
  String get commonGoldLockedA11y;

  /// A · label on every ZaghlolAvatar
  ///
  /// In ar, this message translates to:
  /// **'الكابتن زغلول'**
  String get mascotAvatarLabelA11y;

  /// A · Rive pull, pull to refresh on Home and lists
  ///
  /// In ar, this message translates to:
  /// **'بحدّث…'**
  String get mascotPullRefreshingA11y;

  /// N · Rive saved · after saving a transaction (S-13 or Quick add). Picked at random from line1…3
  ///
  /// In ar, this message translates to:
  /// **'اتسجلت ✓'**
  String get mascotSavedLine1;

  /// N · Rive saved
  ///
  /// In ar, this message translates to:
  /// **'تمام، حطيتها في الحسبة ✓'**
  String get mascotSavedLine2;

  /// N · Rive saved
  ///
  /// In ar, this message translates to:
  /// **'اتقيدت يا كبير ✓'**
  String get mascotSavedLine3;

  /// M · Rive tap · user taps Zaghlol. The next unused line rotates each tap
  ///
  /// In ar, this message translates to:
  /// **'إيه يا عم، بتزغزغني؟ 😄'**
  String get mascotTapLine1;

  /// M · Rive tap
  ///
  /// In ar, this message translates to:
  /// **'أنا هنا يا كبير، وفلوسك في عينيّا'**
  String get mascotTapLine2;

  /// M · Rive tap · currency-neutral (F-20)
  ///
  /// In ar, this message translates to:
  /// **'كل قرش بتحوشه بيطلّعلي ريشة جديدة 🪶'**
  String get mascotTapLine3;

  /// M · Rive tap
  ///
  /// In ar, this message translates to:
  /// **'الكابتن جاهز، وإنت القائد'**
  String get mascotTapLine4;

  /// M · Rive tap
  ///
  /// In ar, this message translates to:
  /// **'اللي يحوش النهارده يتفسح بكره'**
  String get mascotTapLine5;

  /// M · Rive tap · also restates the privacy promise
  ///
  /// In ar, this message translates to:
  /// **'أنا بقرا رسايل البنوك بس، الباقي مش شغلي'**
  String get mascotTapLine6;

  /// M · Rive tap
  ///
  /// In ar, this message translates to:
  /// **'حمامة ولا محاسب؟ الاتنين!'**
  String get mascotTapLine7;

  /// M · Rive tap
  ///
  /// In ar, this message translates to:
  /// **'جناحي سريع وحساباتي مظبوطة'**
  String get mascotTapLine8;

  /// C · each locale shows the other language's name, in that language's own script
  ///
  /// In ar, this message translates to:
  /// **'English'**
  String get onboardingWelcomeLanguageToggle;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'غيّر اللغة للإنجليزي'**
  String get onboardingWelcomeLanguageToggleA11y;

  /// T · M · Rive tourGuide, first launch (FR-MAS-01). Waves once; still pose with reduce motion
  ///
  /// In ar, this message translates to:
  /// **'أهلاً بيك! أنا الكابتن زغلول'**
  String get onboardingWelcomeTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'هعرفك فلوسك بتروح فين من رسايل البنك، من غير ما تكتب حاجة.'**
  String get onboardingWelcomeSubtitle;

  /// S · FR-ONB-01, with a lock icon (not an emoji)
  ///
  /// In ar, this message translates to:
  /// **'بيانات فلوسك بتفضل على موبايلك'**
  String get onboardingWelcomePointOnPhone;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مش هنطلب باسورد البنك أبداً'**
  String get onboardingWelcomePointNoPassword;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'من غير إعلانات'**
  String get onboardingWelcomePointNoAds;

  /// B · primary. Opens S-02 or S-03
  ///
  /// In ar, this message translates to:
  /// **'يلا نبدأ'**
  String get onboardingWelcomeStart;

  /// L · text button, opens S-04 (FR-ONB-12). Gender-neutral (F-15)
  ///
  /// In ar, this message translates to:
  /// **'استخدمت زغلول قبل كده'**
  String get onboardingWelcomeRestore;

  /// L · text link, opens S-71 read-only
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل الخصوصية'**
  String get onboardingWelcomePrivacyLink;

  /// C · C-26 stepper header
  ///
  /// In ar, this message translates to:
  /// **'خطوة {step} من {total}'**
  String onboardingAndroidSetupStep(String step, String total);

  /// T · M · Rive tourGuide, setup step
  ///
  /// In ar, this message translates to:
  /// **'خليني أقرا رسايل البنك'**
  String get onboardingAndroidSetupSmsTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'وهرتبلك كل مصاريفك لوحدي.'**
  String get onboardingAndroidSetupSmsSubtitle;

  /// S · what is read (FR-ING-A-02)
  ///
  /// In ar, this message translates to:
  /// **'بقرا رسايل البنوك والمحافظ وإنستاباي بس'**
  String get onboardingAndroidSetupSmsPointSenders;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'رسايلك الشخصية عمرها ما بتتقري ولا بتتحفظ'**
  String get onboardingAndroidSetupSmsPointPersonal;

  /// S · claim limited to financial data (tone gate 4, R-11, BR-SYNC-03)
  ///
  /// In ar, this message translates to:
  /// **'بيانات فلوسك بتفضل على الموبايل ده'**
  String get onboardingAndroidSetupSmsPointOnPhone;

  /// B · primary, opens the system SMS dialog
  ///
  /// In ar, this message translates to:
  /// **'اسمح بقراية الرسايل'**
  String get onboardingAndroidSetupSmsAllow;

  /// N · success
  ///
  /// In ar, this message translates to:
  /// **'الرسايل اتسمحت ✓'**
  String get onboardingAndroidSetupSmsGranted;

  /// L · Rive scanning (loops while the scan runs)
  ///
  /// In ar, this message translates to:
  /// **'بقرا رسايلك القديمة…'**
  String get onboardingAndroidSetupScanTitle;

  /// S · period = common_period_lastMonths (A-11 default 6)
  ///
  /// In ar, this message translates to:
  /// **'{period} · كمّل وأنا شغال'**
  String onboardingAndroidSetupScanDepth(String period);

  /// L · count:int, n · polite live region, announced at most every 5 s
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{لسه بدوّر…} =1{لقيت حركة واحدة} =2{لقيت حركتين} few{لقيت {n} حركات} many{لقيت {n} حركة} other{لقيت {n} حركة}}'**
  String onboardingAndroidSetupScanCount(int count, String n);

  /// L · followed by bank chips (data)
  ///
  /// In ar, this message translates to:
  /// **'البنوك اللي لقيتها:'**
  String get onboardingAndroidSetupScanBanks;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'وكمان إشعارات تطبيقات البنوك؟'**
  String get onboardingAndroidSetupNotifTitle;

  /// S · FR-ING-A-03/07
  ///
  /// In ar, this message translates to:
  /// **'في بنوك ومحافظ بتبعت إشعار في التطبيق بس من غير SMS، زي Wise وRevolut وPayoneer.'**
  String get onboardingAndroidSetupNotifBody;

  /// S · what is read (FR-ING-A-03: registry apps only)
  ///
  /// In ar, this message translates to:
  /// **'بقرا إشعارات تطبيقات البنوك والمحافظ بس، مش الواتساب ولا أي حاجة تانية.'**
  String get onboardingAndroidSetupNotifPrivacy;

  /// B · primary, opens OS notification access
  ///
  /// In ar, this message translates to:
  /// **'شغّل الإشعارات'**
  String get onboardingAndroidSetupNotifTurnOn;

  /// S · shown under the button
  ///
  /// In ar, this message translates to:
  /// **'في الشاشة الجاية، دوّر على «زغلول» وشغّله.'**
  String get onboardingAndroidSetupNotifOsHint;

  /// N · success, on return from OS
  ///
  /// In ar, this message translates to:
  /// **'الإشعارات اشتغلت ✓'**
  String get onboardingAndroidSetupNotifGranted;

  /// N · on return, still off. No blame
  ///
  /// In ar, this message translates to:
  /// **'لسه مقفولة. تقدر تشغلها بعدين من الإعدادات.'**
  String get onboardingAndroidSetupNotifStillOff;

  /// T · C-20 warning (FR-ING-A-05)
  ///
  /// In ar, this message translates to:
  /// **'قراية الرسايل مقفولة'**
  String get onboardingAndroidSetupDegradedTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'لسه تقدر تتابع مصاريفك بطرق تانية:'**
  String get onboardingAndroidSetupDegradedBody;

  /// L · row action onboarding_androidSetup_degradedNotifOn
  ///
  /// In ar, this message translates to:
  /// **'إشعارات تطبيقات البنوك'**
  String get onboardingAndroidSetupDegradedNotif;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'شغّلها'**
  String get onboardingAndroidSetupDegradedNotifOn;

  /// S · row action onboarding_androidSetup_degradedShareHow
  ///
  /// In ar, this message translates to:
  /// **'ابعت أو الزق رسالة البنك لزغلول'**
  String get onboardingAndroidSetupDegradedShare;

  /// L · text button · opens the capture_shareHow_* sheet
  ///
  /// In ar, this message translates to:
  /// **'إزاي؟'**
  String get onboardingAndroidSetupDegradedShareHow;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'سجّل الكاش بصوتك أو بإيدك'**
  String get onboardingAndroidSetupDegradedManual;

  /// B · when the OS still allows a prompt
  ///
  /// In ar, this message translates to:
  /// **'اسمح تاني'**
  String get onboardingAndroidSetupDegradedRetry;

  /// S · when the OS blocks re-prompting; with common_action_openSettings
  ///
  /// In ar, this message translates to:
  /// **'علشان تشغلها، افتح الإعدادات واسمح لزغلول بالرسايل.'**
  String get onboardingAndroidSetupDegradedSettingsHint;

  /// S · prodNoSms flavour (ADR-004, deployment.md) (FR-ING-A-05). Where it appears is open, see Q-03
  ///
  /// In ar, this message translates to:
  /// **'النسخة دي من زغلول مش بتقرا SMS، بس الإشعارات والمشاركة شغالين تمام.'**
  String get onboardingAndroidSetupPlayUnavailable;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'خطوة {step} من {total}'**
  String onboardingIosSetupStep(String step, String total);

  /// T · M · Rive tourGuide
  ///
  /// In ar, this message translates to:
  /// **'هنستخدم الاختصارات'**
  String get onboardingIosSetupShortcutTitle;

  /// S · under the title. Split out of the title for length (F-7)
  ///
  /// In ar, this message translates to:
  /// **'الآيفون مش بيسمح للتطبيقات تقرا الرسايل، فالاختصارات هي اللي هتبعتهالي.'**
  String get onboardingIosSetupShortcutWhy;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'ضغطة واحدة بتضيف:'**
  String get onboardingIosSetupShortcutLead;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'رسايل البنك'**
  String get onboardingIosSetupShortcutSmsTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'بيلقط رسايل البنوك وإنستاباي، عربي وإنجليزي'**
  String get onboardingIosSetupShortcutSmsSub;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'مدفوعات Apple Pay'**
  String get onboardingIosSetupShortcutApplePayTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'بيسجل أي دفع بالموبايل في ساعتها'**
  String get onboardingIosSetupShortcutApplePaySub;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مرة واحدة بس، وبعدها كل حاجة بتتسجل لوحدها.'**
  String get onboardingIosSetupShortcutOnce;

  /// B · primary, opens the Shortcuts import
  ///
  /// In ar, this message translates to:
  /// **'ضيف اختصار زغلول'**
  String get onboardingIosSetupShortcutAdd;

  /// L · text button, expands the steps below
  ///
  /// In ar, this message translates to:
  /// **'إزاي بيشتغل؟ (نص دقيقة)'**
  String get onboardingIosSetupHowItWorks;

  /// S · list numbers are drawn by the UI, not the copy
  ///
  /// In ar, this message translates to:
  /// **'لما توصلك رسالة من بنك، الآيفون بيشغّل الاختصار لوحده.'**
  String get onboardingIosSetupHowStep1;

  /// S · precise claim about the message, not "no server"
  ///
  /// In ar, this message translates to:
  /// **'الاختصار بيدّي نص الرسالة لزغلول على نفس الموبايل، مش بيبعته لأي حد.'**
  String get onboardingIosSetupHowStep2;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'زغلول يقرا المبلغ والتاجر ويسجلها. خلاص كده.'**
  String get onboardingIosSetupHowStep3;

  /// S · spinner, ≤ 2 s
  ///
  /// In ar, this message translates to:
  /// **'ثانية، بشوف الاختصارات اتضافت ولا لأ…'**
  String get onboardingIosSetupChecking;

  /// S · error, no joke
  ///
  /// In ar, this message translates to:
  /// **'مقدرتش أفتح تطبيق الاختصارات. نزّله من الـ App Store وجرّب تاني.'**
  String get onboardingIosSetupShortcutsMissing;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تعالى نتأكد إن كله تمام'**
  String get onboardingIosSetupCheckTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'زغلول بيبص على الاختصارات اللي اتضافت.'**
  String get onboardingIosSetupCheckSubtitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'رسايل البنوك (عربي)'**
  String get onboardingIosSetupCheckSmsAr;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'رسايل البنوك (إنجليزي)'**
  String get onboardingIosSetupCheckSmsEn;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'مدفوعات Apple Pay'**
  String get onboardingIosSetupCheckApplePay;

  /// L · count:int = total, n, done. «أوتوميشن» doesn't change in AR; every form is written out for the parity test. Can't be 0 (§0.4)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{{done} من {n} أوتوميشن} =2{{done} من {n} أوتوميشن} few{{done} من {n} أوتوميشن} many{{done} من {n} أوتوميشن} other{{done} من {n} أوتوميشن}}'**
  String onboardingIosSetupCheckCount(int count, String done, String n);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'محتاجة «Run Immediately»'**
  String get onboardingIosSetupCheckNeedsRun;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'شغال'**
  String get onboardingIosSetupCheckOkA11y;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'ناقص'**
  String get onboardingIosSetupCheckMissingA11y;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'إزاي تصلحها؟'**
  String get onboardingIosSetupFixTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'افتح Shortcuts وبعدين Automation'**
  String get onboardingIosSetupFixStep1;

  /// S · automationName is the Latin automation name, e.g. Zaghlol – Wallet
  ///
  /// In ar, this message translates to:
  /// **'اختار «{automationName}»'**
  String onboardingIosSetupFixStep2(String automationName);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'شغّل «Run Immediately»'**
  String get onboardingIosSetupFixStep3;

  /// S · no false failure (FR-ING-I-07)
  ///
  /// In ar, this message translates to:
  /// **'مش متأكدين لسه؟ هنعرف أول ما توصلك رسالة بنك.'**
  String get onboardingIosSetupCheckUnknown;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اتأكد تاني'**
  String get onboardingIosSetupCheckAgain;

  /// N · success
  ///
  /// In ar, this message translates to:
  /// **'كله تمام ✓ زغلول جاهز'**
  String get onboardingIosSetupCheckAllGood;

  /// T · M · Rive tourGuide (FR-ONB-09)
  ///
  /// In ar, this message translates to:
  /// **'يلا نسجل أول مصروف!'**
  String get onboardingIosSetupFirstTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'لحد ما توصل أول رسالة بنك، قولي صرفت إيه النهارده.'**
  String get onboardingIosSetupFirstBody;

  /// B · opens S-31
  ///
  /// In ar, this message translates to:
  /// **'قولها'**
  String get onboardingIosSetupFirstSay;

  /// L · spoken example. AR uses number words (§0.3)
  ///
  /// In ar, this message translates to:
  /// **'«دفعت خمسة وأربعين قهوة»'**
  String get onboardingIosSetupFirstSayHint;

  /// B · opens S-13
  ///
  /// In ar, this message translates to:
  /// **'اكتبها'**
  String get onboardingIosSetupFirstType;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'المبلغ والتصنيف'**
  String get onboardingIosSetupFirstTypeHint;

  /// S · opens S-61 supported banks (FR-ING-I-08)
  ///
  /// In ar, this message translates to:
  /// **'بتستخدم Wise أو Revolut أو Payoneer؟'**
  String get onboardingIosSetupFirstOnlineBanks;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'شوف إزاي تتابعهم على الآيفون'**
  String get onboardingIosSetupFirstOnlineBanksSub;

  /// L · the common_gold_badge must show on this row (FR-EXP-04/06); Free opens S-68
  ///
  /// In ar, this message translates to:
  /// **'عندك كشف حساب؟'**
  String get onboardingIosSetupFirstStatement;

  /// S · says Gold in the text too, so Free users aren't promised it (F-8)
  ///
  /// In ar, this message translates to:
  /// **'ضيف شهور فاتت مرة واحدة مع جولد'**
  String get onboardingIosSetupFirstStatementSub;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'استرجاع نسخة'**
  String get backupRestoreTitle;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'النسخة بتاعتك فين؟'**
  String get backupRestoreWhereTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'Google Drive'**
  String get backupRestoreOptionDrive;

  /// L · iOS only
  ///
  /// In ar, this message translates to:
  /// **'iCloud'**
  String get backupRestoreOptionICloud;

  /// S · button loading state during provider sign-in (F-5a)
  ///
  /// In ar, this message translates to:
  /// **'بدخل على {provider}…'**
  String backupRestoreSigningIn(String provider);

  /// S · spinner
  ///
  /// In ar, this message translates to:
  /// **'بدوّر على نسخة زغلول…'**
  String get backupRestoreSearching;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'لقيت نسخة'**
  String get backupRestoreFoundTitle;

  /// L · size = common_fileSize_mb
  ///
  /// In ar, this message translates to:
  /// **'{date} · {size}'**
  String backupRestoreFoundMeta(String date, String size);

  /// L · appVersion stays Latin, e.g. 1.0
  ///
  /// In ar, this message translates to:
  /// **'من: {platform} · إصدار {appVersion}'**
  String backupRestoreFoundFrom(String appVersion, String platform);

  /// L · Gold list, newest first
  ///
  /// In ar, this message translates to:
  /// **'النسخ اللي عندك'**
  String get backupRestoreVersionsTitle;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الأحدث'**
  String get backupRestoreVersionNewest;

  /// L · C-32, single field
  ///
  /// In ar, this message translates to:
  /// **'كلمة سر النسخة'**
  String get backupRestorePassphraseLabel;

  /// B · primary
  ///
  /// In ar, this message translates to:
  /// **'استرجع'**
  String get backupRestoreRestore;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اكتب كلمة السر'**
  String get backupRestorePassphraseRequired;

  /// S · unlimited retries
  ///
  /// In ar, this message translates to:
  /// **'كلمة السر دي مش بتفتح النسخة دي'**
  String get backupRestorePassphraseWrong;

  /// L · text button
  ///
  /// In ar, this message translates to:
  /// **'نسيت كلمة السر؟'**
  String get backupRestoreForgotLink;

  /// S · EC-27, calm and plain
  ///
  /// In ar, this message translates to:
  /// **'للأسف مش هينفع نرجّعها. النسخة مبتتفتحش غير بكلمة السر دي، ومحدش يقدر يفتحها من غيرها، ولا حتى إحنا. تقدر تبدأ من جديد.'**
  String get backupRestoreForgotBody;

  /// L · Rive counting + C-27 with common_progress_percent
  ///
  /// In ar, this message translates to:
  /// **'بسترجع بياناتك…'**
  String get backupRestoreRestoring;

  /// S · no cancel once decryption has started
  ///
  /// In ar, this message translates to:
  /// **'سيب زغلول مفتوح لحد ما يخلص'**
  String get backupRestoreKeepOpen;

  /// T · C-28
  ///
  /// In ar, this message translates to:
  /// **'مفيش نسخة زغلول على الحساب ده'**
  String get backupRestoreEmptyTitle;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'جرّب حساب تاني'**
  String get backupRestoreTryAnotherAccount;

  /// B · opens S-02 or S-03
  ///
  /// In ar, this message translates to:
  /// **'ابدأ من جديد'**
  String get backupRestoreStartFresh;

  /// S · offline / network. provider = Google Drive or iCloud
  ///
  /// In ar, this message translates to:
  /// **'مش قادر أوصل لـ {provider} دلوقتي. اتأكد من النت وجرّب تاني.'**
  String backupRestoreErrorNetwork(String provider);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الدخول على {provider} ما كملش. جرّب تاني.'**
  String backupRestoreErrorSignIn(String provider);

  /// S · EC-26
  ///
  /// In ar, this message translates to:
  /// **'النسخة دي معمولة بإصدار أحدث من زغلول. حدّث التطبيق الأول.'**
  String get backupRestoreErrorNewer;

  /// B · store link
  ///
  /// In ar, this message translates to:
  /// **'حدّث زغلول'**
  String get backupRestoreUpdate;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'النسخة دي مش بتتقري.'**
  String get backupRestoreErrorCorrupted;

  /// B · Gold only (versions)
  ///
  /// In ar, this message translates to:
  /// **'جرّب نسخة أقدم'**
  String get backupRestoreTryOlder;

  /// N · Home C-20 after restore
  ///
  /// In ar, this message translates to:
  /// **'بياناتك رجعت ✓ دلوقتي اسمح لزغلول يقرا على الموبايل ده.'**
  String get backupRestoreDoneBanner;

  /// B · opens S-02 or S-03
  ///
  /// In ar, this message translates to:
  /// **'يلا نظبطها'**
  String get backupRestoreDoneAction;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'زغلول مقفول'**
  String get securityLockTitle;

  /// B · method from the available biometric
  ///
  /// In ar, this message translates to:
  /// **'{method, select, faceId{افتح بالـ Face ID} touchId{افتح بالـ Touch ID} fingerprint{افتح ببصمتك} face{افتح ببصمة الوش} other{افتح القفل}}'**
  String securityLockUnlock(String method);

  /// L · text button (A-08)
  ///
  /// In ar, this message translates to:
  /// **'{platform, select, ios{استخدم كود الآيفون} other{استخدم قفل الموبايل}}'**
  String securityLockUsePasscode(String platform);

  /// L · OS biometric prompt title / iOS localizedReason
  ///
  /// In ar, this message translates to:
  /// **'افتح زغلول'**
  String get securityLockPromptReason;

  /// S · Android BiometricPrompt subtitle
  ///
  /// In ar, this message translates to:
  /// **'علشان محدش يشوف فلوسك غيرك'**
  String get securityLockPromptSubtitle;

  /// N · OS shows its own detail
  ///
  /// In ar, this message translates to:
  /// **'مفتحش. جرّب تاني.'**
  String get securityLockFailed;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'البصمة مش متاحة دلوقتي، افتح بقفل الموبايل.'**
  String get securityLockBiometricsGone;

  /// T · M · Rive proud, scan finished (FR-ONB-06)
  ///
  /// In ar, this message translates to:
  /// **'خلصت! 🎉'**
  String get onboardingScanResultsTitle;

  /// S · count:int, n, period = common_period_inLastMonths
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{لقيت حركة واحدة {period}} =2{لقيت حركتين {period}} few{لقيت {n} حركات {period}} many{لقيت {n} حركة {period}} other{لقيت {n} حركة {period}}}'**
  String onboardingScanResultsFound(int count, String n, String period);

  /// C · under a number
  ///
  /// In ar, this message translates to:
  /// **'اتصنفوا لوحدهم'**
  String get onboardingScanResultsStatAuto;

  /// C · tap opens S-14
  ///
  /// In ar, this message translates to:
  /// **'مستنيين رأيك'**
  String get onboardingScanResultsStatReview;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'كروت وحسابات'**
  String get onboardingScanResultsStatCards;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'دي كروتك؟'**
  String get onboardingScanResultsCardsTitle;

  /// L · count:int, n, type = common_accountType_* or onboarding_scanResults_guessCredit
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{{type} · حركة واحدة} =2{{type} · حركتين} few{{type} · {n} حركات} many{{type} · {n} حركة} other{{type} · {n} حركة}}'**
  String onboardingScanResultsCardSubtitle(int count, String n, String type);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'شكله كريدت كارد'**
  String get onboardingScanResultsGuessCredit;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'كريدت؟'**
  String get onboardingScanResultsCreditBadge;

  /// M · Rive detective · auto-created account that looks like a credit card (FR-ACC-05)
  ///
  /// In ar, this message translates to:
  /// **'{card} شكله كريدت كارد. قولي الليميت وميعاد السداد عشان أفكرك قبلها.'**
  String onboardingScanResultsCreditPrompt(String card);

  /// B · opens S-43 credit fields
  ///
  /// In ar, this message translates to:
  /// **'أيوه، ظبطه'**
  String get onboardingScanResultsCreditYes;

  /// S · leads to S-62
  ///
  /// In ar, this message translates to:
  /// **'كارت مش بتاعك أو كارت شغل؟ دوس عليه واقفل قرايته.'**
  String get onboardingScanResultsNotMineHint;

  /// B · primary, opens S-10
  ///
  /// In ar, this message translates to:
  /// **'ورّيني فلوسي'**
  String get onboardingScanResultsShowMe;

  /// N · count:int, n, card · FR-CAP-07 re-scan
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{ملقيتش حركات جديدة لـ {card}} =1{ضفت حركة واحدة لـ {card}} =2{ضفت حركتين لـ {card}} few{ضفت {n} حركات لـ {card}} many{ضفت {n} حركة لـ {card}} other{ضفت {n} حركة لـ {card}}}'**
  String onboardingScanResultsRescanToast(String card, int count, String n);

  /// T · part: morning 05:00–11:59, afternoon 12:00–16:59, evening 17:00–04:59 (local time). See Q-05
  ///
  /// In ar, this message translates to:
  /// **'{part, select, morning{صباح الفل يا كبير ☀️} afternoon{مساء الفل يا كبير ☀️} evening{مساء الفل يا كبير 🌙} other{أهلاً يا كبير 👋}}'**
  String homeGreetingByTime(String part);

  /// T · first Home visit after onboarding
  ///
  /// In ar, this message translates to:
  /// **'أهلاً يا كبير 👋'**
  String get homeGreetingFirstVisit;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'مسموحلك تصرف النهارده'**
  String get homeHeroSafeToSpend;

  /// C · suffix after the display amount
  ///
  /// In ar, this message translates to:
  /// **'في اليوم'**
  String get homeHeroPerDay;

  /// L · count:int, n · followed by  ·  and common_date_range
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{القبض النهارده} =1{فاضل يوم على القبض} =2{فاضل يومين على القبض} few{فاضل {n} أيام على القبض} many{فاضل {n} يوم على القبض} other{فاضل {n} يوم على القبض}}'**
  String homeHeroDaysToPayday(int count, String n);

  /// S · A-43, replaces the payday line when no payday is set
  ///
  /// In ar, this message translates to:
  /// **'لحد ما تقولي ميعاد قبضك'**
  String get homeHeroCalendarMonth;

  /// L · no payday and no budget (first visit, mockup 25)
  ///
  /// In ar, this message translates to:
  /// **'صرفت الشهر ده'**
  String get homeHeroSpentThisMonth;

  /// L · payday set, no budget (EC-24)
  ///
  /// In ar, this message translates to:
  /// **'صرفت الدورة دي'**
  String get homeHeroSpentThisCycle;

  /// S · replaces safe-to-spend, never shows zeros
  ///
  /// In ar, this message translates to:
  /// **'حط ميزانية عشان تعرف تصرف كام في اليوم'**
  String get homeHeroSetBudgetHint;

  /// B · opens S-23
  ///
  /// In ar, this message translates to:
  /// **'حط ميزانية'**
  String get homeHeroSetBudget;

  /// S · safe-to-spend = 0 with budget > 0 (BR-BUD-03 clamps it with max(0, …), so it's never negative). The hero still shows the amount 0, with this as its caption. Calm, no joke. See Q-06
  ///
  /// In ar, this message translates to:
  /// **'ميزانية الدورة دي خلصت، حاسب على الباقي'**
  String get homeHeroBudgetUsedUp;

  /// C · C-10
  ///
  /// In ar, this message translates to:
  /// **'دخلك'**
  String get homeHeroKpiIncome;

  /// C · tap opens S-11 filtered
  ///
  /// In ar, this message translates to:
  /// **'صرفت'**
  String get homeHeroKpiSpent;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'فاضلك'**
  String get homeHeroKpiLeft;

  /// L · last pager page, only when the ≈ view is on (FR-CUR-04)
  ///
  /// In ar, this message translates to:
  /// **'كله تقريباً بالـ {currency}'**
  String homeHeroApproxTitle(String currency);

  /// A · payday = home_hero_daysToPayday text
  ///
  /// In ar, this message translates to:
  /// **'مسموحلك تصرف {amount} النهارده. {payday}. دخلك {income}، صرفت {spent}، فاضلك {left}.'**
  String homeHeroSummaryA11y(
    String amount,
    String income,
    String left,
    String payday,
    String spent,
  );

  /// M · Rive shocked · BR-MAS-01a: category ≥ 85% before day 20
  ///
  /// In ar, this message translates to:
  /// **'حاسب يا كبير! {category} وصل {percent} من ميزانيته ولسه بدري في الدورة.'**
  String homeMascotShockedCategory(String category, String percent);

  /// M · Rive shocked · same trigger, alternate line
  ///
  /// In ar, this message translates to:
  /// **'{category} قرّب يخلص يا كبير، {percent} راحوا ولسه بدري. نهدّي شوية؟'**
  String homeMascotShockedCategoryAlt(String category, String percent);

  /// M · Rive shocked · BR-MAS-01b: more than 30% above the 3-cycle average
  ///
  /// In ar, this message translates to:
  /// **'الأكل بره والدليفري زايدين {percent} عن العادي بتاعك. المطبخ وحشك؟ 🍳'**
  String homeMascotShockedDining(String percent);

  /// M · Rive detective · BR-MAS-03 duplicate POS (A-34). Money alert, so no emoji
  ///
  /// In ar, this message translates to:
  /// **'اتخصم منك {amount} مرتين من {merchant} في دقايق. بص عليها كده.'**
  String homeMascotDetectiveDuplicate(String amount, String merchant);

  /// B · opens S-12
  ///
  /// In ar, this message translates to:
  /// **'بص عليها'**
  String get homeMascotDetectiveDuplicateAction;

  /// M · Rive detective · BR-MAS-03 subscription detected
  ///
  /// In ar, this message translates to:
  /// **'شكلها اشتراك شهري: {merchant} بـ {amount}. أتابعهولك؟'**
  String homeMascotDetectiveSubscription(String amount, String merchant);

  /// B · confirms the recurring item (S-24)
  ///
  /// In ar, this message translates to:
  /// **'تابعه'**
  String get homeMascotDetectiveSubscriptionTrack;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'مش اشتراك'**
  String get homeMascotDetectiveSubscriptionNot;

  /// M · Rive detective · BR-MAS-03 / BR-XFR-01 self-transfer paired
  ///
  /// In ar, this message translates to:
  /// **'{amount} راحوا من {fromCard} لـ {toCard}. دي تحويلة لنفسك، فمش هحسبها مصروف 👌'**
  String homeMascotDetectiveSelfTransfer(
    String amount,
    String fromCard,
    String toCard,
  );

  /// M · Rive proud · BR-MAS-02: under the ideal burn line, ≥ 7 days into the cycle
  ///
  /// In ar, this message translates to:
  /// **'عاش يا وحش! صارف أقل من خطتك لحد دلوقتي 👏'**
  String get homeMascotProudOnTrack;

  /// M · Rive proud · BR-MAS-02, only when the computed delta is > 0
  ///
  /// In ar, this message translates to:
  /// **'عاش يا وحش! وفرت {amount} زيادة عن الدورة اللي فاتت 👏'**
  String homeMascotProudSavedMore(String amount);

  /// M · Rive proud · BR-MAS-02 goal met
  ///
  /// In ar, this message translates to:
  /// **'هدف الدورة اتحقق! 🎯 إنت قدها'**
  String get homeMascotProudGoal;

  /// M · Rive payday · salary detected (D-35), once per payday. domain-algorithms.md §7 treats payday as motion-only, and the C-14 priority list has no payday slot. Proposed slot: above proud, below detective. See Q-18
  ///
  /// In ar, this message translates to:
  /// **'المرتب نزل! {amount} 🎉 يلا نخطط له من أوله'**
  String homeMascotPayday(String amount);

  /// A · × on C-14
  ///
  /// In ar, this message translates to:
  /// **'اقفل الرسالة'**
  String get homeMascotDismissA11y;

  /// M · Rive detective · salary-like credit detected
  ///
  /// In ar, this message translates to:
  /// **'لقيت مرتب {amount} بينزل يوم {day} كل شهر. ده ميعاد قبضك؟'**
  String homePromptPayday(String amount, String day);

  /// B · only when the detected day is 1–28 (BR-BUD-01). The second button is common_action_no
  ///
  /// In ar, this message translates to:
  /// **'أيوه، يوم {day}'**
  String homePromptPaydayYes(String day);

  /// M · Rive detective · D-68: salary detected on day 29, 30 or 31 → suggest payday = 1 (calendar month). The salary counts in the month it arrives; no copy needed for that
  ///
  /// In ar, this message translates to:
  /// **'لقيت مرتب {amount} بينزل آخر الشهر. نحسب الدورة من أول الشهر لآخره؟'**
  String homePromptPaydayMonthStart(String amount);

  /// B · D-68; the second button is common_action_no
  ///
  /// In ar, this message translates to:
  /// **'أيوه، من أول الشهر'**
  String get homePromptPaydayMonthStartYes;

  /// M · Rive tourGuide · first full cycle completed
  ///
  /// In ar, this message translates to:
  /// **'خلصت أول دورة معايا! تحب نحط ميزانية للدورة الجاية؟'**
  String get homePromptBudget;

  /// B · opens S-23
  ///
  /// In ar, this message translates to:
  /// **'يلا'**
  String get homePromptBudgetYes;

  /// M · Rive tourGuide · A-65, 7 days of data
  ///
  /// In ar, this message translates to:
  /// **'بقالك أسبوع بتسجل معايا. اعمل نسخة احتياطية ببلاش عشان بياناتك تفضل في أمان لو حصل حاجة للموبايل.'**
  String get homePromptBackup;

  /// B · opens S-66
  ///
  /// In ar, this message translates to:
  /// **'اعمل نسخة'**
  String get homePromptBackupYes;

  /// S · card title, may wrap · FR-ONB-04, a one-tap switch, offered only once transactions are visible
  ///
  /// In ar, this message translates to:
  /// **'{method, select, faceId{اقفل زغلول بالـ Face ID؟} touchId{اقفل زغلول بالـ Touch ID؟} fingerprint{اقفل زغلول ببصمتك؟} face{اقفل زغلول ببصمة الوش؟} other{اقفل زغلول بقفل الموبايل؟}}'**
  String homePromptAppLockTitle(String method);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'محدش يشوف فلوسك غيرك'**
  String get homePromptAppLockSub;

  /// N · success
  ///
  /// In ar, this message translates to:
  /// **'القفل اشتغل ✓'**
  String get homePromptAppLockOn;

  /// L · card at the top, FR-ONB-11
  ///
  /// In ar, this message translates to:
  /// **'كمّل الإعداد'**
  String get homePromptFinishSetup;

  /// C · count:int, n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{فاضل خطوة واحدة} =2{فاضل خطوتين} few{فاضل {n} خطوات} many{فاضل {n} خطوة} other{فاضل {n} خطوة}}'**
  String homePromptFinishSetupSteps(int count, String n);

  /// N · count:int, n · only when count > 0; opens S-14
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{حركة واحدة مستنية رأيك 👀} =2{حركتين مستنيين رأيك 👀} few{{n} حركات مستنية رأيك 👀} many{{n} حركة مستنية رأيك 👀} other{{n} حركة مستنية رأيك 👀}}'**
  String homeBannerReview(int count, String n);

  /// N · count:int, n · C-20 info with C-27 progress; the feed fills live
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{بقرا رسايلك…} =1{بقرا رسايلك… لقيت حركة واحدة لحد دلوقتي} =2{بقرا رسايلك… لقيت حركتين لحد دلوقتي} few{بقرا رسايلك… لقيت {n} حركات لحد دلوقتي} many{بقرا رسايلك… لقيت {n} حركة لحد دلوقتي} other{بقرا رسايلك… لقيت {n} حركة لحد دلوقتي}}'**
  String homeBannerScanning(int count, String n);

  /// N · C-20 error + common_action_tryAgain
  ///
  /// In ar, this message translates to:
  /// **'مقدرتش أقرا رسايلك'**
  String get homeBannerScanFailed;

  /// N · Android "capture limited" (EC-13) + common_action_fix (opens S-61)
  ///
  /// In ar, this message translates to:
  /// **'قراية رسايل البنك مقفولة، فممكن حركات تفوتني.'**
  String get homeBannerSmsOff;

  /// N · Android, notification access revoked + common_action_fix
  ///
  /// In ar, this message translates to:
  /// **'إشعارات تطبيقات البنوك اتقفلت، فممكن حركات تفوتني.'**
  String get homeBannerNotifOff;

  /// N · iOS checker failing + common_action_fix (opens S-03 step 2)
  ///
  /// In ar, this message translates to:
  /// **'الاختصارات محتاجة تتظبط عشان ميفوتنيش حاجة.'**
  String get homeBannerShortcutsBroken;

  /// N · count:int, n · FR-ING-I-07 (7 days while active)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{مفيش رسايل بنك اتسجلت من امبارح. الاختصارات لسه شغالة؟} =2{مفيش رسايل بنك اتسجلت من يومين. الاختصارات لسه شغالة؟} few{مفيش رسايل بنك اتسجلت من {n} أيام. الاختصارات لسه شغالة؟} many{مفيش رسايل بنك اتسجلت من {n} يوم. الاختصارات لسه شغالة؟} other{مفيش رسايل بنك اتسجلت من {n} يوم. الاختصارات لسه شغالة؟}}'**
  String homeBannerShortcutsQuiet(int count, String n);

  /// B · opens S-03 step 2
  ///
  /// In ar, this message translates to:
  /// **'اتأكد'**
  String get homeBannerShortcutsCheck;

  /// N · FR-SEC-07, shown once + common_action_learnMore (opens S-71). Warning only, never blocks
  ///
  /// In ar, this message translates to:
  /// **'{platform, select, ios{الآيفون ده متعمله جيلبريك، فحماية بياناتك أضعف.} other{الموبايل ده متعمله روت، فحماية بياناتك أضعف.}}'**
  String homeBannerRooted(String platform);

  /// L · glossary; + common_action_seeAll
  ///
  /// In ar, this message translates to:
  /// **'اللي اتصرف قريب'**
  String get homeFeedTitle;

  /// T · C-28, Rive sleep
  ///
  /// In ar, this message translates to:
  /// **'لسه مفيش حركات'**
  String get homeEmptyTitle;

  /// S · Android with SMS on: no button
  ///
  /// In ar, this message translates to:
  /// **'أول ما توصلك رسالة بنك هتظهر هنا لوحدها.'**
  String get homeEmptyBodyWaiting;

  /// S · every other case
  ///
  /// In ar, this message translates to:
  /// **'سجّل أول مصروف وأنا أكمّل معاك.'**
  String get homeEmptyBodyAdd;

  /// B · opens S-30
  ///
  /// In ar, this message translates to:
  /// **'ضيف أول مصروف'**
  String get homeEmptyAdd;

  /// S · filter-caused empty + common_action_clearFilter. cards = a card label or common_cardFilter_count
  ///
  /// In ar, this message translates to:
  /// **'مفيش حركات لـ {cards} في الدورة دي'**
  String homeEmptyFilter(String cards);

  /// L · source = common_source_*; separators are not mirrored
  ///
  /// In ar, this message translates to:
  /// **'{card} · {time} · {source}'**
  String transactionsRowSubtitle(String card, String source, String time);

  /// L · ⇄ icon, muted
  ///
  /// In ar, this message translates to:
  /// **'تحويلة لنفسك'**
  String get transactionsRowInternalTitle;

  /// L · FR-HOME-03; colour is never the only cue
  ///
  /// In ar, this message translates to:
  /// **'{fromCard} لـ {toCard} · مش محسوبة في المصاريف'**
  String transactionsRowInternalSubtitle(String fromCard, String toCard);

  /// L · BR-TXN-03, strikethrough amount
  ///
  /// In ar, this message translates to:
  /// **'اترفضت · مش محسوبة'**
  String get transactionsRowDeclined;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'دفعت {paid} · رجعلك {back}'**
  String transactionsRowReimbursed(String back, String paid);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'مرتجع من {merchant}'**
  String transactionsRowRefund(String merchant);

  /// A · dot indicator
  ///
  /// In ar, this message translates to:
  /// **'مستنية رأيك'**
  String get transactionsRowNeedsReviewA11y;

  /// A · whole-row label
  ///
  /// In ar, this message translates to:
  /// **'{merchant}، {amount}، {category}، {card}، {time}'**
  String transactionsRowLabelA11y(
    String amount,
    String card,
    String category,
    String merchant,
    String time,
  );

  /// C · swipe from the start edge; also an a11y action
  ///
  /// In ar, this message translates to:
  /// **'غيّر التصنيف'**
  String get transactionsRowSwipeCategory;

  /// L · swipe from the end edge; also an a11y action
  ///
  /// In ar, this message translates to:
  /// **'تقسيم / فلوس راجعة'**
  String get transactionsRowSwipeSplit;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'الحركات'**
  String get transactionsListTitle;

  /// L · next to a search icon, whose label is common_action_searchA11y · FTS, debounced 250 ms; Arabic-Indic digits accepted (CLAUDE.md §2.5)
  ///
  /// In ar, this message translates to:
  /// **'تاجر، ملاحظة أو مبلغ…'**
  String get transactionsListSearchHint;

  /// C · chip; shows the selected common_period_* once set
  ///
  /// In ar, this message translates to:
  /// **'المدة'**
  String get transactionsListFilterPeriod;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'التصنيف'**
  String get transactionsListFilterCategory;

  /// C · options = common_txnType_*
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get transactionsListFilterType;

  /// C · options = common_source_*
  ///
  /// In ar, this message translates to:
  /// **'جت منين'**
  String get transactionsListFilterSource;

  /// C · chip with a multi-selection count
  ///
  /// In ar, this message translates to:
  /// **'{label} · {n}'**
  String transactionsListFilterCount(String label, String n);

  /// T · custom range sheet
  ///
  /// In ar, this message translates to:
  /// **'اختار المدة'**
  String get transactionsListRangeTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'من'**
  String get transactionsListRangeFrom;

  /// L · end ≤ today
  ///
  /// In ar, this message translates to:
  /// **'لحد'**
  String get transactionsListRangeTo;

  /// A · day header, one per currency
  ///
  /// In ar, this message translates to:
  /// **'إجمالي اليوم {amount}'**
  String transactionsListDayTotalA11y(String amount);

  /// T · C-28, Rive sleep
  ///
  /// In ar, this message translates to:
  /// **'حركاتك هتظهر هنا'**
  String get transactionsListEmptyTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'من رسايل البنك، أو سجّلها بإيدك.'**
  String get transactionsListEmptyBody;

  /// B · opens S-13
  ///
  /// In ar, this message translates to:
  /// **'ضيف مصروف'**
  String get transactionsListEmptyAdd;

  /// S · query is isolated
  ///
  /// In ar, this message translates to:
  /// **'مفيش حاجة شبه «{query}»'**
  String transactionsListNoResults(String query);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مفيش حركات بالفلاتر دي'**
  String get transactionsListNoResultsFilters;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'امسح البحث والفلاتر'**
  String get transactionsListClearAll;

  /// T · selection mode; n = formatted count
  ///
  /// In ar, this message translates to:
  /// **'اخترت {n}'**
  String transactionsListSelectedTitle(String n);

  /// C · bottom action bar
  ///
  /// In ar, this message translates to:
  /// **'التصنيف'**
  String get transactionsListBulkCategory;

  /// C · the bar's other actions are common_action_delete and common_action_cancel (§0.10 reuse rule)
  ///
  /// In ar, this message translates to:
  /// **'الكارت'**
  String get transactionsListBulkAccount;

  /// S · switch after a category change; creates rules (FR-CAT)
  ///
  /// In ar, this message translates to:
  /// **'استخدم ده دايماً للتجار دول'**
  String get transactionsListBulkRule;

  /// N · count:int, n + common_action_undo (restores all)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{اتغيرت حركة واحدة} =2{اتغيرت حركتين} few{اتغيرت {n} حركات} many{اتغيرت {n} حركة} other{اتغيرت {n} حركة}}'**
  String transactionsListBulkChanged(int count, String n);

  /// T · count:int, n · C-18 destructive
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{تمسح حركة واحدة؟} =2{تمسح الحركتين؟} few{تمسح {n} حركات؟} many{تمسح {n} حركة؟} other{تمسح {n} حركة؟}}'**
  String transactionsListBulkDeleteTitle(int count, String n);

  /// S · delete asks first and has no Undo; other bulk changes have Undo (FR-TXN-06; Q-08 closed)
  ///
  /// In ar, this message translates to:
  /// **'مش هتقدر ترجعها بعد كده.'**
  String get transactionsListBulkDeleteBody;

  /// N · count:int, n · no Undo
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{اتمسحت حركة واحدة} =2{اتمسحت حركتين} few{اتمسحت {n} حركات} many{اتمسحت {n} حركة} other{اتمسحت {n} حركة}}'**
  String transactionsListBulkDeleted(int count, String n);

  /// A · check circle
  ///
  /// In ar, this message translates to:
  /// **'اختار {merchant}'**
  String transactionsListSelectRowA11y(String merchant);

  /// L · foreign only; symbols allowed here (§0.5)
  ///
  /// In ar, this message translates to:
  /// **'الأصلي: {amount}'**
  String transactionsDetailOriginal(String amount);

  /// L · opens S-41
  ///
  /// In ar, this message translates to:
  /// **'الكارت'**
  String get transactionsDetailFieldCard;

  /// L · value = common_date_dateTime
  ///
  /// In ar, this message translates to:
  /// **'إمتى'**
  String get transactionsDetailFieldDate;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'فاضل في الحساب'**
  String get transactionsDetailFieldBalance;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'جت منين'**
  String get transactionsDetailFieldSource;

  /// L · empty shows "—" (not localized)
  ///
  /// In ar, this message translates to:
  /// **'رقم العملية'**
  String get transactionsDetailFieldReference;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'ملاحظة'**
  String get transactionsDetailFieldNote;

  /// L · text button
  ///
  /// In ar, this message translates to:
  /// **'ضيف ملاحظة'**
  String get transactionsDetailNoteAdd;

  /// L · ≤ 200 (common_validation_noteLength)
  ///
  /// In ar, this message translates to:
  /// **'اكتب ملاحظة…'**
  String get transactionsDetailNoteHint;

  /// L · expenses, opens S-15 Mode A
  ///
  /// In ar, this message translates to:
  /// **'تقسيم / فلوس راجعة'**
  String get transactionsDetailSplit;

  /// L · opens S-16
  ///
  /// In ar, this message translates to:
  /// **'دي تحويلة لنفسي'**
  String get transactionsDetailLinkTransfer;

  /// L · incoming only, opens S-15 Mode B (FR-XFR-06)
  ///
  /// In ar, this message translates to:
  /// **'دي فلوس راجعة عن…'**
  String get transactionsDetailMoneyBackFor;

  /// L · internal; + common_action_unlink
  ///
  /// In ar, this message translates to:
  /// **'مربوطة مع {amount} في {card}'**
  String transactionsDetailLinkedWith(String amount, String card);

  /// N
  ///
  /// In ar, this message translates to:
  /// **'تحويلة لنفسك، مش محسوبة لا مصروف ولا دخل'**
  String get transactionsDetailInternalBanner;

  /// N · BR-TXN-03
  ///
  /// In ar, this message translates to:
  /// **'العملية اترفضت، مش محسوبة'**
  String get transactionsDetailDeclinedBanner;

  /// S · FR-XFR-03
  ///
  /// In ar, this message translates to:
  /// **'مرتجع من {merchant} عن مشتريات {date} · الصافي {net}'**
  String transactionsDetailRefundCard(String date, String merchant, String net);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'شوف الأصلية'**
  String get transactionsDetailRefundView;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'مش مرتبطة'**
  String get transactionsDetailRefundNotRelated;

  /// S · FR-XFR-08, never auto-applied; + yes/no
  ///
  /// In ar, this message translates to:
  /// **'دي من فاتورة {merchant}؟'**
  String transactionsDetailReimbSuggest(String merchant);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'شكلها مكررة مع حركة {date} بنفس المبلغ'**
  String transactionsDetailDuplicate(String date);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'سيب الاتنين'**
  String get transactionsDetailDuplicateKeep;

  /// B · destructive
  ///
  /// In ar, this message translates to:
  /// **'امسح دي'**
  String get transactionsDetailDuplicateDelete;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'دفعت {paid} · رجعلك {back} · نصيبك {share}'**
  String transactionsDetailReimbSummary(String back, String paid, String share);

  /// L · collapsible (spec "SMS inspector")
  ///
  /// In ar, this message translates to:
  /// **'إزاي زغلول قرا الرسالة'**
  String get transactionsDetailHowTitle;

  /// A · raw text is shown on screen only, never logged (CLAUDE.md §2.6)
  ///
  /// In ar, this message translates to:
  /// **'نص الرسالة الأصلي'**
  String get transactionsDetailHowRawA11y;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'المبلغ {amount}'**
  String transactionsDetailHowAmount(String amount);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'التاجر {merchant}'**
  String transactionsDetailHowMerchant(String merchant);

  /// C · FR-PAR-06
  ///
  /// In ar, this message translates to:
  /// **'ثقة {percent}'**
  String transactionsDetailHowConfidence(String percent);

  /// C · Latin ID, e.g. nbe.card_purchase.ar.v2
  ///
  /// In ar, this message translates to:
  /// **'القالب {templateId}'**
  String transactionsDetailHowTemplate(String templateId);

  /// S · manual, voice, CSV
  ///
  /// In ar, this message translates to:
  /// **'مفيش رسالة للحركة دي.'**
  String get transactionsDetailHowNone;

  /// N + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'اتغير التصنيف'**
  String get transactionsDetailCategoryChanged;

  /// T · C-18 destructive
  ///
  /// In ar, this message translates to:
  /// **'تمسح الحركة دي؟'**
  String get transactionsDetailDeleteTitle;

  /// S · auto-captured; re-scan is Android only. Uses the standard ios/other select (§0.4)
  ///
  /// In ar, this message translates to:
  /// **'{platform, select, ios{مش هتقدر ترجعها بعد كده.} other{جت من رسالة، ومش هترجع غير لو دوّرت في الرسايل من جديد.}}'**
  String transactionsDetailDeleteBodyAuto(String platform);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مش هتقدر ترجعها بعد كده.'**
  String get transactionsDetailDeleteBodyManual;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'اتمسحت'**
  String get transactionsDetailDeleted;

  /// N · deleted elsewhere; goes back
  ///
  /// In ar, this message translates to:
  /// **'الحركة دي مبقتش موجودة'**
  String get transactionsDetailGone;

  /// T · FR-CAT-05 sheet, owned by the categorization module (F-19)
  ///
  /// In ar, this message translates to:
  /// **'أستخدم {category} دايماً لـ {merchant}؟'**
  String categorizationRuleTitle(String category, String merchant);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'دايماً'**
  String get categorizationRuleAlways;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'المرة دي بس'**
  String get categorizationRuleOnce;

  /// S · count:int, n · checkbox (A-13), hidden when count = 0 (§0.4)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{وكمان غيّر الحركة القديمة} =2{وكمان غيّر الحركتين القدام} few{وكمان غيّر الـ {n} حركات القديمة} many{وكمان غيّر الـ {n} حركة القديمة} other{وكمان غيّر الـ {n} حركة القديمة}}'**
  String categorizationRuleApplyPast(int count, String n);

  /// N + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'تمام، هفتكر ده ✓'**
  String get categorizationRuleSaved;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'{type, select, income{دخل جديد} transfer{تحويل جديد} other{مصروف جديد}}'**
  String transactionsEditTitleAdd(String type);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'عدّل الحركة'**
  String get transactionsEditTitleEdit;

  /// A · segments use common_txnType_expense/income/transfer
  ///
  /// In ar, this message translates to:
  /// **'نوع الحركة'**
  String get transactionsEditTypeA11y;

  /// A · C-22; numeric pad; Arabic-Indic and Western input accepted
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get transactionsEditAmountA11y;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'العملة'**
  String get transactionsEditCurrency;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'دوّر على عملة'**
  String get transactionsEditCurrencySearch;

  /// L · section
  ///
  /// In ar, this message translates to:
  /// **'الأكتر استخدام'**
  String get transactionsEditCurrencyFeatured;

  /// L · section
  ///
  /// In ar, this message translates to:
  /// **'كل العملات'**
  String get transactionsEditCurrencyAll;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'التصنيف'**
  String get transactionsEditCategory;

  /// C · empty picker
  ///
  /// In ar, this message translates to:
  /// **'اختار'**
  String get transactionsEditChoose;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'التاجر أو الشخص'**
  String get transactionsEditMerchant;

  /// L · default common_accountType_cash (FR-CARD-05)
  ///
  /// In ar, this message translates to:
  /// **'الحساب'**
  String get transactionsEditAccount;

  /// L · transfer
  ///
  /// In ar, this message translates to:
  /// **'من حساب'**
  String get transactionsEditFrom;

  /// L · transfer
  ///
  /// In ar, this message translates to:
  /// **'لحساب'**
  String get transactionsEditTo;

  /// L · multi-currency account
  ///
  /// In ar, this message translates to:
  /// **'من أنهي رصيد؟'**
  String get transactionsEditWhichBalance;

  /// L · default common_date_today
  ///
  /// In ar, this message translates to:
  /// **'إمتى'**
  String get transactionsEditDate;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'ملاحظة'**
  String get transactionsEditNote;

  /// S · validation, transfer from ≠ to
  ///
  /// In ar, this message translates to:
  /// **'اختار حسابين مختلفين'**
  String get transactionsEditSameAccount;

  /// S · FR-ING-A-04 confirm-before-save
  ///
  /// In ar, this message translates to:
  /// **'ده اللي فهمته من الرسالة اللي بعتها. راجعه واحفظ.'**
  String get transactionsEditFromShared;

  /// L · prefilled from S-14 "Enter details"
  ///
  /// In ar, this message translates to:
  /// **'نص الرسالة'**
  String get transactionsEditRawTitle;

  /// C · n = formatted count
  ///
  /// In ar, this message translates to:
  /// **'الكل {n}'**
  String ingestionReviewFilterAll(String n);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'تصنيف'**
  String get ingestionReviewFilterCategory;

  /// C · unread or unrecognized
  ///
  /// In ar, this message translates to:
  /// **'رسايل جديدة'**
  String get ingestionReviewFilterMessages;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'تحويلات'**
  String get ingestionReviewFilterTransfers;

  /// L · counterparty may be an IPA handle (LTR, isolated)
  ///
  /// In ar, this message translates to:
  /// **'{amount} لـ {counterparty}'**
  String ingestionReviewCatOut(String amount, String counterparty);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{amount} من {counterparty}'**
  String ingestionReviewCatIn(String amount, String counterparty);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{amount} عند {merchant}'**
  String ingestionReviewCatAt(String amount, String merchant);

  /// L · followed by category chips (catalog names) and common_action_more
  ///
  /// In ar, this message translates to:
  /// **'كانت إيه دي؟'**
  String get ingestionReviewCatQuestion;

  /// L · checkbox
  ///
  /// In ar, this message translates to:
  /// **'افتكر ده لأي تحويلة لـ {counterparty}'**
  String ingestionReviewRememberCounterparty(String counterparty);

  /// L · checkbox
  ///
  /// In ar, this message translates to:
  /// **'افتكر ده لـ {merchant} على طول'**
  String ingestionReviewRememberMerchant(String merchant);

  /// N + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'اتحطت في {category}'**
  String ingestionReviewCategorized(String category);

  /// C · badge
  ///
  /// In ar, this message translates to:
  /// **'بنك جديد'**
  String get ingestionReviewNewBank;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'من {sender}'**
  String ingestionReviewGenFrom(String sender);

  /// S · FR-PAR-13
  ///
  /// In ar, this message translates to:
  /// **'توقعنا: {amount} عند {merchant}'**
  String ingestionReviewGenGuessOut(String amount, String merchant);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'توقعنا: {amount}'**
  String ingestionReviewGenGuessNoMerchant(String amount);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'توقعنا: {amount} دخلوا'**
  String ingestionReviewGenGuessIn(String amount);

  /// S · FR-PAR-06. The card's buttons are common_action_confirm, common_action_edit (opens S-13 prefilled) and common_action_dismiss
  ///
  /// In ar, this message translates to:
  /// **'مش متأكد أوي، بص عليها قبل ما أسجلها'**
  String get ingestionReviewGenLowConfidence;

  /// L · text button (FR-PAR-14)
  ///
  /// In ar, this message translates to:
  /// **'اطلب دعم البنك ده'**
  String get ingestionReviewRequestBank;

  /// S · FR-ING-A-06
  ///
  /// In ar, this message translates to:
  /// **'رسالة من {sender} مقدرتش أفهمها'**
  String ingestionReviewUnreadTitle(String sender);

  /// B · raw text on screen only
  ///
  /// In ar, this message translates to:
  /// **'شوف الرسالة'**
  String get ingestionReviewUnreadShow;

  /// B · opens S-13 with transactions_edit_rawTitle
  ///
  /// In ar, this message translates to:
  /// **'اكتب التفاصيل'**
  String get ingestionReviewUnreadEnter;

  /// S · BR-XFR-02 / EC-16; confirm with common_action_confirm
  ///
  /// In ar, this message translates to:
  /// **'{amount} في {card}، تبع أنهي تحويلة؟'**
  String ingestionReviewXferTitle(String amount, String card);

  /// L · radio
  ///
  /// In ar, this message translates to:
  /// **'{amount} من {card} · {time}'**
  String ingestionReviewXferOption(String amount, String card, String time);

  /// L · radio
  ///
  /// In ar, this message translates to:
  /// **'مش تحويلة مني'**
  String get ingestionReviewXferNotMine;

  /// A · swipe from the start edge; the button is always visible
  ///
  /// In ar, this message translates to:
  /// **'وافق على الاقتراح'**
  String get ingestionReviewSwipeAcceptA11y;

  /// A · swipe from the end edge, with undo
  ///
  /// In ar, this message translates to:
  /// **'سيبها'**
  String get ingestionReviewSwipeDismissA11y;

  /// N + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'اتشالت من المراجعة'**
  String get ingestionReviewDismissed;

  /// T · C-28, Rive proud
  ///
  /// In ar, this message translates to:
  /// **'كله تمام! مفيش حاجة مستنية رأيك ✨'**
  String get ingestionReviewEmptyTitle;

  /// T · A-66 sheet, after confirming a generic parse
  ///
  /// In ar, this message translates to:
  /// **'أقرا رسايل {sender} على طول؟'**
  String ingestionAlwaysSenderTitle(String sender);

  /// S · count:int, n · count = confirmations still needed (A-66: 3 in total); 0 once all are done
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{من هنا ورايح هسجل رسايله لوحدي.} =1{هتفضل توصلك هنا للمراجعة لحد ما تأكد رسالة واحدة منه، وبعد كده هسجلها لوحدي.} =2{هتفضل توصلك هنا للمراجعة لحد ما تأكد رسالتين منه، وبعد كده هسجلها لوحدي.} few{هتفضل توصلك هنا للمراجعة لحد ما تأكد {n} رسايل منه، وبعد كده هسجلها لوحدي.} many{هتفضل توصلك هنا للمراجعة لحد ما تأكد {n} رسالة منه، وبعد كده هسجلها لوحدي.} other{هتفضل توصلك هنا للمراجعة لحد ما تأكد {n} رسالة منه، وبعد كده هسجلها لوحدي.}}'**
  String ingestionAlwaysSenderBody(int count, String n);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'أيوه، على طول'**
  String get ingestionAlwaysSenderYes;

  /// T · shared by S-14 and S-61
  ///
  /// In ar, this message translates to:
  /// **'اطلب دعم بنكك'**
  String get ingestionRequestBankTitle;

  /// L · prefilled with the sender in S-14
  ///
  /// In ar, this message translates to:
  /// **'اسم البنك'**
  String get ingestionRequestBankName;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'البلد'**
  String get ingestionRequestBankCountry;

  /// L · options common_source_sms / common_source_notification
  ///
  /// In ar, this message translates to:
  /// **'تنبيهاته بتوصل إزاي؟'**
  String get ingestionRequestBankChannel;

  /// S · FR-PAR-14 / BR-SYNC-03 (SRS adds the channel, see Q-09). Sent with common_action_send
  ///
  /// In ar, this message translates to:
  /// **'هنبعت اسم البنك وبلده ونوع التنبيه بس. عمرنا ما هنبعت الرسالة نفسها.'**
  String get ingestionRequestBankPrivacy;

  /// N · no promise of a date
  ///
  /// In ar, this message translates to:
  /// **'وصل طلبك ✓ شكراً!'**
  String get ingestionRequestBankSent;

  /// S · network or offline; draft kept
  ///
  /// In ar, this message translates to:
  /// **'مقدرتش أبعته دلوقتي. حفظته، وتقدر تبعته تاني بعدين.'**
  String get ingestionRequestBankFailed;

  /// S · min = 2, max = 60, both formatted Strings
  ///
  /// In ar, this message translates to:
  /// **'اسم البنك لازم يكون من {min} لـ {max} حرف'**
  String ingestionRequestBankNameLength(String max, String min);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار البلد'**
  String get ingestionRequestBankCountryRequired;

  /// T · glossary
  ///
  /// In ar, this message translates to:
  /// **'تقسيم العزومة'**
  String get transfersSplitTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{merchant} · {amount}'**
  String transfersSplitHeader(String amount, String merchant);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الناس'**
  String get transfersSplitPeople;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'ضيف حد'**
  String get transfersSplitAddPerson;

  /// L · 1–30 characters
  ///
  /// In ar, this message translates to:
  /// **'الاسم'**
  String get transfersSplitPersonHint;

  /// A · apostrophe right after a brace: see §0.10 ARB note
  ///
  /// In ar, this message translates to:
  /// **'نصيب {name}'**
  String transfersSplitShareA11y(String name);

  /// L · row action / a11y action (F-5d)
  ///
  /// In ar, this message translates to:
  /// **'شيل {name}'**
  String transfersSplitRemovePerson(String name);

  /// B · this is the default
  ///
  /// In ar, this message translates to:
  /// **'قسّم بالتساوي'**
  String get transfersSplitEqual;

  /// C · status
  ///
  /// In ar, this message translates to:
  /// **'رجع'**
  String get transfersSplitPaidBack;

  /// C · status (FR-XFR-05)
  ///
  /// In ar, this message translates to:
  /// **'مستني'**
  String get transfersSplitWaiting;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{amount} · {source} · {date}'**
  String transfersSplitPaidDetail(String amount, String date, String source);

  /// L · glossary «دفعت إنت فعلاً» (BR-XFR-04)
  ///
  /// In ar, this message translates to:
  /// **'دفعت إنت فعلاً'**
  String get transfersSplitYourShare;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'اقتراحات'**
  String get transfersSplitSuggestions;

  /// S · + common_action_link; never auto (FR-XFR-08)
  ///
  /// In ar, this message translates to:
  /// **'{amount} من {person} · {date}، من العزومة دي؟'**
  String transfersSplitSuggestion(String amount, String date, String person);

  /// L · on a linked repayment (FR-XFR-09) (F-5d)
  ///
  /// In ar, this message translates to:
  /// **'شيلها من العزومة دي'**
  String get transfersSplitUnassign;

  /// N + common_action_undo · FR-XFR-09
  ///
  /// In ar, this message translates to:
  /// **'اتشالت، ورجعت تتحسب دخل عادي'**
  String get transfersSplitUnassigned;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'اتحفظ التقسيم ✓'**
  String get transfersSplitSaved;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{amount} من {person}'**
  String transfersAssignHeader(String amount, String person);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'وزّعها على مصاريف'**
  String get transfersAssignTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'دوّر في المصاريف الأخيرة'**
  String get transfersAssignSearch;

  /// S · BR-XFR-06
  ///
  /// In ar, this message translates to:
  /// **'مش متوزع: {amount}، هيفضل دخل'**
  String transfersAssignUnassigned(String amount);

  /// S · count:int = 60, n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{مفيش مصاريف من امبارح} =2{مفيش مصاريف في آخر يومين} few{مفيش مصاريف في آخر {n} أيام} many{مفيش مصاريف في آخر {n} يوم} other{مفيش مصاريف في آخر {n} يوم}}'**
  String transfersAssignEmpty(int count, String n);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'دوّر في كل المصاريف'**
  String get transfersAssignSearchAll;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'اتوزعت ✓'**
  String get transfersAssignSaved;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'النصيب لازم يكون أكبر من صفر'**
  String get transfersSplitErrorShareZero;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مجموع الأنصبة أكبر من المصروف'**
  String get transfersSplitErrorSharesExceed;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'وزعت أكتر من المبلغ اللي جالك'**
  String get transfersAssignErrorExceedsIncoming;

  /// S · BR-XFR-06
  ///
  /// In ar, this message translates to:
  /// **'الفلوس الراجعة أكتر من المصروف نفسه'**
  String get transfersAssignErrorExceedsExpense;

  /// S · amounts are never converted
  ///
  /// In ar, this message translates to:
  /// **'عملة مختلفة، مينفعش تربطهم'**
  String get transfersSplitErrorCurrency;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'ربط تحويلة لنفسي'**
  String get transfersLinkTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{amount} · {card} · {date}'**
  String transfersLinkSource(String amount, String card, String date);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'اختار الحركة اللي تقابلها'**
  String get transfersLinkPick;

  /// C · count:int, n · gap under 60 min (0 = same minute)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{في نفس الدقيقة} =1{بعدها بدقيقة} =2{بعدها بدقيقتين} few{بعدها بـ {n} دقايق} many{بعدها بـ {n} دقيقة} other{بعدها بـ {n} دقيقة}}'**
  String transfersLinkAfterMinutes(int count, String n);

  /// C · count:int, n · gap under 60 min
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{في نفس الدقيقة} =1{قبلها بدقيقة} =2{قبلها بدقيقتين} few{قبلها بـ {n} دقايق} many{قبلها بـ {n} دقيقة} other{قبلها بـ {n} دقيقة}}'**
  String transfersLinkBeforeMinutes(int count, String n);

  /// C · count:int, n · gap of 1–23 h (F-5e); can't be 0 (§0.4)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{بعدها بساعة} =2{بعدها بساعتين} few{بعدها بـ {n} ساعات} many{بعدها بـ {n} ساعة} other{بعدها بـ {n} ساعة}}'**
  String transfersLinkAfterHours(int count, String n);

  /// C · count:int, n · gap of 1–23 h
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{قبلها بساعة} =2{قبلها بساعتين} few{قبلها بـ {n} ساعات} many{قبلها بـ {n} ساعة} other{قبلها بـ {n} ساعة}}'**
  String transfersLinkBeforeHours(int count, String n);

  /// C · count:int, n · whole calendar days, gap of 24 h or more. =0 covers a calendar-day count of 0 if a caller passes it
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{في نفس اليوم} =1{بعدها بيوم} =2{بعدها بيومين} few{بعدها بـ {n} أيام} many{بعدها بـ {n} يوم} other{بعدها بـ {n} يوم}}'**
  String transfersLinkAfterDays(int count, String n);

  /// C · count:int, n · as above
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{في نفس اليوم} =1{قبلها بيوم} =2{قبلها بيومين} few{قبلها بـ {n} أيام} many{قبلها بـ {n} يوم} other{قبلها بـ {n} يوم}}'**
  String transfersLinkBeforeDays(int count, String n);

  /// L · cross-currency (A-61); rate includes the target currency. The sheet's button is common_action_link
  ///
  /// In ar, this message translates to:
  /// **'سعر التحويل ≈ {rate} لكل {fromCurrency}'**
  String transfersLinkImpliedRate(String fromCurrency, String rate);

  /// N + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'اتربطوا ✓ ومش هيتحسبوا مصروف'**
  String get transfersLinkLinked;

  /// T · C-28
  ///
  /// In ar, this message translates to:
  /// **'ملقيتش حركة تقابلها'**
  String get transfersLinkEmptyTitle;

  /// S · EC-15
  ///
  /// In ar, this message translates to:
  /// **'ممكن البنك التاني مش بيبعت رسايل. تقدر تعلّمها تحويلة لنفسك برضه، ومش هتتحسب مصروف.'**
  String get transfersLinkEmptyBody;

  /// B · one-sided internal
  ///
  /// In ar, this message translates to:
  /// **'علّمها تحويلة لنفسي'**
  String get transfersLinkMarkAnyway;

  /// S · same currency
  ///
  /// In ar, this message translates to:
  /// **'المبلغين لازم يكونوا زي بعض'**
  String get transfersLinkErrorAmounts;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار حساب تاني'**
  String get transfersLinkErrorAccount;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'لازم واحدة خارجة وواحدة داخلة'**
  String get transfersLinkErrorDirection;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'فلوسي'**
  String get accountsOverviewTitle;

  /// B · opens menu
  ///
  /// In ar, this message translates to:
  /// **'ضيف'**
  String get accountsOverviewAdd;

  /// L · opens accounts_addType_*
  ///
  /// In ar, this message translates to:
  /// **'كارت أو حساب'**
  String get accountsOverviewAddAccount;

  /// L · with common_gold_badge; Free opens S-68
  ///
  /// In ar, this message translates to:
  /// **'أصل (دهب، شهادة…)'**
  String get accountsOverviewAddAsset;

  /// L · glossary; one figure per currency, no cross-currency sum
  ///
  /// In ar, this message translates to:
  /// **'اللي حيلتك كله'**
  String get accountsOverviewNetWorth;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'عملات تانية'**
  String get accountsOverviewOtherCurrenciesA11y;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كروتك وحساباتك'**
  String get accountsOverviewAccountsTitle;

  /// L · text button, opens S-42
  ///
  /// In ar, this message translates to:
  /// **'قارن'**
  String get accountsOverviewCompare;

  /// C · when = common_date_minutesAgo or a date (FR-ACC-02)
  ///
  /// In ar, this message translates to:
  /// **'آخر تحديث {when}'**
  String accountsOverviewAsOf(String when);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'متاح من {limit}'**
  String accountsOverviewCreditAvailable(String limit);

  /// L · count:int, n · multi-currency row (FR-ACC-06)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{وكمان عملة واحدة} =2{وكمان عملتين} few{وكمان {n} عملات} many{وكمان {n} عملة} other{وكمان {n} عملة}}'**
  String accountsOverviewMoreCurrencies(int count, String n);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'يدوي وصوت'**
  String get accountsOverviewCashSub;

  /// C · ignored card (C-07)
  ///
  /// In ar, this message translates to:
  /// **'مش متتبع'**
  String get accountsOverviewNotTracked;

  /// L · row at the end of the list, only when at least one account is hidden. Opens the hidden list (S-40 spec, accounts_hidden_*, §2.12), where each account can be unhidden or opened in S-43 (D-69). Trailing count: accounts_overview_hiddenCount
  ///
  /// In ar, this message translates to:
  /// **'الحسابات المخفية'**
  String get accountsOverviewHiddenEntry;

  /// L · glossary, + common_gold_badge
  ///
  /// In ar, this message translates to:
  /// **'دهبك وشهاداتك'**
  String get accountsOverviewAssetsTitle;

  /// L · text button, opens S-45
  ///
  /// In ar, this message translates to:
  /// **'الأسعار'**
  String get accountsOverviewPrices;

  /// S · locked preview + common_gold_unlock
  ///
  /// In ar, this message translates to:
  /// **'تابع دهبك وشهاداتك وكل أصولك في مكان واحد'**
  String get accountsOverviewAssetsLocked;

  /// L · only when the zakah flag is on
  ///
  /// In ar, this message translates to:
  /// **'الزكاة'**
  String get accountsOverviewZakah;

  /// T · C-28, Rive sleep
  ///
  /// In ar, this message translates to:
  /// **'الحسابات بتظهر لوحدها من رسايل البنك'**
  String get accountsOverviewEmptyTitle;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'ضيف حساب بإيدك'**
  String get accountsOverviewEmptyAdd;

  /// T · sheet
  ///
  /// In ar, this message translates to:
  /// **'تضيف إيه؟'**
  String get accountsAddTypeTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الكروت بتتضاف لوحدها أول ما توصل رسالة. ضيف بإيدك لو لسه مفيش رسايل.'**
  String get accountsAddTypeInfo;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كريدت كارد'**
  String get accountsAddTypeCredit;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الليميت وميعاد السداد'**
  String get accountsAddTypeCreditSub;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كارت ديبت / حساب بنك'**
  String get accountsAddTypeDebit;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مرتب ومصاريف'**
  String get accountsAddTypeDebitSub;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'محفظة'**
  String get accountsAddTypeWallet;

  /// S · mobile-wallet examples; InstaPay removed because it's a transfer rail (Q-10). Brand names still need OQ-09 clearance
  ///
  /// In ar, this message translates to:
  /// **'فودافون كاش، أورانج كاش، إي آند كاش'**
  String get accountsAddTypeWalletSub;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'حساب بأكتر من عملة'**
  String get accountsAddTypeMulti;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'Wise، Revolut، Payoneer'**
  String get accountsAddTypeMultiSub;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'تقسيط'**
  String get accountsAddTypeBnpl;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'فاليو، سيمبل، كونتكت'**
  String get accountsAddTypeBnplSub;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'من أنهي بنك؟'**
  String get accountsAddBankTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'دوّر على بنك…'**
  String get accountsAddBankSearch;

  /// L · section
  ///
  /// In ar, this message translates to:
  /// **'بنوك مصر'**
  String get accountsAddBankEgypt;

  /// L · section
  ///
  /// In ar, this message translates to:
  /// **'بنوك برّه وأونلاين'**
  String get accountsAddBankAbroad;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'بنكي مش موجود'**
  String get accountsAddBankNotListed;

  /// S · generic parser (FR-PAR-13); no promise
  ///
  /// In ar, this message translates to:
  /// **'ضيفه باسمه، وزغلول هيحاول يفهم رسايله'**
  String get accountsAddBankNotListedSub;

  /// S · + not-listed row
  ///
  /// In ar, this message translates to:
  /// **'مفيش بنك بالاسم ده'**
  String get accountsAddBankNoResults;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار بنك'**
  String get accountsAddBankRequired;

  /// N · success
  ///
  /// In ar, this message translates to:
  /// **'الكارت اتضاف! ✨'**
  String get accountsAddedTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'السداد يوم {day} كل شهر'**
  String accountsAddedDueDay(String day);

  /// S · value shows "—"
  ///
  /// In ar, this message translates to:
  /// **'هيتحدث مع أول رسالة فيها الرصيد المتاح'**
  String get accountsAddedWaitingBalance;

  /// S · S-41 empty state, Rive sleep
  ///
  /// In ar, this message translates to:
  /// **'أول ما توصلك رسالة من {bank} على {last4} هتظهر هنا لوحدها.'**
  String accountsAddedEmptyBody(String bank, String last4);

  /// L · common_gold_badge; Free opens S-68
  ///
  /// In ar, this message translates to:
  /// **'ضيف كشف حساب الكارت'**
  String get accountsAddedImport;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'PDF من تطبيق البنك'**
  String get accountsAddedImportSub;

  /// L · opens S-13 on this card (FR-CARD-05)
  ///
  /// In ar, this message translates to:
  /// **'سجّل حركة بإيدك'**
  String get accountsAddedManual;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'على الكارت ده'**
  String get accountsAddedManualSub;

  /// L · glossary, credit
  ///
  /// In ar, this message translates to:
  /// **'فاضل في الكارت'**
  String get accountsDetailAvailable;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{available} من {limit}'**
  String accountsDetailAvailableOf(String available, String limit);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'مستخدم {percent} من الليميت'**
  String accountsDetailLimitUsed(String percent);

  /// L · debit / account
  ///
  /// In ar, this message translates to:
  /// **'الرصيد'**
  String get accountsDetailBalance;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'آخر تحديث {when}'**
  String accountsDetailAsOf(String when);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'هيظهر مع أول رسالة فيها رصيد'**
  String get accountsDetailBalanceUnknown;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'ميعاد السداد {date}'**
  String accountsDetailDue(String date);

  /// L · + period chip common_period_*
  ///
  /// In ar, this message translates to:
  /// **'صرفت'**
  String get accountsDetailSpent;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'توزيع الصرف على التصنيفات'**
  String get accountsDetailDonutA11y;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'أكتر أماكن صرفت فيها'**
  String get accountsDetailTopMerchants;

  /// L · subtitle common_period_lastMonths
  ///
  /// In ar, this message translates to:
  /// **'الصرف شهر بشهر'**
  String get accountsDetailTrend;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'دخل ومرتجعات'**
  String get accountsDetailIncomeRefunds;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'آخر الحركات'**
  String get accountsDetailRecent;

  /// L · sets the card filter, opens S-11
  ///
  /// In ar, this message translates to:
  /// **'كل حركات الكارت'**
  String get accountsDetailAllTransactions;

  /// L · value lists common_channel_*Short + ✓/✗, opens S-62
  ///
  /// In ar, this message translates to:
  /// **'زغلول بيقرا إيه'**
  String get accountsDetailCapture;

  /// L · ⋮ menu
  ///
  /// In ar, this message translates to:
  /// **'زغلول يقرا إيه من الكارت'**
  String get accountsDetailMenuCapture;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'ادمجه مع كارت تاني'**
  String get accountsDetailMenuMerge;

  /// L · D-69: hides from lists and pickers only
  ///
  /// In ar, this message translates to:
  /// **'اخفي الحساب'**
  String get accountsDetailMenuHide;

  /// S · Rive sleep
  ///
  /// In ar, this message translates to:
  /// **'مفيش صرف على الكارت ده في الفترة دي'**
  String get accountsDetailEmpty;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'{platform, select, ios{مش متتبع: الرسايل وApple Pay مقفولين للكارت ده} other{مش متتبع: الرسايل والإشعارات مقفولة للكارت ده}}'**
  String accountsDetailIgnoredBanner(String platform);

  /// B · Android then offers capture_rescanOffer_*
  ///
  /// In ar, this message translates to:
  /// **'تابعه تاني'**
  String get accountsDetailTrackAgain;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'مقارنة الكروت'**
  String get accountsCompareTitle;

  /// L · same currency only
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get accountsCompareTotal;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اختار الكروت'**
  String get accountsCompareChoose;

  /// S · count:int = 6 (UX-A-03), n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{تقدر تختار كارت واحد} =2{تقدر تختار لحد كارتين} few{تقدر تختار لحد {n} كروت} many{تقدر تختار لحد {n} كارت} other{تقدر تختار لحد {n} كارت}}'**
  String accountsCompareMax(int count, String n);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الكروت اللي بعملة تانية بتظهر لما تختار عملتها'**
  String get accountsCompareOtherCurrency;

  /// S · C-28
  ///
  /// In ar, this message translates to:
  /// **'المقارنة محتاجة كارتين على الأقل فيهم صرف'**
  String get accountsCompareEmpty;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'{category}، {card}: {amount}'**
  String accountsCompareCellA11y(String amount, String card, String category);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل الكارت'**
  String get accountsEditTitleEdit;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'كارت جديد'**
  String get accountsEditTitleNew;

  /// L · 1–30, unique
  ///
  /// In ar, this message translates to:
  /// **'اسم الكارت'**
  String get accountsEditName;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'البنك'**
  String get accountsEditBank;

  /// L · read-only when auto-created
  ///
  /// In ar, this message translates to:
  /// **'اتعرف من الرسايل'**
  String get accountsEditBankAuto;

  /// L · LTR input, Western digits shown
  ///
  /// In ar, this message translates to:
  /// **'آخر أربع أرقام'**
  String get accountsEditLast4;

  /// S · sample = a synthetic pattern from the institution template, e.g. 1234 (never a real SMS)
  ///
  /// In ar, this message translates to:
  /// **'في الرسالة بيبان كده: «{sample}»، عشان زغلول يعرف الكارت.'**
  String accountsEditLast4Hint(String sample);

  /// L · common_accountType_*
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get accountsEditType;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'العملة'**
  String get accountsEditCurrency;

  /// L · multi-currency
  ///
  /// In ar, this message translates to:
  /// **'الأرصدة'**
  String get accountsEditBalances;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'ضيف عملة'**
  String get accountsEditAddCurrency;

  /// L · credit only, ≥ 0
  ///
  /// In ar, this message translates to:
  /// **'الليميت'**
  String get accountsEditLimit;

  /// L · credit only, 1–31
  ///
  /// In ar, this message translates to:
  /// **'يوم السداد'**
  String get accountsEditDueDay;

  /// S · count:int (default 3, BR-SUB-03), n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{هفكرك يوم السداد نفسه.} =1{هفكرك قبل ميعاد السداد بيوم.} =2{هفكرك قبل ميعاد السداد بيومين.} few{هفكرك قبل ميعاد السداد بـ {n} أيام.} many{هفكرك قبل ميعاد السداد بـ {n} يوم.} other{هفكرك قبل ميعاد السداد بـ {n} يوم.}}'**
  String accountsEditDueReminder(int count, String n);

  /// T · section heading, create mode inline toggles (common_channel_*)
  ///
  /// In ar, this message translates to:
  /// **'زغلول يقرا إيه من الكارت ده؟'**
  String get accountsEditCaptureTitle;

  /// L · edit mode, opens S-62
  ///
  /// In ar, this message translates to:
  /// **'زغلول بيقرا إيه'**
  String get accountsEditCaptureLink;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'ادمجه مع كارت تاني'**
  String get accountsEditMerge;

  /// L · switch
  ///
  /// In ar, this message translates to:
  /// **'اخفي الحساب ده'**
  String get accountsEditHide;

  /// S · D-69
  ///
  /// In ar, this message translates to:
  /// **'مش هيظهر في القوايم، بس حركاته لسه محسوبة في الأرقام والميزانية والشارتات.'**
  String get accountsEditHideHint;

  /// N + common_action_undo · D-69
  ///
  /// In ar, this message translates to:
  /// **'الحساب اتخفى. حركاته لسه محسوبة.'**
  String get accountsEditHidden;

  /// S · same bank + last-4
  ///
  /// In ar, this message translates to:
  /// **'الكارت ده موجود، افتحه؟'**
  String get accountsEditDuplicate;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'افتحه'**
  String get accountsEditOpenExisting;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الليميت ميكونش بالسالب'**
  String get accountsEditErrorLimit;

  /// S · min = 1, max = 31
  ///
  /// In ar, this message translates to:
  /// **'اختار يوم من {min} لـ {max}'**
  String accountsEditErrorDueDay(String max, String min);

  /// N
  ///
  /// In ar, this message translates to:
  /// **'اتحفظ ✓'**
  String get accountsEditSaved;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تدمجه مع أنهي كارت؟'**
  String get accountsMergePickTitle;

  /// T · count:int, n · see Q-12
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{تدمج {fromCard} في {toCard}؟} =1{تنقل حركة واحدة من {fromCard} لـ {toCard}؟} =2{تنقل حركتين من {fromCard} لـ {toCard}؟} few{تنقل {n} حركات من {fromCard} لـ {toCard}؟} many{تنقل {n} حركة من {fromCard} لـ {toCard}؟} other{تنقل {n} حركة من {fromCard} لـ {toCard}؟}}'**
  String accountsMergeConfirmTitle(
    int count,
    String fromCard,
    String n,
    String toCard,
  );

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الكارتين هيبقوا كارت واحد.'**
  String get accountsMergeConfirmBody;

  /// L · checkbox (EC-60)
  ///
  /// In ar, this message translates to:
  /// **'انقل إعدادات القراية كمان'**
  String get accountsMergeCopyCapture;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'ادمج'**
  String get accountsMergeConfirm;

  /// S · warning dialog
  ///
  /// In ar, this message translates to:
  /// **'الكارتين من بنكين مختلفين. متأكد إنهم نفس الكارت؟'**
  String get accountsMergeDifferentBank;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'أيوه، ادمج'**
  String get accountsMergeDifferentBankConfirm;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مينفعش تدمج الكارت في نفسه'**
  String get accountsMergeErrorSelf;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'اتدمجوا ✓'**
  String get accountsMergeDone;

  /// T · glossary
  ///
  /// In ar, this message translates to:
  /// **'زغلول بيقرا منين'**
  String get captureSettingsTitle;

  /// L · section
  ///
  /// In ar, this message translates to:
  /// **'المصادر'**
  String get captureSettingsSources;

  /// C · Android permission granted
  ///
  /// In ar, this message translates to:
  /// **'شغال'**
  String get captureSettingsOn;

  /// C · + common_action_fix when a permission is revoked
  ///
  /// In ar, this message translates to:
  /// **'مقفول'**
  String get captureSettingsOff;

  /// C · iOS Apple Pay / Shortcuts row when the setup checker passes (F-5b)
  ///
  /// In ar, this message translates to:
  /// **'شغال'**
  String get captureSettingsActive;

  /// C · iOS checker can't tell (FR-ING-I-07). Never shown as a failure; + capture_settings_checkSetup
  ///
  /// In ar, this message translates to:
  /// **'لسه مش متأكدين'**
  String get captureSettingsUnknown;

  /// C · iOS SMS row subtitle
  ///
  /// In ar, this message translates to:
  /// **'عن طريق الاختصارات'**
  String get captureSettingsSmsIos;

  /// B · iOS, opens S-03 step 2
  ///
  /// In ar, this message translates to:
  /// **'اتأكد من الإعداد'**
  String get captureSettingsCheckSetup;

  /// L · opens capture_shareHow_*
  ///
  /// In ar, this message translates to:
  /// **'ابعت أو الزق رسالة'**
  String get captureSettingsShare;

  /// L · section (FR-CAP-06)
  ///
  /// In ar, this message translates to:
  /// **'مش متتبعين'**
  String get captureSettingsNotTracked;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'كل كروتك متتبعة'**
  String get captureSettingsNotTrackedEmpty;

  /// L · channels = list of common_channel_*Short joined by the locale's list format. Row title = card or bank. + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'{channels} مقفولة'**
  String captureSettingsIgnoredChannels(String channels);

  /// L · FR-CAP-03
  ///
  /// In ar, this message translates to:
  /// **'متتابعش كارت أو بنك'**
  String get captureSettingsAddIgnore;

  /// L · section
  ///
  /// In ar, this message translates to:
  /// **'أدوات'**
  String get captureSettingsTools;

  /// L · Android
  ///
  /// In ar, this message translates to:
  /// **'دوّر في الرسايل القديمة تاني'**
  String get captureSettingsRescan;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'البنوك اللي زغلول بيفهمها'**
  String get captureSettingsBanks;

  /// L · opens ingestion_requestBank_*
  ///
  /// In ar, this message translates to:
  /// **'اطلب دعم بنكك'**
  String get captureSettingsRequestBank;

  /// L · common_gold_badge; Free opens S-68
  ///
  /// In ar, this message translates to:
  /// **'قوالب رسايل خاصة بيك'**
  String get captureSettingsTemplates;

  /// N · Android SPOOL_DECRYPT_FAILED
  ///
  /// In ar, this message translates to:
  /// **'في رسايل مقدرتش أقراها. دوّر في الرسايل تاني عشان ميفوتكش حاجة.'**
  String get captureSettingsUnreadable;

  /// T · sheet
  ///
  /// In ar, this message translates to:
  /// **'متتابعش كارت أو بنك'**
  String get captureIgnoreTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'البنك'**
  String get captureIgnoreBank;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'آخر أربع أرقام (اختياري)'**
  String get captureIgnoreLast4;

  /// S · FR-CAP-05
  ///
  /// In ar, this message translates to:
  /// **'سيبه فاضي عشان تبطّل تتابع البنك كله'**
  String get captureIgnoreLast4Hint;

  /// L · common_channel_* checkboxes
  ///
  /// In ar, this message translates to:
  /// **'متقراش من:'**
  String get captureIgnoreChannels;

  /// S · BR-CAP-01; spec wording (screens/70). It doesn't claim "won't look", because the institution and card are identified in memory before the message is discarded (F-4)
  ///
  /// In ar, this message translates to:
  /// **'اللي تقفله، زغلول هيتجاهل رسايله ومش هيحفظ منها حاجة.'**
  String get captureIgnorePrivacy;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار البنك'**
  String get captureIgnoreErrorBank;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار مصدر واحد على الأقل'**
  String get captureIgnoreErrorChannel;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'سيبه فاضي أو اكتب أربع أرقام'**
  String get captureIgnoreErrorLast4;

  /// N + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'تمام، مش هتابعه'**
  String get captureIgnoreSaved;

  /// T · FR-CAP-07
  ///
  /// In ar, this message translates to:
  /// **'دوّر في الرسايل القديمة'**
  String get captureRescanTitle;

  /// L · options common_period_lastMonths 6–24 (A-11)
  ///
  /// In ar, this message translates to:
  /// **'لحد إمتى؟'**
  String get captureRescanDepth;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'ابدأ'**
  String get captureRescanStart;

  /// L · count:int, n · Rive scanning, C-27 with cancel
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{بدوّر…} =1{بدوّر… لقيت حركة جديدة} =2{بدوّر… لقيت حركتين جداد} few{بدوّر… لقيت {n} حركات جديدة} many{بدوّر… لقيت {n} حركة جديدة} other{بدوّر… لقيت {n} حركة جديدة}}'**
  String captureRescanRunning(int count, String n);

  /// N · count:int, n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{ملقيتش حركات جديدة ✓} =1{ضفت حركة جديدة ✓} =2{ضفت حركتين جداد ✓} few{ضفت {n} حركات جديدة ✓} many{ضفت {n} حركة جديدة ✓} other{ضفت {n} حركة جديدة ✓}}'**
  String captureRescanDone(int count, String n);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اللي اتسجل قبل كده مش هيتكرر'**
  String get captureRescanNoDuplicates;

  /// T · after un-ignoring (Android)
  ///
  /// In ar, this message translates to:
  /// **'أدوّر في الرسايل القديمة على حركات {card}؟'**
  String captureRescanOfferTitle(String card);

  /// S · BR-CAP-04
  ///
  /// In ar, this message translates to:
  /// **'الرسايل اللي اتقفلت قبل كده متحفظتش، بس ممكن ألاقيها لسه في صندوق الرسايل.'**
  String get captureRescanOfferBody;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'دوّر'**
  String get captureRescanOfferYes;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'البنوك اللي زغلول بيفهمها'**
  String get captureBanksTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'دوّر على بنك…'**
  String get captureBanksSearch;

  /// S · + capture_settings_requestBank
  ///
  /// In ar, this message translates to:
  /// **'مفيش بنك بالاسم ده'**
  String get captureBanksNoResults;

  /// L · per-bank line on both platforms. channels = common_channel_*Short from the registry (F-5c)
  ///
  /// In ar, this message translates to:
  /// **'بيتسجل من: {channels}'**
  String captureBanksChannels(String channels);

  /// S · FR-ING-I-08. Statements are Gold (FR-EXP-04/06), so the copy says so (F-8)
  ///
  /// In ar, this message translates to:
  /// **'على الآيفون، {bank} بيتسجل من Apple Pay والسكرين شوت، وكشوف الحساب مع جولد. الآيفون مش بيسمح لزغلول يقرا إشعارات التطبيقات التانية.'**
  String captureBanksIosNote(String bank);

  /// T · shared by S-02 and S-61
  ///
  /// In ar, this message translates to:
  /// **'إزاي تبعت رسالة لزغلول'**
  String get captureShareHowTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'افتح رسالة البنك في تطبيق الرسايل'**
  String get captureShareHowStep1;

  /// S · OS labels may differ, see Q-04
  ///
  /// In ar, this message translates to:
  /// **'دوس عليها شوية واختار «مشاركة» أو «نسخ»'**
  String get captureShareHowStep2;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار زغلول، أو افتح زغلول والزقها'**
  String get captureShareHowStep3;

  /// S · FR-ING-A-04
  ///
  /// In ar, this message translates to:
  /// **'هتشوفها قبل ما تتسجل.'**
  String get captureShareHowNote;

  /// T · sheet; switches use common_channel_*
  ///
  /// In ar, this message translates to:
  /// **'زغلول يقرا إيه من {card}؟'**
  String captureCardControlsTitle(String card);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار براحتك، وتقدر تغير في أي وقت'**
  String get captureCardControlsSubtitle;

  /// L · switch subtitle
  ///
  /// In ar, this message translates to:
  /// **'عن طريق اختصارات الآيفون'**
  String get captureCardControlsSmsIos;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الدفع بالموبايل'**
  String get captureCardControlsApplePaySub;

  /// S · BR-CAP-01; spec wording (screens/70:60-61) (F-4)
  ///
  /// In ar, this message translates to:
  /// **'لما تقفل حاجة هنا، رسايل الكارت ده هتتجاهل ومش هتتحفظ.'**
  String get captureCardControlsInfo;

  /// T · last channel switched off (FR-CAP-04). Serious, no emoji
  ///
  /// In ar, this message translates to:
  /// **'تبطّل تتابع {card}؟'**
  String captureStopTrackingTitle(String card);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الحركات اللي اتسجلت قبل كده:'**
  String get captureStopTrackingExisting;

  /// L · radio, default
  ///
  /// In ar, this message translates to:
  /// **'سيبهم زي ما هم'**
  String get captureStopTrackingKeep;

  /// L · radio; count:int, n · hidden when the card has no transactions (§0.4)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{امسح حركة واحدة} =2{امسح الحركتين} few{امسح الـ {n} حركات} many{امسح الـ {n} حركة} other{امسح الـ {n} حركة}}'**
  String captureStopTrackingDelete(int count, String n);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'بطّل المتابعة'**
  String get captureStopTrackingConfirm;

  /// T · count:int, n · second confirmation
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{تمسح حركة واحدة نهائي؟} =2{تمسح الحركتين نهائي؟} few{تمسح {n} حركات نهائي؟} many{تمسح {n} حركة نهائي؟} other{تمسح {n} حركة نهائي؟}}'**
  String captureStopTrackingDeleteTitle(int count, String n);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مفيش رجوع. الحركات دي هتتمسح من الموبايل وكل الأرقام هتتحدث.'**
  String get captureStopTrackingDeleteBody;

  /// B · destructive
  ///
  /// In ar, this message translates to:
  /// **'امسح نهائي'**
  String get captureStopTrackingDeleteConfirm;

  /// N + common_action_undo (restores the switches only; deleted data stays deleted)
  ///
  /// In ar, this message translates to:
  /// **'مش هتابع {card} تاني'**
  String captureStopTrackingDone(String card);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
