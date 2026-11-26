// T-346: the presentation seams of the online helper on S-50.
//
// Assembly seams (the Lead wires these in the app root, T-348):
//   1. `consentPrompterProvider.overrideWith(
//        (ref) => ref.watch(sheetConsentPrompterProvider))`
//      so the flow shows the consent sheet (T-345) over S-50;
//   2. `askConsentTermsProvider` (consent_sheet.dart) from remote config and
//      the tier, or the sheet cannot be allowed;
//   3. `llmAnswerViewBuilderProvider` -> the real answer views once the
//      template filler (T-344) and the views (T-347) land. Until then the
//      default shows the app's own fallback text and never a number.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import '../application/llm_ask_flow.dart';
import '../domain/llm_answer_models.dart';
import 'consent_sheet.dart';
import 'sent_text_parser.dart';

/// Draws the body of one online-helper answer. T-347 supplies the real views.
typedef LlmAnswerViewBuilder = Widget Function(
  BuildContext context,
  AskLlmAnswered answered,
);

/// SEAM (T-344/T-347): the default is plain text and carries no figure.
final llmAnswerViewBuilderProvider = Provider<LlmAnswerViewBuilder>(
  (ref) =>
      (context, answered) => Text(
        AppLocalizations.of(context).chatFallbackText,
        style: ZType.body,
      ),
  name: 'llmAnswerViewBuilderProvider',
);

/// The pose of the avatar for [a] (ux table): `proud` for what-ifs and for
/// "nothing to trim", `professor` for investment, `tourGuide` otherwise.
ZaghlolMoment llmAnswerMood(LlmAnswer a) => switch (a) {
  LlmWhatIfAnswer() || LlmWhatIfSaveAnswer() => ZaghlolMoment.proud,
  LlmSuggestAnswer(:final perCurrency) =>
    perCurrency.every((c) => c.suggestions.isEmpty)
        ? ZaghlolMoment.proud
        : ZaghlolMoment.tourGuide,
  LlmInvestAnswer() => ZaghlolMoment.professor,
  _ => ZaghlolMoment.tourGuide,
};

/// The mounted S-50 registers itself here so the consent sheet (asked by the
/// flow, which has no context) opens over the chat. Not state: nothing
/// rebuilds from it.
final class AskConsentHost {
  BuildContext? context;
  WidgetRef? ref;
}

final askConsentHostProvider = Provider<AskConsentHost>(
  (ref) => AskConsentHost(),
  name: 'askConsentHostProvider',
);

/// The flow's [ConsentPrompter] backed by the T-345 sheet. Declines when no
/// S-50 is on screen.
final class SheetConsentPrompter implements ConsentPrompter {
  SheetConsentPrompter(this._host);
  final AskConsentHost _host;

  @override
  Future<bool> prompt(ConsentPrompt request) async {
    final context = _host.context;
    final ref = _host.ref;
    if (context == null || ref == null || !context.mounted) return false;
    return AskConsentFlow.prompt(
      context,
      ref,
      preview: parseSentText(request.sentText),
      expect: request.terms,
    );
  }
}

final sheetConsentPrompterProvider = Provider<ConsentPrompter>(
  (ref) => SheetConsentPrompter(ref.watch(askConsentHostProvider)),
  name: 'sheetConsentPrompterProvider',
);
