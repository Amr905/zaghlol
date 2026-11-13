@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';

import 'detail_edit_harness.dart';
import 'list/list_harness.dart';

// T-080 goldens: S-12 and S-13 in ar/en, light/dark. PNGs are generated on
// demand (`flutter test --update-goldens --tags golden`) and not committed.
void main() {
  setUpAll(initDateFormatting);
  for (final locale in [const Locale('ar', 'EG'), const Locale('en')]) {
    for (final dark in [false, true]) {
      final name = '${locale.languageCode}_${dark ? 'dark' : 'light'}';
      testWidgets('detail $name', (tester) async {
        await pumpDetail(
          tester,
          Harness(FakeRepo([txnRec('a')])),
          detail: AsyncData(
            detailOf(txnRec('a'), raw: 'SYNTHETIC BANK: purchase 450.00 EGP'),
          ),
          locale: locale,
          dark: dark,
        );
        await expectLater(
          find.byType(Scaffold).last,
          matchesGoldenFile('goldens/transaction_detail_$name.png'),
        );
      });
      testWidgets('edit $name', (tester) async {
        await pumpEditor(
          tester,
          FakeEditor(),
          existing: txnRec('a'),
          locale: locale,
          dark: dark,
        );
        await expectLater(
          find.byType(Scaffold).last,
          matchesGoldenFile('goldens/transaction_edit_$name.png'),
        );
      });
    }
  }
}
