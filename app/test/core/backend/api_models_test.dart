// T-141: the generated DTOs against the contract.
//
// - Drift (FU-013): regenerating from backend/openapi/zaghlol-v1.yaml with
//   the in-repo generator gives the committed file byte for byte.
// - Allow-list (BR-SYNC-03, security-model §2): every request type, with
//   every optional member set, serializes to JSON that an independent
//   validator accepts against the closed request schema (no member outside
//   `properties`, every `required` member present, patterns and bounds).
// - Responses: unknown fields ignored, unknown enum values tolerated,
//   schema violations refused without echoing input.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:zaghlol/core/backend/generated/api_models.g.dart';

import '../../../tool/api_codegen/api_codegen.dart' as codegen;
import '../../../tool/api_codegen/render.dart';

final YamlMap _spec = loadYaml(File(openApiPath).readAsStringSync()) as YamlMap;
final YamlMap _schemas = (_spec['components'] as YamlMap)['schemas'] as YamlMap;

const _jws = 'aGVhZGVy.cGF5bG9hZA.c2lnbmF0dXJl';
const _b64Seat =
    'BA'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
final _sig86 = 'A' * 86;

SeatKeyProof get _seat => SeatKeyProof(publicKey: _b64Seat, signature: _sig86);

/// One fully populated sample per request type (every optional member set).
final Map<String, Map<String, Object?> Function()> _samples = {
  'InstallRequest': () => const InstallRequest(
    installId: '0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77',
    platform: Platform.android,
    appVersion: '1.0.0',
  ).toJson(),
  'SyncRequest': () => const SyncRequest(
    catalogVersion: 41,
    flagsVersion: 7,
    pricesAsOf: '2026-11-02T09:00:00Z',
    entitlementIssuedAt: '2026-10-30T10:00:00Z',
    registryVersion: 12,
    contributions: [
      ContributionInput(
        merchantNorm: 'cafe x',
        institutionCode: 'cib',
        categoryCode: 'food',
      ),
    ],
    bankRequests: [
      BankRequestInput(
        institutionName: 'Bank X',
        country: 'EG',
        channel: BankRequestInputChannel.sms,
      ),
    ],
  ).toJson(),
  'ContributionInput': () => const ContributionInput(
    merchantNorm: 'cafe x',
    institutionCode: 'cib',
    categoryCode: 'food',
  ).toJson(),
  'BankRequestInput': () => const BankRequestInput(
    institutionName: 'Bank X',
    country: 'EG',
    channel: BankRequestInputChannel.notification,
  ).toJson(),
  'PurchaseVerifyAndroidRequest': () => const PurchaseVerifyAndroidRequest(
    productId: 'gold.monthly',
    purchaseToken: 'synthetic-token',
  ).toJson(),
  'PurchaseVerifyIosRequest': () => PurchaseVerifyIosRequest(
    signedTransaction: _jws,
    seatKeys: [_seat],
  ).toJson(),
  'SeatKeyProof': () => _seat.toJson(),
  'AndroidPurchaseRef': () => const AndroidPurchaseRef(
    productId: 'gold.monthly',
    purchaseToken: 'synthetic-token',
  ).toJson(),
  'PlayIntegrityProof': () =>
      const PlayIntegrityProof(token: 'abcdefghijklmnopqrstuvwxyz').toJson(),
  'AppAttestProof': () => AppAttestProof(
    keyId: '${'A' * 43}=',
    assertion: 'QUJDREVGR0hJSktMTU5PUA==',
    attestationObject: 'QUJDREVGR0hJSktMTU5PUA==',
    seatKeys: [_seat],
  ).toJson(),
  'PurchaseRestoreAndroidRequest': () => const PurchaseRestoreAndroidRequest(
    purchases: [
      AndroidPurchaseRef(productId: 'gold.yearly', purchaseToken: 't'),
    ],
    attestation: PlayIntegrityProof(token: 'abcdefghijklmnopqrstuvwxyz'),
  ).toJson(),
  'PurchaseRestoreIosRequest': () => PurchaseRestoreIosRequest(
    signedTransactions: const [_jws],
    attestation: AppAttestProof(
      keyId: '${'A' * 43}=',
      assertion: 'QUJDREVGR0hJSktMTU5PUA==',
      seatKeys: [_seat],
    ),
  ).toJson(),
  'SignInRequest': () => SignInRequest(
    provider: SignInRequestProvider.apple,
    idToken: _jws,
    nonce: 'n' * 22,
    authorizationCode: 'code',
    replaceLink: true,
    seatKeys: [_seat],
  ).toJson(),
};

