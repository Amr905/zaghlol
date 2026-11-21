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
import 'onboarding_parts.dart';

/// Setup step slug recorded when the user skips (FR-ONB-11).
const String kSetupStepIosShortcuts = 'ios_shortcuts';

/// Latin names of the automations the Shortcut creates (not translated).
const String _kWalletAutomation = 'Zaghlol – Wallet';
const String _kMessageAutomation = 'Zaghlol – Message';

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
    this.onStatement,
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

  /// "Have a statement?" (Gold import); the row is hidden while null.
  final VoidCallback? onStatement;

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
            OnbTopBar(
              step: stepNo,
              total: 3,
              stepLabel: l.onboardingIosSetupStep(
                _digits('$stepNo'),
                _digits('3'),
              ),
              skipLabel: l.commonActionSkip,
              skipKey: const ValueKey('ios-setup-skip'),
              onSkip: _skip,
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  /// One row of a white list card: tile, title + sub, trailing, divider.
  Widget _listCard(List<Widget> rows, ZColors c) => ZCard(
    padding: const EdgeInsetsDirectional.symmetric(vertical: ZSpacing.xs),
    child: Column(
      children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: c.outline,
              indent: ZSpacing.lg,
              endIndent: ZSpacing.lg,
            ),
          r,
        ],
      ],
    ),
  );

  Widget _listRow({
    Key? key,
    required IconData icon,
    required String title,
    String? sub,
    Widget? subLead,
    Widget? trailing,
    Color? tileBg,
    Color? tileFg,
    required ZColors c,
  }) => Padding(
    key: key,
    padding: const EdgeInsetsDirectional.symmetric(
      horizontal: ZSpacing.lg,
      vertical: ZSpacing.md,
    ),
    child: Row(
      children: [
        OnbIconTile(
          icon: icon,
          size: 40,
          radius: ZRadius.md,
          background: tileBg ?? c.primary,
          foreground: tileFg ?? c.onPrimary,
        ),
        const SizedBox(width: ZSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: ZType.label.copyWith(
                  color: c.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (sub != null)
                Row(
                  children: [
                    ?subLead,
                    Flexible(
                      child: Text(
                        sub,
                        style: ZType.caption.copyWith(color: c.textMuted),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: ZSpacing.md), trailing],
      ],
    ),
  );

  Widget _addStep(AppLocalizations l, ZColors c) => KeyedSubtree(
    key: const ValueKey('ios-setup-add'),
    child: OnbPage(
      content: [
        const OnbMascot(size: 150),
        const SizedBox(height: ZSpacing.xl),
        Text(
          l.onboardingIosSetupShortcutTitle,
          textAlign: TextAlign.center,
          style: ZType.headline.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.sm),
        Text(
          l.onboardingIosSetupShortcutLead,
          textAlign: TextAlign.center,
          style: ZType.body.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: ZSpacing.lg),
        _listCard([
          _listRow(
            icon: Icons.chat_bubble_outline,
            title: l.onboardingIosSetupShortcutSmsTitle,
            sub: l.onboardingIosSetupShortcutSmsSub,
            trailing: const OnbCheckDot(size: 24),
            c: c,
          ),
          _listRow(
            icon: Icons.credit_card,
            title: l.onboardingIosSetupShortcutApplePayTitle,
            sub: l.onboardingIosSetupShortcutApplePaySub,
            trailing: const OnbCheckDot(size: 24),
            c: c,
          ),
        ], c),
        const SizedBox(height: ZSpacing.md),
        Text(
          l.onboardingIosSetupShortcutOnce,
          textAlign: TextAlign.center,
          style: ZType.bodySmall.copyWith(color: c.textMuted),
        ),
        if (_installFailed) ...[
          const SizedBox(height: ZSpacing.md),
          ZBanner(
            key: const ValueKey('ios-setup-install-failed'),
            message: l.onboardingIosSetupShortcutsMissing,
            tone: ZBannerTone.warning,
          ),
        ],
      ],
      actions: [
        ZButton(
          key: const ValueKey('ios-setup-install'),
          label: l.onboardingIosSetupShortcutAdd,
          icon: Icons.add,
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
    ),
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
            child: Center(
              child: Text(
                l.onboardingIosSetupHowItWorks,
                textAlign: TextAlign.center,
                style: ZType.titleSmall.copyWith(color: c.primary),
              ),
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
    final rep = report.value;
    final loading = report.isLoading;
    return KeyedSubtree(
      key: const ValueKey('ios-setup-check'),
      child: OnbPage(
        content: [
          const SizedBox(height: ZSpacing.lg),
          Text(
            l.onboardingIosSetupCheckTitle,
            style: ZType.headline.copyWith(color: c.text),
          ),
          const SizedBox(height: ZSpacing.xs),
          Text(
            l.onboardingIosSetupCheckSubtitle,
            style: ZType.body.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: ZSpacing.lg),
          if (loading)
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
          else if (rep == null)
            // Cannot tell: never shown as a failure.
            ZBanner(
              key: const ValueKey('ios-setup-unknown'),
              message: l.onboardingIosSetupCheckUnknown,
              tone: ZBannerTone.info,
            )
          else
            ..._rows(l, c, rep),
        ],
        actions: [
          if (!loading)
            ZButton(
              key: const ValueKey('ios-setup-recheck'),
              label: l.onboardingIosSetupCheckAgain,
              icon: Icons.refresh,
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
            variant: ZButtonVariant.text,
            expand: true,
            onPressed: () => setState(() => _step = _Step.first),
          ),
        ],
      ),
    );
  }

  List<Widget> _rows(AppLocalizations l, ZColors c, ShortcutSetupReport rep) {
    final names = {
      _Row.smsAr: l.onboardingIosSetupCheckSmsAr,
      _Row.smsEn: l.onboardingIosSetupCheckSmsEn,
      _Row.applePay: l.onboardingIosSetupCheckApplePay,
    };
    final done = _Row.values.where((r) => _rowOk(r, rep)).length;
    final fixRow = _Row.values.where((r) => _fixing == r && !_rowOk(r, rep));
    return [
      Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
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
      ),
      _listCard([
        for (final r in _Row.values)
          _rowTile(l, c, r, names[r]!, ok: _rowOk(r, rep)),
      ], c),
      if (fixRow.isNotEmpty) ...[
        const SizedBox(height: ZSpacing.md),
        _fixPanel(
          l,
          c,
          fixRow.first == _Row.applePay
              ? _kWalletAutomation
              : _kMessageAutomation,
        ),
      ],
      if (!rep.allOk) ...[
        const SizedBox(height: ZSpacing.lg),
        Text(
          l.onboardingIosSetupCheckUnknown,
          textAlign: TextAlign.center,
          style: ZType.bodySmall.copyWith(color: c.textMuted),
        ),
      ],
    ];
  }

  Widget _fixPanel(AppLocalizations l, ZColors c, String automation) =>
      Container(
        key: const ValueKey('ios-setup-fix-panel'),
        padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
        decoration: BoxDecoration(
          color: c.zaghlolBg,
          borderRadius: BorderRadius.circular(ZRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.onboardingIosSetupFixTitle,
              style: ZType.titleSmall.copyWith(color: c.warningText),
            ),
            const SizedBox(height: ZSpacing.sm),
            for (final (i, t) in [
              l.onboardingIosSetupFixStep1,
              l.onboardingIosSetupFixStep2(automation),
              l.onboardingIosSetupFixStep3,
            ].indexed)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.xs),
                child: Text(
                  '${_digits('${i + 1}')}. $t',
                  style: ZType.body.copyWith(color: c.zaghlolText),
                ),
              ),
          ],
        ),
      );

  Widget _rowTile(
    AppLocalizations l,
    ZColors c,
    _Row r,
    String name, {
    required bool ok,
  }) {
    final fixing = _fixing == r && !ok;
    return _listRow(
      key: ValueKey('ios-setup-row-${r.name}'),
      icon: r == _Row.applePay ? Icons.credit_card : Icons.chat_bubble_outline,
      title: name,
      sub: ok ? null : l.onboardingIosSetupCheckNeedsRun,
      tileBg: ok ? c.primary : c.accent,
      tileFg: ok ? c.onPrimary : c.onAccent,
      trailing: ok
          ? Semantics(
              label: l.onboardingIosSetupCheckOkA11y,
              excludeSemantics: true,
              child: const OnbCheckDot(size: 24),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
              child: Material(
                color: c.zaghlolBg,
                borderRadius: BorderRadius.circular(ZRadius.pill),
                child: InkWell(
                  key: ValueKey('ios-setup-fix-${r.name}'),
                  borderRadius: BorderRadius.circular(ZRadius.pill),
                  onTap: () => setState(() => _fixing = fixing ? null : r),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: ZSpacing.lg,
                      vertical: ZSpacing.md,
                    ),
                    child: Text(
                      l.commonActionFix,
                      style: ZType.titleSmall.copyWith(
                        color: c.brightness == Brightness.dark
                            ? c.zaghlolText
                            : c.warningText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
      c: c,
    );
  }

  Widget _firstStep(AppLocalizations l, ZColors c) => KeyedSubtree(
    key: const ValueKey('ios-setup-first'),
    child: OnbPage(
      content: [
        const OnbMascot(size: 170),
        const SizedBox(height: ZSpacing.lg),
        Text(
          l.onboardingIosSetupFirstTitle,
          textAlign: TextAlign.center,
          style: ZType.headline.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.sm),
        Text(
          l.onboardingIosSetupFirstBody,
          textAlign: TextAlign.center,
          style: ZType.body.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: ZSpacing.lg),
        if (widget.onSay != null || widget.onType != null)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.onSay != null)
                  Expanded(
                    child: _entry(
                      const ValueKey('ios-setup-say'),
                      Icons.mic_none,
                      l.onboardingIosSetupFirstSay,
                      l.onboardingIosSetupFirstSayHint,
                      widget.onSay!,
                      c,
                      filled: true,
                    ),
                  ),
                if (widget.onSay != null && widget.onType != null)
                  const SizedBox(width: ZSpacing.md),
                if (widget.onType != null)
                  Expanded(
                    child: _entry(
                      const ValueKey('ios-setup-type'),
                      Icons.keyboard_alt_outlined,
                      l.onboardingIosSetupFirstType,
                      l.onboardingIosSetupFirstTypeHint,
                      widget.onType!,
                      c,
                      filled: false,
                    ),
                  ),
              ],
            ),
          ),
        if (widget.onOnlineBanks != null || widget.onStatement != null) ...[
          const SizedBox(height: ZSpacing.md),
          _listCard([
            if (widget.onOnlineBanks != null)
              _linkRow(
                const ValueKey('ios-setup-online-banks'),
                Icons.public,
                l.onboardingIosSetupFirstOnlineBanks,
                l.onboardingIosSetupFirstOnlineBanksSub,
                widget.onOnlineBanks!,
                c,
                tileBg: c.primaryContainer,
                tileFg: c.primary,
              ),
            if (widget.onStatement != null)
              _linkRow(
                const ValueKey('ios-setup-statement'),
                Icons.description_outlined,
                l.onboardingIosSetupFirstStatement,
                l.onboardingIosSetupFirstStatementSub,
                widget.onStatement!,
                c,
                subLead: Padding(
                  padding: const EdgeInsetsDirectional.only(end: ZSpacing.xs),
                  child: ExcludeSemantics(
                    child: Icon(
                      Icons.workspace_premium,
                      size: 14,
                      color: c.accentDark,
                    ),
                  ),
                ),
              ),
          ], c),
        ],
      ],
      actions: [
        ZButton(
          key: const ValueKey('ios-setup-done'),
          label: l.commonActionDone,
          expand: true,
          onPressed: widget.onDone,
        ),
      ],
    ),
  );

  Widget _linkRow(
    Key key,
    IconData icon,
    String title,
    String sub,
    VoidCallback onTap,
    ZColors c, {
    Color? tileBg,
    Color? tileFg,
    Widget? subLead,
  }) => InkWell(
    key: key,
    onTap: onTap,
    child: Semantics(
      button: true,
      container: true,
      child: _listRow(
        icon: icon,
        title: title,
        sub: sub,
        tileBg: tileBg,
        tileFg: tileFg,
        subLead: subLead,
        trailing: ExcludeSemantics(
          child: Icon(Icons.chevron_right, color: c.textMuted),
        ),
        c: c,
      ),
    ),
  );

  Widget _entry(
    Key key,
    IconData icon,
    String title,
    String hint,
    VoidCallback onTap,
    ZColors c, {
    required bool filled,
  }) => ZCard(
    key: key,
    onTap: onTap,
    padding: const EdgeInsetsDirectional.symmetric(
      horizontal: ZSpacing.md,
      vertical: ZSpacing.xl,
    ),
    child: Column(
      children: [
        OnbIconTile(
          icon: icon,
          size: 52,
          background: filled ? c.primary : c.primaryContainer,
          foreground: filled ? c.onPrimary : c.primary,
        ),
        const SizedBox(height: ZSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: ZType.titleSmall.copyWith(color: c.text),
        ),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: ZType.bodySmall.copyWith(color: c.textMuted),
        ),
      ],
    ),
  );
}
