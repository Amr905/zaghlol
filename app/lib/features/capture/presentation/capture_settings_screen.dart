// T-086 / S-61: capture settings. Sources, "Not tracked" (ignore rules, one
// tap Undo), tools (re-scan, supported banks, request a bank, templates).
//
// Everything is read through providers; rule writes go through
// `CaptureControls` (T-078 `IgnoreRulesService`), which rewrites the Guard
// config before it returns, so a toggle is in force at once (BR-CAP-01).
// Un-ignoring an SMS rule on Android offers a re-scan of that institution
// (BR-CAP-04); nothing is scanned without the user's yes.
//
// Not built here, for lack of copy-deck keys (see the task file): the
// consent line and "scan the last 3 months" opt-in for user-added
// phone-number senders (FU-109), and the Settings key for it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart' show IgnoreRuleRow;
import '../../../core/db/daos/capture_controls_dao.dart' show IgnoreChannel;
import '../../../core/l10n/digits_mode.dart' show normalizeDigits;
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../accounts/presentation/edit_card/edit_card_providers.dart'
    show InstitutionOption, institutionOptionsProvider;
import '../application/capture_providers.dart';
import '../application/ignore_rules.dart';
import '../application/ios_setup_providers.dart';
import '../domain/capture_health.dart';
import '../domain/scan_plan.dart';
import 'capture_controls.dart';

/// iOS setup checker result (FR-ING-I-07): true = passes, false = failed,
/// null = cannot tell. From the silence check (T-066, `iosSetupStatusProvider`).
final iosSetupCheckProvider = Provider<bool?>(
  (ref) => ref.watch(iosSetupStatusProvider).passes,
  name: 'iosSetupCheckProvider',
);

/// Channels each bank is read from, by registry code (SMS senders, packages).
final bankChannelsProvider = Provider<Map<String, Set<String>>>((ref) {
  try {
    final registry = ref.watch(captureRegistryLoaderProvider)();
    return {
      for (final i in registry.institutions)
        i.code: {
          if (i.senders.isNotEmpty) IgnoreChannel.sms,
          if (i.packages.isNotEmpty) IgnoreChannel.notification,
        },
    };
  } on Object {
    return const {};
  }
}, name: 'bankChannelsProvider');

/// The scan depths A-11 offers.
const List<int> kRescanDepths = [6, 12, 18, 24];

class CaptureSettingsScreen extends ConsumerWidget {
  const CaptureSettingsScreen({
    super.key,
    this.goldActive = false,
    this.onFix,
    this.onCheckSetup,
    this.onRequestBank,
    this.onOpenTemplates,
  });

  /// Custom templates are Gold: Free opens the paywall through
  /// [onOpenTemplates] too (the shell decides the target).
  final bool goldActive;

  /// `common_action_fix`: the shell opens the OS permission flow.
  final void Function(CaptureChannel channel)? onFix;
  final VoidCallback? onCheckSetup;
  final VoidCallback? onRequestBank;
  final VoidCallback? onOpenTemplates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final health = ref.watch(captureHealthProvider);
    final controls = ref.watch(captureControlsProvider);
    final rules = ref.watch(ignoreRulesStreamProvider);
    final banks = ref.watch(institutionOptionsProvider);

    Widget body;
    if (controls.hasError || rules.hasError) {
      body = _Retry(
        onRetry: () {
          ref.invalidate(captureControlsProvider);
          ref.invalidate(ignoreRulesStreamProvider);
        },
      );
    } else if (!controls.hasValue || !rules.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _Body(
        health: health,
        controls: controls.requireValue,
        groups: groupIgnoreRules(rules.requireValue),
        banks: banks,
        ios: ios,
        goldActive: goldActive,
        onFix: onFix,
        onCheckSetup: onCheckSetup,
        onRequestBank: onRequestBank,
        onOpenTemplates: onOpenTemplates,
      );
    }
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(l10n.captureSettingsTitle)),
      body: body,
    );
  }
}

/// One row of "Not tracked": a card (last-4 set) or a whole institution.
final class IgnoreGroup {
  const IgnoreGroup({
    required this.institutionCode,
    required this.last4,
    required this.rules,
  });

