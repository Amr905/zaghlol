// T-120: S-31 Voice logger (mockup 12, spec 40-quick-add.md). Full-screen
// route over the shell. Listening, understanding, parsed list with editable
// items, and the empty / unavailable / mic-denied / limit / consent states.
// Nothing is saved until "Save"; one confirmed recording counts as one voice
// log (A-14). The mascot is decorative and never blocks input.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../budget/application/budget_providers.dart';
import '../../gold/application/gating.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import '../../transactions/data/transactions_providers.dart';
import '../../transactions/presentation/edit/transaction_edit_screen.dart';
import '../../transactions/presentation/edit/txn_edit_providers.dart';
import '../../transactions/presentation/edit/txn_form.dart';
import '../../transactions/presentation/list/txn_list_providers.dart';
import '../../transactions/presentation/list/txn_row.dart';
import '../application/voice_controller.dart';
import '../application/voice_models.dart';
import '../application/voice_providers.dart';
import '../../../core/ui/z_haptics.dart';
import '../../../core/settings/settings_providers.dart';

/// Opens S-31 full screen over the current route.
Future<void> showVoiceLogger(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const VoiceLoggerScreen(),
      ),
    );

class VoiceLoggerScreen extends ConsumerStatefulWidget {
  const VoiceLoggerScreen({super.key});

  @override
  ConsumerState<VoiceLoggerScreen> createState() => _VoiceLoggerState();
}

class _VoiceLoggerState extends ConsumerState<VoiceLoggerScreen> {
  bool _consentShown = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final lang = Localizations.localeOf(context).languageCode;
    // Starts listening on open (spec); after the first frame so the provider
    // is not modified while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(voiceControllerProvider.notifier).begin(languageCode: lang),
        );
      }
    });
  }

  void _typeInstead() {
    final nav = Navigator.of(context, rootNavigator: true);
    nav.pop();
    unawaited(showTransactionEditor(nav.context));
  }

  void _close() => Navigator.of(context).maybePop();

  Future<void> _onSaved(VoiceState s) async {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final n = ref.read(digitsModeProvider(lang)).render('${s.drafts.length}');
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context);
    final ids = s.savedIds;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.voiceLoggerSaved(s.drafts.length, n)),
        action: SnackBarAction(
          label: l.commonActionUndo,
          onPressed: () {
            ZHaptics.light();
            unawaited(_undo(container, ids));
          },
        ),
      ),
    );
  }

  static Future<void> _undo(ProviderContainer c, List<String> ids) async {
    try {
      final repo = await c.read(transactionRepositoryProvider.future);
      await repo.softDelete(ids);
    } on Object {
      // Already gone; nothing to undo.
    }
  }

  Future<void> _askConsent() async {
    final l = AppLocalizations.of(context);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final c = ref.read(voiceControllerProvider.notifier);
    final allow = await showZSheet<bool>(
      context: context,
      title: l.voiceLoggerOnlineTitle,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.voiceLoggerOnlineBody(ios ? 'ios' : 'android'),
            style: ZType.body.copyWith(color: ZColors.of(ctx).text),
          ),
          const SizedBox(height: ZSpacing.lg),
          ZButton(
            key: const ValueKey('voice-consent-allow'),
            label: l.voiceLoggerOnlineAllow,
            expand: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: ZSpacing.sm),
          ZButton(
            key: const ValueKey('voice-consent-deny'),
            label: l.voiceLoggerOnlineDeny,
            variant: ZButtonVariant.text,
            expand: true,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(height: ZSpacing.lg),
        ],
      ),
    );
    if (!mounted) return;
    if (allow == true) {
      await c.allowOnline();
    } else {
      _typeInstead();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(voiceControllerProvider);
    ref.listen(voiceControllerProvider.select((v) => v.phase), (prev, next) {
      if (next == VoicePhase.saved) {
        unawaited(_onSaved(ref.read(voiceControllerProvider)));
      }
      if (next == VoicePhase.needConsent && !_consentShown) {
        _consentShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_askConsent());
        });
      }
      if (next != VoicePhase.needConsent) _consentShown = false;
    });
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: ZSpacing.screen,
                  top: ZSpacing.sm,
                ),
                child: _CloseButton(label: l.commonActionClose, onTap: _close),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: ZMotion.standard,
                child: KeyedSubtree(
                  key: ValueKey(s.phase),
                  child: switch (s.phase) {
                    VoicePhase.checking ||
                    VoicePhase.needConsent => const SizedBox.expand(),
                    VoicePhase.listening => _Listening(state: s),
                    VoicePhase.understanding => _Message(
                      moment: ZaghlolMoment.thinking,
                      title: l.voiceLoggerUnderstanding,
                    ),
                    VoicePhase.parsed ||
                    VoicePhase.saving ||
                    VoicePhase.saved => _Parsed(state: s),
                    VoicePhase.empty => _Message(
                      moment: ZaghlolMoment.oops,
                      title: l.voiceLoggerEmptyTitle,
                      body: l.voiceLoggerEmptyBody,
                      actions: [
                        _primary(
                          l.commonActionTryAgain,
                          () => ref
                              .read(voiceControllerProvider.notifier)
                              .tryAgain(),
                        ),
                        _text(l.commonActionTypeInstead, _typeInstead),
                      ],
                    ),
                    VoicePhase.unavailable => _Message(
                      moment: ZaghlolMoment.oops,
                      title: l.voiceLoggerUnavailable,
                      body: l.voiceLoggerUnavailableBody,
                      actions: [
                        _primary(l.commonActionTypeInstead, _typeInstead),
                      ],
                    ),
                    VoicePhase.micDenied => _Message(
                      moment: ZaghlolMoment.oops,
                      title: l.voiceLoggerMicTitle,
                      body: l.voiceLoggerMicBody,
                      actions: [
                        _primary(
                          l.commonActionOpenSettings,
                          () =>
                              unawaited(ref.read(voiceOpenSettingsProvider)()),
                        ),
                        _text(l.commonActionTypeInstead, _typeInstead),
                      ],
                    ),
                    VoicePhase.limit => _Message(
                      moment: ZaghlolMoment.counting,
                      title: l.voiceLoggerLimitTitle,
                      body: l.voiceLoggerLimitBody(
                        ref
                            .watch(
                              digitsModeProvider(
                                Localizations.localeOf(context).languageCode,
                              ),
                            )
                            .render('${FreeLimits.voiceEntriesPerMonth}'),
                      ),
                      actions: [
                        ZButton(
                          key: const ValueKey('voice-limit-gold'),
                          label: l.commonGoldUnlock,
                          variant: ZButtonVariant.gold,
                          expand: true,
                          onPressed: () => ref.read(paywallTriggerProvider)(
                            GoldCapability.voiceEntry,
                          ),
                        ),
                        _text(l.commonActionTypeInstead, _typeInstead),
                      ],
                    ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primary(String label, VoidCallback onTap) =>
      ZButton(label: label, expand: true, onPressed: onTap);

  Widget _text(String label, VoidCallback onTap) => ZButton(
    label: label,
    variant: ZButtonVariant.text,
    expand: true,
    onPressed: onTap,
  );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: ZSpacing.minTarget,
            height: ZSpacing.minTarget,
            child: Icon(Icons.close, color: c.text),
          ),
        ),
      ),
    );
  }
}

