import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/home/application/home_cards.dart';
import 'package:zaghlol/features/home/presentation/cards/home_cards_view.dart';
import 'package:zaghlol/features/onboarding/application/contextual.dart';
import 'package:zaghlol/features/security/domain/app_lock_controller.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

class FakeCardActions implements HomeCardActions {
  final calls = <String>[];
  EnableLockResult lockResult = EnableLockResult.enabled;

  @override
  Future<void> handle(SetupSuggestionKind kind) async =>
      calls.add('handle:${kind.slug}');

  @override
  Future<void> acceptPayday(int day) async => calls.add('payday:$day');

  @override
  Future<EnableLockResult> enableAppLock(String reason) async {
    calls.add('lock');
    return lockResult;
  }
}

Future<void> pumpCards(
  WidgetTester tester, {
  required Locale locale,
  required HomeCards cards,
  required FakeCardActions actions,
  bool hasTransactions = true,
  bool dark = false,
  double textScale = 1.0,
  VoidCallback? openSetBudget,
  VoidCallback? openBackup,
  VoidCallback? openFinishSetup,
}) async {
  await initDateFormatting();
  await tester.binding.setSurfaceSize(const Size(390, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeCardsProvider(hasTransactions).overrideWith((ref) async => cards),
        homeCardActionsProvider.overrideWithValue(actions),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: dark ? ZaghlolTheme.dark : ZaghlolTheme.light,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: HomeContextualCards(
                hasTransactions: hasTransactions,
                openSetBudget: openSetBudget,
                openBackup: openBackup,
                openFinishSetup: openFinishSetup,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

final salary = Money(Currency.of('EGP'), 3200000);
const allCards = HomeCards(
  suggestion: SetupSuggestion(SetupSuggestionKind.budget),
  offerAppLock: true,
  stepsLeft: 2,
);