/// The object schemas reachable from the app's request bodies.
Set<String> _requestObjectSchemas() {
  final paths = _spec['paths'] as YamlMap;
  final roots = <String>{};
  for (final ops in paths.values) {
    for (final o in (ops as YamlMap).values) {
      if (o is! YamlMap ||
          !codegen.appOperationIds.contains(o['operationId'])) {
        continue;
      }
      final rb = o['requestBody'] as YamlMap?;
      if (rb == null) continue;
      final ref =
          (((rb['content'] as YamlMap)['application/json'] as YamlMap)['schema']
                  as YamlMap)[r'$ref']
              as String;
      roots.add(ref.split('/').last);
    }
  }
  final out = <String>{};
  void walk(Object? node) {
    if (node is YamlMap) {
      final ref = node[r'$ref'];
      if (ref is String) {
        final name = ref.split('/').last;
        final s = _schemas[name] as YamlMap;
        if ((s['type'] == 'object' || s.containsKey('properties')) &&
            !out.add(name)) {
          return;
        }
        walk(s);
        return;
      }
      for (final v in node.values) {
        walk(v);
      }
    } else if (node is YamlList) {
      for (final v in node) {
        walk(v);
      }
    }
  }

  for (final r in roots) {
    walk(YamlMap.wrap({r'$ref': '#/components/schemas/$r'}));
  }
  return out;
}

/// An independent, minimal JSON Schema check (only what the request schemas
/// use). Returns the first problem, or null.
String? _validate(Object? v, YamlMap s, String at) {
  final ref = s[r'$ref'];
  if (ref is String) {
    return _validate(v, _schemas[ref.split('/').last] as YamlMap, at);
  }
  final oneOf = s['oneOf'] as YamlList?;
  if (oneOf != null) {
    final ok = oneOf.where((b) => _validate(v, b as YamlMap, at) == null);
    return ok.length == 1 ? null : '$at: matches ${ok.length} oneOf branches';
  }
  if (s.containsKey('const') && v != s['const']) return '$at: const';
  final type = s['type'];
  switch (type) {
    case 'object':
      if (v is! Map<String, Object?>) return '$at: not an object';
      final props = (s['properties'] as YamlMap?) ?? YamlMap();
      if (s['additionalProperties'] != false) return '$at: open request schema';
      for (final k in v.keys) {
        if (!props.containsKey(k)) return '$at: member $k not allowed';
      }
      for (final r in (s['required'] as YamlList? ?? YamlList())) {
        if (!v.containsKey(r)) return '$at: missing $r';
      }
      for (final e in v.entries) {
        final p = _validate(e.value, props[e.key] as YamlMap, '$at.${e.key}');
        if (p != null) return p;
      }
      return null;
    case 'array':
      if (v is! List) return '$at: not an array';
      if (s['minItems'] is int && v.length < (s['minItems'] as int)) {
        return '$at: minItems';
      }
      if (s['maxItems'] is int && v.length > (s['maxItems'] as int)) {
        return '$at: maxItems';
      }
      for (var i = 0; i < v.length; i++) {
        final p = _validate(v[i], s['items'] as YamlMap, '$at[$i]');
        if (p != null) return p;
      }
      return null;
    case 'string':
      if (v is! String) return '$at: not a string';
      final en = s['enum'] as YamlList?;
      if (en != null && !en.contains(v)) return '$at: enum';
      final pat = s['pattern'] as String?;
      if (pat != null && !RegExp(pat).hasMatch(v)) return '$at: pattern';
      if (s['maxLength'] is int && v.length > (s['maxLength'] as int)) {
        return '$at: maxLength';
      }
      if (s['minLength'] is int && v.length < (s['minLength'] as int)) {
        return '$at: minLength';
      }
      return null;
    case 'integer':
      if (v is! int) return '$at: not an integer';
      if (s['minimum'] is int && v < (s['minimum'] as int)) return '$at: min';
      if (s['maximum'] is int && v > (s['maximum'] as int)) return '$at: max';
      return null;
    case 'boolean':
      return v is bool ? null : '$at: not a boolean';
    case null:
      if (s.containsKey('const')) return null;
      return '$at: untyped schema';
    default:
      return '$at: unsupported $type';
  }
}

