// T-153 / S-04: restore from backup, reached from Welcome's "I already use
// Zaghlol" (T-055 `onRestore`) and from S-66's "Restore a backup".
//
// States: choose provider, searching, backup found (list for Gold), empty,
// restoring (no cancel; the screen can't be left), done, and the errors
// network / sign-in / newer version (EC-26) / corrupted / wrong passphrase.
// The passphrase can't be recovered (EC-27); the help text says so.
//
// Restore reports no progress, so the bar is indeterminate. The "From:
// platform · version" line is left out: the listing carries no app version
// (it is only in the authenticated header, read during the restore).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import 'backup_labels.dart';
import 'backup_ports.dart';
import 'restore_flow.dart';

class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({
    super.key,
    required this.onRestored,
    required this.onStartFresh,
    this.onUpdateApp,
    this.iCloudAvailable = false,
    this.replacesExistingData = false,
  });

  /// Restore finished; the shell goes to the home screen. [regrantDue]: show
  /// the "re-allow capture" prompt (S-02/S-03) once.
  final void Function({required bool regrantDue}) onRestored;

  /// "Start fresh": leave the restore and continue onboarding.
  final VoidCallback onStartFresh;

  /// Opens the store page (newer-version error). Null hides the button.
  final VoidCallback? onUpdateApp;

  /// iCloud is offered on iPhone only.
  final bool iCloudAvailable;

  /// Opened from Settings on a phone that has data: the swap replaces it, so
  /// "Restore" asks first.
  final bool replacesExistingData;

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  final _pass = TextEditingController();
  bool _show = false;
  bool _forgot = false;
  bool _missing = false;

  @override
  void dispose() {
    _pass.clear();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pass.text.isEmpty) {
      setState(() => _missing = true);
      return;
    }
    setState(() => _missing = false);
    final p = _pass.text;
    final hasData =
        widget.replacesExistingData ||
        (await ref.read(restoreReplacesLocalDataProvider.future));
    if (!mounted) return;
    if (hasData) {
      final l10n = AppLocalizations.of(context);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(l10n.backupRestoreReplaceConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.commonActionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.backupRestoreReplaceAction),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    _pass.clear();
    unawaited(ref.read(restoreFlowProvider.notifier).restore(p));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(restoreFlowProvider);
    final c = ZColors.of(context);
    final busy = s.phase == RestorePhase.restoring;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Text(l10n.backupRestoreTitle),
          automaticallyImplyLeading: !busy,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
            children: [_body(context, l10n, s)],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, RestoreState s) {
    switch (s.phase) {
      case RestorePhase.chooseProvider:
        return _choose(l10n, s);
      case RestorePhase.searching:
        return _loading(
          l10n.backupRestoreSigningIn(_name(l10n, s.provider)),
          l10n.backupRestoreSearching,
        );
      case RestorePhase.found:
        return _found(context, l10n, s);
      case RestorePhase.empty:
        return _empty(l10n);
      case RestorePhase.restoring:
        return _restoring(l10n);
      case RestorePhase.done:
        return _done(l10n, s);
      case RestorePhase.error:
        return _error(l10n, s);
    }
  }

  String _name(AppLocalizations l10n, BackupProviderKind k) =>
      backupProviderName(l10n, k == BackupProviderKind.icloud);

  Widget _choose(AppLocalizations l10n, RestoreState s) {
    final c = ZColors.of(context);
    final flow = ref.read(restoreFlowProvider.notifier);
    final kinds = [
      BackupProviderKind.drive,
      if (widget.iCloudAvailable) BackupProviderKind.icloud,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.backupRestoreWhereTitle,
            style: ZType.title.copyWith(color: c.text),
          ),
        ),
        const SizedBox(height: ZSpacing.md),
        RadioGroup<BackupProviderKind>(
          groupValue: s.provider,
          onChanged: (v) {
            if (v != null) flow.chooseProvider(v);
          },
          child: Column(
            children: [
              for (final k in kinds)
                RadioListTile<BackupProviderKind>(
                  value: k,
                  title: Text(_name(l10n, k)),
                  contentPadding: EdgeInsetsDirectional.zero,
                ),
            ],
          ),
        ),
        const SizedBox(height: ZSpacing.lg),
        ZButton(
          label: l10n.commonActionContinue,
          expand: true,
          onPressed: flow.search,
        ),
      ],
    );
  }

  Widget _loading(String title, String sub) {
    final c = ZColors.of(context);
    return Semantics(
      liveRegion: true,
      label: '$title. $sub',
      child: Column(
        children: [
          const SizedBox(height: ZSpacing.xxl),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: ZSpacing.lg),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: ZType.body.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _found(BuildContext context, AppLocalizations l10n, RestoreState s) {
    final c = ZColors.of(context);
    final entry = s.current!;
    final size = entry.sizeBytes;
    final meta = l10n.backupRestoreFoundMeta(
      backupDate(context, ref, entry.createdAt),
      size == null ? '' : backupSize(context, ref, l10n, size),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            s.entries.length > 1
                ? l10n.backupRestoreVersionsTitle
                : l10n.backupRestoreFoundTitle,
            style: ZType.title.copyWith(color: c.text),
          ),
        ),
        const SizedBox(height: ZSpacing.md),
        if (s.entries.length > 1)
          for (var i = 0; i < s.entries.length; i++)
            _versionRow(context, l10n, s, i)
        else
          ZCard(
            child: Text(meta, style: ZType.body.copyWith(color: c.text)),
          ),
        const SizedBox(height: ZSpacing.lg),
        TextField(
          controller: _pass,
          obscureText: !_show,
          enableSuggestions: false,
          autocorrect: false,
          autofillHints: const [],
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(
            labelText: l10n.backupRestorePassphraseLabel,
            errorText: s.wrongPassphrase
                ? l10n.backupRestorePassphraseWrong
                : _missing
                ? l10n.backupRestorePassphraseRequired
                : null,
            suffixIcon: IconButton(
              constraints: const BoxConstraints(
                minWidth: ZSpacing.minTarget,
                minHeight: ZSpacing.minTarget,
              ),
              tooltip: _show ? l10n.commonActionHide : l10n.commonActionShow,
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(ZSpacing.minTarget, ZSpacing.minTarget),
          ),
          onPressed: () => setState(() => _forgot = !_forgot),
          child: Text(l10n.backupRestoreForgotLink),
        ),
        if (_forgot) ...[
          ZBanner(message: l10n.backupRestoreForgotBody),
          const SizedBox(height: ZSpacing.sm),
          ZButton(
            label: l10n.backupRestoreStartFresh,
            variant: ZButtonVariant.secondary,
            expand: true,
            onPressed: widget.onStartFresh,
          ),
        ],
        const SizedBox(height: ZSpacing.md),
        ZButton(
          label: l10n.backupRestoreRestore,
          expand: true,
          onPressed: () => unawaited(_submit()),
        ),
      ],
    );
  }

  Widget _versionRow(
    BuildContext context,
    AppLocalizations l10n,
    RestoreState s,
    int i,
  ) {
    final e = s.entries[i];
    final size = e.sizeBytes;
    final selected = i == s.selected;
    final c = ZColors.of(context);
    final date = backupDate(context, ref, e.createdAt);
    final sub = size == null ? null : backupSize(context, ref, l10n, size);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ZListRow(
        title: i == 0 ? '$date · ${l10n.backupRestoreVersionNewest}' : date,
        subtitle: sub,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? c.primary : c.textMuted,
        ),
        onTap: () => ref.read(restoreFlowProvider.notifier).select(i),
      ),
    );
  }

  Widget _empty(AppLocalizations l10n) {
    final c = ZColors.of(context);
    final flow = ref.read(restoreFlowProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.backupRestoreEmptyTitle,
          style: ZType.title.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.lg),
        ZButton(
          label: l10n.backupRestoreTryAnotherAccount,
          variant: ZButtonVariant.secondary,
          expand: true,
          onPressed: flow.reset,
        ),
        const SizedBox(height: ZSpacing.sm),
        ZButton(
          label: l10n.backupRestoreStartFresh,
          expand: true,
          onPressed: widget.onStartFresh,
        ),
      ],
    );
  }

  Widget _restoring(AppLocalizations l10n) {
    final c = ZColors.of(context);
    return Semantics(
      liveRegion: true,
      label: l10n.backupRestoreRestoring,
      child: Column(
        children: [
          const SizedBox(height: ZSpacing.lg),
          const ZaghlolAvatar(moment: ZaghlolMoment.counting, size: 120),
          const SizedBox(height: ZSpacing.lg),
          Text(
            l10n.backupRestoreRestoring,
            style: ZType.title.copyWith(color: c.text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: ZSpacing.md),
          const LinearProgressIndicator(),
          const SizedBox(height: ZSpacing.md),
          Text(
            l10n.backupRestoreKeepOpen,
            style: ZType.body.copyWith(color: c.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _done(AppLocalizations l10n, RestoreState s) {
    return Column(
      children: [
        ZBanner(
          tone: ZBannerTone.success,
          message: l10n.backupRestoreDoneBanner,
        ),
        const SizedBox(height: ZSpacing.lg),
        ZButton(
          label: l10n.backupRestoreDoneAction,
          expand: true,
          onPressed: () => widget.onRestored(regrantDue: s.regrantDue),
        ),
      ],
    );
  }

  Widget _error(AppLocalizations l10n, RestoreState s) {
    final flow = ref.read(restoreFlowProvider.notifier);
    final provider = _name(l10n, s.provider);
    final kind = s.error ?? RestoreFailureKind.other;
    final message = switch (kind) {
      RestoreFailureKind.network => l10n.backupRestoreErrorNetwork(provider),
      RestoreFailureKind.signIn => l10n.backupRestoreErrorSignIn(provider),
      RestoreFailureKind.newer => l10n.backupRestoreErrorNewer,
      RestoreFailureKind.corrupted => l10n.backupRestoreErrorCorrupted,
      _ => l10n.backupSettingsErrorGeneric,
    };
    final hasOlder = s.selected + 1 < s.entries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ZBanner(tone: ZBannerTone.error, message: message),
        const SizedBox(height: ZSpacing.lg),
        switch (kind) {
          RestoreFailureKind.newer =>
            widget.onUpdateApp == null
                ? const SizedBox.shrink()
                : ZButton(
                    label: l10n.backupRestoreUpdate,
                    expand: true,
                    onPressed: widget.onUpdateApp,
                  ),
          RestoreFailureKind.corrupted =>
            hasOlder
                ? ZButton(
                    label: l10n.backupRestoreTryOlder,
                    expand: true,
                    onPressed: flow.tryOlder,
                  )
                : const SizedBox.shrink(),
          _ => ZButton(
            label: l10n.commonActionTryAgain,
            expand: true,
            onPressed: flow.retry,
          ),
        },
        const SizedBox(height: ZSpacing.sm),
        ZButton(
          label: l10n.backupRestoreStartFresh,
          variant: ZButtonVariant.secondary,
          expand: true,
          onPressed: widget.onStartFresh,
        ),
      ],
    );
  }
}