  final String institutionCode;
  final String? last4;
  final List<IgnoreRuleRow> rules;

  Set<String> get channels => {for (final r in rules) r.channel};
}

List<IgnoreGroup> groupIgnoreRules(List<IgnoreRuleRow> rules) {
  final map = <(String, String?), List<IgnoreRuleRow>>{};
  for (final r in rules) {
    map.putIfAbsent((r.institutionCode, r.last4), () => []).add(r);
  }
  return [
    for (final e in map.entries)
      IgnoreGroup(institutionCode: e.key.$1, last4: e.key.$2, rules: e.value),
  ];
}

String _channelShort(AppLocalizations l10n, String channel) =>
    switch (channel) {
      IgnoreChannel.sms => l10n.commonChannelSmsShort,
      IgnoreChannel.notification => l10n.commonChannelNotificationsShort,
      _ => l10n.commonChannelApplePay,
    };

String _join(BuildContext context, List<String> parts) => parts.join(
  Localizations.localeOf(context).languageCode == 'ar' ? '، ' : ', ',
);

String _bankName(List<InstitutionOption> banks, String code, String lang) {
  for (final b in banks) {
    if (b.code == code) return b.name(lang);
  }
  return code;
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      child: Column(
        children: [
          ZBanner(
            key: const Key('capture-settings-error'),
            message: l10n.commonErrorLoadFailed,
            tone: ZBannerTone.error,
          ),
          ZButton(
            label: l10n.commonActionTryAgain,
            variant: ZButtonVariant.text,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            top: ZSpacing.lg,
            bottom: ZSpacing.sm,
          ),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: ZType.titleSmall.copyWith(color: c.textMuted),
            ),
          ),
        ),
        ZCard(
          padding: EdgeInsetsDirectional.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.health,
    required this.controls,
    required this.groups,
    required this.banks,
    required this.ios,
    required this.goldActive,
    this.onFix,
    this.onCheckSetup,
    this.onRequestBank,
    this.onOpenTemplates,
  });

  final CaptureHealth health;
  final CaptureControls controls;
  final List<IgnoreGroup> groups;
  final List<InstitutionOption> banks;
  final bool ios;
  final bool goldActive;
  final void Function(CaptureChannel channel)? onFix;
  final VoidCallback? onCheckSetup;
  final VoidCallback? onRequestBank;
  final VoidCallback? onOpenTemplates;

  Widget _status(
    BuildContext context,
    AppLocalizations l10n,
    ChannelState? state,
    CaptureChannel channel,
  ) {
    final c = ZColors.of(context);
    final on = state == ChannelState.active;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          on ? Icons.check_rounded : Icons.close_rounded,
          size: 18,
          color: on ? c.primary : c.textMuted,
        ),
        const SizedBox(width: ZSpacing.xs),
        Text(
          on ? l10n.captureSettingsOn : l10n.captureSettingsOff,
          style: ZType.label.copyWith(color: c.text),
        ),
        if (state == ChannelState.offPermission && onFix != null)
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(ZSpacing.minTarget, ZSpacing.minTarget),
            ),
            onPressed: () => onFix!(channel),
            child: Text(l10n.commonActionFix),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final smsState = health.channels[CaptureChannel.smsLive];
    final notifState = health.channels[CaptureChannel.notifications];
    final iosCheck = ref.watch(iosSetupCheckProvider);

    final sources = <Widget>[
      if (ios) ...[
        ZListRow(
          title: l10n.commonChannelSms,
          subtitle: l10n.captureSettingsSmsIos,
          trailing: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(ZSpacing.minTarget, ZSpacing.minTarget),
            ),
            onPressed: onCheckSetup,
            child: Text(l10n.captureSettingsCheckSetup),
          ),
        ),
        ZListRow(
          key: const Key('capture-apple-pay'),
          title: l10n.commonChannelApplePay,
          subtitle: iosCheck == null ? l10n.captureSettingsUnknown : null,
          trailing: iosCheck == null
              ? TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      ZSpacing.minTarget,
                      ZSpacing.minTarget,
                    ),
                  ),
                  onPressed: onCheckSetup,
                  child: Text(l10n.captureSettingsCheckSetup),
                )
              : _status(
                  context,
                  l10n,
                  iosCheck ? ChannelState.active : ChannelState.offPermission,
                  CaptureChannel.sharePaste,
                ),
        ),
      ] else ...[
        if (smsState != null && smsState != ChannelState.unavailable)
          ZListRow(
            key: const Key('capture-sms'),
            title: l10n.commonChannelSms,
            trailing: _status(context, l10n, smsState, CaptureChannel.smsLive),
          ),
        ZListRow(
          key: const Key('capture-notifications'),
          title: l10n.commonChannelNotifications,
          trailing: _status(
            context,
            l10n,
            notifState,
            CaptureChannel.notifications,
          ),
        ),
      ],
      ZListRow(
        key: const Key('capture-share'),
        title: l10n.captureSettingsShare,
        showChevron: true,
        onTap: () => showShareHowSheet(context),
      ),
    ];

    final notTracked = groups.isEmpty
        ? [
            Padding(
              padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
              child: Text(
                l10n.captureSettingsNotTrackedEmpty,
                key: const Key('capture-not-tracked-empty'),
                style: ZType.body,
              ),
            ),
          ]
        : [
            for (final g in groups)
              _IgnoredRow(
                group: g,
                banks: banks,
                controls: controls,
                lang: lang,
              ),
          ];

    return ListView(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      children: [
        if (health.issues.contains(CaptureIssue.unreadable))
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
            child: ZBanner(
              key: const Key('capture-unreadable'),
              message: l10n.captureSettingsUnreadable,
              tone: ZBannerTone.warning,
              actionLabel: controls.canRescan ? l10n.captureRescanTitle : null,
              onAction: controls.canRescan
                  ? () => showRescanSheet(context, controls)
                  : null,
            ),
          ),
        _Section(l10n.captureSettingsSources, sources),
        _Section(l10n.captureSettingsNotTracked, [
          ...notTracked,
          ZListRow(
            key: const Key('capture-add-ignore'),
            title: l10n.captureSettingsAddIgnore,
            leading: const Icon(Icons.add_rounded),
            onTap: () => showAddIgnoreSheet(context, controls, banks, ios),
          ),
        ]),
        _Section(l10n.captureSettingsTools, [
          if (!ios && controls.canRescan)
            ZListRow(
              key: const Key('capture-rescan'),
              title: l10n.captureSettingsRescan,
              showChevron: true,
              onTap: () => showRescanSheet(context, controls),
            ),
          ZListRow(
            key: const Key('capture-banks'),
            title: l10n.captureSettingsBanks,
            showChevron: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SupportedBanksScreen(ios: ios),
              ),
            ),
          ),
          ZListRow(
            key: const Key('capture-request-bank'),
            title: l10n.captureSettingsRequestBank,
            showChevron: true,
            onTap: onRequestBank,
          ),
          ZListRow(
            key: const Key('capture-templates'),
            title: l10n.captureSettingsTemplates,
            trailing: goldActive
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        size: 18,
                        color: ZColors.of(context).accentDark,
                      ),
                      const SizedBox(width: ZSpacing.xs),
                      Text(l10n.commonGoldBadge, style: ZType.label),
                    ],
                  ),
            showChevron: true,
            onTap: onOpenTemplates,
          ),
        ]),
        const SizedBox(height: ZSpacing.xl),
      ],
    );
  }
}

