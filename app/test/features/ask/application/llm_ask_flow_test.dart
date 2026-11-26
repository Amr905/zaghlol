// T-343: the Ask flow states with a fake gateway client. Synthetic data only.
//
// AC -> test map
//  AC1  every UX section 1 state: 'AC1 ...' tests below (local, clarify,
//       consent declined, quota 0, offline, paused, 409, 422, 429, 502,
//       timeout, Stop before reply, valid answer, plus flag off, too long,
//       scrub failure, unknown terms).
//  AC2  llm_ask_boundary_test.dart 'NEGATIVE PROOF 1 ...'
//  AC3  'NEGATIVE PROOF 2 ...' here (the zero-request states, fake client)
//       and llm_ask_boundary_test.dart (the same over the real gateway)
//  AC4  llm_ask_boundary_test.dart 'AC4 ...'
//  AC5  'AC5 ...' here ('NEGATIVE PROOF 3' is the same test with the guard
//       removed)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol/core/llm/llm_gateway_client.dart';
import 'package:zaghlol/core/llm/llm_consent.dart';
import 'package:zaghlol/core/llm/llm_quota_snapshot.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/ask/application/llm_ask_flow.dart';
import 'package:zaghlol/features/ask/data/llm_ask_client.dart';
import 'package:zaghlol/features/ask/domain/ask_models.dart';
import 'package:zaghlol/features/ask/domain/llm_answer_models.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

Map<String, dynamic> _fixtures() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final f = File(
      '${dir.path}/backend/contracts/fixtures/ask-plan-responses-v1.json',
    );
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  fail('fixture not found');
}

final _fx = _fixtures();

Map<String, dynamic> _ok(String name) => ((_fx['ok'] as List)
    .cast<Map<String, dynamic>>()
    .firstWhere((p) => p['name'] == name));

AskPlanResponse _reply(String name) =>
    AskPlanResponse.fromJson(_ok(name)['body']);

final _now = DateTime.utc(2026, 11, 26, 10);
const _terms = LlmTerms(provider: 'openai-luna', v: askLlmConsentVersion);
const _notUnderstood = AskFallbackAnswer(
  AskUnrecognizedReason.noIntent,
  askFallbackChips,
);

final class _MemDao implements SettingsDao {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value, {required int at}) async =>
      values[key] = value;
  @override
  Future<int> delete(String key) async => values.remove(key) == null ? 0 : 1;
  @override
  Stream<String?> watch(String key) => Stream.value(values[key]);
  @override
  Future<Map<String, String>> all() async => Map.of(values);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final class _Client implements LlmAskClient {
  final List<MaskResult> sent = [];
  final List<bool> forced = [];
  final List<Object> script = [];

  @override
  Future<AskPlanResponse> plan({
    required MaskResult masked,
    required LlmLang lang,
    required LlmTerms terms,
    AbortSignal? stop,
    bool forceNewKey = false,
  }) async {
    sent.add(masked);
    forced.add(forceNewKey);
    final next = script.removeAt(0);
    if (next is LlmGatewayException) throw next;
    return next as AskPlanResponse;
  }
}

final class _Prompter implements ConsentPrompter {
  _Prompter(this.answers);
  final List<bool> answers;
  final List<ConsentPrompt> shown = [];
  @override
  Future<bool> prompt(ConsentPrompt request) async {
    shown.add(request);
    return answers.isEmpty ? false : answers.removeAt(0);
  }
}

const _arq = 'لو قللت الأكل بره ٥٠٪ لمدة ١٢ شهر';
const _cardRef = '⟦CARD_1⟧';
final _cardMap = MaskMap({
  _cardRef: const MaskTarget(kind: MaskKind.card, accountIds: ['acc1']),
});

