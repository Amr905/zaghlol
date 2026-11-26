// T-343: the Ask flow orchestrator (ask-llm.md section 1 and 6, ask-llm-ux.md
// section 1; FR-LLM-01/02/04/06/13/19/20/30/50/51).
//
// Design note (the state machine; also in docs/04-tasks/tasks/T-343.md):
//
//   too long (> 300) ─► TooLong                                  [no send]
//   local engine understands ─► Local                            [no send]
//   flag off / scrub failed / masker failed / no terms ─► Local(fallback)
//   scrub ─► mask ─ unresolved ─► Clarify                        [no send]
//   paused ─► Paused · quota 0 before resetsAt ─► QuotaOut ·
//   offline ─► Offline · no consent ─► prompter ─ declined ─►
//   ConsentDeclined                                              [no send]
//   Sending ─► gateway ─► Computing ─► phone validation (T-331) ─►
//   execute (T-342) ─► Answered(answer, sentText kept in memory only)
//   errors: 409 clears consent, prompts again once, then resends;
//   503 Paused; 403 QuotaOut; 422 attestation Failed(integrity) (iOS: one
//   retry with a new key first); 429 Failed(slowDown); 502/5xx, timeout
//   Failed(upstream/timeout); Stop Stopped. Nothing is queued for later.
//
// The one rule of the data boundary: the only user-derived bytes that leave
// are `MaskResult.sentText` (inside the gateway), the language, the consent
// terms and the gateway's own ids. `sentText` and the mask map live in local
// variables of one `ask` call and on the emitted [AskLlmAnswered]; nothing is
// stored or logged here. A plan that fails phone validation is never
// executed (the answer is PL-FALLBACK) and a template that failed the
// grammar is dropped.

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/backend/backend_client.dart'
    show AbortSignal, AskPlanResponse;
import '../../../core/llm/llm_consent.dart';
import '../../../core/llm/llm_feature.dart';
import '../../../core/llm/llm_gateway_client.dart';
import '../../../core/llm/llm_quota_snapshot.dart';
import '../data/llm_ask_client.dart';
import '../domain/ask_models.dart';
import '../domain/llm_answer_models.dart';

/// Longest question accepted (UX: Send enabled 1 to 300 characters).
const int askLlmMaxQuestionChars = 300;

/// The version of the consent sheet's text (FR-LLM-30); raising it asks
/// every user again.
const int askLlmConsentVersion = 1;

/// What the consent sheet (T-345) shows and decides.
final class ConsentPrompt {
  const ConsentPrompt({required this.sentText, required this.terms});

  /// Exactly what will be sent (`MaskResult.sentText`).
  final String sentText;
  final LlmTerms terms;

  @override
  String toString() => 'ConsentPrompt(<redacted>)';
}

/// Implemented by the consent sheet (T-345).
abstract interface class ConsentPrompter {
  /// True only for "Allow and send". Not now, drag and back are false. The
  /// flow stores the grant itself.
  Future<bool> prompt(ConsentPrompt request);
}

/// The fail-closed default until a sheet is installed.
final class DecliningConsentPrompter implements ConsentPrompter {
  const DecliningConsentPrompter();
  @override
  Future<bool> prompt(ConsentPrompt request) async => false;
}

enum AskLlmFailure { timeout, upstream, slowDown, integrity, rejected, unknown }

sealed class AskLlmState {
  const AskLlmState();
}

/// The on-phone engine answered (or the app's own fallback, never a send).
final class AskLlmLocal extends AskLlmState {
  const AskLlmLocal(this.answer);
  final AskAnswer answer;
}

/// More than [askLlmMaxQuestionChars] characters; nothing was sent.
final class AskLlmTooLong extends AskLlmState {
  const AskLlmTooLong();
}

/// A reference could not be resolved; chips of [unresolved] candidates.
final class AskLlmClarify extends AskLlmState {
  const AskLlmClarify(this.unresolved);
  final MaskUnresolved unresolved;
}

final class AskLlmConsentDeclined extends AskLlmState {
  const AskLlmConsentDeclined();
}

/// Quota at 0 before the reset; [quota] is the stored snapshot, if any.
final class AskLlmQuotaOut extends AskLlmState {
  const AskLlmQuotaOut(this.quota);
  final LlmQuotaSnapshot? quota;
}

final class AskLlmOffline extends AskLlmState {
  const AskLlmOffline();
}

final class AskLlmPaused extends AskLlmState {
  const AskLlmPaused();
}

