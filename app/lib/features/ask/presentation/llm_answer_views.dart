// T-347: the answer views of the online helper on S-50 (ask-llm-ux §1.2).
//
// Every figure comes from `TemplateFiller` (T-344), which puts the phone's own
// numbers into app-owned text (or a model template that passed the grammar).
// This file only lays the filled lines out: per-currency lines (never summed),
// what-if captions, suggestion rows, the investment rows with the always
// visible disclaimer block, refusal / fallback / not-found chips and the
// footer ("Online helper" badge + "What I sent").
//
// - Spending and amounts are plain ink, never red.
// - Hide amounts (D-67): the filler masks amounts and grams; the screen
//   reader says "Amount hidden" / "Weight hidden" (a11y label below).
// - A price the feed doesn't have is not guessed: the filler leaves that
//   instrument row out (FU-426).
// - Chips that start a known plan run on the phone (no request, no quota).
//
// Seam: the Lead's `askLlmWiringOverrides` (lib/app/ask_wiring.dart) points
// `llmAnswerViewBuilderProvider` at [buildLlmAnswerView].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/flags/feature_flags.dart';
import '../../../core/flags/flags_providers.dart';
import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart' show kAmountMask;
import '../../../core/routing/app_routes.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/amount_semantics.dart';
import '../../budget/application/budget_providers.dart'
    show paydayScheduleProvider, todayProvider;
import '../../insights/domain/chart_models.dart';
import '../application/llm_ask_flow.dart';
import '../application/template_filler.dart';
import '../data/llm_ask_providers.dart';
import '../domain/llm_answer_models.dart';
import 'ask_chat_controller.dart';
import 'ask_screen.dart' show askCategoryNamesProvider, askChipLabel;
import 'consent_sheet.dart';
import 'sent_disclosure.dart';
import 'sent_text_parser.dart';

/// The seam's builder.
Widget buildLlmAnswerView(BuildContext context, AskLlmAnswered answered) =>
    LlmAnswerView(answered: answered);

/// The plan's what-if mode (the answer models don't carry it). Null: the cut
/// percent is derived from the figures.
WhatIfMode? whatIfModeOf(Plan? plan) {
  final PlanWhatIfCut? cut = switch (plan) {
    PlanWhatIfCut() => plan,
    PlanInvest(:final source) => source.whatIf,
    _ => null,
  };
  if (cut == null) return null;
  final m = cut.mode;
  if (m.kind == WhatIfKind.percent) {
    final pct = m.percent;
    return pct == null ? null : WhatIfPercent(pct);
  }
  final c = Currency.tryOf(m.currency ?? 'EGP');
  final amount = m.amount;
  if (c == null || amount == null) return null;
  final minor = planAmountToMinor(amount, c.exponent);
  return minor == null ? null : WhatIfAmount(Money(c, minor));
}

InvestLeadState investStateOf(Plan? plan) => switch (plan) {
  PlanInvest(:final source) => switch (source.kind) {
    InvestSourceKind.savedLastPeriod => InvestLeadState.saved,
    InvestSourceKind.whatIf => InvestLeadState.whatIf,
    InvestSourceKind.amount => InvestLeadState.other,
  },
  _ => InvestLeadState.saved,
};

/// The plan that "If I had saved?" runs (PL-INVEST savedLastPeriod).
const Plan investSavedPlan = PlanInvest(
  PlanInvestSource(InvestSourceKind.savedLastPeriod),
  [Instrument.gold, Instrument.usd, Instrument.certificate],
  12,
);

/// The plan that "Help me save" runs (PL-SUGGEST).
const Plan suggestPlan = PlanSuggest(null);

class LlmAnswerView extends ConsumerWidget {
  const LlmAnswerView({super.key, required this.answered});
  final AskLlmAnswered answered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final answer = answered.answer;
    final names = ref.watch(askCategoryNamesProvider).value ?? const {};
    final categoryNames = {
      for (final e in names.entries)
        e.key: lang == 'ar' ? e.value.ar : e.value.en,
    };
    final today = ref.watch(todayProvider);
    final schedule = ref.watch(paydayScheduleProvider).value;
    final prices = answer is LlmInvestAnswer
        ? ref.watch(askInvestPricesProvider).value
        : null;

    String span(ChartPeriod p) {
      String date(CivilDate d) => ZDateFormat.date(
        DateTime(d.year, d.month, d.day),
        lang,
        ref.read(digitsModeProvider(lang)),
      );
      if (schedule != null) {
        final cur = schedule.cycleOn(today);
        if (p == ChartPeriod.cycle(cur)) return l.chatPeriodThisMonth;
        if (p == ChartPeriod.cycle(schedule.before(cur))) {
          return l.chatPeriodLastMonth;
        }
      }
      if (p == ChartPeriod.month(today.year, today.month)) {
        return l.chatPeriodThisMonth;
      }
      final prev = today.month == 1
          ? ChartPeriod.month(today.year - 1, 12)
          : ChartPeriod.month(today.year, today.month - 1);
      if (p == prev) return l.chatPeriodLastMonth;
      return l.chatPeriodRange(date(p.from), date(p.to));
    }

