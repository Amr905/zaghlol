// T-231: findings of the explorer that are expected, each keyed by screen AND
// control (see ExplorerAllow). Titles are matched in Arabic and English.
// Everything else the explorer reports stays an issue.

import 'explorer.dart';

RegExp _r(String s) => RegExp(s);

const _pickerReason =
    'a choice closes or changes this sheet or screen, so the control that '
    'opened it is gone (by design)';

final RegExp _emoji = _r('^[^A-Za-z؀-ۿ0-9\\s]{1,6}\$');

/// Exact titles (Arabic and English) of the pickers and sheets that close on
/// a choice, as the explorer reports them.
final List<String> _restoreTitles = [
  '^العملة الأساسية\$|^Primary currency\$',
  '^يوم القبض\$|^Payday\$',
  '^تغيّر يوم القبض في نص الدورة؟\$|^Change payday mid-cycle\\?\$',
  '^يوم الميعاد نفسه\$',
  '^المدة\$|^Dates\$',
  '^التصنيف\$|^Category\$',
  '^الحساب\$|^Account\$',
  '^العملة\$|^Currency\$',
  '^عدّل الحركة\$|^Edit transaction\$',
  '^تمسح الحركة دي؟\$|^Delete this transaction\\?\$',
  '^تحب تسجل إيه؟\$|^What do you want to log\\?\$',
  '^نستخدم التعرف على الصوت أونلاين؟\$|^Use online speech recognition\\?\$',
];

final List<ExplorerAllow> explorerAllow = [
  // Cards filter: "All cards" and its checkbox are already on.
  ExplorerAllow(
    screen: _r('تشوف أنهي كروت|Show which cards'),
    kind: 'dead-tap',
    where: _r('كل الكروت|All cards|Checkbox'),
    reason: 'every card is already selected, so tapping "All cards" is a no-op',
  ),
  // The time picker: the hour and minute digits only move focus.
  ExplorerAllow(
    screen: _r('اختيار الوقت|Select time'),
    kind: 'dead-tap',
    where: _r('^inkwell "[0-9٠-٩]+"\$'),
    reason: 'a digit of the system time picker (the dial is the control)',
  ),
  // Capture settings: "Fix" opens the system settings.
  ExplorerAllow(
    screen: _r('زغلول بيقرا منين|^Capture\$'),
    kind: 'left-app',
    where: _r('صلّحها|Fix'),
    reason: 'opens the Android system settings (leaves the app on purpose)',
  ),
  ExplorerAllow(
    screen: _r('زغلول بيقرا منين|^Capture\$'),
    kind: 'dead-tap',
    where: _r('صلّحها|Fix'),
    reason: 'opens the Android system settings (leaves the app on purpose)',
  ),
  // Re-scan sheet: radio rows.
  ExplorerAllow(
    screen: _r('دوّر في الرسايل القديمة|Re-scan old messages'),
    kind: 'dead-tap',
    where: _r('آخر ٦ شهور|Last 6 months|Radio.*GestureDetector'),
    reason:
        '"6 months" is already selected; the radio\'s own gesture area '
        'repeats the row tap',
  ),
  // Restore: no Google account on the emulator.
  ExplorerAllow(
    screen: _r('استرجاع نسخة|Restore from backup|Restore a backup'),
    kind: 'dead-tap',
    where: _r('Google Drive|Radio.*GestureDetector'),
    reason: 'Google Drive is already the selected provider (radio)',
  ),
  ExplorerAllow(
    screen: _r('استرجاع نسخة|Restore from backup|Restore a backup'),
    kind: 'dead-tap',
    where: _r('جرّب تاني|Try again'),
    reason:
        'the emulator has no signed-in Google account, so the sign-in error '
        'banner (which says why) comes back unchanged',
  ),
  // Note sheet: the text field's selection toolbar handle.
  ExplorerAllow(
    screen: _r('^ملاحظة\$|^Note\$'),
    kind: 'dead-tap',
    where: _r('TextField.*GestureDetector|EditableText'),
    reason: 'the text field\'s selection handle / toolbar (system widget)',
  ),
  // Scan: the system image picker.
  ExplorerAllow(
    screen: _r('اقرا سكرين شوت|Scan a screenshot'),
    kind: 'left-app',
    where: _r('اختار صورة|Choose an image'),
    reason: 'opens the system image picker (leaves the app on purpose)',
  ),
  ExplorerAllow(
    screen: _r('اقرا سكرين شوت|Scan a screenshot'),
    kind: 'dead-tap',
    where: _r('اختار صورة|Choose an image'),
    reason: 'opens the system image picker (leaves the app on purpose)',
  ),
  // Link my own transfer: the first candidate starts selected.
  ExplorerAllow(
    screen: _r('ربط تحويلة لنفسي|Link my own transfer'),
    kind: 'dead-tap',
    where: _r('^(checkbox|radio|inkwell|listtile)\\b|Radio|Checkbox|ListTile'),
    reason:
        'the first candidate is preselected (the sheet keeps `_picked` null '
        'until a tap), so tapping it again changes nothing',
  ),
  // Text fields: a tap focuses them, no text changes. The explorer calls the
  // field's gesture area "GestureDetector". Inferred from the control type.
  ExplorerAllow(
    screen: _r('^رصيد |^Balance of |^مصروف جديد|^New expense|^Add expense'),
    kind: 'dead-tap',
    where: _r('TextField.*GestureDetector|EditableText'),
    reason: 'a text field: the tap focuses it (no text change to see)',
  ),
  // Pickers and sheets that close or change on a choice. The explorer reports
  // the "restore" issue with the screen's own title as the control, so each
  // entry pins one exact title as both screen and control.
  ..._restoreTitles.map(
    (t) => ExplorerAllow(
      screen: _r(t),
      kind: 'restore',
      where: _r(t),
      reason: _pickerReason,
    ),
  ),
  // Saving closes the editor (tested); the hide switch flips and shows a
  // snackbar (tested). Only the controls the explorer reported, per screen.
  ExplorerAllow(
    screen: _r('^عدّل الفاتورة\$|^Edit bill\$'),
    kind: 'dead-tap',
    where: _r('^(inkwell|button) "(احفظ|Save)"\$'),
    reason: 'Save closes the editor (tested)',
  ),
  ExplorerAllow(
    screen: _r('^تفاصيل الكارت\$|^Card details\$'),
    kind: 'dead-tap',
    where: _r(
      '^(button "(احفظ|Save)"|switch "Switch"|'
      'listtile "(اخفي الحساب ده|Hide this account) / [^"]*")\$',
    ),
    reason:
        'Save closes the editor (tested); the hide switch flips and shows a '
        'snackbar (tested)',
  ),
  // A transaction's detail screen is titled with its category emoji; changing
  // the category changes the title. Screen and control are both the emoji.
  ExplorerAllow(
    screen: _emoji,
    kind: 'restore',
    where: _emoji,
    reason:
        'the detail screen is titled by its category emoji, which a '
        'category change replaces',
  ),
];
