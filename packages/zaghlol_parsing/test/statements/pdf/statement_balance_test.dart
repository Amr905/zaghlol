// T-156b: running-balance validation, year-less dates, currency markers,
// header synonyms and repeated tables.

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

PdfTextFragment f(String s, int a, int b, int y, {int page = 1}) =>
    PdfTextFragment(page: page, text: s, x0: a, x1: b, y: y);

final usd = Currency.of('USD');

/// Date | Description | Debit | Credit | Balance, one row per entry:
/// (date, text, debit, credit, balance).
List<PdfTextFragment> table(
  List<(String, String, String, String, String)> rows, {
  List<String> header = const [
    'Date',
    'Description',
    'Debit',
    'Credit',
    'Balance',
  ],
  int y0 = 100,
  int page = 1,
}) {
  final out = <PdfTextFragment>[
    f(header[0], 40, 80, y0, page: page),
    f(header[1], 170, 260, y0, page: page),
    f(header[2], 540, 600, y0, page: page),
    f(header[3], 660, 720, y0, page: page),
    f(header[4], 820, 880, y0, page: page),
  ];
  var y = y0 + 20;
  for (final r in rows) {
    out.add(f(r.$1, 40, 110, y, page: page));
    out.add(f(r.$2, 170, 170 + r.$2.length * 8, y, page: page));
    if (r.$3.isNotEmpty) out.add(f(r.$3, 540, 600, y, page: page));
    if (r.$4.isNotEmpty) out.add(f(r.$4, 660, 720, y, page: page));
    out.add(f(r.$5, 790, 880, y, page: page));
    y += 20;
  }
  return out;
}

StatementMapping mapping(
  StatementTable t, {
  List<StatementColumnRole>? roles,
  Currency? currency,
}) => StatementMapping(
  roles: roles ?? t.suggestedRoles,
  currency: currency ?? usd,
  dayFirst: t.dayFirst,
);

final DateTime today = DateTime(2026, 11, 18);

