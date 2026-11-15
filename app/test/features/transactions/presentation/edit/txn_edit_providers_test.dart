// FIX-device-flows: a fresh install has no account; the first manual entry
// must get the default Cash account (FR-ACC-03) instead of an editor that can
// never save. In-memory database.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/transactions/presentation/edit/txn_edit_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  Future<(AppDatabase, ProviderContainer)> setUpDb({String? lang}) async {
    final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    final repo = SettingsRepository(SettingsDao(db));
    await repo.set(Settings.primaryCurrency, Currency.of('SAR'));
    if (lang != null) {
      await repo.set(
        Settings.language,
        lang == 'en' ? LanguagePref.en : LanguagePref.ar,
      );
    }
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        settingsRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    addTearDown(c.dispose);
    return (db, c);
  }

  test('fresh install: creates Cash once, in the primary currency', () async {
    final (db, c) = await setUpDb(lang: 'en');
    final sub = c.listen(defaultCashAccountIdProvider, (_, _) {});
    addTearDown(sub.close);
    final id = await c.read(defaultCashAccountIdProvider.future);
    expect(id, isNotNull);
    final row = await AccountsDao(db).defaultCash();
    expect(row!.id, id);
    expect(row.kind, 'cash');
    expect(row.defaultCurrency, 'SAR');
    expect(row.label, 'Cash');

    c.invalidate(defaultCashAccountIdProvider);
    expect(await c.read(defaultCashAccountIdProvider.future), id);
    expect(await AccountsDao(db).listLive(includeHidden: true), hasLength(1));
  });

  test('Arabic label by default', () async {
    final (db, c) = await setUpDb(lang: 'ar');
    final sub = c.listen(defaultCashAccountIdProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(defaultCashAccountIdProvider.future);
    expect((await AccountsDao(db).defaultCash())!.label, 'كاش');
  });
}
