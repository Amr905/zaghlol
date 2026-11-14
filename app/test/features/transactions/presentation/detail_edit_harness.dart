// T-080: fakes and pump helpers for S-12 / S-13 widget tests. Synthetic data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/transactions/application/transaction_editor.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/features/transactions/data/transaction_detail_reader.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/detail/transaction_detail_screen.dart';
import 'package:zaghlol/features/transactions/presentation/detail/txn_detail_providers.dart';
import 'package:zaghlol/features/transactions/presentation/edit/transaction_edit_screen.dart';
import 'package:zaghlol/features/transactions/presentation/edit/txn_edit_providers.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';

import 'list/list_harness.dart';

/// Records what the editor was asked to store.
class FakeEditor implements TxnEditorPort {
  final List<List<NewTransaction>> added = [];
  final List<(String, TransactionEdit)> updates = [];
  List<String> removedLinks = const [];
  Object? failWith;

  @override
  Future<List<String>> add(List<NewTransaction> legs) async {
    if (failWith != null) throw failWith!;
    added.add(legs);
    return [for (var i = 0; i < legs.length; i++) 'new$i'];
  }

  @override
  Future<EditOutcome> update(String id, TransactionEdit edit) async {
    if (failWith != null) throw failWith!;
    updates.add((id, edit));
    return EditOutcome(txnRec(id), removedLinks);
  }
}

/// Repository for the detail screen's note edit.
class NoteRepo extends FakeRepo {
  NoteRepo(super.rows);
  final List<TransactionEdit> edits = [];

  @override
  Future<TransactionRecord> edit(String id, TransactionEdit edit) async {
    edits.add(edit);
    return rows.first;
  }
}

TxnDetail detailOf(
  TransactionRecord r, {
  String? raw,
  TransactionRecord? counterpart,
  Money? balance,
}) => TxnDetail(
  record: r,
  referenceNo: '123456',
  balanceAfter: balance,
  templateId: 'nbe.purchase.v1',
  parseConfidence: 0.92,
  rawBody: raw,
  counterpart: counterpart,
);

Widget _app(
  List<Override> overrides,
  Widget home, {
  required Locale locale,
  required double textScale,
  required bool dark,
}) => ProviderScope(
  overrides: [
    txnLookupsProvider.overrideWith((ref) async => lookups),
    paydayScheduleProvider.overrideWith(
      (ref) async => PaydaySchedule.single(1),
    ),
    todayProvider.overrideWith(FixedToday.new),
    clockProvider.overrideWithValue(() => now),
    localZoneProvider.overrideWithValue(const FixedZone()),
    transactionsChangedProvider.overrideWithValue(const Stream.empty()),
    defaultCashAccountIdProvider.overrideWith((ref) async => 'acc1'),
    digitsModeProvider.overrideWith(
      (ref, lang) => DigitsMode.resolve(DigitsPref.auto, lang),
    ),
    ...overrides,
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ZaghlolTheme.light,
    darkTheme: ZaghlolTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  ),
);

/// Pumps S-12 for [id] with [detail] (null = "no longer exists").
Future<void> pumpDetail(
  WidgetTester tester,
  Harness h, {
  required AsyncValue<TxnDetail?> detail,
  NoteRepo? repo,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  bool dark = false,
  String id = 'a',
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      [
        transactionRepositoryProvider.overrideWith(
          (ref) async => repo ?? h.repo,
        ),
        txnBulkActionsProvider.overrideWith((ref) async => h.actions),
        txnDetailProvider.overrideWith((ref, i) async {
          if (detail.hasError) throw detail.error!;
          return detail.value;
        }),
      ],
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TransactionDetailScreen(
                    transactionId: id,
                    onSplit: (_) {},
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: locale,
      textScale: textScale,
      dark: dark,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> pumpEditor(
  WidgetTester tester,
  FakeEditor editor, {
  TransactionRecord? existing,
  String? rawText,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  bool dark = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      [transactionEditorProvider.overrideWith((ref) async => editor)],
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TransactionEditScreen(
                    existing: existing,
                    rawText: rawText,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      locale: locale,
      textScale: textScale,
      dark: dark,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