final class AskLlmSending extends AskLlmState {
  const AskLlmSending();
}

final class AskLlmComputing extends AskLlmState {
  const AskLlmComputing();
}

final class AskLlmStopped extends AskLlmState {
  const AskLlmStopped();
}

final class AskLlmFailed extends AskLlmState {
  const AskLlmFailed(this.failure, {this.retryAfter});
  final AskLlmFailure failure;
  final Duration? retryAfter;
}

/// The answer. [sentText] is for "What I sent" on the in-memory message only.
final class AskLlmAnswered extends AskLlmState {
  const AskLlmAnswered({
    required this.answer,
    required this.sentText,
    required this.counted,
    this.template,
  });
  final LlmAnswer answer;
  final String sentText;
  final bool counted;

  /// A model template that passed the phone grammar; the filler (T-346) puts
  /// the phone's own numbers into it. Null when none or when dropped.
  final PlanTemplate? template;

  @override
  String toString() => 'AskLlmAnswered(<redacted>)';
}

/// The answer language of [question]: Arabic when it has an Arabic letter.
LlmLang askLang(String question) =>
    RegExp(r'[؀-ۿ]').hasMatch(question) ? LlmLang.ar : LlmLang.en;

class LlmAskFlow {
  LlmAskFlow({
    required this.local,
    required this.sources,
    required this.client,
    required this.execute,
    required this.consent,
    required this.quota,
    required this.prompter,
    required this.isFlagOn,
    required this.terms,
    required this.now,
    this.isOnline = _alwaysOnline,
    this.scrub = ClientScrub.apply,
    this.mask = ReferenceMasker.mask,
    this.validatorFor = _defaultValidator,
    this.primaryCurrency = 'EGP',
  });

  /// The on-phone engine (`AskEngine.ask`).
  final Future<AskAnswer> Function(String question) local;
  final Future<MaskSources> Function() sources;
  final LlmAskClient client;

  /// `PlanExecutor.execute`.
  final Future<LlmAnswer> Function(Plan plan, MaskMap map) execute;
  final LlmConsentStore consent;
  final LlmQuotaStore quota;
  final ConsentPrompter prompter;
  final bool Function() isFlagOn;

  /// The active provider and consent version; null when the provider isn't
  /// known yet (nothing is sent then).
  final LlmTerms? Function() terms;
  final DateTime Function() now;
  final Future<bool> Function() isOnline;
  final ScrubResult Function(String) scrub;
  final MaskOutcome Function(String, MaskSources) mask;
  final PlanValidator Function(MaskSources) validatorFor;
  final String primaryCurrency;

  static Future<bool> _alwaysOnline() async => true;
  static PlanValidator _defaultValidator(MaskSources s) =>
      PlanValidator(sources: s);

