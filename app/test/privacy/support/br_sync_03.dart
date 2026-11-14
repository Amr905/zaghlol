// T-171: the BR-SYNC-03 allow-list for the privacy contract test
// (testing-strategy §1 row "Privacy" check 2, §6; security-model §2.4).
//
// Written by hand from the SRS, NOT from the generated DTOs, so a new field
// in the OpenAPI file or the generator fails here until someone classifies
// it against BR-SYNC-03 (and the privacy screen, FR-ONB-07).
//
// Sources: CLAUDE.md §2.1; SRS BR-SYNC-03 with D-45 (attestation proof on
// restore), D-48 (classification of version cursors, restore productId,
// sign-in nonce, time nonce), D-55/D-62 (iOS `seatKeys`, own key only on
// verify per v1.8 R5-9), NFR-SEC-08 (`Zaghlol-Time-Nonce` on the six
// anchoring requests); backend-api §1-§4.
//
// Everything is synthetic; nothing here is a real token or key.

import 'dart:convert';

import 'package:zaghlol/core/backend/transport.dart';
import 'package:zaghlol/features/settings/presentation/server_allow_list.dart';

/// The BR-SYNC-03 data class a wire member belongs to, mapped to the entry
/// of the "What Zaghlol's server knows" screen that discloses it.
enum WireClass {
  /// Anonymous install ID, platform, app version.
  appId(ServerKnows.appId),

  /// Catalog / flags / prices / registry versions and the entitlement
  /// cursor (D-48).
  versions(ServerKnows.versions),

  /// Purchase tokens / signed transactions, restore productId (D-48).
  purchase(ServerKnows.purchase),

  /// Optional account ID token, raw sign-in nonce (D-48), provider choice.
  signIn(ServerKnows.signIn),

  /// Opt-in merchant contributions.
  merchants(ServerKnows.merchants),

  /// "Request my bank" (FR-PAR-14).
  bankRequest(ServerKnows.bankRequest),

  /// Play Integrity / App Attest proof, restore only (D-45).
  attestation(ServerKnows.attestation),

  /// iOS seat keys (D-55/D-62).
  seatKeys(ServerKnows.seatKeys),

  /// Per-request random nonce (NFR-SEC-08, D-48 v1.7).
  timeNonce(ServerKnows.timeNonce),

  /// Protocol plumbing that carries no user or device data: the install
  /// token the server issued, Idempotency-Key, Accept, Content-Type.
  protocol(null);

  const WireClass(this.disclosedAs);
  final ServerKnows? disclosedAs;
}

/// A closed JSON schema node: an object with exactly these optional members,
/// a list of one node, or a leaf of one [WireClass].
sealed class Node {
  const Node();
}

final class Obj extends Node {
  const Obj(this.members);
  final Map<String, Node> members;
}

final class Arr extends Node {
  const Arr(this.item, {required this.maxItems});
  final Node item;
  final int maxItems;
}

final class Leaf extends Node {
  const Leaf(this.cls);
  final WireClass cls;
}

const _seatKey = Obj({
  'publicKey': Leaf(WireClass.seatKeys),
  'signature': Leaf(WireClass.seatKeys),
});

/// Android bodies (`platform: android`).
const Map<String, Obj> androidBodies = {
  'POST /v1/installs': _install,
  'POST /v1/sync': _sync,
  'POST /v1/purchases/verify': Obj({
    'platform': Leaf(WireClass.appId),
    'productId': Leaf(WireClass.purchase),
    'purchaseToken': Leaf(WireClass.purchase),
  }),
  'POST /v1/purchases/restore': Obj({
    'platform': Leaf(WireClass.appId),
    'purchases': Arr(
      Obj({
        'productId': Leaf(WireClass.purchase),
        'purchaseToken': Leaf(WireClass.purchase),
      }),
      maxItems: 20,
    ),
    'attestation': Obj({
      'type': Leaf(WireClass.attestation),
      'token': Leaf(WireClass.attestation),
    }),
  }),
  // No `seatKeys` on Android (D-55: Android has no safe equivalent).
  'POST /v1/accounts/signin': Obj({
    'provider': Leaf(WireClass.signIn),
    'idToken': Leaf(WireClass.signIn),
    'nonce': Leaf(WireClass.signIn),
    'authorizationCode': Leaf(WireClass.signIn),
    'replaceLink': Leaf(WireClass.signIn),
  }),
};

