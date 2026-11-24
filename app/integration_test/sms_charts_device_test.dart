// T-233: the SMS month story, end to end on the Android emulator, with the REAL
// app (main(), real encrypted DB, native receiver, inbox scan).
//
// .github/scripts/scenario-device.sh writes the past messages of
// test/fixtures/sms/scenarios/month_story.json into the system inbox (with
// their dates) before the first launch and passes the file in as the
// SCENARIO_JSON dart-define. This test then:
//  1. runs the first-run inbox scan, prints SCENARIO_DEVICE READY_FOR_LIVE (the
//     script sends the live messages through the modem), adds the manual cash
//     payment;
//  2. checks every scenario entry against the saved transactions (amount,
//     currency, kind, status, category, merchant, internal flag) and that the
//     ignored ones created nothing (mismatches are listed by entry id);
//  3. compares the chart queries (totals, categories and shares, day by day,
//     saved each month, top merchants) with the numbers computed from the
//     scenario alone (test/support/scenario_expected.dart);
//  4. opens Insights v2 (Overview, Categories, Trends) in English and Arabic
//     and checks the shown numbers (hero spend, rows, saved bars, heatmap
//     days), then Home's recent list for the live ones; screenshots of each.
// Synthetic data only. Prints entry ids, field names and numbers; never a
// message body.
//
// Run: flutter test integration_test/sms_charts_device_test.dart
//      --flavor devSms -d <device> --no-uninstall
//      --dart-define-from-file=<file with SCENARIO_JSON>

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/money_format.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/insights/application/chart_period_providers.dart';
import 'package:zaghlol/features/insights/data/chart_providers.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_period_selection.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_format.dart'
    show trimZeroFraction;
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/main.dart' as app;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../test/support/scenario_expected.dart';

