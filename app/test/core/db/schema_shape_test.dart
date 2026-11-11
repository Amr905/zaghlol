// T-017 (FU-071 m-3): the schema shape includes CHECK constraints, so a
// migrated table whose CHECK differs from a fresh one is a mismatch (the
// debug/test schema check and the dump comparison both rely on it).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/schema_shape.dart';

import 'sqlite3mc_contract.dart' show ContractDb;

Future<List<String>> shapeOf(List<String> statements) async {
  final db = ContractDb(NativeDatabase.memory());
  try {
    for (final s in statements) {
      await db.customStatement(s);
    }
    return await schemaShapeOf(db);
  } finally {
    await db.close();
  }
}

void main() {
  group('checkClausesOf', () {
    test('column and table CHECKs, in order, normalised', () {
      expect(
        checkClausesOf(
          'CREATE TABLE "t" ("a" INTEGER CHECK ("a" >= 0), b TEXT '
          "check(b IN ('x', 'y')), CONSTRAINT c1 CHECK ((a IS NULL) = "
          '(b IS NULL)))',
        ),
        ['a >= 0', "b in('x','y')", '(a is null) =(b is null)'],
      );
    });

    test('whitespace, identifier quotes and keyword case do not matter; '
        'string literals do', () {
      expect(
        checkClausesOf('CREATE TABLE t (a INT CHECK ( "A"  IN (1 ,2) ))'),
        checkClausesOf('create table t (a int check(a in(1,2)))'),
      );
      expect(
        checkClausesOf("CREATE TABLE t (a TEXT CHECK (a = 'X'))"),
        isNot(checkClausesOf("CREATE TABLE t (a TEXT CHECK (a = 'x'))")),
      );
      expect(
        checkClausesOf("CREATE TABLE t (a TEXT CHECK (a = 'a  b'))").single,
        "a = 'a  b'",
      );
    });

    test('quoted text is never taken for a clause', () {
      expect(
        checkClausesOf(
          'CREATE TABLE t ("check" TEXT, [check (x)] INT, '
          "d TEXT DEFAULT 'check (1)', check_flag INT, rechecked INT)",
        ),
        isEmpty,
      );
      expect(
        checkClausesOf(
          "CREATE TABLE t (a TEXT CHECK (a <> ')' AND a <> '''('))",
        ).single,
        "a <> ')' and a <> '''('",
      );
    });

    test('unbalanced input does not throw', () {
      expect(
        () => checkClausesOf('CREATE TABLE t (a CHECK (a > (1)'),
        returnsNormally,
      );
      expect(
        () => checkClausesOf("CREATE TABLE t (a CHECK (a = 'x"),
        returnsNormally,
      );
    });
  });

  group('schemaShapeOf', () {
    test('negative proof: tables equal in every PRAGMA but with a different '
        'CHECK have different shapes', () async {
      final a = await shapeOf([
        'CREATE TABLE m (x INTEGER NOT NULL CHECK (x BETWEEN 0 AND 10))',
      ]);
      final b = await shapeOf([
        'CREATE TABLE m (x INTEGER NOT NULL CHECK (x BETWEEN 0 AND 11))',
      ]);
      final none = await shapeOf(['CREATE TABLE m (x INTEGER NOT NULL)']);
      expect(sameSchemaShape(a, b), isFalse);
      expect(sameSchemaShape(a, none), isFalse);
      // The rest of the shape is the same: only the check line differs.
      expect(
        sameSchemaShape(a.where((l) => !l.startsWith('check ')).toList(), none),
        isTrue,
      );
    });

    test('a CHECK added by ALTER TABLE ADD COLUMN equals the same CHECK in '
        'a fresh CREATE TABLE', () async {
      final altered = await shapeOf([
        'CREATE TABLE m (x INTEGER)',
        "ALTER TABLE m ADD COLUMN y TEXT CHECK (y GLOB '[A-Z][A-Z][A-Z]')",
      ]);
      final fresh = await shapeOf([
        "CREATE TABLE m (x INTEGER, y TEXT CHECK (y GLOB '[A-Z][A-Z][A-Z]'))",
      ]);
      expect(sameSchemaShape(altered, fresh), isTrue);
    });
  });
}
