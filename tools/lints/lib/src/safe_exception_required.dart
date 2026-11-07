import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'file_scope.dart';

/// Exception and error classes in the parsing and db layers must extend
/// `SafeException`, so messages never carry data (error-handling doc).
///
/// `SafeException` itself arrives in T-014; until then the rule checks the
/// supertype by name.
class SafeExceptionRequired extends DartLintRule {
  const SafeExceptionRequired() : super(code: _code);

  static const _code = LintCode(
    name: 'safe_exception_required',
    problemMessage:
        'Exceptions in the parsing and db layers must extend SafeException.',
    correctionMessage: 'Extend SafeException instead of Exception or Error.',
  );

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    final scope = FileScope.of(resolver.path);
    if (scope == null || !scope.inParsingOrDbLayer) return;

    context.registry.addClassDeclaration((node) {
      final direct = <DartType?>[
        node.extendsClause?.superclass.type,
        ...?node.implementsClause?.interfaces.map((t) => t.type),
        ...?node.withClause?.mixinTypes.map((t) => t.type),
      ];
      final names = <String>{};
      for (final type in direct) {
        if (type is! InterfaceType) continue;
        names.add(_name(type));
        names.addAll(type.allSupertypes.map(_name));
      }
      final isThrowable =
          names.contains('Exception') || names.contains('Error');
      if (isThrowable && !names.contains('SafeException')) {
        reporter.atToken(node.name, _code);
      }
    });
  }

  static String _name(DartType type) =>
      type.getDisplayString().replaceAll(RegExp(r'[<?].*'), '');
}
