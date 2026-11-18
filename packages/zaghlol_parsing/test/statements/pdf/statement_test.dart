import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

PdfTextFragment f(String t, int x0, int x1, int y, {int page = 1}) =>
    PdfTextFragment(page: page, text: t, x0: x0, x1: x1, y: y);

// Column x ranges (permille): date 40-140, desc 170-480, debit 520-600,
// credit 640-720, balance 780-880.
List<PdfTextFragment> english({String d1 = '05/01/2026'}) => [
  f('Date', 40, 80, 100),
  f('Description', 170, 260, 100),
  f('Debit', 540, 600, 100),
  f('Credit', 660, 720, 100),
  f('Balance', 820, 880, 100),
  f(d1, 40, 140, 120),
  f('CARREFOUR MAADI', 170, 330, 120),
  f('1,250.50', 530, 600, 120),
  f('10,000.00', 790, 880, 120),
  f('06/01/2026', 40, 140, 140),
  f('SALARY JAN', 170, 280, 140),
  f('15,000.00', 650, 720, 140),
  f('25,000.00', 790, 880, 140),
  f('(wrapped)', 170, 240, 152),
  f('07/01/2026', 40, 140, 172),
  f('ATM WITHDRAWAL', 170, 320, 172),
  f('500.00', 540, 600, 172),
  f('0.00', 680, 720, 172),
  f('24,500.00', 790, 880, 172),
  f('Page 1 of 1', 400, 500, 600),
];

StatementMapping m(List<StatementColumnRole> roles, {bool dayFirst = true}) =>
    StatementMapping(
      roles: roles,
      currency: Currency.of('EGP'),
      dayFirst: dayFirst,
    );

