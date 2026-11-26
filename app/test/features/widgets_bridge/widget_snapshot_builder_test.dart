import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/platform/widget_bridge_api.g.dart';
import 'package:zaghlol/features/budget/application/cycle_overview.dart';
import 'package:zaghlol/features/widgets_bridge/domain/widget_snapshot_builder.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final gbp = Currency.of('GBP');

const _en = WidgetCopy(
  perDay: _enPerDay,
  daysToPayday: _enDays,
  setBudget: 'Set a budget',
  openApp: 'Open Zaghlol',
);
String _enPerDay(String a) => '$a/day';
String _enDays(int n, String f) =>
    n == 1 ? '1 day to payday' : '$f days to payday';

const _ar = WidgetCopy(
  perDay: _arPerDay,
  daysToPayday: _arDays,
  setBudget: 'حدد ميزانية',
  openApp: 'افتح زغلول',
);
String _arPerDay(String a) => '$a في اليوم';
String _arDays(int n, String f) => '$f أيام لحد المرتب';

CycleOverview overview({Money? egpSafe, Money? gbpSafe, int days = 7}) {
  final start = CivilDate(2026, 11, 1);
  final cycle = PaydaySchedule([PaydayEra(null, 1)]).cycleOn(start);
  CurrencyOverview of(Currency c, Money? safe) => CurrencyOverview(
    currency: c,
    totals: CycleTotals(
      currency: c,
      income: Money.zero(c),
      spend: Money.zero(c),
      pendingSpend: Money.zero(c),
      byCategoryMinor: const {},
    ),
    budget: safe == null ? null : Money(c, 100000),
    safeToSpend: safe,
    underIdealLine: null,
  );
  return CycleOverview(
    cycle: cycle,
    today: start,
    daysRemaining: days,
    byCurrency: {egp: of(egp, egpSafe), gbp: of(gbp, gbpSafe)},
    incomeTarget: null,
  );
}

WidgetSnapshotInput input({
  CycleOverview? ov,
  bool hide = false,
  bool locked = false,
  String lang = 'en',
  DigitsMode digits = DigitsMode.western,
  WidgetCopy copy = _en,
  List<String> others = const [],
}) => WidgetSnapshotInput(
  overview: ov,
  primaryCurrency: egp,
  hideAmounts: hide,
  appLocked: locked,
  languageCode: lang,
  digits: digits,
  copy: copy,
  nowMs: 1000,
  otherCurrencies: others,
);