void main() {
  test('FU-013: the committed models equal a fresh generation', () async {
    final fresh = await renderApiModels();
    final committed = File(generatedModelsPath).readAsStringSync();
    expect(
      fresh == committed,
      isTrue,
      reason:
          'run `dart run tool/api_codegen/main.dart` in app/ and commit the '
          'result',
    );
    expect(
      committed,
      contains('zaghlol-api-codegen ${codegen.apiCodegenVersion}'),
    );
  });

  test('the operation table matches the contract', () {
    expect(ApiOperations.all.map((o) => o.id), codegen.appOperationIds);
    expect(
      ApiOperations.all.where((o) => o.anchoring).map((o) => o.id).toSet(),
      {
        'sync',
        'getEntitlement',
        'verifyPurchase',
        'restorePurchases',
        'signIn',
        'signOut',
      },
    );
    expect(
      ApiOperations.all.where((o) => o.idempotent).map((o) => o.id).toSet(),
      {'registerInstall', 'verifyPurchase', 'signIn'},
    );
    for (final o in ApiOperations.all.where((o) => o.anchoring)) {
      expect(o.signed, isTrue, reason: o.id);
    }
    expect(ApiOperations.getFullCatalog.signed, isTrue);
    expect(ApiOperations.registerInstall.auth, ApiAuth.none);
    expect(ApiOperations.signIn.auth, ApiAuth.install);
    expect(ApiOperations.signOut.auth, ApiAuth.installAndAccount);
  });

  group('only allow-listed members can be serialized (BR-SYNC-03)', () {
    test('every request type has a sample', () {
      expect(_samples.keys.toSet(), _requestObjectSchemas());
    });
    for (final e in _samples.entries) {
      test(e.key, () {
        final json = jsonDecode(jsonEncode(e.value())) as Object?;
        expect(_validate(json, _schemas[e.key] as YamlMap, e.key), isNull);
      });
    }

    test('optional members left null are omitted, never sent as null', () {
      final j = const SignInRequest(
        provider: SignInRequestProvider.google,
        idToken: _jws,
        nonce: 'nnnnnnnnnnnnnnnnnnnnnn',
      ).toJson();
      expect(j.keys.toSet(), {'provider', 'idToken', 'nonce'});
    });

    test('a constraint violation throws before anything is built', () {
      expect(
        () => const InstallRequest(
          installId: 'x',
          platform: Platform.android,
          appVersion: '1.0',
        ).toJson(),
        throwsA(
          isA<ApiModelException>().having(
            (e) => e.toString(),
            'code only',
            'API_REQUEST_INVALID',
          ),
        ),
      );
      expect(
        () => const InstallRequest(
          installId: 'x',
          platform: Platform.unknown,
          appVersion: '1.0.0',
        ).toJson(),
        throwsA(isA<ApiModelException>()),
      );
      expect(
        () => SyncRequest(
          catalogVersion: 1,
          flagsVersion: 1,
          contributions: List.filled(
            51,
            const ContributionInput(
              merchantNorm: 'ab',
              institutionCode: 'cib',
              categoryCode: 'food',
            ),
          ),
        ).toJson(),
        throwsA(isA<ApiModelException>()),
      );
    });
  });

  group('responses', () {
    test('unknown fields are ignored, unknown enum values tolerated', () {
      final r = PurchaseVerifyResponse.fromJson({
        'status': 'brand_new_status',
        'serverTime': '2026-11-03T18:22:01Z',
        'entitlement': null,
        'somethingNew': {'a': 1},
      });
      expect(r.status, PurchaseStatus.unknown);
      expect(r.entitlement, isNull);
      final p = Problem.fromJson({
        'type': 't',
        'title': 't',
        'status': 418,
        'code': 'SOME_FUTURE_CODE',
      });
      expect(p.code, ProblemCode.unknown);
    });

    test('a schema violation is refused without echoing input', () {
      const secret = 'SENTINEL_SECRET_VALUE';
      for (final bad in <Object?>[
        {'installToken': secret, 'serverTime': '2026-11-03T18:22:01Z'},
        {'installToken': 'A' * 43},
        {'installToken': 'A' * 43, 'serverTime': 5},
        [secret],
        null,
      ]) {
        expect(
          () => InstallResponse.fromJson(bad),
          throwsA(
            isA<ApiModelException>().having(
              (e) => e.toString(),
              'code only',
              'API_RESPONSE_MALFORMED',
            ),
          ),
        );
      }
    });

    test('integers must be integers, not doubles', () {
      expect(
        () =>
            AcceptedCounts.fromJson({'contributions': 1.0, 'bankRequests': 0}),
        throwsA(isA<ApiModelException>()),
      );
    });

    test(
      'discriminated unions decode by tag; an unknown tag is kept apart',
      () {
        final s = CatalogSnapshot.fromJson({
          'version': 3,
          'ops': [
            {'t': 'merchant', 'op': 'delete', 'id': 4},
            {'t': 'future_entity', 'op': 'upsert'},
          ],
        });
        expect(s.ops[0], isA<MerchantOp>());
        expect(s.ops[1], isA<CatalogOpUnknown>());
      },
    );

    test('toString never prints values', () {
      final r = InstallResponse.fromJson({
        'installToken': 'A' * 43,
        'serverTime': '2026-11-03T18:22:01Z',
      });
      expect(r.toString(), 'InstallResponse');
    });
  });
}
