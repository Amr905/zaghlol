// T-346: S-50 online-helper pieces (ask-llm-ux §1, §4). Part of the screen so
// the bubble and typing row are shared.
part of 'ask_screen.dart';

String _failureText(AppLocalizations l, AskLlmFailure f) => switch (f) {
  AskLlmFailure.timeout => l.chatLlmStatusTimeout,
  AskLlmFailure.slowDown => l.chatLlmStatusSlowDown,
  AskLlmFailure.integrity => l.chatLlmStatusIntegrity,
  _ => l.chatLlmStatusError,
};

/// First four-digit run of the question (ASCII or Arabic-Indic), or null.
String? _last4Of(String? question) {
  if (question == null) return null;
  final ascii = question.replaceAllMapped(
    RegExp('[٠-٩]'),
    (m) => '${m.group(0)!.codeUnitAt(0) - 0x0660}',
  );
  return RegExp(r'(?<!\d)\d{4}(?!\d)').firstMatch(ascii)?.group(0);
}

String _clarifyText(AppLocalizations l, MaskUnresolved u, String? question) {
  final shared = u.candidates.isEmpty ? null : u.candidates.first.last4;
  return switch (u.reason) {
    MaskUnresolvedReason.ambiguousCard when shared != null =>
      l.chatClarifySameLast4(shared),
    MaskUnresolvedReason.noSuchCard when _last4Of(question) != null =>
      l.chatClarifyNoCard(_last4Of(question)!),
    _ => l.chatClarifyNoAccount,
  };
}

/// Cairo's first of next month for the reset date (snapshot is UTC).
DateTime _resetDate(LlmQuotaSnapshot? q, DateTime now) {
  if (q != null) return q.resetsAt.add(const Duration(hours: 3));
  return DateTime(now.year, now.month + 1);
}

class _LlmMessageView extends ConsumerWidget {
  const _LlmMessageView({required this.message, required this.onPick});
  final AskMessage message;
  final void Function(String label, String? question) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final s = message.llm!;

    Widget caption(String t) => Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
      child: Text(t, style: ZType.caption.copyWith(color: c.textMuted)),
    );

    Widget plain(
      String text, {
      ZaghlolMoment mood = ZaghlolMoment.tourGuide,
      Widget? extra,
      Widget? actions,
    }) => _Bubble(
      fromUser: false,
      mood: mood,
      liveRegion: true,
      semanticsLabel: l.chatMainZaghlolA11y(text),
      actions: actions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(text), ?extra],
      ),
    );

    Widget tryAgain() => Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        key: const ValueKey('ask-try-again'),
        style: TextButton.styleFrom(
          minimumSize: const Size(ZSpacing.minTarget, ZSpacing.minTarget),
        ),
        onPressed: () => ref.read(askChatProvider.notifier).retry(message),
        child: Text(l.commonActionTryAgain),
      ),
    );

    switch (s) {
      case AskLlmClarify(:final unresolved):
        final text = _clarifyText(l, unresolved, message.retry?.question);
        return plain(
          text,
          mood: ZaghlolMoment.detective,
          extra: caption(l.chatClarifyNotSent),
          actions: Wrap(
            spacing: ZSpacing.sm,
            children: [
              for (final a in unresolved.candidates)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: ZSpacing.minTarget,
                  ),
                  child: ActionChip(
                    key: ValueKey('ask-clarify-${a.id}'),
                    label: Text(a.label),
                    onPressed: () => onPick(a.label, message.retry?.question),
                  ),
                ),
            ],
          ),
        );
      case AskLlmOffline():
        return plain(
          l.chatLlmStatusOffline,
          mood: ZaghlolMoment.oops,
          extra: caption(l.chatLlmStatusNotQueued),
        );
      case AskLlmConsentDeclined():
        return plain(l.chatConsentDeclined);
      case AskLlmPaused():
        return plain(l.chatLlmStatusPaused, mood: ZaghlolMoment.sleep);
      case AskLlmFailed(:final failure):
        return plain(
          _failureText(l, failure),
          mood: ZaghlolMoment.oops,
          actions: message.retry == null ? null : tryAgain(),
        );
      case AskLlmQuotaOut(:final quota):
        final lang = Localizations.localeOf(context).languageCode;
        final date = ZDateFormat.date(
          _resetDate(quota, DateTime.now()),
          lang,
          ref.watch(digitsModeProvider(lang)),
        );
        final gold = ref.watch(entitlementStateProvider).isGold;
        if (gold) {
          return plain(
            l.chatQuotaGoldOut(date),
            extra: caption(l.chatLlmStatusNotQueued),
          );
        }
        final perMonth =
            ref.watch(remoteConfigProvider).value?.askQuotaGold ?? 50;
        return plain(
          l.chatQuotaFreeOut(date),
          extra: Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.workspace_premium_outlined,
                      size: 18,
                      color: c.text,
                    ),
                    const SizedBox(width: ZSpacing.xs),
                    Expanded(
                      child: Text(l.chatQuotaGoldHint(perMonth, perMonth)),
                    ),
                  ],
                ),
                caption(l.chatLlmStatusNotQueued),
              ],
            ),
          ),
          actions: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const ValueKey('ask-see-gold'),
              style: TextButton.styleFrom(
                foregroundColor: c.primary,
                minimumSize: const Size(ZSpacing.minTarget, ZSpacing.minTarget),
              ),
              // The paywall counter (FR-GOLD-05) moves only on this tap.
              onPressed: () =>
                  ref.read(paywallTriggerProvider)(GoldCapability.deepCoaching),
              child: Text(l.chatQuotaSeeGold),
            ),
          ),
        );
      case AskLlmAnswered():
        final build = ref.watch(llmAnswerViewBuilderProvider);
        // The view builds its own semantics (figures, masked amounts, the
        // badge and chips stay separate nodes).
        return _Bubble(
          fromUser: false,
          mood: llmAnswerMood(s.answer),
          child: build(context, s),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// The counter at the input's end edge: "n questions left", or a dash before
/// the first reply. Tap opens the explainer. Hidden while paused.
class _QuotaCounter extends ConsumerWidget {
  const _QuotaCounter({required this.snapshot});
  final LlmQuotaSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final q = snapshot;
    final label = q == null
        ? l.chatQuotaUnknown
        : l.chatQuotaRemaining(q.remaining, q.remaining);
    final a11y = q == null
        ? l.chatQuotaUnknownA11y
        : l.chatQuotaRemainingA11y(q.remaining, q.remaining);
    return Semantics(
      button: true,
      label: a11y,
      excludeSemantics: true,
      onTap: () => _info(context, l),
      child: InkWell(
        key: const ValueKey('ask-quota-counter'),
        borderRadius: BorderRadius.circular(ZRadius.pill),
        onTap: () => _info(context, l),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: ZType.label.copyWith(color: c.textMuted),
                ),
              ),
              const SizedBox(width: ZSpacing.xs),
              Icon(Icons.info_outline, size: 16, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _info(BuildContext context, AppLocalizations l) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            ZSpacing.xl,
            0,
            ZSpacing.xl,
            ZSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(l.chatQuotaInfoTitle, style: ZType.titleSmall),
              ),
              const SizedBox(height: ZSpacing.sm),
              Text(l.chatQuotaInfoBody),
            ],
          ),
        ),
      ),
    );
  }
}