class _IgnoredRow extends ConsumerWidget {
  const _IgnoredRow({
    required this.group,
    required this.banks,
    required this.controls,
    required this.lang,
  });

  final IgnoreGroup group;
  final List<InstitutionOption> banks;
  final CaptureControls controls;
  final String lang;

  Future<void> _undo(BuildContext context, String name) async {
    final l10n = AppLocalizations.of(context);
    // The row disappears once its rules are gone, so keep the navigator.
    final nav = Navigator.of(context);
    RescanOffer? offer;
    try {
      for (final r in group.rules) {
        final res = await controls.remove(r.id);
        offer ??= res.rescanOffer;
      }
    } on Object {
      // A rule another engine already removed: the list refreshes itself.
    }
    if (offer != null && nav.mounted) {
      final yes = await showDialog<bool>(
        context: nav.context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.captureRescanOfferTitle(name)),
          content: Text(l10n.captureRescanOfferBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.commonActionCancel),
            ),
            TextButton(
              key: const Key('rescan-offer-yes'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.captureRescanOfferYes),
            ),
          ],
        ),
      );
      if (yes == true) {
        unawaited(
          controls.rescan(
            depthMonths: kDefaultScanDepthMonths,
            institutionCode: offer.institutionCode,
          ),
        );
      }
    }
  }

  String _title(String Function(String) render) {
    final bank = _bankName(banks, group.institutionCode, lang);
    return group.last4 == null ? bank : '$bank •${render(group.last4!)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final digits = ref.watch(digitsModeProvider(lang));
    final channels = _join(context, [
      for (final ch in [
        IgnoreChannel.sms,
        IgnoreChannel.notification,
        IgnoreChannel.applePay,
      ])
        if (group.channels.contains(ch)) _channelShort(l10n, ch),
    ]);
    return ZListRow(
      key: Key('ignored-${group.institutionCode}-${group.last4 ?? 'all'}'),
      leading: const Icon(Icons.visibility_off_outlined),
      title: _title(digits.render),
      subtitle: l10n.captureSettingsIgnoredChannels(channels),
      trailing: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(ZSpacing.minTarget, ZSpacing.minTarget),
        ),
        onPressed: () => _undo(context, _title(digits.render)),
        child: Text(l10n.commonActionUndo),
      ),
    );
  }
}