/// Mascot + title (+ body) + stacked actions, centred.
class _Message extends StatelessWidget {
  const _Message({
    required this.moment,
    required this.title,
    this.body,
    this.actions = const [],
  });

  final ZaghlolMoment moment;
  final String title;
  final String? body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.screen,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: ZaghlolAvatar(moment: moment, size: 140)),
              const SizedBox(height: ZSpacing.lg),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: ZType.headline.copyWith(color: c.text),
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: ZSpacing.sm),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: ZType.body.copyWith(color: c.textMuted),
                ),
              ],
              const SizedBox(height: ZSpacing.xl),
              for (final a in actions) ...[
                a,
                const SizedBox(height: ZSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Listening extends ConsumerWidget {
  const _Listening({required this.state});
  final VoiceState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    final l = AppLocalizations.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final ring = 150 + 50 * state.level;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.screen,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: ZSpacing.lg),
          Center(
            child: ExcludeSemantics(
              child: SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // The wings "pulse with input level" (spec).
                    AnimatedContainer(
                      duration: reduce ? Duration.zero : ZMotion.micro,
                      width: ring,
                      height: ring,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.primaryContainer,
                      ),
                    ),
                    const ZaghlolAvatar(
                      moment: ZaghlolMoment.listening,
                      size: 130,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              l.voiceLoggerTitle,
              textAlign: TextAlign.center,
              style: ZType.headline.copyWith(color: c.text),
            ),
          ),
          const SizedBox(height: ZSpacing.xs),
          Text(
            l.voiceLoggerListening,
            textAlign: TextAlign.center,
            style: ZType.bodySmall.copyWith(color: c.primary),
          ),
          const SizedBox(height: ZSpacing.lg),
          if (state.transcript.isEmpty)
            Text(
              '${l.voiceLoggerExampleLabel}: “${l.voiceLoggerExample}”',
              textAlign: TextAlign.center,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            )
          else
            Semantics(
              liveRegion: true,
              label: l.voiceLoggerTranscriptA11y(state.transcript),
              child: ExcludeSemantics(
                child: _TranscriptCard(text: state.transcript),
              ),
            ),
          const SizedBox(height: ZSpacing.xl),
          Center(
            child: ZButton(
              key: const ValueKey('voice-done'),
              label: l.voiceLoggerDone,
              icon: Icons.stop_rounded,
              semanticsLabel: l.voiceLoggerStopA11y,
              onPressed: () =>
                  ref.read(voiceControllerProvider.notifier).stopListening(),
            ),
          ),
          const SizedBox(height: ZSpacing.xl),
        ],
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(ZRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
        child: Text('«$text»', style: ZType.body.copyWith(color: c.text)),
      ),
    );
  }
}

