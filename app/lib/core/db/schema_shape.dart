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
// rewrites it) don't matter. Triggers and views are compared by their
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

String _quote(String name) => '"${name.replaceAll('"', '""')}"';

String _normalise(String sql) => sql.replaceAll(RegExp(r'\s+'), ' ').trim();
