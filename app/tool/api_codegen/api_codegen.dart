// T-141 (FU-013): the pinned DTO generator for the app's backend calls.
//
// Reads backend/openapi/zaghlol-v1.yaml and emits
// lib/core/backend/generated/api_models.g.dart: one Dart type per schema
// reachable from the app's operations, plus the operation table. The
// generator is versioned in the repository ([apiCodegenVersion] is written
// into the output) and test/core/backend/api_models_drift_test.dart
// regenerates and compares byte for byte, so the committed models can't drift
// from the contract or from this generator.
//
// Supported JSON Schema: objects with `properties` (closed or open), string
// (pattern, minLength, maxLength, enum, const), integer (minimum, maximum),
// boolean, arrays (minItems, maxItems), string-keyed maps
// (`additionalProperties` + `propertyNames.pattern`), `oneOf` with a
// `discriminator`, and nullability via `oneOf [X, {type: 'null'}]` or
// `type: [X, 'null']`. Anything else throws, so a contract change the
// generator can't express fails loudly. `if`/`then` conditional requirements
// are not generated (consumers check them).
//
// Request types (reachable from a request body) get `toJson()` only; response
// types get `fromJson()` only. A type reachable from both gets both.

import 'package:yaml/yaml.dart';

/// Bump on any change to the emitted code.
const String apiCodegenVersion = '1.0.0';

/// The operations the app calls (backend-api §2). The health check, the
/// store notifications, the Apple callback and the admin API are not app
/// calls.
const List<String> appOperationIds = [
  'registerInstall',
  'deleteInstall',
  'sync',
  'getFullCatalog',
  'verifyPurchase',
  'restorePurchases',
  'getEntitlement',
  'signIn',
  'signOut',
  'deleteAccount',
];

/// Response schemas that are not a 2xx body but are decoded by the app.
const List<String> extraResponseSchemas = ['Problem'];

/// Generates the Dart source (unformatted; the caller runs `dart format`).
String generateApiModels(String openApiYaml) =>
    _Gen(loadYaml(openApiYaml) as YamlMap).run();

final class ApiCodegenError extends Error {
  ApiCodegenError(this.message);
  final String message;
  @override
  String toString() => 'ApiCodegenError: $message';
}

// ---------------------------------------------------------------------------
// Type model

sealed class _T {}

final class _Str extends _T {
  _Str({this.pattern, this.minLength, this.maxLength});
  final String? pattern;
  final int? minLength;
  final int? maxLength;
}

final class _Int extends _T {
  _Int({this.min, this.max});
  final int? min;
  final int? max;
}

final class _Bool extends _T {}

final class _Enum extends _T {
  _Enum(this.name);
  final String name;
}

final class _Obj extends _T {
  _Obj(this.name);
  final String name;
}

final class _List extends _T {
  _List(this.item, {this.minItems, this.maxItems});
  final _T item;
  final int? minItems;
  final int? maxItems;
}

final class _Map extends _T {
  _Map(this.value, {this.keyPattern});
  final _T value;
  final String? keyPattern;
}

final class _Resolved {
  _Resolved(this.type, {this.nullable = false});
  final _T type;
  final bool nullable;
}

final class _Prop {
  _Prop({
    required this.wire,
    required this.field,
    required this.type,
    required this.required,
    required this.nullable,
    this.constValue,
  });
  final String wire;
  final String field;
  final _T? type;
  final bool required;
  final bool nullable;
  final String? constValue;
}

final class _Op {
  _Op({
    required this.id,
    required this.method,
    required this.path,
    required this.successStatus,
    required this.signed,
    required this.anchoring,
    required this.idempotent,
    required this.auth,
    required this.request,
    required this.response,
  });
  final String id;
  final String method;
  final String path;
  final int successStatus;
  final bool signed;
  final bool anchoring;
  final bool idempotent;
  final String auth;
  final String? request;
  final String? response;
}

const Set<String> _reserved = {
  'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case', //
  'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
  'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
  'external', 'factory', 'false', 'final', 'finally', 'for', 'Function',
  'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
  'late', 'library', 'mixin', 'new', 'null', 'of', 'on', 'operator', 'part',
  'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
  'super', 'switch', 'sync', 'this', 'throw', 'true', 'try',
  'typedef', 'var', 'void', 'when', 'while', 'with', 'yield', 'hashCode',
  'runtimeType', 'toString', 'toJson', 'fromJson', 'noSuchMethod',
};

