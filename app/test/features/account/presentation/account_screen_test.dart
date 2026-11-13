// T-147: S-69 in ar and en, RTL, text scale 1.3. Fake actions; no plugin.


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart'
    show SignInRequestProvider;
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/account/application/account_providers.dart';
import 'package:zaghlol/features/account/domain/sign_in_outcome.dart';
import 'package:zaghlol/features/account/presentation/account_screen.dart';
import 'package:zaghlol/features/gold/domain/restore_outcome.dart';

import '../../gold/presentation/gold_ui_harness.dart';

AppLocalizations tr(String lang) => lookupAppLocalizations(Locale(lang));

final DateTime next = DateTime.utc(2026, 12, 5, 9);

final class _Actions implements AccountActions {
  bool signedIn = false;
  bool linkedGold = false;
  bool protect = false;
  SignInOutcome signInResult = const SignedIn();
  final List<bool> replaceFlags = [];
  int restores = 0;
  int signOuts = 0;
  int deletes = 0;
  final List<SignInOutcome> queue = [];

  @override
  Future<AccountStatus> status() async =>
      AccountStatus(signedIn: signedIn, linkedGold: linkedGold);
  @override
  Future<bool> protectPending() async => protect;
  @override
  Future<void> dismissProtect() async => protect = false;
  @override
  Future<SignInOutcome> signIn(
    SignInRequestProvider provider, {
    bool replaceLink = false,
  }) async {
    replaceFlags.add(replaceLink);
    final o = queue.isNotEmpty ? queue.removeAt(0) : signInResult;
    if (o is SignedIn) signedIn = true;
    return o;
  }

  @override
  Future<SignOutOutcome> signOut() async {
    signOuts++;
    signedIn = false;
    return const SignedOut(serverConfirmed: true);
  }

  @override
  Future<DeleteAccountOutcome> deleteAccount() async {
    deletes++;
    signedIn = false;
    return const AccountDeleted();
  }

  @override
  Future<RestoreOutcome> restore() async {
    restores++;
    return const RestoreGold(movedFromOtherPhone: true);
  }
}

Future<void> _pump(
  WidgetTester t,
  _Actions a,
  String lang, {
  AccountReason reason = AccountReason.none,
}) => pumpGold(
  t,
  goldApp(
    AccountScreen(reason: reason),
    overrides: [
      ...goldOverrides(FakeGoldActions()),
      accountActionsProvider.overrideWithValue(a),
    ],
    lang: lang,
    scale: 1.3,
  ),
  height: 3000,
);

