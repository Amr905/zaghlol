// T-155: CSV import. Synthetic data only.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/export_import/application/export.dart';
import 'package:zaghlol/features/export_import/application/import_csv.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

class FakeStore implements CsvImportStore {
  FakeStore({this.accounts = const {'a1'}, this.categories = const {'c1'}});
  final Set<String> accounts;
  final Set<String> categories;
  final List<ImportedTxn> rows = [];
  int txCalls = 0;
  bool failOnInsertN = false;

  @override
  Future<T> inWriteTransaction<T>(Future<T> Function() body) async {
    txCalls++;
    final snapshot = List.of(rows);
    try {
      return await body();
    } catch (_) {
      rows
        ..clear()
        ..addAll(snapshot);
      rethrow;
    }
  }

  @override
  Future<Set<String>> accountIds() async => accounts;
  @override
  Future<Set<String>> categoryIds() async => categories;
  @override
  Future<List<ExistingTxnKey>> existingAt(String a, int ms) async => [
    for (final r in rows)
      if (r.accountId == a && r.occurredAt.millisecondsSinceEpoch == ms)
        ExistingTxnKey(
          direction: r.direction,
          amount: r.amount,
          merchant: r.merchant,
        ),
  ];
  @override
  Future<void> insert(ImportedTxn row) async {
    if (failOnInsertN && rows.length == 1) throw StateError('boom');
    rows.add(row);
  }
}

