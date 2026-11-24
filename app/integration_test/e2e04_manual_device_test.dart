// T-237 E2E-04: manual add, edit, delete with undo and bulk edit with undo,
// all through the real UI of the real app on the emulator (FR-TXN-02,
// FR-TXN-06). After every step the database row and the Home list are checked.
// Synthetic data only; prints step names and ids, never amounts of real data.
//
// Run: flutter test integration_test/e2e04_manual_device_test.dart
//      --flavor devSms -d <device> --no-uninstall

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/features/transactions/presentation/edit/transaction_edit_screen.dart';

import 'support/e2e_common.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final e = E2e('E2E04', binding);

  testWidgets('manual add, edit, delete+undo, bulk edit+undo', (t) async {
    final semantics = t.ensureSemantics();
    try {
      final c = await e.boot(t);
      final db = await c.read(appDatabaseProvider.future);

      Future<String> catName(String id) async =>
          (await e.rows(
                db,
                "SELECT name_en FROM categories WHERE id = '$id'",
              )).single['name_en']!
              as String;
      final groceries = await catName('sys:groceries');
      final subs = await catName('sys:subscriptions');
      final fun = await catName('sys:entertainment');

      Future<Map<String, Object?>> row(String id) async => (await e.rows(
        db,
        'SELECT amount_minor, category_id, direction, source, deleted_at '
        "FROM transactions WHERE id = '$id'",
      )).single;
      Finder homeRow(String id) => find.byKey(ValueKey('home-row-$id'));
      Finder quickAdd() => find.bySemanticsLabel('Quick add');

      Future<void> pickCategory(String name) async {
        final item = find.text(name);
        await e.waitFor(t, item, what: 'category $name in the picker');
        await t.ensureVisible(item.last);
        await e.settle(t, 300);
        await t.tap(item.last);
        await e.settle(t);
      }

      Future<String> addViaType(String amount, String category) async {
        final before = {
          for (final r in await e.rows(db, 'SELECT id FROM transactions'))
            r['id']! as String,
        };
        await e.waitFor(t, quickAdd(), what: 'the Add button');
        await t.tap(quickAdd().first);
        await e.waitFor(t, find.text('Type'), what: 'the Add sheet');
        await e.settle(t);
        await t.tap(find.text('Type'));
        await e.waitFor(t, find.text('Add expense'), what: 'the editor');
        await e.settle(t);
        await t.enterText(find.byType(TextField).first, amount);
        await e.settle(t, 300);
        await e.waitFor(t, find.text('Choose'), what: 'category field');
        await t.ensureVisible(find.text('Choose').first);
        await t.tap(find.text('Choose').first);
        await pickCategory(category);
        await t.ensureVisible(find.text('Save').last);
        await t.tap(find.text('Save').last);
        await e.settle(t, 1500);
        final ok = await e.waitUntil(t, () async {
          final now = await e.rows(db, 'SELECT id FROM transactions');
          return now.length == before.length + 1;
        });
        expect(ok, isTrue, reason: 'the new row reached the database');
        final id = (await e.rows(db, 'SELECT id FROM transactions'))
            .map((r) => r['id']! as String)
            .firstWhere((i) => !before.contains(i));
        return id;
      }

      // ---- 1. add through Type
      final a = await addViaType('125.50', groceries);
      var r = await row(a);
      e.check(r['amount_minor'] == 12550, 'add: amount saved as 12550 minor');
      e.check(r['category_id'] == 'sys:groceries', 'add: category groceries');
      e.check(r['direction'] == 'expense', 'add: direction expense');
      e.check(r['source'] == 'manual', 'add: source manual');
      await e.waitFor(t, homeRow(a), what: 'the new row on Home');
      e.check(e.found(homeRow(a)), 'add: row is on the Home list');
      await e.shot(t, 'e2e04-1-added');

      // ---- 2. edit amount and category from the detail screen
      e.say('STEP open detail via the list');
      await e.go(t, AppRoutes.transactions);
      await e.reveal(t, find.byKey(ValueKey(a)));
      await t.tap(find.byKey(ValueKey(a)));
      e.say('STEP tapped row');
      await e.waitFor(t, find.byTooltip('Edit'), what: 'detail screen');
      await e.settle(t);
      e.say('STEP detail open');
      await t.tap(find.byTooltip('Edit'));
      await e.waitFor(t, find.byType(TransactionEditScreen), what: 'edit form');
      await e.settle(t);
      final form = find.byType(TransactionEditScreen);
      await t.enterText(
        find.descendant(of: form, matching: find.byType(TextField)).first,
        '200.00',
      );
      await e.settle(t, 300);
      final catField = find.descendant(
        of: form,
        matching: find.text(groceries),
      );
      await e.waitFor(t, catField, what: 'the category field');
      await t.ensureVisible(catField.first);
      await t.tap(catField.first);
      await pickCategory(subs);
      await t.ensureVisible(find.text('Save').last);
      await t.tap(find.text('Save').last);
      await e.settle(t, 1500);
      r = await row(a);
      e.check(r['amount_minor'] == 20000, 'edit: amount now 20000 minor');
      e.check(
        r['category_id'] == 'sys:subscriptions',
        'edit: category changed',
      );
      await e.shot(t, 'e2e04-2-edited');

      // ---- 3. delete with Undo (detail screen is still open)
      e.say('STEP delete');
      await t.tap(find.byTooltip('More options'));
      await e.settle(t);
      await t.tap(find.text('Delete').last);
      await e.waitFor(
        t,
        find.text('Delete this transaction?'),
        what: 'delete confirmation',
      );
      await t.tap(find.text('Delete').last);
      await e.settle(t, 1500);
      r = await row(a);
      e.check(r['deleted_at'] != null, 'delete: row is soft-deleted');
      e.check(
        !e.found(find.byKey(ValueKey(a))),
        'delete: row left the transactions list',
      );
      await e.shot(t, 'e2e04-3-deleted');
      await t.tap(find.text('Undo'));
      await e.settle(t, 1500);
      r = await row(a);
      e.check(r['deleted_at'] == null, 'undo delete: row restored');
      e.check(r['amount_minor'] == 20000, 'undo delete: amount intact');
      await e.go(t, AppRoutes.home);
      await e.waitFor(t, homeRow(a), what: 'restored row on Home');
      e.check(e.found(homeRow(a)), 'undo delete: row is back on Home');

      e.say('STEP bulk');
      // ---- 4. bulk edit two rows' category, then Undo
      final b = await addViaType('50.00', groceries);
      e.check(
        (await row(b))['category_id'] == 'sys:groceries',
        'second row added with groceries',
      );
      await e.go(t, AppRoutes.transactions);
      await e.waitFor(t, find.byKey(ValueKey(a)), what: 'row A in the list');
      await e.waitFor(t, find.byKey(ValueKey(b)), what: 'row B in the list');
      await t.longPress(find.byKey(ValueKey(a)));
      await e.settle(t);
      await t.tap(find.byKey(ValueKey(b)));
      await e.settle(t);
      await e.shot(t, 'e2e04-4-selected');
      await t.tap(find.byKey(const ValueKey('bulk-category')));
      await e.settle(t);
      await pickCategory(fun);
      await e.settle(t, 1500);
      e.check(
        (await row(a))['category_id'] == 'sys:entertainment',
        'bulk: row A category changed',
      );
      e.check(
        (await row(b))['category_id'] == 'sys:entertainment',
        'bulk: row B category changed',
      );
      await e.shot(t, 'e2e04-5-bulk-changed');
      await t.tap(find.text('Undo'));
      await e.settle(t, 1500);
      e.check(
        (await row(a))['category_id'] == 'sys:subscriptions',
        'bulk undo: row A back to its category',
      );
      e.check(
        (await row(b))['category_id'] == 'sys:groceries',
        'bulk undo: row B back to its category',
      );
      await e.shot(t, 'e2e04-6-bulk-undone');

      e.say('RESULT problems=${e.problems.length}');
      expect(e.problems, isEmpty, reason: e.problems.join('; '));
    } finally {
      e.restoreErrors();
      semantics.dispose();
    }
  });
}