void main() {
  test(
    'shows the safe-to-spend and days to payday of the primary currency',
    () {
      final s = buildWidgetSnapshot(
        input(
          ov: overview(egpSafe: Money(egp, 31428), gbpSafe: Money(gbp, 99900)),
        ),
      );
      expect(s.state, WidgetDisplayState.ok);
      expect(s.primaryText, contains('314.28'));
      expect(s.primaryText, contains('EGP'));
      expect(s.primaryText, isNot(contains('999')));
      expect(s.primaryText, endsWith('/day'));
      expect(s.secondaryText, '7 days to payday');
      expect(s.daysToPayday, 7);
      expect(s.currency, 'EGP');
      expect(s.updatedAtMs, 1000);
    },
  );

  test('hide amounts shows ••• and no amount digits anywhere', () {
    final s = buildWidgetSnapshot(
      input(ov: overview(egpSafe: Money(egp, 31428)), hide: true),
    );
    expect(s.state, WidgetDisplayState.ok);
    expect(s.primaryText, '•••/day');
    expect(RegExp(r'[0-9٠-٩]').hasMatch(s.primaryText), isFalse);
    expect(s.primaryText, isNot(contains('EGP')));
  });

  test('a locked app always masks, even when hide amounts is off', () {
    final s = buildWidgetSnapshot(
      input(ov: overview(egpSafe: Money(egp, 31428)), locked: true),
    );
    expect(s.primaryText, '•••/day');
  });

  test('no budget in the primary currency: Set a budget', () {
    final s = buildWidgetSnapshot(
      input(ov: overview(egpSafe: null, gbpSafe: Money(gbp, 5000))),
    );
    expect(s.state, WidgetDisplayState.noBudget);
    expect(s.primaryText, 'Set a budget');
    expect(s.secondaryText, isEmpty);
    expect(s.daysToPayday, isNull);
  });

  test('no data: Open Zaghlol', () {
    final s = buildWidgetSnapshot(input());
    expect(s.state, WidgetDisplayState.noData);
    expect(s.primaryText, 'Open Zaghlol');
  });

  test('overspent is 0, not "no budget"', () {
    final s = buildWidgetSnapshot(
      input(ov: overview(egpSafe: Money.zero(egp))),
    );
    expect(s.state, WidgetDisplayState.ok);
    expect(s.primaryText, contains('0.00'));
  });

  test('Arabic: Arabic-Indic digits for the amount and the day count', () {
    final s = buildWidgetSnapshot(
      input(
        ov: overview(egpSafe: Money(egp, 31428), days: 7),
        lang: 'ar',
        digits: DigitsMode.arabicIndic,
        copy: _ar,
      ),
    );
    expect(s.primaryText, contains('٣١٤٫٢٨'));
    expect(s.secondaryText, contains('٧'));
    expect(RegExp(r'[0-9]').hasMatch(s.primaryText + s.secondaryText), isFalse);
  });

  test('3-decimal and 0-decimal primary currencies keep their exponent', () {
    final kwd = Currency.of('KWD');
    final ov = overview();
    final withKwd = CycleOverview(
      cycle: ov.cycle,
      today: ov.today,
      daysRemaining: 3,
      byCurrency: {
        kwd: CurrencyOverview(
          currency: kwd,
          totals: ov.byCurrency[egp]!.totals,
          budget: Money(kwd, 1000),
          safeToSpend: Money(kwd, 1250),
          underIdealLine: null,
        ),
      },
      incomeTarget: null,
    );
    final s = buildWidgetSnapshot(
      WidgetSnapshotInput(
        overview: withKwd,
        primaryCurrency: kwd,
        hideAmounts: false,
        appLocked: false,
        languageCode: 'en',
        digits: DigitsMode.western,
        copy: _en,
        nowMs: 1,
      ),
    );
    expect(s.primaryText, contains('1.250'));
    expect(s.currency, 'KWD');
  });

  group('T-284 other-currency hint', () {
    final ov = overview(egpSafe: Money(egp, 31428));
    String hint(List<String> codes, {bool hide = false, String lang = 'en'}) =>
        buildWidgetSnapshot(
          input(ov: ov, others: codes, hide: hide, lang: lang),
        ).secondaryText;

    test('no cards: no hint', () {
      expect(hint(const []), '7 days to payday');
    });

    test('1, 2 and 3 currencies; at most two codes then +N', () {
      expect(hint(['USD']), '7 days to payday \u00b7 \u2066+ USD\u2069');
      expect(
        hint(['USD', 'EUR']),
        '7 days to payday \u00b7 \u2066+ USD, EUR\u2069',
      );
      expect(
        hint(['USD', 'EUR', 'KWD']),
        '7 days to payday \u00b7 \u2066+ USD, EUR +1\u2069',
      );
    });

    test('codes stay when amounts are hidden; none while locked', () {
      expect(hint(['USD'], hide: true), contains('+ USD'));
      final locked = buildWidgetSnapshot(
        input(ov: ov, others: ['USD'], locked: true),
      );
      expect(locked.secondaryText, '7 days to payday');
    });

    test('FU-387: a line over the native max drops the hint, keeps payday', () {
      final long = WidgetCopy(
        setBudget: 'b',
        perDay: (a) => '$a/day',
        daysToPayday: (n, f) => '$f ${'x' * 110}',
        openApp: 'o',
      );
      final s = buildWidgetSnapshot(input(ov: ov, others: ['USD'], copy: long));
      expect(s.secondaryText, '7 ${'x' * 110}');
      expect(s.secondaryTextByDay, everyElement(isNot(contains('USD'))));
    });

    test('every rolled day line carries the hint, no amount in it', () {
      final s = buildWidgetSnapshot(input(ov: ov, others: ['USD', 'EUR']));
      expect(s.secondaryTextByDay, everyElement(contains('+ USD, EUR')));
      expect(s.secondaryText, contains('+ USD, EUR'));
    });

    test('no budget keeps the hint on line two; no data has none', () {
      final nb = buildWidgetSnapshot(input(ov: overview(), others: ['USD']));
      expect(nb.state, WidgetDisplayState.noBudget);
      expect(nb.secondaryText, contains('+ USD'));
      final nd = buildWidgetSnapshot(input(others: ['USD']));
      expect(nd.secondaryText, '');
    });

    test('Arabic digits for the +N count', () {
      final s = buildWidgetSnapshot(
        input(
          ov: ov,
          lang: 'ar',
          digits: DigitsMode.arabicIndic,
          copy: _ar,
          others: ['USD', 'EUR', 'KWD', 'GBP'],
        ),
      );
      expect(s.secondaryText, contains('+٢'));
    });
  });
}
