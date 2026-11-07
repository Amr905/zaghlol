import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'file_scope.dart';

final RegExp _moneyName = RegExp('amount|minor', caseSensitive: false);

/// Forbids `double` / `num` for money (CLAUDE.md section 2, rule 4).
class NoDoubleMoney extends DartLintRule {
  const NoDoubleMoney() : super(code: _code);

  static const _code = LintCode(
    name: 'no_double_money',
    problemMessage: 'double/num must not be used for money.',
    correctionMessage:
        'Use the shared Money type (integer minor units + currency).',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    final scope = FileScope.of(resolver.path);
    if (scope == null) return;

    context.registry.addNamedType((node) {
      final type = node.type;
      if (type == null || !(type.isDartCoreDouble || type.isDartCoreNum)) {
        return;
      }
      if (scope.inMoneyLayer || _declaresMoneyName(node)) {
        reporter.atNode(node, _code);
      }
    });

    context.registry.addDoubleLiteral((node) {
      if (scope.inMoneyLayer) reporter.atNode(node, _code);
    });
  }

  /// True when [type] is the type of a declaration named like an amount.
  static bool _declaresMoneyName(NamedType type) {
    AstNode? parent = type.parent;
    while (parent is TypeArgumentList || parent is NamedType) {
      parent = parent?.parent;
    }
    final names = <String>[];
    if (parent is VariableDeclarationList) {
      names.addAll(parent.variables.map((v) => v.name.lexeme));
    } else if (parent is SimpleFormalParameter) {
      final name = parent.name;
      if (name != null) names.add(name.lexeme);
    } else if (parent is FieldFormalParameter) {
      names.add(parent.name.lexeme);
    } else if (parent is MethodDeclaration) {
      names.add(parent.name.lexeme);
    } else if (parent is FunctionDeclaration) {
      names.add(parent.name.lexeme);
    }
    return names.any(_moneyName.hasMatch);
  }
}
