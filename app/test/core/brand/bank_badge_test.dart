import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/brand/institution_brand.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/institution_avatar.dart';

/// code -> (nameAr, nameEn) of every bundled registry institution.
Map<String, (String, String)> _registry() {
  final out = <String, (String, String)>{};
  for (final f in Directory('assets/registry/institutions').listSync()) {
    if (f is! File || !f.path.endsWith('.json')) continue;
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final n = j['names'] as Map<String, dynamic>;
    out[j['code'] as String] = (n['ar'] as String, n['en'] as String);
  }
  return out;
}

Map<String, InstitutionBrand> _brands() => parseInstitutionBrands(
  File('assets/brand/institutions_brand.json').readAsStringSync(),
);

void main() {
  final registry = _registry();
  final brands = _brands();

  test('every registry institution has a brand colour and a short code', () {
    expect(registry, isNotEmpty);
    for (final code in registry.keys) {
      final b = brands[code];
      expect(b, isNotNull, reason: code);
      expect(b!.colorValue, isNotNull, reason: '$code colour');
      final t = b.badgeText;
      expect(t, isNotNull, reason: '$code text');
      expect(t!.length, inInclusiveRange(2, 5), reason: '$code "$t"');
      expect(t, isNot(anyOf('بنك', 'ب')), reason: code);
    }
    expect(
      brands.keys.toSet().difference(registry.keys.toSet()),
      isEmpty,
      reason: 'brand rows without a registry institution',
    );
  });

  test('text on every brand colour reaches 4.5:1, light and dark', () {
    for (final e in brands.entries) {
      for (final br in Brightness.values) {
        final p = badgeColors(e.value.colorValue!, br);
        expect(
          contrastRatio(p.bg, p.fg),
          greaterThanOrEqualTo(4.5),
          reason: '${e.key} $br',
        );
      }
    }
  });

  test('badge text is unique among Egyptian-facing codes it could confuse', () {
    // The same acronym is allowed only for the same brand (enbd/emirates_nbd).
    final seen = <String, String>{};
    for (final e in brands.entries) {
      final t = e.value.badgeText!;
      final other = seen[t];
      if (other != null) {
        expect({other, e.key}, {'enbd', 'emirates_nbd'}, reason: t);
      }
      seen[t] = e.key;
    }
  });

  group('badgeInitials (unknown / custom institutions)', () {
    test('drops generic words and the Arabic article', () {
      expect(badgeInitials('بنك مصر'), 'مصر');
      expect(badgeInitials('البنك الأهلي'), 'أهلي');
      expect(badgeInitials('Bank of Alexandria'), 'AL');
      expect(badgeInitials('First Gulf Bank'), 'FG');
      expect(badgeInitials('Acme'), 'ACME');
    });
    test('never empty, never a lone generic word', () {
      expect(badgeInitials('   '), '?');
      expect(badgeInitials('بنك'), isNot(''));
      expect(badgeInitials('بنك مصر النهضة'), 'من');
    });
  });

  for (final dark in [false, true]) {
    testWidgets('no known institution shows بنك, ب or an empty circle '
        '(${dark ? 'dark' : 'light'})', (t) async {
      for (final e in registry.entries) {
        for (final name in [e.value.$1, e.value.$2]) {
          await t.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: ZaghlolTheme.light,
                darkTheme: ZaghlolTheme.dark,
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                home: Scaffold(
                  body: ZInstitutionAvatar(
                    institutionCode: e.key,
                    label: name,
                    brand: brands[e.key],
                  ),
                ),
              ),
            ),
          );
          final txt = t.widget<Text>(
            find.descendant(
              of: find.byType(ZInstitutionAvatar),
              matching: find.byType(Text),
            ),
          );
          expect(txt.data, brands[e.key]!.badgeText, reason: e.key);
          expect(txt.data, isNot(anyOf('بنك', 'ب', '')), reason: e.key);
        }
      }
    });
  }

  testWidgets('unknown institution gets neutral initials from the label', (
    t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ZaghlolTheme.light,
          home: const Scaffold(
            body: ZInstitutionAvatar(
              institutionCode: 'custom_x',
              label: 'بنك الأمل',
            ),
          ),
        ),
      ),
    );
    await t.pump();
    expect(find.text('أمل'), findsOneWidget);
  });
}