String _ident(String s) => _reserved.contains(s) ? '${s}_' : s;

String _camel(String wire) {
  final parts = wire
      .split(RegExp('[^A-Za-z0-9]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) throw ApiCodegenError('bad enum value $wire');
  final allUpper = wire == wire.toUpperCase();
  final b = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i];
    if (allUpper) p = p.toLowerCase();
    b.write(i == 0 ? p : p[0].toUpperCase() + p.substring(1));
  }
  var out = b.toString();
  if (RegExp('^[0-9]').hasMatch(out)) out = 'v$out';
  return _ident(out);
}

String _pascal(String s) => s[0].toUpperCase() + s.substring(1);

String _lit(String s) {
  if (s.contains("'''")) throw ApiCodegenError('unsupported literal');
  return "r'$s'";
}

// ---------------------------------------------------------------------------

final class _Gen {
  _Gen(this.doc)
    : schemas = ((doc['components'] as YamlMap)['schemas'] as YamlMap);

  final YamlMap doc;
  final YamlMap schemas;

  /// Schema/class name -> directions ('req', 'res').
  final Map<String, Set<String>> _classes = {};

  /// Enum name -> wire values; directions.
  final Map<String, List<String>> _enums = {};
  final Map<String, Set<String>> _enumDirs = {};

  /// Sealed base -> discriminator property and (wire value -> variant).
  final Map<String, (String, Map<String, String>)> _sealed = {};
  final Map<String, String> _variantOf = {};

  final Map<String, List<_Prop>> _props = {};
  final Map<String, bool> _closed = {};
  final List<String> _patterns = [];

  String run() {
    final ops = _operations();
    for (final op in ops) {
      if (op.request != null) _visitNamed(op.request!, 'req');
      if (op.response != null) _visitNamed(op.response!, 'res');
    }
    for (final s in extraResponseSchemas) {
      _visitNamed(s, 'res');
    }
    final b = StringBuffer()
      ..writeln(
        '// GENERATED by app/tool/api_codegen (zaghlol-api-codegen '
        '$apiCodegenVersion)',
      )
      ..writeln('// from backend/openapi/zaghlol-v1.yaml. Do not edit: run')
      ..writeln('// `dart run tool/api_codegen/main.dart` in app/ and commit.')
      ..writeln('// T-141: the only types BackendClient can serialize.')
      ..writeln(
        '// Request types: toJson() writes declared properties only and',
      )
      ..writeln('// checks every declared constraint first. Response types:')
      ..writeln(
        '// fromJson() ignores unknown fields, maps unknown enum values',
      )
      ..writeln('// to `unknown`, and never echoes input in an error.')
      ..writeln()
      ..writeln("import '../api_runtime.dart';")
      ..writeln()
      ..writeln("export '../api_runtime.dart' show ApiModelException;")
      ..writeln()
      ..writeln("const String apiCodegenVersion = '$apiCodegenVersion';")
      ..writeln();
    _emitOperations(b, ops);
    final enumNames = _enums.keys.toList()..sort();
    for (final e in enumNames) {
      _emitEnum(b, e);
    }
    final classNames = {..._classes.keys, ..._sealed.keys}.toList()..sort();
    for (final c in classNames) {
      if (_sealed.containsKey(c)) {
        _emitSealed(b, c);
      } else {
        _emitClass(b, c);
      }
    }
    for (var i = 0; i < _patterns.length; i++) {
      b.writeln('final RegExp _re$i = RegExp(${_lit(_patterns[i])});');
    }
    return b.toString();
  }

  // ---- operations ---------------------------------------------------------

