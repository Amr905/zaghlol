@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_row.dart';

import 'list_harness.dart';

// T-079 goldens: S-11 in ar/en, light/dark. PNGs are generated on demand
// (`flutter test --update-goldens --tags golden`) and not committed.
void main() {
  setUpAll(initDateFormatting);
  for (final locale in [const Locale('ar', 'EG'), const Locale('en')]) {
    for (final dark in [false, true]) {
      final name = '${locale.languageCode}_${dark ? 'dark' : 'light'}';
      Harness data() => Harness(
        FakeRepo([
          txnRec('a', merchant: 'Carrefour', minor: 45000),
          txnRec('b', merchant: 'Talabat', minor: 28500),
          txnRec(
            'c',
            merchant: 'Salary',
            minor: 900000,
            daysAgo: 1,
            direction: TxnDirection.income,
          ),
        ]),
      );
      testWidgets('list $name', (tester) async {
        await pumpList(tester, data(), locale: locale, dark: dark);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/transactions_list_$name.png'),
        );
      });
      testWidgets('selection $name', (tester) async {
        await pumpList(tester, data(), locale: locale, dark: dark);
        await tester.longPress(find.byType(TxnRow).first);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/transactions_selection_$name.png'),
        );
      });
    }
  }
}
