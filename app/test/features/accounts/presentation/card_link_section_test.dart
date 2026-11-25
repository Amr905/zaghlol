// T-266 (US-P05): the link on S-41, in Arabic and English. A debit card is
// asked "Is this card on your <bank> account?" and is linked only on the
// tap; a linked card shows the account's balance and can be unlinked after
// a confirm; an account lists its cards and offers "Set current amount".
// Synthetic data.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations_ar.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations_en.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart'
    show accountsRepositoryProvider;
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/accounts/domain/accounts_repository.dart';
import 'package:zaghlol/features/accounts/presentation/card_detail/card_detail.dart';
import 'package:zaghlol/features/accounts/presentation/card_detail/card_detail_providers.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/wealth/data/net_worth_repository.dart';
import 'package:zaghlol/features/wealth/presentation/net_worth_breakdown_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'card_detail_test.dart' show host;

final egp = Currency.of('EGP');
final _t = DateTime.utc(2026, 11, 1);

Account acc(
  String id,
  AccountKind kind, {
  String? linked,
  String? last4,
  String label = 'Bank',
}) => Account(
  id: id,
  kind: kind,
  label: label,
  defaultCurrency: egp,
  isHidden: false,
  isDefaultCash: false,
  createdAt: _t,
  updatedAt: _t,
  institutionCode: 'nbe',
  last4: last4,
  linkedAccountId: linked,
);

class FakeLinkRepo implements AccountsRepository {
  FakeLinkRepo(this.accounts);
  final Map<String, Account> accounts;
  final calls = <String>[];

  @override
  Future<Account> linkCard({
    required String cardId,
    required String accountId,
  }) async {
    calls.add('link $cardId $accountId');
    return accounts[cardId]!;
  }

  @override
  Future<Account> unlinkCard(String cardId) async {
    calls.add('unlink $cardId');
    return accounts[cardId]!;
  }

  @override
  Future<List<LinkTarget>> linkTargets(String cardId) async => [
    LinkTarget(accounts['acc']!, sameBank: true),
  ];

  @override
  Future<List<Account>> cardsLinkedTo(String accountId) async => [
    for (final a in accounts.values)
      if (a.linkedAccountId == accountId) a,
  ];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _empty = CardDetailData(
  donut: const ChartNotEnoughData<CategoryDonut>(
    NotEnoughReason.noData,
    have: 0,
    need: 1,
  ),
  merchants: const ChartNotEnoughData<List<MerchantSpend>>(
    NotEnoughReason.noData,
    have: 0,
    need: 1,
  ),
  trend: const ChartNotEnoughData<List<CashFlowPoint>>(
    NotEnoughReason.noData,
    have: 0,
    need: 1,
  ),
  recent: const [],
  income: null,
  nextDue: null,
);

NetWorthBreakdown _worth() {
  final line = resolveAccountLine(
    accountId: 'acc',
    label: 'Current',
    accountKind: 'account',
    currency: egp,
    isLiability: false,
    now: _t,
    anchor: BalanceAnchor(
      amount: Money(egp, 975000),
      asOf: _t,
      userEntered: false,
    ),
  );
  return NetWorthBreakdown(
    lines: [line],
    units: buildUnitBreakdowns([line]),
    worth: computeNetWorth(money: moneyLinesOf([line])),
  );
}

Future<FakeLinkRepo> pump(
  WidgetTester t,
  String id,
  Map<String, Account> accounts,
  Locale locale,
) async {
  final repo = FakeLinkRepo(accounts);
  await t.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    host(
      CardDetailScreen(accountId: id),
      locale: locale,
      overrides: [
        accountsRepositoryProvider.overrideWith((ref) async => repo),
        cardDetailAccountProvider.overrideWith(
          (ref, id) async => accounts[id] == null
              ? null
              : AccountWithBalances(accounts[id]!, const []),
        ),
        cardDetailDataProvider.overrideWith((ref, key) async => _empty),
        netWorthBreakdownProvider.overrideWith((ref) async => _worth()),
      ],
    ),
  );
  await t.pumpAndSettle();
  return repo;
}