  List<_Op> _operations() {
    final found = <String, _Op>{};
    final paths = doc['paths'] as YamlMap;
    for (final pe in paths.entries) {
      final path = pe.key as String;
      for (final me in (pe.value as YamlMap).entries) {
        final method = me.key as String;
        if (method == 'parameters') continue;
        final o = me.value as YamlMap;
        final id = o['operationId'] as String?;
        if (id == null || !appOperationIds.contains(id)) continue;
        final params = [
          for (final p in (o['parameters'] as YamlList? ?? YamlList()))
            ((p as YamlMap)[r'$ref'] as String?)?.split('/').last ??
                p['name'] as String,
        ];
        String? request;
        final rb = o['requestBody'] as YamlMap?;
        if (rb != null) {
          final content = rb['content'] as YamlMap;
          final json = content['application/json'] as YamlMap?;
          if (json == null || content.length != 1) {
            throw ApiCodegenError('$id: request must be application/json');
          }
          request = _refName((json['schema'] as YamlMap)[r'$ref']);
        }
        final responses = o['responses'] as YamlMap;
        final ok = responses.keys
            .map((k) => '$k')
            .where((k) => k.startsWith('2'))
            .toList();
        if (ok.length != 1) throw ApiCodegenError('$id: one 2xx expected');
        final okResp = responses[ok.single] is YamlMap
            ? responses[ok.single] as YamlMap
            : responses[int.parse(ok.single)] as YamlMap;
        String? response;
        final rc = okResp['content'] as YamlMap?;
        if (rc != null) {
          final json = rc['application/json'] as YamlMap?;
          if (json == null) throw ApiCodegenError('$id: JSON response');
          response = _refName((json['schema'] as YamlMap)[r'$ref']);
        }
        final headers = (okResp['headers'] as YamlMap?)?.keys ?? const [];
        final security = o['security'] as YamlList?;
        final String auth;
        if (security == null || security.isEmpty) {
          auth = 'none';
        } else {
          final sets = [
            for (final s in security)
              {for (final k in (s as YamlMap).keys) k as String},
          ];
          bool isSet(Set<String> s, List<String> w) =>
              s.length == w.length && s.containsAll(w);
          if (sets.length == 1 && isSet(sets[0], ['installToken'])) {
            auth = 'install';
          } else if (sets.length == 1 &&
              isSet(sets[0], ['installToken', 'accountToken'])) {
            auth = 'installAndAccount';
          } else if (sets.length == 2 &&
              isSet(sets[0], ['installToken']) &&
              isSet(sets[1], ['installToken', 'accountToken'])) {
            auth = 'installWithOptionalAccount';
          } else {
            throw ApiCodegenError('$id: unsupported security');
          }
        }
        found[id] = _Op(
          id: id,
          method: method.toUpperCase(),
          path: path,
          successStatus: int.parse(ok.single),
          signed: headers.contains('Zaghlol-Signature'),
          anchoring: params.contains('ZaghlolTimeNonce'),
          idempotent: params.contains('IdempotencyKey'),
          auth: auth,
          request: request,
          response: response,
        );
      }
    }
    return [
      for (final id in appOperationIds)
        found[id] ?? (throw ApiCodegenError('missing operation $id')),
    ];
  }

  void _emitOperations(StringBuffer b, List<_Op> ops) {
    b
      ..writeln('/// Who an operation authenticates as (OpenAPI `security`).')
      ..writeln('enum ApiAuth {')
      ..writeln('  none,')
      ..writeln('  install,')
      ..writeln('  installWithOptionalAccount,')
      ..writeln('  installAndAccount,')
      ..writeln('}')
      ..writeln()
      ..writeln('/// One app-facing operation, as the contract declares it.')
      ..writeln('final class ApiOperation {')
      ..writeln('  const ApiOperation({')
      ..writeln('    required this.id,')
      ..writeln('    required this.method,')
      ..writeln('    required this.path,')
      ..writeln('    required this.successStatus,')
      ..writeln('    required this.signed,')
      ..writeln('    required this.anchoring,')
      ..writeln('    required this.idempotent,')
      ..writeln('    required this.auth,')
      ..writeln('    required this.requestSchema,')
      ..writeln('    required this.responseSchema,')
      ..writeln('  });')
      ..writeln('  final String id;')
      ..writeln('  final String method;')
      ..writeln('  final String path;')
      ..writeln('  final int successStatus;')
      ..writeln('  /// The 2xx carries `Zaghlol-Signature`.')
      ..writeln('  final bool signed;')
      ..writeln('  /// Takes `Zaghlol-Time-Nonce` (R4-2).')
      ..writeln('  final bool anchoring;')
      ..writeln('  /// Takes `Idempotency-Key` (R3-6).')
      ..writeln('  final bool idempotent;')
      ..writeln('  final ApiAuth auth;')
      ..writeln('  final String? requestSchema;')
      ..writeln('  final String? responseSchema;')
      ..writeln('  @override')
      ..writeln("  String toString() => 'ApiOperation(\$id)';")
      ..writeln('}')
      ..writeln()
      ..writeln('abstract final class ApiOperations {');
    for (final op in ops) {
      b
        ..writeln('  static const ApiOperation ${op.id} = ApiOperation(')
        ..writeln("    id: '${op.id}',")
        ..writeln("    method: '${op.method}',")
        ..writeln("    path: '${op.path}',")
        ..writeln('    successStatus: ${op.successStatus},')
        ..writeln('    signed: ${op.signed},')
        ..writeln('    anchoring: ${op.anchoring},')
        ..writeln('    idempotent: ${op.idempotent},')
        ..writeln('    auth: ApiAuth.${op.auth},')
        ..writeln(
          '    requestSchema: '
          '${op.request == null ? 'null' : "'${op.request}'"},',
        )
        ..writeln(
          '    responseSchema: '
          '${op.response == null ? 'null' : "'${op.response}'"},',
        )
        ..writeln('  );');
    }
    b
      ..writeln('  static const List<ApiOperation> all = [')
      ..writeln([for (final op in ops) '    ${op.id},'].join('\n'))
      ..writeln('  ];')
      ..writeln('}')
      ..writeln();
  }

