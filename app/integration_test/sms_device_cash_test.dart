// TEST-explorer4: Cash / InstaPay categories and the floating Add button on
// the emulator, with the REAL app (main(), real encrypted DB, inbox scan).
// device-flows.sh sends two synthetic CIB SMS (an ATM withdrawal and an
// InstaPay transfer out) before the first launch; this test then checks:
//  1. the saved transactions carry the categories Cash and InstaPay;
//  2. a manual cash expense from the Cash account (paid from the cash just
//     withdrawn) leaves the Insights total unchanged and moves the amount
//     from Cash to the expense's own category;
//  3. the Add button never covers Send on the Zaghlol tab and covers no Home
//     content at rest (rect test + hit test + screenshots).
// Then the script resumes the app twice and counts notifications.
// Synthetic data only; prints counts and ids, never a message body.
//
// Run: flutter test integration_test/sms_device_cash_test.dart
//      --flavor devSms -d <device> --no-uninstall

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/ui/shell/app_shell.dart' show ZAddButton;
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/insights/data/chart_providers.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;
  final problems = <String>[];

  void say(String line) {
    // ignore: avoid_print
    print('CASH_DEVICE $line');
  }

  void check(bool ok, String what) {
    if (!ok) {
      problems.add(what);
      say('PROBLEM $what');
    }
  }

  bool safeFound(Finder f) {
    try {
      return f.evaluate().isNotEmpty;
    } on TypeError {
      return false;
    }
  }

  Future<void> settle(WidgetTester t, [int ms = 800]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    try {
      if (!surfaceConverted && Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        surfaceConverted = true;
      }
      await settle(t, 400);
      final bytes = await binding.takeScreenshot(name);
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/ci_screens',
      );
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
      say('SHOT $name');
    } on Object catch (e) {
      say('SHOT_FAILED $name ${e.runtimeType}');
    }
  }

  Future<bool> waitUntil(
    WidgetTester t,
    Future<bool> Function() cond, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 500));
      if (await cond()) return true;
    }
    return false;
  }

  Future<void> go(WidgetTester t, String route) async {
    rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    await settle(t, 300);
    GoRouter.of(rootNavigatorKey.currentContext!).go(route);
    await settle(t, 2000);
  }

  // slice id -> minor, plus the total, over a wide EGP period.
  Future<({int total, Map<String?, int> slices})> donut(
    ProviderContainer c,
  ) async {
    final repo = await c.read(chartRepositoryProvider.future);
    repo.invalidate();
    final r = await repo.categoryDonut(
      ChartPeriod(CivilDate(2020, 1, 1), CivilDate(2035, 12, 31)),
      ChartFilter(currency: Currency.of('EGP')),
    );
    if (r is! ChartReady<CategoryDonut>) {
      return (total: 0, slices: <String?, int>{});
    }
    return (
      total: r.data.total.minor,
      slices: {for (final s in r.data.slices) s.categoryId: s.amount.minor},
    );
  }

  Future<String?> categoryOfAmount(AppDatabase db, int minor) async {
    final rows = await db
        .customSelect(
          'SELECT category_id AS c FROM transactions '
          'WHERE amount_minor = ? AND deleted_at IS NULL',
          variables: [Variable.withInt(minor)],
        )
        .get();
    if (rows.isEmpty) return '<none>';
    return rows.first.data['c'] as String?;
  }

  testWidgets('Cash and InstaPay categories, cash payment, Add button', (
    t,
  ) async {
    final dir = await resolveDbDirectory();
    final seed = ProviderContainer(
      overrides: [dbDirectoryProvider.overrideWithValue(dir)],
    );
    final settings = await seed.read(settingsRepositoryProvider.future);
    final now = DateTime.now();
    await settings.set(
      Settings.setupInstalledOn,
      CivilDate(now.year, now.month, now.day).epochDay,
    );
    await settings.set(Settings.language, LanguagePref.en);
    await (await seed.read(appDatabaseProvider.future)).close();
    seed.dispose();

    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      final text = d.exceptionAsString();
      if (text.contains('overflowed') || text.contains('parentDataDirty')) {
        return;
      }
      original?.call(d);
    };

    await app.main();
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (!safeFound(find.text('Home')) && DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await settle(t, 1500);
    final c = ProviderScope.containerOf(rootNavigatorKey.currentContext!);
    final db = await c.read(appDatabaseProvider.future);

    // ---- 1. the SMS: ATM 1000.00 -> Cash, InstaPay out 500.00 -> InstaPay
    final scan = await c.read(inboxScanServiceProvider.future);
    check(scan != null, 'the inbox scan service exists');
    await scan?.startFirstRun();
    final saved = await waitUntil(t, () async {
      final n = await db
          .customSelect('SELECT COUNT(*) AS n FROM transactions')
          .getSingle();
      return (n.data['n']! as int) >= 2;
    });
    check(saved, 'the ATM and the InstaPay SMS were saved as transactions');
    final atmCat = await categoryOfAmount(db, 100000);
    final ipCat = await categoryOfAmount(db, 50000);
    say('CATEGORY atm=$atmCat instapay=$ipCat');
    check(atmCat == 'sys:cash', 'ATM withdrawal category is Cash ($atmCat)');
    check(
      ipCat == 'sys:instapay',
      'InstaPay transfer category is InstaPay '
      '($ipCat)',
    );

    // ---- 2. a manual cash expense from the Cash account
    final before = await donut(c);
    say('DONUT before total=${before.total} slices=${before.slices}');
    await waitUntil(
      t,
      () async => (await CategoriesDao(db).active()).isNotEmpty,
    );
    final cats = await CategoriesDao(db).active();
    final own = cats.where((x) => !x.id.startsWith('sys:')).first.id;
    final accounts = await c.read(accountsRepositoryProvider.future);
    final cash = await accounts.ensureDefaultCash(
      currency: Currency.of('EGP'),
      label: 'Cash',
    );
    final txns = await c.read(transactionRepositoryProvider.future);
    await txns.add(
      NewTransaction(
        accountId: cash.id,
        direction: TxnDirection.expense,
        amount: Money(Currency.of('EGP'), 30000),
        occurredAt: DateTime.now(),
        occurredTzOffsetMin: DateTime.now().timeZoneOffset.inMinutes,
        categoryId: own,
        merchant: 'Synthetic corner shop',
      ),
    );
    await settle(t, 800);
    final after = await donut(c);
    say('DONUT after total=${after.total} slices=${after.slices}');
    check(
      after.total == before.total,
      'Insights total unchanged by a cash expense covered by withdrawn cash '
      '(${before.total} -> ${after.total})',
    );
    check(
      (after.slices[own] ?? 0) - (before.slices[own] ?? 0) == 30000,
      'the expense moved into its own category',
    );
    check(
      (before.slices['sys:cash'] ?? 0) - (after.slices['sys:cash'] ?? 0) ==
          30000,
      'the same amount left Cash',
    );
    await go(t, AppRoutes.insights);
    await shot(t, 'cash-01-insights');

    // ---- 3. the Add button: Zaghlol tab (Send) and Home at rest
    final size = t.view.physicalSize / t.view.devicePixelRatio;
    await go(t, AppRoutes.zaghlol);
    final add = find.byType(ZAddButton);
    final send = find.byKey(const ValueKey('ask-send'));
    check(safeFound(add), 'the Add button is on the Zaghlol tab');
    check(safeFound(send), 'Send is on the Zaghlol tab');
    if (safeFound(add) && safeFound(send)) {
      final a = t.getRect(add.first);
      final s = t.getRect(send.first);
      say('RECT add=$a send=$s screen=$size');
      check(!a.overlaps(s), 'Add does not overlap Send');
      check(
        send.hitTestable().evaluate().isNotEmpty,
        'Send is hit-testable (nothing covers its centre)',
      );
    }
    await shot(t, 'cash-02-zaghlol-add-vs-send');

    await go(t, AppRoutes.home);
    if (safeFound(add)) {
      final a = t.getRect(add.first).deflate(4);
      var covered = 0;
      for (final f in [find.byType(Text), find.byType(Icon)]) {
        for (final e in f.evaluate()) {
          final box = e.renderObject;
          if (box is! RenderBox || !box.hasSize || !box.attached) continue;
          if (find
              .descendant(of: add, matching: find.byWidget(e.widget))
              .evaluate()
              .isNotEmpty) {
            continue;
          }
          final r = box.localToGlobal(Offset.zero) & box.size;
          final onScreen = r.bottom > 0 && r.top < size.height;
          if (onScreen && r.overlaps(a)) covered++;
        }
      }
      say('HOME content under Add: $covered');
      check(covered == 0, 'Add covers no Home content at rest ($covered)');
    } else {
      check(false, 'the Add button is on Home');
    }
    await shot(t, 'cash-03-home-add');

    say('RESULT problems=${problems.length}');
    FlutterError.onError = original;
    expect(problems, isEmpty, reason: problems.join('; '));
  });
}
