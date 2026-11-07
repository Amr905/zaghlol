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
  const money = '/r/app/lib/money/m.dart';

  test('ignore comment on the previous line silences a rule', () {
    expect(run(money, 'class A {\n  double x = 1;\n}\n'), hasLength(1));
    expect(
      run(money, 'class A {\n  // ignore: no_double_money\n  double x = 1;\n}\n'),
      isEmpty,
    );
  });

  test('ignore on the same line and ignore_for_file', () {
    expect(
      run(money, 'class A {\n  double x = 1; // ignore: no_double_money\n}\n'),
      isEmpty,
    );
    expect(
      run(money, '// ignore_for_file: no_double_money\nclass A {double x = 1;}'),
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
    expect(run('/r/app/lib/core/a.dart', 'class E implements Exception {}'),
        isEmpty);
  });
}
