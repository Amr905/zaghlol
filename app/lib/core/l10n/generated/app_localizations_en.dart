// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Zaghlol';

  @override
  String get commonNavHome => 'Home';

  @override
  String get commonNavInsights => 'Insights';

  @override
  String get commonNavMoney => 'Money';

  @override
  String get commonNavZaghlol => 'Zaghlol';

  @override
  String get commonNavAddA11y => 'Quick add';

  @override
  String get appLockTitle => 'Zaghlol is locked';

  @override
  String get appLockUnlock => 'Unlock';

  @override
  String get appLockReason => 'Confirm it\'s you to open Zaghlol';

  @override
  String get appLockFailed => 'That didn\'t work. Try again.';

  @override
  String get appLockUnavailable =>
      'Set a screen lock (PIN, pattern or password) on your phone, then try again.';

  @override
  String get appLockLockedOut => 'Too many tries. Wait a bit and try again.';

  @override
  String get appLockRootedTitle => 'Weaker protection on this phone';

  @override
  String get appLockRootedBody =>
      'This phone looks rooted or jailbroken, so your data is less protected here. Zaghlol still works, but be careful.';

  @override
  String get appLockRootedOk => 'OK';

  @override
  String get homeQuickAddTitle => 'What do you want to add?';

  @override
  String get homeQuickAddSay => 'Say';

  @override
  String get homeQuickAddType => 'Type';

  @override
  String get homeQuickAddScan => 'Scan';

  @override
  String get homeQuickAddAsset => 'Asset';

  @override
  String get homeQuickAddSayA11y => 'Tell Zaghlol';

  @override
  String get homeQuickAddTypeA11y => 'Type a transaction';

  @override
  String get homeQuickAddScanA11y => 'Scan a screenshot';

  @override
  String get homeQuickAddAssetA11y => 'Add an asset';

  @override
  String get ingestionReviewTitle => 'Needs your review 👀';

  @override
  String get notificationsChannelName => 'Alerts';

  @override
  String get commonActionSave => 'Save';

  @override
  String get commonActionCancel => 'Cancel';

  @override
  String get commonActionDone => 'Done';

  @override
  String get commonActionConfirm => 'Confirm';

  @override
  String get commonActionDismiss => 'Dismiss';

  @override
  String get commonActionUndo => 'Undo';

  @override
  String get commonActionTryAgain => 'Try again';

  @override
  String get commonActionSkip => 'Skip';

  @override
  String get commonActionContinue => 'Continue';

  @override
  String get commonActionNotNow => 'Not now';

  @override
  String get commonActionLater => 'Later';

  @override
  String get commonActionEdit => 'Edit';

  @override
  String get commonActionDelete => 'Delete';

  @override
  String get commonActionClose => 'Close';

  @override
  String get commonActionBackA11y => 'Back';

  @override
  String get commonActionMoreA11y => 'More options';

  @override
  String get commonActionSeeAll => 'See all';

  @override
  String get commonActionClearFilter => 'Clear filter';

  @override
  String get commonActionOpenSettings => 'Open settings';

  @override
  String get commonActionFix => 'Fix';

  @override
  String get commonActionYes => 'Yes';

  @override
  String get commonActionNo => 'No';

  @override
  String get commonActionSelect => 'Select';

  @override
  String get commonActionSelectAll => 'Select all';

  @override
  String get commonActionSend => 'Send';

  @override
  String get commonActionLink => 'Link';

  @override
  String get commonActionUnlink => 'Unlink';

  @override
  String get commonActionMore => 'More';

  @override
  String get commonActionShow => 'Show';

  @override
  String get commonActionHide => 'Hide';

  @override
  String get commonActionLearnMore => 'Learn more';

  @override
  String get commonActionSearchA11y => 'Search';

  @override
  String get commonDiscardTitle => 'Discard changes?';

  @override
  String get commonDiscardBody => 'Anything you haven\'t saved will be lost.';

  @override
  String get commonDiscardConfirm => 'Discard';

  @override
  String get commonDiscardKeep => 'Keep editing';

  @override
  String get commonNavSettingsA11y => 'Settings';

  @override
  String get commonCardFilterAll => 'All cards';

  @override
  String commonCardFilterCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n cards',
      one: '1 card',
    );
    return '$_temp0';
  }

  @override
  String get commonCardFilterSheetTitle => 'Show which cards?';

  @override
  String get commonCardFilterClearA11y => 'Clear card filter';

  @override
  String commonCardFilterActiveA11y(String cards) {
    return 'Filter on: $cards';
  }

  @override
  String commonCurrencyApproxChip(String currency) {
    return '≈ $currency';
  }

  @override
  String commonCurrencyApproxCaption(String date) {
    return 'Approx. at $date rate';
  }

  @override
  String get commonCurrencyApproxA11y => 'approximately';

  @override
  String get commonBadgeStale => 'Out of date';

  @override
  String get commonBadgeStaleA11y => 'This rate is more than a day old';

  @override
  String get commonMoneyMaskedA11y => 'Amount hidden';

  @override
  String commonMoneyCurrencyPagerA11y(
    String currency,
    String index,
    String total,
  ) {
    return 'Page $index of $total: $currency';
  }

  @override
  String get commonSourceSms => 'SMS';

  @override
  String get commonSourceNotification => 'Notification';

  @override
  String get commonSourceApplePay => 'Apple Pay';

  @override
  String get commonSourceShortcut => 'Shortcut';

  @override
  String get commonSourceScan => 'Scan';

  @override
  String get commonSourceStatement => 'Statement';

  @override
  String get commonSourceCsv => 'CSV';

  @override
  String get commonSourceVoice => 'Voice';

  @override
  String get commonSourceManual => 'Manual';

  @override
  String get commonSourceShared => 'Shared message';

  @override
  String get commonTxnTypeExpense => 'Expense';

  @override
  String get commonTxnTypeIncome => 'Income';

  @override
  String get commonTxnTypeTransfer => 'Transfer';

  @override
  String get commonTxnTypeInternal => 'To yourself';

  @override
  String get commonTxnTypeRefund => 'Refund';

  @override
  String get commonTxnTypeReimbursement => 'Money back';

  @override
  String get commonTxnTypeDeclined => 'Declined';

  @override
  String get commonAccountTypeDebit => 'Debit';

  @override
  String get commonAccountTypeCredit => 'Credit';

  @override
  String get commonAccountTypeAccount => 'Bank account';

  @override
  String get commonAccountTypeWallet => 'Wallet';

  @override
  String get commonAccountTypeBnpl => 'Pay later';

  @override
  String get commonAccountTypeCash => 'Cash';

  @override
  String get commonAccountTypeMultiCurrency => 'Multi-currency';

  @override
  String get commonChannelSms => 'Bank SMS';

  @override
  String get commonChannelSmsShort => 'SMS';

  @override
  String get commonChannelNotifications => 'App notifications';

  @override
  String get commonChannelNotificationsShort => 'Notifications';

  @override
  String get commonChannelApplePay => 'Apple Pay';

  @override
  String get commonChannelOnA11y => 'on';

  @override
  String get commonChannelOffA11y => 'off';

  @override
  String get commonDateToday => 'Today';

  @override
  String get commonDateYesterday => 'Yesterday';

  @override
  String get commonDateJustNow => 'Just now';

  @override
  String commonDateMinutesAgo(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n min ago',
      one: '1 min ago',
      zero: 'Just now',
    );
    return '$_temp0';
  }

  @override
  String commonDateHoursAgo(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n hr ago',
      one: '1 hr ago',
    );
    return '$_temp0';
  }

  @override
  String commonDateDateTime(String date, String time) {
    return '$date, $time';
  }

  @override
  String commonDateRange(String end, String start) {
    return '$start – $end';
  }

  @override
  String get commonPeriodThisCycle => 'This cycle';

  @override
  String get commonPeriodLastCycle => 'Last cycle';

  @override
  String get commonPeriodThisMonth => 'This month';

  @override
  String get commonPeriodPickMonth => 'A month';

  @override
  String get commonPeriodCustom => 'Custom range';

  @override
  String commonPeriodLastMonths(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Last $n months',
      one: 'Last month',
    );
    return '$_temp0';
  }

  @override
  String commonPeriodInLastMonths(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'in the last $n months',
      one: 'in the last month',
    );
    return '$_temp0';
  }

  @override
  String commonProgressPercent(String n) {
    return '$n%';
  }

  @override
  String commonFileSizeMb(String n) {
    return '$n MB';
  }

  @override
  String commonFileSizeKb(String n) {
    return '$n KB';
  }

  @override
  String get commonPlatformAndroid => 'Android';

  @override
  String get commonPlatformIos => 'iPhone';

  @override
  String get commonValidationAmountRequired => 'Enter an amount above zero';

  @override
  String get commonValidationAmountTooLarge =>
      'That amount looks too big — check it';

  @override
  String commonValidationAmountDecimals(int count, String currency, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$currency allows $n decimals',
      one: '$currency allows 1 decimal',
      zero: '$currency doesn\'t use decimals',
    );
    return '$_temp0';
  }

  @override
  String get commonValidationCurrencyRequired => 'Choose a currency';

  @override
  String get commonValidationDateFuture => 'Date can\'t be in the future';

  @override
  String get commonValidationDateRange =>
      'Start date must be before the end date';

  @override
  String get commonValidationLast4 => 'Enter the last four digits';

  @override
  String get commonValidationNameRequired => 'Enter a name';

  @override
  String commonValidationNameLength(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Keep it to $n characters',
      one: 'Keep it to 1 character',
    );
    return '$_temp0';
  }

  @override
  String get commonValidationNameTaken => 'That name\'s already used';

  @override
  String commonValidationNoteLength(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Notes can be up to $n characters',
      one: 'Notes can be up to 1 character',
    );
    return '$_temp0';
  }

  @override
  String get commonValidationCategoryRequired => 'Choose a category';

  @override
  String get commonValidationAccountRequired => 'Choose an account';

  @override
  String get commonValidationChoiceRequired => 'Pick one';

  @override
  String get commonErrorLoadFailed =>
      'Couldn\'t load this right now. Your data is safe on this phone.';

  @override
  String get commonErrorSaveFailed =>
      'Couldn\'t save. Try again — what you entered is still here.';

  @override
  String get commonErrorNetwork =>
      'Can\'t reach the server right now. Your money data is safe on this phone — try again in a bit.';

  @override
  String get commonGoldBadge => 'Gold';

  @override
  String get commonGoldUnlock => 'Unlock with Gold';

  @override
  String get commonGoldLockedA11y => 'Available with Zaghlol Gold';

  @override
  String get mascotAvatarLabelA11y => 'Captain Zaghlol';

  @override
  String get mascotPullRefreshingA11y => 'Refreshing…';

  @override
  String get mascotSavedLine1 => 'Saved ✓';

  @override
  String get mascotSavedLine2 => 'Done — it\'s in the books ✓';

  @override
  String get mascotSavedLine3 => 'Logged it ✓';

  @override
  String get mascotTapLine1 => 'Hey, that tickles! 😄';

  @override
  String get mascotTapLine2 => 'Still here, keeping an eye on your money';

  @override
  String get mascotTapLine3 => 'Every bit you save grows me a new feather 🪶';

  @override
  String get mascotTapLine4 => 'Captain reporting. You\'re the boss.';

  @override
  String get mascotTapLine5 => 'Save today, treat yourself tomorrow';

  @override
  String get mascotTapLine6 =>
      'I only read bank messages. The rest is none of my business.';

  @override
  String get mascotTapLine7 => 'Pigeon or accountant? Both.';

  @override
  String get mascotTapLine8 => 'Quick wings, tidy numbers';

  @override
  String get onboardingWelcomeLanguageToggle => 'عربي';

  @override
  String get onboardingWelcomeLanguageToggleA11y => 'Switch to Arabic';

  @override
  String get onboardingWelcomeTitle => 'Hi! I\'m Captain Zaghlol.';

  @override
  String get onboardingWelcomeSubtitle =>
      'I\'ll show you where your money goes — straight from your bank messages, no typing needed.';

  @override
  String get onboardingWelcomePointOnPhone =>
      'Your money data stays on your phone';

  @override
  String get onboardingWelcomePointNoPassword =>
      'We\'ll never ask for your bank password';

  @override
  String get onboardingWelcomePointNoAds => 'No ads';

  @override
  String get onboardingWelcomeStart => 'Let\'s go';

  @override
  String get onboardingWelcomeRestore => 'I already use Zaghlol';

  @override
  String get onboardingWelcomePrivacyLink => 'Privacy details';

  @override
  String onboardingAndroidSetupStep(String step, String total) {
    return 'Step $step of $total';
  }

  @override
  String get onboardingAndroidSetupSmsTitle => 'Let me read your bank texts';

  @override
  String get onboardingAndroidSetupSmsSubtitle =>
      'I\'ll sort out all your spending for you.';

  @override
  String get onboardingAndroidSetupSmsPointSenders =>
      'I only read messages from banks, wallets and InstaPay';

  @override
  String get onboardingAndroidSetupSmsPointPersonal =>
      'Your personal messages are never read or saved';

  @override
  String get onboardingAndroidSetupSmsPointOnPhone =>
      'Your money data stays on this phone';

  @override
  String get onboardingAndroidSetupSmsAllow => 'Allow bank texts';

  @override
  String get onboardingAndroidSetupSmsGranted => 'SMS allowed ✓';

  @override
  String get onboardingAndroidSetupScanTitle => 'Reading your past messages…';

  @override
  String onboardingAndroidSetupScanDepth(String period) {
    return '$period · carry on, I\'m on it';
  }

  @override
  String onboardingAndroidSetupScanCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $n transactions',
      one: 'Found 1 transaction',
      zero: 'Still looking…',
    );
    return '$_temp0';
  }

  @override
  String get onboardingAndroidSetupScanBanks => 'Banks found so far:';

  @override
  String get onboardingAndroidSetupNotifTitle =>
      'Catch bank app notifications too?';

  @override
  String get onboardingAndroidSetupNotifBody =>
      'Some banks and wallets only send in-app alerts, not SMS — like Wise, Revolut and Payoneer.';

  @override
  String get onboardingAndroidSetupNotifPrivacy =>
      'I only read notifications from bank and wallet apps — never WhatsApp or anything else.';

  @override
  String get onboardingAndroidSetupNotifTurnOn => 'Turn on notifications';

  @override
  String get onboardingAndroidSetupNotifOsHint =>
      'On the next screen, find Zaghlol and switch it on.';

  @override
  String get onboardingAndroidSetupNotifGranted => 'Notifications on ✓';

  @override
  String get onboardingAndroidSetupNotifStillOff =>
      'Still off. You can turn it on later in Settings.';

  @override
  String get onboardingAndroidSetupDegradedTitle => 'SMS reading is off';

  @override
  String get onboardingAndroidSetupDegradedBody =>
      'You can still track your spending:';

  @override
  String get onboardingAndroidSetupDegradedNotif => 'Bank app notifications';

  @override
  String get onboardingAndroidSetupDegradedNotifOn => 'Turn on';

  @override
  String get onboardingAndroidSetupDegradedShare =>
      'Share or paste a bank message';

  @override
  String get onboardingAndroidSetupDegradedShareHow => 'How?';

  @override
  String get onboardingAndroidSetupDegradedManual =>
      'Log cash by voice or typing';

  @override
  String get onboardingAndroidSetupDegradedRetry => 'Ask again';

  @override
  String get onboardingAndroidSetupDegradedSettingsHint =>
      'To turn it on, open Settings and allow Zaghlol to read SMS.';

  @override
  String get onboardingAndroidSetupPlayUnavailable =>
      'This version of Zaghlol can\'t read SMS, but notifications and sharing work fine.';

  @override
  String onboardingIosSetupStep(String step, String total) {
    return 'Step $step of $total';
  }

  @override
  String get onboardingIosSetupShortcutTitle => 'We\'ll use Shortcuts';

  @override
  String get onboardingIosSetupShortcutWhy =>
      'iPhone doesn\'t let apps read texts, so Shortcuts pass them to me.';

  @override
  String get onboardingIosSetupShortcutLead => 'One tap adds:';

  @override
  String get onboardingIosSetupShortcutSmsTitle => 'Bank texts';

  @override
  String get onboardingIosSetupShortcutSmsSub =>
      'Catches bank and InstaPay texts, in Arabic and English';

  @override
  String get onboardingIosSetupShortcutApplePayTitle => 'Apple Pay payments';

  @override
  String get onboardingIosSetupShortcutApplePaySub =>
      'Logs every tap-to-pay as it happens';

  @override
  String get onboardingIosSetupShortcutOnce =>
      'Just once — then everything logs itself.';

  @override
  String get onboardingIosSetupShortcutAdd => 'Add Zaghlol shortcut';

  @override
  String get onboardingIosSetupHowItWorks => 'How it works (30 sec)';

  @override
  String get onboardingIosSetupHowStep1 =>
      'When a bank text arrives, your iPhone runs the shortcut by itself.';

  @override
  String get onboardingIosSetupHowStep2 =>
      'The shortcut hands the text to Zaghlol on this same phone — it isn\'t sent anywhere.';

  @override
  String get onboardingIosSetupHowStep3 =>
      'Zaghlol reads the amount and merchant and logs it. That\'s it.';

  @override
  String get onboardingIosSetupChecking => 'One sec — checking your shortcuts…';

  @override
  String get onboardingIosSetupShortcutsMissing =>
      'Couldn\'t open the Shortcuts app. Get it from the App Store and try again.';

  @override
  String get onboardingIosSetupCheckTitle => 'Let\'s make sure it all works';

  @override
  String get onboardingIosSetupCheckSubtitle =>
      'Zaghlol is checking which automations were added.';

  @override
  String get onboardingIosSetupCheckSmsAr => 'Bank texts (Arabic)';

  @override
  String get onboardingIosSetupCheckSmsEn => 'Bank texts (English)';

  @override
  String get onboardingIosSetupCheckApplePay => 'Apple Pay payments';

  @override
  String onboardingIosSetupCheckCount(int count, String done, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$done of $n automations',
      one: '$done of 1 automation',
    );
    return '$_temp0';
  }

  @override
  String get onboardingIosSetupCheckNeedsRun => 'Needs \"Run Immediately\"';

  @override
  String get onboardingIosSetupCheckOkA11y => 'Working';

  @override
  String get onboardingIosSetupCheckMissingA11y => 'Missing';

  @override
  String get onboardingIosSetupFixTitle => 'How to fix it';

  @override
  String get onboardingIosSetupFixStep1 => 'Open Shortcuts, then Automation';

  @override
  String onboardingIosSetupFixStep2(String automationName) {
    return 'Choose \"$automationName\"';
  }

  @override
  String get onboardingIosSetupFixStep3 => 'Turn on \"Run Immediately\"';

  @override
  String get onboardingIosSetupCheckUnknown =>
      'Can\'t tell yet — we\'ll know when your next bank text arrives.';

  @override
  String get onboardingIosSetupCheckAgain => 'Check again';

  @override
  String get onboardingIosSetupCheckAllGood => 'All set ✓ Zaghlol is ready';

  @override
  String get onboardingIosSetupFirstTitle => 'Let\'s log your first expense!';

  @override
  String get onboardingIosSetupFirstBody =>
      'Until your first bank text comes in, tell me what you spent today.';

  @override
  String get onboardingIosSetupFirstSay => 'Say it';

  @override
  String get onboardingIosSetupFirstSayHint => '\"45 on coffee\"';

  @override
  String get onboardingIosSetupFirstType => 'Type it';

  @override
  String get onboardingIosSetupFirstTypeHint => 'Amount and category';

  @override
  String get onboardingIosSetupFirstOnlineBanks =>
      'Use Wise, Revolut or Payoneer?';

  @override
  String get onboardingIosSetupFirstOnlineBanksSub =>
      'See how to track them on iPhone';

  @override
  String get onboardingIosSetupFirstStatement => 'Got a bank statement?';

  @override
  String get onboardingIosSetupFirstStatementSub =>
      'Add past months in one go with Gold';

  @override
  String get backupRestoreTitle => 'Restore from backup';

  @override
  String get backupRestoreWhereTitle => 'Where\'s your backup?';

  @override
  String get backupRestoreOptionDrive => 'Google Drive';

  @override
  String get backupRestoreOptionICloud => 'iCloud';

  @override
  String backupRestoreSigningIn(String provider) {
    return 'Signing in to $provider…';
  }

  @override
  String get backupRestoreSearching => 'Looking for your Zaghlol backup…';

  @override
  String get backupRestoreFoundTitle => 'Backup found';

  @override
  String backupRestoreFoundMeta(String date, String size) {
    return '$date · $size';
  }

  @override
  String backupRestoreFoundFrom(String appVersion, String platform) {
    return 'From: $platform · v$appVersion';
  }

  @override
  String get backupRestoreVersionsTitle => 'Your backups';

  @override
  String get backupRestoreVersionNewest => 'Newest';

  @override
  String get backupRestorePassphraseLabel => 'Backup passphrase';

  @override
  String get backupRestoreRestore => 'Restore';

  @override
  String get backupRestorePassphraseRequired => 'Enter the passphrase';

  @override
  String get backupRestorePassphraseWrong =>
      'That passphrase doesn\'t open this backup';

  @override
  String get backupRestoreForgotLink => 'Forgot the passphrase?';

  @override
  String get backupRestoreForgotBody =>
      'Sorry, it can\'t be recovered. Only that passphrase opens this backup — nobody else can, not even us. You can start fresh.';

  @override
  String get backupRestoreRestoring => 'Restoring your data…';

  @override
  String get backupRestoreKeepOpen => 'Keep Zaghlol open until this finishes';

  @override
  String get backupRestoreEmptyTitle => 'No Zaghlol backup on this account';

  @override
  String get backupRestoreTryAnotherAccount => 'Try another account';

  @override
  String get backupRestoreStartFresh => 'Start fresh';

  @override
  String backupRestoreErrorNetwork(String provider) {
    return 'Can\'t reach $provider right now. Check your connection and try again.';
  }

  @override
  String backupRestoreErrorSignIn(String provider) {
    return 'Signing in to $provider didn\'t finish. Try again.';
  }

  @override
  String get backupRestoreErrorNewer =>
      'This backup was made with a newer Zaghlol. Update the app to restore it.';

  @override
  String get backupRestoreUpdate => 'Update Zaghlol';

  @override
  String get backupRestoreErrorCorrupted => 'This backup can\'t be read.';

  @override
  String get backupRestoreTryOlder => 'Try an older backup';

  @override
  String get backupRestoreDoneBanner =>
      'Your data\'s back ✓ Now let Zaghlol read on this phone.';

  @override
  String get backupRestoreDoneAction => 'Set it up';

  @override
  String get securityLockTitle => 'Zaghlol is locked';

  @override
  String securityLockUnlock(String method) {
    String _temp0 = intl.Intl.selectLogic(method, {
      'faceId': 'Unlock with Face ID',
      'touchId': 'Unlock with Touch ID',
      'fingerprint': 'Use fingerprint',
      'face': 'Use face unlock',
      'other': 'Unlock',
    });
    return '$_temp0';
  }

  @override
  String securityLockUsePasscode(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'Use passcode',
      'other': 'Use phone lock',
    });
    return '$_temp0';
  }

  @override
  String get securityLockPromptReason => 'Unlock Zaghlol';

  @override
  String get securityLockPromptSubtitle => 'So only you can see your money';

  @override
  String get securityLockFailed => 'Didn\'t unlock. Try again.';

  @override
  String get securityLockBiometricsGone =>
      'Biometrics aren\'t available — use your phone lock instead.';

  @override
  String get onboardingScanResultsTitle => 'All done! 🎉';

  @override
  String onboardingScanResultsFound(int count, String n, String period) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Found $n transactions $period',
      one: 'Found 1 transaction $period',
    );
    return '$_temp0';
  }

  @override
  String get onboardingScanResultsStatAuto => 'Sorted for you';

  @override
  String get onboardingScanResultsStatReview => 'Waiting for you';

  @override
  String get onboardingScanResultsStatCards => 'Cards & accounts';

  @override
  String get onboardingScanResultsCardsTitle => 'Are these your cards?';

  @override
  String onboardingScanResultsCardSubtitle(int count, String n, String type) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$type · $n transactions',
      one: '$type · 1 transaction',
    );
    return '$_temp0';
  }

  @override
  String get onboardingScanResultsGuessCredit => 'Looks like a credit card';

  @override
  String get onboardingScanResultsCreditBadge => 'Credit?';

  @override
  String onboardingScanResultsCreditPrompt(String card) {
    return '$card looks like a credit card. Tell me the limit and due date and I\'ll remind you before it\'s due.';
  }

  @override
  String get onboardingScanResultsCreditYes => 'Yes, set it up';

  @override
  String get onboardingScanResultsNotMineHint =>
      'Not yours, or a work card? Tap it to stop tracking it.';

  @override
  String get onboardingScanResultsShowMe => 'Show me my money';

  @override
  String onboardingScanResultsRescanToast(String card, int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $n transactions to $card',
      one: 'Added 1 transaction to $card',
      zero: 'No new transactions for $card',
    );
    return '$_temp0';
  }

  @override
  String homeGreetingByTime(String part) {
    String _temp0 = intl.Intl.selectLogic(part, {
      'morning': 'Good morning ☀️',
      'afternoon': 'Good afternoon ☀️',
      'evening': 'Good evening 🌙',
      'other': 'Hello 👋',
    });
    return '$_temp0';
  }

  @override
  String get homeGreetingFirstVisit => 'Welcome aboard 👋';

  @override
  String get homeHeroSafeToSpend => 'Safe to spend today';

  @override
  String get homeHeroPerDay => 'a day';

  @override
  String homeHeroDaysToPayday(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n days to payday',
      one: '1 day to payday',
      zero: 'Payday is today',
    );
    return '$_temp0';
  }

  @override
  String get homeHeroCalendarMonth => 'until you tell me your payday';

  @override
  String get homeHeroSpentThisMonth => 'Spent this month';

  @override
  String get homeHeroSpentThisCycle => 'Spent this cycle';

  @override
  String get homeHeroSetBudgetHint =>
      'Set a budget to see what\'s safe to spend each day';

  @override
  String get homeHeroSetBudget => 'Set a budget';

  @override
  String get homeHeroBudgetUsedUp =>
      'This cycle\'s budget is used up — go easy on the rest';

  @override
  String get homeHeroKpiIncome => 'Income';

  @override
  String get homeHeroKpiSpent => 'Spent';

  @override
  String get homeHeroKpiLeft => 'Left';

  @override
  String homeHeroApproxTitle(String currency) {
    return 'Everything, roughly in $currency';
  }

  @override
  String homeHeroSummaryA11y(
    String amount,
    String income,
    String left,
    String payday,
    String spent,
  ) {
    return 'Safe to spend today: $amount. $payday. Income $income, spent $spent, left $left.';
  }

  @override
  String homeMascotShockedCategory(String category, String percent) {
    return 'Heads up! $category is at $percent of its budget and the cycle\'s still young.';
  }

  @override
  String homeMascotShockedCategoryAlt(String category, String percent) {
    return '$category is nearly gone — $percent used already. Ease off a little?';
  }

  @override
  String homeMascotShockedDining(String percent) {
    return 'Eating out and delivery are up $percent on your usual. Missing your kitchen? 🍳';
  }

  @override
  String homeMascotDetectiveDuplicate(String amount, String merchant) {
    return '$merchant charged you $amount twice within minutes. Worth a look.';
  }

  @override
  String get homeMascotDetectiveDuplicateAction => 'Take a look';

  @override
  String homeMascotDetectiveSubscription(String amount, String merchant) {
    return 'Looks like a monthly subscription: $merchant, $amount. Want me to track it?';
  }

  @override
  String get homeMascotDetectiveSubscriptionTrack => 'Track it';

  @override
  String get homeMascotDetectiveSubscriptionNot => 'Not a subscription';

  @override
  String homeMascotDetectiveSelfTransfer(
    String amount,
    String fromCard,
    String toCard,
  ) {
    return '$amount moved from $fromCard to $toCard. That\'s you paying you, so it\'s not spending 👌';
  }

  @override
  String get homeMascotProudOnTrack =>
      'Nice one! You\'re spending under plan so far 👏';

  @override
  String homeMascotProudSavedMore(String amount) {
    return 'Look at you! $amount more saved than last cycle 👏';
  }

  @override
  String get homeMascotProudGoal => 'Goal hit this cycle! 🎯 You\'ve got this';

  @override
  String homeMascotPayday(String amount) {
    return 'Payday! $amount just landed 🎉 Let\'s plan it from day one';
  }

  @override
  String get homeMascotDismissA11y => 'Dismiss message';

  @override
  String homePromptPayday(String amount, String day) {
    return 'I spotted a salary of $amount landing on day $day each month. Is that your payday?';
  }

  @override
  String homePromptPaydayYes(String day) {
    return 'Yes, day $day';
  }

  @override
  String homePromptPaydayMonthStart(String amount) {
    return 'I spotted a salary of $amount arriving at the end of the month. Shall we track each calendar month, from the 1st?';
  }

  @override
  String get homePromptPaydayMonthStartYes => 'Yes, from the 1st';

  @override
  String get homePromptBudget =>
      'First full cycle done! Want to set a budget for the next one?';

  @override
  String get homePromptBudgetYes => 'Let\'s do it';

  @override
  String get homePromptBackup =>
      'A week of data so far. Make a free backup so it\'s safe if anything happens to your phone.';

  @override
  String get homePromptBackupYes => 'Back up';

  @override
  String homePromptAppLockTitle(String method) {
    String _temp0 = intl.Intl.selectLogic(method, {
      'faceId': 'Lock Zaghlol with Face ID?',
      'touchId': 'Lock Zaghlol with Touch ID?',
      'fingerprint': 'Lock Zaghlol with your fingerprint?',
      'face': 'Lock Zaghlol with face unlock?',
      'other': 'Lock Zaghlol with your phone lock?',
    });
    return '$_temp0';
  }

  @override
  String get homePromptAppLockSub => 'Keep your money for your eyes only';

  @override
  String get homePromptAppLockOn => 'App lock is on ✓';

  @override
  String get homePromptFinishSetup => 'Finish setup';

  @override
  String homePromptFinishSetupSteps(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n steps left',
      one: '1 step left',
    );
    return '$_temp0';
  }

  @override
  String homeBannerReview(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n waiting for your review 👀',
      one: '1 waiting for your review 👀',
    );
    return '$_temp0';
  }

  @override
  String homeBannerScanning(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Reading your messages… $n found so far',
      one: 'Reading your messages… 1 found so far',
      zero: 'Reading your messages…',
    );
    return '$_temp0';
  }

  @override
  String get homeBannerScanFailed => 'Couldn\'t read your messages';

  @override
  String get homeBannerSmsOff =>
      'Bank SMS reading is off, so I might miss some transactions.';

  @override
  String get homeBannerNotifOff =>
      'Bank app notifications are off, so I might miss some transactions.';

  @override
  String get homeBannerShortcutsBroken =>
      'Your shortcuts need a fix so nothing slips past me.';

  @override
  String homeBannerShortcutsQuiet(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No bank texts logged in $n days. Are your shortcuts still on?',
      one: 'No bank texts logged since yesterday. Are your shortcuts still on?',
    );
    return '$_temp0';
  }

  @override
  String get homeBannerShortcutsCheck => 'Check';

  @override
  String homeBannerRooted(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'This iPhone is jailbroken, so your data is less protected.',
      'other': 'This phone is rooted, so your data is less protected.',
    });
    return '$_temp0';
  }

  @override
  String get homeFeedTitle => 'Recent';

  @override
  String get homeEmptyTitle => 'No transactions yet';

  @override
  String get homeEmptyBodyWaiting =>
      'They\'ll show up here as soon as a bank message arrives.';

  @override
  String get homeEmptyBodyAdd =>
      'Log your first expense and I\'ll take it from there.';

  @override
  String get homeEmptyAdd => 'Add first expense';

  @override
  String homeEmptyFilter(String cards) {
    return 'No transactions for $cards this cycle';
  }

  @override
  String transactionsRowSubtitle(String card, String source, String time) {
    return '$card · $time · $source';
  }

  @override
  String get transactionsRowInternalTitle => 'To yourself';

  @override
  String transactionsRowInternalSubtitle(String fromCard, String toCard) {
    return '$fromCard → $toCard · Excluded from spending';
  }

  @override
  String get transactionsRowDeclined => 'Declined · not counted';

  @override
  String transactionsRowReimbursed(String back, String paid) {
    return 'You paid $paid · got back $back';
  }

  @override
  String transactionsRowRefund(String merchant) {
    return 'Refund from $merchant';
  }

  @override
  String get transactionsRowNeedsReviewA11y => 'Needs your review';

  @override
  String transactionsRowLabelA11y(
    String amount,
    String card,
    String category,
    String merchant,
    String time,
  ) {
    return '$merchant, $amount, $category, $card, $time';
  }

  @override
  String get transactionsRowSwipeCategory => 'Change category';

  @override
  String get transactionsRowSwipeSplit => 'Split / money back';

  @override
  String get transactionsListTitle => 'Transactions';

  @override
  String get transactionsListSearchHint => 'Merchant, note or amount…';

  @override
  String get transactionsListFilterPeriod => 'Dates';

  @override
  String get transactionsListFilterCategory => 'Category';

  @override
  String get transactionsListFilterType => 'Type';

  @override
  String get transactionsListFilterSource => 'Source';

  @override
  String transactionsListFilterCount(String label, String n) {
    return '$label · $n';
  }

  @override
  String get transactionsListRangeTitle => 'Pick dates';

  @override
  String get transactionsListRangeFrom => 'From';

  @override
  String get transactionsListRangeTo => 'To';

  @override
  String transactionsListDayTotalA11y(String amount) {
    return 'Day total $amount';
  }

  @override
  String get transactionsListEmptyTitle =>
      'Your transactions will show up here';

  @override
  String get transactionsListEmptyBody =>
      'From your bank messages — or add them yourself.';

  @override
  String get transactionsListEmptyAdd => 'Add expense';

  @override
  String transactionsListNoResults(String query) {
    return 'Nothing matches \"$query\"';
  }

  @override
  String get transactionsListNoResultsFilters =>
      'No transactions match these filters';

  @override
  String get transactionsListClearAll => 'Clear search & filters';

  @override
  String transactionsListSelectedTitle(String n) {
    return '$n selected';
  }

  @override
  String get transactionsListBulkCategory => 'Category';

  @override
  String get transactionsListBulkAccount => 'Card';

  @override
  String get transactionsListBulkRule => 'Always use this for these merchants';

  @override
  String transactionsListBulkChanged(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n transactions updated',
      one: '1 transaction updated',
    );
    return '$_temp0';
  }

  @override
  String transactionsListBulkDeleteTitle(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $n transactions?',
      one: 'Delete 1 transaction?',
    );
    return '$_temp0';
  }

  @override
  String get transactionsListBulkDeleteBody =>
      'You won\'t be able to get them back.';

  @override
  String transactionsListBulkDeleted(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n transactions deleted',
      one: '1 transaction deleted',
    );
    return '$_temp0';
  }

  @override
  String transactionsListSelectRowA11y(String merchant) {
    return 'Select $merchant';
  }

  @override
  String transactionsDetailOriginal(String amount) {
    return 'Original: $amount';
  }

  @override
  String get transactionsDetailFieldCard => 'Card';

  @override
  String get transactionsDetailFieldDate => 'When';

  @override
  String get transactionsDetailFieldBalance => 'Balance after';

  @override
  String get transactionsDetailFieldSource => 'Source';

  @override
  String get transactionsDetailFieldReference => 'Reference';

  @override
  String get transactionsDetailFieldNote => 'Note';

  @override
  String get transactionsDetailNoteAdd => 'Add a note';

  @override
  String get transactionsDetailNoteHint => 'Write a note…';

  @override
  String get transactionsDetailSplit => 'Split / money back';

  @override
  String get transactionsDetailLinkTransfer => 'This is my own transfer';

  @override
  String get transactionsDetailMoneyBackFor => 'This is money back for…';

  @override
  String transactionsDetailLinkedWith(String amount, String card) {
    return 'Linked with $amount on $card';
  }

  @override
  String get transactionsDetailInternalBanner =>
      'Transfer to yourself — not counted as spending or income';

  @override
  String get transactionsDetailDeclinedBanner => 'Declined — not counted';

  @override
  String transactionsDetailRefundCard(
    String date,
    String merchant,
    String net,
  ) {
    return 'Refund from $merchant for your $date purchase · net $net';
  }

  @override
  String get transactionsDetailRefundView => 'View original';

  @override
  String get transactionsDetailRefundNotRelated => 'Not related';

  @override
  String transactionsDetailReimbSuggest(String merchant) {
    return 'Is this from the $merchant bill?';
  }

  @override
  String transactionsDetailDuplicate(String date) {
    return 'Looks like a duplicate of a $date transaction for the same amount';
  }

  @override
  String get transactionsDetailDuplicateKeep => 'Keep both';

  @override
  String get transactionsDetailDuplicateDelete => 'Delete this one';

  @override
  String transactionsDetailReimbSummary(
    String back,
    String paid,
    String share,
  ) {
    return 'Paid $paid · back $back · your share $share';
  }

  @override
  String get transactionsDetailHowTitle => 'How Zaghlol read this';

  @override
  String get transactionsDetailHowRawA11y => 'Original message text';

  @override
  String transactionsDetailHowAmount(String amount) {
    return 'Amount $amount';
  }

  @override
  String transactionsDetailHowMerchant(String merchant) {
    return 'Merchant $merchant';
  }

  @override
  String transactionsDetailHowConfidence(String percent) {
    return 'Confidence $percent';
  }

  @override
  String transactionsDetailHowTemplate(String templateId) {
    return 'Template $templateId';
  }

  @override
  String get transactionsDetailHowNone => 'There\'s no message for this one.';

  @override
  String get transactionsDetailCategoryChanged => 'Category changed';

  @override
  String get transactionsDetailDeleteTitle => 'Delete this transaction?';

  @override
  String transactionsDetailDeleteBodyAuto(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'You won\'t be able to get it back.',
      'other':
          'It came from a message and won\'t come back unless you re-scan.',
    });
    return '$_temp0';
  }

  @override
  String get transactionsDetailDeleteBodyManual =>
      'You won\'t be able to get it back.';

  @override
  String get transactionsDetailDeleted => 'Deleted';

  @override
  String get transactionsDetailGone => 'This transaction no longer exists';

  @override
  String categorizationRuleTitle(String category, String merchant) {
    return 'Always use $category for $merchant?';
  }

  @override
  String get categorizationRuleAlways => 'Always';

  @override
  String get categorizationRuleOnce => 'Just this once';

  @override
  String categorizationRuleApplyPast(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Also update $n past transactions',
      one: 'Also update 1 past transaction',
    );
    return '$_temp0';
  }

  @override
  String get categorizationRuleSaved => 'Got it — I\'ll remember ✓';

  @override
  String transactionsEditTitleAdd(String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'income': 'Add income',
      'transfer': 'Add transfer',
      'other': 'Add expense',
    });
    return '$_temp0';
  }

  @override
  String get transactionsEditTitleEdit => 'Edit transaction';

  @override
  String get transactionsEditTypeA11y => 'Transaction type';

  @override
  String get transactionsEditAmountA11y => 'Amount';

  @override
  String get transactionsEditCurrency => 'Currency';

  @override
  String get transactionsEditCurrencySearch => 'Search currencies';

  @override
  String get transactionsEditCurrencyFeatured => 'Most used';

  @override
  String get transactionsEditCurrencyAll => 'All currencies';

  @override
  String get transactionsEditCategory => 'Category';

  @override
  String get transactionsEditChoose => 'Choose';

  @override
  String get transactionsEditMerchant => 'Merchant or person';

  @override
  String get transactionsEditAccount => 'Account';

  @override
  String get transactionsEditFrom => 'From';

  @override
  String get transactionsEditTo => 'To';

  @override
  String get transactionsEditWhichBalance => 'Which balance?';

  @override
  String get transactionsEditDate => 'When';

  @override
  String get transactionsEditNote => 'Note';

  @override
  String get transactionsEditSameAccount => 'Pick two different accounts';

  @override
  String get transactionsEditFromShared =>
      'Here\'s what I got from the message you shared. Check it and save.';

  @override
  String get transactionsEditRawTitle => 'Message text';

  @override
  String ingestionReviewFilterAll(String n) {
    return 'All $n';
  }

  @override
  String get ingestionReviewFilterCategory => 'Category';

  @override
  String get ingestionReviewFilterMessages => 'New messages';

  @override
  String get ingestionReviewFilterTransfers => 'Transfers';

  @override
  String ingestionReviewCatOut(String amount, String counterparty) {
    return '$amount to $counterparty';
  }

  @override
  String ingestionReviewCatIn(String amount, String counterparty) {
    return '$amount from $counterparty';
  }

  @override
  String ingestionReviewCatAt(String amount, String merchant) {
    return '$amount at $merchant';
  }

  @override
  String get ingestionReviewCatQuestion => 'What was this?';

  @override
  String ingestionReviewRememberCounterparty(String counterparty) {
    return 'Remember this for $counterparty';
  }

  @override
  String ingestionReviewRememberMerchant(String merchant) {
    return 'Always use this for $merchant';
  }

  @override
  String ingestionReviewCategorized(String category) {
    return 'Filed under $category';
  }

  @override
  String get ingestionReviewNewBank => 'New bank';

  @override
  String ingestionReviewGenFrom(String sender) {
    return 'From $sender';
  }

  @override
  String ingestionReviewGenGuessOut(String amount, String merchant) {
    return 'Our guess: $amount at $merchant';
  }

  @override
  String ingestionReviewGenGuessNoMerchant(String amount) {
    return 'Our guess: $amount';
  }

  @override
  String ingestionReviewGenGuessIn(String amount) {
    return 'Our guess: $amount in';
  }

  @override
  String get ingestionReviewGenLowConfidence =>
      'Not totally sure — check it before I log it';

  @override
  String get ingestionReviewRequestBank => 'Ask us to support this bank';

  @override
  String ingestionReviewUnreadTitle(String sender) {
    return 'A message from $sender I couldn\'t read';
  }

  @override
  String get ingestionReviewUnreadShow => 'Show message';

  @override
  String get ingestionReviewUnreadEnter => 'Enter details';

  @override
  String ingestionReviewXferTitle(String amount, String card) {
    return '$amount into $card — which transfer was it?';
  }

  @override
  String ingestionReviewXferOption(String amount, String card, String time) {
    return '$amount from $card · $time';
  }

  @override
  String get ingestionReviewXferNotMine => 'Not my transfer';

  @override
  String get ingestionReviewSwipeAcceptA11y => 'Accept suggestion';

  @override
  String get ingestionReviewSwipeDismissA11y => 'Dismiss';

  @override
  String get ingestionReviewDismissed => 'Removed from review';

  @override
  String get ingestionReviewEmptyTitle => 'All clear! Nothing to review ✨';

  @override
  String ingestionAlwaysSenderTitle(String sender) {
    return 'Always capture messages from $sender?';
  }

  @override
  String ingestionAlwaysSenderBody(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'They\'ll still come here for review until you\'ve confirmed $n, then I\'ll log them myself.',
      one: 'They\'ll still come here for review until you\'ve confirmed 1, then I\'ll log them myself.',
      zero: 'From now on I\'ll log its messages myself.',
    );
    return '$_temp0';
  }

  @override
  String get ingestionAlwaysSenderYes => 'Yes, always';

  @override
  String get ingestionRequestBankTitle => 'Request your bank';

  @override
  String get ingestionRequestBankName => 'Bank name';

  @override
  String get ingestionRequestBankCountry => 'Country';

  @override
  String get ingestionRequestBankChannel => 'How do its alerts arrive?';

  @override
  String get ingestionRequestBankPrivacy =>
      'We send only the bank\'s name, country and alert type — never the message itself.';

  @override
  String get ingestionRequestBankSent => 'Request sent ✓ Thanks!';

  @override
  String get ingestionRequestBankFailed =>
      'Couldn\'t send it right now. I\'ve kept it so you can send it later.';

  @override
  String ingestionRequestBankNameLength(String max, String min) {
    return 'Bank name must be $min–$max characters';
  }

  @override
  String get ingestionRequestBankCountryRequired => 'Choose a country';

  @override
  String get transfersSplitTitle => 'Split the bill';

  @override
  String transfersSplitHeader(String amount, String merchant) {
    return '$merchant · $amount';
  }

  @override
  String get transfersSplitPeople => 'People';

  @override
  String get transfersSplitAddPerson => 'Add person';

  @override
  String get transfersSplitPersonHint => 'Name';

  @override
  String transfersSplitShareA11y(String name) {
    return '$name\'s share';
  }

  @override
  String transfersSplitRemovePerson(String name) {
    return 'Remove $name';
  }

  @override
  String get transfersSplitEqual => 'Split evenly';

  @override
  String get transfersSplitPaidBack => 'Paid back';

  @override
  String get transfersSplitWaiting => 'Waiting';

  @override
  String transfersSplitPaidDetail(String amount, String date, String source) {
    return '$amount · $source · $date';
  }

  @override
  String get transfersSplitYourShare => 'Your share';

  @override
  String get transfersSplitSuggestions => 'Suggestions';

  @override
  String transfersSplitSuggestion(String amount, String date, String person) {
    return '$amount from $person · $date — from this bill?';
  }

  @override
  String get transfersSplitUnassign => 'Remove from this bill';

  @override
  String get transfersSplitUnassigned => 'Removed — it counts as income again';

  @override
  String get transfersSplitSaved => 'Split saved ✓';

  @override
  String transfersAssignHeader(String amount, String person) {
    return '$amount from $person';
  }

  @override
  String get transfersAssignTitle => 'Assign to expenses';

  @override
  String get transfersAssignSearch => 'Search recent expenses';

  @override
  String transfersAssignUnassigned(String amount) {
    return 'Not assigned: $amount — stays as income';
  }

  @override
  String transfersAssignEmpty(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No expenses in the last $n days',
      one: 'No expenses since yesterday',
    );
    return '$_temp0';
  }

  @override
  String get transfersAssignSearchAll => 'Search all expenses';

  @override
  String get transfersAssignSaved => 'Assigned ✓';

  @override
  String get transfersSplitErrorShareZero =>
      'Each share must be more than zero';

  @override
  String get transfersSplitErrorSharesExceed =>
      'Shares add up to more than the expense';

  @override
  String get transfersAssignErrorExceedsIncoming =>
      'You\'ve assigned more than you received';

  @override
  String get transfersAssignErrorExceedsExpense =>
      'Money back can\'t be more than the expense';

  @override
  String get transfersSplitErrorCurrency =>
      'Different currency — can\'t link these';

  @override
  String get transfersLinkTitle => 'Link my own transfer';

  @override
  String transfersLinkSource(String amount, String card, String date) {
    return '$amount · $card · $date';
  }

  @override
  String get transfersLinkPick => 'Pick the matching transaction';

  @override
  String transfersLinkAfterMinutes(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n min later',
      one: '1 min later',
      zero: 'Same minute',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkBeforeMinutes(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n min earlier',
      one: '1 min earlier',
      zero: 'Same minute',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkAfterHours(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n hr later',
      one: '1 hr later',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkBeforeHours(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n hr earlier',
      one: '1 hr earlier',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkAfterDays(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n days later',
      one: '1 day later',
      zero: 'Same day',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkBeforeDays(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n days earlier',
      one: '1 day earlier',
      zero: 'Same day',
    );
    return '$_temp0';
  }

  @override
  String transfersLinkImpliedRate(String fromCurrency, String rate) {
    return 'Implied rate ≈ $rate per $fromCurrency';
  }

  @override
  String get transfersLinkLinked => 'Linked ✓ Not counted as spending';

  @override
  String get transfersLinkEmptyTitle => 'No matching transaction found';

  @override
  String get transfersLinkEmptyBody =>
      'The other bank may not send messages. You can still mark this as your own transfer so it isn\'t counted as spending.';

  @override
  String get transfersLinkMarkAnyway => 'Mark as my transfer';

  @override
  String get transfersLinkErrorAmounts => 'Amounts must match';

  @override
  String get transfersLinkErrorAccount => 'Pick a different account';

  @override
  String get transfersLinkErrorDirection =>
      'One must be money out, the other money in';

  @override
  String get accountsOverviewTitle => 'Money';

  @override
  String get accountsOverviewAdd => 'Add';

  @override
  String get accountsOverviewAddAccount => 'Card or account';

  @override
  String get accountsOverviewAddAsset => 'Asset (gold, certificate…)';

  @override
  String get accountsOverviewNetWorth => 'Net worth';

  @override
  String get accountsOverviewOtherCurrenciesA11y => 'Other currencies';

  @override
  String get accountsOverviewAccountsTitle => 'Cards & accounts';

  @override
  String get accountsOverviewCompare => 'Compare';

  @override
  String accountsOverviewAsOf(String when) {
    return 'as of $when';
  }

  @override
  String accountsOverviewCreditAvailable(String limit) {
    return 'available of $limit';
  }

  @override
  String accountsOverviewMoreCurrencies(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$n more currencies',
      one: '+1 more currency',
    );
    return '$_temp0';
  }

  @override
  String get accountsOverviewCashSub => 'Manual & voice';

  @override
  String get accountsOverviewNotTracked => 'Not tracked';

  @override
  String get accountsOverviewHiddenEntry => 'Hidden accounts';

  @override
  String get accountsOverviewAssetsTitle => 'Your assets';

  @override
  String get accountsOverviewPrices => 'Prices';

  @override
  String get accountsOverviewAssetsLocked =>
      'Track your gold, certificates and more in one place';

  @override
  String get accountsOverviewZakah => 'Zakah';

  @override
  String get accountsOverviewEmptyTitle =>
      'Accounts appear from your bank messages';

  @override
  String get accountsOverviewEmptyAdd => 'Add one yourself';

  @override
  String get accountsAddTypeTitle => 'What are you adding?';

  @override
  String get accountsAddTypeInfo =>
      'Cards are added automatically when a message arrives. Add one yourself if none has come yet.';

  @override
  String get accountsAddTypeCredit => 'Credit card';

  @override
  String get accountsAddTypeCreditSub => 'Limit and due date';

  @override
  String get accountsAddTypeDebit => 'Debit card / bank account';

  @override
  String get accountsAddTypeDebitSub => 'Salary and spending';

  @override
  String get accountsAddTypeWallet => 'Wallet';

  @override
  String get accountsAddTypeWalletSub => 'Vodafone Cash, Orange Cash, e& cash';

  @override
  String get accountsAddTypeMulti => 'Multi-currency account';

  @override
  String get accountsAddTypeMultiSub => 'Wise, Revolut, Payoneer';

  @override
  String get accountsAddTypeBnpl => 'Buy now, pay later';

  @override
  String get accountsAddTypeBnplSub => 'valU, Sympl, Contact';

  @override
  String get accountsAddBankTitle => 'Which bank?';

  @override
  String get accountsAddBankSearch => 'Search banks…';

  @override
  String get accountsAddBankEgypt => 'Banks in Egypt';

  @override
  String get accountsAddBankAbroad => 'Foreign & online banks';

  @override
  String get accountsAddBankNotListed => 'My bank isn\'t listed';

  @override
  String get accountsAddBankNotListedSub =>
      'Add it by name — Zaghlol will try to read its messages';

  @override
  String get accountsAddBankNoResults => 'No bank by that name';

  @override
  String get accountsAddBankRequired => 'Choose a bank';

  @override
  String get accountsAddedTitle => 'Card added! ✨';

  @override
  String accountsAddedDueDay(String day) {
    return 'Due on day $day each month';
  }

  @override
  String get accountsAddedWaitingBalance =>
      'Updates with the first message that shows your available balance';

  @override
  String accountsAddedEmptyBody(String bank, String last4) {
    return 'As soon as $bank messages you about $last4, it\'ll show up here.';
  }

  @override
  String get accountsAddedImport => 'Import this card\'s statement';

  @override
  String get accountsAddedImportSub => 'A PDF from your bank\'s app';

  @override
  String get accountsAddedManual => 'Add a transaction';

  @override
  String get accountsAddedManualSub => 'On this card';

  @override
  String get accountsDetailAvailable => 'Available';

  @override
  String accountsDetailAvailableOf(String available, String limit) {
    return '$available of $limit';
  }

  @override
  String accountsDetailLimitUsed(String percent) {
    return '$percent of your limit used';
  }

  @override
  String get accountsDetailBalance => 'Balance';

  @override
  String accountsDetailAsOf(String when) {
    return 'As of $when';
  }

  @override
  String get accountsDetailBalanceUnknown =>
      'Shows up with the first message that has a balance';

  @override
  String accountsDetailDue(String date) {
    return 'Statement due $date';
  }

  @override
  String get accountsDetailSpent => 'Spent';

  @override
  String get accountsDetailDonutA11y => 'Spending by category';

  @override
  String get accountsDetailTopMerchants => 'Top merchants';

  @override
  String get accountsDetailTrend => 'Monthly trend';

  @override
  String get accountsDetailIncomeRefunds => 'Income & refunds';

  @override
  String get accountsDetailRecent => 'Recent';

  @override
  String get accountsDetailAllTransactions => 'All card transactions';

  @override
  String get accountsDetailCapture => 'What Zaghlol reads';

  @override
  String get accountsDetailMenuCapture => 'Capture controls';

  @override
  String get accountsDetailMenuMerge => 'Merge with another card';

  @override
  String get accountsDetailMenuHide => 'Hide account';

  @override
  String get accountsDetailEmpty => 'No spending on this card in this period';

  @override
  String accountsDetailIgnoredBanner(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'Not tracked: messages and Apple Pay are off for this card',
      'other': 'Not tracked: messages and notifications are off for this card',
    });
    return '$_temp0';
  }

  @override
  String get accountsDetailTrackAgain => 'Track again';

  @override
  String get accountsCompareTitle => 'Compare cards';

  @override
  String get accountsCompareTotal => 'Total';

  @override
  String get accountsCompareChoose => 'Choose cards';

  @override
  String accountsCompareMax(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pick up to $n cards',
      one: 'Pick 1 card',
    );
    return '$_temp0';
  }

  @override
  String get accountsCompareOtherCurrency =>
      'Cards in other currencies appear when you pick that currency';

  @override
  String get accountsCompareEmpty =>
      'Compare needs at least two cards with spending';

  @override
  String accountsCompareCellA11y(String amount, String card, String category) {
    return '$category, $card: $amount';
  }

  @override
  String get accountsEditTitleEdit => 'Card details';

  @override
  String get accountsEditTitleNew => 'New card';

  @override
  String get accountsEditName => 'Card name';

  @override
  String get accountsEditBank => 'Bank';

  @override
  String get accountsEditBankAuto => 'Detected from messages';

  @override
  String get accountsEditLast4 => 'Last four digits';

  @override
  String accountsEditLast4Hint(String sample) {
    return 'In messages it looks like \"$sample\" — that\'s how Zaghlol spots the card.';
  }

  @override
  String get accountsEditType => 'Type';

  @override
  String get accountsEditCurrency => 'Currency';

  @override
  String get accountsEditBalances => 'Balances';

  @override
  String get accountsEditAddCurrency => 'Add currency';

  @override
  String get accountsEditLimit => 'Credit limit';

  @override
  String get accountsEditDueDay => 'Statement due day';

  @override
  String accountsEditDueReminder(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'I\'ll remind you $n days before it\'s due.',
      one: 'I\'ll remind you 1 day before it\'s due.',
      zero: 'I\'ll remind you on the due day.',
    );
    return '$_temp0';
  }

  @override
  String get accountsEditCaptureTitle =>
      'What should Zaghlol read for this card?';

  @override
  String get accountsEditCaptureLink => 'What Zaghlol reads';

  @override
  String get accountsEditMerge => 'Merge with another card';

  @override
  String get accountsEditHide => 'Hide this account';

  @override
  String get accountsEditHideHint =>
      'It won\'t appear in lists, but its transactions still count in totals, budgets and charts.';

  @override
  String get accountsEditHidden =>
      'Account hidden. Its transactions still count.';

  @override
  String get accountsEditDuplicate => 'This card already exists — open it?';

  @override
  String get accountsEditOpenExisting => 'Open it';

  @override
  String get accountsEditErrorLimit => 'The limit can\'t be negative';

  @override
  String accountsEditErrorDueDay(String max, String min) {
    return 'Pick a day from $min to $max';
  }

  @override
  String get accountsEditSaved => 'Saved ✓';

  @override
  String get accountsMergePickTitle => 'Merge into which card?';

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
      other: 'Move $n transactions from $fromCard into $toCard?',
      one: 'Move 1 transaction from $fromCard into $toCard?',
      zero: 'Merge $fromCard into $toCard?',
    );
    return '$_temp0';
  }

  @override
  String get accountsMergeConfirmBody => 'The two cards will become one.';

  @override
  String get accountsMergeCopyCapture => 'Also copy capture settings';

  @override
  String get accountsMergeConfirm => 'Merge';

  @override
  String get accountsMergeDifferentBank =>
      'These cards are from different banks. Sure they\'re the same card?';

  @override
  String get accountsMergeDifferentBankConfirm => 'Yes, merge';

  @override
  String get accountsMergeErrorSelf => 'A card can\'t be merged into itself';

  @override
  String get accountsMergeDone => 'Merged ✓';

  @override
  String get captureSettingsTitle => 'Capture';

  @override
  String get captureSettingsSources => 'Sources';

  @override
  String get captureSettingsOn => 'On';

  @override
  String get captureSettingsOff => 'Off';

  @override
  String get captureSettingsActive => 'Active';

  @override
  String get captureSettingsUnknown => 'Not sure yet';

  @override
  String get captureSettingsSmsIos => 'Via Shortcuts';

  @override
  String get captureSettingsCheckSetup => 'Check setup';

  @override
  String get captureSettingsShare => 'Share or paste a message';

  @override
  String get captureSettingsNotTracked => 'Not tracked';

  @override
  String get captureSettingsNotTrackedEmpty => 'All your cards are tracked';

  @override
  String captureSettingsIgnoredChannels(String channels) {
    return '$channels off';
  }

  @override
  String get captureSettingsAddIgnore => 'Don\'t track a card or bank';

  @override
  String get captureSettingsTools => 'Tools';

  @override
  String get captureSettingsRescan => 'Re-scan SMS inbox';

  @override
  String get captureSettingsBanks => 'Supported banks';

  @override
  String get captureSettingsRequestBank => 'Request my bank';

  @override
  String get captureSettingsTemplates => 'Custom message templates';

  @override
  String get captureSettingsUnreadable =>
      'Some messages couldn\'t be read. Re-scan so nothing\'s missed.';

  @override
  String get captureIgnoreTitle => 'Don\'t track a card or bank';

  @override
  String get captureIgnoreBank => 'Bank';

  @override
  String get captureIgnoreLast4 => 'Last four digits (optional)';

  @override
  String get captureIgnoreLast4Hint =>
      'Leave it empty to stop tracking the whole bank';

  @override
  String get captureIgnoreChannels => 'Stop reading:';

  @override
  String get captureIgnorePrivacy =>
      'Messages for anything you switch off are ignored and never saved.';

  @override
  String get captureIgnoreErrorBank => 'Choose the bank';

  @override
  String get captureIgnoreErrorChannel => 'Pick at least one source';

  @override
  String get captureIgnoreErrorLast4 => 'Leave it empty or enter four digits';

  @override
  String get captureIgnoreSaved => 'Done — no longer tracking it';

  @override
  String get captureRescanTitle => 'Re-scan old messages';

  @override
  String get captureRescanDepth => 'How far back?';

  @override
  String get captureRescanStart => 'Start';

  @override
  String captureRescanRunning(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Searching… $n new found',
      one: 'Searching… 1 new found',
      zero: 'Searching…',
    );
    return '$_temp0';
  }

  @override
  String captureRescanDone(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $n new transactions ✓',
      one: 'Added 1 new transaction ✓',
      zero: 'No new transactions ✓',
    );
    return '$_temp0';
  }

  @override
  String get captureRescanNoDuplicates =>
      'Nothing already saved will be added twice';

  @override
  String captureRescanOfferTitle(String card) {
    return 'Look through old messages for $card?';
  }

  @override
  String get captureRescanOfferBody =>
      'Messages were not saved while it was off, but they may still be in your inbox.';

  @override
  String get captureRescanOfferYes => 'Search';

  @override
  String get captureBanksTitle => 'Supported banks';

  @override
  String get captureBanksSearch => 'Search banks…';

  @override
  String get captureBanksNoResults => 'No bank by that name';

  @override
  String captureBanksChannels(String channels) {
    return 'Tracked via: $channels';
  }

  @override
  String captureBanksIosNote(String bank) {
    return 'On iPhone, $bank is tracked through Apple Pay and screenshots, and statements with Gold. iOS doesn\'t let Zaghlol read other apps\' notifications.';
  }

  @override
  String get captureShareHowTitle => 'How to share a message';

  @override
  String get captureShareHowStep1 =>
      'Open the bank message in your messages app';

  @override
  String get captureShareHowStep2 => 'Long-press it and choose Share or Copy';

  @override
  String get captureShareHowStep3 =>
      'Pick Zaghlol — or open Zaghlol and paste it';

  @override
  String get captureShareHowNote => 'You\'ll check it before it\'s saved.';

  @override
  String captureCardControlsTitle(String card) {
    return 'What should Zaghlol read from $card?';
  }

  @override
  String get captureCardControlsSubtitle => 'Your choice — change it any time';

  @override
  String get captureCardControlsSmsIos => 'Through iPhone Shortcuts';

  @override
  String get captureCardControlsApplePaySub => 'Phone payments';

  @override
  String get captureCardControlsInfo =>
      'When a switch is off, messages for this card are ignored and never saved.';

  @override
  String captureStopTrackingTitle(String card) {
    return 'Stop tracking $card?';
  }

  @override
  String get captureStopTrackingExisting => 'Transactions already saved:';

  @override
  String get captureStopTrackingKeep => 'Keep them';

  @override
  String captureStopTrackingDelete(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $n transactions',
      one: 'Delete 1 transaction',
    );
    return '$_temp0';
  }

  @override
  String get captureStopTrackingConfirm => 'Stop tracking';

  @override
  String captureStopTrackingDeleteTitle(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $n transactions for good?',
      one: 'Delete 1 transaction for good?',
    );
    return '$_temp0';
  }

  @override
  String get captureStopTrackingDeleteBody =>
      'This can\'t be undone. These transactions will be deleted from this phone and every total will update.';

  @override
  String get captureStopTrackingDeleteConfirm => 'Delete for good';

  @override
  String captureStopTrackingDone(String card) {
    return 'No longer tracking $card';
  }
}
