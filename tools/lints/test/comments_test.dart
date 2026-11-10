import 'package:test/test.dart';
import 'package:zaghlol_lints/src/checker.dart';
import 'package:zaghlol_lints/src/class_graph.dart';
import 'package:zaghlol_lints/src/violation.dart';

List<Violation> run(String path, String source) {
  final file = ParsedFile.parse(path, source);
  final graph = ClassGraph()..addUnit(file.unit);
  return checkFile(file, graph);
}

void main() {
  hardeningTests();
  const money = '/r/app/lib/money/m.dart';

  test('ignore comment on the previous line silences a rule', () {
    expect(run(money, 'class A {\n  double x = 1;\n}\n'), hasLength(1));
    expect(
      run(
        money,
        'class A {\n  // ignore: no_double_money\n  double x = 1;\n}\n',
      ),
      isEmpty,
    );
  });

  test('ignore on the same line and ignore_for_file', () {
    expect(
      run(money, 'class A {\n  double x = 1; // ignore: no_double_money\n}\n'),
      isEmpty,
    );
    expect(
      run(
        money,
        '// ignore_for_file: no_double_money\nclass A {double x = 1;}',
      ),
      isEmpty,
    );
  });

  test('files outside lib/ and generated files are skipped', () {
    expect(run('/r/app/test/money/m.dart', 'double x = 1;'), isEmpty);
    expect(run('/r/app/lib/money/m.g.dart', 'double x = 1;'), isEmpty);
  });

  test('money names outside money/: amount and minor only', () {
    const path = '/r/app/lib/features/a.dart';
    expect(run(path, 'double amountMinor = 0;'), hasLength(1));
    expect(run(path, 'double? minorUnits;'), hasLength(1));
    expect(run(path, 'double opacity = 0;'), isEmpty);
    expect(run(path, 'int f(double amount) => 0;'), hasLength(1));
    expect(run(path, 'int amount = 0;'), isEmpty);
  });

  test('num and nullable double are caught, int and BigInt are not', () {
    expect(run(money, 'num? a;'), hasLength(1));
    expect(run(money, 'List<double> a = [];'), hasLength(1));
    expect(run(money, 'int a = 0; BigInt b = BigInt.zero;'), isEmpty);
  });

  test('print rule: calls on a target are not print', () {
    const path = '/r/app/lib/core/a.dart';
    expect(run(path, 'void f() { print(1); }'), hasLength(1));
    expect(run(path, 'void f() { debugPrint("x"); }'), hasLength(1));
    expect(run(path, 'void f(Logger l) { l.print(1); }'), isEmpty);
    expect(run('/r/app/lib/debug/a.dart', 'void f() { print(1); }'), isEmpty);
  });

  test('strings: Arabic text is flagged, Arabic-Indic digits are not', () {
    const path = '/r/app/lib/features/a.dart';
    String src(String s) =>
        'class W { Widget build(BuildContext c) => Text("$s"); }';
    expect(run(path, src('زغلول')), hasLength(1));
    expect(run(path, src('٣٠')), isEmpty);
    expect(run(path, 'String s() => "plain outside build";'), isEmpty);
  });

  test('exceptions follow supertypes across classes', () {
    const path = '/r/app/lib/parsing/a.dart';
    const safe = 'abstract class SafeException implements Exception {}\n';
    expect(run(path, 'class E extends FormatException {}'), hasLength(1));
    expect(run(path, '${safe}class E extends SafeException {}'), isEmpty);
    expect(
      run(path, '${safe}class A extends SafeException {}class B extends A {}'),
      isEmpty,
    );
    expect(run(path, 'class A {} class B extends A {}'), isEmpty);
    expect(
      run('/r/app/lib/core/a.dart', 'class E implements Exception {}'),
      isEmpty,
    );
  });
}

