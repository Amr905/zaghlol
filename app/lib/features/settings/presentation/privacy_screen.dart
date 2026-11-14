// T-162: S-71 Privacy & data: what stays on the phone, what the server knows
// (generated from the allow-list), the contribution opt-in, app lock, the
// rooted-phone note and Delete everything (FR-ONB-08, FR-CAT-09, NFR-PRIV,
// BR-SYNC-03).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../categorization/application/contributions.dart';
import '../../gold/application/restore.dart' show DeleteEverythingWarning;
import 'preferences_screen.dart';
import 'server_allow_list.dart';
import 'settings_ports.dart';
import 'settings_widgets.dart';

String _platformName() =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key, this.platform});

  /// `ios` / `android`; the device platform when null.
  final String? platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final plat = platform ?? _platformName();
    final contributing = ref.watch(contributionOptInProvider).value ?? false;
    final compromised = ref.watch(deviceCompromisedProvider);

    return SettingsScaffold(
      title: t.privacyMainTitle,
      children: [
        SettingsSection(
          title: t.privacyMainStaysTitle,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
              child: Text(
                t.privacyMainStaysBody,
                style: ZType.body.copyWith(color: c.text),
              ),
            ),
          ],
        ),
        ServerKnowsSection(platform: plat),
        SettingsSection(
          children: [
            SettingsSwitchRow(
              title: t.privacyContributeLabel,
              subtitle: t.privacyContributeSentence,
              value: contributing,
              onChanged: (v) async {
                final queue = await ref.read(contributionQueueProvider.future);
                await queue.setOptIn(v);
                if (v && context.mounted) {
                  showSettingsMessage(context, t.privacyContributeTurnedOn);
                }
              },
            ),
            SettingsRow(
              leading: Icon(Icons.info_outline, color: c.textMuted),
              title: t.privacyContributeInfoTitle,
              onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(t.privacyContributeInfoTitle),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.privacyContributeSends),
                        const SizedBox(height: ZSpacing.sm),
                        Text(t.privacyContributeNeverSends),
                        const SizedBox(height: ZSpacing.sm),
                        Text(t.privacyContributeFilters),
                        const SizedBox(height: ZSpacing.sm),
                        Text(t.privacyContributeOffHint),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(t.commonActionClose),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SettingsSection(
          children: [
            SettingsRow(
              title: t.privacyMainAppLock,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PreferencesScreen(),
                ),
              ),
            ),
            if (compromised)
              SettingsRow(
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: c.warningText,
                ),
                title: t.privacyRootedRow(plat),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(t.privacyRootedTitle),
                    content: Text(t.privacyRootedBody),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(t.commonActionClose),
                      ),
                    ],
                  ),
                ),
              ),
            SettingsRow(
              leading: Icon(Icons.delete_outline, color: c.dangerText),
              title: t.privacyDeleteRow,
              onTap: () => _confirmDelete(context, ref, plat),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String plat,
  ) async {
    final t = AppLocalizations.of(context);
    final last = ref.read(lastBackupAtProvider);
    final lastText = last == null
        ? t.privacyDeleteNoBackup
        : t.privacyDeleteLastBackup(
            localDigits(
              ref,
              context,
              DateFormat.yMMMd(Localizations.localeOf(context).toString())
                  .format(last),
            ),
          );
    // EC-69 (D-55): on Android, while this install holds a seat, warn that
    // bringing Gold back counts as this month's move (with the date during a
    // cooldown). iOS keeps the seat keys, so no warning there.
    String? seatText;
    if (plat == 'android') {
      DeleteEverythingWarning? w;
      try {
        w = await ref.read(deleteSeatWarningProvider.future);
      } on Object {
        w = null;
      }
      if (!context.mounted) return;
      if (w != null && w.holdsSeat) {
        final next = w.nextMoveAt;
        final cooldown = next != null && next.isAfter(DateTime.now());
        seatText = t.goldSeatDeleteWarning(
          cooldown ? 'cooldown' : 'other',
          cooldown
              ? localDigits(
                  ref,
                  context,
                  DateFormat.yMMMd(Localizations.localeOf(context).toString())
                      .format(next.toLocal()),
                )
              : '',
        );
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteDialog(
        lastBackupText: lastText,
        platform: plat,
        seatWarningText: seatText,
      ),
    );
    // Cancel, a dismissed dialog or a wrong word: nothing is deleted.
    if (confirmed != true || !context.mounted) return;
    final wipe = ref.read(wipeEverythingProvider);
    if (wipe == null) return;
    // A blocking progress dialog; the restart into first-launch state
    // replaces the whole tree.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: ZSpacing.lg),
                Expanded(child: Text(t.privacyDeleteWorking)),
              ],
            ),
          ),
        ),
      ),
    );
    await wipe();
  }
}

