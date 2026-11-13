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
}
