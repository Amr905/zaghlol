// T-174: guideline + 1.3x sweep over the Settings screens and the categories
// screens. ar/en x light/dark x scale 1.0/1.3.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/categorization/data/categories_admin.dart';
import 'package:zaghlol/features/categorization/data/rules_providers.dart';
import 'package:zaghlol/features/categorization/presentation/categories_rules_screen.dart';
import 'package:zaghlol/features/categorization/presentation/category_edit_screen.dart';
import 'package:zaghlol/features/settings/presentation/about_screen.dart';
import 'package:zaghlol/features/settings/presentation/preferences_screen.dart';
import 'package:zaghlol/features/settings/presentation/privacy_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_main_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_ports.dart';

import '../features/categorization/presentation/categories_screens_test.dart'
    show FakeAdmin, FakeRules, bills, food, sub, rule;
import '../features/settings/settings_harness.dart';
import '../support/a11y_guidelines.dart';

void main() {
  const screens = <String, Widget>{
    'main': SettingsMainScreen(),
    'preferences': PreferencesScreen(),
    'privacy': PrivacyScreen(platform: 'ios'),
    'about': AboutScreen(),
    'rules': CategoriesRulesScreen(),
    'category edit': CategoryEditScreen(categoryId: 'sub1'),
  };
  for (final e in screens.entries) {
    for (final lang in ['ar', 'en']) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 1.3]) {
          testWidgets(
            '${e.key} a11y $lang ${dark ? 'dark' : 'light'} x$scale',
            (t) async {
              final h = SettingsHarness();
              addTearDown(h.db.close);
              await t.pumpWidget(
                h.app(
                  e.value,
                  locale: Locale(lang),
                  dark: dark,
                  scale: scale,
                  payday: 25,
                  appLock: true,
                  overrides: [
                    supportCodeProvider.overrideWith((ref) async => 'abc-123'),
                    categoriesAdminProvider.overrideWith(
                      (ref) async => FakeAdmin([food, bills, sub]),
                    ),
                    rulesRepositoryProvider.overrideWith(
                      (ref) async => FakeRules([rule]),
                    ),
                  ],
                ),
              );
              await settle(t, height: 1400);
              await expectA11yGuidelines(t);
            },
          );
        }
      }
    }
  }
}
