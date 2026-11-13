// T-163: S-63/S-64 widget tests per state, ar + en, RTL, text scale 1.3.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/categorization/data/categories_admin.dart';
import 'package:zaghlol/features/categorization/data/rules_providers.dart';
import 'package:zaghlol/features/categorization/domain/merchant_rule.dart';
import 'package:zaghlol/features/categorization/presentation/categories_providers.dart';
import 'package:zaghlol/features/categorization/presentation/categories_rules_screen.dart';
import 'package:zaghlol/features/categorization/presentation/category_edit_screen.dart';
import 'package:zaghlol/features/gold/application/gating.dart';

import '../../settings/settings_harness.dart';

CategoryItem cat(
  String id,
  String en,
  String ar, {
  String? parent,
  bool sys = true,
}) => CategoryItem(
  id: id,
  nameAr: ar,
  nameEn: en,
  icon: 'cart',
  color: '#174C4F',
  bucket: 'needs',
  isSystem: sys,
  parentId: parent,
);

class FakeAdmin implements CategoriesAdmin {
  FakeAdmin(this.items);
  List<CategoryItem> items;
  final List<String> deleted = [];
  final List<String> created = [];

  @override
  Future<List<CategoryItem>> list() async => items;

  @override
  Future<CategoryItem> create({
    required String name,
    required String bucket,
    required String icon,
    required String color,
    String? parentId,
  }) async {
    created.add(name);
    final c = cat(
      'n${created.length}',
      name,
      name,
      parent: parentId,
      sys: false,
    );
    items = [...items, c];
    return c;
  }

  @override
  Future<CategoryItem> update(
    String id, {
    required String name,
    required String bucket,
    required String icon,
    required String color,
    String? parentId,
  }) async => items.first;

  @override
  Future<int> deleteWithReplacement(
    String id, {
    required String replacementId,
  }) async {
    deleted.add('$id->$replacementId');
    items = [
      for (final c in items)
        if (c.id != id) c,
    ];
    return 0;
  }
}

class FakeRules implements RulesRepository {
  FakeRules(this.rules);
  List<MerchantRule> rules;

  @override
  Future<List<MerchantRule>> list() async => rules;

  @override
  Future<bool> delete(String id) async {
    rules = [
      for (final r in rules)
        if (r.id != id) r,
    ];
    return true;
  }

  @override
  Future<MerchantRule> changeCategory(String id, String categoryId) async {
    final old = rules.firstWhere((r) => r.id == id);
    final n = MerchantRule(
      id: id,
      kind: old.kind,
      value: old.value,
      categoryId: categoryId,
      createdAt: old.createdAt,
    );
    rules = [for (final r in rules) r.id == id ? n : r];
    return n;
  }

