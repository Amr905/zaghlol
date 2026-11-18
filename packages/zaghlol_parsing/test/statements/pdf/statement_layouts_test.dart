// T-156b: three public statement layouts, recreated synthetically (no real
// data): US credit/debit with a summary block, UK paid in/out with a brought
// forward row, and a scanned US statement without years whose second page
// repeats the transactions by type. Coordinates follow the layouts' own
// proportions; text is invented.

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

final DateTime today = DateTime(2026, 11, 18);

// A4-ish page 1240 px wide: x in px -> permille.
int pm(num px, num width) => (px * 1000 / width).round();

PdfTextFragment t(
  String text,
  num x0,
  num x1,
  num y, {
  required num w,
  int page = 1,
}) => PdfTextFragment(
  page: page,
  text: text,
  x0: pm(x0, w),
  x1: pm(x1, w),
  y: y.round(),
);

StatementMapping mapOf(
  StatementTable table,
  String currency, {
  List<StatementColumnRole>? roles,
}) => StatementMapping(
  roles: roles ?? table.suggestedRoles,
  currency: Currency.of(currency),
  dayFirst: table.dayFirst,
);

int sum(List<StatementRow> rows, {required bool expense}) => rows
    .where((r) => r.isExpense == expense)
    .fold(0, (a, r) => a + r.amount.minor);

// ---------------------------------------------------------------------------
// Layout 1: Date | Description | Credit | Debit | Balance, summary above.

List<PdfTextFragment> layout1() {
  const w = 1240;
  PdfTextFragment f(String s, num a, num b, num y) => t(s, a, b, y, w: w);
  PdfTextFragment right(String s, num edge, num y) =>
      f(s, edge - s.length * 9.4, edge, y);
  final out = <PdfTextFragment>[
    f('STATEMENT OF ACCOUNT', 880, 1152, 198),
    f('Account Number:', 86, 235, 314),
    f('111-234-567-890', 272, 418, 314),
    f('Page 1 of 1', 1015, 1141, 347),
    f('Opening Balance:', 815, 963, 446),
    right('175,800.00', 1141, 446),
    f('Total Credit Amount:', 785, 963, 481),
    right('510,000.00', 1141, 481),
    f('Total Debit Amount:', 790, 963, 515),
    right('94,000.00', 1141, 515),
    f('Closing Balance:', 826, 963, 550),
    right('591,800.00', 1141, 550),
    f('Account Type:', 842, 963, 584),
    f('Current Account', 1003, 1141, 584),
    f('Number of Transactions:', 754, 963, 618),
    f('8', 1059, 1068, 618),
    f('Transactions', 86, 214, 670),
    f('Date', 147, 188, 705),
    f('Description', 408, 507, 705),
    f('Credit', 719, 771, 705),
    f('Debit', 881, 928, 705),
    f('Balance', 1030, 1098, 705),
  ];
  // date, description, credit, debit, balance
  const rows = [
    ('01/02/2026', 'Payment - Credit Card', '', '5,400.00', '170,400.00'),
    ('01/05/2026', 'Payment - Insurance', '', '3,000.00', '167,400.00'),
    ('01/09/2026', 'Account Transfer In', '500,000.00', '', '667,400.00'),
    ('01/12/2026', 'Cheque Deposit', '10,000.00', '', '677,400.00'),
    ('01/15/2026', 'Payment - Electricity', '', '1,500.00', '675,900.00'),
    ('01/16/2026', 'Payment - Water Utility', '', '600.00', '675,300.00'),
    ('01/20/2026', 'Payment - Car Loan', '', '3,500.00', '671,800.00'),
    ('01/28/2026', 'Account Transfer Out', '', '80,000.00', '591,800.00'),
  ];
  var y = 737.0;
  for (final r in rows) {
    out.add(f(r.$1, 113, 221, y));
    out.add(f(r.$2, 272, 272 + r.$2.length * 8.2, y));
    if (r.$3.isNotEmpty) out.add(right(r.$3, 823, y));
    if (r.$4.isNotEmpty) out.add(right(r.$4, 964, y));
    out.add(right(r.$5, 1141, y));
    y += 31.6;
  }
  out.add(f('--- End of Transactions ---', 272, 486, 989));
  out.add(f('templatelab', 1006, 1165, 1666));
  return out;
}

// ---------------------------------------------------------------------------
// Layout 2: Date | Payment Type | Detail | Paid In | Paid Out | Balance.

