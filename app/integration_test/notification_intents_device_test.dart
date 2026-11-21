// T-193 AC5: forged intents versus real notification taps on the emulator,
// with the REAL app (main(), real encrypted DB, the native hand-off token).
// Driven by .github/scripts/notif-intents.sh, which sends the forged
// `am start` intents, taps the real notifications in the shade and reads the
// debug-only `NOTIF_PROBE` markers from logcat. This test holds the parts that
// need the app's process: it seeds two synthetic bills, posts the app's own
// notifications (through the production gateway), waits for the script's
// signals (files under app_flutter/sig/), answers the confirmation dialog like
// a user and checks the database. Prints ids and booleans, never data.
//
// Run: flutter test integration_test/notification_intents_device_test.dart
//      --flavor devSms -d <device> --no-uninstall   (the script does the rest)

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zaghlol/app/notification_taps.dart' show MarkPaidConfirmDialog;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/notifications/application/notification_providers.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/recurring/data/recurring_repository.dart';
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final problems = <String>[];

  void say(String line) {
    // ignore: avoid_print
    print('NOTIF_DEVICE $line');
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

  Future<bool> waitUntil(
    WidgetTester t,
    Future<bool> Function() cond, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 300));
      if (await cond()) return true;
    }
    return false;
  }

  testWidgets('forged intents do nothing; real taps and Mark paid work', (
    t,
  ) async {
    final docs = (await getApplicationDocumentsDirectory()).path;
    final sig = Directory('$docs/sig');
    if (sig.existsSync()) sig.deleteSync(recursive: true);
    sig.createSync(recursive: true);
    Future<bool> signal(String name, {int minutes = 12}) => waitUntil(
      t,
      () async => File('${sig.path}/$name').existsSync(),
      timeout: Duration(minutes: minutes),
    );

    // Past onboarding, English; persisted for the script's cold launches.
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

    await app.main();
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (!safeFound(find.text('Home')) && DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await settle(t, 1500);
    final c = ProviderScope.containerOf(rootNavigatorKey.currentContext!);
    final db = await c.read(appDatabaseProvider.future);
    final recurring = await c.read(recurringRepositoryProvider.future);
    final gateway = c.read(notificationGatewayProvider);
    final today = CivilDate(now.year, now.month, now.day);

    Future<({String id, String due})> addBill(String name) async {
      final id = await recurring.addManual(
        kind: RecurringKind.bill,
        name: name,
        amount: Money(Currency.of('EGP'), 12300),
        dueDay: today.day > 28 ? 28 : today.day,
        nextDue: today,
        merchantNorm: name.toLowerCase(),
      );
      final row = await db
          .customSelect(
            'SELECT next_due_date AS d FROM recurring_items WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingle();
      return (id: id, due: row.data['d']! as String);
    }

    Future<int> paidCount(String id) async {
      final r = await db
          .customSelect(
            'SELECT paid_count AS n FROM recurring_items WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingle();
      return r.data['n']! as int;
    }

    Future<void> post(
      int id,
      String title, {
      String? payload,
      String? actionTitle,
      String? actionRoute,
    }) => gateway.show(
      PlatformNotification(
        id: id,
        title: title,
        body: 'synthetic',
        payload: payload,
        type: NotificationType.upcomingDue,
        actionTitle: actionTitle,
        actionRoute: actionRoute,
      ),
    );

    final billWarm = await addBill('ZPROBE bill warm');
    final billCold = await addBill('ZPROBE bill cold');
    final warmPaid0 = await paidCount(billWarm.id);

    // ---- warm: two notifications, then the script's forged intents.
    await post(9101, 'ZPROBE tap warm', payload: '/settings/backup');
    await post(
      9103,
      'ZPROBE paid warm',
      payload: '/insights',
      actionTitle: 'ZPROBE PAY WARM',
      actionRoute: '/recurring/${billWarm.id}/paid/${billWarm.due}',
    );
    say('READY_WARM billWarm=${billWarm.id} due=${billWarm.due}');
    say('BILL_IDS warm=${billWarm.id} cold=${billCold.id} due=${billWarm.due}');
    check(await signal('forged_warm_done'), 'script: forged warm cases done');
    await settle(t, 1000);
    check(
      !safeFound(find.byType(MarkPaidConfirmDialog)),
      'no confirm dialog after the forged warm intents',
    );
    check(
      await paidCount(billWarm.id) == warmPaid0,
      'the warm bill is still unpaid after the forged intents',
    );
    say('FORGED_WARM_CHECKED');

    // ---- warm: the real tap on the content (script), then the real action.
    check(await signal('real_tap_warm_done'), 'script: real warm tap done');
    check(
      await signal('real_action_warm_tapped'),
      'script: real warm action tapped',
    );
    final shown = await waitUntil(
      t,
      () async => safeFound(find.byType(MarkPaidConfirmDialog)),
      timeout: const Duration(seconds: 40),
    );
    check(shown, 'the real Mark-as-paid action opened the confirm dialog');
    check(
      await paidCount(billWarm.id) == warmPaid0,
      'nothing paid before the user confirms',
    );
    say('DIALOG_SHOWN_WARM=$shown');
    if (shown) {
      await t.tap(
        find.descendant(
          of: find.byType(MarkPaidConfirmDialog),
          matching: find.byType(FilledButton),
        ),
      );
      final paid = await waitUntil(
        t,
        () async => await paidCount(billWarm.id) == warmPaid0 + 1,
        timeout: const Duration(seconds: 20),
      );
      check(paid, 'confirming paid the warm bill');
      say('PAID_WARM=$paid');
    }

    // ---- cold: two more notifications for the script's process-death runs.
    await post(9102, 'ZPROBE tap cold', payload: '/settings/backup');
    await post(
      9104,
      'ZPROBE paid cold',
      payload: '/insights',
      actionTitle: 'ZPROBE PAY COLD',
      actionRoute: '/recurring/${billCold.id}/paid/${billCold.due}',
    );
    say('READY_COLD');
    check(await signal('cold_done', minutes: 25), 'script: cold cases done');
    if (problems.isNotEmpty) fail(problems.join('; '));
    say('DONE');
  });
}
