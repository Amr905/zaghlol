// T-067: S-03 iOS capture setup. Step 1 adds the Shortcut (T-064 install),
// step 2 checks the automations per row with fix instructions (the Wallet
// row is only flagged for users who captured an Apple Pay payment, PO
// decision on T-064), step 3 logs a first expense by voice or typing.
// Skip at any step hands the step slug to the caller (FR-ONB-11).
// Times and counts only: nothing here shows or logs a message or amount.
// The install-guide images are a PO input (FU-212): a placeholder box stands
// in, with no image asset.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_banner.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import '../../capture/application/ios_shortcut_providers.dart';
import '../../capture/domain/ios_shortcut_checker.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';

/// Setup step slug recorded when the user skips (FR-ONB-11).
const String kSetupStepIosShortcuts = 'ios_shortcuts';

enum _Step { add, check, first }

enum _Row { smsAr, smsEn, applePay }

class IosSetupScreen extends ConsumerStatefulWidget {
  const IosSetupScreen({
    super.key,
    required this.onDone,
    this.onSkipped,
    this.onSay,
    this.onType,
    this.onOnlineBanks,
  });

  /// Setup finished -> Home.
  final VoidCallback onDone;

  /// The user skipped [slug]; the caller records it for "Finish setup" and
  /// leaves to Home. Null: Skip just calls [onDone].
  final void Function(String slug)? onSkipped;

  /// "Say it" (S-31) and "Type it" (S-13); a button is hidden while null.
  final VoidCallback? onSay;
  final VoidCallback? onType;

  /// "Use Wise, Revolut or Payoneer?" -> per-bank help (S-61).
  final VoidCallback? onOnlineBanks;

  @override
  ConsumerState<IosSetupScreen> createState() => _IosSetupState();
}

