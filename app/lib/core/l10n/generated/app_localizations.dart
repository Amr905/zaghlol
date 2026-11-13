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

  /// T · sheet
  ///
  /// In ar, this message translates to:
  /// **'عايز تسجل إيه؟'**
  String get homeQuickAddTitle;

  /// L · opens S-31
  ///
  /// In ar, this message translates to:
  /// **'قول'**
  String get homeQuickAddSay;

  /// L · opens S-13
  ///
  /// In ar, this message translates to:
  /// **'اكتب'**
  String get homeQuickAddType;

  /// L · opens S-32
  ///
  /// In ar, this message translates to:
  /// **'صوّر'**
  String get homeQuickAddScan;

  /// L · with common_gold_badge; Free opens S-68
  ///
  /// In ar, this message translates to:
  /// **'أصل'**
  String get homeQuickAddAsset;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'قول لزغلول'**
  String get homeQuickAddSayA11y;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'اكتب حركة'**
  String get homeQuickAddTypeA11y;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'اقرا سكرين شوت'**
  String get homeQuickAddScanA11y;

  /// A
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

  /// B · S-31 and S-32 fallback
  ///
  /// In ar, this message translates to:
  /// **'اكتبها بإيدك'**
  String get commonActionTypeInstead;

  /// C · n = grams, up to three decimals (FR-WLT-02)
  ///
  /// In ar, this message translates to:
  /// **'{n} جرام'**
  String commonUnitGrams(String n);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{amount} في الشهر'**
  String commonUnitPerMonth(String amount);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{amount} في السنة'**
  String commonUnitPerYear(String amount);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{amount} في اليوم'**
  String commonUnitPerDay(String amount);

  /// C · count:int, n · inserted into sentences as {visits}
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{زيارة واحدة} =2{زيارتين} few{{n} زيارات} many{{n} زيارة} other{{n} زيارة}}'**
  String commonUnitVisits(int count, String n);

  /// C · count:int, n · inserted as {orders}
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{أوردر واحد} =2{أوردرين} few{{n} أوردرات} many{{n} أوردر} other{{n} أوردر}}'**
  String commonUnitOrders(int count, String n);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كل أسبوع'**
  String get commonCadenceWeekly;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كل شهر'**
  String get commonCadenceMonthly;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كل تلات شهور'**
  String get commonCadenceQuarterly;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كل ستة شهور'**
  String get commonCadenceSemiannual;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كل سنة'**
  String get commonCadenceYearly;

  /// C · asset type (FR-WLT-02)
  ///
  /// In ar, this message translates to:
  /// **'دهب'**
  String get commonAssetTypeGold;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'شهادة بنك'**
  String get commonAssetTypeCertificate;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'كاش بعملة'**
  String get commonAssetTypeForeignCash;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'أسهم وصناديق'**
  String get commonAssetTypeStocks;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'عقار'**
  String get commonAssetTypeProperty;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'عربية'**
  String get commonAssetTypeCar;

  /// C · karat = 24, 21 or 18 from the digits layer
  ///
  /// In ar, this message translates to:
  /// **'عيار {karat}'**
  String commonKaratLabel(String karat);

  /// C · the gold pound
  ///
  /// In ar, this message translates to:
  /// **'جنيه دهب'**
  String get commonKaratCoin;

  /// M · Rive tap
  ///
  /// In ar, this message translates to:
  /// **'عايز تعرف فلوسك راحت فين؟ افتح الحسبة'**
  String get mascotTapLine9;

  /// M · Rive tap
  ///
  /// In ar, this message translates to:
  /// **'أنا بحسب والدهب بيلمع، وإنت بتحوّش'**
  String get mascotTapLine10;

  /// C · C-35 segment 1
  ///
  /// In ar, this message translates to:
  /// **'الشارتات'**
  String get insightsTabsCharts;

  /// C · segment 2
  ///
  /// In ar, this message translates to:
  /// **'الميزانية'**
  String get insightsTabsBudget;

  /// C · segment 3
  ///
  /// In ar, this message translates to:
  /// **'الفواتير'**
  String get insightsTabsBills;

  /// T · period sheet. Items use common_period_*; Apply uses common_action_done
  ///
  /// In ar, this message translates to:
  /// **'الفترة'**
  String get insightsPeriodTitle;

  /// L · custom range
  ///
  /// In ar, this message translates to:
  /// **'من'**
  String get insightsPeriodStart;

  /// L · custom range. Validation: common_validation_dateRange
  ///
  /// In ar, this message translates to:
  /// **'لحد'**
  String get insightsPeriodEnd;

  /// L · filter context line under each chart title (C-13). period = common_period_* or common_date_range
  ///
  /// In ar, this message translates to:
  /// **'{cards} · {currency} · {period}'**
  String insightsChartsContext(String cards, String currency, String period);

  /// B · the FR-CHT-03 name. Also the S-21 button
  ///
  /// In ar, this message translates to:
  /// **'اشرحلي يا زغلول'**
  String get insightsChartsExplain;

  /// S · C-13 locked, blurred preview + common_gold_unlock
  ///
  /// In ar, this message translates to:
  /// **'شوف الشارت كله مع جولد'**
  String get insightsChartsLockedSub;

  /// S · C-13 empty (EC-23)
  ///
  /// In ar, this message translates to:
  /// **'بيحيا بعد أول دورة كاملة'**
  String get insightsChartsEmptyCycle;

  /// S · charts 8 and 11 when they have nothing to show
  ///
  /// In ar, this message translates to:
  /// **'ضيف حسابات أو أصول علشان الشارت ده يشتغل'**
  String get insightsChartsEmptyNetWorth;

  /// B · opens S-40
  ///
  /// In ar, this message translates to:
  /// **'افتح فلوسي'**
  String get insightsChartsEmptyNetWorthAction;

  /// S · plus common_action_clearFilter
  ///
  /// In ar, this message translates to:
  /// **'مفيش بيانات للفلتر ده في الفترة دي'**
  String get insightsChartsEmptyFilter;

  /// S · C-29 inline; plus common_action_tryAgain
  ///
  /// In ar, this message translates to:
  /// **'الشارت ده مفتحش. باقي الشارتات تمام.'**
  String get insightsChartsCardError;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'بحمّل الشارتات'**
  String get insightsChartsLoadingA11y;

  /// C · donut remainder slice
  ///
  /// In ar, this message translates to:
  /// **'حاجات تانية'**
  String get insightsChartsOtherSlice;

  /// T · chart 1 (Free)
  ///
  /// In ar, this message translates to:
  /// **'الداخل والخارج والصافي'**
  String get insightsChartTitleCashFlow;

  /// T · chart 2 (Free)
  ///
  /// In ar, this message translates to:
  /// **'فلوسك رايحة فين؟'**
  String get insightsChartTitleCategories;

  /// T · chart 3 (Gold)
  ///
  /// In ar, this message translates to:
  /// **'سرعة الصرف لحد القبض'**
  String get insightsChartTitleBurnRate;

  /// T · chart 4 (Gold)
  ///
  /// In ar, this message translates to:
  /// **'ميزان خمسين تلاتين عشرين'**
  String get insightsChartTitleRule503020;

  /// T · chart 5 (Gold), day of week and hour
  ///
  /// In ar, this message translates to:
  /// **'إمتى بتصرف؟'**
  String get insightsChartTitleWeekPattern;

  /// T · chart 6 (Free, top five)
  ///
  /// In ar, this message translates to:
  /// **'أكتر الأماكن اللي بتاخد فلوسك'**
  String get insightsChartTitleMerchants;

  /// T · chart 7 (Gold)
  ///
  /// In ar, this message translates to:
  /// **'الدورة دي ضد متوسط تلات دورات'**
  String get insightsChartTitleVsAverage;

  /// T · chart 8 (Gold)
  ///
  /// In ar, this message translates to:
  /// **'أقساطك في الستة شهور الجايين'**
  String get insightsChartTitleInstallments;

  /// T · chart 9 (Gold)
  ///
  /// In ar, this message translates to:
  /// **'الاشتراكات في السنة كلها'**
  String get insightsChartTitleSubscriptions;

  /// T · chart 10 (Gold)
  ///
  /// In ar, this message translates to:
  /// **'الصرف على كروتك ومحافظك'**
  String get insightsChartTitleCards;

  /// T · chart 11 (Gold)
  ///
  /// In ar, this message translates to:
  /// **'نمو اللي حيلتك كله'**
  String get insightsChartTitleNetWorth;

  /// T · chart 12 (Gold)
  ///
  /// In ar, this message translates to:
  /// **'الغلاء على سلتك إنت'**
  String get insightsChartTitleInflation;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'دخلك'**
  String get insightsLegendIncome;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'صرفت'**
  String get insightsLegendSpent;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'حوشت'**
  String get insightsLegendSaved;

  /// C · chart 3
  ///
  /// In ar, this message translates to:
  /// **'فعلي'**
  String get insightsLegendActual;

  /// C · chart 3 dotted line
  ///
  /// In ar, this message translates to:
  /// **'الخط المثالي'**
  String get insightsLegendIdeal;

  /// C · chart 3 marker
  ///
  /// In ar, this message translates to:
  /// **'النهارده'**
  String get insightsLegendToday;

  /// C · chart 3 end marker
  ///
  /// In ar, this message translates to:
  /// **'القبض'**
  String get insightsLegendPayday;

  /// C · chart 4
  ///
  /// In ar, this message translates to:
  /// **'أساسيات'**
  String get insightsLegendNeeds;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'رفاهيات'**
  String get insightsLegendWants;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'تحويش'**
  String get insightsLegendSavings;

  /// C · chart 4 target mark
  ///
  /// In ar, this message translates to:
  /// **'المثالي'**
  String get insightsLegendTarget;

  /// C · chart 7
  ///
  /// In ar, this message translates to:
  /// **'متوسطك'**
  String get insightsLegendAverage;

  /// C · chart 7
  ///
  /// In ar, this message translates to:
  /// **'الدورة دي'**
  String get insightsLegendThisCycle;

  /// C · chart 8
  ///
  /// In ar, this message translates to:
  /// **'أقساط'**
  String get insightsLegendInstallments;

  /// C · chart 8
  ///
  /// In ar, this message translates to:
  /// **'كروت وجمعية'**
  String get insightsLegendCardDues;

  /// C · chart 9
  ///
  /// In ar, this message translates to:
  /// **'في الشهر'**
  String get insightsLegendMonthly;

  /// C · chart 9, the ×12 bars
  ///
  /// In ar, this message translates to:
  /// **'في السنة'**
  String get insightsLegendYearly;

  /// L · chart 12
  ///
  /// In ar, this message translates to:
  /// **'متوسط فاتورة السوبرماركت'**
  String get insightsLegendSupermarket;

  /// L · chart 12
  ///
  /// In ar, this message translates to:
  /// **'متوسط أوردر الدليفري'**
  String get insightsLegendDelivery;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'الداخل والخارج: دخلك {income}، صرفت {spent}، وحوشت {saved}'**
  String insightsChartA11yCashFlow(String income, String spent, String saved);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'فلوسك رايحة فين: {category} الأكبر بـ {amount}، يعني {percent}'**
  String insightsChartA11yCategories(
    String category,
    String amount,
    String percent,
  );

  /// A
  ///
  /// In ar, this message translates to:
  /// **'سرعة الصرف: صرفت {spent} من {budget} في اليوم {cycleDay}'**
  String insightsChartA11yBurnRate(
    String spent,
    String budget,
    String cycleDay,
  );

  /// A
  ///
  /// In ar, this message translates to:
  /// **'ميزان خمسين تلاتين عشرين: {needsPct} أساسيات، {wantsPct} رفاهيات، {savingsPct} تحويش'**
  String insightsChartA11yRule503020(
    String needsPct,
    String wantsPct,
    String savingsPct,
  );

  /// A
  ///
  /// In ar, this message translates to:
  /// **'إمتى بتصرف: أعلى يوم {peakDay} بمتوسط {amount}'**
  String insightsChartA11yWeekPattern(String peakDay, String amount);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'أكتر الأماكن: {merchant} الأول بـ {amount}'**
  String insightsChartA11yMerchants(String merchant, String amount);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'الدورة دي ضد متوسطك: أكبر زيادة في {category} بـ {percent}'**
  String insightsChartA11yVsAverage(String category, String percent);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'الأقساط: الشهر ده {sum}'**
  String insightsChartA11yInstallments(String sum);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'الاشتراكات: {monthly} في الشهر، يعني {yearly} في السنة'**
  String insightsChartA11ySubscriptions(String monthly, String yearly);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'الكروت: {card} الأكبر بـ {percent} من الصرف'**
  String insightsChartA11yCards(String card, String percent);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'اللي حيلتك كله: من {startAmount} لـ {endAmount}'**
  String insightsChartA11yNetWorth(String startAmount, String endAmount);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'الغلاء: فاتورة السوبرماركت من {startAmount} لـ {endAmount}'**
  String insightsChartA11yInflation(String startAmount, String endAmount);

  /// A · opens S-11 filtered
  ///
  /// In ar, this message translates to:
  /// **'{category}: {amount}، {percent}. اضغط تشوف الحركات'**
  String insightsChartDetailLegendRowA11y(
    String category,
    String amount,
    String percent,
  );

  /// A · chart 10, opens S-41
  ///
  /// In ar, this message translates to:
  /// **'{card}: {amount}. اضغط تفتح الكارت'**
  String insightsChartDetailCardRowA11y(String card, String amount);

  /// A · Rive professor, typing dots
  ///
  /// In ar, this message translates to:
  /// **'زغلول بيكتب'**
  String get insightsChartDetailTypingA11y;

  /// C · label on the tip line
  ///
  /// In ar, this message translates to:
  /// **'نصيحة'**
  String get insightsChartDetailTipLabel;

  /// C · with common_gold_badge; shown on the deep part
  ///
  /// In ar, this message translates to:
  /// **'تحليل أعمق'**
  String get insightsChartDetailDeepLabel;

  /// S · Free only, once under the basic tip, plus common_gold_unlock
  ///
  /// In ar, this message translates to:
  /// **'عايز تحليل أعمق؟ جولد بيقارن بالدورة اللي فاتت ويتوقع آخر الدورة.'**
  String get insightsChartDetailDeepUpsell;

  /// M · need:select (cycle/months/accounts/installments/subscriptions/other) · empty explainer
  ///
  /// In ar, this message translates to:
  /// **'{need, select, cycle{محتاج دورة كاملة علشان أشرحلك الشارت ده} months{محتاج تلات دورات علشان أقارنك بنفسك} accounts{ضيف حسابات أو أصول وأنا أشرحلك} installments{ضيف قسط أو التزام وأنا أشرحلك} subscriptions{لسه مفيش اشتراكات. أول ما ألاقي واحد هشرحلك} other{محتاج بيانات أكتر علشان أشرح الشارت ده}}'**
  String insightsChartDetailNeedsData(String need);

  /// N · bubble hidden, chart stays
  ///
  /// In ar, this message translates to:
  /// **'معرفتش أشرح الشارت ده دلوقتي'**
  String get insightsChartDetailExplainFailed;

  /// T · whole-screen locked state + common_gold_unlock
  ///
  /// In ar, this message translates to:
  /// **'الشارت ده في جولد'**
  String get insightsChartDetailLockedTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اتفرج على شكله، وافتحه كله مع جولد'**
  String get insightsChartDetailLockedBody;

  /// S · Gold deep, charts 1, 2, 3, 5, 7 · state:select(over/other). Only when a budget exists
  ///
  /// In ar, this message translates to:
  /// **'{state, select, over{بالسرعة دي هتقفل الدورة على {projected}، يعني فوق ميزانيتك} other{بالسرعة دي هتقفل الدورة على {projected}، يعني في حدود ميزانيتك}}'**
  String insightsDeepProjection(String state, String projected);

  /// S · Gold deep · only when three merchants qualify
  ///
  /// In ar, this message translates to:
  /// **'أكتر التجار اللي ورا التغيير: {merchant} و{merchant2} و{merchant3}'**
  String insightsDeepDrivers(
    String merchant,
    String merchant2,
    String merchant3,
  );

  /// E · state:select(short/other): short = spent more than earned. No emoji in the short branch
  ///
  /// In ar, this message translates to:
  /// **'{state, select, short{الدورة دي دخلك {income} وصرفت {spent}، يعني صرفت أكتر من دخلك بـ {gap}. خلينا نظبطها سوا.} other{الدورة دي دخلك {income} وصرفت {spent}، يعني حوشت {saved}. ده {percent} من دخلك. الله ينور!}}'**
  String insightsExplainCashFlowBasic(
    String state,
    String income,
    String spent,
    String gap,
    String saved,
    String percent,
  );

  /// S · state, category = largest category, target
  ///
  /// In ar, this message translates to:
  /// **'{state, select, short{قلل {category} بـ {target} الدورة الجاية وهتقفل بفايض.} other{حوّل {target} على الأقل من الفايض ده للادخار قبل ما يتصرف.}}'**
  String insightsExplainCashFlowTip(
    String state,
    String category,
    String target,
  );

  /// E · Gold · trend (up = better)
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{صافي الدورة دي أحسن من الدورة اللي فاتت بـ {delta}.} down{صافي الدورة دي أقل من الدورة اللي فاتت بـ {delta}.} other{صافي الدورة دي زي الدورة اللي فاتت تقريباً.}}'**
  String insightsExplainCashFlowDeep(String trend, String delta);

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'ثبّت هدف تحوّش {target} كل دورة، يعني {yearly} في السنة.'**
  String insightsExplainCashFlowDeepTip(String target, String yearly);

  /// E
  ///
  /// In ar, this message translates to:
  /// **'{category} واخد {percent} من صرفك، يعني {amount}. وبعده {category2} بـ {percent2}.'**
  String insightsExplainCategoriesBasic(
    String category,
    String percent,
    String amount,
    String category2,
    String percent2,
  );

  /// S
  ///
  /// In ar, this message translates to:
  /// **'حط سقف لـ{category} أقل بـ {target} من الدورة دي، وهتوفر الفرق.'**
  String insightsExplainCategoriesTip(String category, String target);

  /// E · Gold
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{{category} زاد عن الدورة اللي فاتت بـ {delta}.} down{{category} قل عن الدورة اللي فاتت بـ {delta}.} other{{category} تقريباً زي الدورة اللي فاتت.}}'**
  String insightsExplainCategoriesDeep(
    String trend,
    String category,
    String delta,
  );

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'خفّض {category} بـ {target} كل دورة، يعني {yearly} في السنة.'**
  String insightsExplainCategoriesDeepTip(
    String category,
    String target,
    String yearly,
  );

  /// E · state:select(over/other). perDay = BR-BUD-03
  ///
  /// In ar, this message translates to:
  /// **'{state, select, over{إنت في اليوم {cycleDay} من الدورة وصارف {spent} من {budget}، يعني فوق الخط المثالي. الباقي يكفي {perDay} في اليوم بس.} other{إنت في اليوم {cycleDay} من الدورة وصارف {spent} من {budget}، يعني تحت الخط المثالي. مسموحلك {perDay} في اليوم.}}'**
  String insightsExplainBurnRateBasic(
    String state,
    String cycleDay,
    String spent,
    String budget,
    String perDay,
  );

  /// S
  ///
  /// In ar, this message translates to:
  /// **'{state, select, over{نزّل صرفك اليومي لـ {perDay} لحد القبض علشان الميزانية تكفي.} other{كمّل على نفس الإيقاع، والفرق ده هيبقى فايض آخر الدورة. تقدر تصرف {perDay} في اليوم.}}'**
  String insightsExplainBurnRateTip(String state, String perDay);

  /// E · Gold · trend (up = spending more than last cycle)
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{في نفس اليوم الدورة اللي فاتت كنت صارف أقل بـ {delta}.} down{في نفس اليوم الدورة اللي فاتت كنت صارف أكتر بـ {delta}.} other{صرفك زي نفس اليوم في الدورة اللي فاتت تقريباً.}}'**
  String insightsExplainBurnRateDeep(String trend, String delta);

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'لو خفضت {target} من صرفك اليومي هتفضل تحت الخط لحد القبض.'**
  String insightsExplainBurnRateDeepTip(String target);

  /// E · state:select(wantsHigh/savingsLow/other). The rule is fifty, thirty, twenty; the chart title carries it
  ///
  /// In ar, this message translates to:
  /// **'{state, select, wantsHigh{صرفك الدورة دي: {needsPct} أساسيات و{wantsPct} رفاهيات و{savingsPct} تحويش. الرفاهيات أعلى من القاعدة المعروفة.} savingsLow{صرفك الدورة دي: {needsPct} أساسيات و{wantsPct} رفاهيات و{savingsPct} تحويش. التحويش أقل من القاعدة المعروفة.} other{صرفك الدورة دي: {needsPct} أساسيات و{wantsPct} رفاهيات و{savingsPct} تحويش. ده قريب من القاعدة المعروفة.}}'**
  String insightsExplainRule503020Basic(
    String state,
    String needsPct,
    String wantsPct,
    String savingsPct,
  );

  /// S
  ///
  /// In ar, this message translates to:
  /// **'{state, select, wantsHigh{نزّل الرفاهيات {target} الدورة الجاية وحوّلهم للتحويش.} savingsLow{حاول تزود التحويش {target} الدورة الجاية.} other{حافظ على التحويش ده، وزوده {target} لو قدرت.}}'**
  String insightsExplainRule503020Tip(String state, String target);

  /// E · Gold
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{التحويش زاد عن الدورة اللي فاتت لـ {savingsPct}.} down{التحويش نزل عن الدورة اللي فاتت لـ {savingsPct}.} other{التحويش ثابت تقريباً عن الدورة اللي فاتت.}}'**
  String insightsExplainRule503020Deep(String trend, String savingsPct);

  /// S · Gold · percent = the next 5-point step
  ///
  /// In ar, this message translates to:
  /// **'لو التحويش وصل لـ {percent}، هتحوّش {yearly} في السنة.'**
  String insightsExplainRule503020DeepTip(String percent, String yearly);

  /// E
  ///
  /// In ar, this message translates to:
  /// **'يوم {peakDay} و{peakDay2} واخدين {percent} من صرفك الأسبوعي، وأكتر وقت إيدك بتفرط فيه حوالين {time}.'**
  String insightsExplainWeekPatternBasic(
    String peakDay,
    String peakDay2,
    String percent,
    String time,
  );

  /// S
  ///
  /// In ar, this message translates to:
  /// **'حط سقف {target} ليوم {peakDay} الجاي.'**
  String insightsExplainWeekPatternTip(String target, String peakDay);

  /// E · Gold
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{متوسط صرفك يوم {peakDay} {amount}، وده أعلى من الدورة اللي فاتت.} down{متوسط صرفك يوم {peakDay} {amount}، وده أقل من الدورة اللي فاتت.} other{متوسط صرفك يوم {peakDay} {amount}، زي الدورة اللي فاتت تقريباً.}}'**
  String insightsExplainWeekPatternDeep(
    String trend,
    String peakDay,
    String amount,
  );

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'لو قللت خروجة {peakDay} بـ {target} كل أسبوع، هتوفر {yearly} في السنة.'**
  String insightsExplainWeekPatternDeepTip(
    String peakDay,
    String target,
    String yearly,
  );

  /// E · visits = common_unit_visits
  ///
  /// In ar, this message translates to:
  /// **'{merchant} في المركز الأول بـ {amount} ({visits})، وبعده {merchant2} بـ {amount2}.'**
  String insightsExplainMerchantsBasic(
    String merchant,
    String amount,
    String visits,
    String merchant2,
    String amount2,
  );

  /// S
  ///
  /// In ar, this message translates to:
  /// **'جمّع مشترياتك من {merchant} في زيارة واحدة كل أسبوع.'**
  String insightsExplainMerchantsTip(String merchant);

  /// E · Gold
  ///
  /// In ar, this message translates to:
  /// **'أول تلات تجار واخدين {percent} من صرفك. {trend, select, up{و{merchant} زاد عن الدورة اللي فاتت بـ {delta}.} down{و{merchant} قل عن الدورة اللي فاتت بـ {delta}.} other{و{merchant} زي الدورة اللي فاتت تقريباً.}}'**
  String insightsExplainMerchantsDeep(
    String percent,
    String trend,
    String merchant,
    String delta,
  );

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'لو قللت {merchant} بالربع هتوفر {target} في الدورة، يعني {yearly} في السنة.'**
  String insightsExplainMerchantsDeepTip(
    String merchant,
    String target,
    String yearly,
  );

  /// E · state:select(both/rise/drop/other). Needs three earlier cycles (insights_chartDetail_needsData)
  ///
  /// In ar, this message translates to:
  /// **'{state, select, both{{category} زاد {percent} عن متوسط آخر تلات دورات، لكن {category2} نزل {percent2}. برافو على ده.} rise{{category} زاد {percent} عن متوسط آخر تلات دورات.} drop{{category2} نزل {percent2} عن متوسط آخر تلات دورات. برافو عليك.} other{صرفك الدورة دي قريب من متوسط آخر تلات دورات.}}'**
  String insightsExplainVsAverageBasic(
    String state,
    String category,
    String percent,
    String category2,
    String percent2,
  );

  /// S
  ///
  /// In ar, this message translates to:
  /// **'{state, select, both{لو رجّعت {category} لمتوسطك هتوفر {target}.} rise{لو رجّعت {category} لمتوسطك هتوفر {target}.} drop{كمّل على نفس النظام في {category2}.} other{كمّل على نفس الإيقاع.}}'**
  String insightsExplainVsAverageTip(
    String state,
    String category,
    String target,
    String category2,
  );

  /// E · Gold
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{في الإجمالي إنت فوق متوسطك بـ {delta}.} down{في الإجمالي إنت تحت متوسطك بـ {delta}.} other{في الإجمالي إنت على متوسطك تقريباً.}}'**
  String insightsExplainVsAverageDeep(String trend, String delta);

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'حط حد لـ {category} على قد متوسطك، يعني {target} في الدورة.'**
  String insightsExplainVsAverageDeepTip(String category, String target);

  /// E · item = the next installment to finish
  ///
  /// In ar, this message translates to:
  /// **'الشهر ده عليك {sum} أقساط والتزامات. {item} هيخلص في {month}.'**
  String insightsExplainInstallmentsBasic(
    String sum,
    String item,
    String month,
  );

  /// S
  ///
  /// In ar, this message translates to:
  /// **'متدخلش في قسط جديد قبل ما {item} يخلص.'**
  String insightsExplainInstallmentsTip(String item);

  /// E · Gold
  ///
  /// In ar, this message translates to:
  /// **'في الستة شهور الجايين هتدفع {amount} كلهم، بمتوسط {average} في الشهر.'**
  String insightsExplainInstallmentsDeep(String amount, String average);

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'لما {item} يخلص هيفضل لك {monthly} كل شهر.'**
  String insightsExplainInstallmentsDeepTip(String item, String monthly);

  /// E
  ///
  /// In ar, this message translates to:
  /// **'الاشتراكات {monthly} في الشهر، يعني {yearly} في السنة. الصغير بيبان فكة، بس لما بيتجمع بيفرق.'**
  String insightsExplainSubscriptionsBasic(String monthly, String yearly);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'راجع {item}، ولو مش بتستخدمه إلغاؤه بيوفر {target} في السنة.'**
  String insightsExplainSubscriptionsTip(String item, String target);

  /// E · Gold
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{الاشتراكات زادت {delta} في الشهر عن تلات شهور فاتت.} down{الاشتراكات قلت {delta} في الشهر عن تلات شهور فاتت.} other{الاشتراكات ثابتة عن تلات شهور فاتت.}}'**
  String insightsExplainSubscriptionsDeep(String trend, String delta);

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'لو ألغيت أغلى اتنين مش بتستخدمهم هتوفر {target} في السنة.'**
  String insightsExplainSubscriptionsDeepTip(String target);

  /// E · state:select(credit/other): credit when the top card is a credit card with a limit
  ///
  /// In ar, this message translates to:
  /// **'{state, select, credit{{percent} من صرفك طلع من {card}، وبعده {card2} بـ {percent2}. استخدامك من ليميت الكريدت {utilisation}.} other{{percent} من صرفك طلع من {card}، وبعده {card2} بـ {percent2}.}}'**
  String insightsExplainCardsBasic(
    String state,
    String percent,
    String card,
    String card2,
    String percent2,
    String utilisation,
  );

  /// S
  ///
  /// In ar, this message translates to:
  /// **'{state, select, credit{خلّي استخدام الكريدت تحت النص وسدّده قبل ميعاده.} other{ركّز مصاريفك اليومية على كارت واحد علشان تتابعها أسهل.}}'**
  String insightsExplainCardsTip(String state);

  /// E · Gold · the apostrophe after a brace needs the early gen-l10n check (§0.10)
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{نصيب {card} من صرفك زاد عن الدورة اللي فاتت.} down{نصيب {card} من صرفك قل عن الدورة اللي فاتت.} other{نصيب {card} من صرفك ثابت عن الدورة اللي فاتت.}}'**
  String insightsExplainCardsDeep(String trend, String card);

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'صرفت {amount} من {card} الدورة دي. حط له سقف {target} للدورة الجاية.'**
  String insightsExplainCardsDeepTip(String amount, String card, String target);

  /// E · one currency or unit at a time, no cross-currency sum
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{اللي حيلتك زاد من {startAmount} في {month} لـ {endAmount} في {month2}.} down{اللي حيلتك نزل من {startAmount} في {month} لـ {endAmount} في {month2}.} other{اللي حيلتك ثابت تقريباً حوالين {endAmount}.}}'**
  String insightsExplainNetWorthBasic(
    String trend,
    String startAmount,
    String month,
    String endAmount,
    String month2,
  );

  /// S · assetType = common_assetType_*
  ///
  /// In ar, this message translates to:
  /// **'{assetType} هو أكبر جزء من اللي حيلتك بـ {percent}. خد بالك لو كله في حاجة واحدة.'**
  String insightsExplainNetWorthTip(String assetType, String percent);

  /// E · Gold
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{نموك الإجمالي {percent}، وأكتر حاجة زوّدته {assetType2}.} down{اللي حيلتك نزل {percent}، وأكتر حاجة أثرت فيه {assetType2}.} other{مفيش تغيير كبير في الفترة دي.}}'**
  String insightsExplainNetWorthDeep(
    String trend,
    String percent,
    String assetType2,
  );

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'بنفس المعدل ده ممكن توصل لـ {projected} بعد سنة. ده تقدير بس.'**
  String insightsExplainNetWorthDeepTip(String projected);

  /// E
  ///
  /// In ar, this message translates to:
  /// **'{trend, select, up{متوسط فاتورة السوبرماركت كان {startAmount} في {month} ودلوقتي {endAmount}، يعني زاد {percent}.} down{متوسط فاتورة السوبرماركت كان {startAmount} في {month} ودلوقتي {endAmount}، يعني نزل {percent}.} other{متوسط فاتورة السوبرماركت ثابت حوالين {endAmount}.}}'**
  String insightsExplainInflationBasic(
    String trend,
    String startAmount,
    String month,
    String endAmount,
    String percent,
  );

  /// S
  ///
  /// In ar, this message translates to:
  /// **'جرّب بدائل أرخص في {category}، هي أكتر حاجة سعرها زاد عليك.'**
  String insightsExplainInflationTip(String category);

  /// E · Gold · only when the delivery average rose; otherwise the sentence is dropped
  ///
  /// In ar, this message translates to:
  /// **'متوسط أوردر الدليفري بقى {average} بدل {previous}.'**
  String insightsExplainInflationDeep(String average, String previous);

  /// S · Gold
  ///
  /// In ar, this message translates to:
  /// **'لو نزّلت متوسط الفاتورة {target}، هتوفر {yearly} في السنة بنفس عدد الزيارات.'**
  String insightsExplainInflationDeepTip(String target, String yearly);

  /// L · cycle header, dates per common_date_*
  ///
  /// In ar, this message translates to:
  /// **'{start} لحد {end}'**
  String budgetOverviewCycle(String start, String end);

  /// C · count:int, n · includes today, so 0 can't occur
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{آخر يوم} =2{فاضل يومين} few{فاضل {n} أيام} many{فاضل {n} يوم} other{فاضل {n} يوم}}'**
  String budgetOverviewDaysLeft(int count, String n);

  /// L · shown when no payday is set (A-43)
  ///
  /// In ar, this message translates to:
  /// **'الشهر الميلادي'**
  String get budgetOverviewCalendarMonth;

  /// L · text link, opens S-72
  ///
  /// In ar, this message translates to:
  /// **'حدد يوم القبض'**
  String get budgetOverviewSetPayday;

  /// L · overall bar, with common_progress_percent
  ///
  /// In ar, this message translates to:
  /// **'{spent} من {budget}'**
  String budgetOverviewOverall(String spent, String budget);

  /// L · BR-BUD-03. At 0 use home_hero_budgetUsedUp
  ///
  /// In ar, this message translates to:
  /// **'مسموحلك {perDay} في اليوم'**
  String budgetOverviewSafePerDay(String perDay);

  /// S · FR-BUD-02, shown when the currency switcher is not EGP
  ///
  /// In ar, this message translates to:
  /// **'الميزانية دي بـ{currency} بس'**
  String budgetOverviewCurrencyNote(String currency);

  /// L · C-12
  ///
  /// In ar, this message translates to:
  /// **'{spent} / {limit}'**
  String budgetOverviewRowAmounts(String spent, String limit);

  /// C · 80–99% (default threshold)
  ///
  /// In ar, this message translates to:
  /// **'قربت تخلص'**
  String get budgetOverviewStatusNear;

  /// C · exactly 100%
  ///
  /// In ar, this message translates to:
  /// **'خلصت'**
  String get budgetOverviewStatusFull;

  /// C · above 100%, danger colour plus these words
  ///
  /// In ar, this message translates to:
  /// **'عدّت بـ {gap}'**
  String budgetOverviewStatusOver(String gap);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'{category}: صرفت {spent} من {limit}، {percent}'**
  String budgetOverviewRowA11y(
    String category,
    String spent,
    String limit,
    String percent,
  );

  /// L
  ///
  /// In ar, this message translates to:
  /// **'من غير ميزانية'**
  String get budgetOverviewNotBudgeted;

  /// S · opens S-11 filtered
  ///
  /// In ar, this message translates to:
  /// **'صرف في تصنيفات ملهاش حد'**
  String get budgetOverviewNotBudgetedSub;

  /// B · opens S-23
  ///
  /// In ar, this message translates to:
  /// **'عدّل الميزانية'**
  String get budgetOverviewEdit;

  /// A · arrow mirrors in RTL
  ///
  /// In ar, this message translates to:
  /// **'الدورة اللي قبلها'**
  String get budgetOverviewPrevA11y;

  /// A · arrow mirrors in RTL
  ///
  /// In ar, this message translates to:
  /// **'الدورة اللي بعدها'**
  String get budgetOverviewNextA11y;

  /// T · C-28, Rive tourGuide
  ///
  /// In ar, this message translates to:
  /// **'حط حدود وشوف مسموحلك تصرف كام'**
  String get budgetOverviewEmptyTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'صرف الدورة دي ظاهر تحت لحد ما تحط ميزانية.'**
  String get budgetOverviewEmptyBody;

  /// B · opens S-23
  ///
  /// In ar, this message translates to:
  /// **'حط ميزانية'**
  String get budgetOverviewEmptyAction;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'بحمّل الميزانية'**
  String get budgetOverviewLoadingA11y;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'الميزانية'**
  String get budgetEditTitle;

  /// L · picker, required (common_validation_currencyRequired)
  ///
  /// In ar, this message translates to:
  /// **'عملة الميزانية'**
  String get budgetEditCurrency;

  /// L · section
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get budgetEditOverall;

  /// L · radio
  ///
  /// In ar, this message translates to:
  /// **'مجموع التصنيفات'**
  String get budgetEditOverallSum;

  /// L · radio, shows an amount field
  ///
  /// In ar, this message translates to:
  /// **'إجمالي أحدده أنا'**
  String get budgetEditOverallSet;

  /// L · section
  ///
  /// In ar, this message translates to:
  /// **'حد كل تصنيف'**
  String get budgetEditCategories;

  /// S · under the fields, zero or blank = no budget
  ///
  /// In ar, this message translates to:
  /// **'سيبه فاضي لو مش عايز حد'**
  String get budgetEditLimitHint;

  /// L · FR-BUD-03
  ///
  /// In ar, this message translates to:
  /// **'نبّهني لما أوصل لـ'**
  String get budgetEditAlerts;

  /// L · percentage field
  ///
  /// In ar, this message translates to:
  /// **'التنبيه الأول'**
  String get budgetEditAlertFirst;

  /// L · percentage field
  ///
  /// In ar, this message translates to:
  /// **'التنبيه التاني'**
  String get budgetEditAlertSecond;

  /// L · switch, FR-BUD-05
  ///
  /// In ar, this message translates to:
  /// **'رحّل اللي فاضل للدورة الجاية'**
  String get budgetEditRollover;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اللي ما اتصرفش بيتضاف لميزانية الدورة الجاية.'**
  String get budgetEditRolloverHint;

  /// L · opens the annual list, FR-BUD-06
  ///
  /// In ar, this message translates to:
  /// **'ميزانيات سنوية'**
  String get budgetEditAnnual;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'للحاجات اللي بتتدفع مرة في السنة، زي المصاريف المدرسية'**
  String get budgetEditAnnualHint;

  /// L · opens the S-72 stepper
  ///
  /// In ar, this message translates to:
  /// **'يوم القبض'**
  String get budgetEditPayday;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الحد مينفعش يكون بالسالب'**
  String get budgetEditErrorLimit;

  /// S · min/max = 1 and 150
  ///
  /// In ar, this message translates to:
  /// **'النسبة لازم تبقى بين {min} و{max}'**
  String budgetEditErrorThreshold(String min, String max);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'التنبيه الأول لازم يبقى أقل من التاني'**
  String get budgetEditErrorOrder;

  /// N · success
  ///
  /// In ar, this message translates to:
  /// **'الميزانية اتحفظت ✓'**
  String get budgetEditSaved;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'ميزانيات سنوية'**
  String get budgetAnnualTitle;

  /// S · C-28 with budget_annual_add
  ///
  /// In ar, this message translates to:
  /// **'لسه مفيش ميزانيات سنوية'**
  String get budgetAnnualEmpty;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'ضيف ميزانية سنوية'**
  String get budgetAnnualAdd;

  /// S · due and subs are Money, one line per currency
  ///
  /// In ar, this message translates to:
  /// **'الشهر ده: {due} مستحقة · {subs} اشتراكات في الشهر'**
  String recurringBillsSummary(String due, String subs);

  /// M · Rive detective · BR-SUB-01
  ///
  /// In ar, this message translates to:
  /// **'لقيت اشتراك: {merchant} بـ {amount} في الشهر'**
  String recurringBillsDetected(String merchant, String amount);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'تابعه'**
  String get recurringBillsTrack;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'مش اشتراك'**
  String get recurringBillsNotSub;

  /// L · C-36 timeline
  ///
  /// In ar, this message translates to:
  /// **'اللي جاي'**
  String get recurringBillsUpcoming;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'{name} · القسط {index} من {total}'**
  String recurringBillsInstallmentRow(String name, String index, String total);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'آخر قسط'**
  String get recurringBillsLastOne;

  /// B · glossary «اتدفع»
  ///
  /// In ar, this message translates to:
  /// **'اتدفع'**
  String get recurringBillsMarkPaid;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'اتدفع ✓'**
  String get recurringBillsPaid;

  /// L · FR-SUB-05
  ///
  /// In ar, this message translates to:
  /// **'اتسجل لوحده من الحركة'**
  String get recurringBillsAutoPaid;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'النهارده'**
  String get recurringBillsDueToday;

  /// C · count:int, n · 0 is recurring_bills_dueToday
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{بكرة} =2{بعد يومين} few{بعد {n} أيام} many{بعد {n} يوم} other{بعد {n} يوم}}'**
  String recurringBillsDueIn(int count, String n);

  /// C · count:int, n · danger colour plus these words, no emoji
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{متأخر يوم} =2{متأخر يومين} few{متأخر {n} أيام} many{متأخر {n} يوم} other{متأخر {n} يوم}}'**
  String recurringBillsOverdue(int count, String n);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'اشتراك'**
  String get recurringBillsKindSubscription;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'قسط'**
  String get recurringBillsKindInstallment;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'سداد كارت'**
  String get recurringBillsKindCard;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'جمعية'**
  String get recurringBillsKindGameya;

  /// S · A-17
  ///
  /// In ar, this message translates to:
  /// **'الجمعية بتتسجل بإيدك'**
  String get recurringBillsGameyaManual;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الاشتراكات'**
  String get recurringBillsSubsTitle;

  /// C · the ×12 column header (FR-SUB-02)
  ///
  /// In ar, this message translates to:
  /// **'في السنة كلها'**
  String get recurringBillsSubsYear;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'{monthly} في الشهر · {yearly} في السنة'**
  String recurringBillsSubRow(String monthly, String yearly);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'المجموع {monthly} في الشهر، يعني {yearly} في السنة'**
  String recurringBillsSubsTotal(String monthly, String yearly);

  /// L · text button, opens S-25
  ///
  /// In ar, this message translates to:
  /// **'ضيف فاتورة أو قسط'**
  String get recurringBillsAdd;

  /// T · C-28, Rive tourGuide
  ///
  /// In ar, this message translates to:
  /// **'لسه مفيش فواتير ولا أقساط'**
  String get recurringBillsEmptyTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'هلاقي الاشتراكات لوحدي من حركاتك، وتقدر تضيف أي قسط بإيدك.'**
  String get recurringBillsEmptyBody;

  /// N + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'اتسجل إن {name} اتدفع ✓'**
  String recurringBillsPaidSnack(String name);

  /// A · status = recurring_bills_dueToday / dueIn / overdue / paid
  ///
  /// In ar, this message translates to:
  /// **'{name}، {amount}، {status}'**
  String recurringBillsRowA11y(String name, String amount, String status);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'ضيف فاتورة أو قسط'**
  String get recurringBillEditTitleAdd;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'عدّل الفاتورة'**
  String get recurringBillEditTitleEdit;

  /// L · segments use recurring_bills_kind*
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get recurringBillEditType;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الاسم'**
  String get recurringBillEditName;

  /// L · hint text
  ///
  /// In ar, this message translates to:
  /// **'مثلاً: قسط التلاجة'**
  String get recurringBillEditNamePlaceholder;

  /// L · C-22, currency picker beside it
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get recurringBillEditAmount;

  /// L · options common_cadence_*
  ///
  /// In ar, this message translates to:
  /// **'بيتكرر'**
  String get recurringBillEditRepeats;

  /// L · may be in the future
  ///
  /// In ar, this message translates to:
  /// **'الدفعة الجاية'**
  String get recurringBillEditNextDue;

  /// L · installments and gameya only
  ///
  /// In ar, this message translates to:
  /// **'اتدفع'**
  String get recurringBillEditPaid;

  /// C · between the two number fields
  ///
  /// In ar, this message translates to:
  /// **'من'**
  String get recurringBillEditPaidOf;

  /// L · count:int, n · stepper 0–30, default 3 (BR-SUB-03)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{فكّرني يوم الميعاد} =1{فكّرني قبلها بيوم} =2{فكّرني قبلها بيومين} few{فكّرني قبلها بـ {n} أيام} many{فكّرني قبلها بـ {n} يوم} other{فكّرني قبلها بـ {n} يوم}}'**
  String recurringBillEditRemind(int count, String n);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الحساب (اختياري)'**
  String get recurringBillEditAccount;

  /// T · destructive, no emoji
  ///
  /// In ar, this message translates to:
  /// **'تمسح {name}؟'**
  String recurringBillEditDeleteTitle(String name);

  /// S · confirm button common_action_delete, cancel common_action_cancel. Assumption, see Q-22
  ///
  /// In ar, this message translates to:
  /// **'هتتشال من الفواتير. الحركات اللي اتسجلت قبل كده مش هتتمسح.'**
  String get recurringBillEditDeleteBody;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اللي اتدفع مينفعش يزيد عن الإجمالي'**
  String get recurringBillEditErrorPaid;

  /// S · max = 120
  ///
  /// In ar, this message translates to:
  /// **'عدد الدفعات لازم يبقى من واحد لـ {max}'**
  String recurringBillEditErrorTotal(String max);

  /// S · max = 30
  ///
  /// In ar, this message translates to:
  /// **'التذكير من صفر لـ {max} يوم'**
  String recurringBillEditErrorRemind(String max);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار ميعاد الدفعة الجاية'**
  String get recurringBillEditErrorDue;

  /// N · success
  ///
  /// In ar, this message translates to:
  /// **'الفاتورة اتحفظت ✓'**
  String get recurringBillEditSaved;

  /// S · Free only (FR-VOI-04)
  ///
  /// In ar, this message translates to:
  /// **'فاضل {remaining} من {max} تسجيل صوتي الشهر ده'**
  String homeQuickAddVoiceLeft(String remaining, String max);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'قول اللي دفعته'**
  String get voiceLoggerTitle;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'مثلاً'**
  String get voiceLoggerExampleLabel;

  /// S · FR-VOI-02/05. Egyptian number words, so the Arabic has no digits
  ///
  /// In ar, this message translates to:
  /// **'دفعت ميت وخمسين جنيه خضار وخمسة وأربعين قهوة وتلاتين تاكسي'**
  String get voiceLoggerExample;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'بسمعك…'**
  String get voiceLoggerListening;

  /// B · stop button, the record icon doesn't mirror
  ///
  /// In ar, this message translates to:
  /// **'خلصت'**
  String get voiceLoggerDone;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'وقّف التسجيل'**
  String get voiceLoggerStopA11y;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'اللي سمعته لحد دلوقتي: {text}'**
  String voiceLoggerTranscriptA11y(String text);

  /// L · up to 2 s (NFR-PERF-05), Rive thinking
  ///
  /// In ar, this message translates to:
  /// **'بفهم اللي قلته…'**
  String get voiceLoggerUnderstanding;

  /// T · count:int, n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{فهمت حاجة واحدة} =2{فهمت حاجتين} few{فهمت {n} حاجات} many{فهمت {n} حاجة} other{فهمت {n} حاجة}}'**
  String voiceLoggerParsedTitle(int count, String n);

  /// L · applies to all items
  ///
  /// In ar, this message translates to:
  /// **'الحساب'**
  String get voiceLoggerAccount;

  /// L · applies to all items
  ///
  /// In ar, this message translates to:
  /// **'إمتى'**
  String get voiceLoggerWhen;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'بينطبق على الكل'**
  String get voiceLoggerApplyAll;

  /// C · error state on an item (EC-30). Save is disabled until it is fixed or removed
  ///
  /// In ar, this message translates to:
  /// **'المبلغ كام؟'**
  String get voiceLoggerAmountMissing;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'عدّل البند ده'**
  String get voiceLoggerEditA11y;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'شيل البند ده'**
  String get voiceLoggerRemoveA11y;

  /// B · count:int, n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{احفظ} =2{احفظ الاتنين} few{احفظ {n}} many{احفظ {n}} other{احفظ {n}}}'**
  String voiceLoggerSave(int count, String n);

  /// N + common_action_undo · count:int, n · one voice log counts once (A-14)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{اتسجلت حركة واحدة ✓} =2{اتسجلت حركتين ✓} few{اتسجلوا {n} حركات ✓} many{اتسجلوا {n} حركة ✓} other{اتسجلوا {n} حركة ✓}}'**
  String voiceLoggerSaved(int count, String n);

  /// T · actions common_action_tryAgain and common_action_typeInstead
  ///
  /// In ar, this message translates to:
  /// **'مسمعتش مبلغ'**
  String get voiceLoggerEmptyTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'جرّب تقول: «ميت وخمسين خضار»'**
  String get voiceLoggerEmptyBody;

  /// T · EC-32, Rive oops. Action common_action_typeInstead
  ///
  /// In ar, this message translates to:
  /// **'الصوت بالعربي مش شغال على الموبايل ده'**
  String get voiceLoggerUnavailable;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'تقدر تكتب الحركة بإيدك في ثواني.'**
  String get voiceLoggerUnavailableBody;

  /// T · D-42, only if on-device Arabic isn't available
  ///
  /// In ar, this message translates to:
  /// **'نستخدم التعرف على الصوت أونلاين؟'**
  String get voiceLoggerOnlineTitle;

  /// E · platform:select(ios/other) · explicit consent, no jokes. Privacy review of the wording: Q-21
  ///
  /// In ar, this message translates to:
  /// **'موبايلك مفيهوش تعرّف على العربي من غير نت. لو وافقت، خدمة الكلام بتاعة {platform, select, ios{آبل} other{جوجل}} هتحوّل صوتك لنص أونلاين. زغلول مش بيحتفظ بالتسجيل.'**
  String voiceLoggerOnlineBody(String platform);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'وافق'**
  String get voiceLoggerOnlineAllow;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'لأ، هكتب'**
  String get voiceLoggerOnlineDeny;

  /// T · C-25
  ///
  /// In ar, this message translates to:
  /// **'محتاج الميكروفون'**
  String get voiceLoggerMicTitle;

  /// S · plus common_action_openSettings and common_action_typeInstead
  ///
  /// In ar, this message translates to:
  /// **'علشان أسمع اللي بتقوله. مش بحتفظ بتسجيل صوتك.'**
  String get voiceLoggerMicBody;

  /// T · Free, 15 used (A-15)
  ///
  /// In ar, this message translates to:
  /// **'خلّصت تسجيلاتك الصوتية الشهر ده'**
  String get voiceLoggerLimitTitle;

  /// S · plus common_gold_unlock and common_action_typeInstead
  ///
  /// In ar, this message translates to:
  /// **'استخدمت {max} تسجيل صوتي الشهر ده، وبيرجعوا أول الشهر الجاي. جولد من غير حدود.'**
  String voiceLoggerLimitBody(String max);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'قراءة سكرين شوت'**
  String get captureScanTitle;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اختار صورة'**
  String get captureScanChoose;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اختار صورة تانية'**
  String get captureScanChooseAnother;

  /// L · Rive scanning
  ///
  /// In ar, this message translates to:
  /// **'بقرا الصورة…'**
  String get captureScanReading;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الصورة بتتقري على موبايلك.'**
  String get captureScanOnDevice;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'ده اللي لقيته'**
  String get captureScanFound;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get captureScanAmount;

  /// L · counterparty, often an IPA handle (LTR)
  ///
  /// In ar, this message translates to:
  /// **'لمين / من مين'**
  String get captureScanParty;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'رقم العملية'**
  String get captureScanReference;

  /// L · validation common_validation_dateFuture
  ///
  /// In ar, this message translates to:
  /// **'إمتى'**
  String get captureScanDate;

  /// L · required
  ///
  /// In ar, this message translates to:
  /// **'التصنيف'**
  String get captureScanCategory;

  /// L · required (common_validation_accountRequired)
  ///
  /// In ar, this message translates to:
  /// **'الحساب'**
  String get captureScanAccount;

  /// A · pencil next to each found field
  ///
  /// In ar, this message translates to:
  /// **'عدّل'**
  String get captureScanEditA11y;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'ده اللي فهمته من الصورة اللي بعتها. راجعه واحفظ.'**
  String get captureScanFromShare;

  /// T · Rive oops; actions capture_scan_chooseAnother and common_action_typeInstead
  ///
  /// In ar, this message translates to:
  /// **'مش لاقي دفعة في الصورة دي'**
  String get captureScanEmptyTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'جرّب صورة أوضح، أو اكتب الحركة بإيدك.'**
  String get captureScanEmptyBody;

  /// T · same amount and reference or time
  ///
  /// In ar, this message translates to:
  /// **'اتسجلت قبل كده من رسالة البنك'**
  String get captureScanDuplicateTitle;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'شوفها'**
  String get captureScanDuplicateView;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'احفظها برضه'**
  String get captureScanDuplicateSave;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الملف ده مش صورة أقدر أقراها'**
  String get captureScanUnsupported;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'محتاج أشوف صورك'**
  String get captureScanPhotoTitle;

  /// S · plus common_action_openSettings
  ///
  /// In ar, this message translates to:
  /// **'علشان تختار السكرين شوت. ببص على الصورة اللي تختارها بس.'**
  String get captureScanPhotoBody;

  /// L · one hero line per karat. grams = common_unit_grams
  ///
  /// In ar, this message translates to:
  /// **'دهب عيار {karat}: {grams}'**
  String wealthOverviewUnitGold(String karat, String grams);

  /// L · count:int, n · hero line, shown only when coins are held
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{جنيه دهب واحد} =2{جنيهين دهب} few{{n} جنيهات دهب} many{{n} جنيه دهب} other{{n} جنيه دهب}}'**
  String wealthOverviewUnitCoins(int count, String n);

  /// A · list = the hero lines joined with the locale list format
  ///
  /// In ar, this message translates to:
  /// **'اللي حيلتك كله: {list}'**
  String wealthOverviewUnitsA11y(String list);

  /// L · asset row
  ///
  /// In ar, this message translates to:
  /// **'دهب عيار {karat}'**
  String wealthOverviewGoldTitle(String karat);

  /// L · value = grams × price. Stale price adds common_badge_stale
  ///
  /// In ar, this message translates to:
  /// **'{grams} · ≈ {value}'**
  String wealthOverviewGoldSub(String grams, String value);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'شهادة {bank}'**
  String wealthOverviewCertTitle(String bank);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'عائد {percent} · {principal}'**
  String wealthOverviewCertSub(String percent, String principal);

  /// L · FR-WLT-04
  ///
  /// In ar, this message translates to:
  /// **'الصرف الجاي {date}: {payout}'**
  String wealthOverviewCertPayout(String date, String payout);

  /// C · stocks, property and car rows
  ///
  /// In ar, this message translates to:
  /// **'قيمة تقديرية'**
  String get wealthOverviewManualValue;

  /// S · EC-35
  ///
  /// In ar, this message translates to:
  /// **'مفيش سعر لـ {currency} لسه، فهو ظاهر بعملته بس'**
  String wealthOverviewNoRate(String currency);

  /// S · Gold, plus accounts_overview_addAsset
  ///
  /// In ar, this message translates to:
  /// **'لسه ماضفتش أصول. ضيف دهبك أو شهاداتك.'**
  String get wealthOverviewAssetsEmpty;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'{name}، {value}'**
  String wealthOverviewAssetRowA11y(String name, String value);

  /// C · count:int, n · trailing text on the accounts_overview_hiddenEntry row, which exists only while 1 or more accounts are hidden
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{حساب واحد} =2{حسابين} few{{n} حسابات} many{{n} حساب} other{{n} حساب}}'**
  String accountsOverviewHiddenCount(int count, String n);

  /// T · the hidden list's title (same words as accounts_overview_hiddenEntry)
  ///
  /// In ar, this message translates to:
  /// **'الحسابات المخفية'**
  String get accountsHiddenTitle;

  /// S · D-69
  ///
  /// In ar, this message translates to:
  /// **'الحسابات دي مش ظاهرة في القوايم، بس حركاتها لسه محسوبة في الأرقام والميزانية والشارتات.'**
  String get accountsHiddenIntro;

  /// B · on each row, no confirmation needed
  ///
  /// In ar, this message translates to:
  /// **'رجّعه'**
  String get accountsHiddenUnhide;

  /// N + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'الحساب رجع للقايمة'**
  String get accountsHiddenUnhidden;

  /// S · C-28, shown if the user unhides the last one while the list is open
  ///
  /// In ar, this message translates to:
  /// **'مفيش حسابات مخفية'**
  String get accountsHiddenEmpty;

  /// A · opens S-43
  ///
  /// In ar, this message translates to:
  /// **'{card}، مخفي. اضغط تفتح الحساب'**
  String accountsHiddenRowA11y(String card);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'ضيف أصل'**
  String get wealthAssetTitleAdd;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'عدّل الأصل'**
  String get wealthAssetTitleEdit;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get wealthAssetType;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'اختياري'**
  String get wealthAssetOptional;

  /// L · options common_karat_label and common_karat_coin
  ///
  /// In ar, this message translates to:
  /// **'العيار'**
  String get wealthAssetGoldKarat;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الوزن بالجرام'**
  String get wealthAssetGoldGrams;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'لحد تلات أرقام بعد العلامة'**
  String get wealthAssetGoldGramsHint;

  /// L · when the karat option is the coin
  ///
  /// In ar, this message translates to:
  /// **'عدد الجنيهات'**
  String get wealthAssetCoinCount;

  /// L · hawl start for Zakah
  ///
  /// In ar, this message translates to:
  /// **'اشتريته إمتى'**
  String get wealthAssetBoughtOn;

  /// L · optional, with a currency picker
  ///
  /// In ar, this message translates to:
  /// **'دفعت فيه كام'**
  String get wealthAssetPricePaid;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'البنك'**
  String get wealthAssetCertBank;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get wealthAssetCertPrincipal;

  /// L · percent field
  ///
  /// In ar, this message translates to:
  /// **'نسبة العائد'**
  String get wealthAssetCertRate;

  /// L · options common_cadence_*
  ///
  /// In ar, this message translates to:
  /// **'العائد بيتصرف'**
  String get wealthAssetCertPayout;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'بتخلص إمتى'**
  String get wealthAssetCertMaturity;

  /// L · any ISO currency
  ///
  /// In ar, this message translates to:
  /// **'العملة'**
  String get wealthAssetCashCurrency;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get wealthAssetCashAmount;

  /// L · stocks, property, car
  ///
  /// In ar, this message translates to:
  /// **'الاسم'**
  String get wealthAssetName;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'عملة التداول'**
  String get wealthAssetStocksCurrency;

  /// L · entered by hand
  ///
  /// In ar, this message translates to:
  /// **'القيمة الحالية'**
  String get wealthAssetValue;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اكتبها بإيدك وحدّثها من وقت للتاني.'**
  String get wealthAssetValueHint;

  /// T · destructive, no emoji
  ///
  /// In ar, this message translates to:
  /// **'تمسح الأصل ده؟'**
  String get wealthAssetDeleteTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'هيتشال من اللي حيلتك كله ومن أي حساب مبني عليه.'**
  String get wealthAssetDeleteBody;

  /// N · success
  ///
  /// In ar, this message translates to:
  /// **'الأصل اتحفظ ✓'**
  String get wealthAssetSaved;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار نوع الأصل'**
  String get wealthAssetErrorType;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الوزن لازم يبقى أكبر من صفر'**
  String get wealthAssetErrorGrams;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'لحد تلات أرقام بعد العلامة بس'**
  String get wealthAssetErrorGramsDecimals;

  /// S · max = 100
  ///
  /// In ar, this message translates to:
  /// **'العائد من صفر لـ {max}٪'**
  String wealthAssetErrorRate(String max);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الانتهاء لازم يبقى بعد تاريخ الشراء'**
  String get wealthAssetErrorMaturity;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'الأسعار'**
  String get wealthPricesTitle;

  /// L · when = date and time or common_date_hoursAgo
  ///
  /// In ar, this message translates to:
  /// **'اتحدثت {when}'**
  String wealthPricesUpdated(String when);

  /// L · rows use common_karat_label
  ///
  /// In ar, this message translates to:
  /// **'الدهب (سعر الجرام)'**
  String get wealthPricesGoldSection;

  /// L · only currencies the user holds, plus featured ones
  ///
  /// In ar, this message translates to:
  /// **'العملات مقابل {currency}'**
  String wealthPricesCurrenciesSection(String currency);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'عيار {karat}: {price} للجرام'**
  String wealthPricesGoldRowA11y(String karat, String price);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'{currency}: {rate}'**
  String wealthPricesCurrencyRowA11y(String currency, String rate);

  /// L · text button on each row
  ///
  /// In ar, this message translates to:
  /// **'غيّر السعر'**
  String get wealthPricesOverride;

  /// T · sheet
  ///
  /// In ar, this message translates to:
  /// **'سعرك إنت'**
  String get wealthPricesOverrideTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'السعر بـ {currency}'**
  String wealthPricesOverrideField(String currency);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'استخدم سعري'**
  String get wealthPricesOverrideUse;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'السعر اللي بتحطه بيتستخدم لحد ما ترجّع الأصلي.'**
  String get wealthPricesOverrideNote;

  /// C · badge on overridden rows
  ///
  /// In ar, this message translates to:
  /// **'سعرك'**
  String get wealthPricesYours;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'رجّع الأصلي'**
  String get wealthPricesReset;

  /// T · Rive sleep
  ///
  /// In ar, this message translates to:
  /// **'لسه ما نزّلتش الأسعار'**
  String get wealthPricesNeverTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اتصل بالنت مرة، أو اكتب السعر بإيدك.'**
  String get wealthPricesNeverBody;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اكتب السعر بإيدك'**
  String get wealthPricesEnterManually;

  /// N · EC-34
  ///
  /// In ar, this message translates to:
  /// **'مقدرتش أحدّث الأسعار. شايف آخر سعر معروف.'**
  String get wealthPricesFetchFailed;

  /// S · NFR-PRIV-03. It speaks about financial data only
  ///
  /// In ar, this message translates to:
  /// **'تحديث الأسعار مبيبعتش أي حاجة عن فلوسك أو أصولك.'**
  String get wealthPricesPrivacy;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'الزكاة'**
  String get zakahMainTitle;

  /// S · always visible (FR-ZAK-05), above the disclaimer
  ///
  /// In ar, this message translates to:
  /// **'ده تقدير تقريبي مش فتوى. اسأل أهل العلم قبل ما تخرج زكاتك.'**
  String get zakahMainDisclaimerSummary;

  /// S · simple standard Arabic (disclaimer exception). Legal and scholar sign-off: Q-23
  ///
  /// In ar, this message translates to:
  /// **'هذا الحساب تقديري وليس فتوى. يُرجى مراجعة أهل العلم قبل إخراج الزكاة.'**
  String get zakahMainDisclaimer;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'النصاب اتحقق'**
  String get zakahMainNisabReached;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'لسه مفيش نصاب'**
  String get zakahMainNisabNotReached;

  /// S · grams = common_unit_grams (BR-ZAK-01)
  ///
  /// In ar, this message translates to:
  /// **'النصاب {grams} من الدهب عيار {karat}، يعني حوالين {value}'**
  String zakahMainNisabInfo(String grams, String karat, String value);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'حسابك تحت النصاب دلوقتي، فالتقدير مفيهوش مبلغ مستحق. هفضل أتابع معاك.'**
  String get zakahMainNisabNotReachedBody;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'دهب عيار {karat} · {grams}'**
  String zakahMainLotGold(String karat, String grams);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كاش وأرصدة بـ{currency}: {amount}'**
  String zakahMainLotCash(String currency, String amount);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'أسهم وصناديق بـ{currency}: {amount}'**
  String zakahMainLotInvest(String currency, String amount);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'شهادات بنك: {amount}'**
  String zakahMainLotCertificate(String amount);

  /// L · BR-ZAK-04
  ///
  /// In ar, this message translates to:
  /// **'بعد خصم الديون المستحقة {debts}'**
  String zakahMainDebtsLine(String debts);

  /// L · BR-ZAK-02
  ///
  /// In ar, this message translates to:
  /// **'الحول: {done} من {total} يوم'**
  String zakahMainHawlProgress(String done, String total);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الحول تم'**
  String get zakahMainHawlDone;

  /// L · count:int, n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{هتستحق بكرة} =2{هتستحق بعد يومين} few{هتستحق بعد {n} أيام} many{هتستحق بعد {n} يوم} other{هتستحق بعد {n} يوم}}'**
  String zakahMainDueIn(int count, String n);

  /// C · the due date in the Hijri calendar
  ///
  /// In ar, this message translates to:
  /// **'هجري: {hijri}'**
  String zakahMainDueHijri(String hijri);

  /// L · native unit (grams of gold, or the currency), FR-ZAK-03
  ///
  /// In ar, this message translates to:
  /// **'المستحق: {dueNative}'**
  String zakahMainDue(String dueNative);

  /// L · cost in EGP, with common_currency_approxCaption
  ///
  /// In ar, this message translates to:
  /// **'تقريباً {cost}'**
  String zakahMainDueCost(String cost);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'حالة الدفع'**
  String get zakahMainStatusLabel;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'لسه'**
  String get zakahMainStatusPending;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'اتدفع جزء'**
  String get zakahMainStatusPartial;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'اتدفعت'**
  String get zakahMainStatusPaid;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'اتدفعت يوم {date}'**
  String zakahMainPaidOn(String date);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الأسعار قديمة، فالمبالغ بالجنيه تقريبية.'**
  String get zakahMainStaleNote;

  /// T · C-28
  ///
  /// In ar, this message translates to:
  /// **'ضيف أصل علشان نحسب الزكاة'**
  String get zakahMainEmptyTitle;

  /// B · opens S-44
  ///
  /// In ar, this message translates to:
  /// **'ضيف أصل'**
  String get zakahMainEmptyAdd;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'بتتحسب إزاي؟'**
  String get zakahMainHowTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'النصاب {grams} دهب عيار {karat}، بسعر النهارده.'**
  String zakahMainHowNisab(String grams, String karat);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الحول سنة هجرية، يعني {days} يوم من يوم ما حصلت على الأصل.'**
  String zakahMainHowHawl(String days);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'المستحق {percent} من كل أصل بوحدته: الدهب بالجرام والكاش بعملته.'**
  String zakahMainHowRate(String percent);

  /// S · BR-ZAK-03
  ///
  /// In ar, this message translates to:
  /// **'دهب عيار {karat} بيتحسب بنسبة {percent} ناحية النصاب.'**
  String zakahMainHowPurity(String karat, String percent);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الديون اللي ميعادها جه بتتخصم من الكاش قبل الحساب.'**
  String get zakahMainHowDebts;

  /// A · status = zakah_main_status*
  ///
  /// In ar, this message translates to:
  /// **'{lot}، {status}، المستحق {dueNative}'**
  String zakahMainLotA11y(String lot, String status, String dueNative);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'اسأل'**
  String get chatMainSegAsk;

  /// C · flag only
  ///
  /// In ar, this message translates to:
  /// **'نصايح'**
  String get chatMainSegTips;

  /// M · Rive tourGuide, first open
  ///
  /// In ar, this message translates to:
  /// **'اسألني أي حاجة عن فلوسك، بالمصري أو بالإنجليزي. بجاوبك من بياناتك اللي على موبايلك.'**
  String get chatMainGreeting;

  /// L · glossary. EN is shorter than the AR
  ///
  /// In ar, this message translates to:
  /// **'اسألني أي حاجة عن فلوسك…'**
  String get chatMainInputHint;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'ابعت السؤال'**
  String get chatMainSendA11y;

  /// S · count:int = 300, n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{السؤال ميزيدش عن حرف واحد} =2{السؤال ميزيدش عن حرفين} few{السؤال ميزيدش عن {n} حروف} many{السؤال ميزيدش عن {n} حرف} other{السؤال ميزيدش عن {n} حرف}}'**
  String chatMainTooLong(int count, String n);

  /// L · the card filter applies to answers
  ///
  /// In ar, this message translates to:
  /// **'الإجابات على {cards}'**
  String chatMainFilterNote(String cards);

  /// L · toggle. The 🔥 is an icon, not text
  ///
  /// In ar, this message translates to:
  /// **'إقصف جبهتي'**
  String get chatMainRoast;

  /// S · R9
  ///
  /// In ar, this message translates to:
  /// **'بيغيّر الأسلوب بس، والأرقام زي ما هي.'**
  String get chatMainRoastHint;

  /// L · overflow menu
  ///
  /// In ar, this message translates to:
  /// **'امسح المحادثة'**
  String get chatMainClear;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'المحادثة اتمسحت'**
  String get chatMainCleared;

  /// L · opens S-11 with the same filters
  ///
  /// In ar, this message translates to:
  /// **'افتح في الحركات'**
  String get chatMainOpenTransactions;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'زغلول بيكتب'**
  String get chatMainTypingA11y;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'إنت قلت: {text}'**
  String chatMainUserA11y(String text);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'زغلول رد: {text}'**
  String chatMainZaghlolA11y(String text);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'رسم صغير بيقارن الأرقام اللي فوق'**
  String get chatMainChartA11y;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'صرفت كام على القهوة؟'**
  String get chatChipCoffee;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'أكتر أماكن بصرف فيها'**
  String get chatChipTopMerchants;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'إيه الفواتير الجاية؟'**
  String get chatChipDues;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'فاضلي كام في الميزانية؟'**
  String get chatChipBudgetLeft;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'إيه أكبر حاجة صرفتها؟'**
  String get chatChipBiggest;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'حوشت كام الشهر ده؟'**
  String get chatChipSavings;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'قارن الشهر ده باللي فات'**
  String get chatChipCompare;

  /// L · only for a card the user has
  ///
  /// In ar, this message translates to:
  /// **'صرفت كام بكارت {card}؟'**
  String chatChipCard(String card);

  /// M · FR-CHAT-03; three chips follow. No number is ever made up
  ///
  /// In ar, this message translates to:
  /// **'لسه مبعرفش أجاوب على ده. جرّب واحد من دول:'**
  String get chatFallbackText;

  /// M · slot ambiguous; candidates appear as chips
  ///
  /// In ar, this message translates to:
  /// **'تقصد أنهي واحد؟'**
  String get chatAnswerPickOne;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'النهارده'**
  String get chatPeriodToday;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'امبارح'**
  String get chatPeriodYesterday;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الأسبوع ده'**
  String get chatPeriodThisWeek;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الأسبوع اللي فات'**
  String get chatPeriodLastWeek;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الدورة دي'**
  String get chatPeriodThisCycle;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الدورة اللي فاتت'**
  String get chatPeriodLastCycle;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الشهر ده'**
  String get chatPeriodThisMonth;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الشهر اللي فات'**
  String get chatPeriodLastMonth;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'من أول السنة'**
  String get chatPeriodSinceYearStart;

  /// L · count:int, n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{في آخر شهر} =2{في آخر شهرين} few{في آخر {n} شهور} many{في آخر {n} شهر} other{في آخر {n} شهر}}'**
  String chatPeriodLastMonths(int count, String n);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'من {start} لحد {end}'**
  String chatPeriodRange(String start, String end);

  /// L · count:int, n · for upcoming dues
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{بكرة} =2{في اليومين الجايين} few{في الـ {n} أيام الجايين} many{في الـ {n} يوم الجايين} other{في الـ {n} يوم الجايين}}'**
  String chatPeriodNextDays(int count, String n);

  /// C
  ///
  /// In ar, this message translates to:
  /// **'لحد القبض'**
  String get chatPeriodUntilPayday;

  /// L · printed before each answer when there are 2+ currencies
  ///
  /// In ar, this message translates to:
  /// **'بـ{currency}:'**
  String chatAnswerCurrencyLead(String currency);

  /// E · spend_on
  ///
  /// In ar, this message translates to:
  /// **'صرفت {amount} على {subject} {span}.'**
  String chatAnswerSpendOn(String amount, String subject, String span);

  /// E · times = common_unit_visits or common_unit_orders
  ///
  /// In ar, this message translates to:
  /// **'صرفت {amount} على {subject} {span} في {times}.'**
  String chatAnswerSpendOnCount(
    String amount,
    String subject,
    String span,
    String times,
  );

  /// E · trend:select(up/down/other)
  ///
  /// In ar, this message translates to:
  /// **'صرفت {amount} {span}، {trend, select, up{أكتر من {spanB} بـ {delta}} down{أقل من {spanB} بـ {delta}} other{زي {spanB} تقريباً}}.'**
  String chatAnswerCompare(
    String amount,
    String span,
    String trend,
    String spanB,
    String delta,
  );

  /// E
  ///
  /// In ar, this message translates to:
  /// **'أكتر الأماكن {span}: {list}.'**
  String chatAnswerTopMerchants(String span, String list);

  /// E
  ///
  /// In ar, this message translates to:
  /// **'رصيد {account} {amount}، آخر تحديث {when}.'**
  String chatAnswerBalance(String account, String amount, String when);

  /// E
  ///
  /// In ar, this message translates to:
  /// **'المتاح في {account} {available} من {limit}.'**
  String chatAnswerBalanceCredit(
    String account,
    String available,
    String limit,
  );

  /// E
  ///
  /// In ar, this message translates to:
  /// **'لسه معرفش رصيد {account}. هيظهر مع أول رسالة فيها الرصيد.'**
  String chatAnswerBalanceUnknown(String account);

  /// E · budget_remaining
  ///
  /// In ar, this message translates to:
  /// **'فاضلك {left} من ميزانية {subject}.'**
  String chatAnswerBudgetLeft(String left, String subject);

  /// E · overall budget
  ///
  /// In ar, this message translates to:
  /// **'فاضلك {left} من الميزانية، يعني {perDay} في اليوم لحد القبض.'**
  String chatAnswerBudgetLeftPerDay(String left, String perDay);

  /// E · calm, no emoji
  ///
  /// In ar, this message translates to:
  /// **'{subject} عدّى ميزانيته بـ {gap}.'**
  String chatAnswerBudgetOver(String subject, String gap);

  /// E · plus budget_overview_emptyAction
  ///
  /// In ar, this message translates to:
  /// **'مفيش ميزانية متحطة لـ {subject}. تحب تحطها؟'**
  String chatAnswerBudgetNone(String subject);

  /// E · count:int, n · upcoming_dues. =0 is the no-data case for dues
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{مفيش فواتير ولا أقساط {span}.} =1{عليك دفعة واحدة {span}: {list}.} =2{عليك دفعتين {span}: {list}، المجموع {amount}.} few{عليك {n} دفعات {span}: {list}، المجموع {amount}.} many{عليك {n} دفعة {span}: {list}، المجموع {amount}.} other{عليك {n} دفعة {span}: {list}، المجموع {amount}.}}'**
  String chatAnswerDues(
    int count,
    String span,
    String list,
    String amount,
    String n,
  );

  /// E
  ///
  /// In ar, this message translates to:
  /// **'أكبر حاجة صرفتها {span} كانت {amount} عند {merchant} يوم {date}.'**
  String chatAnswerBiggest(
    String span,
    String amount,
    String merchant,
    String date,
  );

  /// E · state:select(short/other).
  ///
  /// In ar, this message translates to:
  /// **'{state, select, short{{span} صرفت أكتر من دخلك بـ {gap}.} other{{span} حوشت {saved}، يعني {percent} من دخلك.}}'**
  String chatAnswerSavings(
    String state,
    String span,
    String gap,
    String saved,
    String percent,
  );

  /// E · spend_on_card
  ///
  /// In ar, this message translates to:
  /// **'صرفت {amount} بكارت {card} {span}.'**
  String chatAnswerSpendCard(String amount, String card, String span);

  /// E · EC-33
  ///
  /// In ar, this message translates to:
  /// **'مفيش صرف على {subject} من {start} لحد {end}.'**
  String chatAnswerNoData(String subject, String start, String end);

  /// E · EC-33
  ///
  /// In ar, this message translates to:
  /// **'مفيش بيانات للفترة دي.'**
  String get chatAnswerNoDataGeneric;

  /// E · with common_action_tryAgain
  ///
  /// In ar, this message translates to:
  /// **'حصلت مشكلة وأنا بقرا بياناتك. جرّب تاني.'**
  String get chatAnswerError;

  /// M · Rive tourGuide, when the toggle is switched on
  ///
  /// In ar, this message translates to:
  /// **'تمام، قلبي جامد وإنت كمان! هقصف على الصرف بس، مش عليك.'**
  String get chatRoastOn;

  /// M
  ///
  /// In ar, this message translates to:
  /// **'رجعنا للجد. الأرقام زي ما هي.'**
  String get chatRoastOff;

  /// M · after a typed "roast me" while the toggle is off
  ///
  /// In ar, this message translates to:
  /// **'ده كان قصف سريع. تحب أفتح مود القصف؟'**
  String get chatRoastOfferToggle;

  /// M · fact: delivery orders and amount
  ///
  /// In ar, this message translates to:
  /// **'{orders} بـ {amount} دليفري {span}؟ السواق حافظ عنوانك أكتر مني! 😄'**
  String chatRoastDelivery(String orders, String amount, String span);

  /// M
  ///
  /// In ar, this message translates to:
  /// **'{amount} دليفري {span}.. المطبخ مستني زيارة منك!'**
  String chatRoastDeliveryAlt(String amount, String span);

  /// M
  ///
  /// In ar, this message translates to:
  /// **'{amount} قهوة {span}؟ كده إنت شريك في مزرعة البن! ☕'**
  String chatRoastCoffee(String amount, String span);

  /// M
  ///
  /// In ar, this message translates to:
  /// **'القهوة {span} بـ {amount}. للأسف الكافيين مبيدفعش فواتيرك 😄'**
  String chatRoastCoffeeAlt(String span, String amount);

  /// M · never an essential category
  ///
  /// In ar, this message translates to:
  /// **'{category} واخد {percent} من صرفك. ده مش بند، ده هواية!'**
  String chatRoastTopCategory(String category, String percent);

  /// M
  ///
  /// In ar, this message translates to:
  /// **'{category} واخد {percent} من صرفك ولسه بيطلب كمان!'**
  String chatRoastTopCategoryAlt(String category, String percent);

  /// M · fact: biggest single non-essential expense
  ///
  /// In ar, this message translates to:
  /// **'{amount} مرة واحدة عند {merchant}؟ ده مش مشوار، ده قرار كبير!'**
  String chatRoastSplurge(String amount, String merchant);

  /// M
  ///
  /// In ar, this message translates to:
  /// **'{amount} عند {merchant} دفعة واحدة {span}. ده يوم تاريخي في المحفظة!'**
  String chatRoastSplurgeAlt(String amount, String merchant, String span);

  /// M · fact: peak spending day (chart 5)
  ///
  /// In ar, this message translates to:
  /// **'محفظتك بتخاف من يوم {peakDay}، وعندها حق!'**
  String chatRoastWeekend(String peakDay);

  /// M
  ///
  /// In ar, this message translates to:
  /// **'يوم {peakDay} بتصرف في المتوسط {amount}. باقي الأيام بتغير منه!'**
  String chatRoastWeekendAlt(String peakDay, String amount);

  /// M
  ///
  /// In ar, this message translates to:
  /// **'اشتراكاتك بتاخد {yearly} في السنة. فيهم حاجة بتفتحها فعلاً؟'**
  String chatRoastSubscriptions(String yearly);

  /// M
  ///
  /// In ar, this message translates to:
  /// **'اشتراكاتك بـ {yearly} في السنة شغالة حتى وإنت نايم!'**
  String chatRoastSubscriptionsAlt(String yearly);

  /// M · fact: delivery orders after the hour in chart 5
  ///
  /// In ar, this message translates to:
  /// **'أوردرات بعد الساعة {time}؟ التطبيق صاحي أكتر منك!'**
  String chatRoastLateNight(String time);

  /// M · only when a gold price exists (R8). grams = common_unit_grams
  ///
  /// In ar, this message translates to:
  /// **'{amount} على {category} كانوا يجيبوا {grams} دهب عيار {karat}. بس كانت حلوة، صح؟'**
  String chatRoastGoldEquivalent(
    String amount,
    String category,
    String grams,
    String karat,
  );

  /// M · R4: the only line used when spending exceeds income or a bill is overdue. No emoji
  ///
  /// In ar, this message translates to:
  /// **'النهارده مش هقصف جبهتك، الأرقام محتاجة جد. تحب نبص على أكبر بند سوا؟'**
  String get chatRoastGentle;

  /// M · no eligible fact
  ///
  /// In ar, this message translates to:
  /// **'دورت على حاجة أقصفك بيها ومالقيتش! إنت منظم غصب عني 👏'**
  String get chatRoastClean;

  /// S · above the disclaimer, always visible
  ///
  /// In ar, this message translates to:
  /// **'دي أفكار عامة مش نصيحة مالية.'**
  String get roiTipsDisclaimerSummary;

  /// S · simple standard Arabic (disclaimer exception). Legal sign-off: Q-23
  ///
  /// In ar, this message translates to:
  /// **'هذه اقتراحات عامة وليست نصيحة مالية أو استثمارية. الأرقام تقديرية وقد تختلف عن الواقع.'**
  String get roiTipsDisclaimer;

  /// S · years:select(two/other). Figures are rough examples from the user's own spending
  ///
  /// In ar, this message translates to:
  /// **'{years, select, two{السنة الأولى: توفير حوالين {year1}. السنة التانية: حوالين {year2}.} other{السنة الأولى: توفير حوالين {year1}.}}'**
  String roiTipsProjection(String years, String year1, String year2);

  /// B · opens S-73
  ///
  /// In ar, this message translates to:
  /// **'شارك'**
  String get roiTipsShare;

  /// B · hides the tip
  ///
  /// In ar, this message translates to:
  /// **'مش ليّا'**
  String get roiTipsNotForMe;

  /// N + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'اتشالت. مش هتظهرلك تاني.'**
  String get roiTipsDismissed;

  /// A · count:int, n · the badge on the Tips segment
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{نصيحة جديدة واحدة} =2{نصيحتين جداد} few{{n} نصايح جديدة} many{{n} نصيحة جديدة} other{{n} نصيحة جديدة}}'**
  String roiTipsBadgeA11y(int count, String n);

  /// T · C-28
  ///
  /// In ar, this message translates to:
  /// **'مفيش نصايح دلوقتي'**
  String get roiTipsEmptyTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'هقولك أول ما ألاقي حاجة تفيدك.'**
  String get roiTipsEmptyBody;

  /// S · plus common_gold_unlock
  ///
  /// In ar, this message translates to:
  /// **'نصايح مبنية على صرفك إنت، مع جولد'**
  String get roiTipsLockedBody;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'ماكينة قهوة بدل الكافيهات'**
  String get roiRuleCoffeeTitle;

  /// E · alt = installment + running cost
  ///
  /// In ar, this message translates to:
  /// **'بتصرف {monthly} في الشهر في الكافيهات. ماكينة بالتقسيط مع البن والحليب تقريباً {alt} في الشهر.'**
  String roiRuleCoffeeBody(String monthly, String alt);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'أكل البيت بدل الدليفري كل يوم'**
  String get roiRuleDeliveryTitle;

  /// E
  ///
  /// In ar, this message translates to:
  /// **'الدليفري واخد {monthly} في الشهر. جهاز طبخ صغير بالتقسيط وأكل البيت تقريباً {alt} في الشهر.'**
  String roiRuleDeliveryBody(String monthly, String alt);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'فلتر مياه بدل القوارير'**
  String get roiRuleWaterTitle;

  /// E
  ///
  /// In ar, this message translates to:
  /// **'القوارير والجراكن بـ {monthly} في الشهر. فلتر مياه بالتقسيط مع تغيير الشمعات تقريباً {alt} في الشهر.'**
  String roiRuleWaterBody(String monthly, String alt);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'فلوسك واقفة من غير عائد'**
  String get roiRuleIdleCashTitle;

  /// E · the rate is an example, not an offer and not guaranteed
  ///
  /// In ar, this message translates to:
  /// **'في حسابك {idle} زيادة عن ميزانيتك بقالهم أكتر من عشرين يوم من غير عائد. صندوق نقدي أو شهادة ممكن يشغّلوهم. معدل مثال للتوضيح: {exampleRate}.'**
  String roiRuleIdleCashBody(String idle, String exampleRate);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'مشاويرك المتكررة بالتطبيقات'**
  String get roiRuleCommuteTitle;

  /// E
  ///
  /// In ar, this message translates to:
  /// **'مشاويرك بتطبيقات التوصيل بـ {monthly} في الشهر. وسيلة مواصلات بالتقسيط مع مواصلات عامة للمشاوير الطويلة تقريباً {alt} في الشهر.'**
  String roiRuleCommuteBody(String monthly, String alt);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'سدد الكريدت كارد كله'**
  String get roiRuleCardInterestTitle;

  /// E
  ///
  /// In ar, this message translates to:
  /// **'عليك {balance} على الكريدت كارد وعندك كاش أكتر منه. السداد الكامل قبل ميعاد الكشف بيوفر الفوايد. معدل مثال للتوضيح: {exampleRate} في الشهر.'**
  String roiRuleCardInterestBody(String balance, String exampleRate);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'اشتراك سنوي واحد بدل كذا اشتراك'**
  String get roiRuleSubscriptionsTitle;

  /// E
  ///
  /// In ar, this message translates to:
  /// **'بتدفع {monthly} في الشهر على اشتراكات كتير. باقة سنوية مشتركة ممكن تنزلها لحوالين {alt} في الشهر.'**
  String roiRuleSubscriptionsBody(String monthly, String alt);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'اشتري الأساسيات مرة واحدة يوم القبض'**
  String get roiRuleStaplesTitle;

  /// E
  ///
  /// In ar, this message translates to:
  /// **'بتشتري الأساسيات على مرات صغيرة بـ {monthly} في الشهر. شراء بالجملة مرة واحدة يوم القبض ممكن يخليها حوالين {alt}.'**
  String roiRuleStaplesBody(String monthly, String alt);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'انسخ'**
  String get commonActionCopy;

  /// B · opens the support link (mail, UX-A-06). Used with common_support_codeLabel wherever support is offered
  ///
  /// In ar, this message translates to:
  /// **'كلّم الدعم'**
  String get commonActionContactSupport;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'سجّل دخول'**
  String get commonActionSignIn;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اخرج من الحساب'**
  String get commonActionSignOut;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'إدارة'**
  String get commonActionManage;

  /// L · D-57(f), the install ID shown so support can find the phone
  ///
  /// In ar, this message translates to:
  /// **'كود الدعم'**
  String get commonSupportCodeLabel;

  /// L · Latin, LTR, selectable; never mirrored
  ///
  /// In ar, this message translates to:
  /// **'{supportCode}'**
  String commonSupportCodeValue(String supportCode);

  /// N
  ///
  /// In ar, this message translates to:
  /// **'اتنسخ ✓'**
  String get commonSupportCodeCopied;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'انسخ كود الدعم {supportCode}'**
  String commonSupportCodeCopyA11y(String supportCode);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'ادّي كود الدعم ده للدعم عشان يلاقي موبايلك.'**
  String get commonSupportHint;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get settingsMainTitle;

  /// L · count:int, n · FR-ONB-11, shown only while a step is skipped
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{فاضل خطوة واحدة في الإعداد} =2{فاضل خطوتين في الإعداد} few{فاضل {n} خطوات في الإعداد} many{فاضل {n} خطوة في الإعداد} other{فاضل {n} خطوة في الإعداد}}'**
  String settingsMainFinishSetup(int count, String n);

  /// L · Gold row title for Free
  ///
  /// In ar, this message translates to:
  /// **'الباقة المجانية'**
  String get settingsMainGoldFree;

  /// L · plan = monthly / yearly / lifetime / other
  ///
  /// In ar, this message translates to:
  /// **'{plan, select, monthly{جولد · شهري} yearly{جولد · سنوي} lifetime{جولد · مدى الحياة} other{جولد}}'**
  String settingsMainGoldActive(String plan);

  /// L · opens S-68
  ///
  /// In ar, this message translates to:
  /// **'شوف جولد'**
  String get settingsMainSeeGold;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'عام'**
  String get settingsMainSectionGeneral;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'بياناتك'**
  String get settingsMainSectionData;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'التفضيلات'**
  String get settingsMainPreferences;

  /// L · Zaghlol's own alerts (Q-17)
  ///
  /// In ar, this message translates to:
  /// **'التنبيهات'**
  String get settingsMainNotifications;

  /// L · glossary
  ///
  /// In ar, this message translates to:
  /// **'زغلول بيقرا منين'**
  String get settingsMainCapture;

  /// C · state = ok / attention / other
  ///
  /// In ar, this message translates to:
  /// **'{state, select, ok{كله شغال} attention{محتاج انتباه} other{لسه متظبطش}}'**
  String settingsMainCaptureSub(String state);

  /// L · glossary
  ///
  /// In ar, this message translates to:
  /// **'التصنيفات'**
  String get settingsMainCategories;

  /// L · glossary
  ///
  /// In ar, this message translates to:
  /// **'نسخة احتياطية'**
  String get settingsMainBackup;

  /// L · state = never / other
  ///
  /// In ar, this message translates to:
  /// **'{state, select, never{لسه مفيش نسخة} other{آخر نسخة {date}}}'**
  String settingsMainBackupSub(String state, String date);

  /// L · glossary
  ///
  /// In ar, this message translates to:
  /// **'إكسيل وكشوف البنوك'**
  String get settingsMainExports;

  /// L · glossary
  ///
  /// In ar, this message translates to:
  /// **'خصوصيتك'**
  String get settingsMainPrivacy;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'عن زغلول'**
  String get settingsMainAbout;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'التصنيفات'**
  String get categoriesListTitle;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'التصنيفات'**
  String get categoriesListTabCategories;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'القواعد'**
  String get categoriesListTabRules;

  /// L · count:int, n · row subtitle
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{تصنيف فرعي واحد} =2{تصنيفين فرعيين} few{{n} تصنيفات فرعية} many{{n} تصنيف فرعي} other{{n} تصنيف فرعي}}'**
  String categoriesListSubCount(int count, String n);

  /// S · read-only for Free
  ///
  /// In ar, this message translates to:
  /// **'دي تصنيفات زغلول الأساسية. جولد بيخليك تضيف تصنيفات فرعية.'**
  String get categoriesListSystemNote;

  /// L · + common_gold_badge; Free opens S-68
  ///
  /// In ar, this message translates to:
  /// **'تصنيف جديد'**
  String get categoriesListNew;

  /// L · + common_gold_badge
  ///
  /// In ar, this message translates to:
  /// **'تصنيف فرعي جديد'**
  String get categoriesListNewSub;

  /// L · count:int, n · section header
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{مفيش قواعد} =1{قاعدة واحدة} =2{قاعدتين} few{{n} قواعد} many{{n} قاعدة} other{{n} قاعدة}}'**
  String categoriesListRulesCount(int count, String n);

  /// L · search field
  ///
  /// In ar, this message translates to:
  /// **'دوّر في القواعد'**
  String get categoriesListRulesSearch;

  /// A · each rule row
  ///
  /// In ar, this message translates to:
  /// **'{merchant} بيتصنف {category}'**
  String categoriesListRuleA11y(String merchant, String category);

  /// A
  ///
  /// In ar, this message translates to:
  /// **'غيّر تصنيف القاعدة'**
  String get categoriesListRuleEditA11y;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'امسح القاعدة'**
  String get categoriesListRuleDeleteA11y;

  /// S · empty rules state, Rive tourGuide allowed
  ///
  /// In ar, this message translates to:
  /// **'لما تصلّح تصنيف، هسألك لو عايزني أفتكره.'**
  String get categoriesListRulesEmpty;

  /// T · C-18 dialog
  ///
  /// In ar, this message translates to:
  /// **'تمسح القاعدة دي؟'**
  String get categoriesListRuleDeleteTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'زغلول مش هيطبّقها على الحركات الجاية.'**
  String get categoriesListRuleDeleteBody;

  /// N · + common_action_undo
  ///
  /// In ar, this message translates to:
  /// **'القاعدة اتمسحت'**
  String get categoriesListRuleDeleted;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مفيش قاعدة بالاسم ده'**
  String get categoriesListNoResults;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تصنيف جديد'**
  String get categoriesEditTitleNew;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تعديل التصنيف'**
  String get categoriesEditTitleEdit;

  /// L · 1 to 30 characters, unique (common_validation_nameRequired, …nameLength, …nameTaken)
  ///
  /// In ar, this message translates to:
  /// **'اسم التصنيف'**
  String get categoriesEditName;

  /// L · parent picker
  ///
  /// In ar, this message translates to:
  /// **'تحت تصنيف'**
  String get categoriesEditParent;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'مفيش (تصنيف رئيسي)'**
  String get categoriesEditParentNone;

  /// L · bucket picker (BR-CAT-02)
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get categoriesEditBucket;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'ضروريات'**
  String get categoriesEditBucketNeeds;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'رغبات'**
  String get categoriesEditBucketWants;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'التزامات'**
  String get categoriesEditBucketObligations;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'ادخار'**
  String get categoriesEditBucketSavings;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'دخل'**
  String get categoriesEditBucketIncome;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'عطاء'**
  String get categoriesEditBucketGiving;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار النوع'**
  String get categoriesEditBucketRequired;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الأيقونة'**
  String get categoriesEditIcon;

  /// L · from the approved palette
  ///
  /// In ar, this message translates to:
  /// **'اللون'**
  String get categoriesEditColor;

  /// B · destructive, edit mode only
  ///
  /// In ar, this message translates to:
  /// **'امسح التصنيف'**
  String get categoriesEditDelete;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تمسح \"{category}\"؟'**
  String categoriesEditDeleteTitle(String category);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار تصنيف تتنقل له حركاته قبل ما نمسحه.'**
  String get categoriesEditDeleteBody;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'انقل الحركات لـ'**
  String get categoriesEditMoveTo;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار تصنيف تتنقل له الحركات'**
  String get categoriesEditMoveRequired;

  /// B · destructive
  ///
  /// In ar, this message translates to:
  /// **'امسح وانقل'**
  String get categoriesEditDeleteConfirm;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'التصنيف اتمسح والحركات اتنقلت'**
  String get categoriesEditDeleted;

  /// S · locked state + common_gold_unlock
  ///
  /// In ar, this message translates to:
  /// **'التصنيفات الخاصة بيك مع جولد'**
  String get categoriesEditLockedBody;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'قالب رسالة جديد'**
  String get templatesBuilderTitle;

  /// L · block 1
  ///
  /// In ar, this message translates to:
  /// **'الصق رسالة أو اختار واحدة'**
  String get templatesBuilderPickTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'من اللي مستني رأيك'**
  String get templatesBuilderFromReview;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الصق رسالة'**
  String get templatesBuilderPaste;

  /// S · empty state
  ///
  /// In ar, this message translates to:
  /// **'الصق رسالة من البنك عشان نبدأ'**
  String get templatesBuilderEmpty;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الرسالة بتفضل على موبايلك ومش بتتبعت لحد.'**
  String get templatesBuilderPrivate;

  /// L · block 2
  ///
  /// In ar, this message translates to:
  /// **'علّم الأجزاء'**
  String get templatesBuilderTagTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'دوس على الجزء وبعدين اختار هو إيه.'**
  String get templatesBuilderTapHint;

  /// C · required
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get templatesBuilderTagAmount;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'العملة'**
  String get templatesBuilderTagCurrency;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'التاجر'**
  String get templatesBuilderTagMerchant;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'آخر أربع أرقام'**
  String get templatesBuilderTagLast4;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'الرصيد'**
  String get templatesBuilderTagBalance;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'التاريخ'**
  String get templatesBuilderTagDate;

  /// L · options common_txnType_expense / common_txnType_income
  ///
  /// In ar, this message translates to:
  /// **'الاتجاه'**
  String get templatesBuilderDirection;

  /// L · required
  ///
  /// In ar, this message translates to:
  /// **'اسم المرسل'**
  String get templatesBuilderSender;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'زي ما بيظهر على الرسايل'**
  String get templatesBuilderSenderHint;

  /// L · block 3
  ///
  /// In ar, this message translates to:
  /// **'جرّب القالب'**
  String get templatesBuilderTestTitle;

  /// S · done, total
  ///
  /// In ar, this message translates to:
  /// **'الرسايل الشبه دي اللي القالب فهمها: {done} من {total}'**
  String templatesBuilderTestResult(String done, String total);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'في رسالة مافهمتهاش'**
  String get templatesBuilderTestFailTitle;

  /// S · state = amount / direction / other
  ///
  /// In ar, this message translates to:
  /// **'{state, select, amount{مش لاقي المبلغ فيها.} direction{مش عارف دي صرف ولا دخل.} other{شكلها مختلف عن القالب.}}'**
  String templatesBuilderTestFailReason(String state);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'احفظ القالب'**
  String get templatesBuilderSave;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'القالب اتحفظ ✓'**
  String get templatesBuilderSaved;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'علّم المبلغ الأول'**
  String get templatesBuilderErrorAmount;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اكتب اسم المرسل'**
  String get templatesBuilderErrorSender;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'القالب لازم يقرا الرسالة اللي عملته عليها'**
  String get templatesBuilderErrorSelfParse;

  /// S · locked state + common_gold_unlock
  ///
  /// In ar, this message translates to:
  /// **'علّم زغلول يفهم رسايل بنك مش مدعوم، مع جولد'**
  String get templatesBuilderLockedBody;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'نسخة احتياطية'**
  String get backupSettingsTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'النسخة تتحفظ فين؟'**
  String get backupSettingsWhere;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الحساب'**
  String get backupSettingsAccount;

  /// L · text button
  ///
  /// In ar, this message translates to:
  /// **'غيّر'**
  String get backupSettingsAccountChange;

  /// L · size = common_fileSize_mb
  ///
  /// In ar, this message translates to:
  /// **'آخر نسخة: {date} · {size}'**
  String backupSettingsLast(String date, String size);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'لسه ما عملتش نسخة'**
  String get backupSettingsNever;

  /// S · Free, never backed up
  ///
  /// In ar, this message translates to:
  /// **'النسخة الأولى ببلاش، وبتحمي بياناتك لو الموبايل ضاع.'**
  String get backupSettingsFreeNudge;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اعمل نسخة دلوقتي'**
  String get backupSettingsNow;

  /// S · Free (FR-BAK-08)
  ///
  /// In ar, this message translates to:
  /// **'النسخة الجديدة بتحل محل القديمة.'**
  String get backupSettingsFreeReplaces;

  /// L · + common_gold_badge
  ///
  /// In ar, this message translates to:
  /// **'نسخة تلقائي'**
  String get backupSettingsAuto;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'مقفول'**
  String get backupSettingsAutoOff;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'كل يوم'**
  String get backupSettingsAutoDaily;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'كل أسبوع'**
  String get backupSettingsAutoWeekly;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'كل شهر'**
  String get backupSettingsAutoMonthly;

  /// S · + common_gold_unlock
  ///
  /// In ar, this message translates to:
  /// **'النسخ التلقائي مع جولد'**
  String get backupSettingsAutoLocked;

  /// L · Gold, up to five
  ///
  /// In ar, this message translates to:
  /// **'النسخ المحفوظة'**
  String get backupSettingsVersions;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'جولد بيحتفظ بخمس نسخ'**
  String get backupSettingsVersionsLocked;

  /// S · FR-BAK-09
  ///
  /// In ar, this message translates to:
  /// **'لو بقيت جولد، نسختك الحالية بتبقى أول نسخة في السجل.'**
  String get backupSettingsGoldKeeps;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كلمة سر النسخة'**
  String get backupSettingsPassphrase;

  /// L · text button
  ///
  /// In ar, this message translates to:
  /// **'غيّر'**
  String get backupSettingsPassphraseChange;

  /// L · opens S-04
  ///
  /// In ar, this message translates to:
  /// **'استرجاع نسخة'**
  String get backupSettingsRestore;

  /// S · FR-BAK-06
  ///
  /// In ar, this message translates to:
  /// **'في النسخة: حركاتك وإعداداتك وتصنيفاتك وقواعدك والكروت اللي مش بتتابعها.'**
  String get backupSettingsIncludes;

  /// S · FR-BAK-07
  ///
  /// In ar, this message translates to:
  /// **'مفيهاش مفاتيح الحماية ولا أذونات الموبايل. هتفعّلهم من جديد بعد الاسترجاع.'**
  String get backupSettingsExcludes;

  /// N · count:int, n · Free, older than 30 days (A-67); + backup_settings_now
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{آخر نسخة بقالها يوم} =2{آخر نسخة بقالها يومين} few{آخر نسخة بقالها {n} أيام} many{آخر نسخة بقالها {n} يوم} other{آخر نسخة بقالها {n} يوم}}'**
  String backupSettingsStale(int count, String n);

  /// L · C-27 with common_progress_percent, Rive counting
  ///
  /// In ar, this message translates to:
  /// **'بعمل النسخة…'**
  String get backupSettingsRunning;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'تقدر تلغي قبل ما الرفع يخلص.'**
  String get backupSettingsCancelNote;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'النسخة اتعملت ✓'**
  String get backupSettingsDone;

  /// S · maps NetworkFailure in backup
  ///
  /// In ar, this message translates to:
  /// **'النسخة ماتعملتش لأن النت مش ثابت. النسخة اللي فاتت لسه موجودة.'**
  String get backupSettingsErrorNetwork;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'المساحة على {provider} خلصت. فضّي مساحة وجرّب تاني. النسخة اللي فاتت لسه موجودة.'**
  String backupSettingsErrorStorage(String provider);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الدخول على {provider} خلص. سجّل دخول تاني وجرّب تاني.'**
  String backupSettingsErrorAuth(String provider);

  /// S · ICLOUD_UNAVAILABLE
  ///
  /// In ar, this message translates to:
  /// **'iCloud مش شغال على الموبايل ده. سجّل دخول بحساب Apple من إعدادات الآيفون وشغّل iCloud Drive.'**
  String get backupSettingsErrorIcloud;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'النسخة الاحتياطية ماتعملتش. جرّب تاني.'**
  String get backupSettingsErrorGeneric;

  /// T · first backup
  ///
  /// In ar, this message translates to:
  /// **'اختار كلمة سر للنسخة'**
  String get backupPassphraseTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كلمة السر'**
  String get backupPassphraseNew;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'اكتبها تاني'**
  String get backupPassphraseConfirm;

  /// C · strength meter
  ///
  /// In ar, this message translates to:
  /// **'ضعيفة'**
  String get backupPassphraseWeak;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'كويسة'**
  String get backupPassphraseFair;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'قوية'**
  String get backupPassphraseStrong;

  /// S · FR-BAK-01
  ///
  /// In ar, this message translates to:
  /// **'لو نسيت كلمة السر، محدش يقدر يفتح نسختك، ولا حتى إحنا.'**
  String get backupPassphraseWarning;

  /// L · checkbox, required
  ///
  /// In ar, this message translates to:
  /// **'فاهم إنها مش بتترجّع'**
  String get backupPassphraseUnderstand;

  /// S · UX-A-01, fixed length
  ///
  /// In ar, this message translates to:
  /// **'استخدم عشرة حروف على الأقل'**
  String get backupPassphraseTooShort;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'كلمتين السر مش زي بعض'**
  String get backupPassphraseMismatch;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'علّم إنك فاهم الأول'**
  String get backupPassphraseAckRequired;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'احفظ وابدأ النسخة'**
  String get backupPassphraseSave;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'غيّر كلمة سر النسخة'**
  String get backupPassphraseChangeTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كلمة السر الحالية'**
  String get backupPassphraseCurrent;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'كلمة السر الحالية مش صح'**
  String get backupPassphraseCurrentWrong;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'كلمة السر اتغيرت ✓'**
  String get backupPassphraseChanged;

  /// T · glossary
  ///
  /// In ar, this message translates to:
  /// **'إكسيل وكشوف البنوك'**
  String get exportsMainTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'تصدير'**
  String get exportsMainExportSection;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الصيغة'**
  String get exportsMainFormat;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'CSV'**
  String get exportsMainFormatCsv;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'Excel'**
  String get exportsMainFormatExcel;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الفترة'**
  String get exportsMainDates;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'التصنيفات'**
  String get exportsMainCategories;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'كل التصنيفات'**
  String get exportsMainCategoriesAll;

  /// L · options common_cardFilter_all and the card filter sheet
  ///
  /// In ar, this message translates to:
  /// **'الكروت'**
  String get exportsMainCards;

  /// L · fixed count
  ///
  /// In ar, this message translates to:
  /// **'معاينة أول عشرين صف'**
  String get exportsMainPreview;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مفيش حركات في الفترة دي'**
  String get exportsMainPreviewEmpty;

  /// S · + common_gold_unlock
  ///
  /// In ar, this message translates to:
  /// **'المعاينة ببلاش. التصدير مع جولد.'**
  String get exportsMainFreePreview;

  /// B · + common_gold_badge
  ///
  /// In ar, this message translates to:
  /// **'صدّر'**
  String get exportsMainExport;

  /// S · FR-EXP-07
  ///
  /// In ar, this message translates to:
  /// **'كل صف فيه عملته، ومفيش أي تحويل بين العملات.'**
  String get exportsMainCurrencyNote;

  /// S · FR-EXP-05, FR-SEC-06
  ///
  /// In ar, this message translates to:
  /// **'الملف اللي بتصدّره مش متشفّر. احفظه في مكان بتثق فيه.'**
  String get exportsMainUnencrypted;

  /// L · C-27
  ///
  /// In ar, this message translates to:
  /// **'بجهّز الملف…'**
  String get exportsMainPreparing;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'الملف جاهز ✓'**
  String get exportsMainReady;

  /// B · system file picker
  ///
  /// In ar, this message translates to:
  /// **'احفظ الملف'**
  String get exportsMainSave;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'معرفتش أجهّز الملف. جرّب تاني.'**
  String get exportsMainFailed;

  /// L · + common_gold_badge
  ///
  /// In ar, this message translates to:
  /// **'استيراد'**
  String get exportsImportSection;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'ملف زغلول CSV'**
  String get exportsImportZaghlolCsv;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كشف حساب PDF'**
  String get exportsImportPdfTitle;

  /// L · banks = supported PDF banks (FR-EXP-04), joined with the locale list format
  ///
  /// In ar, this message translates to:
  /// **'{banks}'**
  String exportsImportPdfBanks(String banks);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كشف بنك أونلاين'**
  String get exportsImportOnlineTitle;

  /// L · banks = Wise, Revolut, Monzo, bunq, N26, Payoneer (FR-EXP-06), Latin
  ///
  /// In ar, this message translates to:
  /// **'{banks}'**
  String exportsImportOnlineBanks(String banks);

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اختار الملف'**
  String get exportsImportPick;

  /// L · Rive scanning, C-27. The file is read on the phone
  ///
  /// In ar, this message translates to:
  /// **'بقرا الملف…'**
  String get exportsImportParsing;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'الكشف محمي بكلمة سر'**
  String get exportsImportPasswordTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اكتب كلمة السر. بتتستخدم على موبايلك بس ومش بتتحفظ.'**
  String get exportsImportPasswordBody;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كلمة سر الكشف'**
  String get exportsImportPasswordLabel;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'كلمة السر دي غلط'**
  String get exportsImportPasswordWrong;

  /// L · count:int, n · summary line; the empty file has its own state
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{لقيت حركة واحدة} =2{لقيت حركتين} few{لقيت {n} حركات} many{لقيت {n} حركة} other{لقيت {n} حركة}}'**
  String exportsImportFound(int count, String n);

  /// S · count:int, n · row hidden when 0
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{حركة واحدة موجودة عندك (هتتخطى)} =2{حركتين موجودين عندك (هيتخطوا)} few{{n} حركات موجودة عندك (هتتخطى)} many{{n} حركة موجودة عندك (هتتخطى)} other{{n} حركة موجودة عندك (هتتخطى)}}'**
  String exportsImportDuplicates(int count, String n);

  /// L · count:int, n · expandable; row hidden when 0 (FR-CAP-06)
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{كارت واحد مش متتبع (هيتخطى)} =2{كارتين مش متتبعين (هيتخطوا)} few{{n} كروت مش متتبعة (هتتخطى)} many{{n} كارت مش متتبعة (هتتخطى)} other{{n} كارت مش متتبعة (هتتخطى)}}'**
  String exportsImportUntracked(int count, String n);

  /// B · count:int, n · shown only when at least one is new
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{استورد حركة} =2{استورد حركتين} few{استورد {n} حركات} many{استورد {n} حركة} other{استورد {n} حركة}}'**
  String exportsImportImportButton(int count, String n);

  /// S · replaces the button
  ///
  /// In ar, this message translates to:
  /// **'كل الحركات دي موجودة عندك قبل كده'**
  String get exportsImportNothingNew;

  /// L · C-27
  ///
  /// In ar, this message translates to:
  /// **'بضيف الحركات…'**
  String get exportsImportImporting;

  /// N · count:int, n
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{اتضافت حركة ✓} =2{اتضافت حركتين ✓} few{اتضافت {n} حركات ✓} many{اتضافت {n} حركة ✓} other{اتضافت {n} حركة ✓}}'**
  String exportsImportDone(int count, String n);

  /// T · C-28
  ///
  /// In ar, this message translates to:
  /// **'مفيش حركات في الملف ده'**
  String get exportsImportEmptyTitle;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'الملف ده مش كشف مدعوم'**
  String get exportsImportUnsupportedTitle;

  /// S · banks = both lists, joined
  ///
  /// In ar, this message translates to:
  /// **'دي الجهات المدعومة: {banks}'**
  String exportsImportUnsupportedBody(String banks);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'نوع الملف مش اللي اخترته'**
  String get exportsImportWrongType;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'معرفتش أقرا الملف. جرّب ملف تاني.'**
  String get exportsImportFailed;

  /// S · locked state + common_gold_unlock
  ///
  /// In ar, this message translates to:
  /// **'ضيف شهور فاتتة وكشوف البنوك مع جولد'**
  String get exportsImportLockedBody;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'زغلول جولد'**
  String get goldPaywallTitle;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'اقفل'**
  String get goldPaywallCloseA11y;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'كل أدواتك في مكان واحد'**
  String get goldPaywallHeadline;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'كل الشارتات الاتناشر مع تحليل أعمق'**
  String get goldPaywallBenefitCharts;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'تسجيل بالصوت من غير حدود'**
  String get goldPaywallBenefitVoice;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'تصدير واستيراد وكشوف البنوك'**
  String get goldPaywallBenefitExport;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'نسخ تلقائي بخمس نسخ محفوظة'**
  String get goldPaywallBenefitBackup;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'دهب وشهادات وأصول'**
  String get goldPaywallBenefitAssets;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'تصنيفات وقوالب رسايل خاصة بيك'**
  String get goldPaywallBenefitCustom;

  /// C · C-31 plan card title
  ///
  /// In ar, this message translates to:
  /// **'{plan, select, monthly{شهري} yearly{سنوي} lifetime{مدى الحياة} other{جولد}}'**
  String goldPaywallPlanName(String plan);

  /// L · storePrice = the store's own formatted price
  ///
  /// In ar, this message translates to:
  /// **'{plan, select, monthly{{storePrice} في الشهر} yearly{{storePrice} في السنة} lifetime{{storePrice} مرة واحدة} other{{storePrice}}}'**
  String goldPaywallPlanPrice(String plan, String storePrice);

  /// C · yearly card
  ///
  /// In ar, this message translates to:
  /// **'الأوفر'**
  String get goldPaywallBestValue;

  /// B · Gold button, glossary. No emoji (payment)
  ///
  /// In ar, this message translates to:
  /// **'يلا نشترك'**
  String get goldPaywallContinue;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'اختار خطة الأول'**
  String get goldPaywallPlanRequired;

  /// L · text button
  ///
  /// In ar, this message translates to:
  /// **'استرجع مشترياتي'**
  String get goldPaywallRestore;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الشروط'**
  String get goldPaywallTerms;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الخصوصية'**
  String get goldPaywallPrivacy;

  /// S · simple standard Arabic (store legal line), for monthly and yearly
  ///
  /// In ar, this message translates to:
  /// **'{platform, select, ios{يتجدد الاشتراك تلقائياً ما لم يُلغَ قبل نهاية الفترة من إعدادات حساب Apple.} other{يتجدد الاشتراك تلقائياً ما لم يُلغَ قبل نهاية الفترة من Google Play.}}'**
  String goldPaywallRenewal(String platform);

  /// S · Egyptian summary above gold_paywall_renewal
  ///
  /// In ar, this message translates to:
  /// **'بيتجدد لوحده وتقدر تلغيه من المتجر في أي وقت.'**
  String get goldPaywallRenewalSummary;

  /// S · shown when Lifetime is selected
  ///
  /// In ar, this message translates to:
  /// **'الدفع مرة واحدة ومن غير تجديد.'**
  String get goldPaywallLifetimeNote;

  /// L · skeleton caption
  ///
  /// In ar, this message translates to:
  /// **'بحمّل الأسعار…'**
  String get goldPaywallPricesLoading;

  /// S · + common_action_tryAgain
  ///
  /// In ar, this message translates to:
  /// **'مش قادر أحمّل الأسعار. اتأكد من النت وجرّب تاني.'**
  String get goldPaywallPricesFailed;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'بفتح المتجر…'**
  String get goldPaywallPurchasing;

  /// S · BR-GOLD-05
  ///
  /// In ar, this message translates to:
  /// **'الدفع لسه معلّق. جولد هيشتغل أول ما يتم.'**
  String get goldPaywallPending;

  /// L · no Gold until verified
  ///
  /// In ar, this message translates to:
  /// **'بتأكد من الدفع…'**
  String get goldPaywallVerifying;

  /// S · BR-GOLD-06, EC-44
  ///
  /// In ar, this message translates to:
  /// **'هكمّل التأكد أول ما النت يرجع.'**
  String get goldPaywallVerifyOffline;

  /// N · returns to the origin screen (N-05)
  ///
  /// In ar, this message translates to:
  /// **'جولد اشتغل ✓'**
  String get goldPaywallSuccess;

  /// M · Rive proud · purchase verified. No joke, no emoji (tone gate 1)
  ///
  /// In ar, this message translates to:
  /// **'ألف مبروك. جولد اشتغل وكل حاجة اتفتحت.'**
  String get goldPaywallSuccessMascot;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'الشراء اتلغى. مفيش حاجة اتخصمت.'**
  String get goldPaywallCancelled;

  /// S · PURCHASE_TOKEN_INVALID, PURCHASE_NOT_OWNED, PURCHASE_WRONG_APP; no Gold
  ///
  /// In ar, this message translates to:
  /// **'مقدرناش نتأكد من الشراء. جرّب «استرجع مشترياتي»، ولو لسه كلّم الدعم.'**
  String get goldPaywallInvalid;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'المتجر رجّع مشكلة. جرّب تاني كمان شوية.'**
  String get goldPaywallStoreError;

  /// L · plan = monthly / yearly / lifetime / other; + common_action_manage
  ///
  /// In ar, this message translates to:
  /// **'{plan, select, monthly{إنت جولد: شهري} yearly{إنت جولد: سنوي} lifetime{إنت جولد: مدى الحياة} other{إنت جولد}}'**
  String goldPaywallAlreadyGold(String plan);

  /// S · D-54, shown on the buying phone after success; opens gold_seat_protectTitle
  ///
  /// In ar, this message translates to:
  /// **'بعد الشراء، سجّل دخول على الموبايل ده عشان تحمي الجولد.'**
  String get goldPaywallProtectNote;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'جولد وحسابك'**
  String get goldAccountTitle;

  /// L · plan = monthly / yearly / lifetime / other
  ///
  /// In ar, this message translates to:
  /// **'{plan, select, monthly{جولد · شهري · بيتجدد {date}} yearly{جولد · سنوي · بيتجدد {date}} lifetime{جولد · مدى الحياة} other{الباقة المجانية}}'**
  String goldAccountPlan(String plan, String date);

  /// B · Free, opens S-68
  ///
  /// In ar, this message translates to:
  /// **'شوف جولد'**
  String get goldAccountSeeGold;

  /// L · opens the store
  ///
  /// In ar, this message translates to:
  /// **'إدارة الاشتراك'**
  String get goldAccountManage;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'استرجع مشترياتي'**
  String get goldAccountRestore;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'بدوّر على مشترياتك…'**
  String get goldAccountRestoring;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'الجولد رجع ✓'**
  String get goldAccountRestoreDone;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مفيش مشتريات أقدر أرجّعها على الحساب ده'**
  String get goldAccountRestoreNone;

  /// T · expired or refunded (FR-GOLD-06)
  ///
  /// In ar, this message translates to:
  /// **'الجولد خلص'**
  String get goldAccountEndedTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'بياناتك كلها لسه موجودة، وتقدر ترجع جولد في أي وقت.'**
  String get goldAccountEndedBody;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'استخدم جولد على موبايل تاني (اختياري)'**
  String get goldAccountOtherPhone;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'كمّل بحساب Google'**
  String get goldAccountGoogle;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'كمّل بحساب Apple'**
  String get goldAccountApple;

  /// S · FR-ACCT-02
  ///
  /// In ar, this message translates to:
  /// **'بنربط باقة جولد بس. بيانات فلوسك عمرها ما بتتبعت.'**
  String get goldAccountPrivacy;

  /// L · button loading
  ///
  /// In ar, this message translates to:
  /// **'بدخل…'**
  String get goldAccountSigningIn;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'الدخول اتلغى.'**
  String get goldAccountSignInCancelled;

  /// S · ID_TOKEN_INVALID
  ///
  /// In ar, this message translates to:
  /// **'الدخول ما كملش. جرّب تاني.'**
  String get goldAccountSignInFailed;

  /// S · ACCOUNT_TOKEN_EXPIRED, shown in Settings only
  ///
  /// In ar, this message translates to:
  /// **'سجّل دخول تاني عشان تكمّل'**
  String get goldAccountSignInAgain;

  /// L · email = masked address from the ID token
  ///
  /// In ar, this message translates to:
  /// **'داخل بـ {email}'**
  String goldAccountSignedInAs(String email);

  /// L · stored nextMoveAt (EC-68)
  ///
  /// In ar, this message translates to:
  /// **'تقدر تنقل الجولد تاني يوم {date}'**
  String goldAccountNextMove(String date);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تخرج من الحساب؟'**
  String get goldAccountSignOutTitle;

  /// S · state = linked (Gold bought under the account) / other. FR-ACCT-03
  ///
  /// In ar, this message translates to:
  /// **'{state, select, linked{بياناتك كلها هتفضل على الموبايل. الجولد هيقف على الموبايل ده لحد ما تسجّل دخول تاني بنفس الحساب.} other{بياناتك كلها هتفضل على الموبايل، والجولد هيفضل شغال.}}'**
  String goldAccountSignOutBody(String state);

  /// T · INSTALL_LINKED_TO_OTHER_ACCOUNT (EC-46)
  ///
  /// In ar, this message translates to:
  /// **'الموبايل ده مربوط بحساب تاني'**
  String get goldAccountReplaceTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'تربطه بالحساب ده بدله؟ باقة الجولد بس هي اللي بتتربط.'**
  String get goldAccountReplaceBody;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اربطه بالحساب ده'**
  String get goldAccountReplaceConfirm;

  /// S · FR-ACCT-05, no self-service relink
  ///
  /// In ar, this message translates to:
  /// **'موبايلك القديم ضاع أو اتباع؟ كلّم الدعم وهنساعدك.'**
  String get goldAccountLostPhone;

  /// L · destructive
  ///
  /// In ar, this message translates to:
  /// **'امسح الحساب'**
  String get goldAccountDeleteRow;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تمسح حسابك؟'**
  String get goldAccountDeleteTitle;

  /// S · FR-ACCT-04
  ///
  /// In ar, this message translates to:
  /// **'هنمسح حسابك والربط بالجولد من عندنا. مشترياتك هتفضل على حساب المتجر بتاعك.'**
  String get goldAccountDeleteBody;

  /// B · destructive
  ///
  /// In ar, this message translates to:
  /// **'امسح الحساب'**
  String get goldAccountDeleteConfirm;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'الحساب اتمسح'**
  String get goldAccountDeleted;

  /// T · MOVE_COOLDOWN (409, restore) and sign-in moveRefused (200)
  ///
  /// In ar, this message translates to:
  /// **'نقلت الجولد من قريب'**
  String get goldSeatCooldownTitle;

  /// S · date = nextMoveAt for the locale; with support. Not a move (EC-66), no retry before the date
  ///
  /// In ar, this message translates to:
  /// **'تقدر تنقله تاني يوم {date}، أو كلّم الدعم.'**
  String goldSeatCooldownBody(String date);

  /// T · DEVICE_ATTESTATION_FAILED after the one retry (EC-66)
  ///
  /// In ar, this message translates to:
  /// **'مقدرناش نتأكد من الموبايل ده'**
  String get goldSeatAttestTitle;

  /// S · actions common_action_tryAgain, common_action_signIn; with support. Existing Gold untouched
  ///
  /// In ar, this message translates to:
  /// **'جرّب تاني بعد شوية. لو لسه، سجّل دخول بالحساب اللي اشتريت بيه، أو كلّم الدعم.'**
  String get goldSeatAttestBody;

  /// S · ATTEST_PLAY_SERVICES_OUTDATED (Android)
  ///
  /// In ar, this message translates to:
  /// **'حدّث خدمات Google Play من المتجر وجرّب تاني.'**
  String get goldSeatAttestPlayServices;

  /// S · ATTEST_UNAVAILABLE, ATTEST_TRANSIENT after retries; with support
  ///
  /// In ar, this message translates to:
  /// **'التأكد من الموبايل مش متاح دلوقتي. سجّل دخول بالحساب اللي اشتريت بيه، أو كلّم الدعم.'**
  String get goldSeatAttestUnavailable;

  /// T · restore item account_required (EC-65)
  ///
  /// In ar, this message translates to:
  /// **'سجّل دخول الأول'**
  String get goldSeatAccountRequiredTitle;

  /// S · reveals nothing about the account; action common_action_signIn
  ///
  /// In ar, this message translates to:
  /// **'اعمل تسجيل دخول بالحساب اللي اشتريت بيه.'**
  String get goldSeatAccountRequiredBody;

  /// T · entitlement moved, movedBy: user
  ///
  /// In ar, this message translates to:
  /// **'الجولد اتنقل لموبايل تاني'**
  String get goldSeatMovedUserTitle;

  /// S · actions gold_seat_restoreAction, common_action_signIn
  ///
  /// In ar, this message translates to:
  /// **'لو عايزه على الموبايل ده، استرجع مشترياتك أو سجّل دخول.'**
  String get goldSeatMovedUserBody;

  /// T · movedBy: support (D-57(f))
  ///
  /// In ar, this message translates to:
  /// **'الدعم نقل الجولد لموبايل تاني'**
  String get goldSeatMovedSupportTitle;

  /// S · with support
  ///
  /// In ar, this message translates to:
  /// **'لو ده مش اللي طلبته، كلّم الدعم وادّيهم كود الدعم.'**
  String get goldSeatMovedSupportBody;

  /// T · entitlement paused (D-61(c))
  ///
  /// In ar, this message translates to:
  /// **'الجولد واقف مؤقتاً'**
  String get goldSeatPausedTitle;

  /// S · action common_action_signIn
  ///
  /// In ar, this message translates to:
  /// **'اعمل تسجيل دخول عشان تستخدم الجولد على الموبايل ده. مكانك محفوظ ومش هيتحسب نقلة.'**
  String get goldSeatPausedBody;

  /// T · tampered (D-60, EC-70)
  ///
  /// In ar, this message translates to:
  /// **'اتصل بالنت عشان نتأكد من الجولد'**
  String get goldSeatTamperedTitle;

  /// S · local data stays readable
  ///
  /// In ar, this message translates to:
  /// **'ساعة الموبايل اتغيّرت. أول ما النت يشتغل هنتأكد، وبياناتك كلها لسه موجودة.'**
  String get goldSeatTamperedBody;

  /// S · verify seatHeldElsewhere (D-61(a), EC-71)
  ///
  /// In ar, this message translates to:
  /// **'الدفع تم. الجولد لسه على الموبايل التاني، وتقدر تنقله يوم {date}.'**
  String goldSeatHeldElsewhere(String date);

  /// S · seatHeldElsewhere + accountRequired (R4-4); action common_action_signIn
  ///
  /// In ar, this message translates to:
  /// **'الدفع تم. عشان الجولد ييجي هنا، اعمل تسجيل دخول بالحساب اللي عليه الجولد.'**
  String get goldSeatHeldElsewhereAccount;

  /// T · supportNotice: gold_linked_by_support
  ///
  /// In ar, this message translates to:
  /// **'الدعم ربط الجولد بحساب'**
  String get goldSeatSupportNoticeTitle;

  /// S · shown once, on the buying phone; with support (R4-7(2), R5-7)
  ///
  /// In ar, this message translates to:
  /// **'الدعم ربط الجولد بتاعك بحساب. لو ده مش إنت، كلّم الدعم.'**
  String get goldSeatSupportNoticeBody;

  /// S · sign-in moveRefused; followed by the cooldown copy or one of the two branches below
  ///
  /// In ar, this message translates to:
  /// **'الحساب اتربط، بس الجولد لسه مجاش على الموبايل ده.'**
  String get goldSeatSignInLinked;

  /// S · branch (a): restoreSuggested: true, an App Store purchase exists on this iPhone (D-65(a)); action gold_seat_restoreAction
  ///
  /// In ar, this message translates to:
  /// **'جرّب «استرجع مشترياتي»، والجولد هيرجع على الموبايل ده.'**
  String get goldSeatRestoreSuggested;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'استرجع مشترياتي'**
  String get goldSeatRestoreAction;

  /// S · branch (b): bought on Android or under another Apple ID, no Restore offered (D-66(c)); with support
  ///
  /// In ar, this message translates to:
  /// **'الجولد مش هينفع ينتقل للموبايل ده قبل يوم {date}. كلّم الدعم وهنساعدك.'**
  String goldSeatSupportPath(String date);

  /// T · D-54, FR-ACCT-01. After purchase and in gold_account_*
  ///
  /// In ar, this message translates to:
  /// **'سجّل دخول هنا عشان تحمي الجولد'**
  String get goldSeatProtectTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الربط بيتعمل من الموبايل اللي اشتريت عليه بس. بعدها تقدر تنقل الجولد لموبايل جديد بحسابك.'**
  String get goldSeatProtectBody;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'الجولد اتربط بحسابك ✓'**
  String get goldSeatProtectDone;

  /// S · Android, in the "Delete everything" dialog (D-55, EC-69). state = cooldown (a cooldown is running, date shown) / other
  ///
  /// In ar, this message translates to:
  /// **'{state, select, cooldown{لو مسحت كل حاجة، هيتحسب إن الجولد اتنقل، ومش هتقدر ترجّعه على الموبايل ده قبل يوم {date}.} other{لو مسحت كل حاجة ورجعت الجولد، ده هيتحسب نقلة الشهر ده.}}'**
  String goldSeatDeleteWarning(String state, String date);

  /// T · Q-17
  ///
  /// In ar, this message translates to:
  /// **'التنبيهات'**
  String get notificationsSettingsTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'تنبيهات الميزانية'**
  String get notificationsSettingsBudget;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'لما الصرف يزيد'**
  String get notificationsSettingsSpikes;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الأقساط والفواتير'**
  String get notificationsSettingsDues;

  /// L · count:int, n · FR-SUB-04, 0 to 30
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{يوم الاستحقاق نفسه} =1{قبلها بيوم} =2{قبلها بيومين} few{قبلها بـ {n} أيام} many{قبلها بـ {n} يوم} other{قبلها بـ {n} يوم}}'**
  String notificationsSettingsDueDays(int count, String n);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'حركة اتسجلت مرتين'**
  String get notificationsSettingsDuplicates;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'تجديد الاشتراكات'**
  String get notificationsSettingsRenewals;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'مشاكل النسخة الاحتياطية'**
  String get notificationsSettingsBackup;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'ملخص الأسبوع'**
  String get notificationsSettingsWeekly;

  /// L · UX-A-07
  ///
  /// In ar, this message translates to:
  /// **'كل جمعة الصبح'**
  String get notificationsSettingsWeeklySub;

  /// L · A-27
  ///
  /// In ar, this message translates to:
  /// **'ساعات الهدوء'**
  String get notificationsSettingsQuiet;

  /// L · start, end = times, default 23:00 to 08:00
  ///
  /// In ar, this message translates to:
  /// **'من {start} لحد {end}'**
  String notificationsSettingsQuietRange(String start, String end);

  /// L · FR-NTF-03
  ///
  /// In ar, this message translates to:
  /// **'اخفي المبالغ على شاشة القفل'**
  String get notificationsSettingsHideAmounts;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'التنبيه بيوصل من غير مبلغ ولا اسم تاجر.'**
  String get notificationsSettingsHideAmountsHint;

  /// S · validation, 0 to 30
  ///
  /// In ar, this message translates to:
  /// **'اختار من يوم الاستحقاق لحد تلاتين يوم قبله'**
  String get notificationsSettingsDaysRange;

  /// S · validation
  ///
  /// In ar, this message translates to:
  /// **'بداية ونهاية ساعات الهدوء لازم يختلفوا'**
  String get notificationsSettingsQuietSame;

  /// T · banner
  ///
  /// In ar, this message translates to:
  /// **'التنبيهات مقفولة لزغلول'**
  String get notificationsSettingsOsOffTitle;

  /// S · + common_action_openSettings
  ///
  /// In ar, this message translates to:
  /// **'شغّلها من إعدادات الموبايل عشان توصلك.'**
  String get notificationsSettingsOsOffBody;

  /// T · BR-BUD-02, default 80%
  ///
  /// In ar, this message translates to:
  /// **'قربت توصل لحد الميزانية'**
  String get notificationsAlertBudgetNearTitle;

  /// N · amount variant
  ///
  /// In ar, this message translates to:
  /// **'صرفت {percent} من ميزانية {category}، وفاضلك {left}.'**
  String notificationsAlertBudgetNear(
    String percent,
    String category,
    String left,
  );

  /// N · hidden variant; category name kept (Q-33)
  ///
  /// In ar, this message translates to:
  /// **'ميزانية {category} قربت تخلص.'**
  String notificationsAlertBudgetNearHidden(String category);

  /// T · 100%
  ///
  /// In ar, this message translates to:
  /// **'وصلت لحد الميزانية'**
  String get notificationsAlertBudgetReachedTitle;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'ميزانية {category} خلصت: صرفت {spent} من {budget}.'**
  String notificationsAlertBudgetReached(
    String category,
    String spent,
    String budget,
  );

  /// N
  ///
  /// In ar, this message translates to:
  /// **'ميزانية {category} خلصت.'**
  String notificationsAlertBudgetReachedHidden(String category);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'صرفك النهارده أكتر من المعتاد'**
  String get notificationsAlertSpikeTitle;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'صرفت النهارده {spent}، أكتر من المعتاد بـ {delta}.'**
  String notificationsAlertSpike(String spent, String delta);

  /// N
  ///
  /// In ar, this message translates to:
  /// **'صرفك النهارده أكتر من المعتاد. افتح زغلول وراجع.'**
  String get notificationsAlertSpikeHidden;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'قسط أو فاتورة قربت'**
  String get notificationsAlertDueTitle;

  /// N · count:int, n, item, amount · days until the due date
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{{item} بيستحق النهارده: {amount}} =1{{item} بيستحق بكره: {amount}} =2{{item} بيستحق بعد يومين: {amount}} few{{item} بيستحق بعد {n} أيام: {amount}} many{{item} بيستحق بعد {n} يوم: {amount}} other{{item} بيستحق بعد {n} يوم: {amount}}}'**
  String notificationsAlertDue(int count, String item, String amount, String n);

  /// N
  ///
  /// In ar, this message translates to:
  /// **'عندك قسط أو فاتورة بتستحق قريب.'**
  String get notificationsAlertDueHidden;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'ممكن حركة تكون اتسجلت مرتين'**
  String get notificationsAlertDuplicateTitle;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'{merchant}: {amount} ظهرت مرتين تقريباً في نفس الوقت. بُص عليها.'**
  String notificationsAlertDuplicate(String merchant, String amount);

  /// N
  ///
  /// In ar, this message translates to:
  /// **'في حركة ممكن تكون مكررة. افتح زغلول وراجعها.'**
  String get notificationsAlertDuplicateHidden;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'اشتراك هيتجدد'**
  String get notificationsAlertRenewalTitle;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'{merchant} هيتجدد يوم {date} بـ {amount}.'**
  String notificationsAlertRenewal(String merchant, String date, String amount);

  /// N
  ///
  /// In ar, this message translates to:
  /// **'في اشتراك هيتجدد قريب.'**
  String get notificationsAlertRenewalHidden;

  /// T · FR-NTF-01. No amounts, so no hidden variant
  ///
  /// In ar, this message translates to:
  /// **'النسخة الاحتياطية ماتعملتش'**
  String get notificationsAlertBackupTitle;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'جرّب تاني من الإعدادات. بياناتك لسه على الموبايل.'**
  String get notificationsAlertBackupBody;

  /// T · Friday morning
  ///
  /// In ar, this message translates to:
  /// **'ملخص أسبوعك جاهز'**
  String get notificationsAlertWeeklyTitle;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'صرفت {spent} الأسبوع ده، وأكتر حاجة كانت {category}.'**
  String notificationsAlertWeekly(String spent, String category);

  /// N
  ///
  /// In ar, this message translates to:
  /// **'ملخص أسبوعك جاهز. افتح زغلول تشوفه.'**
  String get notificationsAlertWeeklyHidden;

  /// T · glossary
  ///
  /// In ar, this message translates to:
  /// **'خصوصيتك'**
  String get privacyMainTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'اللي بيفضل على موبايلك'**
  String get privacyMainStaysTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'رسايلك وحركاتك وأرصدتك وميزانياتك وأصولك وقواعدك. كله متشفّر.'**
  String get privacyMainStaysBody;

  /// L · opens S-72
  ///
  /// In ar, this message translates to:
  /// **'قفل التطبيق'**
  String get privacyMainAppLock;

  /// L · opens the list below
  ///
  /// In ar, this message translates to:
  /// **'اللي سيرفر زغلول يعرفه عنك'**
  String get privacyMainServerRow;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'اللي سيرفر زغلول يعرفه عنك'**
  String get privacyServerTitle;

  /// S · Egyptian summary of the whole screen
  ///
  /// In ar, this message translates to:
  /// **'فلوسك وحركاتك عمرها ما بتسيب موبايلك. السيرفر بيعرف الحاجات دي بس:'**
  String get privacyServerSummary;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'رقم عشوائي للتطبيق، مش اسمك ولا رقم موبايلك'**
  String get privacyServerItemId;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'شراء الجولد بتاعك، عشان نتأكد منه'**
  String get privacyServerItemPurchase;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'تسجيل دخولك، لو استخدمته بس'**
  String get privacyServerItemSignIn;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'أسماء التجار، لو سمحت بس'**
  String get privacyServerItemMerchants;

  /// S · BR-SYNC-03
  ///
  /// In ar, this message translates to:
  /// **'نوع الموبايل وإصدار التطبيق وإصدار قايمة التجار'**
  String get privacyServerItemVersion;

  /// S · BR-SYNC-03, D-45 (carries no other device data); "sometimes on purchase" because purchase verify needs it only where ADR-012 requires
  ///
  /// In ar, this message translates to:
  /// **'إثبات إن الموبايل حقيقي (Play Integrity أو App Attest) وقت الاسترجاع، وأحياناً وقت الشراء'**
  String get privacyServerItemAttest;

  /// S · FR-PAR-14; same fields as ingestion_requestBank_privacy
  ///
  /// In ar, this message translates to:
  /// **'طلب دعم بنك، لو طلبته بس: اسم البنك وبلده ونوع التنبيه'**
  String get privacyServerItemBankRequest;

  /// S · Egyptian summary · disclosure 1 (D-62); shown on iOS
  ///
  /// In ar, this message translates to:
  /// **'على الآيفون بس: زغلول بيعرف إن التثبيتات القديمة كانت على نفس الموبايل.'**
  String get privacyServerSeatKeysSummary;

  /// E · simple standard Arabic · disclosure 1
  ///
  /// In ar, this message translates to:
  /// **'على الآيفون، يرسل التطبيق عند الاسترجاع أو تسجيل الدخول إثباتاً من هذا التثبيت ومن حتى أربعة تثبيتات سابقة، ليعرف الخادم أنها على الجهاز نفسه. يحفظ الخادم صورة مشفّرة فقط، ولا يسجّل المفاتيح.'**
  String get privacyServerSeatKeys;

  /// S · Egyptian summary · disclosure 2 (R4-8); shown on iOS
  ///
  /// In ar, this message translates to:
  /// **'لو مسحت كل حاجة من الآيفون، الجولد يقدر يرجع عليه من غير نقلة.'**
  String get privacyServerDeleteKeepsSummary;

  /// E · simple standard Arabic · disclosure 2
  ///
  /// In ar, this message translates to:
  /// **'يُبقي «امسح كل حاجة» على الآيفون مفاتيح التعريف على الجهاز، ليعود الجولد إليه دون احتساب نقلة. ويحتفظ الخادم بتجزئة مفتاحية للمفتاح مع الشراء حتى يُحذف الشراء. مسح الآيفون بالكامل يزيلها.'**
  String get privacyServerDeleteKeeps;

  /// S · Egyptian summary · disclosure 3 (R4-2)
  ///
  /// In ar, this message translates to:
  /// **'رقم عشوائي بيتأكد بيه السيرفر من الوقت، ومفيهوش أي حاجة عنك.'**
  String get privacyServerTimeNonceSummary;

  /// E · simple standard Arabic · disclosure 3
  ///
  /// In ar, this message translates to:
  /// **'تحمل بعض الطلبات رقماً عشوائياً يُستخدم مرة واحدة للتحقق من الوقت. لا يتضمن أي معلومة عن الجهاز أو المستخدم، ولا يُخزَّن.'**
  String get privacyServerTimeNonce;

  /// S · Egyptian summary · disclosure 4 (R4-7(2), R5-7)
  ///
  /// In ar, this message translates to:
  /// **'لو الدعم ربط الجولد بحساب، موبايلك اللي اشتريت عليه بيتبلّغ.'**
  String get privacyServerSupportNoticeSummary;

  /// E · simple standard Arabic · disclosure 4
  ///
  /// In ar, this message translates to:
  /// **'إذا ربط الدعم الجولد بحساب، يُبلَّغ الهاتف الذي اشتُري عليه عند اتصاله التالي. يكرّر الخادم الإشعار حتى تؤكد مزامنة ذلك الهاتف استلامه، حتى لا يضيع إن فُقدت الاستجابة.'**
  String get privacyServerSupportNotice;

  /// S · Egyptian summary · D-47, FR-ACCT-04
  ///
  /// In ar, this message translates to:
  /// **'لما تمسح حسابك، بنمسح كل حاجة، وأثر الدعم بيتمسح بعد سنة.'**
  String get privacyServerSupportRowsSummary;

  /// E · simple standard Arabic
  ///
  /// In ar, this message translates to:
  /// **'عند حذف الحساب تُحذف بياناته من الخادم، عدا سجلات تدقيق الدعم التي تحمل بصمة مشفّرة للبريد ومعرّف الحساب، وتُحذف تلقائياً بعد سنة من إنشائها.'**
  String get privacyServerSupportRows;

  /// L · toggle, off by default
  ///
  /// In ar, this message translates to:
  /// **'ساعد في تحسين قايمة التجار'**
  String get privacyContributeLabel;

  /// S · one-sentence explanation (FR-CAT-09)
  ///
  /// In ar, this message translates to:
  /// **'لو شغّلتها، بنبعت اسم التاجر والتصنيف اللي اخترته بس.'**
  String get privacyContributeSentence;

  /// T · ⓘ sheet
  ///
  /// In ar, this message translates to:
  /// **'بالظبط إيه اللي بيتبعت؟'**
  String get privacyContributeInfoTitle;

  /// E
  ///
  /// In ar, this message translates to:
  /// **'بنبعت: اسم التاجر بعد تنضيفه، وكود البنك، والتصنيف اللي اخترته.'**
  String get privacyContributeSends;

  /// E
  ///
  /// In ar, this message translates to:
  /// **'مبنبعتش: مبالغ، ولا تواريخ، ولا أرقام كروت، ولا أرقام تليفونات، ولا حسابات إنستاباي، ولا أسماء ناس.'**
  String get privacyContributeNeverSends;

  /// E
  ///
  /// In ar, this message translates to:
  /// **'بنستبعد أي اسم شكله اسم شخص، والتصنيفات الخاصة بيك عمرها ما بتتبعت.'**
  String get privacyContributeFilters;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'تقدر تقفلها في أي وقت.'**
  String get privacyContributeOffHint;

  /// N
  ///
  /// In ar, this message translates to:
  /// **'شكراً. هنبعت اسم التاجر والتصنيف بس.'**
  String get privacyContributeTurnedOn;

  /// S · platform = ios / other. Same wording as home_banner_rooted
  ///
  /// In ar, this message translates to:
  /// **'{platform, select, ios{الآيفون ده متعمله جيلبريك، فحماية بياناتك أضعف.} other{الموبايل ده متعمله روت، فحماية بياناتك أضعف.}}'**
  String privacyRootedRow(String platform);

  /// T · opened from common_action_learnMore
  ///
  /// In ar, this message translates to:
  /// **'يعني إيه حماية أضعف؟'**
  String get privacyRootedTitle;

  /// E · not blocking, a warning only
  ///
  /// In ar, this message translates to:
  /// **'على موبايل متعدّل، تطبيق تاني ممكن يوصل لملفات زغلول بسهولة أكتر. بياناتك لسه متشفّرة، بس الأمان مش كامل.'**
  String get privacyRootedBody;

  /// L · destructive
  ///
  /// In ar, this message translates to:
  /// **'امسح كل حاجة'**
  String get privacyDeleteRow;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تمسح كل حاجة من على الموبايل ده؟'**
  String get privacyDeleteTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'هنمسح كل حركاتك وإعداداتك ومفاتيح الحماية من على الموبايل ده. مفيش رجوع.'**
  String get privacyDeleteBody;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'آخر نسخة احتياطية: {date}'**
  String privacyDeleteLastBackup(String date);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مفيش نسخة احتياطية. اللي هتمسحه مش هيرجع.'**
  String get privacyDeleteNoBackup;

  /// E · FR-ONB-08 iOS exception (D-62); iOS only
  ///
  /// In ar, this message translates to:
  /// **'على الآيفون، مفاتيح تعريف الموبايل بتفضل عليه عشان الجولد يرجع من غير نقلة، ومفيهاش أي بيانات مالية. مسح الآيفون كله بيشيلها.'**
  String get privacyDeleteIosKeys;

  /// S · iOS only, R4-8
  ///
  /// In ar, this message translates to:
  /// **'والسيرفر بيحتفظ بصورة مشفّرة من المفتاح مع الشراء لحد ما الشراء يتمسح.'**
  String get privacyDeleteIosServer;

  /// S · both words are accepted in either language
  ///
  /// In ar, this message translates to:
  /// **'اكتب «احذف» أو DELETE عشان تأكد'**
  String get privacyDeleteTypePrompt;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'كلمة التأكيد'**
  String get privacyDeleteTypeLabel;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الكلمة مش مطابقة'**
  String get privacyDeleteTypeMismatch;

  /// B · destructive, enabled on an exact match
  ///
  /// In ar, this message translates to:
  /// **'امسح كل حاجة'**
  String get privacyDeleteConfirm;

  /// L · progress
  ///
  /// In ar, this message translates to:
  /// **'بمسح…'**
  String get privacyDeleteWorking;

  /// N · shown if the server delete failed; the local wipe is never blocked (NFR-PRIV-06)
  ///
  /// In ar, this message translates to:
  /// **'النسخة اللي على السيرفر هتنتهي لوحدها.'**
  String get privacyDeleteServerCopy;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'التفضيلات'**
  String get settingsPrefsTitle;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'اللغة'**
  String get settingsPrefsLanguage;

  /// C · always in its own script
  ///
  /// In ar, this message translates to:
  /// **'العربية'**
  String get settingsPrefsLanguageAr;

  /// C · always in its own script
  ///
  /// In ar, this message translates to:
  /// **'English'**
  String get settingsPrefsLanguageEn;

  /// L · shown only when the language is Arabic
  ///
  /// In ar, this message translates to:
  /// **'الأرقام'**
  String get settingsPrefsDigits;

  /// C · the UI draws the sample glyphs
  ///
  /// In ar, this message translates to:
  /// **'عربي'**
  String get settingsPrefsDigitsArabic;

  /// C · the UI draws the sample glyphs
  ///
  /// In ar, this message translates to:
  /// **'إنجليزي'**
  String get settingsPrefsDigitsWestern;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الشكل'**
  String get settingsPrefsTheme;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'زي الموبايل'**
  String get settingsPrefsThemeSystem;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'فاتح'**
  String get settingsPrefsThemeLight;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'غامق'**
  String get settingsPrefsThemeDark;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'العملة الأساسية'**
  String get settingsPrefsCurrency;

  /// L · FR-CUR-04, off by default
  ///
  /// In ar, this message translates to:
  /// **'اعرض مجموع تقريبي (≈)'**
  String get settingsPrefsApprox;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'بيتحسب بسعر تقريبي ومكتوب عليه كده. مفيش حاجة بتتحوّل فعلاً.'**
  String get settingsPrefsApproxHint;

  /// L · FR-CUR-05, visible when the total is on
  ///
  /// In ar, this message translates to:
  /// **'حوّل المجموع لـ'**
  String get settingsPrefsCombineInto;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'يوم القبض'**
  String get settingsPrefsPayday;

  /// C · stepper value, 1 to 28
  ///
  /// In ar, this message translates to:
  /// **'يوم {day}'**
  String settingsPrefsPaydayDay(String day);

  /// C · calendar month option
  ///
  /// In ar, this message translates to:
  /// **'أول الشهر'**
  String get settingsPrefsPaydayMonth;

  /// S · validation
  ///
  /// In ar, this message translates to:
  /// **'اختار يوم من أول الشهر لحد تمانية وعشرين'**
  String get settingsPrefsPaydayRange;

  /// T · EC-21
  ///
  /// In ar, this message translates to:
  /// **'تغيّر يوم القبض في نص الدورة؟'**
  String get settingsPrefsPaydayChangeTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'الدورة الحالية هتخلص بدري، وهتبدأ دورة جديدة من يوم القبض الجديد.'**
  String get settingsPrefsPaydayChangeBody;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'هدف الدخل الشهري'**
  String get settingsPrefsIncome;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'اختياري'**
  String get settingsPrefsIncomeOptional;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'المبلغ ميكونش بالسالب'**
  String get settingsPrefsIncomeNegative;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'قفل التطبيق'**
  String get settingsPrefsAppLock;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'اقفل بعد'**
  String get settingsPrefsLockAfter;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'على طول'**
  String get settingsPrefsLockImmediately;

  /// C · count:int, n · menu choices 1, 5, 15 minutes
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{دقيقة} =2{دقيقتين} few{{n} دقايق} many{{n} دقيقة} other{{n} دقيقة}}'**
  String settingsPrefsLockAfterMinutes(int count, String n);

  /// S · platform = ios / other (A-08)
  ///
  /// In ar, this message translates to:
  /// **'{platform, select, ios{البصمة مش متاحة. هنستخدم كود الآيفون بدلها.} other{البصمة مش متاحة. هنستخدم قفل الموبايل بدلها.}}'**
  String settingsPrefsBiometricsUnavailable(String platform);

  /// T
  ///
  /// In ar, this message translates to:
  /// **'شارك إنجازك'**
  String get shareStudioTitle;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'اقفل'**
  String get shareStudioCloseA11y;

  /// C · shown only if the data exists
  ///
  /// In ar, this message translates to:
  /// **'التحويش'**
  String get shareStudioTemplateSavings;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'تقليل الدليفري'**
  String get shareStudioTemplateDelivery;

  /// C
  ///
  /// In ar, this message translates to:
  /// **'تحت الميزانية'**
  String get shareStudioTemplateBudget;

  /// L · off by default
  ///
  /// In ar, this message translates to:
  /// **'اظهر المبالغ'**
  String get shareStudioShowAmounts;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'وإنت مقفلها بتظهر النسب بس.'**
  String get shareStudioShowAmountsHint;

  /// T · card header
  ///
  /// In ar, this message translates to:
  /// **'شهادة تقدير من الكابتن زغلول'**
  String get shareStudioCertificate;

  /// T · card, percentage version
  ///
  /// In ar, this message translates to:
  /// **'وفرت {percent} من مرتبي الشهر ده!'**
  String shareStudioCardSavings(String percent);

  /// T · card, amount version
  ///
  /// In ar, this message translates to:
  /// **'وفرت {amount} الشهر ده!'**
  String shareStudioCardSavingsAmount(String amount);

  /// T · card, percentage version
  ///
  /// In ar, this message translates to:
  /// **'قللت الدليفري {percent} الشهر ده!'**
  String shareStudioCardDelivery(String percent);

  /// T · card, amount version
  ///
  /// In ar, this message translates to:
  /// **'قللت الدليفري {amount} الشهر ده!'**
  String shareStudioCardDeliveryAmount(String amount);

  /// T · card, percentage version
  ///
  /// In ar, this message translates to:
  /// **'خلصت الدورة تحت الميزانية بـ {percent}!'**
  String shareStudioCardBudget(String percent);

  /// T · card, amount version
  ///
  /// In ar, this message translates to:
  /// **'خلصت الدورة تحت الميزانية بـ {amount}!'**
  String shareStudioCardBudgetAmount(String amount);

  /// L · FR-SHR-03. One hashtag per card
  ///
  /// In ar, this message translates to:
  /// **'#زغلول_ضبط_الميزانية'**
  String get shareStudioHashtag;

  /// B · opens the system share sheet
  ///
  /// In ar, this message translates to:
  /// **'شارك'**
  String get shareStudioShare;

  /// A
  ///
  /// In ar, this message translates to:
  /// **'معاينة الكارت: {text}'**
  String shareStudioPreviewA11y(String text);

  /// S · FR-SEC-06
  ///
  /// In ar, this message translates to:
  /// **'الصورة مش متشفّرة، ولما تشاركها بتبقى بره زغلول.'**
  String get shareStudioUnencrypted;

  /// T · C-28
  ///
  /// In ar, this message translates to:
  /// **'لسه مفيش إنجاز تشاركه'**
  String get shareStudioEmptyTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'كمّل تسجيل وهتلاقي إنجازات هنا.'**
  String get shareStudioEmptyBody;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'بجهّز الكارت…'**
  String get shareStudioRendering;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'معرفتش أجهّز الصورة. جرّب تاني.'**
  String get shareStudioRenderFailed;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'عن زغلول'**
  String get aboutMainTitle;

  /// L · Western digits always
  ///
  /// In ar, this message translates to:
  /// **'الإصدار {appVersion} (رقم {build})'**
  String aboutMainVersion(String appVersion, String build);

  /// L · FR-SYNC-06
  ///
  /// In ar, this message translates to:
  /// **'قايمة التجار اتحدّثت {date}'**
  String aboutMainCatalog(String date);

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الأسعار اتحدّثت {date}'**
  String aboutMainPrices(String date);

  /// S
  ///
  /// In ar, this message translates to:
  /// **'لسه ما اتحدّثتش (شغال من غير نت)'**
  String get aboutMainNeverSynced;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'الشروط'**
  String get aboutMainTerms;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'سياسة الخصوصية'**
  String get aboutMainPrivacy;

  /// L
  ///
  /// In ar, this message translates to:
  /// **'تراخيص المصدر المفتوح'**
  String get aboutMainLicenses;

  /// L · opens the disclaimers list
  ///
  /// In ar, this message translates to:
  /// **'تنبيهات مهمة'**
  String get aboutMainDisclaimers;

  /// L · opens mail (UX-A-06)
  ///
  /// In ar, this message translates to:
  /// **'كلّم الدعم'**
  String get aboutMainSupport;

  /// L · mail subject; the body holds only common_support_codeValue
  ///
  /// In ar, this message translates to:
  /// **'مساعدة في زغلول'**
  String get aboutMainSupportSubject;

  /// T · error-handling-and-observability.md §3.1
  ///
  /// In ar, this message translates to:
  /// **'بيانات تشخيص'**
  String get aboutDiagTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'ملف فيه أكواد أعطال بس، من غير رسايل ولا مبالغ ولا أسماء. تبعته للدعم لو احتجت.'**
  String get aboutDiagBody;

  /// B · system share sheet, user-initiated (NFR-PRIV-02b)
  ///
  /// In ar, this message translates to:
  /// **'ابعت الملف'**
  String get aboutDiagShare;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مفيش أعطال مسجلة.'**
  String get aboutDiagEmpty;

  /// S · Egyptian summary above the hosted Terms of Use. Wording is a draft for legal (Q-37)
  ///
  /// In ar, this message translates to:
  /// **'الشروط باختصار: بتستخدم زغلول لإدارة فلوسك بنفسك، وقرارك المالي مسؤوليتك.'**
  String get legalTermsSummary;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اقرا الشروط كاملة'**
  String get legalTermsOpen;

  /// S · Egyptian summary above the hosted Privacy Policy. Draft for legal (Q-37)
  ///
  /// In ar, this message translates to:
  /// **'الخصوصية باختصار: بيانات فلوسك بتفضل على موبايلك، والسيرفر مبيعرفش غير اللي مكتوب في «خصوصيتك».'**
  String get legalPrivacySummary;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'اقرا السياسة كاملة'**
  String get legalPrivacyOpen;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'زغلول بيستخدم برامج مفتوحة المصدر، وده ترخيص كل واحد منها.'**
  String get legalLicensesSummary;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تراخيص المصدر المفتوح'**
  String get legalLicensesTitle;

  /// T
  ///
  /// In ar, this message translates to:
  /// **'تنبيهات مهمة'**
  String get legalDisclaimerTitle;

  /// S · Egyptian summary
  ///
  /// In ar, this message translates to:
  /// **'نصايح زغلول أفكار عامة، مش نصيحة مالية.'**
  String get legalDisclaimerCoachingSummary;

  /// E · simple standard Arabic · NFR-LEGAL-03
  ///
  /// In ar, this message translates to:
  /// **'توجيهات الكابتن زغلول وتفسيرات الرسوم البيانية واقتراحاته أفكار عامة للتوعية، وليست نصيحة مالية أو استثمارية أو قانونية. القرار النهائي لك.'**
  String get legalDisclaimerCoaching;

  /// S · Egyptian summary
  ///
  /// In ar, this message translates to:
  /// **'الأرقام تقريبية، وكشف البنك هو المرجع.'**
  String get legalDisclaimerEstimatesSummary;

  /// E · simple standard Arabic
  ///
  /// In ar, this message translates to:
  /// **'الأرقام المعروضة تقديرية، ومبنية على الرسائل التي يقرؤها التطبيق وعلى ما تدخله بنفسك، وقد تختلف عن كشوف حساباتك الرسمية.'**
  String get legalDisclaimerEstimates;

  /// S · Egyptian summary
  ///
  /// In ar, this message translates to:
  /// **'أسعار الدهب والعملات إرشادية، وممكن تتأخر عن السوق.'**
  String get legalDisclaimerPricesSummary;

  /// E · simple standard Arabic
  ///
  /// In ar, this message translates to:
  /// **'أسعار الذهب والعملات المعروضة إرشادية فقط، وقد تتأخر أو تختلف عن سعر السوق وقت التنفيذ.'**
  String get legalDisclaimerPrices;

  /// S · pointer only; the disclaimer itself is zakah_main_disclaimer (Part 2)
  ///
  /// In ar, this message translates to:
  /// **'حساب الزكاة تقدير مش فتوى. التفاصيل في شاشة الزكاة.'**
  String get legalDisclaimerZakahRef;

  /// S · pointer only; the disclaimer itself is roi_tips_disclaimer (Part 2)
  ///
  /// In ar, this message translates to:
  /// **'نصايح الاستثمار أفكار عامة مش نصيحة مالية. التفاصيل في شاشة النصايح.'**
  String get legalDisclaimerRoiRef;

  /// N · short footer for chat answers and chart tips, if the PO wants one (Q-20, Q-37)
  ///
  /// In ar, this message translates to:
  /// **'زغلول بيدّي أفكار عامة، مش نصيحة مالية.'**
  String get legalDisclaimerFooter;

  /// T · unexpected exception (FlutterError.onError), full-screen fallback, Rive oops
  ///
  /// In ar, this message translates to:
  /// **'حصلت مشكلة صغيرة'**
  String get errorsGenericUnexpectedTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'مش بسببك، وبياناتك في أمان على موبايلك. ارجع للرئيسية وجرّب تاني.'**
  String get errorsGenericUnexpectedBody;

  /// B
  ///
  /// In ar, this message translates to:
  /// **'ارجع للرئيسية'**
  String get errorsGenericGoHome;

  /// S · bug-class backend codes when a user action was waiting
  ///
  /// In ar, this message translates to:
  /// **'الحاجة دي ماتمتش. جرّب تاني كمان شوية.'**
  String get errorsGenericActionFailed;

  /// S · NetworkFailure.offline
  ///
  /// In ar, this message translates to:
  /// **'مفيش نت دلوقتي. اللي بتشوفه محفوظ على موبايلك.'**
  String get errorsNetworkOffline;

  /// S · NetworkFailure.timeout
  ///
  /// In ar, this message translates to:
  /// **'الاتصال أخد وقت طويل. جرّب تاني.'**
  String get errorsNetworkTimeout;

  /// S · NetworkFailure.server(5xx), STORE_UNAVAILABLE, UPSTREAM_UNAVAILABLE, INTERNAL
  ///
  /// In ar, this message translates to:
  /// **'السيرفر مشغول دلوقتي. هنجرّب تاني لوحدنا.'**
  String get errorsNetworkServer;

  /// S · RATE_LIMITED (respect Retry-After)
  ///
  /// In ar, this message translates to:
  /// **'الطلبات كتير شوية. استنى شوية وجرّب تاني.'**
  String get errorsNetworkRateLimited;

  /// T · DbFailure open, KEY_INVALIDATED on the DB key, CryptoFailure; full screen, Rive oops
  ///
  /// In ar, this message translates to:
  /// **'مقدرناش نفتح بياناتك'**
  String get errorsStorageOpenTitle;

  /// S
  ///
  /// In ar, this message translates to:
  /// **'ممكن ترجّعها من نسخة احتياطية أو تبدأ من جديد. الملف القديم هيفضل لحد ما تختار.'**
  String get errorsStorageOpenBody;

  /// B · opens S-04
  ///
  /// In ar, this message translates to:
  /// **'استرجع من نسخة'**
  String get errorsStorageRestore;

  /// S · confirm for backup_restore_startFresh
  ///
  /// In ar, this message translates to:
  /// **'هنمسح الملف القديم اللي مش بيتفتح. مفيش رجوع.'**
  String get errorsStorageStartFreshWarn;

  /// S · DbFailure write (EC-28); banner
  ///
  /// In ar, this message translates to:
  /// **'المساحة على الموبايل خلصت. فضّي مساحة وجرّب تاني. الرسايل اللي وصلت متحفظة.'**
  String get errorsStorageFull;

  /// T · migration failed; Rive oops
  ///
  /// In ar, this message translates to:
  /// **'التحديث ماكملش'**
  String get errorsStorageMigrationTitle;

  /// S · + common_action_tryAgain
  ///
  /// In ar, this message translates to:
  /// **'رجّعنا بياناتك زي ما كانت. جرّب تاني.'**
  String get errorsStorageMigrationBody;

  /// S · IO_ERROR
  ///
  /// In ar, this message translates to:
  /// **'حصلت مشكلة في قراءة أو حفظ ملف. جرّب تاني.'**
  String get errorsStorageIo;

  /// S · PERMISSION_DENIED; + common_action_openSettings
  ///
  /// In ar, this message translates to:
  /// **'الإذن ده مقفول. شغّله من إعدادات الموبايل.'**
  String get errorsCapturePermission;

  /// S · NOT_AVAILABLE
  ///
  /// In ar, this message translates to:
  /// **'الحاجة دي مش متاحة على الموبايل ده.'**
  String get errorsCaptureUnavailable;

  /// S · SPOOL_DECRYPT_FAILED after three tries; Settings, Capture; action capture_settings_rescan
  ///
  /// In ar, this message translates to:
  /// **'في رسايل مقدرتش أقراها. دوّر في الرسايل القديمة تاني.'**
  String get errorsCaptureSpool;

  /// S · KEY_INVALIDATED for the spool key (Android)
  ///
  /// In ar, this message translates to:
  /// **'الحماية على الموبايل اتجدّدت بعد تغيير القفل، ورسايل مستنية ممكن تكون ضاعت. دوّر في الرسايل القديمة تاني.'**
  String get errorsCaptureKeyChanged;

  /// S · CONFIG_INVALID; normally silent, shown only on the Capture screen
  ///
  /// In ar, this message translates to:
  /// **'بظبّط إعدادات اللقط لوحدي. مفيش حاجة مطلوبة منك.'**
  String get errorsCaptureConfig;

  /// S · OCR_FAILED; same advice as capture_scan_emptyBody
  ///
  /// In ar, this message translates to:
  /// **'معرفتش أقرا الصورة. جرّب صورة أوضح أو اكتب الحركة بإيدك.'**
  String get errorsCaptureOcr;

  /// S · domain CurrencyMismatch; amounts are never converted
  ///
  /// In ar, this message translates to:
  /// **'العملتين مختلفتين، مينفعش نجمعهم.'**
  String get errorsMoneyCurrency;

  /// S · domain OffsetExceedsAmount
  ///
  /// In ar, this message translates to:
  /// **'المبلغ الراجع أكبر من الحركة نفسها.'**
  String get errorsMoneyOffset;

  /// S · same text as gold_account_signInAgain; Settings only
  ///
  /// In ar, this message translates to:
  /// **'سجّل دخول تاني عشان تكمّل.'**
  String get errorsAccountTokenExpired;

  /// S · INSTALL_EXISTS and INSTALL_TOKEN_INVALID when a user action was waiting (the app re-registers silently first)
  ///
  /// In ar, this message translates to:
  /// **'العملية ماتمتش. جرّب تاني كمان شوية.'**
  String get errorsAccountFailed;
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
