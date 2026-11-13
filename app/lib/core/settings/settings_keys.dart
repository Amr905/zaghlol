// T-020: every setting with its default (FR-ONB-07, FR-BAK-06; A-10, A-11,
// A-26, A-27, A-29, A-43, A-54). Names are the `settings.key` values, so they
// are part of the backup format: never rename one.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'setting_key.dart';

/// FR-ONB-03: until chosen, the device language.
enum LanguagePref { system, ar, en }

/// A-29: `auto` shows Arabic-Indic digits in Arabic and Western in English.
enum DigitsPref { auto, arabicIndic, western }

enum ThemePref { system, light, dark }

/// T-152 (FR-BAK-02): how often Gold backs up by itself.
enum BackupScheduleMode { off, daily, weekly, monthly }

/// T-152: where backups go. `none` until the user picks one.
enum BackupDestinationPref { none, drive, icloud }

/// The settings. Defaults are the SRS assumptions named beside them.
abstract final class Settings {
  static final language = SettingKey.enumeration(
    'language',
    LanguagePref.values,
    byDefault: LanguagePref.system,
  );
  static final digits = SettingKey.enumeration(
    'digits',
    DigitsPref.values,
    byDefault: DigitsPref.auto,
  );
  static final theme = SettingKey.enumeration(
    'theme',
    ThemePref.values,
    byDefault: ThemePref.system,
  );

  /// BR-BUD-01: 1–28; day 1 (calendar month) until set (A-43).
  static final paydayDay = SettingKey.integer(
    'payday_day',
    byDefault: 1,
    min: 1,
    max: 28,
  );

  /// The payday eras (EC-21, T-051): `payday_day` stays the user-facing value
  /// and equals the last era's day. Written first by `setPayday`.
  static final paydayEras = SettingKey.paydaySchedule('payday_eras');

  /// Optional (FR-ONB-03); unset is null.
  static final incomeTarget = SettingKey.optionalMoney('income_target');

  static final primaryCurrency = SettingKey.currency(
    'primary_currency',
    byDefault: Currency.of('EGP'),
  );

  /// The "≈" view: off by default (A-54).
  static final approxViewEnabled = SettingKey.boolean(
    'approx_view.enabled',
    byDefault: false,
  );
  static final approxViewTarget = SettingKey.currency(
    'approx_view.target',
    byDefault: Currency.of('EGP'),
  );

  // FR-NTF-01: every type can be switched off; all on by default.
  static final notifBudgetThreshold = SettingKey.boolean(
    'notif.budget_threshold',
    byDefault: true,
  );
  static final notifSpendingSpike = SettingKey.boolean(
    'notif.spending_spike',
    byDefault: true,
  );
  static final notifUpcomingDue = SettingKey.boolean(
    'notif.upcoming_due',
    byDefault: true,
  );
  static final notifDuplicateCharge = SettingKey.boolean(
    'notif.duplicate_charge',
    byDefault: true,
  );
  static final notifSubscriptionRenewal = SettingKey.boolean(
    'notif.subscription_renewal',
    byDefault: true,
  );
  static final notifBackupFailure = SettingKey.boolean(
    'notif.backup_failure',
    byDefault: true,
  );
  static final notifWeeklySummary = SettingKey.boolean(
    'notif.weekly_summary',
    byDefault: true,
  );

  // FR-NTF-02, A-27: 23:00–08:00, as minutes after local midnight.
  static final quietHoursEnabled = SettingKey.boolean(
    'quiet_hours.enabled',
    byDefault: true,
  );
  static final quietHoursStartMin = SettingKey.integer(
    'quiet_hours.start_min',
    byDefault: 23 * 60,
    min: 0,
    max: 1439,
  );
  static final quietHoursEndMin = SettingKey.integer(
    'quiet_hours.end_min',
    byDefault: 8 * 60,
    min: 0,
    max: 1439,
  );

  /// Off until the user turns it on (FR-ONB-04).
  static final appLockEnabled = SettingKey.boolean(
    'app_lock.enabled',
    byDefault: false,
  );

  /// A-10: re-prompt after 1 minute in the background (0: at once).
  static final appLockTimeoutS = SettingKey.integer(
    'app_lock.timeout_s',
    byDefault: 60,
    min: 0,
    max: 3600,
  );

  // Hide-amounts choices (FR-NTF-03, FR-WID-01; A-26: share cards hide).
  static final hideAmountsNotifications = SettingKey.boolean(
    'hide_amounts.notifications',
    byDefault: false,
  );
  static final hideAmountsWidget = SettingKey.boolean(
    'hide_amounts.widget',
    byDefault: false,
  );
  static final hideAmountsShareCards = SettingKey.boolean(
    'hide_amounts.share_cards',
    byDefault: true,
  );

  // Capture sources (FR-ONB-07): all on until the user turns one off.
  static final captureSms = SettingKey.boolean('capture.sms', byDefault: true);
  static final captureNotifications = SettingKey.boolean(
    'capture.notifications',
    byDefault: true,
  );

  /// Opt-in (D-13): off by default.
  static final contributionOptIn = SettingKey.boolean(
    'contribution_opt_in',
    byDefault: false,
  );

  /// A-11: 6 months, up to 24.
  static final scanDepthMonths = SettingKey.integer(
    'scan_depth_months',
    byDefault: 6,
    min: 1,
    max: 24,
  );

  /// T-048 (FU-109 M-1, PO): opt-in "scan the last 3 months" for phone-number
  /// senders the user added. Off by default; those senders are otherwise
  /// live capture only.
  static final scanPersonalSenders = SettingKey.boolean(
    'capture.scan_personal_senders',
    byDefault: false,
  );

  /// FR-ONB-11: the setup steps (slugs) the user finished or skipped.
  static final setupProgress = SettingKey.slugSet('setup_progress');

  /// T-097 (FR-ONB-10, D-21): contextual setup suggestions already shown or
  /// dismissed. Each one is offered once and never again.
  static final setupSuggestionsHandled = SettingKey.slugSet(
    'setup_suggestions_handled',
  );

  /// When the paywall was last shown: epoch milliseconds UTC; null: never.
  static final paywallLastShown = SettingKey.optionalInteger(
    'paywall_last_shown',
    min: 0,
    max: 999999999999999,
  );

  // T-152 backup schedule and status (FR-BAK-02/04). Times: epoch ms UTC.
  static final backupSchedule = SettingKey.enumeration(
    'backup.schedule',
    BackupScheduleMode.values,
    byDefault: BackupScheduleMode.off,
  );
  static final backupDestination = SettingKey.enumeration(
    'backup.destination',
    BackupDestinationPref.values,
    byDefault: BackupDestinationPref.none,
  );
  static final backupLastSuccess = SettingKey.optionalInteger(
    'backup.last_success',
    min: 0,
    max: 999999999999999,
  );
  static final backupLastFailure = SettingKey.optionalInteger(
    'backup.last_failure',
    min: 0,
    max: 999999999999999,
  );
  static final backupReminderAt = SettingKey.optionalInteger(
    'backup.reminder_at',
    min: 0,
    max: 999999999999999,
  );
}
