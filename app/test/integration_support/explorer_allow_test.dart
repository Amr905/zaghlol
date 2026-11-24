// T-235: the explorer allow-list is precise: each entry matches only its own
// screen and control, never a neighbouring one.

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/explorer.dart';
import '../../integration_test/support/explorer_allow.dart';

bool _allowed(String title, ExplorerIssue i) =>
    explorerAllow.any((a) => a.matches(title, i));

ExplorerIssue _i(String kind, String where) => ExplorerIssue(kind, where, 'x');

void main() {
  test('every entry pins a control (no catch-all)', () {
    for (final a in explorerAllow) {
      expect(a.where, isNotNull, reason: a.reason);
      expect(a.where!.pattern, isNot('.*'));
    }
  });

  test('restore entries match only the same title', () {
    expect(_allowed('العملة', _i('restore', 'العملة')), isTrue);
    expect(_allowed('Payday', _i('restore', 'Payday')), isTrue);
    // a neighbouring screen or control is not covered
    expect(_allowed('العملة', _i('restore', 'الحساب')), isFalse);
    expect(_allowed('العملة الأساسية', _i('restore', 'العملة')), isFalse);
    expect(_allowed('إعدادات', _i('restore', 'إعدادات')), isFalse);
    expect(_allowed('العملة', _i('dead-tap', 'العملة')), isFalse);
    expect(_allowed('🛒', _i('restore', '🛒')), isTrue);
    expect(_allowed('🛒', _i('restore', 'Save')), isFalse);
    expect(_allowed('Settings', _i('restore', 'Settings')), isFalse);
  });

  test('bill and card entries need the exact screen and control', () {
    expect(_allowed('عدّل الفاتورة', _i('dead-tap', 'inkwell "احفظ"')), isTrue);
    expect(
      _allowed('عدّل الفاتورة', _i('dead-tap', 'inkwell "امسح"')),
      isFalse,
    );
    expect(_allowed('فاتورة جديدة', _i('dead-tap', 'inkwell "احفظ"')), isFalse);
    expect(
      _allowed('تفاصيل الكارت', _i('dead-tap', 'switch "Switch"')),
      isTrue,
    );
    expect(
      _allowed(
        'تفاصيل الكارت',
        _i('dead-tap', 'listtile "اخفي الحساب ده / مش هيظهر"'),
      ),
      isTrue,
    );
    expect(
      _allowed('تفاصيل الكارت', _i('dead-tap', 'listtile "امسح الكارت"')),
      isFalse,
    );
    expect(_allowed('الإعدادات', _i('dead-tap', 'switch "Switch"')), isFalse);
  });
}