List<PdfTextFragment> layout2() {
  const w = 1240;
  PdfTextFragment f(String s, num a, num b, num y) => t(s, a, b, y, w: w);
  PdfTextFragment right(String s, num edge, num y) =>
      f(s, edge - s.length * 9.4, edge, y);
  final out = <PdfTextFragment>[
    f('Your Account Statement', 87, 350, 161),
    f('Period:', 86, 144, 226),
    f('Account Activity', 86, 250, 390),
    f('Date', 123, 168, 424),
    f('Payment Type', 231, 369, 424),
    f('Detail', 530, 587, 424),
    f('Paid In', 755, 820, 424),
    f('Paid Out', 877, 961, 424),
    f('Balance', 1041, 1116, 424),
    f('Balance Brought Forward', 396, 626, 455),
    right('8,313.30', 1151, 455),
  ];
  // date, type, detail, in, out, balance
  const rows = [
    ('04/02/2026', 'Fast Payment', 'Amazon', '', '132.30', '8,181.00'),
    ('04/02/2026', 'BACS', 'eBAY Trading Co.', '', '515.22', '7,665.78'),
    ('04/03/2026', 'Fast Payment', 'Morrisons Petrol', '', '80.00', '7,585.78'),
    ('04/06/2026', 'BACS', 'Business Loan', '20,000.00', '', '27,585.78'),
    ('04/07/2026', 'BACS', 'Jumes White Media', '', '2,416.85', '25,168.93'),
    (
      '04/08/2026',
      'Fast Payment',
      'ATM High Street',
      '',
      '100.00',
      '25,068.93',
    ),
    (
      '04/09/2026',
      'BACS',
      'Accorn Advertising Studios',
      '',
      '150.00',
      '24,918.93',
    ),
    (
      '04/10/2026',
      'Fast Payment',
      'Marriott Hotels',
      '',
      '177.00',
      '24,741.93',
    ),
    (
      '04/13/2026',
      'Fast Payment',
      'Abelio Scotrail Ltd',
      '',
      '122.22',
      '24,619.71',
    ),
    (
      '04/14/2026',
      'Fast Payment',
      'Cheque 000234',
      '',
      '1,200.00',
      '23,419.71',
    ),
    ('04/15/2026', 'Int. Bank', 'Interest Paid', '9.33', '', '23,429.04'),
    ('04/16/2026', 'DD', 'OVO Energy', '', '270.00', '23,159.04'),
    ('04/17/2026', 'BACS', 'Toyota Online', '', '10,525.40', '12,633.64'),
    ('04/20/2026', 'BACS', 'HMRC', '', '1,000.00', '11,633.64'),
    ('04/21/2026', 'DD', 'OVLA', '', '280.00', '11,353.64'),
    ('04/22/2026', 'EBP', 'Michael Kor Salary', '', '1,554.00', '9,799.64'),
    ('04/23/2026', 'DD', 'BOS Mastercard', '', '4,000.00', '5,799.64'),
  ];
  var y = 485.0;
  for (final r in rows) {
    out.add(f(r.$1, 87, 203, y));
    out.add(f(r.$2, 226, 226 + r.$2.length * 8.6, y));
    out.add(f(r.$3, 396, 396 + r.$3.length * 8.6, y));
    if (r.$4.isNotEmpty) out.add(right(r.$4, 833, y));
    if (r.$5.isNotEmpty) out.add(right(r.$5, 983, y));
    out.add(right(r.$6, 1151, y));
    y += 30;
  }
  out.add(f('Note:', 87, 137, 1416));
  return out;
}

// ---------------------------------------------------------------------------
// Layout 3: US daily table without years + page 2 grouped by type.

const List<(String, String, String, String, String)> daily = [
  ('10/02', 'POS PURCHASE', '4.23', '', '65.73'),
  ('10/03', 'PREAUTHORIZED CREDIT', '', '763.01', '828.74'),
  ('10/04', 'POS PURCHASE', '11.68', '', '817.06'),
  ('10/05', 'CHECK 1234', '9.98', '', '807.08'),
  ('10/05', 'POS PURCHASE', '25.50', '', '781.58'),
  ('10/08', 'POS PURCHASE', '59.08', '', '722.50'),
  ('10/12', 'CHECK 1236', '69.00', '', '653.50'),
  ('10/14', 'CHECK 1237', '180.63', '', '472.87'),
  ('10/14', 'POS PURCHASE', '18.96', '', '453.91'),
  ('10/16', 'PREAUTHORIZED CREDIT', '', '763.01', '1216.92'),
  ('10/22', 'ATM WITHDRAWAL', '140.00', '', '1076.92'),
  ('10/28', 'CHECK 1238', '91.06', '', '985.86'),
  ('10/30', 'CHECK 1239', '451.20', '', '534.66'),
  ('10/30', 'CHECK 1246', '37.07', '', '497.59'),
  ('10/30', 'POS PURCHASE', '18.67', '', '478.92'),
  ('10/31', 'CHECK 1247', '100.00', '', '378.92'),
  ('10/31', 'CHECK 1248', '78.24', '', '300.68'),
  ('10/31', 'PREAUTHORIZED CREDIT', '', '350.00', '650.68'),
  ('11/02', 'CHECK 1249', '52.23', '', '598.45'),
  ('11/09', 'INTEREST CREDIT', '', '.26', '598.71'),
  ('11/09', 'SERVICE CHARGE', '12.00', '', '586.71'),
];

