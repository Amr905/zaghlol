// T-146: the plain-language Gold outcome and status messages (error-handling
// §1 Gold rows; copy `goldSeat*`). A message never carries money, an account
// name or a token (EC-65); the support code is the install ID only.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../settings/presentation/settings_ports.dart';
import '../application/gating.dart';
import '../domain/purchase_outcome.dart';
import '../domain/restore_outcome.dart';
import 'gold_ui_ports.dart';

enum GoldMessageKind {
  cooldown,
  attestHelp,
  attestPlayServices,
  attestUnavailable,
  accountRequired,
  movedUser,
  movedSupport,
  paused,
  tampered,
  heldElsewhere,
  heldElsewhereAccount,
  supportNotice,
}

@immutable
final class GoldMessage {
  const GoldMessage(this.kind, {this.nextMoveAt});
  final GoldMessageKind kind;
  final DateTime? nextMoveAt;

  /// Restore results that have a seat/attestation message; others are shown
  /// by the screen that asked (null here).
  static GoldMessage? fromRestore(RestoreOutcome o) => switch (o) {
    RestoreMoveCooldown(:final nextMoveAt) => GoldMessage(
      GoldMessageKind.cooldown,
      nextMoveAt: nextMoveAt,
    ),
    RestoreAccountRequired() => const GoldMessage(
      GoldMessageKind.accountRequired,
    ),
    RestoreAttestationHelp() => const GoldMessage(GoldMessageKind.attestHelp),
    RestoreTryLater(playServicesOutdated: true) => const GoldMessage(
      GoldMessageKind.attestPlayServices,
    ),
    _ => null,
  };

  static GoldMessage? fromPurchase(PurchaseOutcome o) => switch (o) {
    PurchaseSeatHeldElsewhere(:final accountRequired, :final nextMoveAt) =>
      accountRequired
          ? const GoldMessage(GoldMessageKind.heldElsewhereAccount)
          : GoldMessage(GoldMessageKind.heldElsewhere, nextMoveAt: nextMoveAt),
    _ => null,
  };

  /// The status message for a non-Gold phase, or null (nothing to say).
  static GoldMessage? fromEntitlement(
    EntitlementState s,
    GoldStatusInfo info,
  ) => switch (s.phase) {
    EntitlementPhase.moved => GoldMessage(
      s.movedBy == MovedBy.support
          ? GoldMessageKind.movedSupport
          : GoldMessageKind.movedUser,
      nextMoveAt: info.nextMoveAt,
    ),
    EntitlementPhase.paused => const GoldMessage(GoldMessageKind.paused),
    EntitlementPhase.tampered => const GoldMessage(GoldMessageKind.tampered),
    _ => null,
  };
}

/// The date as the locale and digits setting show it.
String goldDate(WidgetRef ref, BuildContext context, DateTime d) {
  final lang = Localizations.localeOf(context).languageCode;
  return ZDateFormat.date(d, lang, ref.watch(digitsModeProvider(lang)));
}

/// One message card: title, body, then the actions that fit it.
class GoldMessageCard extends ConsumerWidget {
  const GoldMessageCard({
    super.key,
    required this.message,
    this.onRestore,
    this.onRetry,
    this.onDismiss,
    this.showSignIn = true,
  });

  final GoldMessage message;

  /// False on S-69 itself, where the sign-in buttons are right below.
  final bool showSignIn;

  /// Offered on `movedUser`.
  final VoidCallback? onRestore;

  /// Offered on attestation help.
  final VoidCallback? onRetry;

  /// Offered on the support notice; removes it for good (T-144).
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final date = message.nextMoveAt == null
        ? null
        : goldDate(ref, context, message.nextMoveAt!);
    final signIn = ref.watch(goldSignInOpenerProvider);

    final (String title, String? body) = switch (message.kind) {
      GoldMessageKind.cooldown => (
        t.goldSeatCooldownTitle,
        date == null ? null : t.goldSeatCooldownBody(date),
      ),
      GoldMessageKind.attestHelp => (
        t.goldSeatAttestTitle,
        t.goldSeatAttestBody,
      ),
      GoldMessageKind.attestPlayServices => (
        t.goldSeatAttestTitle,
        t.goldSeatAttestPlayServices,
      ),
      GoldMessageKind.attestUnavailable => (
        t.goldSeatAttestTitle,
        t.goldSeatAttestUnavailable,
      ),
      GoldMessageKind.accountRequired => (
        t.goldSeatAccountRequiredTitle,
        t.goldSeatAccountRequiredBody,
      ),
      GoldMessageKind.movedUser => (
        t.goldSeatMovedUserTitle,
        t.goldSeatMovedUserBody,
      ),
      GoldMessageKind.movedSupport => (
        t.goldSeatMovedSupportTitle,
        t.goldSeatMovedSupportBody,
      ),
      GoldMessageKind.paused => (t.goldSeatPausedTitle, t.goldSeatPausedBody),
      // FU-138: when the clock stays wrong after a fresh echo, "connect" is
      // wrong advice. The "set the clock to automatic" copy is a missing ARB
      // key (see the task file); until it lands both cases show this text.
      GoldMessageKind.tampered => (
        t.goldSeatTamperedTitle,
        t.goldSeatTamperedBody,
      ),
      GoldMessageKind.heldElsewhere => (
        t.goldPaywallTitle,
        date == null ? null : t.goldSeatHeldElsewhere(date),
      ),
      GoldMessageKind.heldElsewhereAccount => (
        t.goldSeatAccountRequiredTitle,
        t.goldSeatHeldElsewhereAccount,
      ),
      GoldMessageKind.supportNotice => (
        t.goldSeatSupportNoticeTitle,
        t.goldSeatSupportNoticeBody,
      ),
    };

