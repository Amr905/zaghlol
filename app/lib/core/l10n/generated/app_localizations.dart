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