  /// Runs one question. [stop] is the user's Stop.
  Stream<AskLlmState> ask(String question, {AbortSignal? stop}) async* {
    if (question.runes.length > askLlmMaxQuestionChars) {
      yield const AskLlmTooLong();
      return;
    }
    final localAnswer = await local(question);
    if (localAnswer is! AskFallbackAnswer) {
      yield AskLlmLocal(localAnswer);
      return;
    }
    if (!isFlagOn()) {
      yield AskLlmLocal(localAnswer);
      return;
    }

    final ScrubResult scrubbed;
    final MaskSources src;
    final MaskOutcome outcome;
    try {
      scrubbed = scrub(question);
      if (scrubbed.failed) {
        yield AskLlmLocal(localAnswer);
        return;
      }
      src = await sources();
      outcome = mask(scrubbed.text, src);
    } on Object {
      // Typed outcome: the question stays on the phone.
      yield AskLlmLocal(localAnswer);
      return;
    }
    switch (outcome) {
      case MaskUnresolved(:final reason)
          when reason == MaskUnresolvedReason.failed:
        yield AskLlmLocal(localAnswer);
        return;
      case MaskUnresolved():
        yield AskLlmClarify(outcome);
        return;
      case MaskResult():
        break;
    }
    final masked = outcome;

    if (await quota.isPaused(LlmFeature.ask)) {
      yield const AskLlmPaused();
      return;
    }
    if (await quota.exhausted(LlmFeature.ask, now())) {
      yield AskLlmQuotaOut(await quota.current(LlmFeature.ask, now()));
      return;
    }
    if (!await isOnline()) {
      yield const AskLlmOffline();
      return;
    }
    var active = terms();
    if (active == null ||
        !LlmConsentGrant.validTerms(active.provider, active.v)) {
      yield AskLlmLocal(localAnswer);
      return;
    }
    if (await consent.grantFor(LlmFeature.ask, active.provider, active.v) ==
        null) {
      if (!await _ask(masked, active)) {
        yield const AskLlmConsentDeclined();
        return;
      }
    }

    final lang = askLang(question);
    var consentRetried = false;
    var keyRetried = false;
    AskPlanResponse? res;
    while (res == null) {
      if (stop?.aborted ?? false) {
        yield const AskLlmStopped();
        return;
      }
      yield const AskLlmSending();
      try {
        res = await client.plan(
          masked: masked,
          lang: lang,
          terms: active!,
          stop: stop,
          forceNewKey: keyRetried,
        );
      } on LlmConsentRequired catch (e) {
        final p = e.providerId;
        if (consentRetried) {
          yield const AskLlmConsentDeclined();
          return;
        }
        consentRetried = true;
        if (p != null && LlmConsentGrant.validTerms(p, active!.v)) {
          active = LlmTerms(provider: p, v: active.v);
        }
        if (!await _ask(masked, active!)) {
          yield const AskLlmConsentDeclined();
          return;
        }
      } on LlmAttestationFailed catch (e) {
        if (keyRetried || e.hadAttestationObject) {
          yield const AskLlmFailed(AskLlmFailure.integrity);
          return;
        }
        keyRetried = true;
      } on LlmGatewayException catch (e) {
        yield await _stateOf(e, localAnswer);
        return;
      } on Object {
        yield const AskLlmFailed(AskLlmFailure.unknown);
        return;
      }
    }
    if (stop?.aborted ?? false) {
      yield const AskLlmStopped();
      return;
    }

    yield const AskLlmComputing();
    final LlmAnswer answer;
    PlanTemplate? template;
    final validation = validatorFor(src).validate(
      askPlanEnvelope(res.plan),
      sent: masked.sentText,
      lang: lang.name,
      map: masked.map,
      primaryCurrency: primaryCurrency,
    );
    if (validation.rejected) {
      // Never executed: the app's own fallback, not a model answer.
      answer = const LlmFallbackAnswer(LlmFallbackReason.unsupported);
    } else {
      answer = await execute(validation.plan, masked.map);
      if (answer is! LlmFallbackAnswer &&
          answer is! LlmRefuseAnswer &&
          answer is! LlmNotFoundAnswer) {
        template = validation.template;
      }
    }
    yield AskLlmAnswered(
      answer: answer,
      sentText: masked.sentText,
      counted: res.counted,
      template: template,
    );
  }

  /// True when the user allowed; the grant is stored here.
  Future<bool> _ask(MaskResult masked, LlmTerms t) async {
    final ok = await prompter.prompt(
      ConsentPrompt(sentText: masked.sentText, terms: t),
    );
    if (!ok) return false;
    await consent.grant(LlmFeature.ask, t.provider, t.v);
    return true;
  }

  Future<AskLlmState> _stateOf(
    LlmGatewayException e,
    AskAnswer fallback,
  ) async => switch (e) {
    LlmBlocked(:final reason) => switch (reason) {
      LlmBlockReason.flagOff => AskLlmLocal(fallback),
      LlmBlockReason.paused => const AskLlmPaused(),
      LlmBlockReason.noConsent => const AskLlmConsentDeclined(),
      LlmBlockReason.quotaExhausted => AskLlmQuotaOut(
        await quota.current(LlmFeature.ask, now()),
      ),
    },
    LlmQuotaExhausted(:final quota) => AskLlmQuotaOut(quota),
    LlmServicePaused() => const AskLlmPaused(),
    LlmOffline() => const AskLlmOffline(),
    LlmCancelled() => const AskLlmStopped(),
    LlmTimeout() => const AskLlmFailed(AskLlmFailure.timeout),
    LlmRateLimited(:final retryAfter) => AskLlmFailed(
      AskLlmFailure.slowDown,
      retryAfter: retryAfter,
    ),
    LlmUpstreamUnavailable(:final retryAfter) => AskLlmFailed(
      AskLlmFailure.upstream,
      retryAfter: retryAfter,
    ),
    LlmAttestationFailed() ||
    LlmAttestationUnavailable() => const AskLlmFailed(AskLlmFailure.integrity),
    LlmRequestRejected() => const AskLlmFailed(AskLlmFailure.rejected),
    LlmConsentRequired() => const AskLlmConsentDeclined(),
  };
}
