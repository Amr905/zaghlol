// T-247 (D-82): chart bars that are payday cycles are named after the month
// the cycle belongs to (a cycle starting on day 21 or later is the next
// month's); bars of whole calendar months keep their own month.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/insights/domain/saved_months.dart';
import 'package:zaghlol/features/insights/presentation/v2/saved_months_chart.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  setUpAll(initDateFormatting);

  Future<String> label(
    WidgetTester tester,
    Locale locale,
    CivilDate from,
    CivilDate to,
  ) async {
    late String out;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
        home: Builder(
          builder: (context) {
            out = savedMonthName(
              context,
              SavedBar(from: from, to: to, netMinor: 0, projected: false),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return out;
  }

  testWidgets('24 Nov .. 23 Dec cycle is Dec; 24 Dec is Jan (en)', (t) async {
    expect(
      await label(
        t,
        const Locale('en'),
        CivilDate(2026, 11, 24),
        CivilDate(2026, 12, 23),
      ),
      'Dec',
    );
    expect(
      await label(
        t,
        const Locale('en'),
        CivilDate(2026, 12, 24),
        CivilDate(2027, 1, 23),
      ),
      'Jan',
    );
  });

  testWidgets('a cycle from day 1 and a calendar month keep their month', (
    t,
  ) async {
    expect(
      await label(
        t,
        const Locale('en'),
        CivilDate(2026, 11, 1),
        CivilDate(2026, 11, 30),
      ),
      'Nov',
    );
    expect(
      await label(
        t,
        const Locale('en'),
        CivilDate(2026, 11, 20),
        CivilDate(2026, 12, 19),
      ),
      'Nov',
    );
  });

  testWidgets('Arabic month name', (t) async {
    expect(
      await label(
        t,
        const Locale('ar', 'EG'),
        CivilDate(2026, 11, 24),
        CivilDate(2026, 12, 23),
      ),
      'ديسمبر',
    );
  });
}
