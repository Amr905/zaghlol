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
    _checkUnmaskedAmount(node);
    super.visitMethodInvocation(node);
  }

  // Rule 5: no_unmasked_amount (D-67, hide amounts).
  //
  // Every amount shown to the user is built by `MoneyFormat.format`, which
  // masks it while the eye toggle is on. The rule fires on:
  //  - `MoneyFormat.format(...)` without a `hidden:` argument, or with the
  //    literal `hidden: false` (pass the real setting);
  //  - `NumberFormat(...)` / `NumberFormat.xxx(...)` outside l10n/ (a second
  //    way to format an amount that nothing can mask);
  //  - in presentation/ and application/ files: `.toStringAsFixed(`,
  //    `.toStringAsPrecision(` and `.toCanonicalString()` (the raw number as
  //    text). A text field the user types the number into is allowed with
  //    `// ignore: no_unmasked_amount - <why>`.
  // Types are not resolved, so the check is by name.

  void _checkUnmaskedAmount(MethodInvocation node) {
    if (scope.isMoneyFormatter) return;
    final name = node.methodName.name;
    final target = node.target;
    if (target is SimpleIdentifier && target.name == 'MoneyFormat') {
      if (name != 'format') return;
      NamedExpression? hidden;
      for (final a in node.argumentList.arguments) {
        if (a is NamedExpression && a.name.label.name == 'hidden') hidden = a;
      }
      if (hidden == null) {
        _report(
          ruleNoUnmaskedAmount,
          node.methodName.offset,
          'MoneyFormat.format without `hidden:`; pass hideAmountsProvider.',
        );
      } else if (hidden.expression is BooleanLiteral &&
          !(hidden.expression as BooleanLiteral).value) {
        _report(
          ruleNoUnmaskedAmount,
          node.methodName.offset,
          '`hidden: false` always shows the amount; pass hideAmountsProvider.',
        );
      }
      return;
    }
    if (!scope.isL10n &&
        ((target is SimpleIdentifier && target.name == 'NumberFormat') ||
            (target == null && name == 'NumberFormat'))) {
      _report(
        ruleNoUnmaskedAmount,
        node.methodName.offset,
        'NumberFormat bypasses the shared amount formatter (hide amounts).',
      );
      return;
    }
    if (scope.inUiText &&
        target != null &&
        (name == 'toStringAsFixed' ||
            name == 'toStringAsPrecision' ||
            name == 'toCanonicalString')) {
      _report(
        ruleNoUnmaskedAmount,
        node.methodName.offset,
        '$name prints a number outside the shared amount formatter; use '
        'MoneyFormat.format (hide amounts).',
      );
    }
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.toSource();
    if (!scope.isL10n && type == 'NumberFormat') {
      _report(
        ruleNoUnmaskedAmount,
        node.offset,
        'NumberFormat bypasses the shared amount formatter (hide amounts).',
      );
    }
    super.visitInstanceCreationExpression(node);
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
      // FU-031: stop at the first argument boundary. A literal nested in
      // `Text('x')` inside an allowed `name:` argument is still user-facing.
      if (parent is NamedExpression) {
        return allowedNamedArguments.contains(parent.name.label.name);
      }
      if (parent is ArgumentList) {
        return allowedCallees.contains(_callee(parent));
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

  // FU-032: also `core.print`, `developer.log`, `stdout.write*` and
  // tear-offs such as `list.forEach(print)`.
  static const Set<String> _sinkTargets = {
    'core',
    'developer',
    'dev',
    'stdout',
    'stderr',
  };
  static const Set<String> _sinkMethods = {
    'print',
    'debugPrint',
    'log',
    'write',
    'writeln',
    'writeAll',
    'writeCharCode',
    'add',
    'addError',
  };

  void _checkPrint(MethodInvocation node) {
    if (scope.isDebugOnly) return;
    final name = node.methodName.name;
    final target = node.target;
    final bare = target == null && (name == 'print' || name == 'debugPrint');
    final sink =
        target is SimpleIdentifier &&
        _sinkTargets.contains(target.name) &&
        _sinkMethods.contains(name) &&
        // `core.add`/`dev.add` are not sinks; only stdout/stderr take add.
        (name != 'add' && name != 'addError' ||
            target.name == 'stdout' ||
            target.name == 'stderr');
    if (bare || sink) {
      _report(
        ruleNoPrintOutsideDebug,
        node.methodName.offset,
        '$name is only allowed in debug-only files.',
      );
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // A tear-off: `print` / `debugPrint` used as a value (argument,
    // initializer or assignment), not called and not a declaration.
    final name = node.name;
    if (!scope.isDebugOnly && (name == 'print' || name == 'debugPrint')) {
      final parent = node.parent;
      final asValue =
          parent is ArgumentList ||
          parent is NamedExpression ||
          parent is VariableDeclaration && parent.initializer == node ||
          parent is AssignmentExpression && parent.rightHandSide == node;
      if (asValue) {
        _report(
          ruleNoPrintOutsideDebug,
          node.offset,
          '$name is only allowed in debug-only files.',
        );
      }
    }
    super.visitSimpleIdentifier(node);
  }

  // Rule 4: safe_exception_required.

  // FU-033: a direct `throw FormatException(..)` (or any platform exception
  // type) in the parsing and db layers.
  @override
  void visitThrowExpression(ThrowExpression node) {
    final e = node.expression;
    // Unresolved parsing yields a MethodInvocation for `Type(..)`.
    final String? type = switch (e) {
      InstanceCreationExpression() => stripGenerics(
        e.constructorName.type.toSource(),
      ),
      MethodInvocation(target: null) => e.methodName.name,
      _ => null,
    };
    if (scope.inParsingOrDbLayer && type != null) {
      // Errors (ArgumentError, StateError, ...) are programmer-error asserts and
      // carry no stored data; only Exception types are in scope.
      if (type == 'FormatException' || type == 'Exception') {
        _report(
          ruleSafeExceptionRequired,
          node.offset,
          'Throw a SafeException subtype in the parsing and db layers, '
          'not $type.',
        );
      }
    }
    super.visitThrowExpression(node);
  }

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
