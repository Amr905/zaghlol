// T-343: the Ask flow's port to the gateway. The only way a question can
// leave the phone is `plan(masked:)`, whose input type is `MaskResult`: the
// gateway builds the request from `masked.sentText` and nothing else the
// user typed (llm_gateway_client.dart). A fake of this port is how the flow
// tests run without a network.

import 'package:zaghlol_parsing/zaghlol_parsing.dart' show MaskResult;

import '../../../core/backend/backend_client.dart';
import '../../../core/llm/llm_gateway_client.dart';

abstract interface class LlmAskClient {
  /// `POST /v1/ask/plan`. Throws an [LlmGatewayException].
  Future<AskPlanResponse> plan({
    required MaskResult masked,
    required LlmLang lang,
    required LlmTerms terms,
    AbortSignal? stop,
    bool forceNewKey = false,
  });
}

final class GatewayLlmAskClient implements LlmAskClient {
  GatewayLlmAskClient(this._gateway);

  final LlmGatewayClient _gateway;

  @override
  Future<AskPlanResponse> plan({
    required MaskResult masked,
    required LlmLang lang,
    required LlmTerms terms,
    AbortSignal? stop,
    bool forceNewKey = false,
  }) => _gateway.askPlan(
    masked: masked,
    lang: lang,
    terms: terms,
    stop: stop,
    forceNewKey: forceNewKey,
  );
}

/// The reply's plan as the JSON map `PlanValidator.validate` takes (the same
/// shape the backend validated).
Map<String, Object?> askPlanEnvelope(AskPlan plan) => {
  'v': plan.v,
  'plan': plan.plan.wire,
  'p': plan.p,
  't': plan.t == null ? null : {'lang': plan.t!.lang, 'text': plan.t!.text},
};