/// The scanned page as text-layer-style fragments (also the shape the OCR
/// adapter produces). 850 px page.
List<PdfTextFragment> layout3({bool page2 = true}) {
  const w = 850;
  PdfTextFragment f(String s, num a, num b, num y, {int page = 1}) =>
      t(s, a, b, y, w: w, page: page);
  PdfTextFragment right(String s, num edge, num y, {int page = 1}) =>
      f(s, edge - s.length * 5.2, edge, y, page: page);
  final out = <PdfTextFragment>[
    f('Statement of Account', 77, 282, 84),
    f('Summary of Your Account', 315, 520, 471),
    f('Beginning balance on October 10', 127, 313, 532),
    right(r'$69.96', 430, 532),
    f('Avg Collected Balance', 505, 620, 532),
    right(r'$643.24', 717, 532),
    f('+ Deposits and other credits', 155, 297, 545),
    right(r'$1,876.02', 430, 545),
    f('+ Interest paid', 155, 226, 558),
    right(r'$0.26', 430, 558),
    f('- Withdrawals and other debits', 155, 311, 572),
    right(r'$1,320.02', 430, 572),
    f('- Service Charges and Fees', 155, 297, 585),
    right(r'$12.00', 430, 585),
    f('Ending balance on November 9', 127, 301, 599),
    right(r'$586.71', 430, 599),
    f('Account Transactions', 89, 262, 742),
    f('Date', 89, 113, 776),
    f('Description', 127, 182, 776),
    f('Debit', 465, 490, 776),
    f('Credit', 589, 619, 776),
    f('Balance', 702, 742, 776),
  ];
  var y = 790.0;
  for (final r in daily) {
    out.add(f(r.$1, 89, 113, y));
    out.add(f(r.$2, 127, 127 + r.$2.length * 5.6, y));
    if (r.$3.isNotEmpty) out.add(right(r.$3, 491, y));
    if (r.$4.isNotEmpty) out.add(right(r.$4, 619, y));
    out.add(right(r.$5, 742, y));
    y += 13.3;
  }
  if (!page2) return out;
  // Page 2: by type, no balance column, plus a cheque list.
  out
    ..add(f('Account Transactions', 89, 262, 155, page: 2))
    ..add(f('Deposits and Other Credits', 89, 232, 180, page: 2))
    ..add(f('Date', 89, 113, 196, page: 2))
    ..add(f('Description', 127, 182, 196, page: 2))
    ..add(f('Amount', 702, 740, 196, page: 2));
  const deposits = [
    ('10/03', 'PREAUTHORIZED CREDIT', 'PAYROLL 0987654 678990', '763.01'),
    ('10/16', 'PREAUTHORIZED CREDIT', 'US TREASURY 310 SOC SEC', '763.01'),
    ('10/31', 'PREAUTHORIZED CREDIT', 'DEPOSIT TERMINAL S097094', '350.00'),
    ('11/09', 'INTEREST CREDIT', '', '0.26'),
  ];
  var y2 = 209.0;
  for (final d in deposits) {
    out
      ..add(f(d.$1, 89, 113, y2, page: 2))
      ..add(f(d.$2, 127, 253, y2, page: 2));
    if (d.$3.isNotEmpty) out.add(f(d.$3, 275, 376, y2, page: 2));
    out.add(right(d.$4, 740, y2, page: 2));
    y2 += 13.5;
  }
  out
    ..add(f('Withdrawals and Other Debits', 89, 245, 383, page: 2))
    ..add(f('Date', 89, 113, 383, page: 2))
    ..add(f('Description', 127, 182, 383, page: 2))
    ..add(f('Amount', 702, 740, 383, page: 2));
  const withdrawals = [
    ('10/02', 'POS PURCHASE', 'TERMINAL 24349201 WAL-MART', '4.23'),
    ('10/04', 'POS PURCHASE', 'TERMINAL 443565 PLAYERS SPORTS', '11.68'),
    ('10/05', 'POS PURCHASE', 'TERMINAL 422443 KWAN COURT', '25.50'),
    ('10/22', 'ATM WITHDRAWAL', 'CASH WITHDRAWAL TERMINAL', '140.00'),
  ];
  y2 = 396.0;
  for (final d in withdrawals) {
    out
      ..add(f(d.$1, 89, 113, y2, page: 2))
      ..add(f(d.$2, 127, 230, y2, page: 2))
      ..add(f(d.$3, 275, 600, y2, page: 2))
      ..add(right(d.$4, 740, y2, page: 2));
    y2 += 13.5;
  }
  out
    ..add(f('Checks Paid', 91, 150, 646, page: 2))
    ..add(f('Check #', 91, 120, 646, page: 2))
    ..add(f('Date', 163, 190, 646, page: 2))
    ..add(f('Amount', 231, 262, 646, page: 2))
    ..add(f('Check #', 321, 350, 646, page: 2))
    ..add(f('Date', 393, 420, 646, page: 2))
    ..add(f('Amount', 461, 492, 646, page: 2));
  const checks = [
    ('1234', '10/05', r'$9.98', '1238', '10/28', r'$91.06'),
    ('1236*', '10/12', r'$69.00', '1239', '10/30', r'$451.20'),
    ('1237', '10/14', r'$180.63', '1246*', '10/30', r'$37.07'),
  ];
  y2 = 659.0;
  for (final c in checks) {
    out
      ..add(f(c.$1, 91, 115, y2, page: 2))
      ..add(f(c.$2, 163, 190, y2, page: 2))
      ..add(right(c.$3, 262, y2, page: 2))
      ..add(f(c.$4, 321, 345, y2, page: 2))
      ..add(f(c.$5, 393, 420, y2, page: 2))
      ..add(right(c.$6, 492, y2, page: 2));
    y2 += 13;
  }
  return out;
}

