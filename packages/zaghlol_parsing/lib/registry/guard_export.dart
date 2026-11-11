import 'dart:convert';

import '../guard/guard_policy.dart';
import '../normalize/text_normalizer.dart';
import 'portable_regex.dart';
import 'registry_issue.dart';
import 'registry_loader.dart';
import 'registry_models.dart';

/// Base Guard config schema version (platform-channels §1.1, T-035).
const int guardConfigVersion = 4;

/// Upper bound of the base config (platform-channels §1.1).
const int maxGuardConfigBytes = 200 * 1024;

/// Result of [exportGuardConfig].
final class GuardExport {
  const GuardExport(this.json, this.issues);

  /// Canonical JSON text, or null when [issues] is not empty.
  final String? json;
  final List<RegistryIssue> issues;
}

/// Builds the **base** Guard config (`guard_base.json`, platform-channels
/// §1.1) from the registry: sender, package and wallet-card rules, drop
/// patterns, last-4 patterns, shortcut keywords, generic hints and the rate
/// limit. User state (ignore rules, user senders) is the separate user part
/// (`buildGuardUserConfig`).
///
/// Values are exported in the form the Guards compare: exact senders,
/// always-capture ids and wallet card names as `foldKey` text; packages
/// trimmed; patterns as [guardPatternText] (leading `(?i)` removed, Arabic
/// variants folded). Every pattern must be in the portable subset
/// ([portableRegexProblems]); `last4` patterns must have exactly one capture
/// group. Any violation is an issue and no config is produced.
///
/// Deterministic: institutions sorted by code, file order within one, fixed
/// key order, one-space indent, so the same registry always produces the
/// same bytes (a diff in CI means the registry changed).
GuardExport exportGuardConfig(Registry registry) {
  final issues = <RegistryIssue>[];
  String pattern(String path, String source, {bool last4 = false}) {
    final text = guardPatternText(source);
    final problems = portableRegexProblems(
      text,
      maxCaptureGroups: last4 ? 1 : null,
      requireCaptureGroup: last4,
    );
    if (problems.isNotEmpty) {
      issues.add(
        RegistryIssue(
          path,
          RegistryIssueCode.nonPortableRegex,
          problems.join(','),
        ),
      );
    }
    return text;
  }

  final senders = <Map<String, Object?>>[];
  final packages = <Map<String, Object?>>[];
  final wallet = <Map<String, Object?>>[];
  final byInst = <String, Object?>{};
  final last4 = <String, Object?>{};
  for (final i in registry.institutions) {
    final file = 'institutions/${i.code}.json';
    for (var k = 0; k < i.senders.length; k++) {
      final s = i.senders[k];
      final exact = s.kind == SenderMatchKind.exact;
      senders.add({
        'match': exact ? 'exact' : 'regex',
        'value': exact
            ? foldKey(s.value)
            : pattern('$file.senders[$k].value', s.value),
        'inst': i.code,
      });
    }
    for (final p in i.packages) {
      packages.add({'value': p.trim(), 'inst': i.code});
    }
    for (final name in i.walletCardNames) {
      final key = foldKey(name);
      if (key.isNotEmpty) {
        wallet.add({'name': key, 'inst': i.code});
      }
    }
    if (i.drop.isNotEmpty) {
      byInst[i.code] = [
        for (var k = 0; k < i.drop.length; k++)
          pattern('$file.drop[$k]', i.drop[k].source),
      ];
    }
    if (i.last4.isNotEmpty) {
      last4[i.code] = [
        for (var k = 0; k < i.last4.length; k++)
          pattern('$file.last4[$k]', i.last4[k].source, last4: true),
      ];
    }
  }
  final shared = registry.shared;
  if (shared.globalLast4.isNotEmpty) {
    last4['*'] = [
      for (var k = 0; k < shared.globalLast4.length; k++)
        pattern(
          'shared.json.last4[$k]',
          shared.globalLast4[k].source,
          last4: true,
        ),
    ];
  }
  final config = <String, Object?>{
    'v': guardConfigVersion,
    'registryVersion': registry.registryVersion,
    'senders': senders,
    'packages': packages,
    'wallet': wallet,
    'drop': {
      'global': [
        for (var k = 0; k < shared.globalDrop.length; k++)
          pattern('shared.json.drop.global[$k]', shared.globalDrop[k].source),
      ],
      'byInst': byInst,
    },
    'last4': last4,
    'generic': {
      'senderHints': [
        for (var k = 0; k < shared.senderHints.length; k++)
          pattern(
            'shared.json.generic.senderHints[$k]',
            shared.senderHints[k].source,
          ),
      ],
      'bodyHints': [
        for (var k = 0; k < shared.bodyHints.length; k++)
          pattern(
            'shared.json.generic.bodyHints[$k]',
            shared.bodyHints[k].source,
          ),
      ],
      'alwaysCapture': [
        for (final a in shared.alwaysCapture)
          if (foldKey(a).isNotEmpty) foldKey(a),
      ],
    },
    'shortcutKeywords': shared.shortcutKeywords,
    'rate': {'perSenderPerMin': kGuardRatePerSenderPerMinute},
  };
  if (issues.isNotEmpty) {
    return GuardExport(null, issues);
  }
  final json = '${const JsonEncoder.withIndent(' ').convert(config)}\n';
  if (utf8.encode(json).length > maxGuardConfigBytes) {
    return const GuardExport(null, [
      RegistryIssue('guard.cfg', RegistryIssueCode.guardConfigTooLarge),
    ]);
  }
  return GuardExport(json, const []);
}
