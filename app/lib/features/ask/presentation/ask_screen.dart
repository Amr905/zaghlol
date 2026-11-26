// T-111: S-50 Ask Zaghlol. Chat bubbles, suggestion chips, mini bar charts,
// roast toggle and a thinking moment. Answers come from `askEngineProvider`
// (T-110) through [askChatProvider]; the widgets never touch the database.
// Lives on the Zaghlol tab (override `TabRoots.zaghlol` with `AskScreen`).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/config/remote_config_providers.dart';
import '../../../core/flags/feature_flags.dart';
import '../../../core/flags/flags_providers.dart';
import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/llm/llm_quota_snapshot.dart';
import '../../../core/theme/z_tokens.dart';
import '../../budget/application/budget_providers.dart'
    show paydayScheduleProvider, todayProvider;
import '../../budget/presentation/budget_providers_ui.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import '../../gold/application/gating.dart';
import '../application/llm_ask_flow.dart';
import '../data/llm_ask_providers.dart';
import '../domain/ask_models.dart';
import '../../settings/presentation/privacy_ask_llm_section.dart'
    show askQuotaStateProvider;
import 'ask_answer_text.dart';
import 'ask_chat_controller.dart';
import 'llm_ask_ui.dart';

import '../../../core/settings/settings_providers.dart';
import '../../../core/ui/amount_semantics.dart';

part 'ask_screen_llm.dart';

/// The category id to localized name map the answers need.
final askCategoryNamesProvider =
    FutureProvider<Map<String, ({String ar, String en})>>((ref) async {
      final rows = await ref.watch(categoryRowsProvider.future);
      return {for (final c in rows) c.id: (ar: c.nameAr, en: c.nameEn)};
    }, name: 'askCategoryNamesProvider');

enum _Menu { clear }

class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final AskConsentHost _host = ref.read(askConsentHostProvider);

  @override
  void dispose() {
    if (_host.context == context) {
      _host
        ..context = null
        ..ref = null;
    }
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: ZMotion.standard,
        curve: ZMotion.curve,
      );
    });
  }

  void _pick(String label, String? question) {
    final q = (question ?? _text.text).trim();
    final next = q.isEmpty ? label : '$q $label';
    _text.text = next.runes.length <= askLlmMaxQuestionChars ? next : label;
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  Future<void> _send() async {
    final sent = await ref.read(askChatProvider.notifier).sendText(_text.text);
    if (sent) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final chat = ref.watch(askChatProvider);
    _host
      ..context = context
      ..ref = ref;
    ref.listen(askChatProvider, (prev, next) {
      if (prev != null && prev.stoppedCount != next.stoppedCount) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.chatLlmStatusStopped)));
      }
      if (prev?.messages.length != next.messages.length ||
          prev?.thinking != next.thinking) {
        _toEnd();
      }
    });

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                ZSpacing.screen,
                ZSpacing.sm,
                ZSpacing.screen,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l.chatMainTitle,
                        style: ZType.display.copyWith(color: c.text),
                      ),
                    ),
                  ),
                  PopupMenuButton<_Menu>(
                    tooltip: l.chatMainClear,
                    onSelected: (_) {
                      ref.read(askChatProvider.notifier).clear();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.chatMainCleared)),
                      );
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _Menu.clear,
                        child: Text(l.chatMainClear),
                      ),
                    ],
                    child: const SizedBox.square(
                      dimension: ZSpacing.minTarget,
                      child: Center(child: _Disc(icon: Icons.more_horiz)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
                children: [
                  if (chat.messages.isEmpty)
                    _Bubble(
                      fromUser: false,
                      mood: chat.thinking
                          ? ZaghlolMoment.thinking
                          : ZaghlolMoment.tourGuide,
                      talk: chat.thinking,
                      semanticsLabel: l.chatMainZaghlolA11y(l.chatMainGreeting),
                      child: Text(l.chatMainGreeting),
                    ),
                  for (final m in chat.messages)
                    _MessageView(message: m, onPick: _pick),
                  if (chat.thinking) _TypingBubble(phase: chat.phase),
                ],
              ),
            ),
            _Chips(chat: chat),
            _InputRow(controller: _text, onSend: _send, roast: chat.roast),
          ],
        ),
      ),
    );
  }
}