    String subject(LlmTarget t) {
      final label = t.label ?? categoryNames[t.categoryId];
      return label ?? l.budgetEditOverall;
    }

    final filler = TemplateFiller(
      l: l,
      languageCode: lang,
      digits: ref.watch(digitsModeProvider(lang)),
      hidden: ref.watch(hideAmountsProvider),
      today: today,
      spanLabel: span,
      subjectLabel: subject,
      prices: prices,
    );
    final lines = filler
        .fill(
          answer,
          template: answered.template,
          whatIfMode: whatIfModeOf(answered.plan),
          investState: investStateOf(answered.plan),
        )
        .lines;

    final body = switch (answer) {
      LlmInvestAnswer() => _InvestBody(lines: lines),
      LlmWhatIfAnswer() => _WhatIfBody(lines: lines, answer: answer),
      LlmSuggestAnswer() => _SuggestBody(lines: lines),
      _ => _PlainLines(lines: lines),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          label: _a11y(l, lines),
          excludeSemantics: true,
          child: body,
        ),
        if (_opensTransactions(answer) && GoRouter.maybeOf(context) != null)
          _OpenTransactions(
            onTap: () => GoRouter.of(context).push(AppRoutes.transactions),
          ),
        _Chips(answer: answer, plan: answered.plan),
        _Footer(answered: answered),
      ],
    );
  }
}

bool _opensTransactions(LlmAnswer a) =>
    a is LlmDataAnswer ||
    a is LlmCompareAnswer ||
    a is LlmTopNAnswer ||
    a is LlmBreakdownAnswer;

/// The screen-reader text of a bubble: masked amounts and hidden grams are
/// announced as words.
String _a11y(AppLocalizations l, List<String> lines) {
  var text = lines.join(' ');
  text = text.replaceAll(
    l.commonUnitGrams(kAmountMask),
    l.chatInvestGramsHiddenA11y,
  );
  return a11yAmounts(l, l.chatMainZaghlolA11y(text));
}

// ----------------------------------------------------------------- bodies

class _PlainLines extends StatelessWidget {
  const _PlainLines({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < lines.length; i++)
        Padding(
          padding: EdgeInsetsDirectional.only(top: i == 0 ? 0 : ZSpacing.sm),
          child: Text(lines[i], style: ZType.body),
        ),
    ],
  );
}

class _WhatIfBody extends StatelessWidget {
  const _WhatIfBody({required this.lines, required this.answer});
  final List<String> lines;
  final LlmWhatIfAnswer answer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    // A body line opens each currency block: the first line, or one led by
    // "In EGP:" when there are several. The rest are captions (basis, capped).
    final leads = {
      for (final o in answer.outcomes)
        l.chatAnswerCurrencyLead(o.currency.code),
    };
    final multi = answer.outcomes.length > 1;
    bool isBody(int i) =>
        i == 0 || (multi && leads.any((lead) => lines[i].startsWith(lead)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(
              top: i == 0 ? 0 : (isBody(i) ? ZSpacing.md : ZSpacing.xs),
            ),
            child: isBody(i)
                ? Text(lines[i], style: ZType.body)
                : Text(
                    lines[i],
                    style: ZType.caption.copyWith(color: c.textMuted),
                  ),
          ),
      ],
    );
  }
}

class _SuggestBody extends StatelessWidget {
  const _SuggestBody({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    if (lines.length < 3) return _PlainLines(lines: lines);
    final footer = lines.last == l.chatSuggestFooter;
    final rows = lines.sublist(1, footer ? lines.length - 1 : lines.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(lines.first, style: ZType.body),
        for (final row in rows)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.primaryContainer,
                    borderRadius: BorderRadius.circular(ZRadius.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(ZSpacing.sm),
                    child: Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: c.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: ZSpacing.sm),
                Expanded(child: Text(row, style: ZType.body)),
              ],
            ),
          ),
        if (footer)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Text(
              lines.last,
              style: ZType.caption.copyWith(color: c.textMuted),
            ),
          ),
      ],
    );
  }
}