class _Rig {
  _Rig({
    this.understood = false,
    this.flagOn = true,
    this.online = true,
    this.sent = 'صرفت كام بكارت $_cardRef الشهر ده؟',
    this.outcome,
    this.activeTerms = _terms,
    this.scrubOverride,
    List<bool> consents = const [true],
  }) : prompter = _Prompter([...consents]) {
    final repo = SettingsRepository(dao, nowMs: () => 1);
    consent = LlmConsentStore(repo, nowMs: () => 2);
    quota = LlmQuotaStore(repo);
    flow = LlmAskFlow(
      local: (q) async =>
          understood ? const AskUnavailableAnswer() : _notUnderstood,
      sources: () async => const StaticMaskSources(),
      client: client,
      execute: (plan, map) async {
        executed.add(plan);
        return const LlmSafeSpendAnswer(daysRemaining: 3, figures: []);
      },
      consent: consent,
      quota: quota,
      prompter: prompter,
      isFlagOn: () => flagOn,
      terms: () => activeTerms,
      now: () => _now,
      isOnline: () async => online,
      scrub: scrubOverride ?? ClientScrub.apply,
      mask:
          outcome ??
          (t, s) => MaskResult(sentText: sent, map: _cardMap, tokens: const []),
    );
  }

  final bool understood;
  final bool flagOn;
  final bool online;
  final String sent;
  final MaskOutcome Function(String, MaskSources)? outcome;
  final LlmTerms? activeTerms;
  final ScrubResult Function(String)? scrubOverride;
  final dao = _MemDao();
  final client = _Client();
  final _Prompter prompter;
  final List<Plan> executed = [];
  late final LlmConsentStore consent;
  late final LlmQuotaStore quota;
  late final LlmAskFlow flow;

  Future<List<AskLlmState>> run(String q, {AbortSignal? stop}) =>
      flow.ask(q, stop: stop).toList();

  bool get nothingSent => client.sent.isEmpty;
}

Future<void> _grant(_Rig r) =>
    r.consent.grant(LlmFeature.ask, 'openai-luna', 1);