/// Share / paste how-to (`capture_shareHow_*`).
Future<void> showShareHowSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showZSheet<void>(
    context: context,
    title: l10n.captureShareHowTitle,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in [
          l10n.captureShareHowStep1,
          l10n.captureShareHowStep2,
          l10n.captureShareHowStep3,
        ])
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
            child: Text(s, style: ZType.body),
          ),
        Text(
          l10n.captureShareHowNote,
          style: ZType.bodySmall.copyWith(color: ZColors.of(ctx).textMuted),
        ),
        const SizedBox(height: ZSpacing.lg),
      ],
    ),
  );
}

/// "Don't track a card or bank" (FR-CAP-03).
Future<void> showAddIgnoreSheet(
  BuildContext context,
  CaptureControls controls,
  List<InstitutionOption> banks,
  bool ios,
) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showZSheet<void>(
    context: context,
    title: l10n.captureIgnoreTitle,
    builder: (ctx) => AddIgnoreForm(
      controls: controls,
      banks: banks,
      ios: ios,
      messenger: messenger,
    ),
  );
}

class AddIgnoreForm extends ConsumerStatefulWidget {
  const AddIgnoreForm({
    super.key,
    required this.controls,
    required this.banks,
    required this.ios,
    this.messenger,
  });

  final CaptureControls controls;
  final List<InstitutionOption> banks;
  final bool ios;
  final ScaffoldMessengerState? messenger;

  @override
  ConsumerState<AddIgnoreForm> createState() => _AddIgnoreFormState();
}

