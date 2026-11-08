import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'string_allowlist.dart';

/// Core types that make a class an exception or an error.
const Set<String> throwableRoots = {
  'Exception',
  'Error',
  'FormatException',
  'StateError',
  'ArgumentError',
  'RangeError',
  'UnsupportedError',
  'UnimplementedError',
  'TypeError',
  'AssertionError',
  'TimeoutException',
};

/// Direct supertypes by class name across all scanned files. Name based (no
/// type resolution), so two classes with the same name share an entry.
class ClassGraph {
  final Map<String, Set<String>> _supers = {};

  void addUnit(CompilationUnit unit) => unit.accept(_Collector(this));

  void _add(String name, Iterable<String> supers) =>
      _supers.putIfAbsent(name, () => {}).addAll(supers);

  /// All supertype names reachable from [name], including [name] itself.
  Set<String> ancestors(String name) {
    final seen = <String>{};
    final pending = [name];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (!seen.add(next)) continue;
      pending.addAll(_supers[next] ?? const <String>{});
    }
    return seen;
  }

  /// Names of the direct supertypes written in [node].
  static Set<String> directSupertypes(ClassDeclaration node) => {
    if (node.extendsClause != null)
      stripGenerics(node.extendsClause!.superclass.toSource()),
    for (final t in node.implementsClause?.interfaces ?? <NamedType>[])
      stripGenerics(t.toSource()),
    for (final t in node.withClause?.mixinTypes ?? <NamedType>[])
      stripGenerics(t.toSource()),
  };
}

class _Collector extends RecursiveAstVisitor<void> {
  _Collector(this.graph);

  final ClassGraph graph;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    graph._add(node.name.lexeme, ClassGraph.directSupertypes(node));
    super.visitClassDeclaration(node);
  }
}