/// The server-knowledge list, generated from [serverAllowList].
class ServerKnowsSection extends StatelessWidget {
  const ServerKnowsSection({super.key, required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return SettingsSection(
      title: t.privacyServerTitle,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
          child: Text(
            t.privacyServerSummary,
            style: ZType.body.copyWith(color: c.text),
          ),
        ),
        for (final k in serverAllowList(platform)) _entry(context, t, k),
      ],
    );
  }

  Widget _entry(BuildContext context, AppLocalizations t, ServerKnows k) {
    final c = ZColors.of(context);
    final (String summary, String? detail) = switch (k) {
      ServerKnows.appId => (t.privacyServerItemId, null),
      ServerKnows.purchase => (t.privacyServerItemPurchase, null),
      ServerKnows.signIn => (t.privacyServerItemSignIn, null),
      ServerKnows.merchants => (t.privacyServerItemMerchants, null),
      ServerKnows.versions => (t.privacyServerItemVersion, null),
      ServerKnows.attestation => (t.privacyServerItemAttest, null),
      ServerKnows.bankRequest => (t.privacyServerItemBankRequest, null),
      ServerKnows.timeNonce => (
        t.privacyServerTimeNonceSummary,
        t.privacyServerTimeNonce,
      ),
      ServerKnows.seatKeys => (
        t.privacyServerSeatKeysSummary,
        t.privacyServerSeatKeys,
      ),
      ServerKnows.deleteKeepsKeys => (
        t.privacyServerDeleteKeepsSummary,
        t.privacyServerDeleteKeeps,
      ),
      ServerKnows.supportNotice => (
        t.privacyServerSupportNoticeSummary,
        t.privacyServerSupportNotice,
      ),
      ServerKnows.supportRows => (
        t.privacyServerSupportRowsSummary,
        t.privacyServerSupportRows,
      ),
    };
    if (detail == null) {
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.lg,
          vertical: ZSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
              child: Icon(Icons.circle, size: ZSpacing.sm, color: c.primary),
            ),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: Text(summary, style: ZType.body.copyWith(color: c.text)),
            ),
          ],
        ),
      );
    }
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.lg,
      ),
      title: Text(summary, style: ZType.body.copyWith(color: c.text)),
      childrenPadding: const EdgeInsetsDirectional.only(
        start: ZSpacing.lg,
        end: ZSpacing.lg,
        bottom: ZSpacing.md,
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(detail, style: ZType.bodySmall.copyWith(color: c.textMuted)),
      ],
    );
  }
}

/// C-18 type-to-confirm. The word is "DELETE" or "احذف" (either language).
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({
    required this.lastBackupText,
    required this.platform,
    this.seatWarningText,
  });

  final String lastBackupText;
  final String platform;

  /// EC-69: the Android seat warning; null: none.
  final String? seatWarningText;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _controller = TextEditingController();
  bool _mismatch = false;

  // The confirmation words are part of the typed protocol, not display copy.
  static const _words = {'DELETE', 'احذف'};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches => _words.contains(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.privacyDeleteTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.privacyDeleteBody),
            const SizedBox(height: ZSpacing.sm),
            Text(widget.lastBackupText),
            if (widget.seatWarningText case final seat?) ...[
              const SizedBox(height: ZSpacing.sm),
              Text(seat, key: const ValueKey('privacyDeleteSeatWarning')),
            ],
            if (widget.platform == 'ios') ...[
              const SizedBox(height: ZSpacing.sm),
              Text(t.privacyDeleteIosKeys),
              const SizedBox(height: ZSpacing.sm),
              Text(t.privacyDeleteIosServer),
            ],
            const SizedBox(height: ZSpacing.sm),
            Text(t.privacyDeleteServerCopy),
            const SizedBox(height: ZSpacing.md),
            Text(t.privacyDeleteTypePrompt),
            TextField(
              controller: _controller,
              onChanged: (_) => setState(() => _mismatch = false),
              decoration: InputDecoration(
                labelText: t.privacyDeleteTypeLabel,
                errorText: _mismatch ? t.privacyDeleteTypeMismatch : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.commonActionCancel),
        ),
        TextButton(
          onPressed: () {
            if (_matches) {
              Navigator.of(context).pop(true);
            } else {
              setState(() => _mismatch = true);
            }
          },
          child: Text(
            t.privacyDeleteConfirm,
            style: TextStyle(color: ZColors.of(context).dangerText),
          ),
        ),
      ],
    );
  }
}
