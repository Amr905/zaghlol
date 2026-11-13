// T-102: the repository's hand-edit methods behind S-24 / S-25.
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/recurring_dao.dart';
import 'package:zaghlol/core/db/money_columns.dart';
import 'package:zaghlol/features/recurring/data/recurring_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../core/db/financial_fixtures.dart';

final egp = Currency.of('EGP');

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late RecurringRepository repo;
  var n = 0;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    n = 0;
    await db.into(db.accounts).insert(account('acc1'));
    repo = RecurringRepository(
      db,
      clock: () => DateTime.utc(2026, 11, 13, 12),
      newId: () => 'id${++n}',
    );
  });
  tearDown(() => edb.close());

  Future<String> add(String kind, {int? total}) => repo.addManual(
    kind: kind,
    name: 'Fridge',
    amount: Money(egp, 100000),
    dueDay: 5,
    totalCount: total,
    merchantNorm: 'fridge',
    nextDue: CivilDate(2026, 11, 5),
  );

  test('markPaidManual counts the payment and moves the due date', () async {
    final id = await add(RecurringKind.installment, total: 3);
    expect(await repo.markPaidManual(id), isTrue);
    final r = (await RecurringDao(db).itemById(id))!;
    expect(r.paidCount, 1);
    expect(r.nextDueDate, '2026-12-05');
    expect(await RecurringDao(db).occurrencesOf(id), hasLength(1));
  });

  test('the last manual payment completes the item', () async {
    final id = await add(RecurringKind.installment, total: 1);
    expect(await repo.markPaidManual(id), isTrue);
    expect((await RecurringDao(db).itemById(id))!.status, 'completed');
    expect(await repo.markPaidManual(id), isFalse);
  });

  test('a card due cannot be marked paid by hand', () async {
    final id = await add(RecurringKind.cardDue);
    expect(await repo.markPaidManual(id), isFalse);
    expect((await RecurringDao(db).itemById(id))!.paidCount, 0);
  });

  test('updateManual edits in place and validates', () async {
    final id = await add(RecurringKind.installment, total: 6);
    final ok = await repo.updateManual(
      id,
      kind: RecurringKind.installment,
      name: 'Washer',
      amount: Money(egp, 25000),
      dueDay: 9,
      nextDue: CivilDate(2026, 12, 9),
      totalCount: 4,
      paidCount: 4,
    );
    expect(ok, isTrue);
    final r = (await RecurringDao(db).itemById(id))!;
    expect(r.name, 'Washer');
    expect(r.amount, Money(egp, 25000));
    expect(r.status, 'completed');
    await expectLater(
      repo.updateManual(
        id,
        kind: RecurringKind.installment,
        name: 'X',
        amount: Money(egp, 100),
        dueDay: 9,
        nextDue: CivilDate(2026, 12, 9),
        totalCount: 2,
        paidCount: 3,
      ),
      throwsA(isA<RecurringException>()),
    );
  });

  test('deleteItem removes the item and its occurrences', () async {
    final id = await add(RecurringKind.installment, total: 3);
    await repo.markPaidManual(id);
    expect(await repo.deleteItem(id), isTrue);
    expect(await RecurringDao(db).itemById(id), isNull);
    expect(await repo.deleteItem(id), isFalse);
  });
}
