// T-271 (D-85): a salary in another currency is income with the salary
// category in its own currency (never converted) and it drives the payday.
// Real bundled registry, real ingest, synthetic message only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';

import '../../ingestion/support/ingest_harness.dart';

const String _body =
    'قيد راتب بمبلغ USD 59.66 لحساب 410*5045 بتاريخ 26/10/2026 .';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Arab Bank USD salary SMS: income, salary category, USD, payday '
      'auto-set with its banner', () async {
    final registry = await preloadBundledRegistry();
    final w = await IngestWorld.open();
    addTearDown(w.close);
    await CategoriesDao(w.db).upsertSystem(
      code: 'income',
      nameAr: 'دخل',
      nameEn: 'Income',
      icon: 'x',
      color: '#112233',
      bucket: 'income',
      sort: 1,
    );
    final r = await w.useCase(registry: registry)([
      sms('a1', _body, source: 'EG'),
    ]);
    expect(r.outcomes['a1'], isA<IngestInserted>());
    final t = (await w.txns()).single;
    expect(t['direction'], 'income');
    expect(t['currency'], 'USD');
    expect(t['amount_minor'], 5966);
    expect(t['category_id'], 'sys:income');
    final settings = SettingsRepository(SettingsDao(w.db));
    final auto = await settings.get(Settings.paydayAuto);
    expect(auto.bannerPending, isTrue);
    expect(auto.autoDay, isNotNull);
    expect(auto.autoDay, lessThanOrEqualTo(28));
    expect(await settings.get(Settings.paydayDay), auto.autoDay);
  });
}
