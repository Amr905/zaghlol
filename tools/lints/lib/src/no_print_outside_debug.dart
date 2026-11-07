import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'file_scope.dart';

/// Forbids `print` / `debugPrint` outside debug-only files (CLAUDE.md
/// section 2, rule 6: raw SMS, balances and account numbers are never logged).
class NoPrintOutsideDebug extends DartLintRule {
  const NoPrintOutsideDebug() : super(code: _code);

  static const _code = LintCode(
    name: 'no_print_outside_debug',
    problemMessage: 'print/debugPrint is only allowed in debug-only files.',
    correctionMessage:
        'Remove it, or move it to a debug/ directory or a *_debug.dart file.',
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    final scope = FileScope.of(resolver.path);
    if (scope == null || scope.isDebugOnly) return;

    context.registry.addMethodInvocation((node) {
      final name = node.methodName.name;
      if (node.target == null && (name == 'print' || name == 'debugPrint')) {
        reporter.atNode(node.methodName, _code);
      }
    });
  }
}
