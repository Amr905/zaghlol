// QA BUG-010 (B57): the Money tab net-worth hero shows the alphabetically
// first currency, not the user's primary currency. A user whose primary is
// EGP and who holds one AED account sees the AED figure as the headline.
// Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/z_money_text.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/accounts/domain/accounts_repository.dart';
import 'package:zaghlol/features/accounts/presentation/money_overview_provider.dart';
import 'package:zaghlol/features/accounts/presentation/money_tab.dart';
import 'package:zaghlol/features/wealth/data/approx_view_providers.dart';
import 'package:zaghlol/features/wealth/domain/approx_view.dart';
import 'package:zaghlol/features/wealth/presentation/net_worth_breakdown_providers.dart';
import 'package:zaghlol/features/wealth/data/net_worth_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../support/hide_amounts_support.dart';

final _egp = Currency.of('EGP');
final _aed = Currency.of('AED');
final _t = DateTime.utc(2026, 11, 1);

Account _acc(String id, Currency c) => Account(
  id: id,
  kind: AccountKind.debit,
  label: 'Acc $id',
  defaultCurrency: c,
  isHidden: false,
  isDefaultCash: false,
  createdAt: _t,
  updatedAt: _t,
);

class _Repo implements AccountsRepository {
  _Repo(this.items);
  final List<AccountWithBalances> items;
  @override
  Future<List<AccountWithBalances>> listWithBalances({
    bool includeHidden = false,
  }) async => items;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

BreakdownLine _line(String id, Currency c, int minor) => resolveAccountLine(
  accountId: id,
  label: 'Acc $id',
  accountKind: 'debit',
  currency: c,
  isLiability: false,
  now: _t,
  anchor: BalanceAnchor(amount: Money(c, minor), asOf: _t, userEntered: false),
);

void main() {
  testWidgets('BUG-010 Money hero headline is the primary currency (EGP), '
      'not the alphabetically first one (AED)', (t) async {
    final h = HideAmountsHarness();
    addTearDown(h.dispose);
    final lines = [_line('e', _egp, 5000000), _line('a', _aed, 10000)];
    await t.binding.setSurfaceSize(const Size(390, 1500));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          primaryCurrencyProvider.overrideWith((ref) => Stream.value(_egp)),
          accountsRepositoryProvider.overrideWith(
            (ref) async => _Repo([
              AccountWithBalances(_acc('e', _egp), const []),
              AccountWithBalances(_acc('a', _aed), const []),
            ]),
          ),
          netWorthBreakdownProvider.overrideWith(
            (ref) async => NetWorthBreakdown(
              lines: lines,
              units: buildUnitBreakdowns(lines),
              worth: computeNetWorth(money: moneyLinesOf(lines)),
            ),
          ),
          moneyGroupByTypeProvider.overrideWith((ref) => Stream.value(true)),
          cardDueDatesProvider.overrideWith((ref) async => const {}),
          approxViewProvider.overrideWith(
            (ref, totals) async => const ApproxViewOff(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: ZaghlolTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MoneyTab(),
        ),
      ),
    );
    await t.pumpAndSettle();
    final hero = t
        .widgetList<ZMoneyText>(find.byType(ZMoneyText))
        .firstWhere((w) => w.size == ZMoneySize.hero);
    expect(hero.unit, 'EGP', reason: 'hero shows ${hero.text} ${hero.unit}');
  });
}