  // ---- schema walk ----------------------------------------------------------

  String _refName(Object? ref) {
    if (ref is! String || !ref.startsWith('#/components/schemas/')) {
      throw ApiCodegenError('unsupported ref $ref');
    }
    final name = ref.substring('#/components/schemas/'.length);
    if (!schemas.containsKey(name)) throw ApiCodegenError('unknown $name');
    return name;
  }

  YamlMap _schema(String name) => schemas[name] as YamlMap;

  bool _isNullSchema(Object? s) => s is YamlMap && s['type'] == 'null';

  /// Resolves a named schema and records what must be emitted.
  _Resolved _visitNamed(String name, String dir) {
    final s = _schema(name);
    final oneOf = s['oneOf'] as YamlList?;
    if (oneOf != null) {
      final disc = s['discriminator'] as YamlMap?;
      if (disc != null) {
        final prop = disc['propertyName'] as String;
        final mapping = <String, String>{};
        for (final e in (disc['mapping'] as YamlMap).entries) {
          mapping[e.key as String] = _refName(e.value);
        }
        final first = !_sealed.containsKey(name);
        _sealed[name] = (prop, mapping);
        _classes.putIfAbsent(name, () => <String>{}).add(dir);
        for (final v in mapping.values) {
          final prev = _variantOf[v];
          if (prev != null && prev != name) {
            throw ApiCodegenError('$v is a variant of two bases');
          }
          _variantOf[v] = name;
          _visitNamed(v, dir);
        }
        if (first) {
          for (final b in oneOf) {
            final n = _refName((b as YamlMap)[r'$ref']);
            if (!mapping.containsValue(n)) {
              throw ApiCodegenError('$name: $n not in mapping');
            }
          }
        }
        return _Resolved(_Obj(name));
      }
      return _nullableOneOf(oneOf, name, dir);
    }
    final type = s['type'];
    if (type == 'object' || s.containsKey('properties')) {
      final dirs = _classes.putIfAbsent(name, () => <String>{});
      final again = dirs.contains(dir);
      dirs.add(dir);
      if (!again) _visitObject(name, s, dir);
      return _Resolved(_Obj(name));
    }
    return _scalar(s, name, dir);
  }

  _Resolved _nullableOneOf(YamlList oneOf, String ctx, String dir) {
    final nonNull = oneOf.where((b) => !_isNullSchema(b)).toList();
    if (nonNull.length != 1 || oneOf.length != 2) {
      throw ApiCodegenError('$ctx: oneOf must be [X, null] or discriminated');
    }
    final r = _resolve(nonNull.single, ctx, dir);
    return _Resolved(r.type, nullable: true);
  }

