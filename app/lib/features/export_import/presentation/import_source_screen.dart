// T-158 / S-67 import flow, step 1 (mockup 32): where the statement comes
// from. Tapping a source runs pick -> read -> summary sheet (mockup 33) ->
// import -> done screen (mockup 34).
//
// States: list, Free (a Gold banner; a tap opens the paywall), coming-soon
// sources (shown disabled), reading (progress), error (unsupported, wrong
// type, failed), empty (no transactions) and nothing new.
//
// The file never leaves the phone: it is read into memory, parsed there and
// dropped; the picker's temporary copy is deleted straight after the read.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../gold/application/gating.dart';
import 'import_done_screen.dart';
import 'import_labels.dart';
import 'import_ports.dart';
import 'import_summary_sheet.dart';
import 'statement_mapping_step.dart';

class ImportSourceScreen extends ConsumerStatefulWidget {
  const ImportSourceScreen({
    super.key,
    this.targetCardName,
    this.onReview,
    this.onOpenCard,
  });

  /// Set when opened from a card ("Import this card's statement").
  final String? targetCardName;

  /// "Review the N" on the done screen; null hides the button.
  final VoidCallback? onReview;

  /// "Open the card" on the done screen; null shows "Done" instead.
  final VoidCallback? onOpenCard;

  @override
  ConsumerState<ImportSourceScreen> createState() => _State();
}

class _State extends ConsumerState<ImportSourceScreen> {
  bool _busy = false;
  ImportFailureKind? _error;

