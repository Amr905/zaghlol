import 'package:test/test.dart';
import 'package:zaghlol_lints/src/checker.dart';
import 'package:zaghlol_lints/src/class_graph.dart';
import 'package:zaghlol_lints/src/violation.dart';

List<Violation> run(String path, String source) {
  final file = ParsedFile.parse(path, source);
  final graph = ClassGraph()..addUnit(file.unit);
  return checkFile(
    file,
    graph,
  ).where((v) => v.rule == ruleNoUnmaskedAmount).toList();
}

void main() {
  const ui = '/r/app/lib/features/home/presentation/s.dart';
  const app = '/r/app/lib/features/home/application/s.dart';
  const data = '/r/app/lib/features/home/data/s.dart';
  const formatter = '/r/app/lib/core/l10n/money_format.dart';
  const l10n = '/r/app/lib/core/l10n/other.dart';

  group('MoneyFormat.format', () {
    test('a call without hidden: is flagged', () {
      expect(
        run(ui, "String f(m) => MoneyFormat.format(m, languageCode: 'en');"),
        hasLength(1),
      );
    });
    test('hidden: false is flagged, any other expression is not', () {
      expect(
        run(ui, 'String f(m) => MoneyFormat.format(m, hidden: false);'),
        hasLength(1),
      );
      expect(
        run(ui, 'String f(m, h) => MoneyFormat.format(m, hidden: h);'),
        isEmpty,
      );
      expect(
        run(ui, 'String f(m, r) => MoneyFormat.format(m, hidden: r.watch(p));'),
        isEmpty,
      );
    });
    test('the formatter file itself is exempt', () {
      expect(
        run(formatter, 'String f(m) => MoneyFormat.format(m, hidden: false);'),
        isEmpty,
      );
    });
    test('other MoneyFormat members are not format calls', () {
      expect(
        run(ui, "Object f(i, c) => MoneyFormat.parseInput(i, c);"),
        isEmpty,
      );
    });
  });

  group('NumberFormat', () {
    test('flagged everywhere except l10n/', () {
      for (final path in [ui, app, data]) {
        expect(
          run(path, "String f(n) => NumberFormat('#').format(n);"),
          hasLength(1),
          reason: path,
        );
        expect(
          run(path, 'String f(n) => NumberFormat.currency().format(n);'),
          hasLength(1),
          reason: path,
        );
        expect(
          run(path, "String f(n) => new NumberFormat('#').format(n);"),
          hasLength(1),
          reason: path,
        );
      }
      expect(run(l10n, "String f(n) => NumberFormat('#').format(n);"), isEmpty);
    });
  });

  group('raw number text', () {
    test('flagged in presentation/ and application/ only', () {
      for (final call in [
        'm.toCanonicalString()',
        'x.toStringAsFixed(2)',
        'x.toStringAsPrecision(3)',
      ]) {
        expect(run(ui, 'Object f(m, x) => $call;'), hasLength(1), reason: call);
        expect(run(app, 'Object f(m, x) => $call;'), hasLength(1));
        expect(run(data, 'Object f(m, x) => $call;'), isEmpty);
      }
    });
    test('ignore with a reason silences it', () {
      expect(
        run(
          ui,
          'Object f(m) =>\n'
          '    // ignore: no_unmasked_amount - edit field, user is typing\n'
          '    m.toCanonicalString();',
        ),
        isEmpty,
      );
    });
  });
}
