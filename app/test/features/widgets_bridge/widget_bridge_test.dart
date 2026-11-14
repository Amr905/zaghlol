// T-118: the Dart side of the widget channel against a fake platform: the
// wiring publishes after a transaction event, respects hide-amounts and the
// app lock, skips unchanged content and survives a platform error.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/platform/widget_bridge_api.g.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/budget/application/cycle_overview.dart';
import 'package:zaghlol/features/security/domain/app_lock_controller.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart'
    show clockProvider;
import 'package:zaghlol/features/widgets_bridge/application/widget_bridge.dart';
import 'package:zaghlol/features/widgets_bridge/domain/widget_snapshot_builder.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

class FakeWidgetHost extends WidgetBridgeHostApi {
  final List<WidgetSnapshot> sent = [];
  int clears = 0;
  Object? error;

  @override
  Future<void> updateSnapshot(WidgetSnapshot snapshot) async {
    final e = error;
    if (e != null) throw e;
    sent.add(snapshot);
  }

  @override
  Future<void> clear() async => clears++;
}

final egp = Currency.of('EGP');

CycleOverview overview(int safeMinor) {
  final today = CivilDate(2026, 11, 3);
  final cycle = PaydaySchedule([PaydayEra(null, 1)]).cycleOn(today);
  return CycleOverview(
    cycle: cycle,
    today: today,
    daysRemaining: 28,
    byCurrency: {
      egp: CurrencyOverview(
        currency: egp,
        totals: CycleTotals(
          currency: egp,
          income: Money.zero(egp),
          spend: Money.zero(egp),
          pendingSpend: Money.zero(egp),
          byCategoryMinor: const {},
        ),
        budget: Money(egp, 1000000),
        safeToSpend: Money(egp, safeMinor),
        underIdealLine: null,
      ),
    },
    incomeTarget: null,
  );
}

const copy = WidgetCopy(
  perDay: _perDay,
  daysToPayday: _days,
  setBudget: 'Set a budget',
  openApp: 'Open Zaghlol',
);
String _perDay(String a) => '$a/day';
String _days(int n, String f) => '$f days to payday';

class _Ov extends Notifier<CycleOverview> {
  @override
  CycleOverview build() => overview(31428);
  void set(CycleOverview o) => state = o;
}

class _Lock extends AppLockController {
  _Lock(this.locked);
  final bool locked;
  @override
  AppLockState build() => AppLockState(locked: locked);
}

void main() {
  late FakeWidgetHost host;
  late StreamController<bool> hide;
  late StreamController<bool> lockOn;
  late NotifierProvider<_Ov, CycleOverview> ovState;

  ProviderContainer make({bool locked = false}) {
    host = FakeWidgetHost();
    hide = StreamController<bool>();
    lockOn = StreamController<bool>();
    ovState = NotifierProvider<_Ov, CycleOverview>(_Ov.new);
    final c = ProviderContainer(
      overrides: [
        widgetBridgeHostProvider.overrideWithValue(host),
        widgetCopyProvider.overrideWith((ref, lang) => copy),
        hideAmountsWidgetProvider.overrideWith((ref) => hide.stream),
        appLockEnabledProvider.overrideWith((ref) => lockOn.stream),
        appLockControllerProvider.overrideWith(() => _Lock(locked)),
        primaryCurrencyProvider.overrideWith((ref) => Stream.value(egp)),
        digitsModeProvider('en').overrideWithValue(DigitsMode.western),
        currentCycleOverviewProvider.overrideWith(
          (ref) async => ref.watch(ovState),
        ),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 3, 12)),
      ],
    );
    addTearDown(() {
      c.dispose();
      hide.close();
      lockOn.close();
    });
    c.listen(widgetBridgeWiringProvider, (_, _) {});
    return c;
  }

  Future<void> pastDebounce() async {
    await Future<void>.delayed(
      widgetPublishDebounce + const Duration(milliseconds: 200),
    );
  }

  test('publishes the primary-currency snapshot and republishes after a new '
      'transaction changes the figure', () async {
    final c = make();
    hide.add(false);
    lockOn.add(false);
    await pastDebounce();
    expect(host.sent, hasLength(1));
    expect(host.sent.single.primaryText, contains('314.28'));

    c.read(ovState.notifier).set(overview(20000));
    await pastDebounce();
    expect(host.sent, hasLength(2));
    expect(host.sent.last.primaryText, contains('200.00'));
  });

  test('hide amounts: the amount never reaches the platform', () async {
    make();
    hide.add(true);
    lockOn.add(false);
    await pastDebounce();
    expect(host.sent.single.primaryText, '•••/day');
    expect(host.sent.map((s) => s.primaryText).join(), isNot(contains('314')));
  });

  test('app lock on and locked: masked', () async {
    make(locked: true);
    hide.add(false);
    lockOn.add(true);
    await pastDebounce();
    expect(host.sent.last.primaryText, '•••/day');
  });

  test('identical content is not sent twice', () async {
    final c = make();
    hide.add(false);
    lockOn.add(false);
    await pastDebounce();
    c.read(ovState.notifier).set(overview(31428));
    await pastDebounce();
    expect(host.sent, hasLength(1));
  });

  test('a platform error is swallowed and the next change retries', () async {
    final publisher = WidgetSnapshotPublisher(
      host = FakeWidgetHost()..error = PlatformException(code: 'IO_ERROR'),
    );
    final snap = WidgetSnapshot(
      state: WidgetDisplayState.ok,
      primaryText: '1/day',
      secondaryText: '',
      currency: 'EGP',
      updatedAtMs: 1,
    );
    expect(await publisher.publish(snap), isFalse);
    host.error = null;
    expect(await publisher.publish(snap), isTrue);
    await publisher.clear();
    expect(host.clears, 1);
  });
}
