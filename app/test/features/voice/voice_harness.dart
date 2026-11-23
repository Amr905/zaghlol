// T-120: fakes and pump helper for the S-31 tests. Synthetic data only.

import 'package:flutter/material.dart';
import 'package:zaghlol/core/settings/setting_key.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/settings/settings_keys.dart' show DigitsPref;
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/presentation/edit/txn_edit_providers.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol/features/voice/application/speech_port.dart';
import 'package:zaghlol/features/voice/application/voice_models.dart';
import 'package:zaghlol/features/voice/application/voice_providers.dart';
import 'package:zaghlol/features/voice/presentation/voice_logger_screen.dart';

import '../transactions/presentation/detail_edit_harness.dart';
import '../transactions/presentation/list/list_harness.dart';
import '../../support/hide_amounts_support.dart';

const voiceLookups = TxnLookups(
  categories: [
    TxnCategory(
      id: 'sys:groceries',
      nameAr: 'خزين البيت',
      nameEn: 'Groceries',
      icon: '🛒',
      color: '#0F7A55',
    ),
    TxnCategory(
      id: 'sys:dining',
      nameAr: 'أكل بره',
      nameEn: 'Dining',
      icon: '🍔',
      color: '#0F7A55',
    ),
    TxnCategory(
      id: 'sys:transport',
      nameAr: 'مواصلات',
      nameEn: 'Transport',
      icon: '🚗',
      color: '#0F7A55',
    ),
  ],
  accounts: [
    TxnAccount(id: 'cash', label: 'Cash', currencyCode: 'EGP'),
    TxnAccount(id: 'usd', label: 'Dollar', currencyCode: 'USD'),
  ],
);

/// A scripted recognizer: [start] returns [startError] or begins a session
/// the test drives with [say] / [end] / [fail].
class FakeSpeech implements SpeechPort {
  FakeSpeech({this.startError, this.onDeviceSupported = true});

  /// What the host reports for on-device recognition.
  bool onDeviceSupported;

  @override
  Future<bool> supportsOnDevice(String localeId) async => onDeviceSupported;

  /// Per-call outcome of `start` (first element used for the first call).
  final List<SpeechError?> startErrors = [];
  SpeechError? startError;
  final List<bool> onDeviceCalls = [];
  int cancels = 0;
  int stops = 0;
  SpeechSink? sink;

  @override
  Future<SpeechError?> start({
    required String localeId,
    required bool onDevice,
    required SpeechSink sink,
    required Duration pauseFor,
    required Duration listenFor,
  }) async {
    onDeviceCalls.add(onDevice);
    this.sink = sink;
    if (startErrors.isNotEmpty) return startErrors.removeAt(0);
    return startError;
  }

  void say(String text, {bool isFinal = false}) =>
      sink!.onText(text, isFinal: isFinal);
  void end() => sink!.onEnded();
  void fail(SpeechError e) => sink!.onError(e);

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}

/// Real parser, keyword categories (the shared categorizer has its own tests).
class TestInterpreter implements VoiceInterpreter {
  @override
  Future<List<VoiceDraft>> interpret(String text, Currency currency) async {
    final r = parseVoicePhrase(text, defaultCurrency: currency);
    if (r is! VoiceParsed) return const [];
    String? cat(String t) {
      if (t.contains('خضار') || t.contains('vegetables')) {
        return 'sys:groceries';
      }
      if (t.contains('قهوة') || t.contains('coffee')) return 'sys:dining';
      if (t.contains('تاكسي') || t.contains('taxi')) return 'sys:transport';
      return null;
    }

    return [
      for (var i = 0; i < r.items.length; i++)
        VoiceDraft(
          key: i,
          text: r.items[i].text,
          amount: r.items[i].amount,
          categoryId: cat(r.items[i].matchText),
          issues: r.items[i].issues,
        ),
    ];
  }
}

class FakeUsage implements VoiceUsagePort {
  FakeUsage(this.count);
  int count;
  int counted = 0;
  int attempts = 0;
  bool failFirstCount = false;

  @override
  Future<int> countThisMonth() async => count;

  @override
  Future<void> countOne() async {
    attempts++;
    if (failFirstCount && attempts == 1) throw StateError('counter');
    count++;
    counted++;
  }
}

class VoiceRig {
  VoiceRig({
    int used = 0,
    this.gold = false,
    FakeSpeech? speech,
    FakeEditor? editor,
    this.lookups = voiceLookups,
  }) : speech = speech ?? FakeSpeech(),
       editor = editor ?? FakeEditor(),
       usage = FakeUsage(used);

  final FakeSpeech speech;
  final FakeEditor editor;
  final FakeUsage usage;
  final bool gold;
  final TxnLookups lookups;
  int paywall = 0;
  int settings = 0;

  /// In-memory settings, so the remembered consent (T-214) can be checked.
  final hide = HideAmountsHarness();
  late final repo = _RigRepo(hide);

  List<Override> get overrides => [
    ...hide.overrides,
    speechPortProvider.overrideWithValue(speech),
    voiceInterpreterProvider.overrideWith((ref) async => TestInterpreter()),
    voiceUsageProvider.overrideWith((ref) async => usage),
    transactionEditorProvider.overrideWith((ref) async => editor),
    txnLookupsProvider.overrideWith((ref) async => lookups),
    defaultCashAccountIdProvider.overrideWith((ref) async => 'cash'),
    paydayScheduleProvider.overrideWith(
      (ref) async => PaydaySchedule.single(1),
    ),
    todayProvider.overrideWith(FixedToday.new),
    clockProvider.overrideWithValue(() => now),
    localZoneProvider.overrideWithValue(const FixedZone()),
    digitsModeProvider.overrideWith(
      (ref, lang) => DigitsMode.resolve(DigitsPref.auto, lang),
    ),
    paywallTriggerProvider.overrideWithValue((_) => paywall++),
    voiceOpenSettingsProvider.overrideWithValue(() async => settings++),
  ];

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    // T-099: the listening mascot loops while the mic is open; these tests
    // settle, so they run with reduce motion (still pose).
    container.read(reduceMotionProvider.notifier).set(true);
    if (gold) {
      container
          .read(entitlementStateProvider.notifier)
          .applyVerified(verified: true, status: 'active');
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ZaghlolTheme.light,
          darkTheme: ZaghlolTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showVoiceLogger(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
}

/// Reads and writes the rig's fake settings (see HideAmountsHarness).
class _RigRepo {
  _RigRepo(this._h);
  final HideAmountsHarness _h;
  Future<T> get<T>(SettingKey<T> k) async =>
      _h.writes.containsKey(k.name) ? _h.writes[k.name] as T : k.defaultValue;
  Future<void> set<T>(SettingKey<T> k, T v) async => _h.writes[k.name] = v;
}
