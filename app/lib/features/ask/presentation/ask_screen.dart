// T-111: S-50 Ask Zaghlol. Chat bubbles, suggestion chips, mini bar charts,
// roast toggle and a thinking moment. Answers come from `askEngineProvider`
// (T-110) through [askChatProvider]; the widgets never touch the database.
// Lives on the Zaghlol tab (override `TabRoots.zaghlol` with `AskScreen`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../budget/application/budget_providers.dart' show todayProvider;
import '../../budget/presentation/budget_providers_ui.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import '../domain/ask_models.dart';
import 'ask_answer_text.dart';
import 'ask_chat_controller.dart';

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

  @override
  void dispose() {
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

  Future<void> _send() async {
    final sent = await ref.read(askChatProvider.notifier).sendText(_text.text);
    if (sent) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final chat = ref.watch(askChatProvider);
    ref.listen(askChatProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          prev?.thinking != next.thinking) {
        _toEnd();
      }
    });

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(l.commonNavZaghlol),
        actions: [
          PopupMenuButton<_Menu>(
            tooltip: l.chatMainClear,
            constraints: const BoxConstraints(minWidth: ZSpacing.minTarget),
            onSelected: (_) {
              ref.read(askChatProvider.notifier).clear();
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l.chatMainCleared)));
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: _Menu.clear, child: Text(l.chatMainClear)),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
                children: [
                  _Header(
                    thinking: chat.thinking,
                    empty: chat.messages.isEmpty,
                  ),
                  for (final m in chat.messages) _MessageView(message: m),
                  if (chat.thinking) const _TypingBubble(),
                ],
              ),
            ),
            _Chips(chat: chat),
            _RoastRow(on: chat.roast),
            _InputRow(controller: _text, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.thinking, required this.empty});
  final bool thinking;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ZaghlolAvatar(
            moment: thinking ? ZaghlolMoment.thinking : ZaghlolMoment.tourGuide,
            talk: thinking,
            size: 72,
          ),
        ),
        if (empty)
          _Bubble(
            fromUser: false,
            semanticsLabel: l.chatMainZaghlolA11y(l.chatMainGreeting),
            child: Text(l.chatMainGreeting),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.fromUser,
    required this.child,
    required this.semanticsLabel,
  });
  final bool fromUser;
  final Widget child;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: fromUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width * 0.82),
          child: Semantics(
            container: true,
            label: semanticsLabel,
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fromUser ? c.primaryContainer : c.zaghlolBg,
                borderRadius: BorderRadius.circular(ZRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(ZSpacing.md),
                child: DefaultTextStyle.merge(
                  style: ZType.body.copyWith(
                    color: fromUser ? c.onPrimaryContainer : c.text,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageView extends ConsumerWidget {
  const _MessageView({required this.message});
  final AskMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
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
      today: ref.watch(todayProvider),
      categoryNames: {
        for (final e in names.entries)
          e.key: lang == 'ar' ? e.value.ar : e.value.en,
      },
    );
    final answer = message.answer!;
    final content = builder.build(answer);
    return _Bubble(
      fromUser: false,
      semanticsLabel: l.chatMainZaghlolA11y(content.lines.join(' ')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in content.lines) Text(line),
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

  static const double _height = 64;

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
                              widthFactor: 0.6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.primary,
                                  borderRadius: BorderRadius.circular(
                                    ZRadius.sm,
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
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return _Bubble(
      fromUser: false,
      semanticsLabel: l.chatMainTypingA11y,
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

class _RoastRow extends ConsumerWidget {
  const _RoastRow({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.screen,
      ),
      child: Semantics(
        hint: l.chatMainRoastHint,
        child: SwitchListTile(
          key: const ValueKey('ask-roast-toggle'),
          contentPadding: EdgeInsetsDirectional.zero,
          secondary: const Icon(Icons.local_fire_department_outlined),
          title: Text(l.chatMainRoast),
          subtitle: Text(l.chatMainRoastHint),
          value: on,
          onChanged: ref.read(askChatProvider.notifier).setRoast,
        ),
      ),
    );
  }
}

class _InputRow extends ConsumerWidget {
  const _InputRow({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final busy = ref.watch(askChatProvider.select((s) => s.thinking));
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final tooLong = v.text.trim().length > askMaxQuestionChars;
        final ok = AskChatController.isValid(v.text) && !busy;
        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            ZSpacing.screen,
            ZSpacing.xs,
            ZSpacing.sm,
            ZSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) {
                    if (ok) onSend();
                  },
                  decoration: InputDecoration(
                    hintText: l.chatMainInputHint,
                    errorText: tooLong
                        ? l.chatMainTooLong(
                            askMaxQuestionChars,
                            '$askMaxQuestionChars',
                          )
                        : null,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('ask-send'),
                tooltip: l.chatMainSendA11y,
                constraints: const BoxConstraints(
                  minWidth: ZSpacing.minTarget,
                  minHeight: ZSpacing.minTarget,
                ),
                // Icons.send mirrors automatically (matchTextDirection).
                icon: const Icon(Icons.send_rounded),
                onPressed: ok ? onSend : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