class _Parsed extends ConsumerWidget {
  const _Parsed({required this.state});
  final VoiceState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final fmt = TxnFmt(
      lang,
      ref.watch(digitsModeProvider(lang)),
      hidden: ref.watch(hideAmountsProvider),
    );
    final lookups = ref.watch(txnLookupsProvider).value;
    final ctrl = ref.read(voiceControllerProvider.notifier);
    final count = state.drafts.length;
    final n = fmt.count(count);
    final saving = state.phase != VoicePhase.parsed;
    final accountOk =
        lookups != null &&
        state.drafts.every((d) => ctrl.accountFor(d, lookups) != null);
    final complete =
        state.canSave && state.drafts.every((d) => d.categoryId != null);
    final today = ref.watch(todayProvider);
    final date = state.date ?? today;
    final dateText = date.epochDay == today.epochDay
        ? l.commonDateToday
        : date.epochDay == today.epochDay - 1
        ? l.commonDateYesterday
        : ZDateFormat.date(
            DateTime(date.year, date.month, date.day),
            lang,
            fmt.digits,
          );
    final account = state.accountId == null
        ? null
        : lookups?.account(state.accountId!);
    final cashId = ref.watch(defaultCashAccountIdProvider).value;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.screen,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(
                        l.voiceLoggerParsedTitle(count, n),
                        style: ZType.headline.copyWith(color: c.text),
                      ),
                    ),
                  ),
                  const ExcludeSemantics(
                    child: ZaghlolAvatar(moment: ZaghlolMoment.saved, size: 88),
                  ),
                ],
              ),
              const SizedBox(height: ZSpacing.md),
              _TranscriptCard(text: state.transcript),
              const SizedBox(height: ZSpacing.lg),
              ZCard(
                padding: const EdgeInsetsDirectional.symmetric(
                  vertical: ZSpacing.xs,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < state.drafts.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: ZSpacing.lg,
                          color: c.outline,
                        ),
                      _ItemRow(
                        draft: state.drafts[i],
                        lookups: lookups,
                        fmt: fmt,
                        enabled: !saving,
                        noAccount:
                            lookups != null &&
                            ctrl.accountFor(state.drafts[i], lookups) == null,
                        itemAccount: _rowAccount(
                          ctrl,
                          state,
                          lookups,
                          state.drafts[i],
                        ),
                        cashId: cashId,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: ZSpacing.md),
              Wrap(
                spacing: ZSpacing.sm,
                runSpacing: ZSpacing.sm,
                children: [
                  ZChip(
                    key: const ValueKey('voice-account'),
                    icon: Icons.account_balance_wallet_outlined,
                    label:
                        '${l.voiceLoggerAccount}: ${account == null ? '…' : accountLabel(l, account, fmt, cashId)}',
                    onTap: saving || lookups == null
                        ? null
                        : () =>
                              _pickAccount(context, ref, lookups, fmt, cashId),
                  ),
                  ZChip(
                    key: const ValueKey('voice-date'),
                    icon: Icons.calendar_month_outlined,
                    label: dateText,
                    onTap: saving ? null : () => _pickDate(context, ref),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                child: Text(
                  l.voiceLoggerApplyAll,
                  style: ZType.caption.copyWith(color: c.textMuted),
                ),
              ),
              if (state.saveFailed)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
                  child: Text(
                    l.commonErrorSaveFailed,
                    key: const ValueKey('voice-save-failed'),
                    style: ZType.bodySmall.copyWith(color: c.dangerText),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            ZSpacing.screen,
            ZSpacing.sm,
            ZSpacing.screen,
            ZSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ZButton(
                key: const ValueKey('voice-save'),
                label: l.voiceLoggerSave(count, n),
                expand: true,
                loading: state.phase == VoicePhase.saving,
                onPressed: complete && accountOk && !saving ? ctrl.save : null,
              ),
              ZButton(
                key: const ValueKey('voice-retry'),
                label: l.commonActionTryAgain,
                icon: Icons.mic_none_rounded,
                variant: ZButtonVariant.text,
                expand: true,
                onPressed: saving ? null : ctrl.tryAgain,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickAccount(
    BuildContext context,
    WidgetRef ref,
    TxnLookups lookups,
    TxnFmt fmt,
    String? cashId,
  ) async {
    final l = AppLocalizations.of(context);
    final id = await showZSheet<String>(
      context: context,
      title: l.voiceLoggerAccount,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in lookups.accounts)
            ListTile(
              minTileHeight: ZSpacing.minTarget,
              title: Text(accountLabel(l, a, fmt, cashId)),
              trailing: a.id == state.accountId
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(ctx).pop(a.id),
            ),
          const SizedBox(height: ZSpacing.lg),
        ],
      ),
    );
    if (id != null) ref.read(voiceControllerProvider.notifier).setAccount(id);
  }

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final today = ref.read(todayProvider);
    final now = DateTime(today.year, today.month, today.day);
    final cur = state.date ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(cur.year, cur.month, cur.day),
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) {
      ref
          .read(voiceControllerProvider.notifier)
          .setDate(CivilDate(picked.year, picked.month, picked.day));
    }
  }
}