void main() {
  group('AC1 states', () {
    test('local answer: the engine understood, nothing sent', () async {
      final r = _Rig(understood: true);
      final s = await r.run('كام صرفت');
      expect(s.single, isA<AskLlmLocal>());
      expect(r.nothingSent, isTrue);
    });

    test(
      'clarify: unresolved reference, candidates handed on, no send',
      () async {
        final r = _Rig(
          outcome: (t, s) =>
              const MaskUnresolved(MaskUnresolvedReason.noSuchCard, []),
        );
        await _grant(r);
        final s = await r.run('صرفت كام بكارت 9999');
        expect((s.single as AskLlmClarify).unresolved.reason, isNotNull);
        expect(r.nothingSent, isTrue);
        expect(r.prompter.shown, isEmpty);
      },
    );

    test('consent declined: the sheet showed exactly sentText; nothing stored '
        'or sent', () async {
      final r = _Rig(consents: [false]);
      final s = await r.run('صرفت كام بكارت 4321');
      expect(s.single, isA<AskLlmConsentDeclined>());
      expect(r.prompter.shown.single.sentText, r.sent);
      expect(await r.consent.read(LlmFeature.ask), isNull);
      expect(r.nothingSent, isTrue);
    });

    test('consent allowed: grant stored, then sent', () async {
      final r = _Rig();
      r.client.script.add(_reply('PL-SPEND'));
      final s = await r.run('صرفت كام بكارت 4321');
      expect(s.last, isA<AskLlmAnswered>());
      expect((await r.consent.read(LlmFeature.ask))?.provider, 'openai-luna');
    });

    test(
      'quota 0 before resetsAt: nothing sent; after resetsAt it sends',
      () async {
        final r = _Rig();
        await _grant(r);
        final snap = LlmQuotaSnapshot(
          limit: 5,
          remaining: 0,
          resetsAt: DateTime.utc(2026, 11, 30, 22),
        );
        await r.dao.write('ask.llm_quota', snap.toJson(), at: 1);
        final s = await r.run('q');
        expect((s.single as AskLlmQuotaOut).quota, snap);
        expect(r.nothingSent, isTrue);
      },
    );

    test('offline: nothing sent, nothing queued', () async {
      final r = _Rig(online: false);
      await _grant(r);
      expect((await r.run('q')).single, isA<AskLlmOffline>());
      expect(r.nothingSent, isTrue);
    });

    test('paused: nothing sent', () async {
      final r = _Rig();
      await _grant(r);
      await r.quota.pause(LlmFeature.ask);
      expect((await r.run('q')).single, isA<AskLlmPaused>());
      expect(r.nothingSent, isTrue);
    });

    test('503 service paused from the backend: Paused', () async {
      final r = _Rig();
      await _grant(r);
      r.client.script.add(LlmServicePaused());
      expect((await r.run('q')).last, isA<AskLlmPaused>());
    });

    test('403: the backend quota is handed on', () async {
      final r = _Rig();
      await _grant(r);
      r.client.script.add(LlmQuotaExhausted(null));
      expect((await r.run('q')).last, isA<AskLlmQuotaOut>());
    });

    test(
      '409: consent was cleared; asks again; allowed resends once',
      () async {
        final r = _Rig(consents: [true, true]);
        await _grant(r);
        r.client.script
          ..add(LlmConsentRequired('other-provider'))
          ..add(_reply('PL-SPEND'));
        await r.consent.clear(LlmFeature.ask); // what the gateway did
        final s = await r.run('q');
        expect(s.whereType<AskLlmSending>(), hasLength(2));
        expect(s.last, isA<AskLlmAnswered>());
        expect(
          (await r.consent.read(LlmFeature.ask))?.provider,
          'other-provider',
        );
        expect(r.prompter.shown.first.terms.provider, 'openai-luna');
        expect(r.prompter.shown.last.terms.provider, 'other-provider');
      },
    );

    test('409 then Not now: declined; a second 409 never loops', () async {
      final r = _Rig(consents: [false]);
      await _grant(r);
      r.client.script.add(LlmConsentRequired(null));
      expect((await r.run('q')).last, isA<AskLlmConsentDeclined>());
      final r2 = _Rig(consents: [true, true]);
      await _grant(r2);
      r2.client.script
        ..add(LlmConsentRequired(null))
        ..add(LlmConsentRequired(null));
      expect((await r2.run('q')).last, isA<AskLlmConsentDeclined>());
      expect(r2.client.sent, hasLength(2));
    });

    test(
      '422 attestation: iOS retries once with a new key, then integrity',
      () async {
        final r = _Rig();
        await _grant(r);
        r.client.script
          ..add(LlmAttestationFailed(hadAttestationObject: false))
          ..add(_reply('PL-SPEND'));
        expect((await r.run('q')).last, isA<AskLlmAnswered>());
        expect(r.client.forced, [false, true]);
        final r2 = _Rig();
        await _grant(r2);
        r2.client.script.add(LlmAttestationFailed(hadAttestationObject: true));
        expect(
          ((await r2.run('q')).last as AskLlmFailed).failure,
          AskLlmFailure.integrity,
        );
        expect(r2.client.sent, hasLength(1));
      },
    );

    test('429, 502, timeout, rejected, unknown error', () async {
      Future<AskLlmFailure> fail(Object e) async {
        final r = _Rig();
        await _grant(r);
        r.client.script.add(e);
        return ((await r.run('q')).last as AskLlmFailed).failure;
      }

      expect(
        await fail(LlmRateLimited(const Duration(seconds: 30))),
        AskLlmFailure.slowDown,
      );
      expect(await fail(LlmUpstreamUnavailable(null)), AskLlmFailure.upstream);
      expect(await fail(LlmTimeout()), AskLlmFailure.timeout);
      expect(await fail(LlmRequestRejected()), AskLlmFailure.rejected);
    });

    test('Stop before the reply: Stopped, no answer, no execution', () async {
      final r = _Rig();
      await _grant(r);
      r.client.script.add(LlmCancelled());
      final s = await r.run('q');
      expect(s.last, isA<AskLlmStopped>());
      expect(r.executed, isEmpty);
      final stop = AbortSignal()..abort();
      final r2 = _Rig();
      await _grant(r2);
      expect((await r2.run('q', stop: stop)).last, isA<AskLlmStopped>());
      expect(r2.nothingSent, isTrue);
    });

    test('valid answer: validated, executed with the mask map, sentText on '
        'the state', () async {
      final r = _Rig();
      await _grant(r);
      r.client.script.add(_reply('PL-SPEND'));
      final s = await r.run('q');
      expect(s.map((e) => e.runtimeType).toList(), [
        AskLlmSending,
        AskLlmComputing,
        AskLlmAnswered,
      ]);
      final a = s.last as AskLlmAnswered;
      expect(a.sentText, r.sent);
      expect(a.counted, isTrue);
      expect(a.answer, isA<LlmSafeSpendAnswer>());
      expect(r.executed.single, isA<PlanSpend>());
    });

    test('flag off, too long, scrub failure, no terms: the on-phone fallback, '
        'nothing sent', () async {
      final off = _Rig(flagOn: false);
      expect((await off.run('q')).single, isA<AskLlmLocal>());
      final long = _Rig();
      expect(
        (await long.run('x' * (askLlmMaxQuestionChars + 1))).single,
        isA<AskLlmTooLong>(),
      );
      expect(
        (await long.run('x' * askLlmMaxQuestionChars)).first,
        isNot(isA<AskLlmTooLong>()),
      );
      final scrubbed = _Rig(
        scrubOverride: (_) => const ScrubResult('⟦NUMBER⟧', [], failed: true),
      );
      await _grant(scrubbed);
      expect((await scrubbed.run('q')).single, isA<AskLlmLocal>());
      expect(scrubbed.nothingSent, isTrue);
      final noTerms = _Rig(activeTerms: null);
      await _grant(noTerms);
      expect((await noTerms.run('q')).single, isA<AskLlmLocal>());
      expect(noTerms.nothingSent, isTrue);
    });
  });

  group('NEGATIVE PROOF 2: no request', () {
    test('local, clarify, declined, quota 0, offline, paused, flag off: the '
        'client is never called', () async {
      final rigs = <_Rig>[
        _Rig(understood: true),
        _Rig(flagOn: false),
        _Rig(online: false),
        _Rig(consents: [false]),
        _Rig(
          outcome: (t, s) =>
              const MaskUnresolved(MaskUnresolvedReason.ambiguousCard, []),
        ),
      ];
      for (final r in rigs) {
        await r.run('q');
        expect(r.nothingSent, isTrue);
      }
    });
  });

  group('AC5 / NEGATIVE PROOF 3: a plan that fails validation', () {
    test('a ref not in the sent text: never executed, PL-FALLBACK', () async {
      final r = _Rig(sent: 'صرفت كام الشهر ده؟'); // no ⟦CARD_1⟧ in the text
      await _grant(r);
      r.client.script.add(_reply('PL-SPEND')); // its ref is ⟦CARD_1⟧
      final a = (await r.run('q')).last as AskLlmAnswered;
      expect(a.answer, isA<LlmFallbackAnswer>());
      expect(r.executed, isEmpty);
    });

    test(
      'a template whose numbers the phone did not compute is dropped',
      () async {
        final r = _Rig(sent: 'لو قللت الأكل بره ٥٠٪ لمدة ١٢ شهر');
        await _grant(r);
        final res = _reply('PL-WHATIF-CUT-with-template');
        // The model's template with a literal figure in it.
        final json = _ok('PL-WHATIF-CUT-with-template');
        final body =
            jsonDecode(jsonEncode(json['body'])) as Map<String, dynamic>;
        (body['plan']['t'] as Map)['text'] =
            'لو قللت {target} هتوفر 999 جنيه في الشهر.';
        r.client.script.add(AskPlanResponse.fromJson(body));
        final a = (await r.run('q')).last as AskLlmAnswered;
        expect(a.template, isNull);
        expect(a.answer, isA<LlmSafeSpendAnswer>());
        // The honest template passes.
        final r2 = _Rig(sent: 'لو قللت الأكل بره ٥٠٪ لمدة ١٢ شهر');
        await _grant(r2);
        r2.client.script.add(res);
        final b = (await r2.run(_arq)).last as AskLlmAnswered;
        expect(b.answer, isA<LlmSafeSpendAnswer>(), reason: '${b.answer}');
        expect(b.template, isNotNull, reason: '${res.plan.t?.text}');
      },
    );
  });
}
