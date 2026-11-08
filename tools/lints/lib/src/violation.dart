/// Rule names, as used in `// ignore:` and `// expect_lint:` comments.
const String ruleNoDoubleMoney = 'no_double_money';
const String ruleNoUiStringLiterals = 'no_ui_string_literals';
const String ruleNoPrintOutsideDebug = 'no_print_outside_debug';
const String ruleSafeExceptionRequired = 'safe_exception_required';

/// One reported problem.
class Violation {
  const Violation(this.rule, this.path, this.line, this.message);

  final String rule;
  final String path;

  /// 1-based line.
  final int line;
  final String message;

  @override
  String toString() => '$path:$line: [$rule] $message';
}
