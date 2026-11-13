// T-144 test support: fake clock, fake backend, JWS minting with synthetic
// keys. Nothing here is a real token, key or install ID.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/db/daos/misc_daos.dart' show DiagLevel;
import 'package:zaghlol/core/logging/diag_logger.dart';
import 'package:zaghlol/features/gold/application/entitlement.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/gold/application/time_anchor.dart';
import 'package:zaghlol/features/gold/application/trusted_time.dart';

import '../../../core/backend/backend_test_support.dart';

final int t0 = DateTime.utc(2026, 11, 13, 10).millisecondsSinceEpoch;
const int minute = 60 * 1000;
const int hour = 60 * minute;
const int day = 24 * hour;

const installA = '0b9f3c1e-aaaa-4aaa-8aaa-000000000001';
const installB = '0b9f3c1e-bbbb-4bbb-8bbb-000000000002';

String iso(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

final class FakeClock implements ClockSource {
  FakeClock({this.wall = 0, this.mono = 1000000, this.boot});
  int wall;
  int mono;
  int? boot;

  /// Real time passes: wall and monotonic both move.
  void pass(int ms) {
    wall += ms;
    mono += ms;
  }

  /// A reboot: monotonic restarts, the boot count (when there is one) moves.
  void reboot({required int uptimeMs}) {
    mono = uptimeMs;
    if (boot != null) boot = boot! + 1;
  }

  @override
  Future<ClockReading> sample() async =>
      ClockReading(wallMs: wall, monotonicMs: mono, bootCount: boot);
}

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

/// Mints an `e` JWS over [claims] with [key].
String mintJws(TestSigningKey key, Map<String, Object?> claims) {
  final h = _b64(utf8.encode(jsonEncode({'alg': 'ES256', 'kid': key.kid})));
  final p = _b64(utf8.encode(jsonEncode(claims)));
  final header = key.sign(Uint8List.fromList(ascii.encode('$h.$p')));
  final sig = RegExp(r'sig=(.*)$').firstMatch(header)!.group(1)!;
  return '$h.$p.$sig';
}

Map<String, Object?> entClaims({
  String sub = installA,
  String? acct,
  String status = 'active',
  String plan = 'yearly',
  required int iatMs,
  int? expSec,
  String? movedBy,
  String? nextMoveAt,
}) {
  final iat = iatMs ~/ 1000;
  final exp = expSec ?? iat + 3 * 86400;
  return {
    'iss': 'zaghlol',
    'sub': sub,
    'acct': acct,
    'plan': plan,
    'status': status,
    'exp': exp,
    'graceUntil': exp + 4 * 86400,
    'iat': iat,
    'nextMoveAt': nextMoveAt,
    'movedBy': movedBy,
    'src': plan == 'none'
        ? <Object?>[]
        : [
            {'store': 'google_play', 'product': 'zaghlol_gold_yearly'},
          ],
    'v': 1,
  };
}

Map<String, Object?> acctClaims({
  required String sub,
  String iid = installA,
  required int iatMs,
  int? expSec,
}) => {
  'sub': sub,
  'iid': iid,
  'iat': iatMs ~/ 1000,
  'exp': expSec ?? iatMs ~/ 1000 + 30 * 86400,
};

final class FakeBackend implements EntitlementBackend {
  String? id = installA;
  final StreamController<BackendEvent> ctl = StreamController.broadcast();
  final List<String> nonces = [];
  Future<EntitlementResponse> Function(TimeNonce)? onGet;
  Future<EntitlementResponse> Function(TimeNonce)? onSignOut;
  int gets = 0;

  @override
  Future<String?> installId() async => id;
  @override
  Stream<BackendEvent> get events => ctl.stream;
  @override
  Future<EntitlementResponse> getEntitlement(TimeNonce n) {
    gets++;
    nonces.add(n.value);
    return onGet!(n);
  }

  @override
  Future<EntitlementResponse> signOut(TimeNonce n) {
    nonces.add(n.value);
    return onSignOut!(n);
  }
}

final class RecordingSink implements EntitlementSink {
  final List<EntitlementPhase> phases = [];
  MovedBy? movedBy;
  EntitlementPhase get last => phases.last;
  @override
  void apply(EntitlementPhase phase, {MovedBy? movedBy}) {
    phases.add(phase);
    this.movedBy = movedBy;
  }
}

final class CapturingDiag implements DiagStore {
  final List<String> rows = [];
  @override
  Future<void> append({
    required int at,
    required DiagLevel level,
    required String code,
    required Map<String, Object?> fields,
  }) async => rows.add('$code ${jsonEncode(fields)}');
  @override
  Future<void> prune({required int olderThan, required int keepAtMost}) async {}
}

final class Harness {
  Harness({int? boot, Random? random}) {
    clock = FakeClock(wall: t0, boot: boot);
    store = FakeBackendStore(log);
    time = TrustedTime(store: store, clock: clock);
    anchor = TimeAnchor(clock: clock, random: random ?? Random(7));
    service = EntitlementService(
      backend: backend,
      store: store,
      time: time,
      anchor: anchor,
      keys: ResponseSignatureVerifier([key.publicKey], allowDevKeys: false),
      sink: sink,
      diag: DiagLogger(diag),
    );
  }

  final List<String> log = [];
  final key = TestSigningKey('e2026a', seed: 5);
  final backend = FakeBackend();
  final sink = RecordingSink();
  final diag = CapturingDiag();
  late final FakeClock clock;
  late final FakeBackendStore store;
  late final TrustedTime time;
  late final TimeAnchor anchor;
  late final EntitlementService service;

  String token(Map<String, Object?> c) => mintJws(key, c);

  /// A normal online answer at the current clock: fresh echo of the nonce.
  Future<void> online(
    String tokenText, {
    String Function(TimeNonce n)? echo,
    SupportNotice? notice,
    int? serverMs,
  }) async {
    await service.anchored(
      (n) async => EntitlementResponse(
        entitlement: Entitlement(token: tokenText),
        serverTime: iso(serverMs ?? clock.wall),
        timeNonce: echo == null ? n.value : echo(n),
        supportNotice: notice,
      ),
      SignedBody.fromEntitlement,
    );
  }

  Future<TrustedTimeState> state() async => (await time.peek())!;
}