void main() {
  group('dates', () {
    test('numeric formats and digits', () {
      expect(parseStatementDate('05/01/2026'), const StatementDate(2026, 1, 5));
      expect(parseStatementDate('5-1-26'), const StatementDate(2026, 1, 5));
      expect(parseStatementDate('٠٥/٠١/٢٠٢٦'), const StatementDate(2026, 1, 5));
      expect(parseStatementDate('2026-01-05'), const StatementDate(2026, 1, 5));
      expect(
        parseStatementDate('05/01/2026', dayFirst: false),
        const StatementDate(2026, 5, 1),
      );
      expect(
        parseStatementDate('05/01/2026 14:30'),
        const StatementDate(2026, 1, 5),
      );
    });
    test('textual months, English and Egyptian Arabic', () {
      expect(parseStatementDate('5 Jan 2026'), const StatementDate(2026, 1, 5));
      expect(
        parseStatementDate('31 December 2025'),
        const StatementDate(2025, 12, 31),
      );
      expect(
        parseStatementDate('5 يناير 2026'),
        const StatementDate(2026, 1, 5),
      );
      expect(
        parseStatementDate('٢٨ فبراير ٢٠٢٦'),
        const StatementDate(2026, 2, 28),
      );
      expect(
        parseStatementDate('3 أغسطس 2026'),
        const StatementDate(2026, 8, 3),
      );
      expect(
        parseStatementDate('3 يونيه 2026'),
        const StatementDate(2026, 6, 3),
      );
    });
    test('rejects non-dates and impossible days', () {
      expect(parseStatementDate('31/02/2026'), isNull);
      expect(parseStatementDate('29/02/2026'), isNull);
      expect(
        parseStatementDate('29/02/2028'),
        const StatementDate(2028, 2, 29),
      );
      expect(parseStatementDate('13/13/2026'), isNull);
      expect(parseStatementDate('hello'), isNull);
      expect(parseStatementDate('1,250.50'), isNull);
      expect(parseStatementDate('5 Foo 2026'), isNull);
      expect(parseStatementDate(''), isNull);
    });
  });

  group('amounts', () {
    final egp = Currency.of('EGP');
    SignedAmount? p(String s) => parseStatementAmount(s, currency: egp);
    test('signs and suffixes', () {
      expect(p('1,250.50')!.amount.minor, 125050);
      expect(p('1,250.50')!.negative, isNull);
      expect(p('-30.00')!.negative, isTrue);
      expect(p('(30.00)')!.negative, isTrue);
      expect(p('30.00-')!.negative, isTrue);
      expect(p('30.00 DR')!.negative, isTrue);
      expect(p('30.00 CR')!.negative, isFalse);
      expect(p('١٬٢٥٠٫٥٠')!.amount.minor, 125050);
    });
    test('exponent respected, junk rejected', () {
      expect(
        parseStatementAmount(
          '1.250',
          currency: Currency.of('KWD'),
        )!.amount.minor,
        1250,
      );
      expect(p('abc'), isNull);
      expect(p(''), isNull);
      expect(p('1.234'), isNull); // excess precision for EGP
    });
    test('EU locale', () {
      final a = parseStatementAmount(
        '1.250,50',
        currency: egp,
        locale: NumberLocale.eu,
      );
      expect(a!.amount.minor, 125050);
    });
  });

  group('table and rows', () {
    test('header layout reads confidently', () {
      final t = buildStatementTable(english());
      expect(t.confident, isTrue);
      expect(t.rows.length, 4); // 3 rows + 1 continuation
      expect(t.rows[2].continuation, isTrue);
      expect(t.suggestedRoles, [
        StatementColumnRole.date,
        StatementColumnRole.description,
        StatementColumnRole.debit,
        StatementColumnRole.credit,
        StatementColumnRole.balance,
      ]);
      final r = parseStatementRows(t, m(t.suggestedRoles));
      expect(r.invalid, 0);
      expect(r.rows.length, 3);
      expect(r.rows[0].isExpense, isTrue);
      expect(r.rows[0].amount, Money.parse('1250.50', Currency.of('EGP')));
      expect(r.rows[0].balance!.minor, 1000000);
      expect(r.rows[0].date, const StatementDate(2026, 1, 5));
      expect(r.rows[1].isExpense, isFalse);
      expect(r.rows[1].amount.minor, 1500000);
      expect(r.rows[1].description, 'SALARY JAN (wrapped)');
      // 0.00 in the credit column is not a second amount.
      expect(r.rows[2].isExpense, isTrue);
      expect(r.rows[2].amount.minor, 50000);
    });

    test('footer far from the last row is not a continuation', () {
      final t = buildStatementTable(english());
      expect(t.rows.any((r) => r.cells.join().contains('Page')), isFalse);
    });

    test('Arabic header and Arabic-Indic digits', () {
      final frags = [
        f('التاريخ', 40, 100, 100),
        f('البيان', 170, 240, 100),
        f('مدين', 540, 600, 100),
        f('دائن', 660, 720, 100),
        f('الرصيد', 820, 880, 100),
        f('٠٥/٠١/٢٠٢٦', 40, 140, 120),
        f('كارفور', 300, 340, 120),
        f('المعادي', 240, 290, 120),
        f('١٬٢٥٠٫٥٠', 530, 600, 120),
        f('١٠٬٠٠٠٫٠٠', 790, 880, 120),
      ];
      final t = buildStatementTable(frags);
      expect(t.confident, isTrue);
      final r = parseStatementRows(t, m(t.suggestedRoles));
      expect(r.rows.single.amount.minor, 125050);
      expect(r.rows.single.description, 'كارفور المعادي');
    });

    test('no header: columns inferred, not confident', () {
      final frags = english().where((x) => x.y != 100).toList();
      final t = buildStatementTable(frags);
      expect(t.confident, isFalse);
      expect(t.columnCount, 5);
      expect(t.suggestedRoles.first, StatementColumnRole.date);
      expect(t.suggestedRoles[1], StatementColumnRole.description);
      // User confirms: same table parses with the chosen roles.
      final r = parseStatementRows(
        t,
        m([
          StatementColumnRole.date,
          StatementColumnRole.description,
          StatementColumnRole.debit,
          StatementColumnRole.credit,
          StatementColumnRole.balance,
        ]),
      );
      expect(r.rows.length, 3);
    });

    test('signed single amount column', () {
      final frags = [
        f('5 Jan 2026', 40, 140, 120),
        f('COFFEE', 170, 260, 120),
        f('-45.00', 600, 680, 120),
        f('6 Jan 2026', 40, 140, 140),
        f('REFUND', 170, 260, 140),
        f('45.00', 610, 680, 140),
        f('7 Jan 2026', 40, 140, 160),
        f('GYM', 170, 260, 160),
        f('(300.00)', 590, 680, 160),
      ];
      final t = buildStatementTable(frags);
      final r = parseStatementRows(
        t,
        m([
          StatementColumnRole.date,
          StatementColumnRole.description,
          StatementColumnRole.amount,
        ]),
      );
      expect([for (final x in r.rows) x.isExpense], [true, false, true]);
      expect(r.rows[2].amount.minor, 30000);
    });

    test('bad rows are counted, not echoed', () {
      final frags = english()
        ..addAll([
          f('08/01/2026', 40, 140, 190),
          f('X', 170, 200, 190),
          f('12abc', 540, 600, 190),
        ]);
      final t = buildStatementTable(frags);
      final r = parseStatementRows(t, m(t.suggestedRoles));
      expect(r.rows.length, 3);
      expect(r.problems[StatementRowProblem.badAmount], 1);
      expect(r.invalidRows, [4]);
      expect(r.toString(), isNot(contains('12abc')));
    });

    test('invalid mapping parses nothing', () {
      final t = buildStatementTable(english());
      final r = parseStatementRows(
        t,
        m(List.filled(5, StatementColumnRole.ignore)),
      );
      expect(r.rows, isEmpty);
    });

    test('multi-page statements keep one header', () {
      final frags = [
        ...english(),
        f('Date', 40, 80, 100, page: 2),
        f('Description', 170, 260, 100, page: 2),
        f('Debit', 540, 600, 100, page: 2),
        f('Credit', 660, 720, 100, page: 2),
        f('Balance', 820, 880, 100, page: 2),
        f('09/01/2026', 40, 140, 120, page: 2),
        f('PHARMACY', 170, 260, 120, page: 2),
        f('80.00', 540, 600, 120, page: 2),
      ];
      final t = buildStatementTable(frags);
      final r = parseStatementRows(t, m(t.suggestedRoles));
      expect(r.rows.length, 4);
      expect(r.rows.last.amount.minor, 8000);
    });

    test('empty and hostile input', () {
      expect(buildStatementTable([]).rows, isEmpty);
      expect(buildStatementTable([f('x', 0, 10, 1)]).confident, isFalse);
    });
  });

  group('template', () {
    test('round trip and a table built from it', () {
      final t0 = buildStatementTable(english());
      final tpl = StatementTemplate(
        bankKey: 'cib',
        cutPoints: t0.cutPoints,
        mapping: m(t0.suggestedRoles),
      );
      final back = StatementTemplate.tryFromJson(tpl.toJson())!;
      expect(back.bankKey, 'cib');
      expect(back.cutPoints, tpl.cutPoints);
      expect(back.mapping.roles, tpl.mapping.roles);
      // No header on the page: the template alone reads it.
      final frags = english().where((x) => x.y != 100).toList();
      final t = buildStatementTable(frags, template: back);
      expect(t.confident, isTrue);
      expect(parseStatementRows(t, back.mapping).rows.length, 3);
    });
    test('corrupt templates are ignored', () {
      expect(StatementTemplate.tryFromJson('nope'), isNull);
      expect(StatementTemplate.tryFromJson('{"v":2}'), isNull);
      expect(
        StatementTemplate.tryFromJson(
          '{"v":1,"bank":"A B","cuts":[1],"roles":["date","debit"],'
          '"currency":"EGP","dayFirst":true,"locale":"standard"}',
        ),
        isNull,
      );
      expect(
        StatementTemplate.tryFromJson(
          '{"v":1,"bank":"cib","cuts":[500,400],"roles":["date","description","amount"],'
          '"currency":"EGP","dayFirst":true,"locale":"standard"}',
        ),
        isNull,
      );
    });
  });
}