class _InvestBody extends StatelessWidget {
  const _InvestBody({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final hasDisclaimer =
        lines.length >= 2 &&
        lines.last == l.chatInvestDisclaimer &&
        lines[lines.length - 2] == l.chatInvestDisclaimerSummary;
    final shown = hasDisclaimer ? lines.sublist(0, lines.length - 2) : lines;
    final stale = ' ${l.commonBadgeStale}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(top: i == 0 ? 0 : ZSpacing.sm),
            child: shown[i].endsWith(stale)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shown[i].substring(0, shown[i].length - stale.length),
                        style: ZType.body,
                      ),
                      const SizedBox(height: ZSpacing.xs),
                      _Pill(text: l.commonBadgeStale, warning: true),
                    ],
                  )
                : Text(shown[i], style: ZType.body),
          ),
        if (hasDisclaimer)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
            child: DecoratedBox(
              key: const ValueKey('invest-disclaimer'),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(ZRadius.md),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(ZSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: c.text),
                    const SizedBox(width: ZSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.chatInvestDisclaimerSummary,
                            style: ZType.body.copyWith(color: c.text),
                          ),
                          const SizedBox(height: ZSpacing.xs),
                          Text(
                            l.chatInvestDisclaimer,
                            style: ZType.caption.copyWith(color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ pieces

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text, this.icon, this.warning = false});
  final String text;
  final IconData? icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final fg = warning ? c.warningText : c.onPrimaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning ? c.warningBg : c.primaryContainer,
        borderRadius: BorderRadius.circular(ZRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.sm,
          vertical: ZSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: ZSpacing.xs),
            ],
            Flexible(
              child: Text(text, style: ZType.caption.copyWith(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenTransactions extends StatelessWidget {
  const _OpenTransactions({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        key: const ValueKey('ask-open-transactions'),
        style: TextButton.styleFrom(
          foregroundColor: ZColors.of(context).primary,
          minimumSize: const Size(ZSpacing.minTarget, ZSpacing.minTarget),
        ),
        onPressed: onTap,
        child: Text(l.chatMainOpenTransactions),
      ),
    );
  }
}

/// Local chips under a bubble. Each runs on the phone: no request, no quota.
class _Chips extends ConsumerWidget {
  const _Chips({required this.answer, required this.plan});
  final LlmAnswer answer;
  final Plan? plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final chat = ref.read(askChatProvider.notifier);
    final busy = ref.watch(askChatProvider.select((s) => s.thinking));
    final investOn = ref.watch(featureFlagProvider(FeatureFlag.askLlmInvest));
    final chips = <(Key, String, VoidCallback)>[];

    void local(AskChip chip) {
      final label = askChipLabel(l, chip);
      chips.add((ValueKey(chip), label, () => chat.sendChip(chip, label)));
    }

    void suggest() => chips.add((
      const ValueKey('invest-suggest-chip'),
      l.chatInvestSuggestChip,
      () => chat.runLocalPlan(l.chatInvestSuggestChip, suggestPlan),
    ));

    switch (answer) {
      case LlmInvestAnswer(:final figures):
        final thin = figures.any(
          (f) =>
              f.illustration.band == InvestBand.nothingSaved ||
              f.illustration.band == InvestBand.small,
        );
        if (thin) suggest();
      case LlmRefuseAnswer(:final reason):
        switch (reason) {
          case RefuseReason.specificPick:
            if (investOn) {
              chips.add((
                const ValueKey('invest-chip'),
                l.chatInvestChip,
                () => chat.runLocalPlan(l.chatInvestChip, investSavedPlan),
              ));
            }
          case RefuseReason.offTopic:
            local(AskChip.spendThisMonth);
            local(AskChip.topMerchants);
            local(AskChip.upcomingDues);
          case RefuseReason.unsafe:
            break;
        }
      case LlmFallbackAnswer():
        local(AskChip.spendThisMonth);
        local(AskChip.topMerchants);
        local(AskChip.upcomingDues);
      case LlmNotFoundAnswer(chips: final found):
        for (final chip in found) {
          chips.add((
            ValueKey(chip),
            chip.label,
            () => chat.runLocalPlan(
              chip.label,
              PlanSpend(
                const PlanPeriod(kind: PeriodKind.month, offset: 0),
                PlanFilter(mention: chip.label),
              ),
            ),
          ));
        }
      default:
        break;
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
      child: Wrap(
        spacing: ZSpacing.sm,
        runSpacing: ZSpacing.xs,
        children: [
          for (final (key, label, onTap) in chips)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
              child: ActionChip(
                key: key,
                label: Text(label),
                onPressed: busy ? null : onTap,
              ),
            ),
        ],
      ),
    );
  }
}

/// The footer: the "Online helper" badge and "What I sent" (D-92). A bubble
/// that never left the phone says so instead.
class _Footer extends ConsumerWidget {
  const _Footer({required this.answered});
  final AskLlmAnswered answered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sent = answered.sentText.isNotEmpty;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sent) ...[
            Semantics(
              label: l.chatSentBadgeA11y,
              excludeSemantics: true,
              child: _Pill(
                key: const ValueKey('sent-badge'),
                text: l.chatSentBadge,
                icon: Icons.cloud_outlined,
              ),
            ),
            SentDisclosure(
              segments: parseSentText(answered.sentText),
              providerName:
                  ref.watch(askConsentTermsProvider)?.providerName ?? '',
            ),
          ] else
            Text(
              l.chatSentLocal,
              key: const ValueKey('sent-local'),
              style: ZType.caption.copyWith(
                color: ZColors.of(context).textMuted,
              ),
            ),
        ],
      ),
    );
  }
}
