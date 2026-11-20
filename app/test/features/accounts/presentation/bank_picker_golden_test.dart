@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/brand/institution_brand.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/add_card_steps.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/edit_card_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../support/golden_matrix.dart';

// T-198. The picker with the real registry names and the real badge data:
// the full grid and a search ("bank" / "بنك" matches many names).
List<InstitutionOption> _options() {
  final out = <InstitutionOption>[];
  for (final f in Directory('assets/registry/institutions').listSync()) {
    if (f is! File || !f.path.endsWith('.json')) continue;
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final n = j['names'] as Map<String, dynamic>;
    out.add(
      InstitutionOption(
        code: j['code'] as String,
        nameAr: n['ar'] as String,
        nameEn: n['en'] as String,
        defaultCurrency: Currency.of(j['defaultCurrency'] as String),
        isEgypt: j['country'] == 'EG',
      ),
    );
  }
  return out;
}

Future<void> _pump(WidgetTester t, GoldenVariant v) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(390, 1400);
  addTearDown(t.view.reset);
  final brands = parseInstitutionBrands(
    File('assets/brand/institutions_brand.json').readAsStringSync(),
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        institutionOptionsProvider.overrideWithValue(_options()),
        institutionBrandsProvider.overrideWith((ref) async => brands),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ZaghlolTheme.light,
        darkTheme: ZaghlolTheme.dark,
        themeMode: v.dark ? ThemeMode.dark : ThemeMode.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: v.locale,
        home: const BankPicker(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  for (final v in goldenVariants) {
    testWidgets('bank picker grid golden ${v.name}', (t) async {
      await _pump(t, v);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../goldens/bank_picker_${v.name}.png'),
      );
    });
    testWidgets('bank picker search golden ${v.name}', (t) async {
      await _pump(t, v);
      await t.enterText(
        find.byKey(const Key('bank-search')),
        v.locale.languageCode == 'ar' ? 'بنك' : 'bank',
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../goldens/bank_picker_search_${v.name}.png'),
      );
    });
  }
}