  _Resolved _resolve(Object? node, String ctx, String dir) {
    if (node is! YamlMap) throw ApiCodegenError('$ctx: bad schema');
    if (node.containsKey(r'$ref')) {
      return _visitNamed(_refName(node[r'$ref']), dir);
    }
    final oneOf = node['oneOf'] as YamlList?;
    if (oneOf != null) return _nullableOneOf(oneOf, ctx, dir);
    final type = node['type'];
    if (type is YamlList) {
      final ts = type.toList();
      if (ts.length == 2 && ts.contains('null')) {
        final t = ts.firstWhere((x) => x != 'null');
        final copy = {...node.value, 'type': t};
        final r = _resolve(YamlMap.wrap(copy), ctx, dir);
        return _Resolved(r.type, nullable: true);
      }
      throw ApiCodegenError('$ctx: unsupported type list');
    }
    if (type == 'array') {
      final item = _resolve(node['items'], ctx, dir);
      if (item.nullable) throw ApiCodegenError('$ctx: nullable items');
      return _Resolved(
        _List(
          item.type,
          minItems: node['minItems'] as int?,
          maxItems: node['maxItems'] as int?,
        ),
      );
    }
    if (type == 'object') {
      if (node.containsKey('properties')) {
        throw ApiCodegenError('$ctx: inline objects are not supported');
      }
      final ap = node['additionalProperties'];
      if (ap is! YamlMap) throw ApiCodegenError('$ctx: free-form object');
      final v = _resolve(ap, ctx, dir);
      if (v.nullable) throw ApiCodegenError('$ctx: nullable map values');
      final pn = node['propertyNames'] as YamlMap?;
      final kp = pn?['pattern'] as String?;
      if (kp != null) _pat(kp);
      return _Resolved(_Map(v.type, keyPattern: kp));
    }
    return _scalar(node, ctx, dir);
  }

  _Resolved _scalar(YamlMap s, String ctx, String dir) {
    final type = s['type'];
    switch (type) {
      case 'string':
        final en = s['enum'] as YamlList?;
        if (en != null) {
          final values = [for (final v in en) v as String];
          final prev = _enums[ctx];
          if (prev != null && prev.join('|') != values.join('|')) {
            throw ApiCodegenError('enum name clash $ctx');
          }
          if (prev == null && _classes.containsKey(ctx)) {
            throw ApiCodegenError('enum/class name clash $ctx');
          }
          _enums[ctx] = values;
          _enumDirs.putIfAbsent(ctx, () => <String>{}).add(dir);
          return _Resolved(_Enum(ctx));
        }
        final p = s['pattern'] as String?;
        if (p != null) _pat(p);
        return _Resolved(
          _Str(
            pattern: p,
            minLength: s['minLength'] as int?,
            maxLength: s['maxLength'] as int?,
          ),
        );
      case 'integer':
        return _Resolved(
          _Int(min: s['minimum'] as int?, max: s['maximum'] as int?),
        );
      case 'boolean':
        return _Resolved(_Bool());
      default:
        throw ApiCodegenError('$ctx: unsupported type $type');
    }
  }

  int _pat(String p) {
    final i = _patterns.indexOf(p);
    if (i >= 0) return i;
    _patterns.add(p);
    return _patterns.length - 1;
  }

  void _visitObject(String name, YamlMap s, String dir) {
    if (s.containsKey('allOf') || s.containsKey('anyOf')) {
      throw ApiCodegenError('$name: allOf/anyOf unsupported');
    }
    final required = {
      for (final r in (s['required'] as YamlList? ?? YamlList())) r as String,
    };
    final props = <_Prop>[];
    final pm = (s['properties'] as YamlMap?) ?? YamlMap();
    for (final e in pm.entries) {
      final wire = e.key as String;
      final ps = e.value as YamlMap;
      if (ps.containsKey('const')) {
        props.add(
          _Prop(
            wire: wire,
            field: _ident(wire),
            type: null,
            required: true,
            nullable: false,
            constValue: '${ps['const']}',
          ),
        );
        continue;
      }
      final r = _resolve(ps, '$name${_pascal(wire)}', dir);
      final isReq = required.contains(wire);
      props.add(
        _Prop(
          wire: wire,
          field: _ident(wire),
          type: r.type,
          required: isReq,
          nullable: r.nullable || !isReq,
        ),
      );
    }
    for (final r in required) {
      if (!pm.containsKey(r)) throw ApiCodegenError('$name: required $r');
    }
    if (_props.containsKey(name)) return;
    _props[name] = props;
    _closed[name] = s['additionalProperties'] == false;
  }

