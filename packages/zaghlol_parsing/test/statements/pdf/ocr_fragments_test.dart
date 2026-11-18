// T-156b: OCR lines (boxes in 0..1) through the same table detector, with
// the noise a scan brings: jitter, stray marks, split currency signs, a
// row whose amounts came out as one box.

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

const int pageW = 850;
const int pageH = 1100;

OcrLineBox box(String s, num x0, num x1, num y, {num h = 11}) => OcrLineBox(
  text: s,
  x0: (x0 * 1000 / pageW).round(),
  x1: (x1 * 1000 / pageW).round(),
  yCenter: (y * 10000 / pageH).round(),
);

final DateTime today = DateTime(2026, 11, 18);

/// (date, description, debit, credit, balance) as an OCR engine would see
/// them: date and description in one box, each amount in its own.
const rows = [
  ('10/02', 'POS PURCHASE', '4.23', '', '65.73'),
  ('10/03', 'PREAUTHORIZED CREDIT', '', '763.01', '828.74'),
  ('10/04', 'POS PURCHASE', '11.68', '', '817.06'),
  ('10/05', 'CHECK 1234', '9.98', '', '807.08'),
  ('10/30', 'CHECK 1239', '451.20', '', '355.88'),
];

List<OcrLineBox> scan({bool mergeLastAmounts = false, bool misplace = false}) {
  final out = <OcrLineBox>[
    box('Statement of Account', 77, 282, 84),
    box(r'Beginning balance on October 10', 127, 313, 532),
    box(r'$ 69.96', 395, 430, 533),
    box('|', 84, 88, 700),
    box('Date', 89, 113, 776),
    box('Description', 127, 182, 777),
    box('Debit', 465, 490, 775),
    box('Credit', 589, 619, 776),
    box('Balance', 702, 742, 777),
  ];
  var y = 790.0;
  var i = 0;
  for (final r in rows) {
    final jitter = (i++ % 3) - 1.0; // -1, 0, +1 px
    out.add(box('${r.$1} ${r.$2}', 89, 127 + r.$2.length * 5.6, y + jitter));
    final isLast = r == rows.last;
    if (mergeLastAmounts && isLast) {
      // Debit and balance read as one box: "451.20 355.88".
      out.add(box('${r.$3} ${r.$5}', 450, 742, y + jitter));
    } else {
      if (r.$3.isNotEmpty) {
        out.add(box(r.$3, 491 - r.$3.length * 5.2, 491, y + jitter));
      }
      if (r.$4.isNotEmpty) {
        final x1 = misplace && r == rows[1] ? 491.0 : 619.0;
        out.add(box(r.$4, x1 - r.$4.length * 5.2, x1, y + jitter));
      }
      out.add(box(r.$5, 742 - r.$5.length * 5.2, 742, y + jitter));
    }
    y += 13.3;
  }
  out.add(box('—', 300, 320, 1000));
  return out;
}

StatementTable read(List<OcrLineBox> lines) => buildStatementTable(
  ocrLinesToFragments(lines, page: 1, pageHeightPoints: pageH),
  today: today,
);

StatementMapping map(StatementTable t) => StatementMapping(
  roles: t.suggestedRoles,
  currency: Currency.of('USD'),
  dayFirst: t.dayFirst,
);

void main() {
  test('noise lines are dropped, positions scale to permille and points', () {
    final f = ocrLinesToFragments(
      [box('|', 10, 12, 100), box('  ', 10, 20, 100), box('Date', 85, 170, 55)],
      page: 3,
      pageHeightPoints: pageH,
    );
    expect(f, hasLength(1));
    expect(f.single.page, 3);
    expect(f.single.x0, 100);
    expect(f.single.x1, 200);
    expect(f.single.y, 55);
  });

  test('a row box is split into date, description and amounts', () {
    final f = ocrLinesToFragments(
      [box('10/02 POS PURCHASE 4.23 65.73', 89, 742, 800)],
      page: 1,
      pageHeightPoints: pageH,
    );
    expect(f.map((x) => x.text).toList(), [
      '10/02',
      'POS PURCHASE',
      '4.23',
      '65.73',
    ]);
    expect(f.skip(1).every((x) => x.breakBefore), isTrue);
    expect(f.last.x1, pm(742));
  });

  test('a lone currency sign joins the amount', () {
    final f = ocrLinesToFragments(
      [box(r'Ending balance $ 586.71', 127, 430, 599)],
      page: 1,
      pageHeightPoints: pageH,
    );
    expect(f.last.text, r'$586.71');
  });

  test('a scanned statement reads like a text one', () {
    final t = read(scan());
    expect(t.confident, isTrue);
    expect(t.openingBalance, r'$69.96');
    final r = parseStatementRows(t, map(t));
    expect(r.rows, hasLength(5));
    expect(r.invalid, 0);
    expect(r.balanceChecked, 5);
    expect(r.rows.first.date, const StatementDate(2026, 10, 2));
    expect(r.rows.first.description, 'POS PURCHASE');
    expect(r.rows.first.amount.minor, 423);
    expect(r.rows[1].isExpense, isFalse);
    expect(r.rows.last.amount.minor, 45120);
  });

  test('debit and balance merged into one box still land right', () {
    final r = parseStatementRows(
      read(scan(mergeLastAmounts: true)),
      map(read(scan(mergeLastAmounts: true))),
    );
    expect(r.rows, hasLength(5));
    expect(r.rows.last.isExpense, isTrue);
    expect(r.rows.last.amount.minor, 45120);
  });

  test('an amount that lands in the wrong column is flagged, not imported', () {
    final t = read(scan(misplace: true));
    final r = parseStatementRows(t, map(t));
    // The credit of 10/03 sits under Debit: the balance says it was money in.
    expect(r.problems[StatementRowProblem.balanceMismatch], 1);
    expect(r.rows, hasLength(4));
  });

  test('empty and hostile input', () {
    expect(ocrLinesToFragments([], page: 1, pageHeightPoints: pageH), isEmpty);
    final many = [for (var i = 0; i < 5000; i++) box('x $i', 0, 10, i % 900)];
    expect(
      ocrLinesToFragments(many, page: 1, pageHeightPoints: pageH).length,
      lessThanOrEqualTo(maxOcrLinesPerPage * 2),
    );
  });
}

int pm(num px) => (px * 1000 / pageW).round();