    final wantsSignIn = const {
      GoldMessageKind.attestHelp,
      GoldMessageKind.attestUnavailable,
      GoldMessageKind.accountRequired,
      GoldMessageKind.movedUser,
      GoldMessageKind.paused,
      GoldMessageKind.heldElsewhereAccount,
    }.contains(message.kind);
    final wantsSupport = const {
      GoldMessageKind.cooldown,
      GoldMessageKind.attestHelp,
      GoldMessageKind.attestUnavailable,
      GoldMessageKind.movedSupport,
      GoldMessageKind.supportNotice,
    }.contains(message.kind);
    final warn =
        message.kind == GoldMessageKind.tampered ||
        message.kind == GoldMessageKind.paused;

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
        decoration: BoxDecoration(
          color: warn ? c.warningBg : c.zaghlolBg,
          borderRadius: BorderRadius.circular(ZRadius.card),
          border: Border.all(color: c.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: ZType.titleSmall.copyWith(color: c.text)),
            if (body != null) ...[
              const SizedBox(height: ZSpacing.xs),
              Text(body, style: ZType.body.copyWith(color: c.text)),
            ],
            const SizedBox(height: ZSpacing.md),
            Wrap(
              spacing: ZSpacing.sm,
              runSpacing: ZSpacing.sm,
              children: [
                if (message.kind == GoldMessageKind.movedUser &&
                    onRestore != null)
                  ZButton(
                    label: t.goldSeatRestoreAction,
                    onPressed: onRestore,
                    variant: ZButtonVariant.secondary,
                    size: ZButtonSize.small,
                  ),
                if (message.kind == GoldMessageKind.attestHelp &&
                    onRetry != null)
                  ZButton(
                    label: t.commonActionTryAgain,
                    onPressed: onRetry,
                    variant: ZButtonVariant.secondary,
                    size: ZButtonSize.small,
                  ),
                if (message.kind == GoldMessageKind.attestPlayServices)
                  ZButton(
                    label: t.commonActionTryAgain,
                    onPressed: onRetry,
                    variant: ZButtonVariant.secondary,
                    size: ZButtonSize.small,
                  ),
                if (showSignIn && wantsSignIn && signIn != null)
                  ZButton(
                    label: t.commonActionSignIn,
                    onPressed: signIn,
                    variant: ZButtonVariant.secondary,
                    size: ZButtonSize.small,
                  ),
                if (message.kind == GoldMessageKind.supportNotice &&
                    onDismiss != null)
                  ZButton(
                    label: t.commonActionDismiss,
                    onPressed: onDismiss,
                    variant: ZButtonVariant.text,
                    size: ZButtonSize.small,
                  ),
              ],
            ),
            if (wantsSupport) ...[
              const SizedBox(height: ZSpacing.md),
              const GoldSupportBlock(),
            ],
          ],
        ),
      ),
    );
  }
}

/// Contact support plus the copyable support code (install ID only).
class GoldSupportBlock extends ConsumerStatefulWidget {
  const GoldSupportBlock({super.key});

  @override
  ConsumerState<GoldSupportBlock> createState() => _GoldSupportBlockState();
}

class _GoldSupportBlockState extends ConsumerState<GoldSupportBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final code = ref.watch(supportCodeProvider).value;
    final contact = ref.watch(contactSupportProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (code != null)
          Semantics(
            button: true,
            label: t.commonSupportCodeCopyA11y(code),
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(ZRadius.md),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (mounted) setState(() => _copied = true);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ZSpacing.minTarget,
                ),
                child: Row(
                  children: [
                    Text(
                      t.commonSupportCodeLabel,
                      style: ZType.label.copyWith(color: c.textMuted),
                    ),
                    const SizedBox(width: ZSpacing.sm),
                    Flexible(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          _copied
                              ? t.commonSupportCodeCopied
                              : t.commonSupportCodeValue(code),
                          style: ZType.label.copyWith(color: c.text),
                        ),
                      ),
                    ),
                    const SizedBox(width: ZSpacing.sm),
                    Icon(Icons.copy, size: ZSpacing.lg, color: c.textMuted),
                  ],
                ),
              ),
            ),
          ),
        if (code != null)
          Text(
            t.commonSupportHint,
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
        const SizedBox(height: ZSpacing.sm),
        ZButton(
          label: t.commonActionContactSupport,
          onPressed: contact == null
              ? null
              : () => contact(t.commonActionContactSupport),
          variant: ZButtonVariant.secondary,
          size: ZButtonSize.small,
        ),
      ],
    );
  }
}