void main() {
  group('layout 1: credit/debit, month first, summary block', () {
    final table = buildStatementTable(layout1(), today: today);
    test('header read, no mapping step needed, month-first detected', () {
      expect(table.confident, isTrue);
      expect(table.dayFirst, isFalse);
      expect(table.suggestedRoles, const [
        StatementColumnRole.date,
        StatementColumnRole.description,
        StatementColumnRole.credit,
        StatementColumnRole.debit,
        StatementColumnRole.balance,
      ]);
      expect(table.rows.where((r) => !r.continuation), hasLength(8));
    });
    test('opening and closing come from the summary', () {
      expect(table.openingBalance, '175,800.00');
      expect(table.closingBalance, '591,800.00');
    });
    test('8 rows, totals equal the summary, every balance verified', () {
      final r = parseStatementRows(table, mapOf(table, 'USD'));
      expect(r.rows, hasLength(8));
      expect(r.invalid, 0);
      expect(r.balanceChecked, 8);
      expect(r.closingMatches, isTrue);
      expect(sum(r.rows, expense: false), 51000000);
      expect(sum(r.rows, expense: true), 9400000);
      expect(r.rows.first.date, const StatementDate(2026, 1, 2));
      expect(r.rows[2].date, const StatementDate(2026, 1, 9));
      expect(r.rows.first.description, 'Payment - Credit Card');
      expect(r.rows.first.isExpense, isTrue);
      expect(r.rows[2].isExpense, isFalse);
      expect(r.rows.every((x) => x.amount.currency.code == 'USD'), isTrue);
    });
    test('the end row is not a continuation of the last description', () {
      final r = parseStatementRows(table, mapOf(table, 'USD'));
      expect(r.rows.last.description, 'Account Transfer Out');
    });
  });

  group('layout 2: paid in/out, brought forward row, payment type', () {
    final table = buildStatementTable(layout2(), today: today);
    test('synonyms map, payment type is ignored', () {
      expect(table.confident, isTrue);
      expect(table.suggestedRoles, const [
        StatementColumnRole.date,
        StatementColumnRole.ignore,
        StatementColumnRole.description,
        StatementColumnRole.credit,
        StatementColumnRole.debit,
        StatementColumnRole.balance,
      ]);
      expect(table.openingBalance, '8,313.30');
    });
    test('17 rows verified against the running balance', () {
      final r = parseStatementRows(table, mapOf(table, 'GBP'));
      expect(r.rows, hasLength(17));
      expect(r.invalid, 0);
      expect(r.balanceChecked, 17);
      expect(sum(r.rows, expense: false), 2000933);
      // 8,313.30 + 20,009.33 - 5,799.64 = 22,522.99 paid out.
      expect(sum(r.rows, expense: true), 2252299);
      expect(r.rows.first.description, 'Amazon');
      expect(r.rows[1].description, 'eBAY Trading Co.');
      expect(r.rows[8].date, const StatementDate(2026, 4, 13));
    });
    test('left-aligned detail under a centred header stays in its column', () {
      final r = parseStatementRows(table, mapOf(table, 'GBP'));
      // "Amazon" is short and starts left of the header's midpoint.
      expect(r.rows.first.description, isNot(contains('Fast')));
      expect(r.rows[5].description, 'ATM High Street');
    });
  });

  group('layout 3: no years, two pages, repeated transactions', () {
    final table = buildStatementTable(layout3(), today: today);
    test('the table with a balance column is chosen', () {
      expect(table.suggestedRoles, const [
        StatementColumnRole.date,
        StatementColumnRole.description,
        StatementColumnRole.debit,
        StatementColumnRole.credit,
        StatementColumnRole.balance,
      ]);
      expect(table.confident, isTrue);
      expect(table.rows.where((r) => !r.continuation), hasLength(21));
    });
    test('currency symbol is proposed, never applied silently', () {
      expect(table.suggestedCurrency?.code, 'USD');
    });
    test(
      'no printed full date: the year is today\'s and must be confirmed',
      () {
        expect(table.yearSource, StatementYearSource.today);
        expect(table.anchorYear, 2026);
      },
    );
    test('a year shift moves every date', () {
      final r = parseStatementRows(table, mapOf(table, 'USD'), yearShift: -1);
      expect(r.rows.first.date, const StatementDate(2025, 10, 2));
      expect(r.rows.last.date, const StatementDate(2025, 11, 9));
    });
    test('year from today, 21 rows, no duplicates, chain verified', () {
      final r = parseStatementRows(table, mapOf(table, 'USD'));
      expect(r.rows, hasLength(21));
      expect(r.invalid, 0);
      expect(r.balanceChecked, 21);
      expect(r.closingMatches, isTrue);
      expect(r.rows.first.date, const StatementDate(2026, 10, 2));
      expect(r.rows.last.date, const StatementDate(2026, 11, 9));
      expect(sum(r.rows, expense: false), 187628);
      expect(sum(r.rows, expense: true), 135953);
      // ".26" is 26 cents of interest.
      expect(r.rows[19].amount.minor, 26);
      expect(r.rows[19].isExpense, isFalse);
    });
    test('page 2 alone is not imported twice (no balance table)', () {
      final onlyP2 = [
        for (final f in layout3())
          if (f.page == 2) f,
      ];
      final tb = buildStatementTable(onlyP2, today: today);
      final r = parseStatementRows(tb, mapOf(tb, 'USD'));
      // Deposits (4) and withdrawals (4) share columns; the cheque list is
      // a different table and is not added on top.
      expect(r.rows, isEmpty);
      expect(r.review, hasLength(8));
      expect(
        r.review.every(
          (x) => x.review == StatementReviewReason.directionUnknown,
        ),
        isTrue,
      );
    });
    test(
      'year of a statement that ends in January rolls back for December',
      () {
        final f = <PdfTextFragment>[
          t('Date', 40, 80, 100, w: 1000),
          t('Description', 170, 260, 100, w: 1000),
          t('Debit', 540, 600, 100, w: 1000),
          t('Credit', 660, 720, 100, w: 1000),
          t('Balance', 820, 880, 100, w: 1000),
          t('12/30', 40, 100, 120, w: 1000),
          t('SHOP A', 170, 260, 120, w: 1000),
          t('10.00', 540, 600, 120, w: 1000),
          t('90.00', 820, 880, 120, w: 1000),
          t('12/31', 40, 100, 140, w: 1000),
          t('SHOP B', 170, 260, 140, w: 1000),
          t('5.00', 540, 600, 140, w: 1000),
          t('85.00', 820, 880, 140, w: 1000),
          t('01/02', 40, 100, 160, w: 1000),
          t('SHOP C', 170, 260, 160, w: 1000),
          t('5.00', 540, 600, 160, w: 1000),
          t('80.00', 820, 880, 160, w: 1000),
        ];
        final tb = buildStatementTable(f, today: DateTime(2026, 1, 20));
        final r = parseStatementRows(tb, mapOf(tb, 'USD'));
        expect(r.rows.map((x) => x.date).toList(), const [
          StatementDate(2025, 12, 30),
          StatementDate(2025, 12, 31),
          StatementDate(2026, 1, 2),
        ]);
      },
    );
  });
}
