import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/brand/institution_brand.dart';
import 'package:zaghlol/core/ui/bank_name_text.dart';

const _full = 'البنك الأهلي المصري';

Widget _host({
  required double width,
  required TextDirection dir,
  double scale = 1,
  String? last4 = '٥٠٧٥',
}) => ProviderScope(
  overrides: [
    institutionBrandsProvider.overrideWith(
      (ref) async => {'nbe': const InstitutionBrand(acronym: 'NBE')},
    ),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(textDirection: dir, child: child!),
    ),
    home: Scaffold(
      body: Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          width: width,
          child: BankNameText(
            name: _full,
            institutionCode: 'nbe',
            last4: last4,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final dir in TextDirection.values) {
    testWidgets('full name when it fits ($dir)', (tester) async {
      await tester.pumpWidget(_host(width: 600, dir: dir));
      await tester.pumpAndSettle();
      expect(find.textContaining(_full), findsOneWidget);
      expect(find.textContaining('NBE'), findsNothing);
    });

    testWidgets('acronym when too long, full name in semantics ($dir)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(width: 120, dir: dir, scale: 1.3));
      await tester.pumpAndSettle();
      expect(find.textContaining('NBE'), findsOneWidget);
      expect(find.textContaining(_full), findsNothing);
      // The card tail stays Western digits.
      expect(find.textContaining('•••• 5075'), findsOneWidget);
      expect(find.byTooltip('$_full \u2066•••• 5075\u2069'), findsOneWidget);
    });
  }

  testWidgets('no acronym known: ellipsis, never throws', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 60,
          child: ProviderScope(
            child: const BankNameText(name: _full, style: TextStyle()),
          ),
        ),
      ),
    );
    expect(find.textContaining(_full), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('parseInstitutionBrands reads the acronym', () {
    final m = parseInstitutionBrands(
      '{"institutions":{"cib":{"brandColor":null,"logoAsset":null,"acronym":"CIB"},"x":{}}}',
    );
    expect(m['cib']!.acronym, 'CIB');
    expect(m['x']!.acronym, isNull);
  });
}
