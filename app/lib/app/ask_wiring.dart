// T-347: wires the online helper's two seams in the root ProviderScope.
//
// - `consentPrompterProvider` -> the consent sheet (T-345) over S-50;
// - `llmAnswerViewBuilderProvider` -> the answer views (T-347).
//
// NOT wired here, on purpose (FU-425): `askConsentTermsProvider` keeps its
// default (null). The app has no source for the active provider id yet, so
// the consent sheet can't be allowed and nothing can be sent.

import 'package:flutter_riverpod/misc.dart' show Override;

import '../features/ask/data/llm_ask_providers.dart';
import '../features/ask/presentation/llm_answer_views.dart';
import '../features/ask/presentation/llm_ask_ui.dart';

final List<Override> askLlmWiringOverrides = [
  consentPrompterProvider.overrideWith(
    (ref) => ref.watch(sheetConsentPrompterProvider),
  ),
  llmAnswerViewBuilderProvider.overrideWithValue(buildLlmAnswerView),
];
