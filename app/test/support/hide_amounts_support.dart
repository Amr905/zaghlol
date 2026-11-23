// T-187: widget tests that need the hide-amounts setting without a database.
// [HideAmountsHarness] backs `hide_amounts.app` with a stream, and records the
// writes the eye button makes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ui/z_money_text.dart';
import 'package:zaghlol/core/settings/setting_key.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';

class _Repo implements SettingsRepository {
  _Repo(this._harness);
  final HideAmountsHarness _harness;

  @override
  Future<void> set<T>(SettingKey<T> key, T value) async {
    _harness.writes[key.name] = value;
    if (key.name == Settings.hideAmountsApp.name) {
      _harness.value = value as bool;
    }
  }

  @override
  Future<T> get<T>(SettingKey<T> key) async {
    // Only the voice consent (T-214) is readable; other reads stay
    // unsupported, as before, so unrelated features keep their old paths.
    if (key.name != Settings.voiceOnlineConsent.name) {
      throw UnimplementedError(key.name);
    }
    return _harness.writes.containsKey(key.name)
        ? _harness.writes[key.name] as T
        : key.defaultValue;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HideAmountsHarness {
  HideAmountsHarness({bool hidden = false}) : _value = hidden;

  bool _value;

  /// Every setting written through the fake repository, by key name.
  final writes = <String, Object?>{};
  final _controller = StreamController<bool>.broadcast();

  bool get value => _value;
  set value(bool v) {
    _value = v;
    _controller.add(v);
  }

  /// Providers to put in a `ProviderScope`.
  List<Override> get overrides => [
    hideAmountsAppProvider.overrideWith((ref) async* {
      yield _value;
      yield* _controller.stream;
    }),
    settingsRepositoryProvider.overrideWith((ref) async => _Repo(this)),
  ];

  Future<void> dispose() => _controller.close();
}

/// Overrides that read as "amounts shown" without a database; for tests of
/// screens that are not about hiding.
List<Override> amountsShown() => HideAmountsHarness().overrides;

final _digitRe = RegExp(r'[0-9٠-٩]');

/// Strings of every amount widget on screen: `ZMoneyText` and any `Text` that
/// carries a currency or a gold unit.
List<String> amountStrings(WidgetTester tester) => [
  for (final w in tester.widgetList<ZMoneyText>(find.byType(ZMoneyText)))
    '${w.text} ${w.unit ?? ''}',
  for (final w in tester.widgetList<Text>(find.byType(Text)))
    if (RegExp(r'EGP|USD|ج\.م|جم\b|\bg\b|جرام|عملة|coin')
        .hasMatch(w.data ?? w.textSpan?.toPlainText() ?? ''))
      w.data ?? w.textSpan!.toPlainText(),
];

/// Fails when an amount widget shows a digit (percentages may stay).
/// A karat label is not an amount; [allowLines] names public constants (the
/// nisab threshold) that may keep their digits.
Future<void> expectNoAmountDigits(
  WidgetTester tester, {
  RegExp? allowLines,
}) async {
  await expectNoMaskGlyphInSemantics(tester);
  final amounts = amountStrings(tester);
  expect(amounts, isNotEmpty, reason: 'the screen shows amounts');
  for (final a in amounts) {
    if (allowLines != null && allowLines.hasMatch(a)) continue;
    final noPct = a
        .replaceAll(RegExp(r'[0-9٠-٩]+(?:[.٫][0-9٠-٩]+)?\s*[%٪]'), '')
        .replaceAll(RegExp(r'[0-9٠-٩]+\s*K\b'), '')
        .replaceAll(RegExp(r'[A-Za-z]{3,9} [0-9]{1,2}, [0-9]{4}'), '')
        .replaceAll(RegExp(r'[0-9٠-٩]{1,2} \S+ [0-9٠-٩]{4}'), '')
        .replaceAll(RegExp(r'عيار\s*[0-9٠-٩]+'), '');
    expect(_digitRe.hasMatch(noPct), isFalse, reason: 'amount widget: $a');
  }
}

/// A screen reader says "amount hidden", never the `****` glyphs (AC 7).
Future<void> expectNoMaskGlyphInSemantics(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  // Turning semantics on needs a frame that re-lays out the tree.
  await tester.pumpAndSettle();
  final labels = <String>[];
  void walk(SemanticsNode n) {
    labels
      ..add(n.label)
      ..add(n.value)
      ..add(n.tooltip);
    n.visitChildren((SemanticsNode c) {
      walk(c);
      return true;
    });
  }

  walk(tester.getSemantics(find.byType(MaterialApp)));
  handle.dispose();
  expect(
    labels.where((l) => l.isNotEmpty),
    isNotEmpty,
    reason: 'semantics tree read',
  );
  final bad = {
    for (final l in labels)
      if (l.contains('****')) l,
  };
  expect(bad, isEmpty, reason: 'semantics label with the mask glyphs');
}
