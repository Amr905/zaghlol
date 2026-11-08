import 'package:test/test.dart';
import 'package:zaghlol_lints/src/runner.dart';

void main() {
  final files = parseTree(['test/fixtures']);

  test('fixtures were found', () {
    expect(files.length, greaterThan(10));
  });

  test('every rule fires where expected and nowhere else', () {
    expect(verifyAll(files), isEmpty);
  });

  test('each rule is exercised by at least one fixture', () {
    final reported = checkAll(files).map((v) => v.rule).toSet();
    expect(reported, {
      'no_double_money',
      'no_ui_string_literals',
      'no_print_outside_debug',
      'safe_exception_required',
    });
  });

  test('compliant fixtures are silent', () {
    final noisy = checkAll(files)
        .where((v) => v.path.contains('compliant') || v.path.contains('debug'))
        .toList();
    expect(noisy, isEmpty);
  });
}
