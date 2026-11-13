import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/gold/domain/purchase_outcome.dart';
import 'package:zaghlol/features/gold/domain/restore_outcome.dart';
import 'package:zaghlol/features/gold/presentation/gold_ui_ports.dart';
import 'package:zaghlol/features/settings/presentation/settings_ports.dart';

class FakeGoldActions implements GoldActions {
  final StreamController<PurchaseOutcome> ctl =
      StreamController<PurchaseOutcome>.broadcast();
  final List<GoldPlan> bought = [];
  bool buyStarts = true;
  RestoreOutcome restoreResult = const RestoreNothingToRestore();
  int restores = 0;
  int dismissals = 0;
  bool noticePending = false;

  @override
  Future<bool> buy(GoldPlan plan) async {
    bought.add(plan);
    return buyStarts;
  }

  @override
  Stream<PurchaseOutcome> get outcomes => ctl.stream;

  @override
  Future<RestoreOutcome> restore() async {
    restores++;
    return restoreResult;
  }

  @override
  Future<void> dismissSupportNotice() async {
    dismissals++;
    noticePending = false;
  }
}

class _StateNotifier extends EntitlementNotifier {
  _StateNotifier(this._phase, this._by);
  final EntitlementPhase _phase;
  final MovedBy? _by;
  @override
  EntitlementState build() {
    if (_phase == EntitlementPhase.free) return EntitlementState.free;
    if (_phase == EntitlementPhase.active) {
      Future.microtask(() => applyVerified(verified: true, status: 'active'));
      return EntitlementState.free;
    }
    Future.microtask(() => applyNonGold(_phase, movedBy: _by));
    return EntitlementState.free;
  }
}

const offers = [
  GoldPlanOffer(plan: GoldPlan.monthly, storePrice: 'EGP 49.99'),
  GoldPlanOffer(plan: GoldPlan.yearly, storePrice: 'EGP 399.99'),
  GoldPlanOffer(plan: GoldPlan.lifetime, storePrice: 'EGP 899.99'),
];

List<Override> goldOverrides(
  FakeGoldActions actions, {
  EntitlementPhase phase = EntitlementPhase.free,
  MovedBy? movedBy,
  Future<List<GoldPlanOffer>> Function()? offerLoader,
  GoldStatusInfo info = const GoldStatusInfo(),
  bool western = false,
  void Function(GoldLink)? onLink,
  VoidCallback? signIn,
  List<String>? contacted,
}) => [
  goldActionsProvider.overrideWithValue(actions),
  entitlementStateProvider.overrideWith(() => _StateNotifier(phase, movedBy)),
  goldOffersProvider.overrideWith(
    (ref) => (offerLoader ?? () async => offers)(),
  ),
  goldStatusInfoProvider.overrideWith(
    (ref) async => GoldStatusInfo(
      plan: info.plan,
      nextMoveAt: info.nextMoveAt,
      supportNoticePending: actions.noticePending || info.supportNoticePending,
    ),
  ),
  supportCodeProvider.overrideWith((ref) async => 'abc-123'),
  contactSupportProvider.overrideWithValue((s) async => contacted?.add(s)),
  digitsProvider.overrideWith(
    (ref) => Stream.value(western ? DigitsPref.western : DigitsPref.auto),
  ),
  goldLinkOpenerProvider.overrideWithValue(onLink ?? (_) {}),
  goldSignInOpenerProvider.overrideWithValue(signIn),
];

Widget goldApp(
  Widget home, {
  required List<Override> overrides,
  String lang = 'en',
  bool dark = false,
  double scale = 1.0,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: Locale(lang),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ZaghlolTheme.light,
    darkTheme: ZaghlolTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  ),
);

Future<void> pumpGold(
  WidgetTester tester,
  Widget app, {
  double height = 2200,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
