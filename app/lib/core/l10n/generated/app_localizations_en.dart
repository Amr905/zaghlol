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
}