  Future<void> _start(ImportSourceDef source) async {
    if (_busy) return;
    final gold = ref.read(entitlementStateProvider).isGold;
    if (!gold) {
      ref.read(paywallTriggerProvider)(source.capability);
      return;
    }
    setState(() => _error = null);
    final picked = await ref.read(importFilePickerProvider).pick(source.kind);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    // The PDF password lives in this local only: asked for when the runner
    // says the file is protected, passed down per call, never put in state,
    // logs or storage, and dropped when the flow ends.
    String? password;
    ImportTargetCard? target;
    try {
      final runner = await ref.read(importRunnerProvider.future);
      var wrong = false;
      ImportPreview? preview;
      while (preview == null) {
        try {
          preview = await runner.preview(source.id, picked, password: password);
        } on ImportFlowException catch (e) {
          final needs =
              e.kind == ImportFailureKind.passwordRequired ||
              e.kind == ImportFailureKind.wrongPassword;
          if (!needs) rethrow;
          if (!mounted) return;
          setState(() => _busy = false);
          final asked = await askStatementPassword(
            context,
            _passwordLabels(AppLocalizations.of(context)),
            wrong: wrong || e.kind == ImportFailureKind.wrongPassword,
          );
          if (asked == null || asked.isEmpty || !mounted) {
            if (mounted) setState(() => _busy = false);
            return;
          }
          password = asked;
          wrong = true;
          setState(() => _busy = true);
        }
      }
      if (!mounted) return;
      setState(() => _busy = false);
      final go = await showImportSummarySheet(
        context,
        preview: preview,
        targetCardName: widget.targetCardName,
        onTargetChanged: (c) => target = c,
      );
      if (go != true || !mounted) return;
      setState(() => _busy = true);
      final outcome = await runner.commit(
        source.id,
        picked,
        password: password,
        targetCardId: target?.id,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ImportDoneScreen(
            outcome: outcome,
            cardName: target?.name ?? widget.targetCardName,
            onReview: widget.onReview,
            onOpenCard: widget.onOpenCard,
          ),
          fullscreenDialog: true,
        ),
      );
    } on ImportFlowException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.kind;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ImportFailureKind.failed;
        });
      }
    }
  }

  void _howTo() {
    final l = AppLocalizations.of(context);
    showZSheet<void>(
      context: context,
      title: l.importFlowHowTo,
      builder: (_) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.xl),
        child: Text(
          l.importFlowHowToBody,
          style: ZType.body.copyWith(color: ZColors.of(context).text),
        ),
      ),
    );
  }

  String _errorText(AppLocalizations l, ImportFailureKind k) => switch (k) {
    ImportFailureKind.wrongType => l.exportsImportWrongType,
    ImportFailureKind.unsupported => l.exportsImportUnsupportedTitle,
    ImportFailureKind.failed => l.exportsImportFailed,
    ImportFailureKind.passwordRequired ||
    ImportFailureKind.wrongPassword => l.exportsImportPasswordWrong,
  };

  StatementPasswordLabels _passwordLabels(AppLocalizations l) =>
      StatementPasswordLabels(
        title: l.exportsImportPasswordTitle,
        body: l.exportsImportPasswordBody,
        fieldLabel: l.exportsImportPasswordLabel,
        wrongHint: l.exportsImportPasswordWrong,
        confirm: l.commonActionContinue,
        cancel: l.commonActionCancel,
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final gold = ref.watch(entitlementStateProvider).isGold;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                ZSpacing.screen,
                ZSpacing.sm,
                ZSpacing.screen,
                ZSpacing.xl,
              ),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ImportRoundButton(
                    icon: Icons.chevron_left,
                    label: l.commonActionBackA11y,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(height: ZSpacing.lg),
                Semantics(
                  header: true,
                  child: Text(
                    l.importFlowTitle,
                    style: ZType.display.copyWith(color: c.text),
                  ),
                ),
                const SizedBox(height: ZSpacing.sm),
                Text(
                  l.importFlowSub,
                  style: ZType.body.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: ZSpacing.lg),
                if (!gold) ...[
                  ZBanner(
                    tone: ZBannerTone.info,
                    icon: Icons.workspace_premium_outlined,
                    message: l.exportsImportLockedBody,
                  ),
                  const SizedBox(height: ZSpacing.lg),
                ],
                if (_error != null) ...[
                  ZBanner(
                    tone: ZBannerTone.error,
                    message: _errorText(l, _error!),
                  ),
                  const SizedBox(height: ZSpacing.lg),
                ],
                _group(
                  l,
                  c,
                  ImportSourceGroup.egyptBanks,
                  l.importFlowGroupEgypt,
                ),
                _group(
                  l,
                  c,
                  ImportSourceGroup.onlineBanks,
                  l.importFlowGroupOnline,
                  howTo: true,
                ),
                _group(l, c, ImportSourceGroup.zaghlol, null),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: c.bg.withValues(alpha: 0.85),
                  child: Center(
                    child: Semantics(
                      liveRegion: true,
                      label: l.exportsImportParsing,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: ZSpacing.md),
                          Text(
                            l.exportsImportParsing,
                            style: ZType.body.copyWith(color: c.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _group(
    AppLocalizations l,
    ZColors c,
    ImportSourceGroup group,
    String? title, {
    bool howTo = false,
  }) {
    final items = [
      for (final s in importSources)
        if (s.group == group) s,
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                bottom: ZSpacing.sm,
                top: ZSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: ZType.titleSmall.copyWith(color: c.text),
                      ),
                    ),
                  ),
                  if (howTo)
                    Flexible(
                      child: InkWell(
                        onTap: _howTo,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: ZSpacing.minTarget,
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              l.importFlowHowTo,
                              textAlign: TextAlign.end,
                              style: ZType.label.copyWith(color: c.primary),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ZCard(
            padding: EdgeInsetsDirectional.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _row(l, c, items[i], divider: i < items.length - 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    AppLocalizations l,
    ZColors c,
    ImportSourceDef s, {
    required bool divider,
  }) {
    final (bg, fg) = importSourceTint(c, s.id);
    final badge = importSourceBadge(l, s.id);
    return ZListRow(
      title: importSourceName(l, s.id),
      subtitle: s.available
          ? importSourceSub(l, s)
          : '${importSourceSub(l, s)} · ${l.importFlowSoon}',
      leading: ExcludeSemantics(
        child: Container(
          width: 40,
          height: 40,
          alignment: AlignmentDirectional.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg.withValues(alpha: 0.18),
          ),
          child: badge == null
              ? Icon(Icons.description_outlined, size: 20, color: fg)
              : Text(
                  badge,
                  maxLines: 1,
                  style: ZType.caption.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
      showChevron: true,
      showDivider: divider,
      enabled: s.available,
      onTap: s.available ? () => _start(s) : null,
    );
  }
}

/// The white round button at the top corner (mockups 32 / 34).
class ImportRoundButton extends StatelessWidget {
  const ImportRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
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
        elevation: 1,
        shadowColor: c.shadow,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: ZSpacing.minTarget,
            height: ZSpacing.minTarget,
            child: Icon(icon, color: c.text),
          ),
        ),
      ),
    );
  }
}
