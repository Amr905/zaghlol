/// Value types of the Capture Guard (T-035). No message text is ever held
/// by these types except the institution code and, in [GuardKeep], the
/// last-4 digits (which `toString` never prints).
library;

import 'guard_policy.dart';

/// Channels the Guard knows. Anything else is dropped as
/// [GuardDropReason.unknownChannel].
enum GuardChannel {
  sms('sms'),
  notification('notification'),
  shortcutMessage('shortcut_message'),
  applePay('apple_pay'),

  /// User-initiated share/paste. Both platforms skip the Guard for shares
  /// (platform-channels §2.1, §3); the value is defined so the Guard has an
  /// answer if it is ever asked.
  share('share');

  const GuardChannel(this.wire);
  final String wire;

  static GuardChannel? fromWire(String text) {
    for (final c in values) {
      if (c.wire == text) {
        return c;
      }
    }
    return null;
  }
}

/// Channels an ignore rule can name (database `ignore_rules.channel`).
enum GuardIgnoreChannel {
  sms('sms'),
  notification('notification'),
  applePay('apple_pay');

  const GuardIgnoreChannel(this.wire);
  final String wire;

  static GuardIgnoreChannel? fromWire(String text) {
    for (final c in values) {
      if (c.wire == text) {
        return c;
      }
    }
    return null;
  }
}

/// The ignore-rule channel a message on [channel] is checked against, or
/// null when ignore rules do not apply (`share`). `shortcut_message` maps to
/// `sms` (iOS SMS arrive through the Shortcuts automation; PO Q5).
GuardIgnoreChannel? guardIgnoreChannel(GuardChannel channel) =>
    switch (channel) {
      GuardChannel.sms => GuardIgnoreChannel.sms,
      GuardChannel.shortcutMessage =>
        kShortcutMessageUsesSmsToggle ? GuardIgnoreChannel.sms : null,
      GuardChannel.notification => GuardIgnoreChannel.notification,
      GuardChannel.applePay => GuardIgnoreChannel.applePay,
      GuardChannel.share => null,
    };

/// Why a message was not kept. Wire names are shared with Kotlin and Swift
/// and the golden cases.
enum GuardDropReason {
  unknownChannel('unknown_channel'),
  emptyBody('empty_body'),
  tooLong('too_long'),
  notFinancial('not_financial'),
  otpOrPromoInst('otp_or_promo_inst'),
  otpOrPromoGlobal('otp_or_promo_global'),
  ignoredInstitution('ignored_institution'),
  ignoredCard('ignored_card'),
  configInvalid('config_invalid'),
  rateLimited('rate_limited');

  const GuardDropReason(this.wire);
  final String wire;
}

/// How a kept message was recognised.
enum GuardKeepKind {
  /// Registry sender, package or wallet card name: `inst` is set.
  registry('registry'),

  /// A sender the user chose to capture (`capture_senders` or a custom
  /// template sender).
  user('user'),

  /// Generic: always-capture list, a sender-less channel, or sender and
  /// body hints.
  generic('generic');

  const GuardKeepKind(this.wire);
  final String wire;
}

/// The Guard's answer for one message.
sealed class GuardDecision {
  const GuardDecision();
}

final class GuardKeep extends GuardDecision {
  const GuardKeep(this.kind, {this.inst, this.last4});

  final GuardKeepKind kind;

  /// Institution code when [kind] is [GuardKeepKind.registry].
  final String? inst;

  /// Card/account last 4 digits found by the `last4` patterns (registry
  /// kind only). Financial data: never printed by [toString].
  final String? last4;

  @override
  String toString() => 'GuardKeep(${kind.wire})';
}

final class GuardDrop extends GuardDecision {
  const GuardDrop(this.reason);

  final GuardDropReason reason;

  @override
  String toString() => 'GuardDrop(${reason.wire})';
}
