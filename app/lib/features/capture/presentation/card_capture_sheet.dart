// T-086 / S-62: per-card, per-channel capture switches (FR-CAP-01/02/04).
//
// A switch is a ignore rule (T-078) for (institution, last-4, channel);
// turning it on removes that rule. Turning the LAST available channel off
// asks "Stop tracking?" with Keep (default) / Delete N, Delete asks a second
// time, then a snackbar offers Undo (restores the switches only: deleted data
// stays deleted). A channel switched off for the whole institution (S-61) is
// shown off and cannot be switched on here; undo it in capture settings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart' show IgnoreRuleRow;
import '../../../core/db/daos/capture_controls_dao.dart' show IgnoreChannel;
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../application/ignore_rules.dart';
import 'capture_controls.dart';

/// Opens S-62 as a sheet. [cardName] is the label shown in the copy.
Future<void> showCardCaptureSheet(
  BuildContext context, {
  required String institutionCode,
  required String? last4,
  required String cardName,
}) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showZSheet<void>(
    context: context,
    title: l10n.captureCardControlsTitle(cardName),
    builder: (ctx) => CardCaptureControls(
      institutionCode: institutionCode,
      last4: last4,
      cardName: cardName,
      messenger: messenger,
    ),
  );
}

class CardCaptureControls extends ConsumerStatefulWidget {
  const CardCaptureControls({
    super.key,
    required this.institutionCode,
    required this.last4,
    required this.cardName,
    this.messenger,
  });

  final String institutionCode;
  final String? last4;
  final String cardName;

  /// Outlives the sheet, so the Undo snackbar can show after it closes.
  final ScaffoldMessengerState? messenger;

  @override
  ConsumerState<CardCaptureControls> createState() => _State();
}

class _State extends ConsumerState<CardCaptureControls> {
  bool _busy = false;
  bool _failed = false;

  List<String> _channels(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.iOS
      ? const [IgnoreChannel.sms, IgnoreChannel.applePay]
      : const [IgnoreChannel.sms, IgnoreChannel.notification];

  IgnoreTarget _target(String channel) => IgnoreTarget(
    institutionCode: widget.institutionCode,
    last4: widget.last4,
    channel: channel,
  );

  IgnoreRuleRow? _cardRule(List<IgnoreRuleRow> rules, String channel) {
    for (final r in rules) {
      if (r.institutionCode == widget.institutionCode &&
          r.last4 == widget.last4 &&
          r.channel == channel) {
        return r;
      }
    }
    return null;
  }

  bool _instOff(List<IgnoreRuleRow> rules, String channel) =>
      widget.last4 != null &&
      rules.any(
        (r) =>
            r.institutionCode == widget.institutionCode &&
            r.last4 == null &&
            r.channel == channel,
      );

  bool _isOn(List<IgnoreRuleRow> rules, String channel) =>
      _cardRule(rules, channel) == null && !_instOff(rules, channel);

  Future<void> _toggle(
    String channel,
    bool on,
    List<IgnoreRuleRow> rules,
    List<String> channels,
  ) async {
    if (_busy) return;
    final controls = await ref.read(captureControlsProvider.future);
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (on) {
        final rule = _cardRule(rules, channel);
        if (rule != null) await controls.remove(rule.id);
        return;
      }
      final othersOn = channels.where((c) => c != channel && _isOn(rules, c));
      if (othersOn.isNotEmpty) {
        await controls.add(_target(channel));
        return;
      }
      await _stopTracking(controls, channel, channels);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopTracking(
    CaptureControls controls,
    String channel,
    List<String> channels,
  ) async {
    final l10n = AppLocalizations.of(context);
    final previews = {
      for (final c in channels) c: await controls.preview(_target(c)),
    };
    final count = {for (final p in previews.values) ...p.ids}.length;
    if (!mounted) return;
    final choice = await showDialog<_Existing>(
      context: context,
      builder: (_) => _StopDialog(card: widget.cardName, count: count),
    );
    if (choice == null || !mounted) return;
    if (choice == _Existing.delete) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (_) => _DeleteSureDialog(count: count),
      );
      if (sure != true || !mounted) return;
    }
    final created = <String>[];
    final messenger = widget.messenger ?? ScaffoldMessenger.maybeOf(context);
    // The channel just switched first, then the ones already off, so a
    // delete covers every channel's transactions.
    final order = [channel, ...channels.where((c) => c != channel)];
    for (final c in order) {
      final r = await controls.add(
        _target(c),
        existing: choice == _Existing.delete
            ? DeleteExisting(confirmedIds: previews[c]!.ids.toSet())
            : const KeepExisting(),
      );
      if (r.created) created.add(r.ruleId);
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(l10n.captureStopTrackingDone(widget.cardName)),
        action: SnackBarAction(
          label: l10n.commonActionUndo,
          onPressed: () async {
            for (final id in created) {
              try {
                await controls.remove(id);
              } on Object {
                // Already removed elsewhere: nothing to restore.
              }
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final channels = _channels(context);
    final rulesAsync = ref.watch(ignoreRulesStreamProvider);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;

    String title(String ch) => switch (ch) {
      IgnoreChannel.sms => l10n.commonChannelSms,
      IgnoreChannel.notification => l10n.commonChannelNotifications,
      _ => l10n.commonChannelApplePay,
    };
    String? sub(String ch) => switch (ch) {
      IgnoreChannel.sms when ios => l10n.captureCardControlsSmsIos,
      IgnoreChannel.applePay => l10n.captureCardControlsApplePaySub,
      _ => null,
    };

    return rulesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsetsDirectional.all(ZSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.xl),
        child: Column(
          children: [
            ZBanner(
              message: l10n.commonErrorLoadFailed,
              tone: ZBannerTone.error,
            ),
            ZButton(
              label: l10n.commonActionTryAgain,
              variant: ZButtonVariant.text,
              onPressed: () => ref.invalidate(ignoreRulesStreamProvider),
            ),
          ],
        ),
      ),
      data: (rules) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.captureCardControlsSubtitle,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.sm),
          if (_failed)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
              child: ZBanner(
                key: const Key('capture-card-error'),
                message: l10n.commonErrorSaveFailed,
                tone: ZBannerTone.error,
              ),
            ),
          for (final ch in channels)
            SwitchListTile(
              key: Key('capture-card-$ch'),
              contentPadding: EdgeInsets.zero,
              title: Text(title(ch), style: ZType.titleSmall),
              subtitle: sub(ch) == null ? null : Text(sub(ch)!),
              value: _isOn(rules, ch),
              onChanged:
                  _busy || (_instOff(rules, ch) && _cardRule(rules, ch) == null)
                  ? null
                  : (v) => _toggle(ch, v, rules, channels),
            ),
          const SizedBox(height: ZSpacing.sm),
          Text(
            l10n.captureCardControlsInfo,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.lg),
          ZButton(
            label: l10n.commonActionDone,
            expand: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: ZSpacing.lg),
        ],
      ),
    );
  }
}

