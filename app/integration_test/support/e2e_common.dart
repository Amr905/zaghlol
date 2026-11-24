// T-238: shared helpers of the E2E device tests (export, language and digits,
// app lock, delete everything). They drive the REAL app (`main()`, real
// providers, real encrypted database) on the Android emulator. Synthetic data
// only; nothing here prints a message body or an amount.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/core/ui/shell/app_shell.dart' show ZBottomBar;
import 'package:zaghlol_domain/zaghlol_domain.dart';

class E2e {
  E2e(this.tag)
    : binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Log prefix and screenshot prefix, e.g. `E2E09`.
  final String tag;
  final IntegrationTestWidgetsFlutterBinding binding;
  final List<String> problems = [];
  final List<String> flutterErrors = [];
  bool _surfaceConverted = false;
  void Function(FlutterErrorDetails)? _original;

  void say(String line) {
    // ignore: avoid_print
    print('$tag $line');
  }

  void check(bool ok, String what) {
    if (!ok) {
      problems.add(what);
      say('PROBLEM $what');
    }
  }

  /// Every FlutterError (overflows included) is recorded; the test fails at
  /// the end through [finish]. Only the first line of each is kept.
  void captureFlutterErrors() {
    _original = FlutterError.onError;
    _captured = true;
    FlutterError.onError = (d) {
      final first = d.exceptionAsString().split('\n').first;
      final line =
          '${d.exception.runtimeType}: ${first.length > 140 ? first.substring(0, 140) : first}';
      flutterErrors.add(line);
      say('FLUTTER_ERROR $line');
    };
  }

  void releaseFlutterErrors() {
    if (_captured) FlutterError.onError = _original;
    _captured = false;
  }

  bool _captured = false;
  SemanticsHandle? _semantics;

  /// Runs [body] with semantics on; always gives the FlutterError handler and
  /// the semantics handle back, so a failing step reports its own error (and
  /// the test process ends) instead of a framework assertion about them.
  Future<void> guarded(WidgetTester t, Future<void> Function() body) async {
    _semantics = t.ensureSemantics();
    try {
      await body();
    } finally {
      releaseFlutterErrors();
      _semantics?.dispose();
      _semantics = null;
    }
  }

  Future<void> settle(WidgetTester t, [int ms = 800]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  bool found(Finder f) {
    try {
      return f.evaluate().isNotEmpty;
    } on TypeError {
      return false;
    }
  }

  Future<void> waitFor(
    WidgetTester t,
    Finder f, {
    Duration timeout = const Duration(seconds: 30),
    String? what,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
      if (found(f)) return;
    }
    fail('timed out waiting for ${what ?? f}');
  }

  Future<void> waitGone(
    WidgetTester t,
    Finder f, {
    Duration timeout = const Duration(seconds: 30),
    String? what,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
      if (!found(f)) return;
    }
    fail('timed out waiting for ${what ?? f} to go');
  }

  Future<void> shot(WidgetTester t, String name) async {
    try {
      if (!_surfaceConverted && Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        _surfaceConverted = true;
      }
      await settle(t, 400);
      final bytes = await binding.takeScreenshot('$tag-$name');
      final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/ci_screens',
      );
      await dir.create(recursive: true);
      await File('${dir.path}/$tag-$name.png').writeAsBytes(bytes);
      say('SHOT $name');
    } on Object catch (e) {
      say('SHOT_FAILED $name ${e.runtimeType}');
    }
  }

  ProviderContainer container() =>
      ProviderScope.containerOf(rootNavigatorKey.currentContext!);

  /// A returning user: the first-run marker is written through the app's own
  /// providers and the real database, so onboarding (system permission
  /// dialogs) is skipped.
  Future<void> seedReturningUser({
    LanguagePref language = LanguagePref.en,
    DigitsPref digits = DigitsPref.western,
  }) async {
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
    await settings.set(Settings.language, language);
    await settings.set(Settings.digits, digits);
    await (await seed.read(appDatabaseProvider.future)).close();
    seed.dispose();
    say('SEEDED settings');
  }

  /// Adds expenses of [amountsMinor] EGP through the running app's own
  /// providers (after `app.main()`).
  Future<void> addTransactions(List<int> amountsMinor) async {
    final c = container();
    final accounts = await c.read(accountsRepositoryProvider.future);
    final txns = await c.read(transactionRepositoryProvider.future);
    final cash = await accounts.ensureDefaultCash(
      currency: Currency.of('EGP'),
      label: 'Cash',
    );
    for (var i = 0; i < amountsMinor.length; i++) {
      final at = DateTime.now().subtract(Duration(minutes: 5 + i));
      await txns.add(
        NewTransaction(
          accountId: cash.id,
          direction: TxnDirection.expense,
          amount: Money(Currency.of('EGP'), amountsMinor[i]),
          occurredAt: at,
          occurredTzOffsetMin: at.timeZoneOffset.inMinutes,
          merchant: 'TEST SHOP ${String.fromCharCode(65 + i)}',
        ),
      );
    }
    say('SEEDED transactions=${amountsMinor.length}');
  }

  /// Selects tab [i] (0 Home, 1 Money, 2 Insights, 3 Zaghlol) as a tap does.
  Future<void> selectTab(WidgetTester t, int i) async {
    final bar = find.byType(ZBottomBar);
    await waitFor(t, bar, what: 'the tab bar');
    t.widget<ZBottomBar>(bar.first).onSelect(i);
    await settle(t, 1200);
  }

  /// Fails when [problems] or [flutterErrors] is not empty.
  void finish() {
    releaseFlutterErrors();
    say(
      'SUMMARY problems=${problems.length} flutterErrors=${flutterErrors.length}',
    );
    expect(problems, isEmpty, reason: problems.join(' | '));
    expect(flutterErrors, isEmpty, reason: flutterErrors.take(5).join(' | '));
  }
}
