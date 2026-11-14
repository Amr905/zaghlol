// WIRE-2 (T-092): the ingest hook opens a suggestion for a stored incoming
// P2P transfer, and the review actions accept or dismiss it. Synthetic data.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_ports.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_providers.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transfers/application/suggestion_hook.dart';

import '../../../core/db/financial_fixtures.dart';

const _day = 86400000;

void main() {
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    await AccountsDao(db).insert(account('acc1'));
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'dine',
            systemCode: const Value('dining'),
            nameAr: 'a',
            nameEn: 'dine',
            icon: 'x',
            color: '#000000',
            bucket: 'wants',
            sort: 0,
          ),
        );
    final dao = TransactionsDao(db);
    await dao.insert(
      txn(
        'bill',
        amountMinor: 120000,
        occurredAt: t0,
      ).copyWith(categoryId: const Value('dine')),
    );
    await dao.insert(
      txn(
        'in1',
        direction: 'transfer_in',
        amountMinor: 40000,
        occurredAt: t0 + _day,
      ).copyWith(counterpartyKind: const Value('person')),
    );
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        settingsRepositoryProvider.overrideWith(
          (ref) async => SettingsRepository(SettingsDao(db)),
        ),
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(t0 + _day, isUtc: true),
        ),
      ],
    );
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<List<String>> open() async => [
    for (final r
        in await db
            .customSelect(
              "SELECT id FROM review_items WHERE kind = 'reimbursement_suggestion' "
              'AND resolved_at IS NULL',
            )
            .get())
      r.read<String>('id'),
  ];

  Future<int> links() async =>
      (await db
              .customSelect('SELECT count(*) AS n FROM offset_links')
              .getSingle())
          .read<int>('n');

  test('hook: a newly stored incoming transfer opens one suggestion', () async {
    final hook = ReimbursementSuggestionHook(db);
    const p = PersistedTxn(txnId: 'in1', accountId: 'acc1', inserted: true);
    await hook.afterPersist(p);
    await hook.afterPersist(p); // idempotent
    expect(await open(), hasLength(1));
    expect(await links(), 0, reason: 'nothing is linked until accepted');
  });

  test(
    'hook: a merge into an existing row (inserted false) does nothing',
    () async {
      await ReimbursementSuggestionHook(db).afterPersist(
        const PersistedTxn(txnId: 'in1', accountId: 'acc1', inserted: false),
      );
      expect(await open(), isEmpty);
    },
  );

  test('hook: an unknown id never throws', () async {
    await ReimbursementSuggestionHook(db).afterPersist(
      const PersistedTxn(txnId: 'nope', accountId: 'acc1', inserted: true),
    );
    expect(await open(), isEmpty);
  });

  test(
    'review action accept links the transfer to the named expense',
    () async {
      await ReimbursementSuggestionHook(db).afterPersist(
        const PersistedTxn(txnId: 'in1', accountId: 'acc1', inserted: true),
      );
      final id = (await open()).single;
      // A bare accept never picks a candidate for the user.
      await c.read(reviewActionsProvider).accept(id);
      expect(await links(), 0);
      expect(await open(), [id]);
      await c.read(reviewActionsProvider).acceptCandidate(id, 'bill');
      expect(await links(), 1);
      expect(await open(), isEmpty);
    },
  );

  test(
    'review action dismiss resolves it, links nothing, is remembered',
    () async {
      final hook = ReimbursementSuggestionHook(db);
      const p = PersistedTxn(txnId: 'in1', accountId: 'acc1', inserted: true);
      await hook.afterPersist(p);
      await c.read(reviewActionsProvider).dismiss((await open()).single);
      expect(await links(), 0);
      expect(await open(), isEmpty);
      await hook.afterPersist(
        p,
      ); // the dismissed candidate is not suggested again
      expect(await open(), isEmpty);
    },
  );
}