enum _Existing { keep, delete }

class _StopDialog extends ConsumerStatefulWidget {
  const _StopDialog({required this.card, required this.count});

  final String card;
  final int count;

  @override
  ConsumerState<_StopDialog> createState() => _StopDialogState();
}

class _StopDialogState extends ConsumerState<_StopDialog> {
  _Existing _choice = _Existing.keep;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    return AlertDialog(
      title: Text(l10n.captureStopTrackingTitle(widget.card)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.count > 0) ...[
              Text(l10n.captureStopTrackingExisting),
              RadioGroup<_Existing>(
                groupValue: _choice,
                onChanged: (v) => setState(() => _choice = v ?? _choice),
                child: Column(
                  children: [
                    RadioListTile<_Existing>(
                      key: const Key('stop-keep'),
                      contentPadding: EdgeInsets.zero,
                      value: _Existing.keep,
                      title: Text(l10n.captureStopTrackingKeep),
                    ),
                    RadioListTile<_Existing>(
                      key: const Key('stop-delete'),
                      contentPadding: EdgeInsets.zero,
                      value: _Existing.delete,
                      title: Text(
                        l10n.captureStopTrackingDelete(
                          widget.count,
                          digits.render('${widget.count}'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonActionCancel),
        ),
        TextButton(
          key: const Key('stop-confirm'),
          onPressed: () => Navigator.of(context).pop(_choice),
          child: Text(l10n.captureStopTrackingConfirm),
        ),
      ],
    );
  }
}

class _DeleteSureDialog extends ConsumerWidget {
  const _DeleteSureDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final c = ZColors.of(context);
    return AlertDialog(
      title: Text(
        l10n.captureStopTrackingDeleteTitle(count, digits.render('$count')),
      ),
      content: Text(l10n.captureStopTrackingDeleteBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonActionCancel),
        ),
        TextButton(
          key: const Key('stop-delete-confirm'),
          style: TextButton.styleFrom(foregroundColor: c.dangerText),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.captureStopTrackingDeleteConfirm),
        ),
      ],
    );
  }
}
