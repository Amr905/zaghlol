// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_schema.dart';

// ignore_for_file: type=lint
class $DbMetaTable extends DbMeta with TableInfo<$DbMetaTable, DbMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  DbMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbMetaRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $DbMetaTable createAlias(String alias) {
    return $DbMetaTable(attachedDatabase, alias);
  }
}

class DbMetaRow extends DataClass implements Insertable<DbMetaRow> {
  final String key;
  final String value;
  const DbMetaRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  DbMetaCompanion toCompanion(bool nullToAbsent) {
    return DbMetaCompanion(key: Value(key), value: Value(value));
  }

  factory DbMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbMetaRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  DbMetaRow copyWith({String? key, String? value}) =>
      DbMetaRow(key: key ?? this.key, value: value ?? this.value);
  DbMetaRow copyWithCompanion(DbMetaCompanion data) {
    return DbMetaRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbMetaRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbMetaRow &&
          other.key == this.key &&
          other.value == this.value);
}

class DbMetaCompanion extends UpdateCompanion<DbMetaRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const DbMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<DbMetaRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return DbMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppSchema extends GeneratedDatabase {
  _$AppSchema(QueryExecutor e) : super(e);
  $AppSchemaManager get managers => $AppSchemaManager(this);
  late final $DbMetaTable dbMeta = $DbMetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [dbMeta];
}

typedef $$DbMetaTableCreateCompanionBuilder = DbMetaCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$DbMetaTableUpdateCompanionBuilder = DbMetaCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$DbMetaTableFilterComposer extends Composer<_$AppSchema, $DbMetaTable> {
  $$DbMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbMetaTableOrderingComposer
    extends Composer<_$AppSchema, $DbMetaTable> {
  $$DbMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbMetaTableAnnotationComposer
    extends Composer<_$AppSchema, $DbMetaTable> {
  $$DbMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$DbMetaTableTableManager
    extends
        RootTableManager<
          _$AppSchema,
          $DbMetaTable,
          DbMetaRow,
          $$DbMetaTableFilterComposer,
          $$DbMetaTableOrderingComposer,
          $$DbMetaTableAnnotationComposer,
          $$DbMetaTableCreateCompanionBuilder,
          $$DbMetaTableUpdateCompanionBuilder,
          (DbMetaRow, BaseReferences<_$AppSchema, $DbMetaTable, DbMetaRow>),
          DbMetaRow,
          PrefetchHooks Function()
        > {
  $$DbMetaTableTableManager(_$AppSchema db, $DbMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => DbMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => DbMetaCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DbMetaTable, DbMetaRow>(table),
                  BaseReferences<_$AppSchema, $DbMetaTable, DbMetaRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppSchema,
      $DbMetaTable,
      DbMetaRow,
      $$DbMetaTableFilterComposer,
      $$DbMetaTableOrderingComposer,
      $$DbMetaTableAnnotationComposer,
      $$DbMetaTableCreateCompanionBuilder,
      $$DbMetaTableUpdateCompanionBuilder,
      (DbMetaRow, BaseReferences<_$AppSchema, $DbMetaTable, DbMetaRow>),
      DbMetaRow,
      PrefetchHooks Function()
    >;

class $AppSchemaManager {
  final _$AppSchema _db;
  $AppSchemaManager(this._db);
  $$DbMetaTableTableManager get dbMeta =>
      $$DbMetaTableTableManager(_db, _db.dbMeta);
}