Future<void> main() async {
  await initDateFormatting();

  for (final lang in ['en', 'ar']) {
    final t = tr(lang);
    final rtl = lang == 'ar';
    group('S-69 $lang', () {
      testWidgets('signed out: provider buttons and the privacy line; layout '
          'direction follows the locale', (tester) async {
        await _pump(tester, _Actions(), lang);
        expect(find.text(t.goldAccountTitle), findsOneWidget);
        expect(find.text(t.goldAccountGoogle), findsOneWidget);
        expect(find.text(t.goldAccountApple), findsOneWidget);
        expect(find.text(t.goldAccountPrivacy), findsOneWidget);
        expect(find.text(t.commonActionSignOut), findsNothing);
        expect(
          Directionality.of(tester.element(find.byType(AccountScreen))),
          rtl ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('R3-5: refused move shows linked, the cooldown date and '
          'support', (tester) async {
        final a = _Actions()
          ..signInResult = SignedIn(moveRefused: true, nextMoveAt: next);
        await _pump(tester, a, lang);
        await tester.tap(find.text(t.goldAccountGoogle));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldSeatSignInLinked), findsOneWidget);
        expect(find.textContaining(RegExp('2026|٢٠٢٦')), findsWidgets);
        expect(find.text(t.commonActionContactSupport), findsOneWidget);
        expect(find.text(t.goldSeatRestoreAction), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('R5-3(b): restoreSuggested with a StoreKit transaction '
          'offers Restore', (tester) async {
        final a = _Actions()
          ..signInResult = const SignedIn(
            restoreHint: RestoreHint.offerRestore,
          );
        await _pump(tester, a, lang);
        await tester.tap(find.text(t.goldAccountApple));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldSeatRestoreSuggested), findsOneWidget);
        await tester.tap(find.text(t.goldSeatRestoreAction));
        await tester.pump();
        await tester.pump();
        expect(a.restores, 1);
        expect(find.text(t.goldAccountRestoreDone), findsOneWidget);
      });

      testWidgets('R5-3(b): restoreSuggested without a transaction shows '
          'nextMoveAt and the support path, and no Restore button', (
        tester,
      ) async {
        final a = _Actions()
          ..signInResult = SignedIn(
            restoreHint: RestoreHint.supportPath,
            nextMoveAt: next,
          );
        await _pump(tester, a, lang);
        await tester.tap(find.text(t.goldAccountApple));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldSeatRestoreAction), findsNothing);
        expect(find.text(t.goldSeatRestoreSuggested), findsNothing);
        expect(find.text(t.goldSeatSignInLinked), findsOneWidget);
        expect(find.textContaining(RegExp('2026|٢٠٢٦')), findsWidgets);
        expect(find.text(t.commonActionContactSupport), findsOneWidget);
        expect(find.textContaining('abc-123'), findsOneWidget);
      });

      testWidgets('cancel and failure show their lines', (tester) async {
        final a = _Actions()
          ..queue.addAll([const SignInCancelled(), const SignInFailed()]);
        await _pump(tester, a, lang);
        await tester.tap(find.text(t.goldAccountGoogle));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldAccountSignInCancelled), findsOneWidget);
        await tester.tap(find.text(t.goldAccountGoogle));
        await tester.pump();
        await tester.pump();
        expect(find.text(t.goldAccountSignInFailed), findsOneWidget);
      });

      testWidgets('EC-46: another account asks first, then repeats with '
          'replaceLink', (tester) async {
        final a = _Actions()
          ..queue.add(const SignInNeedsReplaceConfirm())
          ..signInResult = const SignedIn();
        await _pump(tester, a, lang);
        await tester.tap(find.text(t.goldAccountGoogle));
        await tester.pumpAndSettle();
        expect(find.text(t.goldAccountReplaceTitle), findsOneWidget);
        expect(a.replaceFlags, [false]);
        await tester.tap(find.text(t.goldAccountReplaceConfirm));
        await tester.pumpAndSettle();
        expect(a.replaceFlags, [false, true]);
      });

      testWidgets('EC-46: declining the replace sends nothing more', (
        tester,
      ) async {
        final a = _Actions()..queue.add(const SignInNeedsReplaceConfirm());
        await _pump(tester, a, lang);
        await tester.tap(find.text(t.goldAccountGoogle));
        await tester.pumpAndSettle();
        await tester.tap(find.text(t.commonActionCancel));
        await tester.pumpAndSettle();
        expect(a.replaceFlags, [false]);
      });

      testWidgets('signed in: sign out (with the linked-Gold warning) and '
          'delete account, each behind a confirmation', (tester) async {
        final a = _Actions()
          ..signedIn = true
          ..linkedGold = true;
        await _pump(tester, a, lang);
        expect(find.text(t.goldAccountGoogle), findsNothing);
        await tester.tap(find.text(t.commonActionSignOut));
        await tester.pumpAndSettle();
        expect(find.text(t.goldAccountSignOutBody('linked')), findsOneWidget);
        await tester.tap(find.text(t.commonActionCancel));
        await tester.pumpAndSettle();
        expect(a.signOuts, 0);
        await tester.tap(find.text(t.commonActionSignOut));
        await tester.pumpAndSettle();
        await tester.tap(find.text(t.commonActionSignOut).last);
        await tester.pumpAndSettle();
        expect(a.signOuts, 1);

        a.signedIn = true;
        a.linkedGold = false;
        ref(tester).invalidate(accountStatusProvider);
        await tester.pumpAndSettle();
        await tester.tap(find.text(t.goldAccountDeleteRow));
        await tester.pumpAndSettle();
        expect(find.text(t.goldAccountDeleteBody), findsOneWidget);
        await tester.tap(find.text(t.goldAccountDeleteConfirm).last);
        await tester.pumpAndSettle();
        expect(a.deletes, 1);
        expect(find.text(t.goldAccountDeleted), findsOneWidget);
      });

      testWidgets('D-54 suggestion shows only while pending and signed out', (
        tester,
      ) async {
        final a = _Actions()..protect = true;
        await _pump(tester, a, lang);
        expect(find.text(t.goldSeatProtectTitle), findsOneWidget);
        final b = _Actions();
        await _pump(tester, b, lang);
        expect(find.text(t.goldSeatProtectTitle), findsNothing);
      });

      testWidgets('R4-4: accountRequired reason leads with the sign-in '
          'prompt', (tester) async {
        await _pump(
          tester,
          _Actions(),
          lang,
          reason: AccountReason.accountRequired,
        );
        expect(find.text(t.goldSeatAccountRequiredTitle), findsOneWidget);
        expect(find.text(t.goldSeatAccountRequiredBody), findsOneWidget);
      });
    });
  }
}

ProviderContainer ref(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(AccountScreen)));