/// The account name as the user knows it: the default cash account shows the
/// localized "Cash" (its stored label is not translated).
String accountLabel(
  AppLocalizations l,
  TxnAccount a,
  TxnFmt fmt,
  String? cashId,
) => a.id == cashId ? l.commonAccountTypeCash : accountName(a, fmt);

/// The account to show on a row: only when the item is not stored on the
/// chip's account (a different currency or a row-level pick).
TxnAccount? _rowAccount(
  VoiceController ctrl,
  VoiceState state,
  TxnLookups? lookups,
  VoiceDraft d,
) {
  if (lookups == null || d.amount == null) return null;
  final id = ctrl.accountFor(d, lookups);
  if (id == null || id == state.accountId) return null;
  return lookups.account(id);
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({
    required this.draft,
    required this.lookups,
    required this.fmt,
    required this.enabled,
    required this.noAccount,
    required this.itemAccount,
    required this.cashId,
  });

  final VoiceDraft draft;
  final TxnLookups? lookups;
  final TxnFmt fmt;
  final bool enabled;
  final bool noAccount;

  /// The account this item is stored on when it differs from the chip
  /// (a spoken currency that is not the chip's); null when it is the chip's.
  final TxnAccount? itemAccount;
  final String? cashId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final cat = lookups?.category(draft.categoryId);
    final catText = cat == null
        ? l.commonValidationCategoryRequired
        : categoryName(cat, fmt.lang);
    final amountText = draft.hasAmount
        ? fmt.money(draft.amount!)
        : l.voiceLoggerAmountMissing;
    final ctrl = ref.read(voiceControllerProvider.notifier);
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          ZSpacing.md,
          ZSpacing.xs,
          ZSpacing.xs,
          ZSpacing.xs,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: ZCategoryGlyph(categoryId: draft.categoryId, size: 44),
            ),
            const SizedBox(width: ZSpacing.sm),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    key: ValueKey('voice-item-${draft.key}'),
                    onTap: enabled ? () => _edit(context, ref) : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: ZSpacing.minTarget,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Semantics(
                          label: '${l.voiceLoggerEditA11y}: ${draft.text}',
                          button: true,
                          excludeSemantics: true,
                          child: Text(
                            draft.text.isEmpty ? kNoValueDash : draft.text,
                            style: ZType.titleSmall.copyWith(color: c.text),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _CategoryPill(
                      key: ValueKey('voice-cat-${draft.key}'),
                      label: catText,
                      missing: cat == null,
                      onTap: enabled && lookups != null
                          ? () => _pickCategory(context, ref)
                          : null,
                    ),
                  ),
                  if (itemAccount != null && lookups != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _CategoryPill(
                        key: ValueKey('voice-acct-${draft.key}'),
                        label: accountLabel(l, itemAccount!, fmt, cashId),
                        missing: false,
                        onTap: enabled
                            ? () => _pickItemAccount(context, ref)
                            : null,
                      ),
                    ),
                  if (noAccount)
                    Text(
                      l.commonValidationAccountRequired,
                      style: ZType.caption.copyWith(color: c.dangerText),
                    ),
                ],
              ),
            ),
            const SizedBox(width: ZSpacing.xs),
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: enabled ? () => _edit(context, ref) : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    amountText,
                    style: ZType.titleSmall.copyWith(
                      color: draft.hasAmount ? c.text : c.dangerText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              key: ValueKey('voice-remove-${draft.key}'),
              tooltip: l.voiceLoggerRemoveA11y,
              constraints: const BoxConstraints(
                minWidth: ZSpacing.minTarget,
                minHeight: ZSpacing.minTarget,
              ),
              icon: Icon(Icons.close, size: 20, color: c.textMuted),
              onPressed: enabled ? () => ctrl.remove(draft.key) : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCategory(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final id = await showZSheet<String>(
      context: context,
      title: l.transactionsEditCategory,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final cat in lookups!.categories)
            ListTile(
              minTileHeight: ZSpacing.minTarget,
              leading: ExcludeSemantics(
                child: ZCategoryGlyph(categoryId: cat.id, size: 32),
              ),
              title: Text(categoryName(cat, fmt.lang)),
              trailing: cat.id == draft.categoryId
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(ctx).pop(cat.id),
            ),
          const SizedBox(height: ZSpacing.lg),
        ],
      ),
    );
    if (id != null) {
      ref
          .read(voiceControllerProvider.notifier)
          .update(draft.key, categoryId: id);
    }
  }

  Future<void> _pickItemAccount(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final code = draft.amount?.currency.code;
    final current = itemAccount?.id;
    final id = await showZSheet<String>(
      context: context,
      title: l.voiceLoggerAccount,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in lookups!.accounts)
            if (a.currencyCode == code)
              ListTile(
                minTileHeight: ZSpacing.minTarget,
                title: Text(accountLabel(l, a, fmt, cashId)),
                trailing: a.id == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(ctx).pop(a.id),
              ),
          const SizedBox(height: ZSpacing.lg),
        ],
      ),
    );
    if (id != null) {
      ref.read(voiceControllerProvider.notifier).setItemAccount(draft.key, id);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final Currency currency =
        draft.amount?.currency ?? ref.read(voiceDefaultCurrencyProvider);
    final result = await showZSheet<({String text, Money amount})>(
      context: context,
      title: l.voiceLoggerEditA11y,
      builder: (ctx) => _EditForm(
        initialText: draft.text,
        initialAmount: draft.hasAmount ? draft.amount!.toCanonicalString() : '',
        currency: currency,
      ),
    );
    if (result != null) {
      ref
          .read(voiceControllerProvider.notifier)
          .update(draft.key, text: result.text, amount: result.amount);
    }
  }
}