  @override
  Future<MerchantRule> save({
    required RuleMatchKind kind,
    required String value,
    required String categoryId,
  }) async {
    final n = MerchantRule(
      id: 'r${rules.length}',
      kind: kind,
      value: value,
      categoryId: categoryId,
      createdAt: DateTime.utc(2026),
    );
    rules = [...rules, n];
    return n;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

final food = cat('sys:food', 'Food', 'أكل');
final bills = cat('sys:bills', 'Bills', 'فواتير');
final sub = cat('sub1', 'Cafes', 'قهوة', parent: 'sys:food', sys: false);
final rule = MerchantRule(
  id: 'r1',
  kind: RuleMatchKind.merchantNorm,
  value: 'kazyon',
  categoryId: 'sys:food',
  createdAt: DateTime.utc(2026),
);

Widget host(
  SettingsHarness h,
  Widget screen, {
  required FakeAdmin admin,
  FakeRules? rules,
  String lang = 'en',
  double scale = 1.0,
  bool dark = false,
}) => h.app(
  screen,
  locale: Locale(lang),
  scale: scale,
  dark: dark,
  overrides: [
    categoriesAdminProvider.overrideWith((ref) async => admin),
    rulesRepositoryProvider.overrideWith(
      (ref) async => rules ?? FakeRules(const []),
    ),
  ],
);

void setGold(WidgetTester t, bool gold) {
  final c = ProviderScope.containerOf(t.element(find.byType(Scaffold).first));
  c.read(entitlementStateProvider.notifier).debugOverride(gold);
}

void main() {
  for (final lang in ['en', 'ar']) {
    for (final scale in [1.0, 1.3]) {
      group('$lang x$scale', () {
        testWidgets('categories tab lists system categories, no overflow', (
          t,
        ) async {
          final h = SettingsHarness();
          addTearDown(h.db.close);
          await t.pumpWidget(
            host(
              h,
              const CategoriesRulesScreen(),
              admin: FakeAdmin([food, bills, sub]),
              lang: lang,
              scale: scale,
            ),
          );
          await settle(t);
          expect(find.byIcon(Icons.shopping_cart_outlined), findsWidgets);
          expect(find.byType(CategoriesRulesScreen), findsOneWidget);
          expect(t.takeException(), isNull);
          final dir = Directionality.of(
            t.element(find.byType(CategoriesRulesScreen)),
          );
          expect(dir, lang == 'ar' ? TextDirection.rtl : TextDirection.ltr);
        });

        testWidgets('empty rules state', (t) async {
          final h = SettingsHarness();
          addTearDown(h.db.close);
          await t.pumpWidget(
            host(
              h,
              const CategoriesRulesScreen(),
              admin: FakeAdmin([food]),
              lang: lang,
              scale: scale,
            ),
          );
          await settle(t);
          final l = AppLocalizations.of(
            t.element(find.byType(CategoriesRulesScreen)),
          );
          await t.tap(find.text(l.categoriesListTabRules));
          await settle(t);
          expect(find.text(l.categoriesListRulesEmpty), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      });
    }
  }

  testWidgets('rules tab: edit, search, delete with undo', (t) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    final rules = FakeRules([rule]);
    await t.pumpWidget(
      host(
        h,
        const CategoriesRulesScreen(),
        admin: FakeAdmin([food, bills]),
        rules: rules,
      ),
    );
    await settle(t);
    await t.tap(find.text('Rules'));
    await settle(t);
    expect(find.text('kazyon'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'zzz');
    await settle(t);
    expect(find.text('No rule matches that'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'kaz');
    await settle(t);

    await t.tap(find.byIcon(Icons.edit_outlined));
    await settle(t);
    await t.tap(find.text('Bills'));
    await settle(t);
    expect(rules.rules.single.categoryId, 'sys:bills');

    await t.tap(find.byIcon(Icons.delete_outline));
    await settle(t);
    await t.tap(find.text('Delete'));
    await settle(t);
    expect(rules.rules, isEmpty);
    await t.tap(find.text('Undo'));
    await settle(t);
    expect(rules.rules.single.value, 'kazyon');
  });

  testWidgets('Free: new category fires the paywall, creates nothing', (
    t,
  ) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    GoldCapability? hit;
    await t.pumpWidget(
      h.app(
        const CategoriesRulesScreen(),
        overrides: [
          categoriesAdminProvider.overrideWith(
            (ref) async => FakeAdmin([food]),
          ),
          rulesRepositoryProvider.overrideWith(
            (ref) async => FakeRules(const []),
          ),
          paywallTriggerProvider.overrideWith(
            (ref) =>
                (c) => hit = c,
          ),
        ],
      ),
    );
    await settle(t);
    await t.tap(find.text('New category'));
    await settle(t);
    expect(hit, GoldCapability.customCategories);
    expect(find.byType(CategoryEditScreen), findsNothing);
  });

  testWidgets('Gold: create a category through S-64', (t) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    final admin = FakeAdmin([food]);
    await t.pumpWidget(host(h, const CategoriesRulesScreen(), admin: admin));
    await settle(t);
    setGold(t, true);
    await settle(t);
    await t.tap(find.text('New category'));
    await settle(t);
    expect(find.byType(CategoryEditScreen), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Trips');
    await t.tap(find.text('Wants'));
    await t.pump();
    await t.tap(find.text('Save'));
    await settle(t);
    expect(admin.created, ['Trips']);
  });

  testWidgets('bucket is required before saving', (t) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    final admin = FakeAdmin([food]);
    await t.pumpWidget(host(h, const CategoryEditScreen(), admin: admin));
    await settle(t);
    setGold(t, true);
    await settle(t);
    await t.enterText(find.byType(TextField), 'Trips');
    await t.pump();
    await t.tap(find.text('Save'));
    await settle(t);
    expect(find.text('Choose a type'), findsOneWidget);
    expect(admin.created, isEmpty);
  });

  testWidgets('delete needs a replacement', (t) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    final admin = FakeAdmin([food, sub]);
    await t.pumpWidget(
      host(h, const CategoryEditScreen(categoryId: 'sub1'), admin: admin),
    );
    await settle(t);
    setGold(t, true);
    await settle(t);
    await t.ensureVisible(find.text('Delete category'));
    await t.tap(find.text('Delete category'));
    await settle(t);
    expect(find.text('Choose a category to move them to'), findsOneWidget);
    final confirm = find.widgetWithText(TextButton, 'Delete and move');
    expect(t.widget<TextButton>(confirm).onPressed, isNull);
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await settle(t);
    await t.tap(find.text('Food').last);
    await settle(t);
    await t.tap(confirm);
    await settle(t);
    expect(admin.deleted, ['sub1->sys:food']);
  });

  testWidgets('downgrade: existing custom category readable, not editable', (
    t,
  ) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    final admin = FakeAdmin([food, sub]);
    await t.pumpWidget(
      host(h, const CategoryEditScreen(categoryId: 'sub1'), admin: admin),
    );
    await settle(t);
    expect(find.text('Your own categories come with Gold'), findsOneWidget);
    expect(find.text('Cafes'), findsOneWidget);
    expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await t.ensureVisible(find.text('Delete category'));
    await t.tap(find.text('Delete category'), warnIfMissed: false);
    await settle(t);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('error state offers retry', (t) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    await t.pumpWidget(
      h.app(
        const CategoriesRulesScreen(),
        overrides: [
          categoryItemsProvider.overrideWith(
            (ref) async => throw StateError('x'),
          ),
          rulesRepositoryProvider.overrideWith(
            (ref) async => FakeRules(const []),
          ),
        ],
      ),
    );
    await settle(t);
    expect(find.text('Try again'), findsOneWidget);
  });
}
