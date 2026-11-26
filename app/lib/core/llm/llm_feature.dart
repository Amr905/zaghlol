// T-340: the two features that use the LLM gateway (ask-llm §5, §6;
// llm-categorise §3, §7). Shared code keys everything off this enum, so it
// holds no Ask- or categorise-specific behaviour, only names.

import '../flags/feature_flags.dart';

enum LlmFeature {
  /// The online helper (`POST /v1/ask/plan`).
  ask(
    settingsPrefix: 'ask',
    flag: FeatureFlag.askLlm,
    bindingPrefix: 'zaghlol-ask-v1',
    clientDataPrefix: 'zaghlol-ask-attest-v1',
  ),

  /// Automatic category for unknown merchants (`POST /v1/categorise`).
  categorise(
    settingsPrefix: 'cat',
    flag: FeatureFlag.llmCategorise,
    bindingPrefix: 'zaghlol-cat-v1',
    clientDataPrefix: 'zaghlol-cat-attest-v1',
  );

  const LlmFeature({
    required this.settingsPrefix,
    required this.flag,
    required this.bindingPrefix,
    required this.clientDataPrefix,
  });

  /// `ask` / `cat`: the prefix of the feature's encrypted settings keys.
  final String settingsPrefix;

  /// The remote kill switch; fail closed (stale or never synced = OFF).
  final FeatureFlag flag;

  /// The body-binding prefix (`bodyHash`, ask-llm §5).
  final String bindingPrefix;

  /// The App Attest `clientDataHash` prefix (ask-llm §5; T-322 vectors).
  final String clientDataPrefix;
}
