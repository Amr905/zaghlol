// T-343: MaskSourcesDrift (merchant ids are merchant_norm, accounts carry
// their ids, nothing is capped) and the registry short aliases (FU-399).
// Synthetic data only.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/ask/data/mask_sources_drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  group('FU-399 registry short aliases', () {
    test('Vodafone Cash gives the short forms', () {
      final a = aliasesOfInstitution(
        const InstitutionNames(
          code: 'vodafone_cash',
          nameAr: 'فودافون كاش',
          nameEn: 'Vodafone Cash',
        ),
      );
      final texts = [for (final x in a) foldKey(x.text)];
      expect(texts, containsAll(['vodafone cash', 'vodafone', 'فودافون']));
      expect(a.every((x) => !x.ordinaryWord), isTrue);
    });

    test('a generic lead is skipped and an everyday short form needs a bank '
        'word', () {
      final a = aliasesOfInstitution(
        const InstitutionNames(
          code: 'banque_misr',
          nameAr: 'بنك مصر',
          nameEn: 'Banque Misr',
        ),
      );
      final byKey = {for (final x in a) foldKey(x.text): x};
      expect(byKey['misr']?.ordinaryWord, isTrue);
      expect(byKey['مصر']?.ordinaryWord, isTrue);
      expect(byKey['banque misr']?.ordinaryWord, isFalse);
      expect(byKey.containsKey('banque'), isFalse);
      expect(byKey.containsKey('بنك'), isFalse);
    });

    test('through the masker: a short form is masked, an everyday one only '
        'next to a bank word', () {
      const cib = MaskAccount(
        id: 'a1',
        label: 'Main',
        institutionId: 'vodafone_cash',
        type: MaskAccountType.wallet,
        last4: null,
      );
      final sources = StaticMaskSources(
        accounts: const [cib],
        institutions: [
          MaskInstitution(
            'vodafone_cash',
            aliasesOfInstitution(
              const InstitutionNames(
                code: 'vodafone_cash',
                nameAr: 'فودافون كاش',
                nameEn: 'Vodafone Cash',
              ),
            ),
          ),
        ],
      );
      final o = ReferenceMasker.mask('how much is left in vodafone', sources);
      expect(o, isA<MaskResult>());
      expect(
        (o as MaskResult).sentText.toLowerCase(),
        isNot(contains('vodafone')),
      );
    });
  });

  group('MaskSourcesDrift', () {
    late EncryptedDb edb;
    setUp(() async => edb = await EncryptedDb.open(background: false));
    tearDown(() => edb.close());

    test('merchants: id is merchant_norm, all raw names kept, '
        'unnamed rows ignored, 600 merchants are not capped', () async {
      final db = edb.db;
      await db.into(db.accounts).insert(account('acc1'));
      var n = 0;
      for (final (norm, raw) in [
        ('carrefour', 'Carrefour Maadi'),
        ('carrefour', 'CARREFOUR*NASR'),
        ('talabat', 'TALABAT*EG'),
      ]) {
        await db
            .into(db.transactions)
            .insert(txn('t${n++}', merchant: raw, merchantNorm: norm));
      }
      for (var i = 0; i < 600; i++) {
        await db
            .into(db.transactions)
            .insert(txn('m$i', merchant: 'Shop $i', merchantNorm: 'shop $i'));
      }
      await db
          .into(db.transactions)
          .insert(txn('nn', merchant: 'No Norm', merchantNorm: null));
      final s = await MaskSourcesDrift.load(
        db,
        accounts: () async => [
          Account(
            id: 'acc1',
            kind: AccountKind.credit,
            label: 'My Visa',
            defaultCurrency: Currency.of('EGP'),
            isHidden: false,
            isDefaultCash: false,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            institutionCode: 'cib',
            last4: '4321',
          ),
        ],
        registry: const [
          InstitutionNames(code: 'cib', nameAr: 'التجاري', nameEn: 'CIB'),
        ],
      );
      final carrefour = s.merchants.singleWhere((m) => m.id == 'carrefour');
      expect(
        carrefour.names,
        unorderedEquals(['carrefour', 'Carrefour Maadi', 'CARREFOUR*NASR']),
      );
      // B94-M2: a row without merchant_norm is kept, id = its read-time key.
      expect(s.merchants, hasLength(603));
      expect(
        s.merchants.singleWhere((m) => m.names.contains('No Norm')).id,
        merchantKey('No Norm'),
      );
      final a = s.accounts.single;
      expect(
        [a.id, a.last4, a.institutionId, a.type],
        ['acc1', '4321', 'cib', MaskAccountType.creditCard],
      );
      expect(s.institutions.single.id, 'cib');
      expect(s.toString(), isNot(contains('Carrefour')));
    });

    test('FU-424: a hand-added recurring item name is a mask source, and a '
        'question naming it leaves with a placeholder', () async {
      final db = edb.db;
      Future<void> item(String id, String name, {String? norm}) => db
          .into(db.recurringItems)
          .insert(
            RecurringItemsCompanion.insert(
              id: id,
              kind: 'subscription',
              status: 'dismissed',
              name: name,
              merchantNorm: Value(norm),
              amountMinor: 10000,
              currency: 'EGP',
              cadence: 'monthly',
              createdAt: 1,
            ),
          );
      await item('r1', 'Zorbaplex Gym');
      await item('r2', 'Netflix Family', norm: 'netflix');
      final s = await MaskSourcesDrift.load(
        db,
        accounts: () async => const [],
        registry: const [],
      );
      expect(
        s.merchants.singleWhere((m) => m.id == merchantKey('Zorbaplex Gym')),
        isNotNull,
      );
      expect(
        s.merchants.singleWhere((m) => m.id == 'netflix').names,
        contains('Netflix Family'),
      );
      final o = ReferenceMasker.mask('what did Zorbaplex Gym cost me', s);
      expect(o, isA<MaskResult>());
      expect((o as MaskResult).sentText, isNot(contains('Zorbaplex')));
      expect(o.sentText, contains('MERCHANT'));
    });

    test('B94-M2: 5,000 transactions over 50 merchants load fast '
        '(deduped in SQL)', () async {
      final db = edb.db;
      await db.into(db.accounts).insert(account('acc1'));
      await db.batch(
        (b) => b.insertAll(db.transactions, [
          for (var i = 0; i < 5000; i++)
            txn(
              'p$i',
              merchant: 'Shop ${i % 50}',
              merchantNorm: i.isEven ? 'shop ${i % 50}' : null,
            ),
        ]),
      );
      final sw = Stopwatch()..start();
      final s = await MaskSourcesDrift.load(
        db,
        accounts: () async => const [],
        registry: const [],
      );
      sw.stop();
      expect(s.merchants, hasLength(50));
      expect(sw.elapsedMilliseconds, lessThan(200));
    });
  });
}