const String _scenarioJson = String.fromEnvironment('SCENARIO_JSON');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;
  final problems = <String>[];

  void say(String line) {
    // ignore: avoid_print
    print('SCENARIO_DEVICE $line');
  }

  void check(bool ok, String what) {
    if (!ok) {
      problems.add(what);
      say('MISMATCH $what');
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
    Duration timeout = const Duration(seconds: 120),
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

  // ------------------------------------------------------------ formatting
  String clean(String s) =>
      s.replaceAll(RegExp('[\\u2066-\\u2069\\u200e\\u200f\\u061c]'), '');

  String money(String cur, int minor, String lang) => clean(
    trimZeroFraction(
      MoneyFormat.format(
        Money(Currency.of(cur), minor),
        languageCode: lang,
        digits: DigitsMode.resolve(DigitsPref.auto, lang),
        hidden: false,
      ),
    ),
  );

  List<String> semanticsLabels(WidgetTester t) {
    final out = <String>[];
    void walk(SemanticsNode n) {
      if (n.label.isNotEmpty) out.add(clean(n.label));
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    final root = t.binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;
    if (root != null) walk(root);
    return out;
  }

  String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  int epochDayOf(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

  testWidgets('SMS month story: saved transactions and Insights numbers', (
    t,
  ) async {
    expect(_scenarioJson, isNotEmpty, reason: 'SCENARIO_JSON dart-define');
    final scenario = Scenario.parse(_scenarioJson);
    final now = DateTime.now();
    final semantics = t.ensureSemantics();

    // ---- seed: installed today, English, amounts shown
    final dir = await resolveDbDirectory();
    final seed = ProviderContainer(
      overrides: [dbDirectoryProvider.overrideWithValue(dir)],
    );
    final settings = await seed.read(settingsRepositoryProvider.future);
    await settings.set(
      Settings.setupInstalledOn,
      CivilDate(now.year, now.month, now.day).epochDay,
    );
    await settings.set(Settings.language, LanguagePref.en);
    await settings.set(Settings.hideAmountsApp, false);
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

    Future<int> txnCount() async =>
        (await db
                    .customSelect('SELECT COUNT(*) AS n FROM transactions')
                    .getSingle())
                .data['n']!
            as int;

    final smsEntries = [
      for (final e in scenario.entries)
        if (!e.isManual && !e.ignored) e,
    ];
    final pastSms = smsEntries.where((e) => !e.isLive).length;
    final liveSms = smsEntries.where((e) => e.isLive).length;
    say(
      'SCENARIO entries=${scenario.entries.length} pastSms=$pastSms '
      'liveSms=$liveSms ignored=${scenario.entries.where((e) => e.ignored).length}',
    );

    // ---- 1a. the first-run scan: the past messages
    final scan = await c.read(inboxScanServiceProvider.future);
    check(scan != null, 'the inbox scan service exists');
    await scan?.startFirstRun();
    final pastOk = await waitUntil(t, () async => await txnCount() >= pastSms);
    say('PAST saved=${await txnCount()} of $pastSms (ok=$pastOk)');

    // ---- 1b. the live messages
    say('READY_FOR_LIVE');
    final liveOk = await waitUntil(
      t,
      () async => await txnCount() >= pastSms + liveSms,
      timeout: const Duration(seconds: 150),
    );
    say('LIVE saved=${await txnCount()} of ${pastSms + liveSms} (ok=$liveOk)');
    await settle(t, 6000); // late extras (an ignored message that was saved)

    // ---- 1c. the manual cash payment(s)
    final accounts = await c.read(accountsRepositoryProvider.future);
    final txns = await c.read(transactionRepositoryProvider.future);
    for (final e in scenario.entries.where((e) => e.isManual)) {
      final at = e.localAt(now);
      final cash = await accounts.ensureDefaultCash(
        currency: Currency.of(e.currency),
        label: 'Cash',
      );
      await txns.add(
        NewTransaction(
          accountId: cash.id,
          direction: TxnDirection.expense,
          amount: Money(Currency.of(e.currency), e.amountMinor),
          occurredAt: at,
          occurredTzOffsetMin: at.timeZoneOffset.inMinutes,
          categoryId: e.category == null ? null : 'sys:${e.category}',
          merchant: e.merchant,
        ),
      );
    }
    await settle(t, 1000);

    // ---- 2. every entry against the saved transactions
    final rows =
        (await db
                .customSelect(
                  'SELECT id, direction, status, amount_minor, currency, '
                  'category_id, is_internal, merchant_raw, merchant_norm, '
                  'occurred_at, occurred_tz_offset_min FROM transactions '
                  'WHERE deleted_at IS NULL',
                )
                .get())
            .map((r) => r.data)
            .toList();
    final used = <String>{};
    var matched = 0;
    for (final e in scenario.entries) {
      if (e.ignored) continue;
      final at = e.localAt(now);
      final wantDay = epochDayOf(at);
      Map<String, Object?>? hit;
      for (final r in rows) {
        if (used.contains(r['id'])) continue;
        if (r['amount_minor'] != e.amountMinor || r['currency'] != e.currency) {
          continue;
        }
        final day =
            ((r['occurred_at']! as int) +
                (r['occurred_tz_offset_min']! as int) * 60000) ~/
            86400000;
        if (!e.isLive && day != wantDay) continue;
        if (e.isLive && day != epochDayOf(now) && day != epochDayOf(now) - 1) {
          continue;
        }
        hit = r;
        break;
      }
      if (hit == null) {
        check(
          false,
          '${e.id} missing: no transaction for ${e.amountMinor} '
          '${e.currency} on ${ymd(at)}',
        );
        continue;
      }
      used.add(hit['id']! as String);
      matched++;
      final problemsBefore = problems.length;
      check(
        hit['direction'] == e.kind,
        '${e.id} direction expected=${e.kind} actual=${hit['direction']}',
      );
      check(
        hit['status'] == e.status,
        '${e.id} status expected=${e.status} actual=${hit['status']}',
      );
      final wantCat = e.category == null ? null : 'sys:${e.category}';
      check(
        hit['category_id'] == wantCat,
        '${e.id} category expected=$wantCat actual=${hit['category_id']}',
      );
      check(
        (hit['is_internal'] == 1) == e.internal,
        '${e.id} internal expected=${e.internal} actual=${hit['is_internal']}',
      );
      if (e.merchant != null) {
        final got = ((hit['merchant_raw'] ?? hit['merchant_norm']) as String?)
            ?.toLowerCase();
        final alt = (hit['merchant_norm'] as String?)?.toLowerCase();
        final want = e.merchant!.toLowerCase();
        check(
          got == want || alt == want,
          '${e.id} merchant expected=$want actual=$got/$alt',
        );
      }
      if (problems.length == problemsBefore) say('ENTRY_OK ${e.id}');
    }
    final extra = rows.length - used.length;
    say(
      'ENTRIES matched=$matched of ${smsEntries.length + scenario.entries.where((e) => e.isManual).length} '
      'transactions=${rows.length} extra=$extra',
    );
    check(
      extra == 0,
      'ignored messages created $extra unexpected transaction(s)',
    );

    // ---- 3. chart queries against the independent numbers
    final repo = await c.read(chartRepositoryProvider.future);
    repo.invalidate();
    ChartPeriod monthPeriod(int ago) {
      final idx = now.year * 12 + now.month - 1 - ago;
      return ChartPeriod.month(idx ~/ 12, idx % 12 + 1);
    }

    for (final cur in currenciesOf(scenario)) {
      final f = ChartFilter(currency: Currency.of(cur));
      for (var ago = 3; ago >= 0; ago--) {
        final span = monthOf(now, ago);
        final want = expectedFor(
          scenario,
          cur,
          now,
          from: span.from,
          to: span.to,
        );
        final p = monthPeriod(ago);
        final tag = '$cur month-$ago';
        final cf = await repo.cashFlow([p], f);
        if (cf is ChartReady<List<CashFlowPoint>>) {
          final tot = CashFlowPoint.total(cf.data);
          check(
            tot.spend.minor == want.spend,
            '$tag spend expected=${want.spend} actual=${tot.spend.minor}',
          );
          check(
            tot.income.minor == want.income,
            '$tag income expected=${want.income} actual=${tot.income.minor}',
          );
        } else if (want.spend != 0 || want.income != 0) {
          check(false, '$tag cash flow not ready');
        }
        final donut = await repo.categoryDonut(p, f);
        if (donut is ChartReady<CategoryDonut>) {
          final got = {
            for (final s in donut.data.slices) s.categoryId: s.amount.minor,
          };
          final wantCat = {
            for (final e in want.byCategory.entries)
              e.key == null ? null : 'sys:${e.key}': e.value,
          };
          check(
            donut.data.total.minor == want.spend,
            '$tag donut total expected=${want.spend} '
            'actual=${donut.data.total.minor}',
          );
          for (final k in {...got.keys, ...wantCat.keys}) {
            check(
              got[k] == wantCat[k],
              '$tag category $k expected=${wantCat[k]} actual=${got[k]}',
            );
          }
          final wantShare = want.sharesBp();
          for (final s in donut.data.slices) {
            final key = s.categoryId?.replaceFirst('sys:', '');
            check(
              wantShare[key] == s.shareBp,
              '$tag share $key expected=${wantShare[key]} actual=${s.shareBp}',
            );
          }
        } else if (want.spend != 0) {
          check(false, '$tag category donut not ready');
        }
        final daily = await repo.dailySpend(p, f);
        for (var i = 0; i < daily.length; i++) {
          final day = ymd(DateTime(span.from.year, span.from.month, 1 + i));
          check(
            daily[i] == (want.daily[day] ?? 0),
            '$tag day $day expected=${want.daily[day] ?? 0} actual=${daily[i]}',
          );
        }
        final tm = await repo.topMerchants(p, f, limit: 5);
        if (tm is ChartReady<List<MerchantSpend>>) {
          final wantTop = want.topMerchants(5);
          for (var i = 0; i < wantTop.top.length; i++) {
            final got = i < tm.data.length ? tm.data[i] : null;
            check(
              got != null &&
                  got.amount.minor == wantTop.top[i].value &&
                  got.name.toLowerCase().contains(
                    wantTop.top[i].key.split(' ').first,
                  ),
              '$tag merchant #${i + 1} expected=${wantTop.top[i].key}:'
              '${wantTop.top[i].value} actual='
              '${got == null ? 'none' : '${got.name.toLowerCase()}:${got.amount.minor}'}',
            );
          }
          say(
            '$tag merchants other(expected)=${wantTop.other} '
            'income=${want.income} spend=${want.spend}',
          );
        } else if (want.byMerchant.isNotEmpty) {
          check(false, '$tag top merchants not ready');
        }
      }
    }

    // ---- 4. the screens, English then Arabic, last month
    await c
        .read(chartPeriodSelectionProvider.notifier)
        .select(const ChartPeriodSelection(ChartPreset.lastMonth));
    final lastMonth = monthOf(now, 1);
    final cats = await db
        .customSelect('SELECT id, name_en, name_ar FROM categories')
        .get();
    String catName(String? id, String lang) {
      for (final r in cats) {
        if (r.data['id'] == (id == null ? 'sys:other' : 'sys:$id')) {
          return (lang == 'ar' ? r.data['name_ar'] : r.data['name_en'])!
              as String;
        }
      }
      return id ?? '';
    }

    for (final lang in ['en', 'ar']) {
      await settings.set(
        Settings.language,
        lang == 'en' ? LanguagePref.en : LanguagePref.ar,
      );
      await go(t, AppRoutes.insights);
      await settle(t, 1500);
      final l = AppLocalizations.of(rootNavigatorKey.currentContext!);
      final egp = expectedFor(
        scenario,
        'EGP',
        now,
        from: lastMonth.from,
        to: lastMonth.to,
      );
      final tag = 'ui $lang';

      // Overview: the hero spend
      await t.tap(find.text(l.insightsV2TabOverview).first);
      await settle(t, 1500);
      final hero = find.byKey(const Key('hero-spent'));
      if (safeFound(hero)) {
        final shown = clean((t.widget(hero) as Text).data ?? '');
        check(
          shown == money('EGP', egp.spend, lang),
          '$tag overview hero expected=${money('EGP', egp.spend, lang)} '
          'actual=$shown',
        );
      } else {
        check(false, '$tag overview hero not found');
      }
      var labels = semanticsLabels(t);
      for (final top
          in (egp.byCategory.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .take(3)) {
        final want =
            '${catName(top.key, lang)}: ${money('EGP', top.value, lang)}';
        check(
          labels.any((x) => x.contains(want)),
          '$tag overview row expected="$want"',
        );
      }
      // Saved each month: the bars of the three closed months
      for (var ago = 1; ago <= 3; ago++) {
        final span = monthOf(now, ago);
        final m = expectedFor(
          scenario,
          'EGP',
          now,
          from: span.from,
          to: span.to,
        );
        final amt = money('EGP', m.saved.abs(), lang);
        check(
          labels.any((x) => x.contains(': $amt') || x.contains(amt)),
          '$tag saved bar month-$ago expected=$amt',
        );
      }
      await shot(t, 'scn-$lang-1-overview');

      // Categories
      await t.tap(find.text(l.insightsV2TabCategories).first);
      await settle(t, 1500);
      labels = semanticsLabels(t);
      for (final e in egp.byCategory.entries) {
        final want = '${catName(e.key, lang)}: ${money('EGP', e.value, lang)}';
        check(
          labels.any((x) => x.contains(want)),
          '$tag categories row expected="$want"',
        );
      }
      await shot(t, 'scn-$lang-2-categories');

      // Trends: three sample days of the heatmap
      await t.tap(find.text(l.insightsV2TabTrends).first);
      await settle(t, 1500);
      for (final day in [3, 5, 7]) {
        final d = DateTime(lastMonth.from.year, lastMonth.from.month, day);
        final key = find.byKey(Key('heat-${ymd(d)}'));
        try {
          await t.scrollUntilVisible(
            key,
            200,
            scrollable: find.byType(Scrollable).first,
          );
        } on Object {
          // not scrollable or already visible
        }
        await settle(t, 300);
        final want = money('EGP', egp.daily[ymd(d)] ?? 0, lang);
        if (!safeFound(key)) {
          check(false, '$tag heatmap day ${ymd(d)} cell not found');
          continue;
        }
        final label = clean(t.getSemantics(key).label);
        check(
          label.contains(want),
          '$tag heatmap day ${ymd(d)} expected=$want',
        );
      }
      await shot(t, 'scn-$lang-3-trends');
    }

    // ---- 5. Home's recent list shows the live ones
    await settings.set(Settings.language, LanguagePref.en);
    await go(t, AppRoutes.home);
    await settle(t, 1500);
    for (final e in scenario.entries.where((e) => e.isLive && !e.ignored)) {
      final name = e.merchant!.toLowerCase();
      final hit = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').toLowerCase().contains(name),
      );
      check(safeFound(hit), '${e.id} not in the Home recent list ($name)');
    }
    await shot(t, 'scn-en-4-home');

    say('RESULT problems=${problems.length}');
    semantics.dispose();
    FlutterError.onError = original;
    expect(problems, isEmpty, reason: problems.join('; '));
  });
}
