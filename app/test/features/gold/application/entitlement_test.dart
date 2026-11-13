// T-144: token verification, install binding, offline bound, anchor rules,
// sign-out and support notice. Synthetic keys and IDs only.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/backend_state.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/features/gold/application/entitlement.dart';
import 'package:zaghlol/features/gold/application/gating.dart';

import '../../../core/backend/backend_test_support.dart';
import 'entitlement_harness.dart';

const _entKey = BackendStateKeys.entitlementToken;

String? _cached(Harness h) => h.store.text(_entKey);

void main() {
  group('verification and decision', () {
    test(
      'a verified, bound, active token is Gold; grace from hw >= exp',
      () async {
        final h = Harness(boot: 1);
        final t = h.token(entClaims(iatMs: t0));
        await h.online(t);
        expect(h.sink.last, EntitlementPhase.active);
        h.clock.pass(3 * day + hour);
        expect(await h.service.evaluate(), EntitlementPhase.grace);
      },
    );

    test(
      'long offline, clock untouched: Gold until exactly graceUntil',
      () async {
        final h = Harness(boot: 1);
        await h.online(h.token(entClaims(iatMs: t0)));
        h.clock.pass(7 * day - 1000);
        expect((await h.service.evaluate()).name, 'grace');
        h.clock.pass(1000); // hw == graceUntil
        expect(await h.service.evaluate(), EntitlementPhase.free);
      },
    );

    test(
      'NEGATIVE PROOF: an edited token or a bad signature never yields Gold',
      () async {
        final h = Harness(boot: 1);
        final good = h.token(entClaims(iatMs: t0));
        await h.online(good);
        expect(h.sink.last, EntitlementPhase.active);
        // Edit the payload (status flips are the realistic attack).
        final parts = good.split('.');
        final payload = utf8.decode(
          base64Url.decode(base64Url.normalize(parts[1])),
        );
        final edited = base64Url
            .encode(utf8.encode(payload.replaceFirst('"yearly"', '"lifetime"')))
            .replaceAll('=', '');
        h.store.values[_entKey] = Uint8List.fromList(
          utf8.encode('${parts[0]}.$edited.${parts[2]}'),
        );
        expect(await h.service.evaluate(), EntitlementPhase.free);
        // A token signed by a key outside the pinned set.
        final other = TestSigningKey('e2026b', seed: 9);
        h.store.values[_entKey] = Uint8List.fromList(
          utf8.encode(mintJws(other, entClaims(iatMs: t0))),
        );
        expect(await h.service.evaluate(), EntitlementPhase.free);
      },
    );

    test('FU-115: an empty (release) key set never grants Gold', () async {
      final h = Harness(boot: 1);
      final svc = EntitlementService(
        backend: h.backend,
        store: h.store,
        time: h.time,
        anchor: h.anchor,
        keys: ResponseSignatureVerifier(releaseEntitlementKeys),
        sink: h.sink,
      );
      h.store.values[_entKey] = Uint8List.fromList(
        utf8.encode(h.token(entClaims(iatMs: t0))),
      );
      expect(await svc.evaluate(), EntitlementPhase.free);
    });

    test('moved(user|support), paused and none map to their states', () async {
      for (final by in ['user', 'support']) {
        final h = Harness(boot: 1);
        await h.online(
          h.token(entClaims(iatMs: t0, status: 'moved', movedBy: by)),
        );
        expect(h.sink.last, EntitlementPhase.moved);
        expect(h.sink.movedBy, by == 'user' ? MovedBy.user : MovedBy.support);
      }
      final h = Harness(boot: 1);
      await h.online(h.token(entClaims(iatMs: t0, status: 'paused')));
      expect(h.sink.last, EntitlementPhase.paused);
      await h.clock.sample();
      h.clock.pass(minute);
      await h.online(
        h.token(entClaims(iatMs: t0 + minute, status: 'none', plan: 'none')),
      );
      expect(h.sink.last, EntitlementPhase.free);
    });

    test(
      'plan none and a whole-hour nextMoveAt parse (FU-116); off-hour dropped',
      () async {
        final h = Harness(boot: 1);
        await h.online(
          h.token(
            entClaims(
              iatMs: t0,
              status: 'moved',
              plan: 'none',
              nextMoveAt: '2026-12-01T10:00:00Z',
            ),
          ),
        );
        var c = await h.service.cachedClaims();
        expect(c!.plan, 'none');
        expect(c.nextMoveAt, DateTime.utc(2026, 12, 1, 10));
        h.clock.pass(minute);
        await h.online(
          h.token(
            entClaims(
              iatMs: t0 + minute,
              status: 'moved',
              nextMoveAt: '2026-12-01T10:30:00Z',
            ),
          ),
        );
        c = await h.service.cachedClaims();
        expect(c!.nextMoveAt, isNull);
      },
    );

    test('lifetime rule: exp beyond iat + 3 d is refused', () async {
      final h = Harness(boot: 1);
      await h.online(
        h.token(entClaims(iatMs: t0, expSec: t0 ~/ 1000 + 4 * 86400)),
      );
      expect(h.sink.last, EntitlementPhase.free);
      expect(_cached(h), isNull);
    });

    test('an older signed token never replaces a newer cached one', () async {
      final h = Harness(boot: 1);
      await h.online(h.token(entClaims(iatMs: t0, status: 'moved')));
      h.clock.pass(hour);
      final newer = h.token(entClaims(iatMs: t0 + hour));
      await h.online(newer);
      await h.online(h.token(entClaims(iatMs: t0, status: 'moved')));
      expect(_cached(h), newer);
    });

    test('5-day holder guarantee with one reboot', () async {
      final h = Harness(boot: 1);
      await h.online(h.token(entClaims(iatMs: t0)));
      for (var i = 0; i < 10; i++) {
        h.clock.pass(12 * hour);
        if (i == 3) h.clock.reboot(uptimeMs: 3 * minute);
        final p = await h.service.evaluate();
        expect(h.sink.last.name, anyOf('active', 'grace'), reason: '$i $p');
      }
    });
  });

  group('R5-1 install binding', () {
    test(
      'a signed token for another install, with this app\'s own fresh echo: '
      'no Gold, cache unchanged, hw/lb only raised, tampered kept, counter',
      () async {
        final h = Harness(boot: 1);
        final mine = h.token(entClaims(iatMs: t0));
        await h.online(mine);
        // Rollback => tampered.
        h.clock.pass(hour);
        h.clock.wall -= 2 * day;
        await h.service.evaluate();
        expect(h.sink.last, EntitlementPhase.tampered);
        final before = await h.state();
        final foreign = h.token(entClaims(sub: installB, iatMs: t0 + hour));
        await h.service.anchored(
          (n) async => EntitlementResponse(
            entitlement: Entitlement(token: foreign),
            serverTime: iso(t0 - day), // below hw: must not lower anything
            timeNonce: n.value,
          ),
          SignedBody.fromEntitlement,
        );
        final after = await h.state();
        expect(_cached(h), mine);
        expect(after.tampered, isTrue);
        expect(after.hw, greaterThanOrEqualTo(before.hw));
        expect(after.lb, greaterThanOrEqualTo(before.lb));
        expect(h.sink.last, isNot(EntitlementPhase.active));
        expect(h.sink.last, isNot(EntitlementPhase.grace));
        expect(
          h.diag.rows.where((r) => r.startsWith('ENTITLEMENT_SUB_MISMATCH')),
          hasLength(1),
        );
        // And with no cached token at all it grants nothing.
        final h2 = Harness(boot: 1);
        await h2.online(h2.token(entClaims(sub: installB, iatMs: t0)));
        expect(h2.sink.last, EntitlementPhase.free);
        expect(_cached(h2), isNull);
      },
    );

    test('an account token with a foreign iid is not stored and its acct '
        'purchase not granted; no re-anchor', () async {
      final h = Harness(boot: 1);
      final ent = h.token(entClaims(iatMs: t0, acct: 'acct-1'));
      final foreignAcct = h.token(
        acctClaims(sub: 'acct-1', iid: installB, iatMs: t0),
      );
      h.clock.pass(hour);
      h.clock.wall -= 2 * day;
      await h.service.evaluate(); // creates a tampered state
      await h.service.anchored(
        (n) async => SignInResponse(
          accountId: 'acct-1',
          accountToken: foreignAcct,
          entitlement: Entitlement(token: ent),
          linkedInstalls: 1,
          serverTime: iso(t0),
          timeNonce: n.value,
        ),
        SignedBody.fromSignIn,
      );
      expect(h.store.values[BackendStateKeys.accountToken], isNull);
      expect(h.sink.last, isNot(EntitlementPhase.active));
      expect((await h.state()).tampered, isTrue);
      expect(
        h.diag.rows.where((r) => r.startsWith('ACCOUNT_IID_MISMATCH')),
        hasLength(1),
      );
    });

    test(
      'an account-linked token is Gold only with a valid bound account token',
      () async {
        final h = Harness(boot: 1);
        final ent = h.token(entClaims(iatMs: t0, acct: 'acct-1'));
        final acct = h.token(acctClaims(sub: 'acct-1', iatMs: t0));
        await h.service.anchored(
          (n) async => SignInResponse(
            accountId: 'acct-1',
            accountToken: acct,
            entitlement: Entitlement(token: ent),
            linkedInstalls: 1,
            serverTime: iso(t0),
            timeNonce: n.value,
          ),
          SignedBody.fromSignIn,
        );
        expect(h.sink.last, EntitlementPhase.active);
        h.store.values.remove(BackendStateKeys.accountToken);
        expect(await h.service.evaluate(), EntitlementPhase.paused);
      },
    );

    test('after re-registration the old-install token is gone and a replayed '
        'old-sub body grants nothing', () async {
      final h = Harness(boot: 1);
      await h.service.start();
      final old = h.token(entClaims(iatMs: t0));
      await h.online(old);
      expect(h.sink.last, EntitlementPhase.active);
      // T-141: tokens deleted, new install ID, event.
      h.store.values.remove(_entKey);
      h.backend.id = installB;
      h.backend.ctl.add(const InstallReregistered());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(h.sink.last, EntitlementPhase.free);
      await h.online(old); // replay
      expect(h.sink.last, EntitlementPhase.free);
      expect(_cached(h), isNull);
      await h.service.stop();
    });
  });

  group('R4-2 time anchor', () {
    Future<Harness> tamperedWithToken() async {
      final h = Harness(boot: 1);
      await h.online(h.token(entClaims(iatMs: t0)));
      h.clock.pass(hour);
      h.clock.wall -= 2 * day;
      await h.service.evaluate();
      expect(h.sink.last, EntitlementPhase.tampered);
      return h;
    }

    test('a fresh echo recovers a rolled-back clock (Gold returns)', () async {
      final h = await tamperedWithToken();
      // The user fixes the clock (or NTP does), then the app anchors online.
      h.clock.wall += 2 * day;
      await h.online(h.token(entClaims(iatMs: t0 + hour)));
      expect((await h.state()).tampered, isFalse);
      expect(h.sink.last, EntitlementPhase.active);
    });

    test('another install\'s body: unknown nonce, S below hw: no lowering, tampered kept', () async {
      final h = await tamperedWithToken();
      final before = await h.state();
      await h.service.handleBody(
        SignedBody(
          serverTime: iso(t0 - 5 * day),
          timeNonce: 'AAAAAAAAAAAAAAAAAAAAAA',
        ),
      );
      final after = await h.state();
      expect(after.hw, greaterThanOrEqualTo(before.hw));
      expect(after.lb, greaterThanOrEqualTo(before.lb));
      expect(after.tampered, isTrue);
    });

    test(
      'NEGATIVE PROOF: a withheld own response (newer request sent, or > 60 s) '
      'only raises',
      () async {
        // Delivered after a newer request replaced pending.
        var h = await tamperedWithToken();
        late String firstNonce;
        await h.service.anchored((n) async {
          firstNonce = n.value;
          return EntitlementResponse(
            entitlement: Entitlement(token: h.token(entClaims(iatMs: t0))),
            serverTime: iso(t0),
            timeNonce: 'AAAAAAAAAAAAAAAAAAAAAA', // answer to something else
          );
        }, SignedBody.fromEntitlement);
        await h.service.anchored(
          (n) async => EntitlementResponse(
            entitlement: Entitlement(token: h.token(entClaims(iatMs: t0))),
            serverTime: iso(t0),
            timeNonce: 'BBBBBBBBBBBBBBBBBBBBBB',
          ),
          SignedBody.fromEntitlement,
        );
        await h.service.handleBody(
          SignedBody(serverTime: iso(t0), timeNonce: firstNonce),
        );
        expect((await h.state()).tampered, isTrue);

        // Delivered more than 60 s after sending.
        h = await tamperedWithToken();
        await h.service.anchored((n) async {
          h.clock.pass(61 * 1000);
          return EntitlementResponse(
            entitlement: Entitlement(token: h.token(entClaims(iatMs: t0))),
            serverTime: iso(t0),
            timeNonce: n.value,
          );
        }, SignedBody.fromEntitlement);
        expect((await h.state()).tampered, isTrue);
      },
    );

    test('a fresh echo used twice: the second time raises only', () async {
      final h = Harness(boot: 1);
      String? echoed;
      await h.online(
        h.token(entClaims(iatMs: t0)),
        echo: (n) => echoed = n.value,
      );
      h.clock.pass(hour);
      h.clock.wall -= 2 * day;
      await h.service.evaluate();
      expect((await h.state()).tampered, isTrue);
      await h.service.handleBody(
        SignedBody(serverTime: iso(t0), timeNonce: echoed),
      );
      expect((await h.state()).tampered, isTrue);
    });

    test(
      'an Idempotency-Key replay echoing an older nonce raises only',
      () async {
        final h = await tamperedWithToken();
        await h.online(
          h.token(entClaims(iatMs: t0)),
          echo: (n) => 'CCCCCCCCCCCCCCCCCCCCCC',
        );
        expect((await h.state()).tampered, isTrue);
      },
    );

    test('the nonce comes from the injected RNG, one is outstanding, and it is '
        'never stored or logged', () async {
      final rng = ScriptedRandom(List<int>.generate(16, (i) => i * 11 + 1));
      final h = Harness(boot: 1, random: rng);
      final expected = base64Url
          .encode(List<int>.generate(16, (i) => (i * 11 + 1) % 256))
          .replaceAll('=', '');
      String? seen;
      await h.service.anchored((n) async {
        seen = n.value;
        expect(h.anchor.hasPending, isTrue);
        return EntitlementResponse(
          entitlement: Entitlement(token: h.token(entClaims(iatMs: t0))),
          serverTime: iso(t0),
          timeNonce: n.value,
        );
      }, SignedBody.fromEntitlement);
      expect(seen, expected);
      expect(rng.calls, 16);
      expect(h.anchor.hasPending, isFalse); // consumed
      for (final v in h.store.values.values) {
        expect(utf8.decode(v, allowMalformed: true), isNot(contains(expected)));
      }
      expect(h.diag.rows.join(), isNot(contains(expected)));
    });

    test(
      'requests are serialized: the second starts after the first finished',
      () async {
        final h = Harness(boot: 1);
        final order = <String>[];
        Future<void> go(String id) async {
          await h.service.anchored((n) async {
            order.add('start $id');
            await Future<void>.delayed(const Duration(milliseconds: 5));
            order.add('end $id');
            return EntitlementResponse(
              entitlement: Entitlement(token: h.token(entClaims(iatMs: t0))),
              serverTime: iso(t0),
              timeNonce: n.value,
            );
          }, SignedBody.fromEntitlement);
        }

        await Future.wait([go('a'), go('b')]);
        expect(order, ['start a', 'end a', 'start b', 'end b']);
      },
    );
  });

  group('refresh, sign-out, notice', () {
    EntitlementResponse resp(Harness h, TimeNonce n, String token) =>
        EntitlementResponse(
          entitlement: Entitlement(token: token),
          serverTime: iso(h.clock.wall),
          timeNonce: n.value,
        );

    test('12 h refresh boundary', () async {
      final h = Harness(boot: 1);
      h.backend.onGet = (n) async =>
          resp(h, n, h.token(entClaims(iatMs: h.clock.wall)));
      expect(await h.service.refreshIfDue(), isFalse); // no token, no call
      await h.online(h.token(entClaims(iatMs: t0)));
      h.clock.pass(12 * hour - 1000);
      expect(await h.service.refreshIfDue(), isFalse);
      h.clock.pass(1000);
      expect(await h.service.refreshIfDue(), isTrue);
      expect(h.backend.gets, 1);
      expect(await h.service.refreshIfDue(), isFalse);
    });

    test('tampered state refreshes even when the token is young', () async {
      final h = Harness(boot: 1);
      await h.online(h.token(entClaims(iatMs: t0)));
      h.clock.pass(hour);
      h.clock.wall -= 2 * day;
      await h.service.evaluate();
      h.backend.onGet = (n) async =>
          resp(h, n, h.token(entClaims(iatMs: t0 + hour)));
      h.clock.wall += 2 * day; // the server time we will be told
      expect(await h.service.refreshIfDue(), isTrue);
    });

    test('a failed refresh leaves state untouched (unsigned/failed answer ignored)', () async {
      final h = Harness(boot: 1);
      await h.online(h.token(entClaims(iatMs: t0)));
      h.clock.pass(13 * hour);
      h.backend.onGet = (n) async =>
          throw BackendFailure(BackendFailureKind.badSignature);
      final before = await h.state();
      await expectLater(
        h.service.refreshIfDue(),
        throwsA(isA<BackendFailure>()),
      );
      final after = await h.state();
      expect(after.hw, greaterThanOrEqualTo(before.hw));
      expect(after.tampered, isFalse);
      expect(await h.service.evaluate(), EntitlementPhase.active);
      expect(await h.service.onResume(), isFalse);
    });

    test('sign-out drops the token at once even when the call fails; '
        'account-linked Gold then shows paused', () async {
      final h = Harness(boot: 1);
      await h.online(h.token(entClaims(iatMs: t0, acct: 'acct-1')));
      h.store.values[BackendStateKeys.accountToken] = Uint8List.fromList(
        utf8.encode(h.token(acctClaims(sub: 'acct-1', iatMs: t0))),
      );
      h.backend.onSignOut = (n) async =>
          throw BackendFailure(BackendFailureKind.offline);
      await expectLater(h.service.signOut(), throwsA(isA<BackendFailure>()));
      expect(_cached(h), isNull);
      expect(h.sink.last, EntitlementPhase.free);
      // Online: the 200 carries a paused token, stored after the binding check.
      h.backend.onSignOut = (n) async => resp(
        h,
        n,
        h.token(entClaims(iatMs: t0, status: 'paused', acct: 'acct-1')),
      );
      await h.service.signOut();
      expect(h.sink.last, EntitlementPhase.paused);
    });

    test('supportNotice survives a restart, is shown until dismissed, a repeat '
        'after dismissal is ignored, and a cleared notice resets', () async {
      final h = Harness(boot: 1);
      await h.online(
        h.token(entClaims(iatMs: t0)),
        notice: SupportNotice.goldLinkedBySupport,
      );
      // "App kill": a new service over the same store still has it.
      final h2 = Harness(boot: 1);
      h2.store.values.addAll(h.store.values);
      expect(await h2.service.hasPendingSupportNotice(), isTrue);
      await h2.service.dismissSupportNotice();
      expect(await h2.service.hasPendingSupportNotice(), isFalse);
      h2.clock.pass(minute);
      await h2.online(
        h2.token(entClaims(iatMs: t0 + minute)),
        notice: SupportNotice.goldLinkedBySupport,
      );
      expect(await h2.service.hasPendingSupportNotice(), isFalse);
      h2.clock.pass(minute);
      await h2.online(h2.token(entClaims(iatMs: t0 + 2 * minute)));
      h2.clock.pass(minute);
      await h2.online(
        h2.token(entClaims(iatMs: t0 + 3 * minute)),
        notice: SupportNotice.goldLinkedBySupport,
      );
      expect(await h2.service.hasPendingSupportNotice(), isTrue);
    });

    test('a notice that arrives with a rejected token is not stored', () async {
      final h = Harness(boot: 1);
      await h.online(
        h.token(entClaims(sub: installB, iatMs: t0)),
        notice: SupportNotice.goldLinkedBySupport,
      );
      expect(await h.service.hasPendingSupportNotice(), isFalse);
    });

    test(
      'start() shows pendingVerification while a cached token is checked',
      () async {
        final h = Harness(boot: 1);
        h.store.values[_entKey] = Uint8List.fromList(
          utf8.encode(h.token(entClaims(iatMs: t0))),
        );
        await h.service.start();
        expect(h.sink.phases.first, EntitlementPhase.pendingVerification);
        expect(h.sink.last, EntitlementPhase.active);
        await h.service.stop();
      },
    );
  });
}
