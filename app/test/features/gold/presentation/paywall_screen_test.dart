import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/gold/domain/purchase_outcome.dart';
import 'package:zaghlol/features/gold/domain/restore_outcome.dart';
import 'package:zaghlol/features/gold/presentation/gold_messages.dart';
import 'package:zaghlol/features/gold/presentation/gold_ui_ports.dart';
import 'package:zaghlol/features/gold/presentation/paywall_launcher.dart';
import 'package:zaghlol/features/gold/presentation/paywall_screen.dart';
import 'package:zaghlol/features/gold/presentation/upsell_cap.dart';

import 'gold_ui_harness.dart';

AppLocalizations tr(String lang) => lookupAppLocalizations(Locale(lang));

final DateTime next = DateTime.utc(2026, 12, 5, 9);

Future<void> main() async {
  await initDateFormatting();

  for (final lang in ['en', 'ar']) {
    final t = tr(lang);
    group('paywall $lang', () {
      testWidgets(
        'ready: store prices only, yearly preselected, renewal line',
        (tester) async {
          final a = FakeGoldActions();
          await pumpGold(
            tester,
            goldApp(
              const PaywallScreen(),
              overrides: goldOverrides(a),
              lang: lang,
              scale: 1.3,
            ),
          );
          expect(find.textContaining('399.99'), findsOneWidget);
          expect(find.textContaining('49.99'), findsOneWidget);
          expect(find.textContaining('899.99'), findsOneWidget);
          expect(find.text(t.goldPaywallBestValue), findsOneWidget);
          expect(find.text(t.goldPaywallRenewalSummary), findsOneWidget);
          expect(find.text(t.goldPaywallRenewal('android')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(t.goldPaywallContinue));
          await tester.pump();
          expect(a.bought, [GoldPlan.yearly]);
          expect(find.text(t.goldPaywallPurchasing), findsOneWidget);
        },
      );

      testWidgets('lifetime shows the one-payment note, no renewal', (
        tester,
      ) async {
        final a = FakeGoldActions();
        await pumpGold(
          tester,
          goldApp(
            const PaywallScreen(),
            overrides: goldOverrides(a),
            lang: lang,
          ),
        );
        await tester.tap(find.textContaining('899.99'));
        await tester.pump();
        expect(find.text(t.goldPaywallLifetimeNote), findsOneWidget);
        expect(find.text(t.goldPaywallRenewalSummary), findsNothing);
      });

      testWidgets('loading skeleton then failure with retry', (tester) async {
        final a = FakeGoldActions();
        final c = Completer<List<GoldPlanOffer>>();
        await pumpGold(
          tester,
          goldApp(
            const PaywallScreen(),
            overrides: goldOverrides(a, offerLoader: () => c.future),
            lang: lang,
          ),
        );
        expect(find.text(t.goldPaywallPricesLoading), findsWidgets);
        c.completeError(StateError('x'));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldPaywallPricesFailed), findsOneWidget);
        expect(find.text(t.commonActionTryAgain), findsOneWidget);
        expect(find.text(t.goldPaywallContinue), findsNothing);
      });

      final outcomes = <String, (PurchaseOutcome, String Function())>{
        'pending': (const PurchasePending(), () => t.goldPaywallPending),
        'queued': (const PurchaseQueued(), () => t.goldPaywallVerifyOffline),
        'invalid': (const PurchaseInvalid(), () => t.goldPaywallInvalid),
        'notOwned': (const PurchaseNotOwned(), () => t.goldPaywallInvalid),
        'cancelled': (const PurchaseCancelled(), () => t.goldPaywallCancelled),
      };
      for (final e in outcomes.entries) {
        testWidgets('outcome ${e.key}', (tester) async {
          final a = FakeGoldActions();
          await pumpGold(
            tester,
            goldApp(
              const PaywallScreen(),
              overrides: goldOverrides(a),
              lang: lang,
            ),
          );
          a.ctl.add(e.value.$1);
          await tester.pump();
          await tester.pump();
          expect(find.text(e.value.$2()), findsOneWidget);
          expect(find.byType(PaywallScreen), findsOneWidget);
        });
      }

      testWidgets('seat held elsewhere with a date, and with accountRequired', (
        tester,
      ) async {
        final a = FakeGoldActions();
        await pumpGold(
          tester,
          goldApp(
            const PaywallScreen(),
            overrides: goldOverrides(a, signIn: () {}),
            lang: lang,
          ),
        );
        a.ctl.add(
          PurchaseSeatHeldElsewhere(accountRequired: false, nextMoveAt: next),
        );
        await tester.pump();
        await tester.pump();
        final date = ZDateFormat.date(
          next,
          lang,
          DigitsMode.resolve(DigitsPref.auto, lang),
        );
        expect(find.text(t.goldSeatHeldElsewhere(date)), findsOneWidget);
        a.ctl.add(const PurchaseSeatHeldElsewhere(accountRequired: true));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldSeatHeldElsewhereAccount), findsOneWidget);
        expect(find.text(t.commonActionSignIn), findsOneWidget);
      });

      testWidgets('gold success closes the paywall with true', (tester) async {
        final a = FakeGoldActions();
        bool? result;
        await pumpGold(
          tester,
          goldApp(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await Navigator.of(context)
                    .push<bool>(
                      MaterialPageRoute(builder: (_) => const PaywallScreen()),
                    ),
                child: const Text('open'),
              ),
            ),
            overrides: goldOverrides(a),
            lang: lang,
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        a.ctl.add(const PurchaseGold());
        await tester.pumpAndSettle();
        expect(result, isTrue);
      });

      testWidgets('restore: nothing, cooldown, account required, attestation', (
        tester,
      ) async {
        final a = FakeGoldActions();
        await pumpGold(
          tester,
          goldApp(
            const PaywallScreen(),
            overrides: goldOverrides(a, signIn: () {}),
            lang: lang,
          ),
        );
        await tester.tap(find.text(t.goldPaywallRestore));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldAccountRestoreNone), findsOneWidget);

        a.restoreResult = RestoreMoveCooldown(nextMoveAt: next);
        await tester.tap(find.text(t.goldPaywallRestore));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldSeatCooldownTitle), findsOneWidget);
        expect(find.text(t.commonActionContactSupport), findsOneWidget);
        expect(find.text(t.commonSupportCodeLabel), findsOneWidget);

        a.restoreResult = const RestoreAccountRequired();
        await tester.tap(find.text(t.goldPaywallRestore));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldSeatAccountRequiredBody), findsOneWidget);

        a.restoreResult = const RestoreAttestationHelp();
        await tester.tap(find.text(t.goldPaywallRestore));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldSeatAttestBody), findsOneWidget);
        expect(find.text(t.commonActionSignIn), findsOneWidget);
        expect(a.restores, 4);
      });

      testWidgets('already Gold shows the plan and Manage', (tester) async {
        final a = FakeGoldActions();
        final links = <GoldLink>[];
        await pumpGold(
          tester,
          goldApp(
            const PaywallScreen(),
            overrides: goldOverrides(
              a,
              phase: EntitlementPhase.active,
              info: const GoldStatusInfo(plan: GoldPlan.yearly),
              onLink: links.add,
            ),
            lang: lang,
          ),
        );
        expect(find.text(t.goldPaywallAlreadyGold('yearly')), findsOneWidget);
        expect(find.text(t.goldPaywallContinue), findsNothing);
        await tester.tap(find.text(t.commonActionManage));
        expect(links, [GoldLink.manageSubscription]);
      });
    });
  }

  group('status messages', () {
    for (final lang in ['en', 'ar']) {
      final t = tr(lang);
      final cases =
          <
            String,
            (EntitlementPhase, MovedBy?, String Function(), bool support)
          >{
            'movedUser': (
              EntitlementPhase.moved,
              MovedBy.user,
              () => t.goldSeatMovedUserBody,
              false,
            ),
            'movedSupport': (
              EntitlementPhase.moved,
              MovedBy.support,
              () => t.goldSeatMovedSupportBody,
              true,
            ),
            'paused': (
              EntitlementPhase.paused,
              null,
              () => t.goldSeatPausedBody,
              false,
            ),
            'tampered': (
              EntitlementPhase.tampered,
              null,
              () => t.goldSeatTamperedBody,
              false,
            ),
          };
      for (final e in cases.entries) {
        testWidgets('${e.key} $lang', (tester) async {
          final a = FakeGoldActions();
          await pumpGold(
            tester,
            goldApp(
              const PaywallScreen(),
              overrides: goldOverrides(
                a,
                phase: e.value.$1,
                movedBy: e.value.$2,
                signIn: () {},
              ),
              lang: lang,
              scale: 1.3,
            ),
          );
          expect(find.text(e.value.$3()), findsOneWidget);
          expect(
            find.text(t.commonActionContactSupport),
            e.value.$4 ? findsOneWidget : findsNothing,
          );
          if (e.key == 'movedUser') {
            expect(find.text(t.goldSeatRestoreAction), findsNWidgets(2));
            expect(find.text(t.commonActionSignIn), findsOneWidget);
          }
          if (e.key == 'paused') {
            expect(find.text(t.commonActionSignIn), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('support notice', () {
    testWidgets('shows once; dismiss removes it and it does not return', (
      tester,
    ) async {
      final t = tr('en');
      final a = FakeGoldActions()..noticePending = true;
      final overrides = goldOverrides(a);
      await pumpGold(
        tester,
        goldApp(const PaywallScreen(), overrides: overrides),
      );
      expect(find.text(t.goldSeatSupportNoticeBody), findsOneWidget);
      expect(find.text(t.commonActionContactSupport), findsOneWidget);
      await tester.tap(find.text(t.commonActionDismiss));
      await tester.pump();
      await tester.pump();
      expect(a.dismissals, 1);
      expect(find.text(t.goldSeatSupportNoticeBody), findsNothing);
      // A rebuild of the same screen does not bring it back.
      await pumpGold(
        tester,
        goldApp(const PaywallScreen(), overrides: overrides),
      );
      expect(find.text(t.goldSeatSupportNoticeBody), findsNothing);
    });
  });

  group('no money or account details (EC-65)', () {
    testWidgets('message cards carry no digits besides date and code', (
      tester,
    ) async {
      final t = tr('en');
      for (final k in GoldMessageKind.values) {
        await pumpGold(
          tester,
          goldApp(
            Scaffold(body: GoldMessageCard(message: GoldMessage(k))),
            overrides: goldOverrides(FakeGoldActions()),
          ),
        );
        expect(find.textContaining('@'), findsNothing);
        expect(find.textContaining('EGP'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data != 'abc-123' &&
                RegExp(r'\d').hasMatch(w.data ?? ''),
          ),
          findsNothing,
          reason: '$k',
        );
      }
      expect(t.goldSeatPausedBody, isNotEmpty);
    });
  });

  group('message mapping', () {
    test('restore and purchase outcomes', () {
      expect(
        GoldMessage.fromRestore(
          const RestoreTryLater(playServicesOutdated: true),
        )?.kind,
        GoldMessageKind.attestPlayServices,
      );
      expect(GoldMessage.fromRestore(const RestoreFailed()), isNull);
      expect(
        GoldMessage.fromPurchase(
          const PurchaseSeatHeldElsewhere(accountRequired: true),
        )?.kind,
        GoldMessageKind.heldElsewhereAccount,
      );
      expect(GoldMessage.fromPurchase(const PurchaseGold()), isNull);
    });
  });

  group('upsell cap (A-22)', () {
    test('one unsolicited prompt per week, never for Gold', () async {
      var now = DateTime.utc(2026, 11, 1);
      final cap = UpsellCap(MemoryUpsellCapStore(), () => now);
      expect(await cap.tryShow(isGold: false), isTrue);
      now = now.add(const Duration(days: 6));
      expect(await cap.tryShow(isGold: false), isFalse);
      now = now.add(const Duration(days: 1));
      expect(await cap.tryShow(isGold: false), isTrue);
      now = now.add(const Duration(days: 30));
      expect(await cap.tryShow(isGold: true), isFalse);
    });
  });

  testWidgets('a gate opens the paywall through the trigger override', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    final a = FakeGoldActions();
    late WidgetRef captured;
    await pumpGold(
      tester,
      ProviderScope(
        overrides: [...goldOverrides(a), paywallTriggerOverride(key)],
        child: MaterialApp(
          navigatorKey: key,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: ZaghlolTheme.light,
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      ),
    );
    expect(find.byType(PaywallScreen), findsNothing);
    captured.read(paywallTriggerProvider)(GoldCapability.csvExport);
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
  });
}