  // ---- emit ---------------------------------------------------------------

  void _emitEnum(StringBuffer b, String name) {
    final values = _enums[name]!;
    final res = _enumDirs[name]!.contains('res');
    b.writeln('enum $name {');
    final seen = <String>{};
    for (final v in values) {
      final id = _camel(v);
      if (!seen.add(id) || id == 'unknown') {
        throw ApiCodegenError('$name: enum identifier clash $id');
      }
      b.writeln('  $id(${_lit(v)}),');
    }
    b
      ..writeln(
        '  /// A value this app version does not know (responses only; never '
        'sent).',
      )
      ..writeln('  unknown(null);')
      ..writeln()
      ..writeln('  const $name(this.wire);')
      ..writeln('  final String? wire;');
    if (res) {
      b
        ..writeln()
        ..writeln('  static $name fromJson(Object? json) {')
        ..writeln('    final s = apiString(json);')
        ..writeln('    for (final v in values) {')
        ..writeln('      if (v.wire == s) return v;')
        ..writeln('    }')
        ..writeln('    return unknown;')
        ..writeln('  }');
    }
    b
      ..writeln('}')
      ..writeln();
  }

  void _emitSealed(StringBuffer b, String name) {
    final (prop, mapping) = _sealed[name]!;
    final dirs = _classes[name]!;
    b
      ..writeln('sealed class $name {')
      ..writeln('  const $name();');
    if (dirs.contains('req')) {
      b
        ..writeln()
        ..writeln('  Map<String, Object?> toJson();');
    }
    if (dirs.contains('res')) {
      b
        ..writeln()
        ..writeln('  factory $name.fromJson(Object? json) {')
        ..writeln('    final m = apiObject(json);')
        ..writeln("    return switch (apiString(apiRequired(m, '$prop'))) {");
      for (final e in mapping.entries) {
        b.writeln('      ${_lit(e.key)} => ${e.value}.fromJson(m),');
      }
      b
        ..writeln('      _ => const ${name}Unknown(),')
        ..writeln('    };')
        ..writeln('  }');
    }
    b
      ..writeln('}')
      ..writeln();
    if (dirs.contains('res')) {
      b
        ..writeln('/// A `$prop` value this app version does not know.')
        ..writeln('final class ${name}Unknown extends $name {')
        ..writeln('  const ${name}Unknown();');
      if (dirs.contains('req')) {
        b
          ..writeln('  @override')
          ..writeln('  Map<String, Object?> toJson() =>')
          ..writeln(
            '      throw ApiModelException(ApiModelException.invalid);',
          );
      }
      b
        ..writeln('  @override')
        ..writeln("  String toString() => '${name}Unknown';")
        ..writeln('}')
        ..writeln();
    }
  }