class _IosSetupState extends ConsumerState<IosSetupScreen>
    with WidgetsBindingObserver {
  _Step _step = _Step.add;
  bool _openedInstall = false;
  bool _installFailed = false;
  bool _howOpen = false;
  _Row? _fixing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Returning from Shortcuts runs the checker (S-03 interactions).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _openedInstall &&
        _step == _Step.add) {
      _openedInstall = false;
      _goCheck();
    }
  }

  void _goCheck() {
    ref.invalidate(shortcutSetupReportProvider);
    setState(() => _step = _Step.check);
  }

  Future<void> _install() async {
    setState(() => _installFailed = false);
    try {
      await ref.read(installShortcutProvider)();
      _openedInstall = true;
    } on Object {
      if (mounted) setState(() => _installFailed = true);
    }
  }

  void _skip() {
    final slug = kSetupStepIosShortcuts;
    if (widget.onSkipped != null) {
      widget.onSkipped!(slug);
    } else {
      widget.onDone();
    }
  }

  String _digits(String s) {
    final lang = Localizations.localeOf(context).languageCode;
    return ref.read(digitsModeProvider(lang)).render(s);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final stepNo = _step.index + 1;
    final body = switch (_step) {
      _Step.add => _addStep(l, c),
      _Step.check => _checkStep(l, c),
      _Step.first => _firstStep(l, c),
    };
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                ZSpacing.screen,
                ZSpacing.sm,
                ZSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.onboardingIosSetupStep(
                        _digits('$stepNo'),
                        _digits('3'),
                      ),
                      style: ZType.label.copyWith(color: c.textMuted),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: ZSpacing.minTarget,
                      minWidth: ZSpacing.minTarget,
                    ),
                    child: TextButton(
                      key: const ValueKey('ios-setup-skip'),
                      onPressed: _skip,
                      child: Text(l.commonActionSkip),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mascot(ZaghlolMoment m) => Center(
    child: ExcludeSemantics(child: ZaghlolAvatar(moment: m, size: 120)),
  );

  Widget _bullet(String title, String sub, ZColors c) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(Icons.check_circle_outline, color: c.primary, size: 20),
        ),
        const SizedBox(width: ZSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: ZType.label.copyWith(color: c.text)),
              Text(sub, style: ZType.bodySmall.copyWith(color: c.textMuted)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _addStep(AppLocalizations l, ZColors c) => Column(
    key: const ValueKey('ios-setup-add'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _mascot(ZaghlolMoment.tourGuide),
      const SizedBox(height: ZSpacing.lg),
      Text(
        l.onboardingIosSetupShortcutTitle,
        style: ZType.headline.copyWith(color: c.text),
      ),
      const SizedBox(height: ZSpacing.sm),
      Text(
        l.onboardingIosSetupShortcutWhy,
        style: ZType.body.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: ZSpacing.lg),
      Text(
        l.onboardingIosSetupShortcutLead,
        style: ZType.label.copyWith(color: c.text),
      ),
      const SizedBox(height: ZSpacing.sm),
      _bullet(
        l.onboardingIosSetupShortcutSmsTitle,
        l.onboardingIosSetupShortcutSmsSub,
        c,
      ),
      _bullet(
        l.onboardingIosSetupShortcutApplePayTitle,
        l.onboardingIosSetupShortcutApplePaySub,
        c,
      ),
      Text(
        l.onboardingIosSetupShortcutOnce,
        style: ZType.bodySmall.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: ZSpacing.lg),
      if (_installFailed) ...[
        ZBanner(
          key: const ValueKey('ios-setup-install-failed'),
          message: l.onboardingIosSetupShortcutsMissing,
          tone: ZBannerTone.warning,
        ),
        const SizedBox(height: ZSpacing.md),
      ],
      ZButton(
        key: const ValueKey('ios-setup-install'),
        label: l.onboardingIosSetupShortcutAdd,
        expand: true,
        onPressed: () => unawaited(_install()),
      ),
      const SizedBox(height: ZSpacing.sm),
      _howItWorks(l, c),
      ZButton(
        key: const ValueKey('ios-setup-to-check'),
        label: l.commonActionContinue,
        variant: ZButtonVariant.text,
        expand: true,
        onPressed: _goCheck,
      ),
    ],
  );

  Widget _howItWorks(AppLocalizations l, ZColors c) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        button: true,
        expanded: _howOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: InkWell(
            key: const ValueKey('ios-setup-how'),
            onTap: () => setState(() => _howOpen = !_howOpen),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.onboardingIosSetupHowItWorks,
                    style: ZType.label.copyWith(color: c.primary),
                  ),
                ),
                ExcludeSemantics(
                  child: Icon(
                    _howOpen ? Icons.expand_less : Icons.expand_more,
                    color: c.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (_howOpen) ...[
        // Placeholder for the install-guide images (FU-212, PO input).
        Container(
          key: const ValueKey('ios-setup-how-placeholder'),
          height: 120,
          margin: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(ZRadius.card),
            border: Border.all(color: c.outline),
          ),
        ),
        for (final (i, t) in [
          l.onboardingIosSetupHowStep1,
          l.onboardingIosSetupHowStep2,
          l.onboardingIosSetupHowStep3,
        ].indexed)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.xs),
            child: Text(
              '${_digits('${i + 1}')}. $t',
              style: ZType.bodySmall.copyWith(color: c.text),
            ),
          ),
      ],
    ],
  );

  /// Rows the check shows. The Wallet row is a problem only after an Apple
  /// Pay payment was captured; before that it counts as fine.
  bool _rowOk(_Row r, ShortcutSetupReport rep) => switch (r) {
    _Row.smsAr || _Row.smsEn => !rep.message.flagged,
    _Row.applePay => rep.wallet.neverRan || !rep.wallet.flagged,
  };

  Widget _checkStep(AppLocalizations l, ZColors c) {
    final report = ref.watch(shortcutSetupReportProvider);
    return Column(
      key: const ValueKey('ios-setup-check'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mascot(ZaghlolMoment.detective),
        const SizedBox(height: ZSpacing.lg),
        Text(
          l.onboardingIosSetupCheckTitle,
          style: ZType.headline.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.sm),
        Text(
          l.onboardingIosSetupCheckSubtitle,
          style: ZType.body.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: ZSpacing.lg),
        if (report.isLoading)
          Semantics(
            liveRegion: true,
            child: Column(
              key: const ValueKey('ios-setup-checking'),
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: ZSpacing.sm),
                Text(
                  l.onboardingIosSetupChecking,
                  style: ZType.bodySmall.copyWith(color: c.textMuted),
                ),
              ],
            ),
          )
        else if (report.value == null)
          // Cannot tell: never shown as a failure.
          ZBanner(
            key: const ValueKey('ios-setup-unknown'),
            message: l.onboardingIosSetupCheckUnknown,
            tone: ZBannerTone.info,
          )
        else
          ..._rows(l, c, report.value!),
        const SizedBox(height: ZSpacing.lg),
        if (!report.isLoading)
          ZButton(
            key: const ValueKey('ios-setup-recheck'),
            label: l.onboardingIosSetupCheckAgain,
            variant: ZButtonVariant.secondary,
            expand: true,
            onPressed: () {
              setState(() => _fixing = null);
              ref.invalidate(shortcutSetupReportProvider);
            },
          ),
        const SizedBox(height: ZSpacing.sm),
        ZButton(
          key: const ValueKey('ios-setup-to-first'),
          label: l.commonActionContinue,
          expand: true,
          onPressed: () => setState(() => _step = _Step.first),
        ),
      ],
    );
  }

  List<Widget> _rows(AppLocalizations l, ZColors c, ShortcutSetupReport rep) {
    final names = {
      _Row.smsAr: l.onboardingIosSetupCheckSmsAr,
      _Row.smsEn: l.onboardingIosSetupCheckSmsEn,
      _Row.applePay: l.onboardingIosSetupCheckApplePay,
    };
    final done = _Row.values.where((r) => _rowOk(r, rep)).length;
    return [
      Semantics(
        liveRegion: true,
        child: Text(
          rep.allOk
              ? l.onboardingIosSetupCheckAllGood
              : l.onboardingIosSetupCheckCount(
                  _Row.values.length,
                  _digits('$done'),
                  _digits('${_Row.values.length}'),
                ),
          key: const ValueKey('ios-setup-count'),
          style: ZType.label.copyWith(color: c.text),
        ),
      ),
      const SizedBox(height: ZSpacing.sm),
      for (final r in _Row.values) ...[
        _rowTile(l, c, r, names[r]!, ok: _rowOk(r, rep)),
        const SizedBox(height: ZSpacing.sm),
      ],
    ];
  }

  Widget _rowTile(
    AppLocalizations l,
    ZColors c,
    _Row r,
    String name, {
    required bool ok,
  }) {
    final fixing = _fixing == r && !ok;
    return ZCard(
      key: ValueKey('ios-setup-row-${r.name}'),
      padding: const EdgeInsetsDirectional.all(ZSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                label: ok
                    ? l.onboardingIosSetupCheckOkA11y
                    : l.onboardingIosSetupCheckMissingA11y,
                excludeSemantics: true,
                child: Icon(
                  ok ? Icons.check_circle : Icons.error_outline,
                  color: ok ? c.primary : c.text,
                ),
              ),
              const SizedBox(width: ZSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: ZType.label.copyWith(color: c.text)),
                    if (!ok)
                      Text(
                        l.onboardingIosSetupCheckNeedsRun,
                        style: ZType.bodySmall.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
              if (!ok)
                ZButton(
                  key: ValueKey('ios-setup-fix-${r.name}'),
                  label: l.commonActionFix,
                  variant: ZButtonVariant.text,
                  onPressed: () => setState(() => _fixing = fixing ? null : r),
                ),
            ],
          ),
          if (fixing) ...[
            const SizedBox(height: ZSpacing.sm),
            Text(
              l.onboardingIosSetupFixTitle,
              style: ZType.label.copyWith(color: c.text),
            ),
            for (final (i, t) in [
              l.onboardingIosSetupFixStep1,
              l.onboardingIosSetupFixStep2(name),
              l.onboardingIosSetupFixStep3,
            ].indexed)
              Text(
                '${_digits('${i + 1}')}. $t',
                style: ZType.bodySmall.copyWith(color: c.text),
              ),
          ],
        ],
      ),
    );
  }

  Widget _firstStep(AppLocalizations l, ZColors c) => Column(
    key: const ValueKey('ios-setup-first'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _mascot(ZaghlolMoment.listening),
      const SizedBox(height: ZSpacing.lg),
      Text(
        l.onboardingIosSetupFirstTitle,
        style: ZType.headline.copyWith(color: c.text),
      ),
      const SizedBox(height: ZSpacing.sm),
      Text(
        l.onboardingIosSetupFirstBody,
        style: ZType.body.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: ZSpacing.lg),
      if (widget.onSay != null)
        _entry(
          const ValueKey('ios-setup-say'),
          Icons.mic_none,
          l.onboardingIosSetupFirstSay,
          l.onboardingIosSetupFirstSayHint,
          widget.onSay!,
          c,
        ),
      if (widget.onType != null)
        _entry(
          const ValueKey('ios-setup-type'),
          Icons.edit_outlined,
          l.onboardingIosSetupFirstType,
          l.onboardingIosSetupFirstTypeHint,
          widget.onType!,
          c,
        ),
      if (widget.onOnlineBanks != null)
        ZCard(
          key: const ValueKey('ios-setup-online-banks'),
          onTap: widget.onOnlineBanks,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.onboardingIosSetupFirstOnlineBanks,
                      style: ZType.label.copyWith(color: c.text),
                    ),
                    Text(
                      l.onboardingIosSetupFirstOnlineBanksSub,
                      style: ZType.bodySmall.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
              ),
              ExcludeSemantics(
                child: Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left
                      : Icons.chevron_right,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: ZSpacing.lg),
      ZButton(
        key: const ValueKey('ios-setup-done'),
        label: l.commonActionDone,
        expand: true,
        onPressed: widget.onDone,
      ),
    ],
  );

  Widget _entry(
    Key key,
    IconData icon,
    String title,
    String hint,
    VoidCallback onTap,
    ZColors c,
  ) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
    child: ZCard(
      key: key,
      onTap: onTap,
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, color: c.primary)),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ZType.label.copyWith(color: c.text)),
                Text(hint, style: ZType.bodySmall.copyWith(color: c.textMuted)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
