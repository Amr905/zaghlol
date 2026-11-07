import 'package:analyzer/dart/ast/ast.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'file_scope.dart';
import 'string_allowlist.dart';

/// Forbids user-facing string literals in widget `build` methods
/// (CLAUDE.md section 2, rule 3: no hard-coded user-facing strings).
class NoUiStringLiterals extends DartLintRule {
  const NoUiStringLiterals() : super(code: _code);

  static const _code = LintCode(
    name: 'no_ui_string_literals',
    problemMessage: 'Hard-coded string in a build method.',
    correctionMessage:
        'Use the localized strings (l10n), or add an allow-listed technical '
        'value such as a key or asset path.',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    final scope = FileScope.of(resolver.path);
    if (scope == null || scope.isL10n) return;

    context.registry.addSimpleStringLiteral((node) {
      if (_isViolation(node, node.value)) reporter.atNode(node, _code);
    });

    context.registry.addStringInterpolation((node) {
      final staticText = node.elements
          .whereType<InterpolationString>()
          .map((e) => e.value)
          .join(' ');
      if (_isViolation(node, staticText)) reporter.atNode(node, _code);
    });
  }

  static bool _isViolation(StringLiteral node, String text) {
    final method = node.thisOrAncestorOfType<MethodDeclaration>();
    if (method == null || method.name.lexeme != 'build') return false;
    if (isTechnicalString(text)) return false;
    return !_isAllowedByContext(node);
  }

  /// Allow-list by position: named arguments, constructors, throw, assert,
  /// comparisons and index expressions.
  static bool _isAllowedByContext(AstNode literal) {
    AstNode node = literal;
    while (true) {
      final parent = node.parent;
      if (parent == null ||
          parent is MethodDeclaration ||
          parent is FunctionExpression) {
        return false;
      }
      if (parent is NamedExpression &&
          allowedNamedArguments.contains(parent.name.label.name)) {
        return true;
      }
      if (parent is ArgumentList && allowedCallees.contains(_callee(parent))) {
        return true;
      }
      if (parent is ThrowExpression ||
          parent is AssertStatement ||
          parent is AssertInitializer) {
        return true;
      }
      if (parent is BinaryExpression &&
          (parent.operator.lexeme == '==' || parent.operator.lexeme == '!=')) {
        return true;
      }
      if (parent is IndexExpression && identical(parent.index, node)) {
        return true;
      }
      node = parent;
    }
  }

  static String? _callee(ArgumentList arguments) {
    final call = arguments.parent;
    if (call is InstanceCreationExpression) {
      return stripGenerics(call.constructorName.toSource());
    }
    if (call is MethodInvocation) {
      final target = call.target;
      final name = call.methodName.name;
      return target == null ? name : '${target.toSource()}.$name';
    }
    return null;
  }
}
