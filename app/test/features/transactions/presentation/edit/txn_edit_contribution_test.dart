// FU-141: the editor provider offers an unknown merchant the user
// categorizes to the contribution queue (opt-in on), and queues nothing with
// the opt-in off. In-memory database, synthetic data.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/outbox_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/edit/txn_edit_providers.dart';

import '../../../../core/db/financial_fixtures.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late ProviderContainer c;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    settings = SettingsRepository(SettingsDao(db));
    await AccountsDao(db).insert(account('acc1', institution: 'nbe'));
    await CategoriesDao(db).upsertSystem(
      code: 'food',
      nameAr: 'أكل',
      nameEn: 'Food',
      icon: 'i',
      color: '#0F7A55',
      bucket: 'needs',
      sort: 1,
    );
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        settingsRepositoryProvider.overrideWith((ref) async => settings),
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(t0 + 1000, isUtc: true),
        ),
      ],
    );
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  // A captured row: the parser stored a normalized merchant key. Manual
  // rows carry only the typed text (no key) and are never offered.
  Future<String> captured() async {
    await TransactionsDao(
      db,
    ).insert(txn('cap1', merchant: 'CORNER SHOP', merchantNorm: 'corner shop'));
    return 'cap1';
  }

  Future<int> queued() async => (await OutboxDao(db).due(now: 1 << 50)).length;

  test('opt-in on: categorizing an unknown merchant queues it', () async {
    await settings.set(Settings.contributionOptIn, true);
    final editor = await c.read(transactionEditorProvider.future);
    final id = await captured();
    await editor.update(
      id,
      const TransactionEdit(categoryId: Maybe('sys:food')),
    );
    expect(await queued(), 1);
  });

  test('opt-in off: nothing is queued', () async {
    final editor = await c.read(transactionEditorProvider.future);
    final id = await captured();
    await editor.update(
      id,
      const TransactionEdit(categoryId: Maybe('sys:food')),
    );
    expect(await queued(), 0);
  });
}