  void _emitClass(StringBuffer b, String name) {
    final props = _props[name]!;
    final dirs = _classes[name]!;
    final base = _variantOf[name];
    final fields = props.where((p) => p.constValue == null).toList();
    if (dirs.contains('req') && _closed[name] != true) {
      // BR-SYNC-03: every body the app sends is a closed schema.
      throw ApiCodegenError('$name: request schemas must be closed');
    }
    b.writeln('final class $name${base == null ? '' : ' extends $base'} {');
    if (fields.isEmpty) {
      b.writeln('  const $name();');
    } else {
      b.writeln('  const $name({');
      for (final p in fields) {
        b.writeln('    ${p.required ? 'required ' : ''}this.${p.field},');
      }
      b.writeln('  });');
    }
    for (final p in props) {
      if (p.constValue != null) {
        b.writeln(
          '  static const String ${p.field}Value = ${_lit(p.constValue!)};',
        );
      }
    }
    for (final p in fields) {
      b.writeln(
        '  final ${_dartType(p.type!)}${p.nullable ? '?' : ''} '
        '${p.field};',
      );
    }
    if (dirs.contains('req')) {
      b
        ..writeln()
        ..writeln('  /// Declared properties only; throws [ApiModelException]')
        ..writeln('  /// before anything is built when a constraint fails.')
        ..write(base != null ? '  @override\n' : '')
        ..writeln('  Map<String, Object?> toJson() => {');
      for (final p in props) {
        if (p.constValue != null) {
          b.writeln("    '${p.wire}': ${p.field}Value,");
        } else if (p.nullable) {
          b.writeln(
            "    if (${p.field} != null) '${p.wire}': "
            '${_enc(p.type!, '${p.field}!')},',
          );
        } else {
          b.writeln("    '${p.wire}': ${_enc(p.type!, p.field)},");
        }
      }
      b.writeln('  };');
    }
    if (dirs.contains('res')) {
      b
        ..writeln()
        ..writeln('  factory $name.fromJson(Object? json) {')
        ..writeln('    final m = apiObject(json);');
      for (final p in props) {
        if (p.constValue != null) {
          b.writeln(
            "    apiConst(apiRequired(m, '${p.wire}'), ${p.field}Value);",
          );
        }
      }
      if (fields.isEmpty) {
        b.writeln('    return const $name();');
      } else {
        b.writeln('    return $name(');
        for (final p in fields) {
          final read = p.required
              ? "apiRequired(m, '${p.wire}')"
              : "m['${p.wire}']";
          if (p.nullable) {
            b.writeln(
              '      ${p.field}: apiNullable($read, '
              '(v) => ${_dec(p.type!, 'v')}),',
            );
          } else {
            b.writeln('      ${p.field}: ${_dec(p.type!, read)},');
          }
        }
        b.writeln('    );');
      }
      b.writeln('  }');
    }
    b
      ..writeln()
      ..writeln('  /// Never prints values (tokens, keys, purchase data).')
      ..writeln('  @override')
      ..writeln("  String toString() => '$name';")
      ..writeln('}')
      ..writeln();
  }

  String _dartType(_T t) => switch (t) {
    _Str() => 'String',
    _Int() => 'int',
    _Bool() => 'bool',
    _Enum(:final name) => name,
    _Obj(:final name) => name,
    _List(:final item) => 'List<${_dartType(item)}>',
    _Map(:final value) => 'Map<String, ${_dartType(value)}>',
  };

  String _strArgs(_Str t) => [
    if (t.pattern != null) 'pattern: _re${_pat(t.pattern!)}',
    if (t.minLength != null) 'minLength: ${t.minLength}',
    if (t.maxLength != null) 'maxLength: ${t.maxLength}',
  ].map((a) => ', $a').join();

  String _intArgs(_Int t) => [
    if (t.min != null) 'min: ${t.min}',
    if (t.max != null) 'max: ${t.max}',
  ].map((a) => ', $a').join();

  String _listArgs(_List t) => [
    if (t.minItems != null) 'minItems: ${t.minItems}',
    if (t.maxItems != null) 'maxItems: ${t.maxItems}',
  ].map((a) => ', $a').join();

  String _enc(_T t, String v) => switch (t) {
    _Str() => 'apiCheckString($v${_strArgs(t)})',
    _Int() => 'apiCheckInt($v${_intArgs(t)})',
    _Bool() => v,
    _Enum() => 'apiCheckEnum($v.wire)',
    _Obj() => '$v.toJson()',
    _List(:final item) =>
      'apiCheckList($v${_listArgs(t)}).map((e) => ${_enc(item, 'e')})'
          '.toList()',
    _Map() => throw ApiCodegenError('maps are not sendable'),
  };

  String _dec(_T t, String v) => switch (t) {
    _Str() => 'apiString($v${_strArgs(t)})',
    _Int() => 'apiInt($v${_intArgs(t)})',
    _Bool() => 'apiBool($v)',
    _Enum(:final name) => '$name.fromJson($v)',
    _Obj(:final name) => '$name.fromJson($v)',
    _List(:final item) =>
      'List<${_dartType(item)}>.unmodifiable(apiList($v${_listArgs(t)})'
          '.map((e) => ${_dec(item, 'e')}))',
    _Map(:final value, :final keyPattern) =>
      'Map<String, ${_dartType(value)}>.unmodifiable({'
          'for (final e in apiObject($v).entries) '
          'apiString(e.key${keyPattern == null ? '' : ', pattern: _re${_pat(keyPattern)}'}): '
          '${_dec(value, 'e.value')}})',
  };
}
