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
  String get backupRestoreReplaceConfirm =>
      'This replaces everything on this phone with the backup. Continue?';

  @override
  String get backupRestoreReplaceAction => 'Replace';

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

  @override
  String get commonActionTypeInstead => 'Type it instead';

  @override
  String commonUnitGrams(String n) {
    return '$n g';
  }

  @override
  String commonUnitPerMonth(String amount) {
    return '$amount/mo';
  }

  @override
  String commonUnitPerYear(String amount) {
    return '$amount/yr';
  }

  @override
  String commonUnitPerDay(String amount) {
    return '$amount/day';
  }

  @override
  String commonUnitVisits(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n visits',
      one: '1 visit',
    );
    return '$_temp0';
  }

  @override
  String commonUnitOrders(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n orders',
      one: '1 order',
    );
    return '$_temp0';
  }

  @override
  String get commonCadenceWeekly => 'Weekly';

  @override
  String get commonCadenceMonthly => 'Monthly';

  @override
  String get commonCadenceQuarterly => 'Every 3 months';

  @override
  String get commonCadenceSemiannual => 'Every 6 months';

  @override
  String get commonCadenceYearly => 'Yearly';

  @override
  String get commonAssetTypeGold => 'Gold';

  @override
  String get commonAssetTypeCertificate => 'Bank certificate';

  @override
  String get commonAssetTypeForeignCash => 'Foreign cash';

  @override
  String get commonAssetTypeStocks => 'Stocks & funds';

  @override
  String get commonAssetTypeProperty => 'Property';

  @override
  String get commonAssetTypeCar => 'Car';

  @override
  String commonKaratLabel(String karat) {
    return '${karat}K';
  }

  @override
  String get commonKaratCoin => 'Gold coin';

  @override
  String get mascotTapLine9 => 'Wondering where it all went? Try Insights';

  @override
  String get mascotTapLine10 => 'I count, the gold shines, you save';

  @override
  String get insightsTabsCharts => 'Charts';

  @override
  String get insightsTabsBudget => 'Budget';

  @override
  String get insightsTabsBills => 'Bills';

  @override
  String get insightsPeriodTitle => 'Period';

  @override
  String get insightsPeriodStart => 'From';

  @override
  String get insightsPeriodEnd => 'To';

  @override
  String insightsChartsContext(String cards, String currency, String period) {
    return '$cards · $currency · $period';
  }

  @override
  String get insightsChartsExplain => 'Explain this';

  @override
  String get insightsChartsLockedSub => 'See the full chart with Gold';

  @override
  String get insightsChartsEmptyCycle =>
      'Comes alive after your first full cycle';

  @override
  String get insightsChartsEmptyNetWorth =>
      'Add accounts or assets to bring this chart to life';

  @override
  String get insightsChartsEmptyNetWorthAction => 'Open Money';

  @override
  String get insightsChartsEmptyFilter =>
      'No data for this filter in this period';

  @override
  String get insightsChartsCardError =>
      'This chart didn\'t load. The others are fine.';

  @override
  String get insightsChartsLoadingA11y => 'Loading charts';

  @override
  String get insightsChartsOtherSlice => 'Other';

  @override
  String get insightsChartTitleCashFlow => 'Cash flow';

  @override
  String get insightsChartTitleCategories => 'Where your money went';

  @override
  String get insightsChartTitleBurnRate => 'Burn rate to payday';

  @override
  String get insightsChartTitleRule503020 => '50/30/20 balance';

  @override
  String get insightsChartTitleWeekPattern => 'When you spend';

  @override
  String get insightsChartTitleMerchants => 'Top merchants';

  @override
  String get insightsChartTitleVsAverage =>
      'This cycle vs your 3-cycle average';

  @override
  String get insightsChartTitleInstallments => 'Installments, next 6 months';

  @override
  String get insightsChartTitleSubscriptions => 'Subscriptions over a year';

  @override
  String get insightsChartTitleCards => 'Cards & wallets';

  @override
  String get insightsChartTitleNetWorth => 'Net worth growth';

  @override
  String get insightsChartTitleInflation => 'Your personal inflation';

  @override
  String get insightsLegendIncome => 'Income';

  @override
  String get insightsLegendSpent => 'Spent';

  @override
  String get insightsLegendSaved => 'Saved';

  @override
  String get insightsLegendActual => 'Actual';

  @override
  String get insightsLegendIdeal => 'Ideal pace';

  @override
  String get insightsLegendToday => 'Today';

  @override
  String get insightsLegendPayday => 'Payday';

  @override
  String get insightsLegendNeeds => 'Needs';

  @override
  String get insightsLegendWants => 'Wants';

  @override
  String get insightsLegendSavings => 'Savings';

  @override
  String get insightsLegendTarget => 'Target';

  @override
  String get insightsLegendAverage => 'Your average';

  @override
  String get insightsLegendThisCycle => 'This cycle';

  @override
  String get insightsLegendInstallments => 'Installments';

  @override
  String get insightsLegendCardDues => 'Cards & gameya';

  @override
  String get insightsLegendMonthly => 'Per month';

  @override
  String get insightsLegendYearly => 'Per year';

  @override
  String get insightsLegendSupermarket => 'Avg supermarket basket';

  @override
  String get insightsLegendDelivery => 'Avg delivery order';

  @override
  String insightsChartA11yCashFlow(String income, String spent, String saved) {
    return 'Cash flow: income $income, spent $spent, saved $saved';
  }

  @override
  String insightsChartA11yCategories(
    String category,
    String amount,
    String percent,
  ) {
    return 'Where your money went: $category is the largest at $amount, $percent';
  }

  @override
  String insightsChartA11yBurnRate(
    String spent,
    String budget,
    String cycleDay,
  ) {
    return 'Burn rate: spent $spent of $budget on day $cycleDay';
  }

  @override
  String insightsChartA11yRule503020(
    String needsPct,
    String wantsPct,
    String savingsPct,
  ) {
    return '50/30/20: $needsPct needs, $wantsPct wants, $savingsPct savings';
  }

  @override
  String insightsChartA11yWeekPattern(String peakDay, String amount) {
    return 'When you spend: busiest day is $peakDay, averaging $amount';
  }

  @override
  String insightsChartA11yMerchants(String merchant, String amount) {
    return 'Top merchants: $merchant first with $amount';
  }

  @override
  String insightsChartA11yVsAverage(String category, String percent) {
    return 'This cycle vs average: biggest rise is $category at $percent';
  }

  @override
  String insightsChartA11yInstallments(String sum) {
    return 'Installments: $sum due this month';
  }

  @override
  String insightsChartA11ySubscriptions(String monthly, String yearly) {
    return 'Subscriptions: $monthly a month, $yearly a year';
  }

  @override
  String insightsChartA11yCards(String card, String percent) {
    return 'Cards: $card is the largest at $percent of spending';
  }

  @override
  String insightsChartA11yNetWorth(String startAmount, String endAmount) {
    return 'Net worth: from $startAmount to $endAmount';
  }

  @override
  String insightsChartA11yInflation(String startAmount, String endAmount) {
    return 'Inflation: supermarket basket from $startAmount to $endAmount';
  }

  @override
  String insightsChartDetailLegendRowA11y(
    String category,
    String amount,
    String percent,
  ) {
    return '$category: $amount, $percent. Tap to see the transactions';
  }

  @override
  String insightsChartDetailCardRowA11y(String card, String amount) {
    return '$card: $amount. Tap to open the card';
  }

  @override
  String get insightsChartDetailTypingA11y => 'Zaghlol is typing';

  @override
  String get insightsChartDetailTipLabel => 'Tip';

  @override
  String get insightsChartDetailDeepLabel => 'Deeper look';

  @override
  String get insightsChartDetailDeepUpsell =>
      'Want a deeper look? Gold compares with last cycle and projects your cycle\'s end.';

  @override
  String insightsChartDetailNeedsData(String need) {
    String _temp0 = intl.Intl.selectLogic(need, {
      'cycle': 'I need one full cycle before I can explain this chart',
      'months': 'I need three cycles to compare you with yourself',
      'accounts': 'Add accounts or assets and I\'ll explain',
      'installments': 'Add an installment or commitment and I\'ll explain',
      'subscriptions': 'No subscriptions yet. I\'ll explain once I spot one',
      'other': 'I need more data to explain this chart',
    });
    return '$_temp0';
  }

  @override
  String get insightsChartDetailExplainFailed =>
      'Couldn\'t explain this chart right now';

  @override
  String get insightsChartDetailLockedTitle => 'This chart is part of Gold';

  @override
  String get insightsChartDetailLockedBody =>
      'Take a look, then unlock it with Gold';

  @override
  String insightsDeepProjection(String state, String projected) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'over':
          'At this pace you\'ll finish the cycle at $projected, over your budget',
      'other':
          'At this pace you\'ll finish the cycle at $projected, within your budget',
    });
    return '$_temp0';
  }

  @override
  String insightsDeepDrivers(
    String merchant,
    String merchant2,
    String merchant3,
  ) {
    return 'The merchants behind the change: $merchant, $merchant2 and $merchant3';
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
          'This cycle you earned $income and spent $spent, so you\'re $gap over your income. Let\'s sort it out together.',
      'other':
          'This cycle you earned $income and spent $spent, so you saved $saved. That\'s $percent of your income. Well done!',
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
      'short':
          'Trim $category by $target next cycle and you\'ll finish in the black.',
      'other':
          'Move at least $target of this surplus into savings before it gets spent.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCashFlowDeep(String trend, String delta) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'This cycle\'s net is $delta better than last cycle.',
      'down': 'This cycle\'s net is $delta lower than last cycle.',
      'other': 'This cycle\'s net is about the same as last cycle.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCashFlowDeepTip(String target, String yearly) {
    return 'Set a goal of saving $target every cycle. That\'s $yearly a year.';
  }

  @override
  String insightsExplainCategoriesBasic(
    String category,
    String percent,
    String amount,
    String category2,
    String percent2,
  ) {
    return '$category takes $percent of your spending, that\'s $amount. $category2 is next at $percent2.';
  }

  @override
  String insightsExplainCategoriesTip(String category, String target) {
    return 'Cap $category $target below this cycle and keep the difference.';
  }

  @override
  String insightsExplainCategoriesDeep(
    String trend,
    String category,
    String delta,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': '$category is up $delta on last cycle.',
      'down': '$category is down $delta on last cycle.',
      'other': '$category is about the same as last cycle.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCategoriesDeepTip(
    String category,
    String target,
    String yearly,
  ) {
    return 'Bring $category down by $target each cycle. That\'s $yearly a year.';
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
          'You\'re on day $cycleDay of the cycle and have spent $spent of $budget, above the ideal pace. What\'s left covers $perDay a day.',
      'other':
          'You\'re on day $cycleDay of the cycle and have spent $spent of $budget, under the ideal pace. You can spend $perDay a day.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainBurnRateTip(String state, String perDay) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'over':
          'Bring your daily spending down to $perDay until payday so the budget lasts.',
      'other':
          'Keep this pace and the gap becomes surplus at the end of the cycle. You can spend $perDay a day.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainBurnRateDeep(String trend, String delta) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'At this point last cycle you had spent $delta less.',
      'down': 'At this point last cycle you had spent $delta more.',
      'other': 'Your spending is about the same as this point last cycle.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainBurnRateDeepTip(String target) {
    return 'Cut $target from your daily spending and you\'ll stay under the line until payday.';
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
          'This cycle: $needsPct needs, $wantsPct wants, $savingsPct savings. Wants are above the usual rule.',
      'savingsLow':
          'This cycle: $needsPct needs, $wantsPct wants, $savingsPct savings. Savings are below the usual rule.',
      'other':
          'This cycle: $needsPct needs, $wantsPct wants, $savingsPct savings. That\'s close to the usual rule.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainRule503020Tip(String state, String target) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'wantsHigh': 'Trim wants by $target next cycle and move it to savings.',
      'savingsLow': 'Try to add $target to your savings next cycle.',
      'other': 'Keep this up, and add $target more if you can.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainRule503020Deep(String trend, String savingsPct) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'Savings rose from last cycle to $savingsPct.',
      'down': 'Savings fell from last cycle to $savingsPct.',
      'other': 'Savings are about the same as last cycle.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainRule503020DeepTip(String percent, String yearly) {
    return 'If savings reach $percent, you\'ll save $yearly a year.';
  }

  @override
  String insightsExplainWeekPatternBasic(
    String peakDay,
    String peakDay2,
    String percent,
    String time,
  ) {
    return '$peakDay and $peakDay2 take $percent of your weekly spending, and your busiest hour is around $time.';
  }

  @override
  String insightsExplainWeekPatternTip(String target, String peakDay) {
    return 'Set a $target limit for next $peakDay.';
  }

  @override
  String insightsExplainWeekPatternDeep(
    String trend,
    String peakDay,
    String amount,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'Your average on $peakDay is $amount, higher than last cycle.',
      'down': 'Your average on $peakDay is $amount, lower than last cycle.',
      'other':
          'Your average on $peakDay is $amount, about the same as last cycle.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainWeekPatternDeepTip(
    String peakDay,
    String target,
    String yearly,
  ) {
    return 'Spend $target less each $peakDay and you\'ll save $yearly a year.';
  }

  @override
  String insightsExplainMerchantsBasic(
    String merchant,
    String amount,
    String visits,
    String merchant2,
    String amount2,
  ) {
    return '$merchant is first with $amount ($visits), then $merchant2 with $amount2.';
  }

  @override
  String insightsExplainMerchantsTip(String merchant) {
    return 'Group your $merchant shopping into one visit a week.';
  }

  @override
  String insightsExplainMerchantsDeep(
    String percent,
    String trend,
    String merchant,
    String delta,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': '$merchant is up $delta on last cycle.',
      'down': '$merchant is down $delta on last cycle.',
      'other': '$merchant is about the same as last cycle.',
    });
    return 'Your top three merchants take $percent of your spending. $_temp0';
  }

  @override
  String insightsExplainMerchantsDeepTip(
    String merchant,
    String target,
    String yearly,
  ) {
    return 'Cut $merchant by a quarter and you\'ll save $target a cycle, $yearly a year.';
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
          '$category is up $percent on your 3-cycle average, but $category2 is down $percent2. Nice work on that.',
      'rise': '$category is up $percent on your 3-cycle average.',
      'drop':
          '$category2 is down $percent2 on your 3-cycle average. Nice work.',
      'other': 'This cycle is close to your 3-cycle average.',
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
      'both': 'Bring $category back to your average and you\'ll save $target.',
      'rise': 'Bring $category back to your average and you\'ll save $target.',
      'drop': 'Keep doing what you\'re doing with $category2.',
      'other': 'Keep this pace.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainVsAverageDeep(String trend, String delta) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'Overall you\'re $delta above your average.',
      'down': 'Overall you\'re $delta below your average.',
      'other': 'Overall you\'re right on your average.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainVsAverageDeepTip(String category, String target) {
    return 'Set $category\'s limit at your average, that\'s $target a cycle.';
  }

  @override
  String insightsExplainInstallmentsBasic(
    String sum,
    String item,
    String month,
  ) {
    return 'You owe $sum in installments and commitments this month. $item ends in $month.';
  }

  @override
  String insightsExplainInstallmentsTip(String item) {
    return 'Hold off on a new installment until $item is done.';
  }

  @override
  String insightsExplainInstallmentsDeep(String amount, String average) {
    return 'Over the next six months you\'ll pay $amount in total, averaging $average a month.';
  }

  @override
  String insightsExplainInstallmentsDeepTip(String item, String monthly) {
    return 'When $item ends, $monthly a month frees up.';
  }

  @override
  String insightsExplainSubscriptionsBasic(String monthly, String yearly) {
    return 'Subscriptions cost $monthly a month, $yearly a year. Small ones look like loose change until they add up.';
  }

  @override
  String insightsExplainSubscriptionsTip(String item, String target) {
    return 'Check $item. If you don\'t use it, cancelling saves $target a year.';
  }

  @override
  String insightsExplainSubscriptionsDeep(String trend, String delta) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'Subscriptions are up $delta a month on three months ago.',
      'down': 'Subscriptions are down $delta a month on three months ago.',
      'other': 'Subscriptions are unchanged from three months ago.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainSubscriptionsDeepTip(String target) {
    return 'Cancel the two priciest ones you don\'t use and you\'ll save $target a year.';
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
          '$percent of your spending came from $card, then $card2 at $percent2. You\'ve used $utilisation of your credit limit.',
      'other':
          '$percent of your spending came from $card, then $card2 at $percent2.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCardsTip(String state) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'credit': 'Keep credit use under half the limit and pay it before the due date.',
      'other': 'Keep daily spending on one card so it\'s easier to follow.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCardsDeep(String trend, String card) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': '$card\'s share of your spending rose since last cycle.',
      'down': '$card\'s share of your spending fell since last cycle.',
      'other': '$card\'s share of your spending is unchanged since last cycle.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainCardsDeepTip(
    String amount,
    String card,
    String target,
  ) {
    return 'You spent $amount on $card this cycle. Set a $target limit for the next one.';
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
          'Your net worth grew from $startAmount in $month to $endAmount in $month2.',
      'down':
          'Your net worth dropped from $startAmount in $month to $endAmount in $month2.',
      'other': 'Your net worth is steady at about $endAmount.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainNetWorthTip(String assetType, String percent) {
    return '$assetType is your biggest slice at $percent. Keep an eye on it if it\'s all in one place.';
  }

  @override
  String insightsExplainNetWorthDeep(
    String trend,
    String percent,
    String assetType2,
  ) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'up': 'You\'re up $percent overall, mostly thanks to $assetType2.',
      'down': 'You\'re down $percent overall, mostly because of $assetType2.',
      'other': 'No big change over this period.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainNetWorthDeepTip(String projected) {
    return 'At this rate you could reach $projected in a year. That\'s an estimate only.';
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
          'Your average supermarket basket was $startAmount in $month and is $endAmount now, up $percent.',
      'down':
          'Your average supermarket basket was $startAmount in $month and is $endAmount now, down $percent.',
      'other': 'Your average supermarket basket is steady at about $endAmount.',
    });
    return '$_temp0';
  }

  @override
  String insightsExplainInflationTip(String category) {
    return 'Try cheaper alternatives for $category, where your prices rose the most.';
  }

  @override
  String insightsExplainInflationDeep(String average, String previous) {
    return 'Your average delivery order is now $average, up from $previous.';
  }

  @override
  String insightsExplainInflationDeepTip(String target, String yearly) {
    return 'Bring your average basket down $target and you\'ll save $yearly a year at the same number of visits.';
  }

  @override
  String budgetOverviewCycle(String start, String end) {
    return '$start to $end';
  }

  @override
  String budgetOverviewDaysLeft(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n days left',
      one: 'Last day',
    );
    return '$_temp0';
  }

  @override
  String get budgetOverviewCalendarMonth => 'Calendar month';

  @override
  String get budgetOverviewSetPayday => 'Set payday';

  @override
  String budgetOverviewOverall(String spent, String budget) {
    return '$spent of $budget';
  }

  @override
  String budgetOverviewSafePerDay(String perDay) {
    return 'You can spend $perDay a day';
  }

  @override
  String budgetOverviewCurrencyNote(String currency) {
    return 'This budget counts $currency only';
  }

  @override
  String budgetOverviewRowAmounts(String spent, String limit) {
    return '$spent / $limit';
  }

  @override
  String get budgetOverviewStatusNear => 'Nearly used';

  @override
  String get budgetOverviewStatusFull => 'Used up';

  @override
  String budgetOverviewStatusOver(String gap) {
    return 'Over by $gap';
  }

  @override
  String budgetOverviewRowA11y(
    String category,
    String spent,
    String limit,
    String percent,
  ) {
    return '$category: spent $spent of $limit, $percent';
  }

  @override
  String get budgetOverviewNotBudgeted => 'Not budgeted';

  @override
  String get budgetOverviewNotBudgetedSub =>
      'Spending in categories with no limit';

  @override
  String get budgetOverviewEdit => 'Edit budgets';

  @override
  String get budgetOverviewPrevA11y => 'Previous cycle';

  @override
  String get budgetOverviewNextA11y => 'Next cycle';

  @override
  String get budgetOverviewEmptyTitle =>
      'Set limits and see what\'s safe to spend';

  @override
  String get budgetOverviewEmptyBody =>
      'Your spending shows below until you set a budget.';

  @override
  String get budgetOverviewEmptyAction => 'Set budgets';

  @override
  String get budgetOverviewLoadingA11y => 'Loading budget';

  @override
  String get budgetEditTitle => 'Budgets';

  @override
  String get budgetEditCurrency => 'Budget currency';

  @override
  String get budgetEditOverall => 'Overall';

  @override
  String get budgetEditOverallSum => 'Sum of categories';

  @override
  String get budgetEditOverallSet => 'A total I set';

  @override
  String get budgetEditCategories => 'Limit per category';

  @override
  String get budgetEditLimitHint => 'Leave empty for no limit';

  @override
  String get budgetEditAlerts => 'Alert me at';

  @override
  String get budgetEditAlertFirst => 'First alert';

  @override
  String get budgetEditAlertSecond => 'Second alert';

  @override
  String get budgetEditRollover => 'Roll over what\'s left';

  @override
  String get budgetEditRolloverHint =>
      'Unspent budget is added to the next cycle.';

  @override
  String get budgetEditAnnual => 'Annual budgets';

  @override
  String get budgetEditAnnualHint => 'For once-a-year costs like school fees';

  @override
  String get budgetEditPayday => 'Payday';

  @override
  String get budgetEditErrorLimit => 'A limit can\'t be negative';

  @override
  String budgetEditErrorThreshold(String min, String max) {
    return 'The percentage must be between $min and $max';
  }

  @override
  String get budgetEditErrorOrder =>
      'The first alert must be lower than the second';

  @override
  String get budgetEditSaved => 'Budget saved ✓';

  @override
  String get budgetAnnualTitle => 'Annual budgets';

  @override
  String get budgetAnnualEmpty => 'No annual budgets yet';

  @override
  String get budgetAnnualAdd => 'Add an annual budget';

  @override
  String recurringBillsSummary(String due, String subs) {
    return 'This month: $due due · $subs in subscriptions a month';
  }

  @override
  String recurringBillsDetected(String merchant, String amount) {
    return 'Found a subscription: $merchant, $amount a month';
  }

  @override
  String get recurringBillsTrack => 'Track it';

  @override
  String get recurringBillsNotSub => 'Not a subscription';

  @override
  String get recurringBillsUpcoming => 'Coming up';

  @override
  String recurringBillsInstallmentRow(String name, String index, String total) {
    return '$name · payment $index of $total';
  }

  @override
  String get recurringBillsLastOne => 'Last payment';

  @override
  String get recurringBillsMarkPaid => 'Mark paid';

  @override
  String get recurringBillsPaid => 'Paid ✓';

  @override
  String get recurringBillsAutoPaid => 'Marked from a captured payment';

  @override
  String get recurringBillsDueToday => 'Today';

  @override
  String recurringBillsDueIn(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $n days',
      one: 'Tomorrow',
    );
    return '$_temp0';
  }

  @override
  String recurringBillsOverdue(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n days overdue',
      one: '1 day overdue',
    );
    return '$_temp0';
  }

  @override
  String get recurringBillsKindSubscription => 'Subscription';

  @override
  String get recurringBillsKindInstallment => 'Installment';

  @override
  String get recurringBillsKindCard => 'Card payment';

  @override
  String get recurringBillsKindGameya => 'Gameya';

  @override
  String get recurringBillsGameyaManual => 'Gameya payments are logged by hand';

  @override
  String get recurringBillsSubsTitle => 'Subscriptions';

  @override
  String get recurringBillsSubsYear => 'Over a full year';

  @override
  String recurringBillsSubRow(String monthly, String yearly) {
    return '$monthly/mo · $yearly/yr';
  }

  @override
  String recurringBillsSubsTotal(String monthly, String yearly) {
    return 'Total $monthly a month, $yearly a year';
  }

  @override
  String get recurringBillsAdd => 'Add a bill or installment';

  @override
  String get recurringBillsEmptyTitle => 'No bills or installments yet';

  @override
  String get recurringBillsEmptyBody =>
      'I\'ll spot subscriptions from your transactions, and you can add any installment yourself.';

  @override
  String recurringBillsPaidSnack(String name) {
    return 'Marked $name as paid ✓';
  }

  @override
  String recurringBillsRowA11y(String name, String amount, String status) {
    return '$name, $amount, $status';
  }

  @override
  String get recurringBillEditTitleAdd => 'Add a bill or installment';

  @override
  String get recurringBillEditTitleEdit => 'Edit bill';

  @override
  String get recurringBillEditType => 'Type';

  @override
  String get recurringBillEditName => 'Name';

  @override
  String get recurringBillEditNamePlaceholder => 'e.g. Fridge installment';

  @override
  String get recurringBillEditAmount => 'Amount';

  @override
  String get recurringBillEditRepeats => 'Repeats';

  @override
  String get recurringBillEditNextDue => 'Next payment';

  @override
  String get recurringBillEditPaid => 'Paid';

  @override
  String get recurringBillEditPaidOf => 'of';

  @override
  String recurringBillEditRemind(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remind me $n days before',
      one: 'Remind me 1 day before',
      zero: 'Remind me on the day',
    );
    return '$_temp0';
  }

  @override
  String get recurringBillEditAccount => 'Account (optional)';

  @override
  String recurringBillEditDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get recurringBillEditDeleteBody =>
      'It will be removed from Bills. Transactions already recorded stay.';

  @override
  String get recurringBillEditErrorPaid => 'Paid can\'t be more than the total';

  @override
  String recurringBillEditErrorTotal(String max) {
    return 'The number of payments must be from 1 to $max';
  }

  @override
  String recurringBillEditErrorRemind(String max) {
    return 'Reminder: 0 to $max days';
  }

  @override
  String get recurringBillEditErrorDue => 'Pick the next payment date';

  @override
  String get recurringBillEditSaved => 'Bill saved ✓';

  @override
  String homeQuickAddVoiceLeft(String remaining, String max) {
    return '$remaining of $max voice logs left this month';
  }

  @override
  String get voiceLoggerTitle => 'Tell me what you paid';

  @override
  String get voiceLoggerExampleLabel => 'For example';

  @override
  String get voiceLoggerExample =>
      'Paid 150 pounds for vegetables, 45 for coffee and 30 for a taxi';

  @override
  String get voiceLoggerListening => 'Listening…';

  @override
  String get voiceLoggerDone => 'Done';

  @override
  String get voiceLoggerStopA11y => 'Stop recording';

  @override
  String voiceLoggerTranscriptA11y(String text) {
    return 'Heard so far: $text';
  }

  @override
  String get voiceLoggerUnderstanding => 'Understanding…';

  @override
  String voiceLoggerParsedTitle(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'I understood $n items',
      one: 'I understood 1 item',
    );
    return '$_temp0';
  }

  @override
  String get voiceLoggerAccount => 'Account';

  @override
  String get voiceLoggerWhen => 'When';

  @override
  String get voiceLoggerApplyAll => 'Applies to all';

  @override
  String get voiceLoggerAmountMissing => 'Amount?';

  @override
  String get voiceLoggerEditA11y => 'Edit this item';

  @override
  String get voiceLoggerRemoveA11y => 'Remove this item';

  @override
  String voiceLoggerSave(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Save $n',
      one: 'Save',
    );
    return '$_temp0';
  }

  @override
  String voiceLoggerSaved(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n expenses saved ✓',
      one: '1 expense saved ✓',
    );
    return '$_temp0';
  }

  @override
  String get voiceLoggerEmptyTitle => 'I didn\'t catch an amount';

  @override
  String get voiceLoggerEmptyBody => 'Try saying: \"150 vegetables\"';

  @override
  String get voiceLoggerUnavailable =>
      'Arabic voice isn\'t available on this phone';

  @override
  String get voiceLoggerUnavailableBody =>
      'You can type the transaction in a few seconds.';

  @override
  String get voiceLoggerOnlineTitle => 'Use online speech recognition?';

  @override
  String voiceLoggerOnlineBody(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'This phone can\'t recognise Arabic offline. If you agree, Apple\'s speech service converts your voice to text online. Zaghlol doesn\'t keep the recording.',
      'other': 'This phone can\'t recognise Arabic offline. If you agree, Google\'s speech service converts your voice to text online. Zaghlol doesn\'t keep the recording.',
    });
    return '$_temp0';
  }

  @override
  String get voiceLoggerOnlineAllow => 'Allow';

  @override
  String get voiceLoggerOnlineDeny => 'No, I\'ll type';

  @override
  String get voiceLoggerMicTitle => 'I need the microphone';

  @override
  String get voiceLoggerMicBody =>
      'So I can hear you. I don\'t keep a recording of your voice.';

  @override
  String get voiceLoggerLimitTitle => 'You\'ve used this month\'s voice logs';

  @override
  String voiceLoggerLimitBody(String max) {
    return 'You\'ve used all $max voice logs this month. They reset next month. Gold has no limit.';
  }

  @override
  String get captureScanTitle => 'Scan a screenshot';

  @override
  String get captureScanChoose => 'Choose an image';

  @override
  String get captureScanChooseAnother => 'Choose another image';

  @override
  String get captureScanReading => 'Reading the image…';

  @override
  String get captureScanOnDevice => 'The image is read on this phone.';

  @override
  String get captureScanFound => 'Here\'s what I found';

  @override
  String get captureScanAmount => 'Amount';

  @override
  String get captureScanParty => 'To / From';

  @override
  String get captureScanReference => 'Reference';

  @override
  String get captureScanDate => 'When';

  @override
  String get captureScanCategory => 'Category';

  @override
  String get captureScanAccount => 'Account';

  @override
  String get captureScanEditA11y => 'Edit';

  @override
  String get captureScanFromShare =>
      'Here\'s what I read from the image you sent. Check it and save.';

  @override
  String get captureScanEmptyTitle =>
      'I couldn\'t find a payment in this image';

  @override
  String get captureScanEmptyBody =>
      'Try a clearer image, or type the transaction.';

  @override
  String get captureScanDuplicateTitle =>
      'Already captured from a bank message';

  @override
  String get captureScanDuplicateView => 'View';

  @override
  String get captureScanDuplicateSave => 'Save anyway';

  @override
  String get captureScanUnsupported => 'I can\'t read this kind of file';

  @override
  String get captureScanPhotoTitle => 'I need access to your photos';

  @override
  String get captureScanPhotoBody =>
      'So you can pick the screenshot. I only look at the image you choose.';

  @override
  String wealthOverviewUnitGold(String karat, String grams) {
    return 'Gold ${karat}K: $grams';
  }

  @override
  String wealthOverviewUnitCoins(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n gold coins',
      one: '1 gold coin',
    );
    return '$_temp0';
  }

  @override
  String wealthOverviewUnitsA11y(String list) {
    return 'Net worth: $list';
  }

  @override
  String wealthOverviewGoldTitle(String karat) {
    return 'Gold ${karat}K';
  }

  @override
  String wealthOverviewGoldSub(String grams, String value) {
    return '$grams · ≈ $value';
  }

  @override
  String wealthOverviewCertTitle(String bank) {
    return '$bank certificate';
  }

  @override
  String wealthOverviewCertSub(String percent, String principal) {
    return '$percent rate · $principal';
  }

  @override
  String wealthOverviewCertPayout(String date, String payout) {
    return 'Next payout $date: $payout';
  }

  @override
  String get wealthOverviewManualValue => 'Estimated value';

  @override
  String wealthOverviewNoRate(String currency) {
    return 'No rate for $currency yet, so it\'s shown in its own currency only';
  }

  @override
  String get wealthOverviewAssetsEmpty =>
      'No assets yet. Add your gold or certificates.';

  @override
  String wealthOverviewAssetRowA11y(String name, String value) {
    return '$name, $value';
  }

  @override
  String accountsOverviewHiddenCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n accounts',
      one: '1 account',
    );
    return '$_temp0';
  }

  @override
  String get accountsHiddenTitle => 'Hidden accounts';

  @override
  String get accountsHiddenIntro =>
      'These accounts are out of your lists, but their transactions still count in totals, budgets and charts.';

  @override
  String get accountsHiddenUnhide => 'Unhide';

  @override
  String get accountsHiddenUnhidden => 'The account is back in your list';

  @override
  String get accountsHiddenEmpty => 'No hidden accounts';

  @override
  String accountsHiddenRowA11y(String card) {
    return '$card, hidden. Tap to open the account';
  }

  @override
  String get wealthAssetTitleAdd => 'Add an asset';

  @override
  String get wealthAssetTitleEdit => 'Edit asset';

  @override
  String get wealthAssetType => 'Type';

  @override
  String get wealthAssetOptional => 'Optional';

  @override
  String get wealthAssetGoldKarat => 'Karat';

  @override
  String get wealthAssetGoldGrams => 'Weight in grams';

  @override
  String get wealthAssetGoldGramsHint => 'Up to three decimals';

  @override
  String get wealthAssetCoinCount => 'Number of coins';

  @override
  String get wealthAssetBoughtOn => 'Bought on';

  @override
  String get wealthAssetPricePaid => 'Price paid';

  @override
  String get wealthAssetCertBank => 'Bank';

  @override
  String get wealthAssetCertPrincipal => 'Principal';

  @override
  String get wealthAssetCertRate => 'Rate';

  @override
  String get wealthAssetCertPayout => 'Payout';

  @override
  String get wealthAssetCertMaturity => 'Matures on';

  @override
  String get wealthAssetCashCurrency => 'Currency';

  @override
  String get wealthAssetCashAmount => 'Amount';

  @override
  String get wealthAssetName => 'Name';

  @override
  String get wealthAssetStocksCurrency => 'Trading currency';

  @override
  String get wealthAssetValue => 'Current value';

  @override
  String get wealthAssetValueHint =>
      'Enter it yourself and update it now and then.';

  @override
  String get wealthAssetDeleteTitle => 'Delete this asset?';

  @override
  String get wealthAssetDeleteBody =>
      'It will be removed from your net worth and anything worked out from it.';

  @override
  String get wealthAssetSaved => 'Asset saved ✓';

  @override
  String get wealthAssetErrorType => 'Choose an asset type';

  @override
  String get wealthAssetErrorGrams => 'Weight must be above zero';

  @override
  String get wealthAssetErrorGramsDecimals => 'Up to three decimals only';

  @override
  String wealthAssetErrorRate(String max) {
    return 'The rate must be from 0 to $max%';
  }

  @override
  String get wealthAssetErrorMaturity =>
      'Maturity must be after the purchase date';

  @override
  String get wealthPricesTitle => 'Prices';

  @override
  String wealthPricesUpdated(String when) {
    return 'Updated $when';
  }

  @override
  String get wealthPricesGoldSection => 'Gold (per gram)';

  @override
  String wealthPricesCurrenciesSection(String currency) {
    return 'Currencies to $currency';
  }

  @override
  String wealthPricesGoldRowA11y(String karat, String price) {
    return '${karat}K: $price per gram';
  }

  @override
  String wealthPricesCurrencyRowA11y(String currency, String rate) {
    return '$currency: $rate';
  }

  @override
  String get wealthPricesOverride => 'Change price';

  @override
  String get wealthPricesOverrideTitle => 'Your price';

  @override
  String wealthPricesOverrideField(String currency) {
    return 'Price in $currency';
  }

  @override
  String get wealthPricesOverrideUse => 'Use my price';

  @override
  String get wealthPricesOverrideNote =>
      'Your price is used until you reset it.';

  @override
  String get wealthPricesYours => 'Your price';

  @override
  String get wealthPricesReset => 'Reset';

  @override
  String get wealthPricesNeverTitle => 'Prices haven\'t been downloaded yet';

  @override
  String get wealthPricesNeverBody =>
      'Connect once, or enter a price yourself.';

  @override
  String get wealthPricesEnterManually => 'Enter manually';

  @override
  String get wealthPricesFetchFailed =>
      'Couldn\'t update prices. Showing the last known ones.';

  @override
  String get wealthPricesPrivacy =>
      'Updating prices doesn\'t send anything about your money or assets.';

  @override
  String get zakahMainTitle => 'Zakah';

  @override
  String get zakahMainDisclaimerSummary =>
      'This is an estimate, not a ruling. Ask a scholar before you pay Zakah.';

  @override
  String get zakahMainDisclaimer =>
      'This calculation is an estimate and not a religious ruling. Please consult a qualified scholar before paying Zakah.';

  @override
  String get zakahMainNisabReached => 'Nisab reached';

  @override
  String get zakahMainNisabNotReached => 'Nisab not reached';

  @override
  String zakahMainNisabInfo(String grams, String karat, String value) {
    return 'The nisab is $grams of ${karat}K gold, about $value';
  }

  @override
  String get zakahMainNisabNotReachedBody =>
      'You\'re under the nisab now, so the estimate shows nothing due. I\'ll keep watching with you.';

  @override
  String zakahMainLotGold(String karat, String grams) {
    return 'Gold ${karat}K · $grams';
  }

  @override
  String zakahMainLotCash(String currency, String amount) {
    return 'Cash and balances in $currency: $amount';
  }

  @override
  String zakahMainLotInvest(String currency, String amount) {
    return 'Stocks and funds in $currency: $amount';
  }

  @override
  String zakahMainLotCertificate(String amount) {
    return 'Bank certificates: $amount';
  }

  @override
  String zakahMainDebtsLine(String debts) {
    return 'After due debts of $debts';
  }

  @override
  String zakahMainHawlProgress(String done, String total) {
    return 'Hawl: day $done of $total';
  }

  @override
  String get zakahMainHawlDone => 'Hawl complete';

  @override
  String zakahMainDueIn(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Due in $n days',
      one: 'Due tomorrow',
    );
    return '$_temp0';
  }

  @override
  String zakahMainDueHijri(String hijri) {
    return 'Hijri: $hijri';
  }

  @override
  String zakahMainDue(String dueNative) {
    return 'Due: $dueNative';
  }

  @override
  String zakahMainDueCost(String cost) {
    return '≈ $cost';
  }

  @override
  String get zakahMainStatusLabel => 'Payment status';

  @override
  String get zakahMainStatusPending => 'Pending';

  @override
  String get zakahMainStatusPartial => 'Partly paid';

  @override
  String get zakahMainStatusPaid => 'Paid';

  @override
  String zakahMainPaidOn(String date) {
    return 'Paid on $date';
  }

  @override
  String get zakahMainStaleNote =>
      'Prices are out of date, so the EGP amounts are approximate.';

  @override
  String get zakahMainEmptyTitle => 'Add assets to work out Zakah';

  @override
  String get zakahMainEmptyAdd => 'Add an asset';

  @override
  String get zakahMainHowTitle => 'How is it worked out?';

  @override
  String zakahMainHowNisab(String grams, String karat) {
    return 'The nisab is $grams of ${karat}K gold at today\'s price.';
  }

  @override
  String zakahMainHowHawl(String days) {
    return 'The hawl is one lunar year, $days days from when you got the asset.';
  }

  @override
  String zakahMainHowRate(String percent) {
    return 'What\'s due is $percent of each asset in its own unit: gold in grams, cash in its currency.';
  }

  @override
  String zakahMainHowPurity(String karat, String percent) {
    return '${karat}K gold counts at $percent toward the nisab.';
  }

  @override
  String get zakahMainHowDebts =>
      'Debts that are due now are deducted from cash first.';

  @override
  String zakahMainLotA11y(String lot, String status, String dueNative) {
    return '$lot, $status, due $dueNative';
  }

  @override
  String get chatMainSegAsk => 'Ask';

  @override
  String get chatMainSegTips => 'Tips';

  @override
  String get chatMainGreeting =>
      'Ask me anything about your money, in Arabic or English. I answer from the data on your phone.';

  @override
  String get chatMainInputHint => 'Ask me about your money…';

  @override
  String get chatMainSendA11y => 'Send question';

  @override
  String chatMainTooLong(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Keep the question to $n characters',
      one: 'Keep the question to 1 character',
    );
    return '$_temp0';
  }

  @override
  String chatMainFilterNote(String cards) {
    return 'Answers cover $cards';
  }

  @override
  String get chatMainRoast => 'Roast me';

  @override
  String get chatMainRoastHint =>
      'Changes the style only. The numbers stay the same.';

  @override
  String get chatMainClear => 'Clear chat';

  @override
  String get chatMainCleared => 'Chat cleared';

  @override
  String get chatMainOpenTransactions => 'Open in Transactions';

  @override
  String get chatMainTypingA11y => 'Zaghlol is typing';

  @override
  String chatMainUserA11y(String text) {
    return 'You said: $text';
  }

  @override
  String chatMainZaghlolA11y(String text) {
    return 'Zaghlol replied: $text';
  }

  @override
  String get chatMainChartA11y => 'A small chart comparing the figures above';

  @override
  String get chatChipCoffee => 'How much on coffee?';

  @override
  String get chatChipTopMerchants => 'Where do I spend most?';

  @override
  String get chatChipDues => 'What bills are coming?';

  @override
  String get chatChipBudgetLeft => 'What\'s left in my budget?';

  @override
  String get chatChipBiggest => 'What was my biggest expense?';

  @override
  String get chatChipSavings => 'How much did I save?';

  @override
  String get chatChipCompare => 'This month vs last';

  @override
  String chatChipCard(String card) {
    return 'How much on $card?';
  }

  @override
  String get chatFallbackText => 'I can\'t answer that yet. Try one of these:';

  @override
  String get chatAnswerPickOne => 'Which one do you mean?';

  @override
  String get chatPeriodToday => 'today';

  @override
  String get chatPeriodYesterday => 'yesterday';

  @override
  String get chatPeriodThisWeek => 'this week';

  @override
  String get chatPeriodLastWeek => 'last week';

  @override
  String get chatPeriodThisCycle => 'this cycle';

  @override
  String get chatPeriodLastCycle => 'last cycle';

  @override
  String get chatPeriodThisMonth => 'this month';

  @override
  String get chatPeriodLastMonth => 'last month';

  @override
  String get chatPeriodSinceYearStart => 'since the start of the year';

  @override
  String chatPeriodLastMonths(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'in the last $n months',
      one: 'in the last month',
    );
    return '$_temp0';
  }

  @override
  String chatPeriodRange(String start, String end) {
    return 'from $start to $end';
  }

  @override
  String chatPeriodNextDays(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'in the next $n days',
      one: 'tomorrow',
    );
    return '$_temp0';
  }

  @override
  String get chatPeriodUntilPayday => 'until payday';

  @override
  String chatAnswerCurrencyLead(String currency) {
    return 'In $currency:';
  }

  @override
  String chatAnswerSpendOn(String amount, String subject, String span) {
    return 'You spent $amount on $subject $span.';
  }

  @override
  String chatAnswerSpendOnCount(
    String amount,
    String subject,
    String span,
    String times,
  ) {
    return 'You spent $amount on $subject $span across $times.';
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
      'up': '$delta more than $spanB',
      'down': '$delta less than $spanB',
      'other': 'about the same as $spanB',
    });
    return 'You spent $amount $span, $_temp0.';
  }

  @override
  String chatAnswerTopMerchants(String span, String list) {
    return 'Your top merchants $span: $list.';
  }

  @override
  String chatAnswerBalance(String account, String amount, String when) {
    return '$account has $amount, as of $when.';
  }

  @override
  String chatAnswerBalanceCredit(
    String account,
    String available,
    String limit,
  ) {
    return '$account has $available available of $limit.';
  }

  @override
  String chatAnswerBalanceUnknown(String account) {
    return 'I don\'t know the balance of $account yet. It\'ll show up with the first message that includes it.';
  }

  @override
  String chatAnswerBudgetLeft(String left, String subject) {
    return 'You have $left left in your $subject budget.';
  }

  @override
  String chatAnswerBudgetLeftPerDay(String left, String perDay) {
    return 'You have $left left in your budget, that\'s $perDay a day until payday.';
  }

  @override
  String chatAnswerBudgetOver(String subject, String gap) {
    return '$subject is $gap over its budget.';
  }

  @override
  String chatAnswerBudgetNone(String subject) {
    return 'There\'s no budget set for $subject. Want to set one?';
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
      other: 'You have $n payments $span: $list, $amount in total.',
      one: 'You have 1 payment $span: $list.',
      zero: 'No bills or installments $span.',
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
    return 'Your biggest expense $span was $amount at $merchant on $date.';
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
      'short': '$span you spent $gap more than you earned.',
      'other': '$span you saved $saved, that\'s $percent of your income.',
    });
    return '$_temp0';
  }

  @override
  String chatAnswerSpendCard(String amount, String card, String span) {
    return 'You spent $amount on $card $span.';
  }

  @override
  String chatAnswerNoData(String subject, String start, String end) {
    return 'There\'s no spending on $subject between $start and $end.';
  }

  @override
  String get chatAnswerNoDataGeneric => 'There\'s no data for that period.';

  @override
  String get chatAnswerError =>
      'Something went wrong while reading your data. Try again.';

  @override
  String get chatRoastOn =>
      'Fine, I\'m game if you are! I\'ll roast the spending, never you.';

  @override
  String get chatRoastOff => 'Back to serious. The numbers are as they were.';

  @override
  String get chatRoastOfferToggle =>
      'That was a quick roast. Want me to turn roast mode on?';

  @override
  String chatRoastDelivery(String orders, String amount, String span) {
    return '$orders worth $amount of delivery $span? Your courier knows your door better than I do 😄';
  }

  @override
  String chatRoastDeliveryAlt(String amount, String span) {
    return '$amount on delivery $span.. Your kitchen is waiting for a visit!';
  }

  @override
  String chatRoastCoffee(String amount, String span) {
    return '$amount on coffee $span? You\'re practically a partner in the bean farm! ☕';
  }

  @override
  String chatRoastCoffeeAlt(String span, String amount) {
    return 'Coffee cost $amount $span. Sadly, caffeine doesn\'t pay your bills 😄';
  }

  @override
  String chatRoastTopCategory(String category, String percent) {
    return '$category takes $percent of your spending. That\'s not a budget line, that\'s a hobby!';
  }

  @override
  String chatRoastTopCategoryAlt(String category, String percent) {
    return '$category takes $percent of your spending and is still asking for more!';
  }

  @override
  String chatRoastSplurge(String amount, String merchant) {
    return '$amount in one go at $merchant? That\'s not an errand, that\'s a big decision!';
  }

  @override
  String chatRoastSplurgeAlt(String amount, String merchant, String span) {
    return '$amount at $merchant in one go $span. A historic day for your wallet!';
  }

  @override
  String chatRoastWeekend(String peakDay) {
    return 'Your wallet is scared of $peakDay, and it has a point!';
  }

  @override
  String chatRoastWeekendAlt(String peakDay, String amount) {
    return 'You average $amount on $peakDay. The other days are jealous!';
  }

  @override
  String chatRoastSubscriptions(String yearly) {
    return 'Your subscriptions take $yearly a year. Do you actually open any of them?';
  }

  @override
  String chatRoastSubscriptionsAlt(String yearly) {
    return 'Your $yearly a year in subscriptions keep running even while you sleep!';
  }

  @override
  String chatRoastLateNight(String time) {
    return 'Orders after $time? The app is more awake than you are!';
  }

  @override
  String chatRoastGoldEquivalent(
    String amount,
    String category,
    String grams,
    String karat,
  ) {
    return '$amount on $category could have bought $grams of ${karat}K gold. But it was fun, right?';
  }

  @override
  String get chatRoastGentle =>
      'I\'ll skip the roast today. These numbers deserve a serious look. Want to go through the biggest item together?';

  @override
  String get chatRoastClean =>
      'I looked for something to roast and found nothing! You\'re annoyingly organised 👏';

  @override
  String get roiTipsDisclaimerSummary =>
      'These are general ideas, not financial advice.';

  @override
  String get roiTipsDisclaimer =>
      'These are general suggestions, not financial or investment advice. The figures are estimates and may differ in practice.';

  @override
  String roiTipsProjection(String years, String year1, String year2) {
    String _temp0 = intl.Intl.selectLogic(years, {
      'two': 'Year 1: save about $year1. Year 2: about $year2.',
      'other': 'Year 1: save about $year1.',
    });
    return '$_temp0';
  }

  @override
  String get roiTipsShare => 'Share';

  @override
  String get roiTipsNotForMe => 'Not for me';

  @override
  String get roiTipsDismissed => 'Removed. It won\'t show again.';

  @override
  String roiTipsBadgeA11y(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n new tips',
      one: '1 new tip',
    );
    return '$_temp0';
  }

  @override
  String get roiTipsEmptyTitle => 'No tips right now';

  @override
  String get roiTipsEmptyBody => 'I\'ll tell you when I spot something useful.';

  @override
  String get roiTipsLockedBody => 'Tips built on your own spending, with Gold';

  @override
  String get roiRuleCoffeeTitle => 'A coffee machine instead of cafés';

  @override
  String roiRuleCoffeeBody(String monthly, String alt) {
    return 'You spend $monthly a month at cafés. A machine on installments plus beans and milk comes to about $alt a month.';
  }

  @override
  String get roiRuleDeliveryTitle => 'Home cooking instead of daily delivery';

  @override
  String roiRuleDeliveryBody(String monthly, String alt) {
    return 'Delivery takes $monthly a month. A small cooking appliance on installments plus home groceries comes to about $alt a month.';
  }

  @override
  String get roiRuleWaterTitle => 'A water filter instead of bottles';

  @override
  String roiRuleWaterBody(String monthly, String alt) {
    return 'Bottled water costs $monthly a month. A filter on installments plus new cartridges comes to about $alt a month.';
  }

  @override
  String get roiRuleIdleCashTitle => 'Your cash is sitting idle';

  @override
  String roiRuleIdleCashBody(String idle, String exampleRate) {
    return '$idle in your account above your budget has sat there for over twenty days earning nothing. A money-market fund or a savings certificate could put it to work. Example rate, for illustration only: $exampleRate.';
  }

  @override
  String get roiRuleCommuteTitle => 'Your regular app rides';

  @override
  String roiRuleCommuteBody(String monthly, String alt) {
    return 'Ride-hailing costs you $monthly a month. A vehicle on installments plus public transport for long trips comes to about $alt a month.';
  }

  @override
  String get roiRuleCardInterestTitle => 'Pay your credit card in full';

  @override
  String roiRuleCardInterestBody(String balance, String exampleRate) {
    return 'You owe $balance on your credit card and hold more cash than that. Paying in full before the statement date saves the interest. Example rate, for illustration only: $exampleRate a month.';
  }

  @override
  String get roiRuleSubscriptionsTitle => 'One yearly plan instead of several';

  @override
  String roiRuleSubscriptionsBody(String monthly, String alt) {
    return 'You pay $monthly a month across several subscriptions. A shared yearly plan could bring that to about $alt a month.';
  }

  @override
  String get roiRuleStaplesTitle => 'Buy staples once, on payday';

  @override
  String roiRuleStaplesBody(String monthly, String alt) {
    return 'You buy staples in many small trips for $monthly a month. One bulk shop on payday could bring that to about $alt.';
  }

  @override
  String get commonActionCopy => 'Copy';

  @override
  String get commonActionContactSupport => 'Contact support';

  @override
  String get commonActionSignIn => 'Sign in';

  @override
  String get commonActionSignOut => 'Sign out';

  @override
  String get commonActionManage => 'Manage';

  @override
  String get commonSupportCodeLabel => 'Support code';

  @override
  String commonSupportCodeValue(String supportCode) {
    return '$supportCode';
  }

  @override
  String get commonSupportCodeCopied => 'Copied ✓';

  @override
  String commonSupportCodeCopyA11y(String supportCode) {
    return 'Copy support code $supportCode';
  }

  @override
  String get commonSupportHint =>
      'Give this code to support so they can find your phone.';

  @override
  String get settingsMainTitle => 'Settings';

  @override
  String settingsMainFinishSetup(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n setup steps left',
      one: '1 setup step left',
    );
    return '$_temp0';
  }

  @override
  String get settingsMainGoldFree => 'Free plan';

  @override
  String settingsMainGoldActive(String plan) {
    String _temp0 = intl.Intl.selectLogic(plan, {
      'monthly': 'Gold · Monthly',
      'yearly': 'Gold · Yearly',
      'lifetime': 'Gold · Lifetime',
      'other': 'Gold',
    });
    return '$_temp0';
  }

  @override
  String get settingsMainSeeGold => 'See Gold';

  @override
  String get settingsMainSectionGeneral => 'General';

  @override
  String get settingsMainSectionData => 'Your data';

  @override
  String get settingsMainPreferences => 'Preferences';

  @override
  String get settingsMainNotifications => 'Notifications';

  @override
  String get settingsMainCapture => 'Capture';

  @override
  String settingsMainCaptureSub(String state) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'ok': 'All on',
      'attention': 'Needs attention',
      'other': 'Not set up yet',
    });
    return '$_temp0';
  }

  @override
  String get settingsMainCategories => 'Categories & rules';

  @override
  String get settingsMainBackup => 'Backup';

  @override
  String settingsMainBackupSub(String state, String date) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'never': 'No backup yet',
      'other': 'Last: $date',
    });
    return '$_temp0';
  }

  @override
  String get settingsMainExports => 'Export & import';

  @override
  String get settingsMainPrivacy => 'Privacy & data';

  @override
  String get settingsMainAbout => 'About';

  @override
  String get categoriesListTitle => 'Categories & rules';

  @override
  String get categoriesListTabCategories => 'Categories';

  @override
  String get categoriesListTabRules => 'Rules';

  @override
  String categoriesListSubCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n subcategories',
      one: '1 subcategory',
    );
    return '$_temp0';
  }

  @override
  String get categoriesListSystemNote =>
      'These are Zaghlol\'s built-in categories. Gold lets you add subcategories.';

  @override
  String get categoriesListNew => 'New category';

  @override
  String get categoriesListNewSub => 'New subcategory';

  @override
  String categoriesListRulesCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n rules',
      one: '1 rule',
      zero: 'No rules',
    );
    return '$_temp0';
  }

  @override
  String get categoriesListRulesSearch => 'Search rules';

  @override
  String categoriesListRuleA11y(String merchant, String category) {
    return '$merchant goes to $category';
  }

  @override
  String get categoriesListRuleEditA11y => 'Change the rule\'s category';

  @override
  String get categoriesListRuleDeleteA11y => 'Delete the rule';

  @override
  String get categoriesListRulesEmpty =>
      'When you fix a category, I\'ll ask if you want me to remember it.';

  @override
  String get categoriesListRuleDeleteTitle => 'Delete this rule?';

  @override
  String get categoriesListRuleDeleteBody =>
      'Zaghlol won\'t apply it to future transactions.';

  @override
  String get categoriesListRuleDeleted => 'Rule deleted';

  @override
  String get categoriesListNoResults => 'No rule matches that';

  @override
  String get categoriesEditTitleNew => 'New category';

  @override
  String get categoriesEditTitleEdit => 'Edit category';

  @override
  String get categoriesEditName => 'Category name';

  @override
  String get categoriesEditParent => 'Inside';

  @override
  String get categoriesEditParentNone => 'None (top level)';

  @override
  String get categoriesEditBucket => 'Type';

  @override
  String get categoriesEditBucketNeeds => 'Needs';

  @override
  String get categoriesEditBucketWants => 'Wants';

  @override
  String get categoriesEditBucketObligations => 'Obligations';

  @override
  String get categoriesEditBucketSavings => 'Savings';

  @override
  String get categoriesEditBucketIncome => 'Income';

  @override
  String get categoriesEditBucketGiving => 'Giving';

  @override
  String get categoriesEditBucketRequired => 'Choose a type';

  @override
  String get categoriesEditIcon => 'Icon';

  @override
  String get categoriesEditColor => 'Colour';

  @override
  String get categoriesEditDelete => 'Delete category';

  @override
  String categoriesEditDeleteTitle(String category) {
    return 'Delete \"$category\"?';
  }

  @override
  String get categoriesEditDeleteBody =>
      'Choose a category to move its transactions to before we delete it.';

  @override
  String get categoriesEditMoveTo => 'Move transactions to';

  @override
  String get categoriesEditMoveRequired => 'Choose a category to move them to';

  @override
  String get categoriesEditDeleteConfirm => 'Delete and move';

  @override
  String get categoriesEditDeleted => 'Category deleted and transactions moved';

  @override
  String get categoriesEditLockedBody => 'Your own categories come with Gold';

  @override
  String get templatesBuilderTitle => 'New message template';

  @override
  String get templatesBuilderPickTitle => 'Paste or pick a message';

  @override
  String get templatesBuilderFromReview => 'From the review queue';

  @override
  String get templatesBuilderPaste => 'Paste a message';

  @override
  String get templatesBuilderEmpty => 'Paste a bank message to begin';

  @override
  String get templatesBuilderPrivate =>
      'The message stays on your phone and isn\'t sent anywhere.';

  @override
  String get templatesBuilderTagTitle => 'Tap the parts';

  @override
  String get templatesBuilderTapHint => 'Tap a part, then say what it is.';

  @override
  String get templatesBuilderTagAmount => 'Amount';

  @override
  String get templatesBuilderTagCurrency => 'Currency';

  @override
  String get templatesBuilderTagMerchant => 'Merchant';

  @override
  String get templatesBuilderTagLast4 => 'Last four digits';

  @override
  String get templatesBuilderTagBalance => 'Balance';

  @override
  String get templatesBuilderTagDate => 'Date';

  @override
  String get templatesBuilderDirection => 'Direction';

  @override
  String get templatesBuilderSender => 'Sender name';

  @override
  String get templatesBuilderSenderHint => 'As it shows on the messages';

  @override
  String get templatesBuilderTestTitle => 'Test the template';

  @override
  String templatesBuilderTestResult(String done, String total) {
    return 'Similar messages the template understood: $done of $total';
  }

  @override
  String get templatesBuilderTestFailTitle => 'One message didn\'t match';

  @override
  String templatesBuilderTestFailReason(String state) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'amount': 'I can\'t find the amount in it.',
      'direction': 'I can\'t tell if it\'s spending or income.',
      'other': 'It looks different from the template.',
    });
    return '$_temp0';
  }

  @override
  String get templatesBuilderSave => 'Save template';

  @override
  String get templatesBuilderSaved => 'Template saved ✓';

  @override
  String get templatesBuilderErrorAmount => 'Tag the amount first';

  @override
  String get templatesBuilderErrorSender => 'Enter the sender name';

  @override
  String get templatesBuilderErrorSelfParse =>
      'The template has to read the message you built it from';

  @override
  String get templatesBuilderLockedBody =>
      'Teach Zaghlol an unsupported bank\'s messages, with Gold';

  @override
  String get backupSettingsTitle => 'Backup';

  @override
  String get backupSettingsWhere => 'Where to back up';

  @override
  String get backupSettingsAccount => 'Account';

  @override
  String get backupSettingsAccountChange => 'Change';

  @override
  String backupSettingsLast(String date, String size) {
    return 'Last backup: $date · $size';
  }

  @override
  String get backupSettingsNever => 'No backup yet';

  @override
  String get backupSettingsFreeNudge =>
      'Your first backup is free, and it protects your data if the phone is lost.';

  @override
  String get backupSettingsNow => 'Back up now';

  @override
  String get backupSettingsFreeReplaces =>
      'The new backup replaces the current one.';

  @override
  String get backupSettingsAuto => 'Automatic backup';

  @override
  String get backupSettingsAutoOff => 'Off';

  @override
  String get backupSettingsAutoDaily => 'Daily';

  @override
  String get backupSettingsAutoWeekly => 'Weekly';

  @override
  String get backupSettingsAutoMonthly => 'Monthly';

  @override
  String get backupSettingsAutoLocked => 'Automatic backups come with Gold';

  @override
  String get backupSettingsVersions => 'Saved versions';

  @override
  String get backupSettingsVersionsLocked => 'Gold keeps five versions';

  @override
  String get backupSettingsGoldKeeps =>
      'If you go Gold, your current backup becomes the first version in the history.';

  @override
  String get backupSettingsPassphrase => 'Backup passphrase';

  @override
  String get backupSettingsPassphraseChange => 'Change';

  @override
  String get backupSettingsRestore => 'Restore a backup';

  @override
  String get backupSettingsIncludes =>
      'The backup holds your transactions, settings, categories, rules and ignored cards.';

  @override
  String get backupSettingsExcludes =>
      'It doesn\'t hold your security keys or phone permissions. You\'ll set those up again after restoring.';

  @override
  String backupSettingsStale(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Your last backup is $n days old',
      one: 'Your last backup is 1 day old',
    );
    return '$_temp0';
  }

  @override
  String get backupSettingsRunning => 'Backing up…';

  @override
  String get backupSettingsCancelNote =>
      'You can cancel before the upload finishes.';

  @override
  String get backupSettingsDone => 'Backup done ✓';

  @override
  String get backupSettingsErrorNetwork =>
      'The backup didn\'t finish because the connection dropped. Your previous backup is still there.';

  @override
  String backupSettingsErrorStorage(String provider) {
    return 'There\'s no space left on $provider. Free some up and try again. Your previous backup is still there.';
  }

  @override
  String backupSettingsErrorAuth(String provider) {
    return 'Your $provider sign-in expired. Sign in again and retry.';
  }

  @override
  String get backupSettingsErrorIcloud =>
      'iCloud isn\'t available on this phone. Sign in with your Apple ID in Settings and turn on iCloud Drive.';

  @override
  String get backupSettingsErrorGeneric =>
      'The backup didn\'t work. Try again.';

  @override
  String get backupPassphraseTitle => 'Choose a backup passphrase';

  @override
  String get backupPassphraseNew => 'Passphrase';

  @override
  String get backupPassphraseConfirm => 'Enter it again';

  @override
  String get backupPassphraseWeak => 'Weak';

  @override
  String get backupPassphraseFair => 'Fair';

  @override
  String get backupPassphraseStrong => 'Strong';

  @override
  String get backupPassphraseWarning =>
      'If you forget this passphrase, nobody can open your backup, not even us.';

  @override
  String get backupPassphraseUnderstand => 'I know it can\'t be recovered';

  @override
  String get backupPassphraseTooShort => 'Use at least 10 characters';

  @override
  String get backupPassphraseMismatch => 'The passphrases don\'t match';

  @override
  String get backupPassphraseAckRequired => 'Tick that you understand first';

  @override
  String get backupPassphraseSave => 'Save and back up';

  @override
  String get backupPassphraseChangeTitle => 'Change backup passphrase';

  @override
  String get backupPassphraseCurrent => 'Current passphrase';

  @override
  String get backupPassphraseCurrentWrong => 'The current passphrase is wrong';

  @override
  String get backupPassphraseChanged => 'Passphrase changed ✓';

  @override
  String get exportsMainTitle => 'Export & import';

  @override
  String get exportsMainExportSection => 'Export';

  @override
  String get exportsMainFormat => 'Format';

  @override
  String get exportsMainFormatCsv => 'CSV';

  @override
  String get exportsMainFormatExcel => 'Excel';

  @override
  String get exportsMainDates => 'Dates';

  @override
  String get exportsMainCategories => 'Categories';

  @override
  String get exportsMainCategoriesAll => 'All categories';

  @override
  String get exportsMainCards => 'Cards';

  @override
  String get exportsMainPreview => 'Preview of the first 20 rows';

  @override
  String get exportsMainPreviewEmpty => 'No transactions in this range';

  @override
  String get exportsMainFreePreview =>
      'The preview is free. Exporting comes with Gold.';

  @override
  String get exportsMainExport => 'Export';

  @override
  String get exportsMainCurrencyNote =>
      'Every row keeps its own currency. Nothing is converted.';

  @override
  String get exportsMainUnencrypted =>
      'The file you export isn\'t encrypted. Save it somewhere you trust.';

  @override
  String get exportsMainPreparing => 'Preparing the file…';

  @override
  String get exportsMainReady => 'The file is ready ✓';

  @override
  String get exportsMainSave => 'Save the file';

  @override
  String get exportsMainFailed => 'Couldn\'t prepare the file. Try again.';

  @override
  String get exportsImportSection => 'Import';

  @override
  String get exportsImportZaghlolCsv => 'Zaghlol CSV file';

  @override
  String get exportsImportPdfTitle => 'Bank statement (PDF)';

  @override
  String exportsImportPdfBanks(String banks) {
    return '$banks';
  }

  @override
  String get exportsImportOnlineTitle => 'Online bank statement';

  @override
  String exportsImportOnlineBanks(String banks) {
    return '$banks';
  }

  @override
  String get exportsImportPick => 'Choose the file';

  @override
  String get exportsImportParsing => 'Reading the file…';

  @override
  String get exportsImportPasswordTitle => 'This statement has a password';

  @override
  String get exportsImportPasswordBody =>
      'Enter the password. It\'s used on this phone only and isn\'t saved.';

  @override
  String get exportsImportPasswordLabel => 'Statement password';

  @override
  String get exportsImportPasswordWrong => 'That password is wrong';

  @override
  String exportsImportFound(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n transactions found',
      one: '1 transaction found',
    );
    return '$_temp0';
  }

  @override
  String exportsImportDuplicates(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n already in Zaghlol (skipped)',
      one: '1 already in Zaghlol (skipped)',
    );
    return '$_temp0';
  }

  @override
  String exportsImportUntracked(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n cards not tracked (skipped)',
      one: '1 card not tracked (skipped)',
    );
    return '$_temp0';
  }

  @override
  String exportsImportImportButton(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Import $n transactions',
      one: 'Import 1 transaction',
    );
    return '$_temp0';
  }

  @override
  String get exportsImportNothingNew =>
      'Everything in this file is already in Zaghlol';

  @override
  String get exportsImportImporting => 'Adding the transactions…';

  @override
  String exportsImportDone(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n transactions added ✓',
      one: '1 transaction added ✓',
    );
    return '$_temp0';
  }

  @override
  String get exportsImportEmptyTitle => 'No transactions in this file';

  @override
  String get exportsImportUnsupportedTitle =>
      'This isn\'t a supported statement';

  @override
  String exportsImportUnsupportedBody(String banks) {
    return 'Supported: $banks';
  }

  @override
  String get exportsImportWrongType => 'The file type isn\'t the one you chose';

  @override
  String get exportsImportFailed => 'Couldn\'t read the file. Try another one.';

  @override
  String get exportsImportLockedBody =>
      'Add past months and bank statements with Gold';

  @override
  String get goldPaywallTitle => 'Zaghlol Gold';

  @override
  String get goldPaywallCloseA11y => 'Close';

  @override
  String get goldPaywallHeadline => 'All your tools in one place';

  @override
  String get goldPaywallBenefitCharts =>
      'All twelve charts with deeper insight';

  @override
  String get goldPaywallBenefitVoice => 'Unlimited voice logging';

  @override
  String get goldPaywallBenefitExport => 'Export, import and bank statements';

  @override
  String get goldPaywallBenefitBackup => 'Automatic backups, five versions';

  @override
  String get goldPaywallBenefitAssets => 'Gold, certificates and assets';

  @override
  String get goldPaywallBenefitCustom => 'Your own categories and templates';

  @override
  String goldPaywallPlanName(String plan) {
    String _temp0 = intl.Intl.selectLogic(plan, {
      'monthly': 'Monthly',
      'yearly': 'Yearly',
      'lifetime': 'Lifetime',
      'other': 'Gold',
    });
    return '$_temp0';
  }

  @override
  String goldPaywallPlanPrice(String plan, String storePrice) {
    String _temp0 = intl.Intl.selectLogic(plan, {
      'monthly': '$storePrice per month',
      'yearly': '$storePrice per year',
      'lifetime': '$storePrice one time',
      'other': '$storePrice',
    });
    return '$_temp0';
  }

  @override
  String get goldPaywallBestValue => 'Best value';

  @override
  String get goldPaywallContinue => 'Continue';

  @override
  String get goldPaywallPlanRequired => 'Choose a plan first';

  @override
  String get goldPaywallRestore => 'Restore purchases';

  @override
  String get goldPaywallTerms => 'Terms';

  @override
  String get goldPaywallPrivacy => 'Privacy';

  @override
  String goldPaywallRenewal(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'The subscription renews automatically unless cancelled before the period ends, in your Apple account settings.',
      'other': 'The subscription renews automatically unless cancelled before the period ends, in Google Play.',
    });
    return '$_temp0';
  }

  @override
  String get goldPaywallRenewalSummary =>
      'It renews by itself, and you can cancel in the store any time.';

  @override
  String get goldPaywallLifetimeNote => 'One payment, no renewal.';

  @override
  String get goldPaywallPricesLoading => 'Loading prices…';

  @override
  String get goldPaywallPricesFailed =>
      'Can\'t load the prices. Check your connection and try again.';

  @override
  String get goldPaywallPurchasing => 'Opening the store…';

  @override
  String get goldPaywallPending =>
      'Your payment is still pending. Gold starts when it\'s complete.';

  @override
  String get goldPaywallVerifying => 'Verifying your purchase…';

  @override
  String get goldPaywallVerifyOffline =>
      'I\'ll finish checking when you\'re back online.';

  @override
  String get goldPaywallSuccess => 'Gold is on ✓';

  @override
  String get goldPaywallSuccessMascot =>
      'Congratulations. Gold is on and everything is unlocked.';

  @override
  String get goldPaywallCancelled =>
      'The purchase was cancelled. Nothing was charged.';

  @override
  String get goldPaywallInvalid =>
      'We couldn\'t verify the purchase. Try \"Restore purchases\", and contact support if it still fails.';

  @override
  String get goldPaywallStoreError =>
      'The store reported a problem. Try again in a bit.';

  @override
  String goldPaywallAlreadyGold(String plan) {
    String _temp0 = intl.Intl.selectLogic(plan, {
      'monthly': 'You have Gold: Monthly',
      'yearly': 'You have Gold: Yearly',
      'lifetime': 'You have Gold: Lifetime',
      'other': 'You have Gold',
    });
    return '$_temp0';
  }

  @override
  String get goldPaywallProtectNote =>
      'After you buy, sign in on this phone to protect your Gold.';

  @override
  String get goldAccountTitle => 'Gold & account';

  @override
  String goldAccountPlan(String plan, String date) {
    String _temp0 = intl.Intl.selectLogic(plan, {
      'monthly': 'Gold · Monthly · renews $date',
      'yearly': 'Gold · Yearly · renews $date',
      'lifetime': 'Gold · Lifetime',
      'other': 'Free plan',
    });
    return '$_temp0';
  }

  @override
  String get goldAccountSeeGold => 'See Gold';

  @override
  String get goldAccountManage => 'Manage subscription';

  @override
  String get goldAccountRestore => 'Restore purchases';

  @override
  String get goldAccountRestoring => 'Looking for your purchases…';

  @override
  String get goldAccountRestoreDone => 'Gold is back ✓';

  @override
  String get goldAccountRestoreNone =>
      'I found no purchases to restore on this account';

  @override
  String get goldAccountEndedTitle => 'Gold has ended';

  @override
  String get goldAccountEndedBody =>
      'All your data is still here, and you can come back to Gold any time.';

  @override
  String get goldAccountOtherPhone => 'Use Gold on another phone (optional)';

  @override
  String get goldAccountGoogle => 'Continue with Google';

  @override
  String get goldAccountApple => 'Continue with Apple';

  @override
  String get goldAccountPrivacy =>
      'We only link your Gold plan. Your money data is never sent.';

  @override
  String get goldAccountSigningIn => 'Signing in…';

  @override
  String get goldAccountSignInCancelled => 'Sign-in was cancelled.';

  @override
  String get goldAccountSignInFailed => 'Sign-in didn\'t finish. Try again.';

  @override
  String get goldAccountSignInAgain => 'Sign in again to continue';

  @override
  String goldAccountSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String goldAccountNextMove(String date) {
    return 'You can move Gold again on $date';
  }

  @override
  String get goldAccountSignOutTitle => 'Sign out?';

  @override
  String goldAccountSignOutBody(String state) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'linked': 'All your data stays on this phone. Gold pauses here until you sign in again with the same account.',
      'other': 'All your data stays on this phone, and Gold keeps working.',
    });
    return '$_temp0';
  }

  @override
  String get goldAccountReplaceTitle =>
      'This phone is linked to another account';

  @override
  String get goldAccountReplaceBody =>
      'Link it to this account instead? Only the Gold plan is linked.';

  @override
  String get goldAccountReplaceConfirm => 'Link to this account';

  @override
  String get goldAccountLostPhone =>
      'Lost or sold your old phone? Contact support and we\'ll help.';

  @override
  String get goldAccountDeleteRow => 'Delete account';

  @override
  String get goldAccountDeleteTitle => 'Delete your account?';

  @override
  String get goldAccountDeleteBody =>
      'We\'ll delete your account and its link to Gold on our side. Your purchases stay with your store account.';

  @override
  String get goldAccountDeleteConfirm => 'Delete account';

  @override
  String get goldAccountDeleted => 'Account deleted';

  @override
  String get goldSeatCooldownTitle => 'You moved Gold recently';

  @override
  String goldSeatCooldownBody(String date) {
    return 'You can move it again on $date, or contact support.';
  }

  @override
  String get goldSeatAttestTitle => 'We couldn\'t verify this phone';

  @override
  String get goldSeatAttestBody =>
      'Try again in a bit. If it still fails, sign in with the account you bought with, or contact support.';

  @override
  String get goldSeatAttestPlayServices =>
      'Update Google Play services from the store and try again.';

  @override
  String get goldSeatAttestUnavailable =>
      'Phone verification isn\'t available right now. Sign in with the account you bought with, or contact support.';

  @override
  String get goldSeatAccountRequiredTitle => 'Sign in first';

  @override
  String get goldSeatAccountRequiredBody =>
      'Sign in with the account you bought with.';

  @override
  String get goldSeatMovedUserTitle => 'Gold moved to another phone';

  @override
  String get goldSeatMovedUserBody =>
      'To use it on this phone, restore your purchases or sign in.';

  @override
  String get goldSeatMovedSupportTitle => 'Support moved Gold to another phone';

  @override
  String get goldSeatMovedSupportBody =>
      'If that isn\'t what you asked for, contact support and give them your support code.';

  @override
  String get goldSeatPausedTitle => 'Gold is paused';

  @override
  String get goldSeatPausedBody =>
      'Sign in to use Gold on this phone. Your place is kept and it won\'t count as a move.';

  @override
  String get goldSeatTamperedTitle => 'Go online so we can check your Gold';

  @override
  String get goldSeatTamperedBody =>
      'The phone\'s clock changed. We\'ll check as soon as you\'re online, and all your data is still here.';

  @override
  String goldSeatHeldElsewhere(String date) {
    return 'Payment went through. Gold is still on your other phone, and you can move it on $date.';
  }

  @override
  String get goldSeatHeldElsewhereAccount =>
      'Payment went through. To bring Gold here, sign in with the account that holds it.';

  @override
  String get goldSeatSupportNoticeTitle =>
      'Support linked your Gold to an account';

  @override
  String get goldSeatSupportNoticeBody =>
      'Support linked your Gold to an account. If that wasn\'t you, contact support.';

  @override
  String get goldSeatSignInLinked =>
      'Your account is linked, but Gold isn\'t on this phone yet.';

  @override
  String get goldSeatRestoreSuggested =>
      'Try \"Restore purchases\" and Gold will come back to this phone.';

  @override
  String get goldSeatRestoreAction => 'Restore purchases';

  @override
  String goldSeatSupportPath(String date) {
    return 'Gold can\'t move to this phone before $date. Contact support and we\'ll help.';
  }

  @override
  String get goldSeatProtectTitle =>
      'Sign in on this phone to protect your Gold';

  @override
  String get goldSeatProtectBody =>
      'Linking can only be done from the phone you bought on. After that you can move Gold to a new phone with your account.';

  @override
  String get goldSeatProtectDone => 'Gold is linked to your account ✓';

  @override
  String goldSeatDeleteWarning(String state, String date) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'cooldown':
          'If you delete everything, Gold counts as moved, and you can\'t bring it back to this phone before $date.',
      'other': 'If you delete everything and bring Gold back, it counts as this month\'s move.',
    });
    return '$_temp0';
  }

  @override
  String get notificationsSettingsTitle => 'Notifications';

  @override
  String get notificationsSettingsBudget => 'Budget alerts';

  @override
  String get notificationsSettingsSpikes => 'Spending spikes';

  @override
  String get notificationsSettingsDues => 'Bills & installments';

  @override
  String notificationsSettingsDueDays(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n days before',
      one: '1 day before',
      zero: 'On the due day',
    );
    return '$_temp0';
  }

  @override
  String get notificationsSettingsDuplicates => 'Duplicate charges';

  @override
  String get notificationsSettingsRenewals => 'Subscription renewals';

  @override
  String get notificationsSettingsBackup => 'Backup problems';

  @override
  String get notificationsSettingsWeekly => 'Weekly summary';

  @override
  String get notificationsSettingsWeeklySub => 'Friday mornings';

  @override
  String get notificationsSettingsQuiet => 'Quiet hours';

  @override
  String notificationsSettingsQuietRange(String start, String end) {
    return 'From $start to $end';
  }

  @override
  String get notificationsSettingsHideAmounts => 'Hide amounts on lock screen';

  @override
  String get notificationsSettingsHideAmountsHint =>
      'Alerts arrive without amounts or merchant names.';

  @override
  String get notificationsSettingsDaysRange =>
      'Choose from the due day up to thirty days before';

  @override
  String get notificationsSettingsQuietSame =>
      'The start and end of quiet hours must differ';

  @override
  String get notificationsSettingsOsOffTitle =>
      'Notifications are off for Zaghlol';

  @override
  String get notificationsSettingsOsOffBody =>
      'Turn them on in your phone\'s settings so they reach you.';

  @override
  String get notificationsAlertBudgetNearTitle =>
      'You\'re near your budget limit';

  @override
  String notificationsAlertBudgetNear(
    String percent,
    String category,
    String left,
  ) {
    return 'You\'ve used $percent of your $category budget, with $left left.';
  }

  @override
  String notificationsAlertBudgetNearHidden(String category) {
    return 'Your $category budget is nearly used up.';
  }

  @override
  String get notificationsAlertBudgetReachedTitle =>
      'You\'ve reached your budget limit';

  @override
  String notificationsAlertBudgetReached(
    String category,
    String spent,
    String budget,
  ) {
    return 'Your $category budget is used up: $spent of $budget.';
  }

  @override
  String notificationsAlertBudgetReachedHidden(String category) {
    return 'Your $category budget is used up.';
  }

  @override
  String get notificationsAlertSpikeTitle =>
      'Spending is higher than usual today';

  @override
  String notificationsAlertSpike(String spent, String delta) {
    return 'You\'ve spent $spent today, $delta more than usual.';
  }

  @override
  String get notificationsAlertSpikeHidden =>
      'Your spending today is higher than usual. Open Zaghlol to take a look.';

  @override
  String get notificationsAlertDueTitle => 'A bill or installment is coming up';

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
      other: '$item is due in $n days: $amount',
      one: '$item is due tomorrow: $amount',
      zero: '$item is due today: $amount',
    );
    return '$_temp0';
  }

  @override
  String get notificationsAlertDueHidden =>
      'You have a bill or installment due soon.';

  @override
  String get notificationsAlertDuplicateTitle =>
      'A charge may have been logged twice';

  @override
  String notificationsAlertDuplicate(String merchant, String amount) {
    return '$merchant: $amount appears twice around the same time. Take a look.';
  }

  @override
  String get notificationsAlertDuplicateHidden =>
      'A transaction may be a duplicate. Open Zaghlol to check.';

  @override
  String get notificationsAlertRenewalTitle =>
      'A subscription is about to renew';

  @override
  String notificationsAlertRenewal(
    String merchant,
    String date,
    String amount,
  ) {
    return '$merchant renews on $date for $amount.';
  }

  @override
  String get notificationsAlertRenewalHidden => 'A subscription renews soon.';

  @override
  String get notificationsAlertBackupTitle => 'Your backup didn\'t work';

  @override
  String get notificationsAlertBackupBody =>
      'Try again from Settings. Your data is still on this phone.';

  @override
  String get notificationsAlertWeeklyTitle => 'Your weekly summary is ready';

  @override
  String notificationsAlertWeekly(String spent, String category) {
    return 'You spent $spent this week, mostly on $category.';
  }

  @override
  String get notificationsAlertWeeklyHidden =>
      'Your weekly summary is ready. Open Zaghlol to see it.';

  @override
  String get privacyMainTitle => 'Privacy & data';

  @override
  String get privacyMainStaysTitle => 'What stays on your phone';

  @override
  String get privacyMainStaysBody =>
      'Your messages, transactions, balances, budgets, assets and rules. All encrypted.';

  @override
  String get privacyMainAppLock => 'App lock';

  @override
  String get privacyMainServerRow => 'What Zaghlol\'s server knows';

  @override
  String get privacyServerTitle => 'What Zaghlol\'s server knows about you';

  @override
  String get privacyServerSummary =>
      'Your money and transactions never leave your phone. The server knows only these things:';

  @override
  String get privacyServerItemId =>
      'A random app ID, not your name or phone number';

  @override
  String get privacyServerItemPurchase =>
      'Your Gold purchase, so we can verify it';

  @override
  String get privacyServerItemSignIn => 'Your sign-in, only if you use it';

  @override
  String get privacyServerItemMerchants =>
      'Merchant names, only if you allow it';

  @override
  String get privacyServerItemVersion =>
      'Phone platform, app version and merchant-list version';

  @override
  String get privacyServerItemAttest =>
      'A proof the phone is genuine (Play Integrity or App Attest) on restore, sometimes on purchase';

  @override
  String get privacyServerItemBankRequest =>
      'A bank-support request, only if you ask: the bank\'s name, country and alert type';

  @override
  String get privacyServerSeatKeysSummary =>
      'iPhone only: Zaghlol can tell that earlier installs were on the same phone.';

  @override
  String get privacyServerSeatKeys =>
      'On iPhone, restoring or signing in sends a key proof from this install and up to four earlier ones, so the server can tell they were on the same phone. The server keeps only a scrambled form and never logs the keys.';

  @override
  String get privacyServerDeleteKeepsSummary =>
      'If you delete everything on iPhone, Gold can come back to it without using a move.';

  @override
  String get privacyServerDeleteKeeps =>
      '\"Delete everything\" on iPhone keeps the identity keys on the phone, so Gold can return without counting as a move. The server keeps a keyed hash of the key with the purchase until the purchase is deleted. Erasing the iPhone removes them.';

  @override
  String get privacyServerTimeNonceSummary =>
      'A random number the server uses to check the time. It says nothing about you.';

  @override
  String get privacyServerTimeNonce =>
      'Some requests carry a random one-time number used to check the time. It contains nothing about the phone or the user, and it isn\'t stored.';

  @override
  String get privacyServerSupportNoticeSummary =>
      'If support links your Gold to an account, the phone you bought it on is told.';

  @override
  String get privacyServerSupportNotice =>
      'If support links Gold to an account, the phone that bought it is told when it next connects. The server repeats the notice until that phone\'s next sync confirms it, so a lost response doesn\'t lose it.';

  @override
  String get privacyServerSupportRowsSummary =>
      'When you delete your account we delete everything, and support traces go after a year.';

  @override
  String get privacyServerSupportRows =>
      'When an account is deleted its data is removed from the server, except support audit rows that hold an encrypted e-mail fingerprint and the account ID. They are deleted automatically one year after creation.';

  @override
  String get privacyContributeLabel => 'Help improve the merchant list';

  @override
  String get privacyContributeSentence =>
      'If you turn it on, we send only the merchant name and the category you chose.';

  @override
  String get privacyContributeInfoTitle => 'What exactly is sent?';

  @override
  String get privacyContributeSends =>
      'We send: the cleaned-up merchant name, the bank code and the category you chose.';

  @override
  String get privacyContributeNeverSends =>
      'We never send: amounts, dates, card numbers, phone numbers, InstaPay addresses or people\'s names.';

  @override
  String get privacyContributeFilters =>
      'We skip anything that looks like a person\'s name, and your own custom categories are never sent.';

  @override
  String get privacyContributeOffHint => 'You can turn it off any time.';

  @override
  String get privacyContributeTurnedOn =>
      'Thanks. We\'ll send only the merchant name and category.';

  @override
  String privacyRootedRow(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'This iPhone is jailbroken, so your data is less protected.',
      'other': 'This phone is rooted, so your data is less protected.',
    });
    return '$_temp0';
  }

  @override
  String get privacyRootedTitle => 'What does weaker protection mean?';

  @override
  String get privacyRootedBody =>
      'On a modified phone, another app may reach Zaghlol\'s files more easily. Your data is still encrypted, but protection isn\'t complete.';

  @override
  String get privacyDeleteRow => 'Delete everything';

  @override
  String get privacyDeleteTitle => 'Delete everything from this phone?';

  @override
  String get privacyDeleteBody =>
      'We\'ll delete all your transactions, settings and security keys from this phone. There\'s no undo.';

  @override
  String privacyDeleteLastBackup(String date) {
    return 'Last backup: $date';
  }

  @override
  String get privacyDeleteNoBackup =>
      'You have no backup. What you delete can\'t come back.';

  @override
  String get privacyDeleteIosKeys =>
      'On iPhone, the phone\'s identity keys stay so Gold can return without a move. They hold no financial data. Erasing the iPhone removes them.';

  @override
  String get privacyDeleteIosServer =>
      'The server keeps a scrambled form of the key with the purchase until the purchase is deleted.';

  @override
  String get privacyDeleteTypePrompt =>
      'Type \"DELETE\" (or «احذف») to confirm';

  @override
  String get privacyDeleteTypeLabel => 'Confirmation word';

  @override
  String get privacyDeleteTypeMismatch => 'The word doesn\'t match';

  @override
  String get privacyDeleteConfirm => 'Delete everything';

  @override
  String get privacyDeleteWorking => 'Deleting…';

  @override
  String get privacyDeleteServerCopy =>
      'The copy on the server will expire on its own.';

  @override
  String get widgetOpenZaghlol => 'Open Zaghlol';

  @override
  String get privacyDeleteBackupsKept =>
      'Your backups on Google Drive or iCloud stay there. Delete them from there if you want.';

  @override
  String get privacyDeleteFailed =>
      'Couldn\'t delete everything. Open the app again and we\'ll finish.';

  @override
  String get settingsPrefsTitle => 'Preferences';

  @override
  String get settingsPrefsLanguage => 'Language';

  @override
  String get settingsPrefsLanguageAr => 'العربية';

  @override
  String get settingsPrefsLanguageEn => 'English';

  @override
  String get settingsPrefsDigits => 'Digits';

  @override
  String get settingsPrefsDigitsArabic => 'Arabic-Indic';

  @override
  String get settingsPrefsDigitsWestern => 'Western';

  @override
  String get settingsPrefsTheme => 'Theme';

  @override
  String get settingsPrefsThemeSystem => 'System';

  @override
  String get settingsPrefsThemeLight => 'Light';

  @override
  String get settingsPrefsThemeDark => 'Dark';

  @override
  String get settingsPrefsCurrency => 'Primary currency';

  @override
  String get settingsPrefsApprox => 'Show an approximate total (≈)';

  @override
  String get settingsPrefsApproxHint =>
      'Calculated at an approximate rate and labelled as such. Nothing is actually converted.';

  @override
  String get settingsPrefsCombineInto => 'Combine into';

  @override
  String get settingsPrefsPayday => 'Payday';

  @override
  String settingsPrefsPaydayDay(String day) {
    return 'Day $day';
  }

  @override
  String get settingsPrefsPaydayMonth => 'Month start';

  @override
  String get settingsPrefsPaydayRange =>
      'Choose a day from the 1st up to the 28th';

  @override
  String get settingsPrefsPaydayChangeTitle => 'Change payday mid-cycle?';

  @override
  String get settingsPrefsPaydayChangeBody =>
      'Your current cycle will end early and a new one starts from the new payday.';

  @override
  String get settingsPrefsIncome => 'Monthly income target';

  @override
  String get settingsPrefsIncomeOptional => 'Optional';

  @override
  String get settingsPrefsIncomeNegative => 'The amount can\'t be negative';

  @override
  String get settingsPrefsAppLock => 'App lock';

  @override
  String get settingsPrefsLockAfter => 'Lock after';

  @override
  String get settingsPrefsLockImmediately => 'Immediately';

  @override
  String settingsPrefsLockAfterMinutes(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String settingsPrefsBiometricsUnavailable(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'ios': 'Biometrics aren\'t available. We\'ll use your passcode instead.',
      'other':
          'Biometrics aren\'t available. We\'ll use your phone lock instead.',
    });
    return '$_temp0';
  }

  @override
  String get shareStudioTitle => 'Share your win';

  @override
  String get shareStudioCloseA11y => 'Close';

  @override
  String get shareStudioTemplateSavings => 'Savings';

  @override
  String get shareStudioTemplateDelivery => 'Delivery cut';

  @override
  String get shareStudioTemplateBudget => 'Under budget';

  @override
  String get shareStudioShowAmounts => 'Show amounts';

  @override
  String get shareStudioShowAmountsHint =>
      'While it\'s off, only percentages show.';

  @override
  String get shareStudioCertificate =>
      'A certificate of thanks from Captain Zaghlol';

  @override
  String shareStudioCardSavings(String percent) {
    return 'I saved $percent of my salary this month!';
  }

  @override
  String shareStudioCardSavingsAmount(String amount) {
    return 'I saved $amount this month!';
  }

  @override
  String shareStudioCardDelivery(String percent) {
    return 'I cut my delivery spending by $percent this month!';
  }

  @override
  String shareStudioCardDeliveryAmount(String amount) {
    return 'I cut $amount from my delivery spending this month!';
  }

  @override
  String shareStudioCardBudget(String percent) {
    return 'I finished the cycle $percent under budget!';
  }

  @override
  String shareStudioCardBudgetAmount(String amount) {
    return 'I finished the cycle $amount under budget!';
  }

  @override
  String get shareStudioHashtag => '#ZaghlolOnBudget';

  @override
  String get shareStudioShare => 'Share';

  @override
  String shareStudioPreviewA11y(String text) {
    return 'Card preview: $text';
  }

  @override
  String get shareStudioUnencrypted =>
      'The image isn\'t encrypted, and once shared it\'s outside Zaghlol.';

  @override
  String get shareStudioEmptyTitle => 'Nothing to share yet';

  @override
  String get shareStudioEmptyBody =>
      'Keep logging and your wins will show up here.';

  @override
  String get shareStudioRendering => 'Preparing the card…';

  @override
  String get shareStudioRenderFailed =>
      'Couldn\'t prepare the image. Try again.';

  @override
  String get aboutMainTitle => 'About Zaghlol';

  @override
  String aboutMainVersion(String appVersion, String build) {
    return 'Version $appVersion (build $build)';
  }

  @override
  String aboutMainCatalog(String date) {
    return 'Merchant list updated $date';
  }

  @override
  String aboutMainPrices(String date) {
    return 'Prices updated $date';
  }

  @override
  String get aboutMainNeverSynced => 'Not updated yet (works offline)';

  @override
  String get aboutMainTerms => 'Terms of use';

  @override
  String get aboutMainPrivacy => 'Privacy policy';

  @override
  String get aboutMainLicenses => 'Open-source licences';

  @override
  String get aboutMainDisclaimers => 'Important notices';

  @override
  String get aboutMainSupport => 'Contact support';

  @override
  String get aboutMainSupportSubject => 'Help with Zaghlol';

  @override
  String get aboutDiagTitle => 'Diagnostics';

  @override
  String get aboutDiagBody =>
      'A file with error codes only, with no messages, amounts or names. Send it to support if you need to.';

  @override
  String get aboutDiagShare => 'Share the file';

  @override
  String get aboutDiagEmpty => 'No errors logged.';

  @override
  String get legalTermsSummary =>
      'Terms in short: you use Zaghlol to manage your own money, and your financial decisions are yours.';

  @override
  String get legalTermsOpen => 'Read the full terms';

  @override
  String get legalPrivacySummary =>
      'Privacy in short: your money data stays on your phone, and the server knows only what\'s listed in \"Privacy & data\".';

  @override
  String get legalPrivacyOpen => 'Read the full policy';

  @override
  String get legalLicensesSummary =>
      'Zaghlol uses open-source software, and these are each one\'s licence.';

  @override
  String get legalLicensesTitle => 'Open-source licences';

  @override
  String get legalDisclaimerTitle => 'Important notices';

  @override
  String get legalDisclaimerCoachingSummary =>
      'Zaghlol\'s tips are general ideas, not financial advice.';

  @override
  String get legalDisclaimerCoaching =>
      'Captain Zaghlol\'s guidance, chart explanations and suggestions are general ideas for awareness, not financial, investment or legal advice. The final decision is yours.';

  @override
  String get legalDisclaimerEstimatesSummary =>
      'The numbers are approximate. Your bank statement is the reference.';

  @override
  String get legalDisclaimerEstimates =>
      'The figures shown are estimates based on the messages the app reads and what you enter yourself. They may differ from your official statements.';

  @override
  String get legalDisclaimerPricesSummary =>
      'Gold and currency prices are indicative and may lag the market.';

  @override
  String get legalDisclaimerPrices =>
      'Gold and currency prices shown are indicative only and may lag or differ from the market price at the time of a deal.';

  @override
  String get legalDisclaimerZakahRef =>
      'The Zakah figure is an estimate, not a ruling. Details are on the Zakah screen.';

  @override
  String get legalDisclaimerRoiRef =>
      'Investment tips are general ideas, not financial advice. Details are on the tips screen.';

  @override
  String get legalDisclaimerFooter =>
      'Zaghlol gives general ideas, not financial advice.';

  @override
  String get errorsGenericUnexpectedTitle => 'A small problem came up';

  @override
  String get errorsGenericUnexpectedBody =>
      'It\'s not your fault, and your data is safe on this phone. Go home and try again.';

  @override
  String get errorsGenericGoHome => 'Go home';

  @override
  String get errorsGenericActionFailed =>
      'That didn\'t go through. Try again in a bit.';

  @override
  String get errorsNetworkOffline =>
      'You\'re offline. What you see is saved on your phone.';

  @override
  String get errorsNetworkTimeout => 'The connection took too long. Try again.';

  @override
  String get errorsNetworkServer =>
      'The server is busy right now. We\'ll retry on our own.';

  @override
  String get errorsNetworkRateLimited =>
      'That\'s a lot of requests. Wait a moment and try again.';

  @override
  String get errorsStorageOpenTitle => 'We couldn\'t open your data';

  @override
  String get errorsStorageOpenBody =>
      'You can restore from a backup or start fresh. The old file stays until you choose.';

  @override
  String get errorsStorageRestore => 'Restore a backup';

  @override
  String get errorsStorageStartFreshWarn =>
      'We\'ll delete the old file that won\'t open. There\'s no undo.';

  @override
  String get errorsStorageFull =>
      'Your phone is out of space. Free some up and try again. Messages that arrived are kept.';

  @override
  String get errorsStorageMigrationTitle => 'The update didn\'t finish';

  @override
  String get errorsStorageMigrationBody =>
      'We put your data back as it was. Try again.';

  @override
  String get errorsStorageIo =>
      'There was a problem reading or saving a file. Try again.';

  @override
  String get errorsCapturePermission =>
      'That permission is off. Turn it on in your phone\'s settings.';

  @override
  String get errorsCaptureUnavailable => 'That isn\'t available on this phone.';

  @override
  String get errorsCaptureSpool =>
      'Some messages couldn\'t be read. Re-scan your old messages.';

  @override
  String get errorsCaptureKeyChanged =>
      'Phone protection was renewed after a lock change, so waiting messages may be lost. Re-scan your old messages.';

  @override
  String get errorsCaptureConfig =>
      'I\'m fixing the capture settings myself. Nothing needed from you.';

  @override
  String get errorsCaptureOcr =>
      'I couldn\'t read the image. Try a clearer one or type the transaction.';

  @override
  String get errorsMoneyCurrency =>
      'The currencies differ, so they can\'t be combined.';

  @override
  String get errorsMoneyOffset =>
      'The amount back is larger than the transaction.';

  @override
  String get errorsAccountTokenExpired => 'Sign in again to continue.';

  @override
  String get errorsAccountFailed =>
      'That didn\'t go through. Try again in a bit.';

  @override
  String accountsOverviewApproxNotIncluded(String currencies) {
    return 'Not included in the ≈ total: $currencies';
  }

  @override
  String get accountsOverviewApproxLabel => 'Approximate';

  @override
  String get goldSeatTamperedClockBody =>
      'Set your phone\'s date and time to automatic, then open Zaghlol again.';

  @override
  String get transactionsEditLinksRemoved =>
      'The amount changed, so the money-back and split links on this transaction were removed.';

  @override
  String get goldAccountSignedIn => 'Signed in';

  @override
  String insightsChartsPeakHour(String time) {
    return 'Your busiest hour is around $time';
  }

  @override
  String get homeFeedExcludedFromSpending => 'Excluded from spending';

  @override
  String get notificationsAlertBackupReminderTitle => 'Time for a backup';

  @override
  String get notificationsAlertBackupReminderBody =>
      'Back up from Settings to keep your data safe.';

  @override
  String transactionsReimbUnassigned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count reimbursements were unassigned because the expense got smaller',
      one: '1 reimbursement was unassigned because the expense got smaller',
    );
    return '$_temp0';
  }
}