void hardeningTests() {
  const parsing = '/r/packages/zaghlol_parsing/lib/p.dart';
  const domain = '/r/packages/zaghlol_domain/lib/d.dart';
  const other = '/r/packages/zaghlol_other/lib/o.dart';
  const money = '/r/app/lib/money/m.dart';

  group('no_double_money hardening', () {
    test('parse calls and toDouble are flagged in the strict scope', () {
      for (final path in [parsing, domain, money]) {
        const snippets = [
          "int f() { return double.parse('1').toInt(); }",
          "Object? f() => double.tryParse('1');",
          "Object f() => num.parse('1');",
          "Object? f() => num.tryParse('1');",
          'int f(int a) { return a.toDouble().round(); }',
        ];
        for (final code in snippets) {
          expect(run(path, code), hasLength(1), reason: '$path: $code');
        }
      }
    });

    test('double literals, / and /= are flagged; ~/ and int ops are not', () {
      expect(run(parsing, 'final a = 1.5;'), hasLength(1));
      expect(run(parsing, 'final a = 3 / 2;'), hasLength(1));
      expect(run(parsing, 'void f() { var a = 8; a /= 2; }'), hasLength(1));
      expect(run(parsing, 'final a = 3 ~/ 2;'), isEmpty);
      expect(run(parsing, 'void f() { var a = 8; a ~/= 2; }'), isEmpty);
      expect(run(parsing, 'int a(int x) => x * 2 + 1;'), isEmpty);
    });

    test('double and num types: flagged in the packages, not elsewhere', () {
      expect(run(parsing, 'double total = 0;'), hasLength(1));
      expect(run(domain, 'num? price;'), hasLength(1));
      expect(run(other, 'double total = 0;'), isEmpty);
      expect(run(other, 'final a = 1.5; double w = 2 / 3;'), isEmpty);
    });

    test('int.parse, BigInt.parse and int.tryParse are fine', () {
      const code =
          'int a(String s) => int.parse(s);\n'
          'BigInt b(String s) => BigInt.parse(s);\n'
          'int? c(String s) => int.tryParse(s);\n';
      expect(run(parsing, code), isEmpty);
    });

    test('one report per line', () {
      expect(run(parsing, 'double x = 1.5;'), hasLength(1));
    });

    test('outside the strict scope: amount-named inferred doubles', () {
      expect(run(other, 'final amount = 12.5;'), hasLength(1));
      expect(run(other, 'final minorX = 1 / 2;'), hasLength(1));
      expect(run(other, "final amountY = double.parse('1');"), hasLength(1));
      expect(run(other, 'final amountZ = 5;'), isEmpty);
      expect(run(other, 'final opacity = 0.5;'), isEmpty);
      expect(
        run(other, 'Object amountOf(int x) { return x * 1.5; }'),
        hasLength(1),
      );
      expect(run(other, 'Object minorOf(int x) => x / 2;'), hasLength(1));
      expect(run(other, 'int minorOf(int x) => (x / 2) ~/ 1;'), isEmpty);
      expect(run(other, 'int minorOf(int x) => x ~/ 2;'), isEmpty);
      expect(run(other, 'double scale(int x) => x / 3;'), isEmpty);
    });

    test('allow-list: ignore with a reason silences one line only', () {
      const timing = 's.elapsedMicroseconds / 1000';
      expect(
        run(
          parsing,
          'void f(Stopwatch s) {\n'
          '  // ignore: no_double_money - benchmark timing\n'
          '  final ms = $timing;\n'
          '}\n',
        ),
        isEmpty,
      );
      expect(
        run(
          parsing,
          'void f(Stopwatch s) {\n'
          '  final ms = $timing; // ignore: no_double_money\n'
          '}\n',
        ),
        isEmpty,
      );
      expect(
        run(
          parsing,
          'void f(Stopwatch s) {\n'
          '  final ms = $timing;\n'
          '  final q = 1.5;\n'
          '}\n',
        ),
        hasLength(2),
      );
    });
  });
}
