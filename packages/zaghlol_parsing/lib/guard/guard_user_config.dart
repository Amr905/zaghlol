import 'dart:convert';

import 'guard_config.dart';
import 'guard_policy.dart';
import 'guard_types.dart';

/// One `ignore_rules` row (database-schema): institution is required, so a
/// last-4-only rule can not be expressed (EC-59).
final class GuardIgnoreRuleInput {
  const GuardIgnoreRuleInput({
    required this.institutionCode,
    required this.last4,
    required this.channel,
  });

  final String institutionCode;

  /// Null for an institution-level rule.
  final String? last4;

  /// `sms`, `notification` or `apple_pay`.
  final String channel;

  @override
  String toString() => 'GuardIgnoreRuleInput(<redacted>)';
}

/// A sender the user chose to capture (`capture_senders.always_capture`, or
/// a custom template's sender).
final class GuardUserSenderInput {
  const GuardUserSenderInput({required this.sender, required this.channel});

  final String sender;
  final String channel;

  @override
  String toString() => 'GuardUserSenderInput(<redacted>)';
}

/// Result of [buildGuardUserConfig]: the canonical UTF-8 JSON bytes, or an
/// error (code + JSON-ish path, never a value).
final class GuardUserConfigBuild {
  const GuardUserConfigBuild._(this.bytes, this.error);

  final List<int>? bytes;
  final GuardConfigError? error;

  bool get ok => bytes != null;
}

final RegExp _instShape = RegExp(r'^[a-z][a-z0-9_]{1,31}$');
final RegExp _last4Shape = RegExp(r'^[0-9]{4}$');

/// Builds the user part of the Guard config from database state (T-047
/// reads the rows and calls this; the bytes go to `writeGuardConfig` in
/// plaintext and are encrypted natively).
///
/// - [alwaysCaptureSenders]: `capture_senders` rows with `always_capture`.
/// - [customTemplateSenders]: senders of the user's custom templates; kept
///   after Gold lapses per [kCaptureCustomTemplateSendersWithoutGold] (PO
///   Q4).
///
/// Output is sorted and deduplicated, so the same state always gives the
/// same bytes. Any invalid row or a cap overrun is an error: the config is
/// never truncated or silently thinned (the old file stays in force).
GuardUserConfigBuild buildGuardUserConfig({
  required int baseRegistryVersion,
  required List<GuardIgnoreRuleInput> ignoreRules,
  required List<GuardUserSenderInput> alwaysCaptureSenders,
  required List<GuardUserSenderInput> customTemplateSenders,
  required bool goldActive,
}) {
  GuardUserConfigBuild fail(GuardConfigErrorCode code, String path) =>
      GuardUserConfigBuild._(null, GuardConfigError(code, path));

  if (baseRegistryVersion < 0) {
    return fail(GuardConfigErrorCode.badValue, r'$.baseRegistryVersion');
  }
  final rules = <(String, String?, String)>{};
  for (var i = 0; i < ignoreRules.length; i++) {
    final r = ignoreRules[i];
    final path = '\$.ignore[$i]';
    if (!_instShape.hasMatch(r.institutionCode)) {
      return fail(GuardConfigErrorCode.badValue, '$path.inst');
    }
    final last4 = r.last4;
    if (last4 != null && !_last4Shape.hasMatch(last4)) {
      return fail(GuardConfigErrorCode.badValue, '$path.last4');
    }
    if (GuardIgnoreChannel.fromWire(r.channel) == null) {
      return fail(GuardConfigErrorCode.badValue, '$path.ch');
    }
    rules.add((r.institutionCode, last4, r.channel));
  }
  if (rules.length > maxGuardIgnoreRules) {
    return fail(GuardConfigErrorCode.tooMany, r'$.ignore');
  }

  final senders = <(String, String)>{};
  bool addSenders(List<GuardUserSenderInput> list) {
    for (var i = 0; i < list.length; i++) {
      final s = list[i];
      final ch = GuardChannel.fromWire(s.channel);
      if (ch == null || !guardUserSenderChannels.contains(ch)) {
        return false;
      }
      if (s.sender.length > maxGuardValueLength) {
        return false;
      }
      final key = guardSourceKey(ch, s.sender);
      if (key.isEmpty) {
        return false;
      }
      senders.add((ch.wire, key));
    }
    return true;
  }

  if (!addSenders(alwaysCaptureSenders)) {
    return fail(GuardConfigErrorCode.badValue, r'$.userSenders');
  }
  if (goldActive || kCaptureCustomTemplateSendersWithoutGold) {
    if (!addSenders(customTemplateSenders)) {
      return fail(GuardConfigErrorCode.badValue, r'$.userSenders');
    }
  }
  if (senders.length > maxGuardUserSenders) {
    return fail(GuardConfigErrorCode.tooMany, r'$.userSenders');
  }

  int cmp(String? a, String? b) {
    if (a == b) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return a.compareTo(b);
  }

  final sortedRules = rules.toList()
    ..sort((a, b) {
      var c = a.$1.compareTo(b.$1);
      if (c != 0) return c;
      c = cmp(a.$2, b.$2);
      if (c != 0) return c;
      return a.$3.compareTo(b.$3);
    });
  final sortedSenders = senders.toList()
    ..sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });

  final config = <String, Object?>{
    'v': guardUserConfigVersion,
    'baseRegistryVersion': baseRegistryVersion,
    'ignore': [
      for (final r in sortedRules) {'inst': r.$1, 'last4': r.$2, 'ch': r.$3},
    ],
    'userSenders': [
      for (final s in sortedSenders) {'value': s.$2, 'ch': s.$1},
    ],
  };
  final bytes = utf8.encode(
    '${const JsonEncoder.withIndent(' ').convert(config)}\n',
  );
  if (bytes.length > maxGuardUserConfigBytes) {
    return fail(GuardConfigErrorCode.tooLarge, r'$');
  }
  return GuardUserConfigBuild._(bytes, null);
}