void main() {
  for (final locale in const [Locale('en'), Locale('ar')]) {
    final AppLocalizations l = locale.languageCode == 'ar'
        ? AppLocalizationsAr()
        : AppLocalizationsEn();
    final dir = locale.languageCode == 'ar'
        ? TextDirection.rtl
        : TextDirection.ltr;

    group(locale.languageCode, () {
      testWidgets('a debit card is asked about its same-bank account and '
          'linked only on the tap', (t) async {
        final repo = await pump(t, 'deb', {
          'deb': acc('deb', AccountKind.debit, last4: '1234', label: 'Debit'),
          'acc': acc('acc', AccountKind.account, label: 'Current'),
        }, locale);
        expect(find.text(l.accountsLinkSuggest('Current')), findsOneWidget);
        expect(
          Directionality.of(t.element(find.byKey(const Key('card-link-yes')))),
          dir,
        );
        expect(repo.calls, isEmpty);
        await t.tap(find.byKey(const Key('card-link-yes')));
        await t.pumpAndSettle();
        expect(repo.calls, ['link deb acc']);
      });

      testWidgets('the picker lists the targets; picking one links', (t) async {
        final repo = await pump(t, 'deb', {
          'deb': acc('deb', AccountKind.debit, last4: '1234'),
          'acc': acc('acc', AccountKind.account, label: 'Current'),
        }, locale);
        await t.tap(find.byKey(const Key('card-link-pick')));
        await t.pumpAndSettle();
        expect(find.text(l.accountsLinkSheetTitle), findsOneWidget);
        await t.tap(find.byKey(const Key('card-link-target-acc')));
        await t.pumpAndSettle();
        expect(repo.calls, ['link deb acc']);
      });

      testWidgets('a linked card shows the account balance; unlink asks '
          'first', (t) async {
        final repo = await pump(t, 'deb', {
          'deb': acc('deb', AccountKind.debit, last4: '1234', linked: 'acc'),
          'acc': acc('acc', AccountKind.account, label: 'Current'),
        }, locale);
        expect(find.byKey(const Key('card-linked-header')), findsOneWidget);
        expect(find.text(l.accountsLinkBalanceOn('Current')), findsOneWidget);
        expect(find.byKey(const Key('card-linked-name')), findsOneWidget);
        await t.ensureVisible(find.byKey(const Key('card-link-unlink')));
        await t.tap(find.byKey(const Key('card-link-unlink')));
        await t.pumpAndSettle();
        expect(find.text(l.accountsLinkUnlinkBody), findsOneWidget);
        await t.tap(find.text(l.commonActionCancel));
        await t.pumpAndSettle();
        expect(repo.calls, isEmpty);
        await t.tap(find.byKey(const Key('card-link-unlink')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('card-unlink-yes')));
        await t.pumpAndSettle();
        expect(repo.calls, ['unlink deb']);
      });

      testWidgets('an account lists its cards and offers "Set current '
          'amount" (the typed balance sheet)', (t) async {
        await pump(t, 'acc', {
          'deb': acc(
            'deb',
            AccountKind.debit,
            last4: '1234',
            linked: 'acc',
            label: 'Debit',
          ),
          'acc': acc('acc', AccountKind.account, label: 'Current'),
        }, locale);
        expect(find.text(l.accountsCardsOnAccount), findsOneWidget);
        expect(
          find.byKey(const Key('account-linked-card-deb')),
          findsOneWidget,
        );
        await t.ensureVisible(find.byKey(const Key('account-set-current')));
        await t.tap(find.byKey(const Key('account-set-current')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('networth-amount')), findsOneWidget);
      });

      testWidgets('a credit card has no link section', (t) async {
        await pump(t, 'cc', {
          'cc': acc('cc', AccountKind.credit, last4: '9999'),
          'acc': acc('acc', AccountKind.account),
        }, locale);
        expect(find.byKey(const Key('card-link-section')), findsNothing);
        expect(find.byKey(const Key('account-link-section')), findsNothing);
      });
    });
  }
}