TransactionRecord rec(
  int i, {
  String? merchant,
  String? note,
  String cur = 'EGP',
  int minor = 12345,
  TxnDirection dir = TxnDirection.expense,
  TxnStatus status = TxnStatus.posted,
  Money? original,
  String? category,
  DateTime? at,
}) => TransactionRecord(
  id: 't$i',
  accountId: 'a1',
  source: TxnSource.manual,
  direction: dir,
  status: status,
  amount: Money(Currency.of(cur), minor),
  originalAmount: original,
  occurredAt: at ?? DateTime.utc(2026, 1, 31, 23, 59, i),
  occurredTzOffsetMin: 120,
  merchantRaw: merchant,
  categoryId: category,
  note: note,
  categorySource: CategorySource.none,
  isUserVerified: true,
  isInternal: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Uint8List csvOf(List<TransactionRecord> rs) =>
    encodeCsv([exportHeader, ...rs.map(exportRow)]);

Uint8List raw(String s) => Uint8List.fromList(utf8.encode(s));

String hdr() => '${exportHeader.join(',')}\r\n';

String line({
  String date = '2026-02-01T10:00:00.000Z',
  String off = '120',
  String acc = 'a1',
  String type = 'expense',
  String status = 'posted',
  String amount = '10.50',
  String cur = 'EGP',
  String oa = '',
  String oc = '',
  String merchant = 'Shop',
  String cat = '',
  String note = '',
}) =>
    'x,$date,$off,$acc,$type,$status,$amount,$cur,$oa,$oc,$merchant,$cat,csv,$note\r\n';

void main() {
  late FakeStore store;
  late ImportCsvUseCase uc;
  setUp(() {
    store = FakeStore();
    uc = ImportCsvUseCase(store);
  });

  Future<String?> code(Future<Object?> f) async {
    try {
      await f;
      return null;
    } on ImportCsvException catch (e) {
      return e.code;
    }
  }

  group('AC: re-importing an export creates no duplicates', () {
    test('export -> import into empty -> import again: 0 new', () async {
      final bytes = csvOf([
        rec(1, merchant: 'Café', note: 'a,b "q"\nline2', category: 'c1'),
        rec(
          2,
          cur: 'KWD',
          minor: 1250,
          original: Money(Currency.of('USD'), 400),
          status: TxnStatus.pending,
        ),
        rec(3, cur: 'JPY', minor: 500, dir: TxnDirection.income),
      ]);
      final first = await uc.run(bytes);
      expect(first.imported, 3);
      expect(first.duplicates, 0);
      expect(store.rows.map((r) => r.amount.toStorage()).toList(), [
        (minor: 12345, currency: 'EGP'),
        (minor: 1250, currency: 'KWD'),
        (minor: 500, currency: 'JPY'),
      ]);
      expect(store.rows[0].note, 'a,b "q"\nline2');
      expect(store.rows[1].status, TxnStatus.pending);
      expect(store.rows[1].originalAmount!.toStorage().minor, 400);
      expect(store.rows[0].categoryId, 'c1');
      final again = await uc.run(bytes);
      expect(again.imported, 0);
      expect(again.duplicates, 3);
      expect(store.rows.length, 3);
    });

    test('duplicate key uses storage terms: 10.5 vs 10.50 vs 010.5', () async {
      await uc.run(raw(hdr() + line(amount: '10.5')));
      final s = await uc.run(
        raw(hdr() + line(amount: '010.50') + line(amount: '10.50')),
      );
      expect(s.imported, 1); // two file rows, one existing -> second is new
      expect(s.duplicates, 1);
    });

    test('two identical purchases in one file both import once', () async {
      final s = await uc.run(raw(hdr() + line() + line()));
      expect(s.imported, 2);
      final s2 = await uc.run(raw(hdr() + line() + line()));
      expect(s2.imported, 0);
      expect(s2.duplicates, 2);
    });

    test(
      'different currency, amount, direction or merchant is not a dup',
      () async {
        await uc.run(raw(hdr() + line()));
        final s = await uc.run(
          raw(
            hdr() +
                line(cur: 'USD') +
                line(amount: '10.51') +
                line(type: 'income') +
                line(merchant: 'Other'),
          ),
        );
        expect(s.imported, 4);
      },
    );
  });

  group('exact money and digits', () {
    test('Arabic-Indic digits and separator parse exactly', () async {
      final s = await uc.run(
        raw(
          hdr() +
              line(
                amount: '"١٢٣٫٤٥"',
                date: '٢٠٢٦-٠٢-٠١T١٠:٠٠:٠٠.٠٠٠Z',
                off: '١٢٠',
              ),
        ),
      );
      expect(s.imported, 1);
      expect(store.rows.single.amount.toStorage().minor, 12345);
      expect(store.rows.single.occurredTzOffsetMin, 120);
    });

    test(
      'no double: 0.1+0.2 style and huge values are exact or rejected',
      () async {
        final s = await uc.run(
          raw(
            hdr() +
                line(amount: '9007199254740.99') +
                line(amount: '9007199254740.992') + // too many fraction digits
                line(amount: '99999999999999999999') +
                line(amount: '-5') +
                line(amount: '1e3') +
                line(amount: '"1,5"') +
                line(amount: ''),
          ),
        );
        expect(s.imported, 1);
        expect(store.rows.single.amount.toStorage().minor, 900719925474099);
        expect(s.invalidByProblem[ImportRowProblem.badAmount], 6);
      },
    );

    test('JPY has no fraction, KWD has three', () async {
      final s = await uc.run(
        raw(
          hdr() +
              line(amount: '5', cur: 'JPY') +
              line(amount: '5.5', cur: 'JPY') +
              line(amount: '1.250', cur: 'KWD'),
        ),
      );
      expect(s.imported, 2);
      expect(s.invalid, 1);
    });

    test('unknown currency and half original amount are invalid', () async {
      final s = await uc.run(
        raw(
          hdr() +
              line(cur: 'ZZZ') +
              line(oa: '4.00') +
              line(oa: '4.00', oc: 'USD'),
        ),
      );
      expect(s.invalidByProblem[ImportRowProblem.badAmount], 1);
      expect(s.invalidByProblem[ImportRowProblem.badOriginalAmount], 1);
      expect(s.imported, 1);
    });
  });

  group('untrusted input', () {
    test(
      'formula-injected cells are stored as text; added apostrophe removed',
      () async {
        final s = await uc.run(
          csvOf([rec(1, merchant: '=HYPERLINK("x")', note: '@cmd')]),
        );
        expect(s.imported, 1);
        expect(store.rows.single.merchant, '=HYPERLINK("x")');
        expect(store.rows.single.note, '@cmd');
      },
    );

    test(
      'a raw formula cell without apostrophe is kept as inert text',
      () async {
        await uc.run(raw(hdr() + line(merchant: '=1+1')));
        expect(store.rows.single.merchant, '=1+1');
      },
    );

    test('control characters removed; text capped', () async {
      await uc.run(
        raw(hdr() + line(merchant: 'a\u0000b\u0007c') + line(note: 'n' * 3000)),
      );
      expect(store.rows[0].merchant, 'abc');
      expect(store.rows[1].note!.length, importMaxNoteRunes);
    });

    test('cell longer than cap invalidates only its row', () async {
      final s = await uc.run(
        raw(hdr() + line(note: 'x' * (importMaxCellRunes + 1)) + line()),
      );
      expect(s.invalidByProblem[ImportRowProblem.cellTooLong], 1);
      expect(s.imported, 1);
    });

    test(
      'file over the byte cap, bad UTF-8, bad header, unbalanced quote',
      () async {
        expect(
          await code(uc.run(Uint8List(importMaxBytes + 1))),
          ImportCsvException.tooLarge,
        );
        expect(
          await code(uc.run(Uint8List.fromList([...raw(hdr()), 0xFF, 0xFE]))),
          ImportCsvException.notUtf8,
        );
        expect(
          await code(uc.run(raw('a,b,c\r\n1,2,3\r\n'))),
          ImportCsvException.badHeader,
        );
        expect(await code(uc.run(raw(''))), ImportCsvException.badHeader);
        expect(
          await code(uc.run(raw('${hdr()}x,"unterminated\r\n'))),
          ImportCsvException.malformed,
        );
        expect(
          await code(uc.run(raw('${hdr()}x,ab"c,d\r\n'))),
          ImportCsvException.malformed,
        );
        expect(store.rows, isEmpty);
      },
    );

    test('row cap', () async {
      final b = StringBuffer(hdr());
      for (var i = 0; i <= importMaxRows; i++) {
        b.write('\n');
        b.write('x,');
      }
      expect(
        await code(uc.run(raw(b.toString()))),
        ImportCsvException.tooManyRows,
      );
    });

    test('wrong column count, bad date/offset/type/status/account', () async {
      final s = await uc.run(
        raw(
          '${hdr()}a,b\r\n'
          '${line(date: '2026-02-01T10:00:00+02:00')}'
          '${line(date: '1999-01-01T00:00:00Z')}'
          '${line(off: '5000')}'
          '${line(type: 'bogus')}'
          '${line(status: 'bogus')}'
          '${line(acc: 'nope')}',
        ),
      );
      expect(s.invalidByProblem, {
        ImportRowProblem.columnCount: 1,
        ImportRowProblem.badDate: 2,
        ImportRowProblem.badOffset: 1,
        ImportRowProblem.badDirection: 1,
        ImportRowProblem.badStatus: 1,
        ImportRowProblem.unknownAccount: 1,
      });
      expect(s.invalidRows, [1, 2, 3, 4, 5, 6, 7]);
      expect(s.imported, 0);
    });

    test('unknown category is dropped, not an error', () async {
      await uc.run(raw(hdr() + line(cat: 'zzz')));
      expect(store.rows.single.categoryId, isNull);
    });

    test('BOM, LF-only line ends and blank lines are accepted', () async {
      final s = await uc.run(
        raw(
          '\u{FEFF}${exportHeader.join(',')}\n\n'
          'x,2026-02-01T10:00:00.000Z,0,a1,expense,posted,1,EGP,,,S,,csv,\n',
        ),
      );
      expect(s.imported, 1);
    });

    test('summary and exceptions never carry row content', () async {
      const sentinel = 'SENTINEL_MERCHANT';
      final s = await uc.run(
        raw(hdr() + line(merchant: sentinel, amount: 'bad')),
      );
      expect(s.invalidByProblem.toString().contains(sentinel), isFalse);
      try {
        await uc.run(raw('${hdr()}$sentinel,"x'));
      } on ImportCsvException catch (e) {
        expect(e.toString().contains(sentinel), isFalse);
      }
    });
  });

  group('safety', () {
    test('one write transaction; failure part-way leaves nothing', () async {
      store.failOnInsertN = true;
      await expectLater(
        uc.run(raw(hdr() + line() + line(amount: '2') + line(amount: '3'))),
        throwsA(isA<StateError>()),
      );
      expect(store.rows, isEmpty);
      expect(store.txCalls, 1);
    });

    test('import only inserts (existing rows untouched)', () async {
      await uc.run(raw(hdr() + line(amount: '1')));
      final before = List.of(store.rows);
      await uc.run(raw(hdr() + line(amount: '1') + line(amount: '2')));
      expect(store.rows.first, same(before.first));
      expect(store.rows.length, 2);
    });
  });
}
