import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/brand/institution_brand.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/institution_avatar.dart';

Widget _wrap(InstitutionBrand? b, TextDirection d, {double scale = 1}) =>
    ProviderScope(
      child: MaterialApp(
        theme: ZaghlolTheme.light,
        home: Directionality(
          textDirection: d,
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Center(
              child: ZInstitutionAvatar(label: 'Nile Bank', brand: b),
            ),
          ),
        ),
      ),
    );

void main() {
  for (final d in TextDirection.values) {
    testWidgets('neutral fallback without brand ($d)', (t) async {
      await t.pumpWidget(_wrap(null, d, scale: 1.3));
      final box =
          t.widget<Container>(find.byType(Container).first).decoration
              as BoxDecoration;
      expect(box.color, const Color(0xFFD7F3E5));
      expect(find.text('NILE'), findsOneWidget);
    });
  }

  testWidgets('initials on brand colour with readable contrast', (t) async {
    for (final v in [0xFF006A4E, 0xFFFFB86B, 0xFFFFFFFF, 0xFF000000]) {
      await t.pumpWidget(
        _wrap(
          InstitutionBrand(colorValue: v, acronym: 'NBE'),
          TextDirection.rtl,
        ),
      );
      final txt = t.widget<Text>(find.text('NBE'));
      final bg =
          (t.widget<Container>(find.byType(Container).first).decoration
                  as BoxDecoration)
              .color!;
      expect(
        contrastRatio(bg, txt.style!.color!),
        greaterThanOrEqualTo(4.5),
        reason: '$v',
      );
    }
  });

  testWidgets('missing logo asset falls back to initials', (t) async {
    await t.pumpWidget(
      _wrap(
        const InstitutionBrand(
          colorValue: 0xFF006A4E,
          acronym: 'NBE',
          logoAsset: 'assets/brand/logos/none.png',
        ),
        TextDirection.ltr,
      ),
    );
    await t.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('NBE'), findsOneWidget);
  });

  test('parse brand map', () {
    final m = parseInstitutionBrands(
      '{"institutions":{"a":{"brandColor":"#006A4E","logoAsset":null},'
      '"b":{"brandColor":"bad"}}}',
    );
    expect(m['a']!.colorValue, 0xFF006A4E);
    expect(m['b']!.colorValue, isNull);
  });
}
