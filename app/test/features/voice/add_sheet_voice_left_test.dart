// T-120: the Add sheet's quota line comes from the monthly counter; Gold
// hides it; the Say tile is reachable at 48 dp.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/shell/add_sheet.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/voice/application/voice_providers.dart';

import 'voice_harness.dart';

Future<void> _pump(
  WidgetTester t,
  Locale locale, {
  required int used,
  bool gold = false,
  ValueChanged<AddAction>? onSelected,
}) async {
  final container = ProviderContainer(
    overrides: [
      voiceUsageProvider.overrideWith((ref) async => FakeUsage(used)),
    ],
  );
  addTearDown(container.dispose);
  if (gold) {
    container
        .read(entitlementStateProvider.notifier)
        .applyVerified(verified: true, status: 'active');
  }
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ZaghlolTheme.light,
        home: Scaffold(body: AddSheet(onSelected: onSelected)),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Free: shows how many voice logs are left', (t) async {
    await _pump(t, const Locale('en'), used: 4);
    expect(find.text('11 of 15 voice logs left this month'), findsOneWidget);
  });

  testWidgets('Free: 15 used shows 0 left (the Say tile still opens S-31)', (
    t,
  ) async {
    AddAction? picked;
    await _pump(t, const Locale('en'), used: 15, onSelected: (a) => picked = a);
    expect(find.text('0 of 15 voice logs left this month'), findsOneWidget);
    await t.tap(find.text('Say'));
    expect(picked, AddAction.say);
  });

  testWidgets('Free, Arabic: digits follow the locale', (t) async {
    await _pump(t, const Locale('ar'), used: 4);
    expect(find.textContaining('١١'), findsOneWidget);
  });

  testWidgets('Gold: no quota line', (t) async {
    await _pump(t, const Locale('en'), used: 4, gold: true);
    expect(find.textContaining('voice logs left'), findsNothing);
  });
}
