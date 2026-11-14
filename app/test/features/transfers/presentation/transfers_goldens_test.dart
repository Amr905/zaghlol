@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transfers/presentation/assign_sheet.dart';
import 'package:zaghlol/features/transfers/presentation/link_transfer_sheet.dart';
import 'package:zaghlol/features/transfers/presentation/split_sheet.dart';

import 'transfers_harness.dart';

// T-093 goldens: S-15 (both modes) and S-16 in ar/en, light/dark. PNGs are
// generated on demand (`flutter test --update-goldens --tags golden`).
void main() {
  setUpAll(initDateFormatting);
  for (final locale in [const Locale('ar', 'EG'), const Locale('en')]) {
    for (final dark in [false, true]) {
      final n = '${locale.languageCode}_${dark ? 'dark' : 'light'}';
      Future<void> shot(
        WidgetTester t,
        FakePort port,
        Future<Object?> Function(BuildContext) open,
        String name,
      ) async {
        await pumpSheet(t, port: port, open: open, locale: locale, dark: dark);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_$n.png'),
        );
      }

      testWidgets('split $n', (t) async {
        await shot(
          t,
          FakePort(split: sampleSplit()),
          (c) => showSplitSheet(c, 'x1'),
          'split',
        );
      });
      testWidgets('assign $n', (t) async {
        await shot(
          t,
          FakePort(assignData: sampleAssign()),
          (c) => showAssignSheet(c, 'in1'),
          'assign',
        );
      });
      testWidgets('link $n', (t) async {
        await shot(
          t,
          FakePort(linkData: sampleLink()),
          (c) => showLinkTransferSheet(c, 'out1'),
          'link',
        );
      });
    }
  }
}