/// iOS bodies (`platform: ios`).
const Map<String, Obj> iosBodies = {
  'POST /v1/installs': _install,
  'POST /v1/sync': _sync,
  // D-62 v1.8 (R5-9): only element 0, the install's own key, on verify.
  'POST /v1/purchases/verify': Obj({
    'platform': Leaf(WireClass.appId),
    'signedTransaction': Leaf(WireClass.purchase),
    'seatKeys': Arr(_seatKey, maxItems: 1),
  }),
  'POST /v1/purchases/restore': Obj({
    'platform': Leaf(WireClass.appId),
    'signedTransactions': Arr(Leaf(WireClass.purchase), maxItems: 20),
    'attestation': Obj({
      'type': Leaf(WireClass.attestation),
      'keyId': Leaf(WireClass.attestation),
      'assertion': Leaf(WireClass.attestation),
      'attestationObject': Leaf(WireClass.attestation),
      // D-62: own key + up to 4 earlier installs' keys.
      'seatKeys': Arr(_seatKey, maxItems: 5),
    }),
  }),
  'POST /v1/accounts/signin': Obj({
    'provider': Leaf(WireClass.signIn),
    'idToken': Leaf(WireClass.signIn),
    'nonce': Leaf(WireClass.signIn),
    'authorizationCode': Leaf(WireClass.signIn),
    'replaceLink': Leaf(WireClass.signIn),
    'seatKeys': Arr(_seatKey, maxItems: 5),
  }),
};

const _install = Obj({
  'installId': Leaf(WireClass.appId),
  'platform': Leaf(WireClass.appId),
  'appVersion': Leaf(WireClass.appId),
});

const _sync = Obj({
  'catalogVersion': Leaf(WireClass.versions),
  'flagsVersion': Leaf(WireClass.versions),
  'pricesAsOf': Leaf(WireClass.versions),
  'entitlementIssuedAt': Leaf(WireClass.versions),
  'registryVersion': Leaf(WireClass.versions),
  'contributions': Arr(
    Obj({
      'merchantNorm': Leaf(WireClass.merchants),
      'institutionCode': Leaf(WireClass.merchants),
      'categoryCode': Leaf(WireClass.merchants),
    }),
    maxItems: 50,
  ),
  'bankRequests': Arr(
    Obj({
      'institutionName': Leaf(WireClass.bankRequest),
      'country': Leaf(WireClass.bankRequest),
      'channel': Leaf(WireClass.bankRequest),
    }),
    maxItems: 10,
  ),
});

/// Requests that carry no body.
const Set<String> bodiless = {
  'DELETE /v1/installs/me',
  'GET /v1/entitlement',
  'POST /v1/accounts/signout',
  'DELETE /v1/accounts/me',
};

/// `GET /v1/catalog/{version}/full`.
final RegExp catalogPath = RegExp(r'^/v1/catalog/[1-9][0-9]{0,9}/full$');

/// The six anchoring requests (NFR-SEC-08): `Zaghlol-Time-Nonce` on these
/// and nowhere else.
const Set<String> anchoring = {
  'POST /v1/sync',
  'POST /v1/purchases/verify',
  'POST /v1/purchases/restore',
  'GET /v1/entitlement',
  'POST /v1/accounts/signin',
  'POST /v1/accounts/signout',
};

/// `Idempotency-Key` only on these three.
const Set<String> idempotent = {
  'POST /v1/installs',
  'POST /v1/purchases/verify',
  'POST /v1/accounts/signin',
};

/// Install token + install ID headers: every install-scoped request.
const Set<String> installScoped = {
  'DELETE /v1/installs/me',
  'POST /v1/sync',
  'POST /v1/purchases/verify',
  'POST /v1/purchases/restore',
  'GET /v1/entitlement',
  'POST /v1/accounts/signin',
  'POST /v1/accounts/signout',
  'DELETE /v1/accounts/me',
};

/// Where the optional account token may travel.
const Set<String> accountAllowed = {
  'POST /v1/sync',
  'POST /v1/purchases/verify',
  'POST /v1/purchases/restore',
  'GET /v1/entitlement',
  'POST /v1/accounts/signout',
  'DELETE /v1/accounts/me',
};

/// Every header name the app may send. Nothing device-related beyond the
/// `Zaghlol-App` platform/version string (no Accept-Language, no
/// User-Agent with OS/model, no cookies).
const Set<String> allowedHeaders = {
  'zaghlol-app',
  'accept',
  'content-type',
  'idempotency-key',
  'zaghlol-time-nonce',
  'authorization',
  'zaghlol-install',
  'zaghlol-account',
};

final RegExp _appHeader = RegExp(
  r'^(android|ios)/\d{1,4}\.\d{1,4}\.\d{1,4}([-+][0-9A-Za-z.-]{1,32})? \([0-9A-Za-z.-]{1,32}\)$',
);
final RegExp _timeNonce = RegExp(r'^[A-Za-z0-9_-]{21}[AQgw]$');
final RegExp _installId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// One request's verdict.
final class Checked {
  Checked(this.op, this.violations, this.classes);
  final String op;
  final List<String> violations;
  final Set<WireClass> classes;
}

