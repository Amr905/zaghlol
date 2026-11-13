// T-153 / S-66: backup and restore settings. Where to back up, last backup,
// "Back up now", the Gold schedule and versions, the passphrase and the way
// into S-04.
//
// States: never backed up (Free nudge), backing up (counting mascot), done,
// error (network / storage / auth / iCloud off / generic, with Try again; the
// last good backup stays), stale reminder (Free, over 30 days; A-67), Free
// (locked Automatic and Versions rows open the paywall) and Gold.
//
// A running backup has no cancel: the services expose no cancellation, so the
// "you can cancel" note is not shown. The Account row is left out: no
// account name is exposed by the Drive or iCloud services.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../gold/application/gating.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import '../application/schedule.dart' show backupStaleAfter;
import '../application/schedule_providers.dart';
import '../crypto/backup_crypto_exception.dart';
import 'backup_labels.dart';
import 'backup_ports.dart';
import 'passphrase_sheet.dart';

final backupScheduleModeProvider = settingProvider(Settings.backupSchedule);
final backupDestinationProvider = settingProvider(Settings.backupDestination);

/// The saved versions on the chosen destination (Gold, newest first).
final backupVersionsProvider = FutureProvider.autoDispose
    .family<List<BackupEntryView>, BackupProviderKind>((ref, kind) async {
      ref.watch(backupLastSuccessProvider);
      return ref
          .watch(backupRestoreGatewayProvider)
          .list(kind, interactive: false);
    }, name: 'backupVersionsProvider');

/// Size of the newest backup in bytes, from a passive listing; null while
/// unknown (the date is then shown alone).
final backupLastSizeProvider = Provider.autoDispose
    .family<int?, BackupProviderKind>((ref, kind) {
      final list = ref.watch(backupVersionsProvider(kind)).value;
      return list == null || list.isEmpty ? null : list.first.sizeBytes;
    }, name: 'backupLastSizeProvider');

