// T-156: statement import against a real (in-memory encrypted) database:
// day-range duplicate check, `pdf` source, template persistence.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/export_import/application/import_statement_pdf.dart';
import 'package:zaghlol/features/export_import/data/drift_csv_import_store.dart';
import 'package:zaghlol/features/export_import/data/drift_statement_template_store.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';

class _X implements PdfTextExtractor {
  @override
  Future<List<PdfTextFragment>> extract(
    Uint8List b, {
    String? password,
  }) async => [
    const PdfTextFragment(page: 1, text: 'Date', x0: 40, x1: 80, y: 100),
    const PdfTextFragment(page: 1, text: 'Details', x0: 170, x1: 260, y: 100),
    const PdfTextFragment(page: 1, text: 'Amount', x0: 600, x1: 680, y: 100),
    const PdfTextFragment(page: 1, text: '05/01/2026', x0: 40, x1: 140, y: 120),
    const PdfTextFragment(page: 1, text: 'COFFEE', x0: 170, x1: 260, y: 120),
    const PdfTextFragment(page: 1, text: '-45.00', x0: 610, x1: 680, y: 120),
    const PdfTextFragment(page: 1, text: '06/01/2026', x0: 40, x1: 140, y: 140),
    const PdfTextFragment(page: 1, text: 'REFUND', x0: 170, x1: 260, y: 140),
    const PdfTextFragment(page: 1, text: '45.00', x0: 620, x1: 680, y: 140),
  ];
}

void main() {
  late EncryptedDb edb;
  late DriftTransactionRepository repo;
  late ImportStatementPdfUseCase uc;
  late DriftStatementTemplateStore templates;

  setUp(() async {
    edb = await EncryptedDb.open();
    final dao = TransactionsDao(edb.db);
    final accounts = AccountsDao(edb.db);
    await accounts.insert(account('acc1'));
    repo = DriftTransactionRepository(dao);
    templates = DriftStatementTemplateStore(SettingsDao(edb.db));
    uc = ImportStatementPdfUseCase(
      _X(),
      DriftCsvImportStore(edb.db, dao, accounts),
      templates,
    );
  });
  tearDown(() => edb.close());

  test('imports, skips an existing same-day row, saves the template', () async {
    // An SMS-captured row on the same local day, at 18:42.
    await repo.add(
      NewTransaction(
        accountId: 'acc1',
        direction: TxnDirection.expense,
        amount: Money.parse('45.00', Currency.of('EGP')),
        occurredAt: DateTime(2026, 1, 5, 18, 42).toUtc(),
        occurredTzOffsetMin: DateTime(2026, 1, 5).timeZoneOffset.inMinutes,
        merchant: 'Cafe',
      ),
    );
    final reading = await uc.open(
      Uint8List.fromList([1, 2, 3]),
      bankKey: 'cib',
    );
    expect(reading.needsMapping, isFalse);
    final mapping = StatementMapping(
      currency: Currency.of('EGP'),
      roles: const [
        StatementColumnRole.date,
        StatementColumnRole.description,
        StatementColumnRole.amount,
      ],
    );
    final s = await uc.run(reading, mapping, accountId: 'acc1');
    expect(s.duplicates, 1);
    expect(s.imported, 1);
    expect(await repo.count(), 2);
    final pdfRows = (await repo.query()).where(
      (r) => r.source == TxnSource.pdf,
    );
    expect(pdfRows.single.direction, TxnDirection.income);
    expect(pdfRows.single.amount.minor, 4500);

    final saved = await templates.load('cib');
    expect(saved!.mapping.roles, mapping.roles);
    expect(await templates.load('nbe'), isNull);
  });

  test('a corrupt stored template is ignored', () async {
    await SettingsDao(edb.db)
        .write(DriftStatementTemplateStore.keyFor('cib'), '{broken', at: 1);
    expect(await templates.load('cib'), isNull);
  });
}
