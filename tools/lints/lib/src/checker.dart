import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'class_graph.dart';
import 'comments.dart';
import 'file_scope.dart';
import 'string_allowlist.dart';
import 'violation.dart';

/// A parsed Dart file.
class ParsedFile {
  ParsedFile(this.path, this.source, this.unit, this.lineInfo);

  factory ParsedFile.parse(String path, String source) {
    final result = parseString(
      content: source,
      path: path,
      throwIfDiagnostics: false,
    );
    return ParsedFile(path, source, result.unit, result.lineInfo);
  }

  final String path;
  final String source;
  final CompilationUnit unit;
  final LineInfo lineInfo;
}

/// Runs all four rules on [file]. [graph] must already contain every scanned
/// file (rule safe_exception_required follows supertypes across files).
List<Violation> checkFile(ParsedFile file, ClassGraph graph) {
  final scope = FileScope.of(file.path);
  if (scope == null) return const [];
  final visitor = _RuleVisitor(file, scope, graph);
  file.unit.accept(visitor);
  return applyIgnores(file.source, visitor.violations);
}

final RegExp _moneyName = RegExp('amount|minor', caseSensitive: false);
final RegExp _doubleOrNum = RegExp(r'^(double|num)\??$');

class _RuleVisitor extends RecursiveAstVisitor<void> {
  _RuleVisitor(this.file, this.scope, this.graph);

  final ParsedFile file;
  final FileScope scope;
  final ClassGraph graph;
  final List<Violation> violations = [];

  int _buildDepth = 0;

  void _report(String rule, int offset, String message) {
    final line = file.lineInfo.getLocation(offset).lineNumber;
    violations.add(Violation(rule, file.path, line, message));
  }

  // Rule 1: no_double_money.

  @override
  void visitNamedType(NamedType node) {
    if (_doubleOrNum.hasMatch(node.toSource()) &&
        (scope.inMoneyLayer || _declaresMoneyName(node))) {
      _report(
        ruleNoDoubleMoney,
        node.offset,
        'double/num must not be used for money; use Money (minor units).',
      );
    }
    super.visitNamedType(node);
  }

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    if (scope.inMoneyLayer) {
      _report(
        ruleNoDoubleMoney,
        node.offset,
        'double literal in a money file; use integer minor units.',
      );
    }
    super.visitDoubleLiteral(node);
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

  // Rule 2: no_ui_string_literals.

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final isBuild = node.name.lexeme == 'build';
    if (isBuild) _buildDepth++;
    super.visitMethodDeclaration(node);
    if (isBuild) _buildDepth--;
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _checkString(node, node.value);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    final staticText = node.elements
        .whereType<InterpolationString>()
        .map((e) => e.value)
        .join(' ');
    _checkString(node, staticText);
    super.visitStringInterpolation(node);
  }

  void _checkString(StringLiteral node, String text) {
    if (_buildDepth == 0 || scope.isL10n) return;
    if (isTechnicalString(text) || _isAllowedByContext(node)) return;
    _report(
      ruleNoUiStringLiterals,
      node.offset,
      'Hard-coded string in a build method; use the localized strings.',
    );
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

  // Rule 3: no_print_outside_debug.

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (!scope.isDebugOnly &&
        node.target == null &&
        (name == 'print' || name == 'debugPrint')) {
      _report(
        ruleNoPrintOutsideDebug,
        node.methodName.offset,
        '$name is only allowed in debug-only files.',
      );
    }
    super.visitMethodInvocation(node);
  }

  // Rule 4: safe_exception_required.

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (scope.inParsingOrDbLayer) {
      final ancestors = <String>{};
      for (final direct in ClassGraph.directSupertypes(node)) {
        ancestors.addAll(graph.ancestors(direct));
      }
      final isThrowable = ancestors.any(throwableRoots.contains);
      if (isThrowable && !ancestors.contains('SafeException')) {
        _report(
          ruleSafeExceptionRequired,
          node.name.offset,
          'Exceptions in the parsing and db layers must extend SafeException.',
        );
      }
    }
    super.visitClassDeclaration(node);
  }
}