class _EditForm extends StatefulWidget {
  const _EditForm({
    required this.initialText,
    required this.initialAmount,
    required this.currency,
  });

  final String initialText;
  final String initialAmount;
  final Currency currency;

  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.initialAmount.replaceAll(RegExp('[^0-9.]'), ''),
  );
  bool _bad = false;

  @override
  void dispose() {
    _text.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _done() {
    final r = parseAmount(_amount.text, widget.currency);
    if (r.money == null) {
      setState(() => _bad = true);
      return;
    }
    Navigator.of(context).pop((text: _text.text.trim(), amount: r.money!));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('voice-edit-text'),
          controller: _text,
          decoration: InputDecoration(labelText: l.transactionsEditMerchant),
        ),
        const SizedBox(height: ZSpacing.md),
        TextField(
          key: const ValueKey('voice-edit-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: amountInputFormatters,
          decoration: InputDecoration(
            labelText: widget.currency.code,
            errorText: _bad ? l.commonValidationAmountRequired : null,
          ),
        ),
        const SizedBox(height: ZSpacing.lg),
        ZButton(
          key: const ValueKey('voice-edit-done'),
          label: l.commonActionDone,
          expand: true,
          onPressed: _done,
        ),
        const SizedBox(height: ZSpacing.lg),
      ],
    );
  }
}

/// The small "category v" pill under an item (mockup 12). The label can
/// shrink and ellipsize; the tap target stays 48 dp high.
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    super.key,
    required this.label,
    required this.missing,
    required this.onTap,
  });

  final String label;
  final bool missing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZRadius.pill),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Align(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(ZRadius.pill),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: ZSpacing.md,
                  vertical: ZSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.expand_more, size: 18, color: c.textMuted),
                    const SizedBox(width: ZSpacing.xs),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.label.copyWith(
                          color: missing ? c.dangerText : c.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
