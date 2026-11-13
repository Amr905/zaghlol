// T-147: S-69 Gold & account. Sign-in is optional and only carries Gold to
// another phone (FR-ACCT-01); every non-Gold feature works without it. The
// screen shows what the server decided in the words of the copy deck, never
// a token, an account ID or an e-mail (EC-65).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_client.dart' show SignInRequestProvider;
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../gold/domain/restore_outcome.dart';
import '../../gold/presentation/gold_messages.dart';
import '../application/account_providers.dart';
import '../domain/sign_in_outcome.dart';

/// Why S-69 was opened; changes the lead message only.
enum AccountReason {
  /// From Settings or the Gold status.
  none,

  /// A purchase or restore said `accountRequired` (R4-4): sign in with the
  /// account that owns Gold.
  accountRequired,
}

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key, this.reason = AccountReason.none});
  final AccountReason reason;

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

enum _Note { none, cancelled, failed, restored, restoreNone, deleted }

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _busy = false;
  SignedIn? _linked;
  _Note _note = _Note.none;
  GoldMessage? _message;

  void _refresh() {
    ref.invalidate(accountStatusProvider);
    ref.invalidate(protectPendingProvider);
  }

  Future<void> _signIn(
    SignInRequestProvider provider, {
    bool replaceLink = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = _Note.none;
      _linked = null;
    });
    final SignInOutcome o;
    try {
      o = await ref
          .read(accountActionsProvider)
          .signIn(provider, replaceLink: replaceLink);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _note = _Note.failed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    switch (o) {
      case final SignedIn s:
        setState(() => _linked = s);
        _refresh();
      case SignInCancelled():
        setState(() => _note = _Note.cancelled);
      case SignInNeedsReplaceConfirm():
        if (await _confirmReplace() && mounted) {
          await _signIn(provider, replaceLink: true);
        }
      case SignInTryLater() || SignInFailed():
        setState(() => _note = _Note.failed);
    }
  }

  Future<bool> _confirmReplace() async {
    final t = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.goldAccountReplaceTitle),
        content: Text(t.goldAccountReplaceBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.commonActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.goldAccountReplaceConfirm),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    RestoreOutcome? o;
    try {
      o = await ref.read(accountActionsProvider).restore();
    } on Object {
      o = null;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = o == null ? null : GoldMessage.fromRestore(o);
      _note = switch (o) {
        RestoreGold() => _Note.restored,
        RestoreNothingToRestore() => _Note.restoreNone,
        _ when _message != null => _Note.none,
        _ => _Note.failed,
      };
      if (o is RestoreGold) _linked = null;
    });
  }

  Future<void> _signOut(bool linkedGold) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.goldAccountSignOutTitle),
        content: Text(
          t.goldAccountSignOutBody(linkedGold ? 'linked' : 'other'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.commonActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.commonActionSignOut),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    await ref.read(accountActionsProvider).signOut();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _linked = null;
      _note = _Note.none;
    });
    _refresh();
  }

  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.goldAccountDeleteTitle),
        content: Text(t.goldAccountDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.commonActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.goldAccountDeleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final o = await ref.read(accountActionsProvider).deleteAccount();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _linked = null;
      _note = o is AccountDeleted ? _Note.deleted : _Note.failed;
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final status = ref.watch(accountStatusProvider).value;
    final signedIn = status?.signedIn ?? false;
    final protect = ref.watch(protectPendingProvider).value ?? false;

    final noteText = switch (_note) {
      _Note.none => null,
      _Note.cancelled => t.goldAccountSignInCancelled,
      _Note.failed => t.goldAccountSignInFailed,
      _Note.restored => t.goldAccountRestoreDone,
      _Note.restoreNone => t.goldAccountRestoreNone,
      _Note.deleted => t.goldAccountDeleted,
    };

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(backgroundColor: c.bg, title: Text(t.goldAccountTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          children: [
            if (widget.reason == AccountReason.accountRequired && !signedIn)
              GoldMessageCard(
                message: const GoldMessage(GoldMessageKind.accountRequired),
                showSignIn: false,
              ),
            if (protect && !signedIn) ...[
              _Card(title: t.goldSeatProtectTitle, body: t.goldSeatProtectBody),
              const SizedBox(height: ZSpacing.md),
            ],
            if (_linked != null) _linkedCard(context, _linked!),
            if (_message != null)
              GoldMessageCard(message: _message!, showSignIn: false),
            if (noteText != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    noteText,
                    style: ZType.body.copyWith(color: c.text),
                  ),
                ),
              ),
            const SizedBox(height: ZSpacing.lg),
            if (!signedIn) ...[
              Text(
                t.goldAccountOtherPhone,
                style: ZType.titleSmall.copyWith(color: c.text),
              ),
              const SizedBox(height: ZSpacing.xs),
              Text(
                t.goldAccountPrivacy,
                style: ZType.body.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: ZSpacing.md),
              ZButton(
                label: _busy ? t.goldAccountSigningIn : t.goldAccountGoogle,
                onPressed: _busy
                    ? null
                    : () => unawaited(_signIn(SignInRequestProvider.google)),
                variant: ZButtonVariant.secondary,
                expand: true,
              ),
              const SizedBox(height: ZSpacing.sm),
              ZButton(
                label: t.goldAccountApple,
                onPressed: _busy
                    ? null
                    : () => unawaited(_signIn(SignInRequestProvider.apple)),
                variant: ZButtonVariant.secondary,
                expand: true,
              ),
            ] else ...[
              ZButton(
                label: t.commonActionSignOut,
                onPressed: _busy
                    ? null
                    : () => unawaited(_signOut(status?.linkedGold ?? false)),
                variant: ZButtonVariant.secondary,
                expand: true,
              ),
              const SizedBox(height: ZSpacing.sm),
              ZButton(
                label: t.goldAccountDeleteRow,
                onPressed: _busy ? null : () => unawaited(_delete()),
                variant: ZButtonVariant.destructive,
                expand: true,
              ),
            ],
            const SizedBox(height: ZSpacing.xl),
            Text(
              t.goldAccountLostPhone,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.sm),
            const GoldSupportBlock(),
          ],
        ),
      ),
    );
  }

  /// R3-5 and R5-3(b): what the server decided, in the copy deck's words.
  Widget _linkedCard(BuildContext context, SignedIn s) {
    final t = AppLocalizations.of(context);
    final date = s.nextMoveAt == null
        ? null
        : goldDate(ref, context, s.nextMoveAt!);
    final c = ZColors.of(context);
    if (!s.linkedWithoutGold) {
      return _Card(
        title: s.movedFromOtherPhone
            ? t.goldAccountRestoreDone
            : t.goldSeatProtectDone,
      );
    }
    final hint = s.restoreHint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Card(
          title: t.goldSeatSignInLinked,
          body: switch (hint) {
            RestoreHint.offerRestore => t.goldSeatRestoreSuggested,
            RestoreHint.supportPath =>
              date == null ? null : t.goldSeatSupportPath(date),
            RestoreHint.none =>
              date == null ? null : t.goldAccountNextMove(date),
          },
        ),
        if (s.moveRefused && hint == RestoreHint.none && date != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Text(
              t.goldSeatCooldownBody(date),
              style: ZType.body.copyWith(color: c.textMuted),
            ),
          ),
        if (hint == RestoreHint.offerRestore)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: ZButton(
              label: t.goldSeatRestoreAction,
              onPressed: _busy ? null : () => unawaited(_restore()),
              variant: ZButtonVariant.secondary,
              size: ZButtonSize.small,
            ),
          ),
        const SizedBox(height: ZSpacing.md),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, this.body});
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
        decoration: BoxDecoration(
          color: c.zaghlolBg,
          borderRadius: BorderRadius.circular(ZRadius.card),
          border: Border.all(color: c.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: ZType.titleSmall.copyWith(color: c.text)),
            if (body != null) ...[
              const SizedBox(height: ZSpacing.xs),
              Text(body!, style: ZType.body.copyWith(color: c.text)),
            ],
          ],
        ),
      ),
    );
  }
}
