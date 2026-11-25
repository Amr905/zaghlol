// T-265 / US-P04: InstaPay rows show "InstaPay" then the counterparty name.
// All data synthetic.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/list/transactions_list_screen.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_row.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'list_harness.dart';

const _ar = Locale('ar', 'EG');

/// Strips the bidi isolates the row adds around the name.
String _plain(String s) => s.replaceAll(RegExp('[\u2068\u2069]'), '');

bool _hasText(String needle) => find
    .byWidgetPredicate(
      (w) =>
          w is Text && _plain(w.data ?? '').contains(needle) ||
          w is RichText && _plain(w.text.toPlainText()).contains(needle),
    )
    .evaluate()
    .isNotEmpty;

Harness _rows() => Harness(
  FakeRepo([
    txnRec(
      'out',
      merchant: '',
      categoryId: kInstapayCategoryId,
      direction: TxnDirection.transferOut,
      counterpartyKind: 'ipa',
      counterpartyValue: 'Mona Ali',
    ),
    txnRec(
      'in',
      merchant: '',
      categoryId: kInstapayCategoryId,
      direction: TxnDirection.income,
      counterpartyKind: 'ipa',
      counterpartyValue: 'Omar *** 12',
    ),
    txnRec(
      'noname',
      merchant: '',
      categoryId: kInstapayCategoryId,
      direction: TxnDirection.transferOut,
      counterpartyKind: 'ipa',
    ),
    txnRec(
      'mixed',
      merchant: '',
      categoryId: 'food',
      direction: TxnDirection.transferOut,
      counterpartyKind: 'ipa',
      counterpartyValue: 'محمد Hassan',
    ),
    txnRec('shop', merchant: 'Carrefour'),
  ]),
);

void main() {
  setUpAll(initDateFormatting);

  for (final (name, locale) in [('en', const Locale('en')), ('ar', _ar)]) {
    final title = name == 'en' ? 'InstaPay' : 'إنستاباي';
    final to = name == 'en' ? 'To ' : 'إلى ';
    final from = name == 'en' ? 'From ' : 'من ';
    group('InstaPay rows ($name)', () {
      testWidgets('out, in, no name, mixed-script name', (tester) async {
        await pumpList(tester, _rows(), locale: locale);
        expect(tester.takeException(), isNull);
        expect(find.text(title), findsNWidgets(4));
        expect(_hasText(_j(to, 'Mona Ali')), isTrue);
        expect(_hasText(_j(from, 'Omar *** 12')), isTrue);
        expect(_hasText(_j(to, 'محمد Hassan')), isTrue);
        // The category the user kept still wins over the InstaPay marker.
        expect(find.text('Carrefour'), findsOneWidget);
      });

      testWidgets('search finds a row by counterparty name', (tester) async {
        final h = _rows();
        await pumpList(tester, h, locale: locale);
        await tester.enterText(find.byType(TextField), 'Mona');
        await tester.pump(txnSearchDebounce);
        await tester.pumpAndSettle();
        expect(find.byType(TxnRow), findsOneWidget);
        expect(_hasText(_j(to, 'Mona Ali')), isTrue);
      });

      testWidgets('a user-renamed merchant keeps its own title', (
        tester,
      ) async {
        final h = Harness(
          FakeRepo([
            txnRec(
              'r',
              merchant: 'Rent',
              categoryId: kInstapayCategoryId,
              direction: TxnDirection.transferOut,
              counterpartyKind: 'ipa',
              counterpartyValue: 'Mona Ali',
            ),
          ]),
        );
        await pumpList(tester, h, locale: locale);
        expect(find.text('Rent'), findsOneWidget);
        expect(find.text(title), findsNothing);
      });
    });
  }
}

String _j(String a, String b) => '$a$b';