enum _Run { idle, running, done, failed }

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({
    super.key,
    required this.onOpenRestore,
    this.iCloudAvailable = false,
    this.now,
  });

  /// Opens S-04.
  final VoidCallback onOpenRestore;

  /// iCloud is offered on iPhone only.
  final bool iCloudAvailable;

  /// Test seam for the stale check.
  final DateTime Function()? now;

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  _Run _run = _Run.idle;
  BackupErrorKind? _error;
  BackupProviderKind? _picked;

  BackupProviderKind get _where {
    if (_picked != null) return _picked!;
    final saved = ref.watch(backupDestinationProvider).value;
    return saved == BackupDestinationPref.icloud && widget.iCloudAvailable
        ? BackupProviderKind.icloud
        : BackupProviderKind.drive;
  }

  Future<void> _backUp() async {
    final actions = ref.read(backupActionsProvider);
    final where = _where;
    setState(() {
      _run = _Run.idle;
      _error = null;
    });
    try {
      var haveKey = false;
      try {
        haveKey = await actions.hasKey();
      } on BackupCryptoException catch (e) {
        if (e.reason != BackupCryptoErrorCode.keyMismatch) rethrow;
        if (!await _recover(actions)) return _idle();
        haveKey = true;
      }
      if (!haveKey) {
        if (!mounted) return;
        final r = await showPassphraseSheet(
          context,
          mode: PassphraseMode.setup,
        );
        if (r == null) return _idle();
        await actions.createKey(r.passphrase);
      }
      if (!mounted) return;
      setState(() => _run = _Run.running);
      await actions.backupNow(
        where == BackupProviderKind.icloud
            ? BackupDestinationPref.icloud
            : BackupDestinationPref.drive,
      );
      if (mounted) setState(() => _run = _Run.done);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _run = _Run.failed;
        _error = backupErrorKindOf(e);
      });
    }
  }

  void _idle() {
    if (mounted) setState(() => _run = _Run.idle);
  }

  /// Asks for the current passphrase until it opens, or the user closes.
  Future<bool> _recover(BackupActions actions) async {
    var wrong = false;
    while (true) {
      if (!mounted) return false;
      final r = await showPassphraseSheet(
        context,
        mode: PassphraseMode.recover,
        currentWrong: wrong,
      );
      if (r == null) return false;
      try {
        await actions.recoverKey(r.passphrase);
        return true;
      } on BackupCryptoException catch (e) {
        if (e.reason != BackupCryptoErrorCode.wrongPassphrase) rethrow;
        wrong = true;
      }
    }
  }

  Future<void> _changePassphrase() async {
    final actions = ref.read(backupActionsProvider);
    var wrong = false;
    while (true) {
      if (!mounted) return;
      final r = await showPassphraseSheet(
        context,
        mode: PassphraseMode.change,
        currentWrong: wrong,
      );
      if (r == null) return;
      try {
        await actions.changePassphrase(r.current ?? '', r.passphrase);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).backupPassphraseChanged),
          ),
        );
        return;
      } on BackupCryptoException catch (e) {
        if (e.reason != BackupCryptoErrorCode.wrongPassphrase) {
          if (mounted) {
            setState(() {
              _run = _Run.failed;
              _error = BackupErrorKind.other;
            });
          }
          return;
        }
        wrong = true;
      }
    }
  }

  Future<void> _setSchedule(BackupScheduleMode m) async {
    try {
      await ref.read(backupActionsProvider).setSchedule(m);
    } on Object {
      if (mounted) {
        setState(() {
          _run = _Run.failed;
          _error = BackupErrorKind.other;
        });
      }
    }
  }

  void _paywall() =>
      ref.read(paywallTriggerProvider)(GoldCapability.autoBackupSchedule);

  String _errorText(AppLocalizations l10n, BackupErrorKind k) {
    final provider = backupProviderName(
      l10n,
      _where == BackupProviderKind.icloud,
    );
    return switch (k) {
      BackupErrorKind.network => l10n.backupSettingsErrorNetwork,
      BackupErrorKind.storage => l10n.backupSettingsErrorStorage(provider),
      BackupErrorKind.auth => l10n.backupSettingsErrorAuth(provider),
      BackupErrorKind.icloud => l10n.backupSettingsErrorIcloud,
      _ => l10n.backupSettingsErrorGeneric,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final gold = ref.watch(entitlementStateProvider).isGold;
    final last = ref.watch(lastBackupAtProvider).value;
    final mode =
        ref.watch(backupScheduleModeProvider).value ?? BackupScheduleMode.off;
    final running = _run == _Run.running;
    final now = (widget.now ?? DateTime.now)();
    final staleDays = last == null ? 0 : now.difference(last).inDays;
    final stale =
        !gold && last != null && now.difference(last) > backupStaleAfter;
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(l10n.backupSettingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          children: [
            if (stale) ...[
              ZBanner(
                tone: ZBannerTone.warning,
                message: l10n.backupSettingsStale(
                  staleDays,
                  digits.render('$staleDays'),
                ),
              ),
              const SizedBox(height: ZSpacing.md),
            ],
            if (widget.iCloudAvailable) ...[
              _title(l10n.backupSettingsWhere),
              const SizedBox(height: ZSpacing.sm),
              ZSegmentedControl<BackupProviderKind>(
                segments: [
                  ZSegment(
                    value: BackupProviderKind.drive,
                    label: l10n.backupRestoreOptionDrive,
                  ),
                  ZSegment(
                    value: BackupProviderKind.icloud,
                    label: l10n.backupRestoreOptionICloud,
                  ),
                ],
                selected: _where,
                onChanged: running
                    ? (_) {}
                    : (v) => setState(() => _picked = v),
              ),
              const SizedBox(height: ZSpacing.lg),
            ],
            ZCard(
              child: _status(
                l10n,
                last,
                gold,
                running,
                ref.watch(backupLastSizeProvider(_where)),
              ),
            ),
            const SizedBox(height: ZSpacing.md),
            if (_run == _Run.done)
              ZBanner(
                tone: ZBannerTone.success,
                message: l10n.backupSettingsDone,
              ),
            if (_run == _Run.failed && _error != null)
              ZBanner(
                tone: ZBannerTone.error,
                message: _errorText(l10n, _error!),
                actionLabel: l10n.commonActionTryAgain,
                onAction: _backUp,
              ),
            const SizedBox(height: ZSpacing.lg),
            _auto(l10n, gold, mode),
            const SizedBox(height: ZSpacing.lg),
            _versions(l10n, gold),
            const SizedBox(height: ZSpacing.lg),
            ZListRow(
              title: l10n.backupSettingsPassphrase,
              trailing: Text(l10n.backupSettingsPassphraseChange),
              showChevron: true,
              onTap: running ? null : _changePassphrase,
            ),
            ZListRow(
              title: l10n.backupSettingsRestore,
              showChevron: true,
              onTap: running ? null : widget.onOpenRestore,
            ),
            const SizedBox(height: ZSpacing.lg),
            Text(
              l10n.backupSettingsIncludes,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              l10n.backupSettingsExcludes,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(String text) => Semantics(
    header: true,
    child: Text(
      text,
      style: ZType.titleSmall.copyWith(color: ZColors.of(context).text),
    ),
  );

  Widget _status(
    AppLocalizations l10n,
    DateTime? last,
    bool gold,
    bool running,
    int? size,
  ) {
    final c = ZColors.of(context);
    if (running) {
      return Semantics(
        liveRegion: true,
        label: l10n.backupSettingsRunning,
        child: Column(
          children: [
            const ZaghlolAvatar(moment: ZaghlolMoment.counting, size: 96),
            const SizedBox(height: ZSpacing.sm),
            Text(
              l10n.backupSettingsRunning,
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
            const SizedBox(height: ZSpacing.md),
            const LinearProgressIndicator(),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          last == null
              ? l10n.backupSettingsNever
              : l10n.backupSettingsLast(
                  backupDate(context, ref, last),
                  size == null ? '–' : backupSize(context, ref, l10n, size),
                ),
          style: ZType.body.copyWith(color: c.text),
        ),
        if (last == null) ...[
          const SizedBox(height: ZSpacing.sm),
          Text(
            l10n.backupSettingsFreeNudge,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
        ],
        const SizedBox(height: ZSpacing.md),
        ZButton(
          label: l10n.backupSettingsNow,
          expand: true,
          onPressed: _backUp,
        ),
        if (!gold && last != null) ...[
          const SizedBox(height: ZSpacing.sm),
          Text(
            l10n.backupSettingsFreeReplaces,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _lockedRow(String title, String sub, AppLocalizations l10n) {
    return ZListRow(
      title: title,
      subtitle: sub,
      trailing: ZChip(label: l10n.commonGoldBadge, selected: true),
      onTap: _paywall,
    );
  }

  Widget _auto(AppLocalizations l10n, bool gold, BackupScheduleMode mode) {
    if (!gold) {
      return _lockedRow(
        l10n.backupSettingsAuto,
        l10n.backupSettingsAutoLocked,
        l10n,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(l10n.backupSettingsAuto),
        const SizedBox(height: ZSpacing.sm),
        ZSegmentedControl<BackupScheduleMode>(
          segments: [
            ZSegment(
              value: BackupScheduleMode.off,
              label: l10n.backupSettingsAutoOff,
            ),
            ZSegment(
              value: BackupScheduleMode.daily,
              label: l10n.backupSettingsAutoDaily,
            ),
            ZSegment(
              value: BackupScheduleMode.weekly,
              label: l10n.backupSettingsAutoWeekly,
            ),
            ZSegment(
              value: BackupScheduleMode.monthly,
              label: l10n.backupSettingsAutoMonthly,
            ),
          ],
          selected: mode,
          onChanged: _setSchedule,
        ),
      ],
    );
  }

  Widget _versions(AppLocalizations l10n, bool gold) {
    final c = ZColors.of(context);
    if (!gold) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lockedRow(
            l10n.backupSettingsVersions,
            l10n.backupSettingsVersionsLocked,
            l10n,
          ),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.lg,
            ),
            child: Text(
              l10n.backupSettingsGoldKeeps,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ),
        ],
      );
    }
    final versions =
        ref.watch(backupVersionsProvider(_where)).value ?? const [];
    if (versions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(l10n.backupSettingsVersions),
        const SizedBox(height: ZSpacing.sm),
        for (final v in versions.take(5))
          ZListRow(
            title: backupDate(context, ref, v.createdAt),
            subtitle: v.sizeBytes == null
                ? null
                : backupSize(context, ref, l10n, v.sizeBytes!),
          ),
      ],
    );
  }
}
