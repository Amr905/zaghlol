// T-272: the "I exchanged money" entry (D-86, WP-4). Synthetic data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/presentation/edit/txn_edit_providers.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol/features/transfers/presentation/exchange_entry_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../transactions/presentation/list/list_harness.dart'
    show FixedToday, FixedZone, lookups;

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

/// Records the exchange the screen asked for.
class _FakePairing implements TransferPairingUseCase {
  final List<Map<String, Object?>> calls = [];

  @override
  Future<PairingResult> recordExchange({
    required String fromAccountId,
    required Money sent,
    required String toAccountId,
    required Money received,
    required DateTime occurredAt,
    required int tzOffsetMin,
    String? resolveItemId,
  }) async {
    calls.add({
      'from': fromAccountId,
      'sent': sent,
      'to': toAccountId,
      'received': received,
      'item': resolveItemId,
    });
    return const PairingResult(PairingStatus.paired);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakePairing> _pump(
  WidgetTester t, {
  Locale locale = const Locale('en'),
  ExchangePrefill prefill = const ExchangePrefill(),
}) async {
  final fake = _FakePairing();
  await t.binding.setSurfaceSize(const Size(390, 1000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        txnLookupsProvider.overrideWith((ref) async => lookups),
        defaultCashAccountIdProvider.overrideWith((ref) async => 'acc1'),
        primaryCurrencyProvider.overrideWith((ref) => Stream.value(egp)),
        todayProvider.overrideWith(FixedToday.new),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 13, 10)),
        localZoneProvider.overrideWithValue(const FixedZone()),
        digitsModeProvider.overrideWith(
          (ref, lang) => DigitsMode.resolve(DigitsPref.auto, lang),
        ),
        transferPairingUseCaseProvider.overrideWith((ref) async => fake),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ZaghlolTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showExchangeEntry(context, prefill: prefill),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return fake;
}

Finder _amountIn(String side) => find.descendant(
  of: find.byKey(ValueKey('exchange-$side')),
  matching: find.byType(TextField),
);

void main() {
  test('formatRateE9: 2 to 4 decimals, integer math', () {
    expect(formatRateE9(49500000000), '49.50');
    expect(formatRateE9(486666666667), '486.6667');
    expect(formatRateE9(20618557), '0.0206');
    expect(formatRateE9(1000000000), '1.00');
    expect(formatRateE9(0), '0');
  });

  testWidgets('PO story: USD wallet -> NBE EGP, rate shown, exact amounts '
      'saved', (t) async {
    final fake = await _pump(t);
    expect(find.text('I exchanged money'), findsWidgets);
    await t.enterText(_amountIn('sent'), '600');
    await t.enterText(_amountIn('received'), '29,700');
    await t.pump();
    expect(find.text('Rate: 1 USD = 49.50 EGP'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('exchange-save')));
    await t.pumpAndSettle();
    expect(fake.calls, hasLength(1));
    final c = fake.calls.single;
    expect(c['from'], 'acc2');
    expect(c['to'], 'acc1');
    expect(c['sent'], Money(usd, 60000));
    expect(c['received'], Money(egp, 2970000));
    expect(c['item'], isNull);
    expect(find.text('Exchange saved'), findsOneWidget);
  });

  testWidgets('prefilled from a balance-rise question: received side set, '
      'item resolved on save; Arabic digits accepted', (t) async {
    final fake = await _pump(
      t,
      locale: const Locale('ar'),
      prefill: ExchangePrefill(
        toAccountId: 'acc1',
        received: Money(egp, 2970000),
        reviewItemId: 'jump1',
      ),
    );
    expect(find.text('29700.00'), findsOneWidget);
    await t.enterText(_amountIn('sent'), '٦٠٠');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('exchange-save')));
    await t.pumpAndSettle();
    expect(fake.calls.single['sent'], Money(usd, 60000));
    expect(fake.calls.single['received'], Money(egp, 2970000));
    expect(fake.calls.single['item'], 'jump1');
  });

  testWidgets('one currency on both sides or an empty amount: nothing saved', (
    t,
  ) async {
    final fake = await _pump(t);
    await t.tap(find.byKey(const ValueKey('exchange-save')));
    await t.pump();
    expect(fake.calls, isEmpty);
    expect(find.text('Enter an amount above zero'), findsWidgets);
    // Make the sent side EGP too.
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('exchange-sent')),
        matching: find.text('USD'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('EGP').last);
    await t.pumpAndSettle();
    await t.enterText(_amountIn('sent'), '600');
    await t.enterText(_amountIn('received'), '600');
    await t.pump();
    expect(find.text('Pick two different currencies'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('exchange-save')));
    await t.pump();
    expect(fake.calls, isEmpty);
  });
}