/// 40 dp white disc used for round top-bar actions.
class _Disc extends StatelessWidget {
  const _Disc({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.surface,
        border: c.flatBorder,
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, size: 20, color: c.text),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.fromUser,
    required this.child,
    this.semanticsLabel,
    this.mood = ZaghlolMoment.tourGuide,
    this.talk = false,
    this.tag,
    this.liveRegion = false,
    this.actions,
  });
  final bool fromUser;
  final Widget child;

  /// Null: the child supplies its own semantics.
  final String? semanticsLabel;
  final ZaghlolMoment mood;
  final bool talk;

  /// Announce the bubble politely when it appears (status changes, T-346).
  final bool liveRegion;

  /// Buttons under the bubble (outside its merged semantics node).
  final Widget? actions;

  /// Small label above a Zaghlol bubble (roast mode).
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final width = MediaQuery.sizeOf(context).width;
    const avatar = 56.0;
    final bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: fromUser ? c.primary : c.zaghlolBg,
        borderRadius: BorderRadiusDirectional.only(
          topStart: const Radius.circular(ZRadius.card),
          topEnd: const Radius.circular(ZRadius.card),
          bottomStart: Radius.circular(fromUser ? ZRadius.card : ZRadius.sm),
          bottomEnd: Radius.circular(fromUser ? ZRadius.sm : ZRadius.card),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
        child: DefaultTextStyle.merge(
          style: ZType.body.copyWith(
            color: fromUser ? c.onPrimary : c.zaghlolText,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tag != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: ZSpacing.sm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 16,
                        color: c.warningText,
                      ),
                      const SizedBox(width: ZSpacing.xs),
                      Text(
                        tag!,
                        style: ZType.label.copyWith(color: c.warningText),
                      ),
                    ],
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
      child: fromUser
          ? Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width * 0.78),
                child: Semantics(
                  container: true,
                  label: semanticsLabel,
                  excludeSemantics: semanticsLabel != null,
                  child: bubble,
                ),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: ZSpacing.sm),
                  child: ZaghlolAvatar(moment: mood, talk: talk, size: avatar),
                ),
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width * 0.78),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          container: true,
                          liveRegion: liveRegion,
                          label: semanticsLabel,
                          excludeSemantics: semanticsLabel != null,
                          child: bubble,
                        ),
                        ?actions,
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MessageView extends ConsumerWidget {
  const _MessageView({required this.message, required this.onPick});
  final AskMessage message;
  final void Function(String label, String? question) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (message.llm != null) {
      return _LlmMessageView(message: message, onPick: onPick);
    }
    if (message.fromUser) {
      return _Bubble(
        fromUser: true,
        semanticsLabel: l.chatMainUserA11y(message.text!),
        child: Text(message.text!),
      );
    }
    final note = message.system;
    if (note != null) {
      final t = note == AskSystemNote.roastOn ? l.chatRoastOn : l.chatRoastOff;
      return _Bubble(
        fromUser: false,
        semanticsLabel: l.chatMainZaghlolA11y(t),
        child: Text(t),
      );
    }
    final lang = Localizations.localeOf(context).languageCode;
    final names = ref.watch(askCategoryNamesProvider).value ?? const {};
    final builder = AskAnswerTextBuilder(
      l: l,
      languageCode: lang,
      digits: ref.watch(digitsModeProvider(lang)),
      hidden: ref.watch(hideAmountsProvider),
      today: ref.watch(todayProvider),
      schedule: ref.watch(paydayScheduleProvider).value,
      categoryNames: {
        for (final e in names.entries)
          e.key: lang == 'ar' ? e.value.ar : e.value.en,
      },
    );
    final answer = message.answer!;
    final content = builder.build(answer);
    return _Bubble(
      fromUser: false,
      tag: answer is AskRoastAnswer ? l.chatMainRoastTag : null,
      mood: answer is AskRoastAnswer
          ? ZaghlolMoment.shocked
          : ZaghlolMoment.proud,
      semanticsLabel: a11yAmounts(
        l,
        l.chatMainZaghlolA11y(content.lines.join(' ')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in content.lines) Text(line, style: ZType.body),
          for (final chart in content.charts) _MiniBars(chart: chart),
          if (answer is AskUnavailableAnswer)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () =>
                    ref.read(askChatProvider.notifier).retry(message),
                child: Text(l.commonActionTryAgain),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small bar chart in plain widgets. A `Row` flips in RTL, so the earlier
/// period is at the start edge in both directions.
class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.chart});
  final AskMiniChart chart;

  static const double _height = 88;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
      child: Semantics(
        label: l.chatMainChartA11y,
        excludeSemantics: true,
        child: SizedBox(
          key: const ValueKey('ask-mini-chart'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in chart.bars)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: ZSpacing.xs,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: _height,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: (b.permille.clamp(30, 1000)) / 1000,
                              widthFactor: 0.5,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.dangerText.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(
                                    ZRadius.md,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          b.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: ZType.caption.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({this.phase = AskLlmPhase.none});
  final AskLlmPhase phase;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return _Bubble(
      fromUser: false,
      mood: ZaghlolMoment.thinking,
      talk: true,
      liveRegion: phase != AskLlmPhase.none,
      semanticsLabel: switch (phase) {
        AskLlmPhase.none => l.chatMainTypingA11y,
        AskLlmPhase.sending => l.chatLlmStatusThinkingA11y,
        AskLlmPhase.computing => l.chatLlmStatusComputing,
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        key: const ValueKey('ask-typing'),
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: ZSpacing.xs),
              child: SizedBox.square(
                dimension: ZSpacing.sm,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          if (phase != AskLlmPhase.none)
            Flexible(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: ZSpacing.xs),
                child: Text(
                  phase == AskLlmPhase.sending
                      ? l.chatLlmStatusSending
                      : l.chatLlmStatusComputing,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String askChipLabel(AppLocalizations l, AskChip chip) => switch (chip) {
  AskChip.spendThisMonth => '${l.budgetEditOverall} ${l.chatPeriodThisMonth}',
  AskChip.spendLastMonth => '${l.budgetEditOverall} ${l.chatPeriodLastMonth}',
  AskChip.topMerchants => l.chatChipTopMerchants,
  AskChip.biggestExpense => l.chatChipBiggest,
  AskChip.budgetLeft => l.chatChipBudgetLeft,
  AskChip.balance => l.accountsDetailBalance,
  AskChip.upcomingDues => l.chatChipDues,
  AskChip.savings => l.chatChipSavings,
  AskChip.compareMonths => l.chatChipCompare,
  AskChip.roast => l.chatMainRoast,
};

List<AskChip> _chipsFor(AskChatState chat) {
  AskAnswer? last;
  for (final m in chat.messages.reversed) {
    if (m.answer != null) {
      last = m.answer;
      break;
    }
  }
  return switch (last) {
    null => const [
      AskChip.spendThisMonth,
      AskChip.topMerchants,
      AskChip.upcomingDues,
    ],
    AskFallbackAnswer(:final chips) => chips.take(3).toList(),
    AskSpendAnswer() => followUpChips(AskIntent.spend),
    AskCompareAnswer() => followUpChips(AskIntent.comparePeriods),
    AskTopMerchantsAnswer() => followUpChips(AskIntent.topMerchants),
    AskBalanceAnswer() => followUpChips(AskIntent.accountBalance),
    AskBudgetAnswer() => followUpChips(AskIntent.budgetRemaining),
    AskDuesAnswer() => followUpChips(AskIntent.upcomingDues),
    AskBiggestAnswer() => followUpChips(AskIntent.biggestExpense),
    AskSavingsAnswer() => followUpChips(AskIntent.savings),
    AskRoastAnswer() => followUpChips(AskIntent.roast),
    AskExchangeAnswer() => followUpChips(AskIntent.exchange),
    _ => const [AskChip.spendThisMonth, AskChip.topMerchants, AskChip.roast],
  };
}

class _Chips extends ConsumerWidget {
  const _Chips({required this.chat});
  final AskChatState chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.screen,
      ),
      child: Row(
        children: [
          for (final chip in _chipsFor(chat))
            Padding(
              padding: const EdgeInsetsDirectional.only(end: ZSpacing.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ZSpacing.minTarget,
                ),
                child: ActionChip(
                  label: Text(askChipLabel(l, chip)),
                  labelStyle: ZType.titleSmall.copyWith(
                    color: ZColors.of(context).text,
                    fontWeight: FontWeight.w500,
                  ),
                  backgroundColor: ZColors.of(context).surface,
                  side: BorderSide.none,
                  elevation: 2,
                  shadowColor: ZColors.of(context).shadow,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: ZSpacing.sm,
                    vertical: ZSpacing.sm,
                  ),
                  onPressed: chat.thinking
                      ? null
                      : () => ref
                            .read(askChatProvider.notifier)
                            .sendChip(chip, askChipLabel(l, chip)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InputRow extends ConsumerWidget {
  const _InputRow({
    required this.controller,
    required this.onSend,
    required this.roast,
  });
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool roast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final busy = ref.watch(askChatProvider.select((s) => s.thinking));
    final llm = ref.watch(featureFlagProvider(FeatureFlag.askLlm));
    final phase = ref.watch(askChatProvider.select((s) => s.phase));
    final chatPaused = ref.watch(askChatProvider.select((s) => s.paused));
    final storedPaused =
        ref.watch(askQuotaStateProvider).value?.paused ?? false;
    final paused = chatPaused || storedPaused;
    final snapshot = ref.watch(askQuotaSnapshotProvider).value;
    final stoppable = llm && phase != AskLlmPhase.none;
    final bigText = MediaQuery.textScalerOf(context).scale(10) >= 13;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final len = v.text.trim().length;
        // With the helper on, the field stops at 300 and says so there.
        final tooLong = llm
            ? len >= askMaxQuestionChars
            : len > askMaxQuestionChars;
        final ok = AskChatController.isValid(v.text) && !busy;
        return Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            ZSpacing.screen,
            ZSpacing.sm,
            ZSpacing.screen,
            // The shell's Add circle is raised above the bar's top edge and
            // would cover this row's centre: keep it clear (C-02).
            ZSpacing.sm + ZSpacing.addRaise,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (llm && !paused)
                _CounterLine(
                  snapshot: snapshot,
                  stacked: bigText,
                  lastOne: snapshot?.remaining == 1,
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(ZRadius.pill),
                  border: Border.all(color: c.outline),
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: ZSpacing.xs,
                      ),
                      child: Semantics(
                        toggled: roast,
                        hint: l.chatMainRoastHint,
                        label: l.chatMainRoast,
                        excludeSemantics: true,
                        child: Tooltip(
                          message: l.chatMainRoast,
                          child: InkResponse(
                            key: const ValueKey('ask-roast-toggle'),
                            onTap: () => ref
                                .read(askChatProvider.notifier)
                                .setRoast(!roast),
                            radius: 28,
                            child: SizedBox.square(
                              dimension: ZSpacing.minTarget,
                              child: Center(
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: roast
                                        ? c.accent
                                        : c.primaryContainer,
                                  ),
                                  child: Icon(
                                    Icons.local_fire_department,
                                    size: 22,
                                    color: roast ? c.onAccent : c.warningText,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        // Money questions stay out of keyboard learning.
                        enableIMEPersonalizedLearning: false,
                        enableSuggestions: false,
                        autocorrect: false,
                        inputFormatters: llm
                            ? [
                                LengthLimitingTextInputFormatter(
                                  askMaxQuestionChars,
                                ),
                              ]
                            : null,
                        onSubmitted: (_) {
                          if (ok) onSend();
                        },
                        decoration: InputDecoration(
                          hintText: llm
                              ? l.chatLlmInputHint
                              : l.chatMainInputHint,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsetsDirectional.symmetric(
                            horizontal: ZSpacing.md,
                            vertical: ZSpacing.md,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: ZSpacing.xs,
                      ),
                      child: stoppable
                          ? IconButton(
                              key: const ValueKey('ask-stop'),
                              tooltip: l.chatLlmInputStopA11y,
                              style: IconButton.styleFrom(
                                backgroundColor: c.primary,
                                foregroundColor: c.onPrimary,
                                fixedSize: const Size(44, 44),
                                minimumSize: const Size(44, 44),
                                tapTargetSize: MaterialTapTargetSize.padded,
                              ),
                              // The stop square never mirrors.
                              icon: const Icon(Icons.stop_rounded, size: 22),
                              onPressed: ref
                                  .read(askChatProvider.notifier)
                                  .stop,
                            )
                          : IconButton(
                              key: const ValueKey('ask-send'),
                              tooltip: l.chatMainSendA11y,
                              style: IconButton.styleFrom(
                                backgroundColor: c.primary,
                                foregroundColor: c.onPrimary,
                                disabledBackgroundColor: c.primary.withValues(
                                  alpha: 0.38,
                                ),
                                disabledForegroundColor: c.onPrimary,
                                fixedSize: const Size(44, 44),
                                minimumSize: const Size(44, 44),
                                tapTargetSize: MaterialTapTargetSize.padded,
                              ),
                              // Icons.send mirrors automatically (matchTextDirection).
                              icon: const Icon(Icons.send_rounded, size: 20),
                              onPressed: ok ? onSend : null,
                            ),
                    ),
                  ],
                ),
              ),
              if (llm && len >= 250)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: ZSpacing.xs,
                      end: ZSpacing.lg,
                    ),
                    child: Text(
                      l.chatLlmInputCounter(len, askMaxQuestionChars),
                      style: ZType.caption.copyWith(color: c.textMuted),
                    ),
                  ),
                ),
              if (tooLong)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    top: ZSpacing.xs,
                    start: ZSpacing.lg,
                  ),
                  child: Text(
                    l.chatMainTooLong(
                      askMaxQuestionChars,
                      '$askMaxQuestionChars',
                    ),
                    style: ZType.bodySmall.copyWith(color: c.dangerText),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Above the field: the "last question" note at the start, the counter at the
/// end; stacked (counter on its own line) at 130 % text.
class _CounterLine extends StatelessWidget {
  const _CounterLine({
    required this.snapshot,
    required this.stacked,
    required this.lastOne,
  });
  final LlmQuotaSnapshot? snapshot;
  final bool stacked;
  final bool lastOne;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final counter = _QuotaCounter(snapshot: snapshot);
    final note = lastOne
        ? Text(
            l.chatQuotaLastOne,
            style: ZType.caption.copyWith(color: c.textMuted),
          )
        : null;
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?note,
          Align(alignment: AlignmentDirectional.centerEnd, child: counter),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: note ?? const SizedBox.shrink()),
        counter,
      ],
    );
  }
}
