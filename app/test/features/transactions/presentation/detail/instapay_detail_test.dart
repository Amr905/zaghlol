// T-265 / US-P04: the detail header of an InstaPay transaction. Synthetic.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../detail_edit_harness.dart';
import '../list/list_harness.dart';

String _plain(String s) => s.replaceAll(RegExp('[\u2068\u2069]'), '');

Finder _text(String needle) =>
    find.byWidgetPredicate((w) => w is Text && _plain(w.data ?? '') == needle);

void main() {
  setUpAll(initDateFormatting);

  for (final (name, locale) in [
    ('en', const Locale('en')),
    ('ar', const Locale('ar', 'EG')),
  ]) {
    final title = name == 'en' ? 'InstaPay' : 'إنستاباي';
    final to = name == 'en' ? 'To ' : 'إلى ';
    final from = name == 'en' ? 'From ' : 'من ';

    Future<void> pump(WidgetTester tester, TxnDirection d, String? who) async {
      final r = txnRec(
        'a',
        merchant: '',
        categoryId: kInstapayCategoryId,
        direction: d,
        counterpartyKind: 'ipa',
        counterpartyValue: who,
      );
      await pumpDetail(
        tester,
        Harness(FakeRepo([r])),
        detail: AsyncData(detailOf(r)),
        locale: locale,
      );
    }

    group('InstaPay detail ($name)', () {
      testWidgets('out', (tester) async {
        await pump(tester, TxnDirection.transferOut, 'Mona Ali');
        expect(find.text(title), findsOneWidget);
        expect(_text(_j(to, 'Mona Ali')), findsOneWidget);
      });
      testWidgets('in, masked name', (tester) async {
        await pump(tester, TxnDirection.income, 'Omar *** 12');
        expect(_text(_j(from, 'Omar *** 12')), findsOneWidget);
      });
      testWidgets('mixed-script name', (tester) async {
        await pump(tester, TxnDirection.transferOut, 'محمد Hassan');
        expect(_text(_j(to, 'محمد Hassan')), findsOneWidget);
      });
      testWidgets('no name: title only', (tester) async {
        await pump(tester, TxnDirection.transferOut, null);
        expect(find.text(title), findsOneWidget);
        expect(_text(_j(to, 'Mona Ali')), findsNothing);
      });
    });
  }
}

String _j(String a, String b) => '$a$b';
