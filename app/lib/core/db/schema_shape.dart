// T-016 §5: a structural snapshot of a SQLite schema, used to prove that a
// migrated database has exactly the schema a fresh install would create
// (debug/test `beforeOpen`) and that the generated schema matches the
// committed dump (tests). drift_dev's `validateDatabaseSchema()` and
// `SchemaVerifier` can't be used: drift_dev does not resolve in the
// workspace (tools/drift_codegen/pubspec.yaml).
//
// Tables are compared through PRAGMAs (columns with type, NOT NULL, default
// and primary-key position; foreign keys; indexes with their columns), so
// formatting differences in `sqlite_schema.sql` (ALTER TABLE ADD COLUMN
// rewrites it) don't matter. CHECK constraints, which no PRAGMA reports, are
// read from the table's SQL: one line per CHECK clause, normalised
// (T-017, FU-071 m-3). Triggers and views are compared by their
// whitespace-normalised SQL.

import 'package:drift/drift.dart';

/// Reads the schema shape of [db] as a sorted list of lines. Internal
/// `sqlite_*` objects are skipped.
Future<List<String>> schemaShapeOf(DatabaseConnectionUser db) async {
  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  final shape = <String>[];
  final objects = await rows(
    'SELECT type, name, tbl_name, sql FROM sqlite_schema '
    "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
  );
  for (final o in objects) {
    final type = o['type']! as String;
    final name = o['name']! as String;
    switch (type) {
      case 'table':
        final quoted = _quote(name);
        final sql = (o['sql'] as String?) ?? '';
        if (sql.toUpperCase().startsWith('CREATE VIRTUAL TABLE')) {
          shape.add('vtable $name ${_normalise(sql)}');
          continue;
        }
        for (final check in checkClausesOf(sql)) {
          shape.add('check $name $check');
        }
        for (final c in await rows('PRAGMA table_xinfo($quoted)')) {
          shape.add(
            'column $name.${c['name']} type=${c['type']} '
            'notnull=${c['notnull']} default=${c['dflt_value']} '
            'pk=${c['pk']} hidden=${c['hidden']}',
          );
        }
        for (final f in await rows('PRAGMA foreign_key_list($quoted)')) {
          shape.add(
            'fk $name ${f['id']}.${f['seq']} ${f['from']} -> '
            '${f['table']}.${f['to']} update=${f['on_update']} '
            'delete=${f['on_delete']} match=${f['match']}',
          );
        }
        for (final i in await rows('PRAGMA index_list($quoted)')) {
          final index = i['name']! as String;
          // Auto-indexes are named by position, so compare by content.
          final label = index.startsWith('sqlite_autoindex_') ? 'auto' : index;
          final cols = [
            for (final c in await rows('PRAGMA index_xinfo(${_quote(index)})'))
              if (c['key'] == 1) '${c['name']}:${c['desc']}:${c['coll']}',
          ];
          shape.add(
            'index $name $label unique=${i['unique']} '
            'origin=${i['origin']} partial=${i['partial']} '
            'cols=${cols.join(',')}',
          );
        }
      case 'index':
        // Covered per table above (explicit and automatic indexes).
        continue;
      default:
        shape.add('$type $name ${_normalise((o['sql'] as String?) ?? '')}');
    }
  }
  shape.sort();
  return shape;
}

/// True when both shapes are equal.
bool sameSchemaShape(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The CHECK clauses of a `CREATE TABLE` statement, in order, each
/// normalised: identifier quotes dropped, everything outside string literals
/// lower-cased, whitespace collapsed and removed next to `(`, `)` and `,`.
/// String literals are kept byte for byte. Text inside quotes (a column
/// named `"check"`, a literal `'check (x)'`) is never taken for a clause.
List<String> checkClausesOf(String createSql) {
  final out = <String>[];
  final s = createSql;
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"' || c == '`' || c == '[') {
      i = _skipQuoted(s, i);
      continue;
    }
    if (_isWordStart(s, i) && _startsWithKeyword(s, i, 'check')) {
      var j = i + 5;
      while (j < s.length && s[j].trim().isEmpty) {
        j++;
      }
      if (j < s.length && s[j] == '(') {
        final end = _matchingParen(s, j);
        out.add(_normaliseCheck(s.substring(j + 1, end)));
        i = end + 1;
        continue;
      }
    }
    i++;
  }
  return out;
}

bool _isIdentChar(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

bool _isWordStart(String s, int i) => i == 0 || !_isIdentChar(s[i - 1]);

bool _startsWithKeyword(String s, int i, String word) {
  if (i + word.length > s.length) return false;
  if (s.substring(i, i + word.length).toLowerCase() != word) return false;
  return i + word.length == s.length || !_isIdentChar(s[i + word.length]);
}

/// Index just after the quoted token starting at [start] (`'…'`, `"…"`,
/// `` `…` `` with doubled-quote escapes, or `[…]`). Unterminated: the end.
int _skipQuoted(String s, int start) {
  final close = s[start] == '[' ? ']' : s[start];
  var i = start + 1;
  while (i < s.length) {
    if (s[i] == close) {
      if (close != ']' && i + 1 < s.length && s[i + 1] == close) {
        i += 2;
        continue;
      }
      return i + 1;
    }
    i++;
  }
  return s.length;
}

/// Index of the `)` matching the `(` at [open], skipping quoted text.
/// Unbalanced: the end of [s].
int _matchingParen(String s, int open) {
  var depth = 0;
  var i = open;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"' || c == '`' || c == '[') {
      i = _skipQuoted(s, i);
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return s.length;
}

String _normaliseCheck(String clause) {
  final out = StringBuffer();
  var i = 0;
  while (i < clause.length) {
    final c = clause[i];
    if (c == "'") {
      final end = _skipQuoted(clause, i);
      out.write(clause.substring(i, end));
      i = end;
    } else if (c == '"' || c == '`' || c == '[') {
      final end = _skipQuoted(clause, i);
      final inner = clause.substring(i + 1, end > i + 1 ? end - 1 : end);
      out.write(inner.toLowerCase());
      i = end;
    } else {
      out.write(c.trim().isEmpty ? ' ' : c.toLowerCase());
      i++;
    }
  }
  return _squeeze(out.toString());
}

/// Collapses whitespace outside string literals and drops it next to `(`,
/// `)` and `,`.
String _squeeze(String text) {
  final out = StringBuffer();
  var pendingSpace = false;
  var last = '';
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c == ' ') {
      pendingSpace = true;
      i++;
      continue;
    }
    final token = c == "'" ? text.substring(i, _skipQuoted(text, i)) : c;
    if (pendingSpace &&
        last.isNotEmpty &&
        !'(,'.contains(last) &&
        !'),'.contains(token[0]) &&
        token != '(') {
      out.write(' ');
    }
    pendingSpace = false;
    out.write(token);
    last = token[token.length - 1];
    i += token.length;
  }
  return out.toString();
}

String _quote(String name) => '"${name.replaceAll('"', '""')}"';

String _normalise(String sql) => sql.replaceAll(RegExp(r'\s+'), ' ').trim();