/// Checks [r] against the allow-list for a client on [platform]
/// (`android` / `ios`). Violation texts name members and headers only,
/// never values.
Checked checkRequest(BackendRequest r, {required String platform}) {
  final v = <String>[];
  final classes = <WireClass>{};
  final path = r.uri.path;
  final op = catalogPath.hasMatch(path)
      ? 'GET /v1/catalog/{version}/full'
      : '${r.method} $path';

  if (r.uri.scheme != 'https') v.add('$op: not https');
  if (r.uri.hasQuery) v.add('$op: query string');
  if (r.uri.hasFragment || r.uri.userInfo.isNotEmpty) v.add('$op: uri extras');

  final bodies = platform == 'ios' ? iosBodies : androidBodies;
  final known =
      bodies.containsKey(op) ||
      bodiless.contains(op) ||
      op == 'GET /v1/catalog/{version}/full';
  if (!known) v.add('$op: operation not on the allow-list');

  // ---- headers
  for (final h in r.headers.keys) {
    if (h != h.toLowerCase()) v.add('$op: header case $h');
    if (!allowedHeaders.contains(h.toLowerCase())) v.add('$op: header $h');
  }
  final app = r.headers['zaghlol-app'];
  if (app == null || !_appHeader.hasMatch(app)) {
    v.add('$op: Zaghlol-App missing or carries more than platform/version');
  } else if (!app.startsWith('$platform/')) {
    v.add('$op: Zaghlol-App platform mismatch');
  } else {
    classes.add(WireClass.appId);
  }
  final nonce = r.headers['zaghlol-time-nonce'];
  if (anchoring.contains(op)) {
    if (nonce == null || !_timeNonce.hasMatch(nonce)) {
      v.add('$op: anchoring request without a well-formed time nonce');
    } else {
      classes.add(WireClass.timeNonce);
    }
  } else if (nonce != null) {
    v.add('$op: time nonce on a non-anchoring request');
  }
  if (idempotent.contains(op) != r.headers.containsKey('idempotency-key')) {
    v.add('$op: Idempotency-Key presence');
  }
  final scoped = installScoped.contains(op);
  if (scoped != r.headers.containsKey('authorization') ||
      scoped != r.headers.containsKey('zaghlol-install')) {
    v.add('$op: install headers presence');
  }
  final iid = r.headers['zaghlol-install'];
  if (iid != null && !_installId.hasMatch(iid)) {
    v.add('$op: Zaghlol-Install is not an install ID');
  }
  if (r.headers.containsKey('zaghlol-account') &&
      !accountAllowed.contains(op)) {
    v.add('$op: account token on a request that may not carry it');
  }
  if ((r.body != null) != r.headers.containsKey('content-type')) {
    v.add('$op: content-type without body or body without content-type');
  }

  // ---- body
  final schema = bodies[op];
  if (schema == null) {
    if (r.body != null && r.body!.isNotEmpty) v.add('$op: unexpected body');
  } else if (r.body == null) {
    v.add('$op: missing body');
  } else {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(r.body!));
    } on FormatException {
      v.add('$op: body is not JSON');
    }
    if (json != null) _walk(op, r'$', schema, json, v, classes);
    if (json is Map && json['platform'] != null) {
      if (json['platform'] != platform) v.add('$op: body platform mismatch');
    }
    if (op == 'POST /v1/purchases/restore' && json is Map) {
      final att = json['attestation'];
      final want = platform == 'ios' ? 'app_attest' : 'play_integrity';
      if (att is! Map || att['type'] != want) {
        v.add('$op: attestation type is not $want');
      }
    }
  }
  return Checked(op, v, classes);
}

void _walk(
  String op,
  String at,
  Node n,
  Object? json,
  List<String> v,
  Set<WireClass> classes,
) {
  switch (n) {
    case Obj(:final members):
      if (json is! Map) {
        v.add('$op $at: expected object');
        return;
      }
      for (final e in json.entries) {
        final child = members[e.key];
        if (child == null) {
          v.add('$op $at.${e.key}: member not on the BR-SYNC-03 allow-list');
          continue;
        }
        _walk(op, '$at.${e.key}', child, e.value, v, classes);
      }
    case Arr(:final item, :final maxItems):
      if (json is! List) {
        v.add('$op $at: expected list');
        return;
      }
      if (json.length > maxItems) v.add('$op $at: more than $maxItems items');
      for (var i = 0; i < json.length; i++) {
        _walk(op, '$at[$i]', item, json[i], v, classes);
      }
    case Leaf(:final cls):
      if (json is Map || json is List) {
        v.add('$op $at: nested value where a scalar is allowed');
        return;
      }
      if (json is double) v.add('$op $at: floating-point value');
      classes.add(cls);
  }
}

/// Every place in [r] (URL, header values, body) where one of [needles]
/// appears; returns the needle labels only.
List<String> canaryHits(BackendRequest r, Map<String, String> needles) {
  final hay = StringBuffer()
    ..write(r.uri.toString())
    ..write('\n');
  r.headers.forEach((k, val) => hay.write('$k: $val\n'));
  if (r.body != null) {
    hay.write(utf8.decode(r.body!, allowMalformed: true));
  }
  final text = hay.toString();
  final lower = text.toLowerCase();
  return [
    for (final e in needles.entries)
      if (lower.contains(e.value.toLowerCase())) e.key,
  ];
}