class _AddIgnoreFormState extends ConsumerState<AddIgnoreForm> {
  String? _bank;
  final _last4 = TextEditingController();
  final Set<String> _channels = {};
  bool _touched = false;
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _last4.dispose();
    super.dispose();
  }

  String get _digits => normalizeDigits(_last4.text.trim());
  bool get _last4Ok =>
      _digits.isEmpty || RegExp(r'^[0-9]{4}$').hasMatch(_digits);
  bool get _valid => _bank != null && _channels.isNotEmpty && _last4Ok;

  Future<void> _save() async {
    setState(() {
      _touched = true;
      _failed = false;
    });
    if (!_valid) return;
    final l10n = AppLocalizations.of(context);
    final messenger = widget.messenger ?? ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    final created = <String>[];
    try {
      for (final ch in _channels) {
        final r = await widget.controls.add(
          IgnoreTarget(
            institutionCode: _bank!,
            last4: _digits.isEmpty ? null : _digits,
            channel: ch,
          ),
        );
        if (r.created) created.add(r.ruleId);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
      return;
    }
    nav.maybePop();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(l10n.captureIgnoreSaved),
        action: SnackBarAction(
          label: l10n.commonActionUndo,
          onPressed: () async {
            for (final id in created) {
              try {
                await widget.controls.remove(id);
              } on Object {
                // Already removed: nothing to undo.
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
    final lang = Localizations.localeOf(context).languageCode;
    final c = ZColors.of(context);
    final channels = widget.ios
        ? const [IgnoreChannel.sms, IgnoreChannel.applePay]
        : const [IgnoreChannel.sms, IgnoreChannel.notification];
    String label(String ch) => switch (ch) {
      IgnoreChannel.sms => l10n.commonChannelSms,
      IgnoreChannel.notification => l10n.commonChannelNotifications,
      _ => l10n.commonChannelApplePay,
    };
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_failed)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
              child: ZBanner(
                key: const Key('ignore-save-error'),
                message: l10n.commonErrorSaveFailed,
                tone: ZBannerTone.error,
              ),
            ),
          DropdownButtonFormField<String>(
            key: const Key('ignore-bank'),
            isExpanded: true,
            initialValue: _bank,
            decoration: InputDecoration(
              labelText: l10n.captureIgnoreBank,
              errorText: _touched && _bank == null
                  ? l10n.captureIgnoreErrorBank
                  : null,
            ),
            items: [
              for (final b in widget.banks)
                DropdownMenuItem(value: b.code, child: Text(b.name(lang))),
            ],
            onChanged: (v) => setState(() => _bank = v),
          ),
          const SizedBox(height: ZSpacing.md),
          TextField(
            key: const Key('ignore-last4'),
            controller: _last4,
            keyboardType: TextInputType.number,
            maxLength: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.captureIgnoreLast4,
              helperText: l10n.captureIgnoreLast4Hint,
              counterText: '',
              errorText: _touched && !_last4Ok
                  ? l10n.captureIgnoreErrorLast4
                  : null,
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          Text(l10n.captureIgnoreChannels, style: ZType.titleSmall),
          for (final ch in channels)
            CheckboxListTile(
              key: Key('ignore-ch-$ch'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(label(ch)),
              value: _channels.contains(ch),
              onChanged: (v) => setState(
                () => v == true ? _channels.add(ch) : _channels.remove(ch),
              ),
            ),
          if (_touched && _channels.isEmpty)
            Text(
              l10n.captureIgnoreErrorChannel,
              style: ZType.bodySmall.copyWith(color: c.dangerText),
            ),
          const SizedBox(height: ZSpacing.sm),
          Text(
            l10n.captureIgnorePrivacy,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.lg),
          ZButton(
            key: const Key('ignore-save'),
            label: l10n.commonActionDone,
            expand: true,
            loading: _saving,
            onPressed: _save,
          ),
          const SizedBox(height: ZSpacing.lg),
        ],
      ),
    );
  }
}

/// Re-scan sheet (FR-CAP-07): depth picker 6-24 months, progress, result.
Future<void> showRescanSheet(BuildContext context, CaptureControls controls) {
  final l10n = AppLocalizations.of(context);
  return showZSheet<void>(
    context: context,
    title: l10n.captureRescanTitle,
    builder: (ctx) => RescanPanel(controls: controls),
  );
}

class RescanPanel extends ConsumerStatefulWidget {
  const RescanPanel({super.key, required this.controls});

  final CaptureControls controls;

  @override
  ConsumerState<RescanPanel> createState() => _RescanPanelState();
}

enum _ScanUi { idle, running, done, failed }

class _RescanPanelState extends ConsumerState<RescanPanel> {
  int _depth = 6;
  _ScanUi _ui = _ScanUi.idle;
  int _found = 0;

  Future<void> _start() async {
    final run = widget.controls.rescan(depthMonths: _depth);
    if (run == null) return;
    setState(() {
      _ui = _ScanUi.running;
      _found = 0;
    });
    try {
      final p = await run;
      if (!mounted) return;
      setState(() {
        _found = p.imported;
        _ui = p.phase == ScanPhase.failed ? _ScanUi.failed : _ScanUi.done;
      });
    } on Object {
      if (mounted) setState(() => _ui = _ScanUi.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final c = ZColors.of(context);
    ref.listen(scanProgressProvider, (_, next) {
      final p = next.value;
      if (p != null && _ui == _ScanUi.running && mounted) {
        setState(() => _found = p.imported);
      }
    });
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_ui == _ScanUi.idle) ...[
          Text(l10n.captureRescanDepth, style: ZType.titleSmall),
          RadioGroup<int>(
            groupValue: _depth,
            onChanged: (v) => setState(() => _depth = v ?? _depth),
            child: Column(
              children: [
                for (final m in kRescanDepths)
                  RadioListTile<int>(
                    key: Key('rescan-depth-$m'),
                    contentPadding: EdgeInsets.zero,
                    value: m,
                    title: Text(
                      l10n.commonPeriodLastMonths(m, digits.render('$m')),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            l10n.captureRescanNoDuplicates,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.lg),
          ZButton(
            key: const Key('rescan-start'),
            label: l10n.captureRescanStart,
            expand: true,
            onPressed: _start,
          ),
        ] else if (_ui == _ScanUi.running) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: ZSpacing.md),
          Text(
            l10n.captureRescanRunning(_found, digits.render('$_found')),
            key: const Key('rescan-running'),
            style: ZType.body,
          ),
        ] else if (_ui == _ScanUi.done) ...[
          Text(
            l10n.captureRescanDone(_found, digits.render('$_found')),
            key: const Key('rescan-done'),
            style: ZType.body,
          ),
          const SizedBox(height: ZSpacing.lg),
          ZButton(
            label: l10n.commonActionDone,
            expand: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ] else ...[
          ZBanner(
            key: const Key('rescan-failed'),
            message: l10n.commonErrorLoadFailed,
            tone: ZBannerTone.error,
          ),
          ZButton(
            label: l10n.commonActionTryAgain,
            variant: ZButtonVariant.text,
            onPressed: () => setState(() => _ui = _ScanUi.idle),
          ),
        ],
        const SizedBox(height: ZSpacing.lg),
      ],
    );
  }
}

/// Supported banks (`capture_banks_*`): searchable, with how each is read.
class SupportedBanksScreen extends ConsumerStatefulWidget {
  const SupportedBanksScreen({super.key, required this.ios});

  final bool ios;

  @override
  ConsumerState<SupportedBanksScreen> createState() => _BanksState();
}

class _BanksState extends ConsumerState<SupportedBanksScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final banks = ref.watch(institutionOptionsProvider);
    final channels = ref.watch(bankChannelsProvider);
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final b in banks)
        if (q.isEmpty ||
            b.nameAr.toLowerCase().contains(q) ||
            b.nameEn.toLowerCase().contains(q))
          b,
    ];
    return Scaffold(
      backgroundColor: ZColors.of(context).bg,
      appBar: AppBar(title: Text(l10n.captureBanksTitle)),
      body: ListView(
        padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
        children: [
          TextField(
            key: const Key('banks-search'),
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: l10n.captureBanksSearch,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          if (shown.isEmpty)
            Text(
              l10n.captureBanksNoResults,
              key: const Key('banks-empty'),
              style: ZType.body,
            ),
          for (final b in shown)
            ZListRow(
              key: Key('bank-${b.code}'),
              title: b.name(lang),
              subtitle: widget.ios
                  ? l10n.captureBanksIosNote(b.name(lang))
                  : _bankChannels(context, l10n, channels[b.code]),
            ),
        ],
      ),
    );
  }

  String? _bankChannels(
    BuildContext context,
    AppLocalizations l10n,
    Set<String>? set,
  ) {
    if (set == null || set.isEmpty) return null;
    return l10n.captureBanksChannels(
      _join(context, [
        for (final ch in [IgnoreChannel.sms, IgnoreChannel.notification])
          if (set.contains(ch)) _channelShort(l10n, ch),
      ]),
    );
  }
}
