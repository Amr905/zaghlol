@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/categorization/data/categories_admin.dart';
import 'package:zaghlol/features/categorization/data/rules_providers.dart';
import 'package:zaghlol/features/categorization/presentation/categories_rules_screen.dart';
import 'package:zaghlol/features/categorization/presentation/category_edit_screen.dart';

import '../../settings/settings_harness.dart';
import 'categories_screens_test.dart'
    show FakeAdmin, FakeRules, bills, food, sub, rule;

void main() {
  final screens = <String, Widget>{
    'rules': const CategoriesRulesScreen(),
    'edit': const CategoryEditScreen(categoryId: 'sub1'),
  };
  for (final e in screens.entries) {
    for (final lang in ['ar', 'en']) {
      for (final dark in [false, true]) {
        testWidgets('${e.key} $lang ${dark ? 'dark' : 'light'}', (t) async {
          final h = SettingsHarness();
          addTearDown(h.db.close);
          await t.pumpWidget(
            h.app(
              e.value,
              locale: Locale(lang),
              dark: dark,
              overrides: [
                categoriesAdminProvider.overrideWith(
                  (ref) async => FakeAdmin([food, bills, sub]),
                ),
                rulesRepositoryProvider.overrideWith(
                  (ref) async => FakeRules([rule]),
                ),
              ],
            ),
          );
          await settle(t, height: 1200);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/categories_${e.key}_${lang}_${dark ? 'dark' : 'light'}.png',
            ),
          );
        });
      }
    }
  }
}
