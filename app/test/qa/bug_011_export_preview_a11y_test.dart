// QA BUG-011 (B57): with hide-amounts on, the export preview rows put the raw
// `****` glyphs in the semantics tree (T-187 AC 7: a screen reader must say
// "amount hidden"). Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/export_import/application/export.dart';
import 'package:zaghlol/features/export_import/presentation/export_screen.dart';
import 'package:zaghlol/features/export_import/presentation/export_ports.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/domain/transaction_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../support/hide_amounts_support.dart';
import '../features/backup/presentation/backup_fakes.dart';

class _Repo implements TransactionRepository {
  @override
  Future<List<TransactionRecord>> query({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  }) async => [
    TransactionRecord(
      id: 't1',
      accountId: 'a1',
      source: TxnSource.manual,
      direction: TxnDirection.expense,
      status: TxnStatus.posted,
      amount: Money(Currency.of('EGP'), 12550),
      occurredAt: DateTime.utc(2026, 1, 5, 12),
      occurredTzOffsetMin: 120,
      merchantRaw: 'Metro',
      categorySource: CategorySource.none,
      isUserVerified: true,
      isInternal: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  ];

  @override
  Future<int> count({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
  }) async => 1;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  testWidgets('BUG-011 export preview: no **** in semantics when hidden', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(390, 1500));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        ...(HideAmountsHarness()..value = true).overrides,
        languageProviderOverride('en'),
        exportServiceProvider.overrideWith(
          (ref) async => ExportService(_Repo()),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(entitlementStateProvider.notifier)
        .applyVerified(verified: true, status: 'active');
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: host(ExportScreen(onOpenImport: () {}), lang: 'en'),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('****'), findsOneWidget); // the masked preview row
    await expectNoMaskGlyphInSemantics(t);
  });
}
