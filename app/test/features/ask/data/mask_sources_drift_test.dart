// T-343: MaskSourcesDrift (merchant ids are merchant_norm, accounts carry
// their ids, nothing is capped) and the registry short aliases (FU-399).
// Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
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
      expect(s.merchants, hasLength(602));
      expect(s.merchants.any((m) => m.names.contains('No Norm')), isFalse);
      final a = s.accounts.single;
      expect(
        [a.id, a.last4, a.institutionId, a.type],
        ['acc1', '4321', 'cib', MaskAccountType.creditCard],
      );
      expect(s.institutions.single.id, 'cib');
      expect(s.toString(), isNot(contains('Carrefour')));
    });
  });
}