void main() {
  group('running balance', () {
    final good = [
      ('03/01/2026', 'A', '10.00', '', '90.00'),
      ('03/02/2026', 'B', '', '5.00', '95.00'),
      ('03/03/2026', 'C', '20.00', '', '75.00'),
    ];
    final opening = [
      f('Opening balance', 40, 150, 60),
      f('100.00', 790, 880, 60),
    ];

    test('a row whose balance does not add up is flagged, not guessed', () {
      final bad = [good[0], ('03/02/2026', 'B', '', '5.00', '96.00'), good[2]];
      final t = buildStatementTable([...opening, ...table(bad)], today: today);
      final r = parseStatementRows(t, mapping(t));
      // B is off by one; C follows B's printed balance (96 - 20 = 76 != 75).
      expect(r.problems[StatementRowProblem.balanceMismatch], 2);
      expect(r.rows.map((x) => x.description).toList(), ['A']);
      expect(r.invalidRows, [2, 3]);
    });

    test('debit and credit swapped on one row is caught', () {
      final swapped = [
        good[0],
        ('03/02/2026', 'B', '5.00', '', '95.00'), // printed as debit
        good[2],
      ];
      final t = buildStatementTable([
        ...opening,
        ...table(swapped),
      ], today: today);
      final r = parseStatementRows(t, mapping(t));
      expect(r.problems[StatementRowProblem.balanceMismatch], 1);
      expect(r.rows.map((x) => x.description).toList(), ['A', 'C']);
    });

    test('all rows verified when the chain holds', () {
      final t = buildStatementTable([...opening, ...table(good)], today: today);
      final r = parseStatementRows(t, mapping(t));
      expect(r.rows, hasLength(3));
      expect(r.balanceChecked, 3);
      expect(r.rows.every((x) => x.balanceChecked), isTrue);
    });

    test(
      'without an opening balance the first row is unchecked, the rest are',
      () {
        final t = buildStatementTable(table(good), today: today);
        final r = parseStatementRows(t, mapping(t));
        expect(r.rows, hasLength(3));
        expect(r.balanceChecked, 2);
        expect(r.rows.first.balanceChecked, isFalse);
      },
    );

    test('newest-first statements are verified in reverse', () {
      final t = buildStatementTable(
        table([good[2], good[1], good[0]]),
        today: today,
      );
      final r = parseStatementRows(t, mapping(t));
      expect(r.rows, hasLength(3));
      expect(r.invalid, 0);
      expect(r.balanceChecked, 2);
      expect(r.rows.map((x) => x.description).toList(), ['C', 'B', 'A']);
    });

    test('closing balance that differs is reported', () {
      final t = buildStatementTable([
        ...opening,
        f('Closing balance', 40, 150, 300),
        f('999.00', 790, 880, 300),
        ...table(good),
      ], today: today);
      final r = parseStatementRows(t, mapping(t));
      expect(r.closingMatches, isFalse);
    });

    test('an unsigned amount column takes its direction from the balances', () {
      final frags = [
        f('Date', 40, 80, 100),
        f('Details', 170, 260, 100),
        f('Amount', 600, 660, 100),
        f('Balance', 820, 880, 100),
        f('Opening balance', 40, 150, 60),
        f('100.00', 790, 880, 60),
        f('03/01/2026', 40, 110, 120),
        f('A', 170, 190, 120),
        f('10.00', 600, 660, 120),
        f('90.00', 790, 880, 120),
        f('03/02/2026', 40, 110, 140),
        f('B', 170, 190, 140),
        f('5.00', 600, 660, 140),
        f('95.00', 790, 880, 140),
        f('03/03/2026', 40, 110, 160),
        f('C', 170, 190, 160),
        f('7.00', 600, 660, 160),
        f('50.00', 790, 880, 160), // does not add up: flagged
      ];
      final t = buildStatementTable(frags, today: today);
      final r = parseStatementRows(t, mapping(t));
      expect(r.rows.map((x) => x.isExpense).toList(), [true, false]);
      expect(r.problems[StatementRowProblem.balanceMismatch], 1);
    });
  });

  group('year-less dates', () {
    test('partial dates parse month first or day first', () {
      expect(
        parsePartialStatementDate('10/02', dayFirst: false),
        const PartialDate(10, 2),
      );
      expect(parsePartialStatementDate('10/02'), const PartialDate(2, 10));
      expect(parsePartialStatementDate('Oct 10'), const PartialDate(10, 10));
      expect(parsePartialStatementDate('10 Oct'), const PartialDate(10, 10));
      expect(parsePartialStatementDate('١٠/٠٢'), const PartialDate(2, 10));
      expect(parsePartialStatementDate('12.50'), isNull);
      expect(parsePartialStatementDate('13/13'), isNull);
      expect(parsePartialStatementDate('10/02/2026'), isNull);
    });

    test('day-first is read from the dates', () {
      expect(detectDayFirst(['10/30/2026', '01/02/2026']), isFalse);
      expect(detectDayFirst(['30/10/2026']), isTrue);
      expect(detectDayFirst(['10/30', '13/01']), isNull);
      expect(detectDayFirst(['01/02/2026']), isNull);
      expect(detectDayFirst(['2026-01-30']), isNull);
    });

    test('rollover Dec to Jan, in both orders', () {
      const anchor = StatementDate(2026, 1, 20);
      final asc = resolveStatementYears(const [
        PartialDate(12, 30),
        PartialDate(12, 31),
        PartialDate(1, 2),
      ], anchor: anchor);
      expect(asc, const [
        StatementDate(2025, 12, 30),
        StatementDate(2025, 12, 31),
        StatementDate(2026, 1, 2),
      ]);
      final desc = resolveStatementYears(const [
        PartialDate(1, 2),
        PartialDate(12, 31),
        PartialDate(12, 30),
      ], anchor: anchor);
      expect(desc, const [
        StatementDate(2026, 1, 2),
        StatementDate(2025, 12, 31),
        StatementDate(2025, 12, 30),
      ]);
    });

    test('a statement that ends after the anchor falls back a year', () {
      final r = resolveStatementYears(const [
        PartialDate(10, 2),
        PartialDate(11, 9),
      ], anchor: const StatementDate(2026, 11, 8));
      expect(r.last, const StatementDate(2025, 11, 9));
    });

    test('a full date printed outside the table is the anchor', () {
      final frags = [
        f('Statement period 01 Nov 2024 to 30 Nov 2024', 40, 500, 40),
        ...table([
          ('11/25', 'A', '10.00', '', '90.00'),
          ('11/26', 'B', '10.00', '', '80.00'),
        ]),
      ];
      final t = buildStatementTable(frags, today: today);
      final r = parseStatementRows(t, mapping(t));
      expect(r.rows.first.date, const StatementDate(2024, 11, 25));
    });

    test('Feb 29 in a non-leap year is a bad date, not a wrong one', () {
      final t = buildStatementTable(
        table([
          ('02/29', 'A', '10.00', '', '90.00'),
          ('03/01', 'B', '10.00', '', '80.00'),
        ]),
        today: DateTime(2026, 3, 10),
      );
      final r = parseStatementRows(t, mapping(t));
      expect(r.problems[StatementRowProblem.badDate], 1);
    });
  });

  group('amounts with currency markers', () {
    SignedAmount? p(String s, {Currency? c}) =>
        parseStatementAmount(s, currency: c ?? usd);
    test('symbols and codes are stripped, nothing converted', () {
      expect(p(r'$1,250.50')!.amount.minor, 125050);
      expect(p('£8,313.30', c: Currency.of('GBP'))!.amount.minor, 831330);
      expect(p('EGP 1,250.50', c: Currency.of('EGP'))!.amount.minor, 125050);
      expect(p('1,250.50 ج.م', c: Currency.of('EGP'))!.amount.minor, 125050);
      expect(p('1250 جنيه', c: Currency.of('EGP'))!.amount.minor, 125000);
      expect(p(r'-$9.98')!.negative, isTrue);
      expect(p(r'($9.98)')!.negative, isTrue);
      expect(p('.26')!.amount.minor, 26);
      expect(p(r'$ .26')!.amount.minor, 26);
      expect(p('abc'), isNull);
      expect(p('USD'), isNull);
    });

    test('a statement with one marker proposes its currency', () {
      final t = buildStatementTable(
        table([
          ('01/02/2026', 'A', r'£10.00', '', r'£90.00'),
          ('01/03/2026', 'B', '', r'£5.00', r'£95.00'),
        ]),
        today: today,
      );
      expect(t.suggestedCurrency?.code, 'GBP');
      final r = parseStatementRows(t, mapping(t, currency: Currency.of('GBP')));
      expect(r.rows, hasLength(2));
      expect(r.rows.first.amount.minor, 1000);
    });

    test('two currencies on one statement propose none', () {
      final t = buildStatementTable(
        table([
          ('01/02/2026', 'A', r'$10.00', '', r'$90.00'),
          ('01/03/2026', 'B', '', r'£5.00', r'£95.00'),
        ]),
        today: today,
      );
      expect(t.suggestedCurrency, isNull);
    });

    test('EGP markers in Arabic and Latin', () {
      final t = buildStatementTable(
        table([
          ('02/01/2026', 'A', '10.00 ج.م', '', '90.00 ج.م'),
          ('03/01/2026', 'B', '', '5.00 ج.م', '95.00 ج.م'),
        ]),
        today: today,
      );
      expect(t.suggestedCurrency?.code, 'EGP');
    });
  });

  group('header synonyms', () {
    StatementTable read(List<String> h) => buildStatementTable(
      table([
        ('01/02/2026', 'A', '10.00', '', '90.00'),
        ('01/03/2026', 'B', '', '5.00', '95.00'),
      ], header: h),
      today: today,
    );
    const expected = [
      StatementColumnRole.date,
      StatementColumnRole.description,
      StatementColumnRole.debit,
      StatementColumnRole.credit,
      StatementColumnRole.balance,
    ];
    test('English variants', () {
      for (final h in const [
        ['Date', 'Narrative', 'Withdrawals', 'Deposits', 'Balance'],
        ['Transaction Date', 'Detail', 'Paid Out', 'Paid In', 'Balance'],
        ['Date', 'Particulars', 'Money Out', 'Money In', 'Balance'],
        ['Date', 'Description', 'Amount Out', 'Amount In', 'Balance'],
      ]) {
        expect(read(h).suggestedRoles, expected, reason: h.join(','));
        expect(read(h).confident, isTrue);
      }
    });
    test('Egyptian Arabic', () {
      final t = read(const ['التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد']);
      expect(t.suggestedRoles, expected);
    });
    test('payment type is not a description', () {
      final t = buildStatementTable([
        f('Date', 40, 80, 100),
        f('Payment Type', 140, 230, 100),
        f('Detail', 300, 360, 100),
        f('Paid In', 560, 620, 100),
        f('Paid Out', 680, 740, 100),
        f('Balance', 820, 880, 100),
        f('01/02/2026', 40, 110, 120),
        f('BACS', 140, 190, 120),
        f('SHOP', 300, 340, 120),
        f('10.00', 680, 740, 120),
        f('90.00', 810, 880, 120),
      ], today: today);
      expect(t.suggestedRoles[1], StatementColumnRole.ignore);
      expect(t.suggestedRoles[2], StatementColumnRole.description);
    });
  });

  group('repeated tables', () {
    test('a later section that repeats the first is dropped', () {
      final rows = [
        ('01/02/2026', 'SHOP A', '10.00', '', '90.00'),
        ('01/03/2026', 'SHOP B', '5.00', '', '85.00'),
        ('01/04/2026', 'SHOP C', '', '20.00', '105.00'),
      ];
      final t = buildStatementTable([
        ...table(rows),
        ...table(rows, y0: 300, page: 2),
      ], today: today);
      final r = parseStatementRows(t, mapping(t));
      expect(r.rows, hasLength(3));
    });

    test('a continuation page with new rows is kept', () {
      final p1 = [
        ('01/02/2026', 'SHOP A', '10.00', '', '90.00'),
        ('01/03/2026', 'SHOP B', '5.00', '', '85.00'),
      ];
      final p2 = [
        ('01/04/2026', 'SHOP C', '', '20.00', '105.00'),
        ('01/05/2026', 'SHOP D', '5.00', '', '100.00'),
      ];
      final t = buildStatementTable([
        ...table(p1),
        ...table(p2, y0: 300, page: 2),
      ], today: today);
      final r = parseStatementRows(t, mapping(t));
      expect(r.rows, hasLength(4));
      expect(r.invalid, 0);
    });

    test('two identical purchases on one day are both kept', () {
      final t = buildStatementTable(
        table([
          ('01/02/2026', 'COFFEE', '3.00', '', '97.00'),
          ('01/02/2026', 'COFFEE', '3.00', '', '94.00'),
        ]),
        today: today,
      );
      final r = parseStatementRows(t, mapping(t));
      expect(r.rows, hasLength(2));
    });
  });

  group('end and summary rows', () {
    test('totals row and brought forward row are not transactions', () {
      final frags = [
        ...table([
          ('01/02/2026', 'A', '10.00', '', '90.00'),
          ('01/03/2026', 'B', '5.00', '', '85.00'),
        ]),
        f('Total', 40, 90, 170),
        f('15.00', 540, 600, 170),
        f('Closing Balance', 40, 150, 190),
        f('85.00', 790, 880, 190),
      ];
      final t = buildStatementTable(frags, today: today);
      final r = parseStatementRows(t, mapping(t));
      expect(r.rows, hasLength(2));
      expect(r.rows.last.description, 'B');
      expect(t.closingBalance, '85.00');
    });
  });
}
