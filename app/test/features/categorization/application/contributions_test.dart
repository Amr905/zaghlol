// T-142: contribution opt-in and outbox. Synthetic data only.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/outbound_text_filter.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/outbox_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/categorization/application/contributions.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late SettingsRepository settings;
  late ContributionQueue queue;
  var n = 0;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    n = 0;
    settings = SettingsRepository(SettingsDao(db));
    await CategoriesDao(db).upsertSystem(
      code: 'groceries',
      nameAr: 'بقالة',
      nameEn: 'Groceries',
      icon: 'cart',
      color: '#0F7A55',
      bucket: 'needs',
      sort: 1,
    );
    queue = ContributionQueue(
      db,
      settings,
      clock: () => DateTime.utc(2026, 11, 13),
      newId: () => 'c${++n}',
    );
  });
  tearDown(() => edb.close());

  Future<ContributionDecision> offer(
    String name, {
    String category = 'groceries',
    bool p2p = false,
    String? display,
  }) => queue.offer(
    merchantNorm: name,
    institutionCode: 'nbe',
    categoryCode: category,
    isPersonTransfer: p2p,
    displayName: display,
  );

  Future<void> optIn() => queue.setOptIn(true);

  test('opt-in defaults off', () async {
    expect(await settings.get(Settings.contributionOptIn), isFalse);
  });

  test('NEGATIVE PROOF: with opt-in off nothing is queued', () async {
    expect(await offer('seoudi market'), ContributionDecision.optedOut);
    expect(await queue.queuedCount(), 0);
  });

  test(
    'queues exactly {merchantNorm, institutionCode, categoryCode}',
    () async {
      await optIn();
      expect(await offer('seoudi market'), ContributionDecision.queued);
      final rows = await OutboxDao(db).due(now: 1 << 50);
      expect(rows, hasLength(1));
      expect(rows.single.kind, OutboxKind.contribution);
      expect(jsonDecode(rows.single.payload), {
        'merchantNorm': 'seoudi market',
        'institutionCode': 'nbe',
        'categoryCode': 'groceries',
      });
    },
  );

  test('privacy contract: payload keys are the allow-list and no value is '
      'an amount, date, card, phone or address', () async {
    await optIn();
    await offer('seoudi market');
    final p = jsonDecode(
      (await OutboxDao(db).due(now: 1 << 50)).single.payload,
    ) as Map<String, Object?>;
    expect(p.keys.toSet(), {'merchantNorm', 'institutionCode', 'categoryCode'});
    for (final v in p.values) {
      expect(hasPersonalDataMarks(v! as String), isFalse);
    }
  });

  test('NEGATIVE PROOF: names with phone, card, e-mail or IPA never reach '
      'the outbox (Latin, Arabic-Indic, fullwidth digits)', () async {
    await optIn();
    for (final bad in [
      'shop 01012345678',
      'shop 4111 1111 1111',
      'shop 12345',
      'shop ٠١٠١٢٣٤٥٦٧٨',
      'shop １２３４５６',
      'shop 0-1-0-1-2-3',
      'ali@instapay',
      'ali＠bank',
      'shop +201012345678',
      'x​1​2​3​4​5',
    ]) {
      expect(await offer(bad), ContributionDecision.personalData, reason: bad);
    }
    expect(await offer('shop 1234'), ContributionDecision.queued);
    expect(await queue.queuedCount(), 1);
  });

  test('person-to-person, person names, custom categories and bad codes '
      'are dropped', () async {
    await optIn();
    expect(
      await offer('seoudi market', p2p: true),
      ContributionDecision.personTransfer,
    );
    expect(
      await offer('x', display: 'Ahmed Hassan'),
      ContributionDecision.invalid,
    );
    expect(
      await offer('ahmed hassan', display: 'Ahmed Hassan'),
      ContributionDecision.personName,
    );
    expect(
      await offer('mohamed ali', display: 'محمد علي'),
      ContributionDecision.personName,
    );
    expect(await offer('cafe nour'), ContributionDecision.queued);
    expect(
      await offer('seoudi market', category: 'my_custom'),
      ContributionDecision.customCategory,
    );
    expect(
      await offer('seoudi market', category: 'Bad Code'),
      ContributionDecision.invalid,
    );
    expect(await offer('a'), ContributionDecision.invalid);
    expect(await offer('a' * 65), ContributionDecision.invalid);
    expect(await queue.queuedCount(), 1);
  });

  test('looksLikePersonName ignores merchants', () {
    expect(
      looksLikePersonName('Carrefour Maadi'),
      isTrue,
    ); // accepted: heuristic
    expect(looksLikePersonName('Seoudi Market'), isFalse);
    expect(looksLikePersonName('Hany Pharmacy'), isFalse);
    expect(looksLikePersonName('Zaghlol'), isFalse);
  });

  test('the same contribution is queued once', () async {
    await optIn();
    expect(await offer('seoudi market'), ContributionDecision.queued);
    expect(await offer('seoudi market'), ContributionDecision.duplicate);
    expect(await queue.queuedCount(), 1);
  });

  test('queue is capped', () async {
    await optIn();
    for (var i = 0; i < maxQueuedContributions; i++) {
      expect(await offer('shop ${'abcdefghij'[i % 10]}${i ~/ 10}x'), isNotNull);
    }
    expect(await queue.queuedCount(), maxQueuedContributions);
    await expectLater(offer('one more'), throwsA(isA<ContributionException>()));
  });

  test(
    'opt-out deletes queued contributions only and keeps other kinds',
    () async {
      await optIn();
      await offer('seoudi market');
      await offer('cafe nour');
      await OutboxDao(db).enqueue(
        id: 'b1',
        kind: OutboxKind.bankRequest,
        payload: {
          'institutionName': 'Some Bank',
          'country': 'EG',
          'channel': 'sms',
        },
        createdAt: 1,
      );
      expect(await queue.setOptIn(false), 2);
      expect(await settings.get(Settings.contributionOptIn), isFalse);
      expect(await queue.queuedCount(), 0);
      expect((await OutboxDao(db).due(now: 1 << 50)).single.id, 'b1');
      expect(await offer('seoudi market'), ContributionDecision.optedOut);
    },
  );

  test('errors and decisions never echo the name', () async {
    await optIn();
    for (var i = 0; i < maxQueuedContributions; i++) {
      await offer('shop ${'abcdefghij'[i % 10]}${i ~/ 10}x');
    }
    try {
      await offer('sentinel merchant');
      fail('expected');
    } on ContributionException catch (e) {
      expect(e.toString(), isNot(contains('sentinel')));
    }
  });
}
