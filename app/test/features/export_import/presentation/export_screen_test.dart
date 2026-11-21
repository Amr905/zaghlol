// FU-240c: the export half of S-67.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/export_import/application/export.dart';
import 'package:zaghlol/features/export_import/presentation/export_ports.dart';
import 'package:zaghlol/features/export_import/presentation/export_screen.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/domain/transaction_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../support/hide_amounts_support.dart';
import '../../backup/presentation/backup_fakes.dart';

class _Repo implements TransactionRepository {
  _Repo(this.rows);
  final List<TransactionRecord> rows;

  @override
  Future<List<TransactionRecord>> query({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  }) async => rows;

  @override
  Future<int> count({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
  }) async => rows.length;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Dest implements ExportDestination {
  final names = <String>[];
  Object? error;
  @override
  Future<void> write(String suggestedName, Uint8List bytes) async {
    if (error != null) throw error!;
    names.add(suggestedName);
  }
}

TransactionRecord _t(int i) => TransactionRecord(
  id: 't$i',
  accountId: 'a1',
  source: TxnSource.manual,
  direction: TxnDirection.expense,
  status: TxnStatus.posted,
  amount: Money(Currency.of('EGP'), 12550),
  occurredAt: DateTime.utc(2026, 1, 5, 12),
  occurredTzOffsetMin: 120,
  merchantRaw: 'Metro $i',
  categorySource: CategorySource.none,
  isUserVerified: true,
  isInternal: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  for (final lang in ['ar', 'en']) {
    group('S-67 export ($lang)', () {
      late _Dest dest;
      GoldCapability? paywallFor;
      var openedImport = 0;

      Future<AppLocalizations> pump(
        WidgetTester t, {
        bool gold = true,
        List<TransactionRecord>? rows,
        double scale = 1.0,
        bool hidden = false,
      }) async {
        await t.binding.setSurfaceSize(const Size(390, 1500));
        addTearDown(() => t.binding.setSurfaceSize(null));
        paywallFor = null;
        openedImport = 0;
        final container = ProviderContainer(
          overrides: [
            ...(hidden
                ? (HideAmountsHarness()..value = true).overrides
                : amountsShown()),
            languageProviderOverride(lang),
            exportServiceProvider.overrideWith(
              (ref) async => ExportService(_Repo(rows ?? [_t(1), _t(2)])),
            ),
            exportDestinationFactoryProvider.overrideWithValue(() => dest),
            paywallTriggerProvider.overrideWithValue((c) => paywallFor = c),
          ],
        );
        addTearDown(container.dispose);
        if (gold) {
          container
              .read(entitlementStateProvider.notifier)
              .applyVerified(verified: true, status: 'active');
        }
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: host(
              ExportScreen(onOpenImport: () => openedImport++),
              lang: lang,
              scale: scale,
            ),
          ),
        );
        await t.pumpAndSettle();
        return AppLocalizations.of(t.element(find.byType(Scaffold).first));
      }

      setUp(() => dest = _Dest());

      testWidgets('Gold: preview, notice, export writes a csv', (t) async {
        final l = await pump(t);
        expect(find.text(l.exportsMainTitle), findsOneWidget);
        expect(find.text(l.exportsMainUnencrypted), findsOneWidget);
        expect(find.text('Metro 1'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('exportButton')));
        await t.pumpAndSettle();
        expect(dest.names.single, endsWith('.csv'));
        expect(find.text(l.exportsMainReady), findsOneWidget);
      });

      testWidgets('Gold: Excel format writes an xlsx', (t) async {
        final l = await pump(t);
        await t.tap(find.text(l.exportsMainFormatExcel));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('exportButton')));
        await t.pumpAndSettle();
        expect(dest.names.single, endsWith('.xlsx'));
      });

      testWidgets('Free: preview only, Export opens the paywall', (t) async {
        final l = await pump(t, gold: false);
        expect(find.text(l.exportsMainFreePreview), findsOneWidget);
        expect(find.text('Metro 1'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('exportButton')));
        await t.pumpAndSettle();
        expect(paywallFor, GoldCapability.csvExport);
        expect(dest.names, isEmpty);
      });

      testWidgets('empty: no transactions message', (t) async {
        final l = await pump(t, rows: []);
        expect(find.text(l.exportsMainPreviewEmpty), findsOneWidget);
      });

      testWidgets('error: failed write shows the banner', (t) async {
        dest.error = StateError('x');
        final l = await pump(t);
        await t.tap(find.byKey(const ValueKey('exportButton')));
        await t.pumpAndSettle();
        expect(find.text(l.exportsMainFailed), findsOneWidget);
      });

      testWidgets('hide-amounts masks the preview amounts', (t) async {
        await pump(t, hidden: true);
        expect(find.textContaining('125'), findsNothing);
      });

      testWidgets('the import row opens the import flow', (t) async {
        await pump(t);
        await t.ensureVisible(find.byKey(const ValueKey('exportOpenImport')));
        await t.tap(find.byKey(const ValueKey('exportOpenImport')));
        expect(openedImport, 1);
      });

      testWidgets('text scale 1.3 does not overflow', (t) async {
        await pump(t, scale: 1.3);
        expect(t.takeException(), isNull);
      });
    });
  }
}
