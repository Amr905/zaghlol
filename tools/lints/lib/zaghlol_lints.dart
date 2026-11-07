/// custom_lint plugin entry point (T-002). See README.md for the rules.
library;

import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'src/no_double_money.dart';
import 'src/no_print_outside_debug.dart';
import 'src/no_ui_string_literals.dart';
import 'src/safe_exception_required.dart';

PluginBase createPlugin() => _ZaghlolLints();

class _ZaghlolLints extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
    NoDoubleMoney(),
    NoUiStringLiterals(),
    NoPrintOutsideDebug(),
    SafeExceptionRequired(),
  ];
}
