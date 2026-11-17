// CAT-cash / CAT-INSTAPAY (PO 2026-11-17): ATM withdrawals land in Cash,
// InstaPay transfers (template or generic cue) in InstaPay; a user's choice
// is never overwritten. Real bundled registry and Guard base, synthetic text.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart';
import 'package:zaghlol/features/categorization/data/categorizer_ports.dart';
import 'package:zaghlol/features/categorization/data/recategorizer.dart';
import 'package:zaghlol/features/categorization/data/rules_repository.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_rules.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show
        CategorizeTier,
        CategoryDecision,
        Categorizer,
        CategorySource,
        GenericEvent,
        TemplateEvent;

import '../features/ingestion/support/ingest_harness.dart';

final int _rx = DateTime.utc(2026, 11, 10, 10).millisecondsSinceEpoch;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = File('assets/guard/guard_base.json').readAsBytesSync();

  Future<
    (IngestWorld, Future<List<Map<String, Object?>>> Function(String, String))
  >
  open() async {
    final registry = await preloadBundledRegistry();
    final w = await IngestWorld.open();
    addTearDown(w.close);
    for (final c in ['cash', 'instapay', 'dining']) {
      await w.db
          .into(w.db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'sys:$c',
              systemCode: Value(c),
              nameAr: c,
              nameEn: c,
              icon: 'x',
              color: '#000000',
              bucket: 'wants',
              sort: 1,
            ),
          );
    }
    var n = 0;
    Future<List<Map<String, Object?>>> ingest(
      String sender,
      String body,
    ) async {
      final id = 'm${n++}';
      final r = await w.useCase(
        registry: registry,
        guardBase: BytesGuardBase(base),
      )([sms(id, body, source: sender, rx: _rx + n)]);
      expect(r.outcomes[id], isA<IngestInserted>());
      return w.txns();
    }

    return (w, ingest);
  }

  test('template ATM withdrawal is Cash', () async {
    final (_, ingest) = await open();
    final t = await ingest(
      'AlRajhiBank',
      'ATM Withdrawal\nBy: 4242;mada\nAmount: SAR 500.00',
    );
    expect(t.single['direction'], 'expense');
    expect(t.single['category_id'], 'sys:cash');
  });

  test('template InstaPay out is InstaPay, even to a person', () async {
    final (_, ingest) = await open();
    final t = await ingest(
      'InstaPay',
      'InstaPay: You transferred EGP 1,250.00 to ahmed.ali@instapay from '
          'A/C *4567. Ref: 62910482112',
    );
    expect(t.single['direction'], 'transfer_out');
    expect(t.single['category_id'], 'sys:instapay');
  });

  test('generic InstaPay cue (Arabic) is InstaPay; no cue is not', () async {
    final (_, ingest) = await open();
    expect(hasInstapayCue('تم تحويل عبر إنستاباي'), isTrue);
    expect(hasInstapayCue('Sent via InstaPay IPN'), isTrue);
    expect(hasInstapayCue('transfer to ipnoteworthy'), isFalse);
    expect(hasInstapayCue('Salary transfer'), isFalse);
    expect(eventCategoryOf(TemplateEvent.atmWithdrawal), 'sys:cash');
    expect(eventCategoryOf(TemplateEvent.cardPurchase), isNull);
    expect(
      genericEventCategoryOf(GenericEvent.transfer, instapay: true),
      'sys:instapay',
    );
    expect(
      genericEventCategoryOf(GenericEvent.transfer, instapay: false),
      isNull,
    );
    expect(
      genericEventCategoryOf(GenericEvent.withdrawal, instapay: false),
      'sys:cash',
    );
    final t = await ingest(
      'NBE',
      'Dear customer, you sent EGP 250.00 via InstaPay from your account '
          '*4567 to AHMED on 09/11/2026',
    );
    expect(t.single['category_id'], 'sys:instapay');
  });

  test('a user-chosen category sticks through re-categorize', () async {
    final (w, ingest) = await open();
    final t = await ingest(
      'AlRajhiBank',
      'ATM Withdrawal\nBy: 4242;mada\nAmount: SAR 500.00',
    );
    final id = t.single['id']! as String;
    // The user moves it to Dining (a verified, user-sourced edit).
    await (w.db.update(w.db.transactions)..where((x) => x.id.equals(id))).write(
      const TransactionsCompanion(
        categoryId: Value('sys:dining'),
        categorySource: Value('user'),
        isUserVerified: Value(1),
      ),
    );
    final categorizer = Categorizer(
      driftCategorizerPorts(
        w.db,
        DriftRulesRepository(
          MerchantRulesDao(w.db),
          CategoriesDao(w.db),
          clock: () => DateTime.utc(2026, 11, 10),
          newId: () => 'rule1',
        ),
      ),
      memoize: true,
    );
    await Recategorizer(w.db).run(categorizer, at: _rx);
    expect((await w.txns()).single['category_id'], 'sys:dining');
  });

  test(
    're-categorize: a catalog hit never replaces the event category',
    () async {
      final (w, ingest) = await open();
      final t = await ingest(
        'AlRajhiBank',
        'ATM Withdrawal\nBy: 4242;mada\nAmount: SAR 500.00',
      );
      final r = Recategorizer(w.db);
      final n = await r.apply(
        id: t.single['id']! as String,
        oldCategoryId: 'sys:cash',
        oldCatalogMerchantId: null,
        decision: const CategoryDecision(
          categoryId: 'sys:dining',
          source: CategorySource.catalog,
          tier: CategorizeTier.exact,
        ),
        at: _rx,
      );
      expect(n, 0);
      expect((await w.txns()).single['category_id'], 'sys:cash');
      expect(CategorySource.catalog.code, 'catalog');
    },
  );
}
