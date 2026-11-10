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

  int _uiDepth = 0;

  void _report(String rule, int offset, String message) {
    final line = file.lineInfo.getLocation(offset).lineNumber;
    violations.add(Violation(rule, file.path, line, message));
  }

  // Rule 1: no_double_money.
  //
  // Strict scope (money/ directories, packages zaghlol_parsing and
  // zaghlol_domain): every double/num type, double literal, `/` operator
  // (always a double in Dart), `double.parse`/`tryParse`, `num.parse`/
  // `tryParse` and `.toDouble()` is reported. Elsewhere only declarations
  // named like an amount are checked, including their initializers/returns.
  // Types are inferred syntactically (no type resolution): a `final x = 1.5;`
  // or `final r = a / b;` is caught through the expression that produces the
  // double. Escape hatch for non-money uses (benchmark timings, UI geometry):
  // `// ignore: no_double_money` with a reason; never on money code.

  static const String _doubleMessage =
      'double/num must not be used for money; use Money (minor units).';

  void _reportDouble(int offset, String message) {
    final line = file.lineInfo.getLocation(offset).lineNumber;
    // One report per line: `double x = 1.5;` is a single finding.
    if (violations.any((v) => v.rule == ruleNoDoubleMoney && v.line == line)) {
      return;
    }
    violations.add(Violation(ruleNoDoubleMoney, file.path, line, message));
  }

  @override
  void visitNamedType(NamedType node) {
    if (_doubleOrNum.hasMatch(node.toSource()) &&
        (scope.inStrictDoubleScope || _declaresMoneyName(node))) {
      _reportDouble(node.offset, _doubleMessage);
    }
    super.visitNamedType(node);
  }

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    if (scope.inStrictDoubleScope) {
      _reportDouble(
        node.offset,
        'double literal; use integer minor units (no doubles for money).',
      );
    }
    super.visitDoubleLiteral(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (scope.inStrictDoubleScope && node.operator.lexeme == '/') {
      _reportDouble(
        node.operator.offset,
        '`/` yields a double; use `~/` or integer minor-unit arithmetic.',
      );
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (scope.inStrictDoubleScope && node.operator.lexeme == '/=') {
      _reportDouble(
        node.operator.offset,
        '`/=` yields a double; use `~/=` or integer minor-unit arithmetic.',
      );
    }
    super.visitAssignmentExpression(node);
  }

  /// `double.parse(..)`, `double.tryParse(..)`, `num.parse(..)`,
  /// `num.tryParse(..)` and `x.toDouble()`.
  static bool _isDoubleCall(MethodInvocation node) {
    final name = node.methodName.name;
    if (name == 'toDouble' && node.target != null) return true;
    final target = node.target;
    return (name == 'parse' || name == 'tryParse') &&
        target is SimpleIdentifier &&
        (target.name == 'double' || target.name == 'num');
  }

  /// True when [e] syntactically produces a double.
  static bool _isDoubleExpression(Expression? e) {
    if (e == null) return false;
    if (e is DoubleLiteral) return true;
    if (e is ParenthesizedExpression) return _isDoubleExpression(e.expression);
    if (e is PrefixExpression) return _isDoubleExpression(e.operand);
    if (e is BinaryExpression) {
      // `~/` and `%` on ints stay int; only `/` is always a double.
      if (e.operator.lexeme == '~/') return false;
      return e.operator.lexeme == '/' ||
          _isDoubleExpression(e.leftOperand) ||
          _isDoubleExpression(e.rightOperand);
    }
    if (e is ConditionalExpression) {
      return _isDoubleExpression(e.thenExpression) ||
          _isDoubleExpression(e.elseExpression);
    }
    if (e is MethodInvocation) return _isDoubleCall(e);
    if (e is AsExpression) return _doubleOrNum.hasMatch(e.type.toSource());
    return false;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (scope.inStrictDoubleScope && _isDoubleCall(node)) {
      _reportDouble(
        node.methodName.offset,
        '${node.methodName.name} produces a double; parse amounts into '
        'integer minor units instead.',
      );
    }
    _checkPrint(node);
    super.visitMethodInvocation(node);
  }

  // Outside the strict scope: amount-named variables and functions whose
  // value is a double expression (the declared-type form is NamedType above).

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (!scope.inStrictDoubleScope &&
        _moneyName.hasMatch(node.name.lexeme) &&
        _isDoubleExpression(node.initializer)) {
      _reportDouble(node.name.offset, _doubleMessage);
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (!scope.inStrictDoubleScope &&
        _isDoubleExpression(node.expression) &&
        _enclosingFunctionHasMoneyName(node)) {
      _reportDouble(node.offset, _doubleMessage);
    }
    super.visitReturnStatement(node);
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    if (!scope.inStrictDoubleScope &&
        _isDoubleExpression(node.expression) &&
        _enclosingFunctionHasMoneyName(node)) {
      _reportDouble(node.expression.offset, _doubleMessage);
    }
    super.visitExpressionFunctionBody(node);
  }

  static bool _enclosingFunctionHasMoneyName(AstNode node) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (p is MethodDeclaration) return _moneyName.hasMatch(p.name.lexeme);
      if (p is FunctionDeclaration) return _moneyName.hasMatch(p.name.lexeme);
      if (p is FunctionExpression && p.parent is! FunctionDeclaration) {
        return false;
      }
    }
    return false;
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

  /// UI scope: methods named `build`, and any method, getter or function whose
  /// return type is a widget (`Widget`, `PreferredSizeWidget`, `Widget?`,
  /// `List<Widget>`), so helpers like `_buildHeader()` are covered too.
  static final RegExp _widgetType = RegExp(
    r'^(?:List<)?(?:\w+\.)?\w*Widget\??>?\??$',
  );

  static bool _returnsWidget(TypeAnnotation? type) =>
      type != null && _widgetType.hasMatch(type.toSource());

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final isUi = node.name.lexeme == 'build' || _returnsWidget(node.returnType);
    if (isUi) _uiDepth++;
    super.visitMethodDeclaration(node);
    if (isUi) _uiDepth--;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final isUi = _returnsWidget(node.returnType);
    if (isUi) _uiDepth++;
    super.visitFunctionDeclaration(node);
    if (isUi) _uiDepth--;
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
    if (_uiDepth == 0 || scope.isL10n) return;
    if (isTechnicalString(text) || _isAllowedByContext(node)) return;
    _report(
      ruleNoUiStringLiterals,
      node.offset,
      'Hard-coded string in a build method or widget helper; use the localized strings.',
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

  void _checkPrint(MethodInvocation node) {
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
  }

  // Rule 4: safe_exception_required.

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    // SafeException itself implements Exception, so it is exempt.
    if (scope.inParsingOrDbLayer && node.name.lexeme != 'SafeException') {
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
