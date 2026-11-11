import 'dart:convert';

import 'registry_issue.dart';
import 'registry_loader.dart';
import 'registry_models.dart';

/// Guard config schema version (platform-channels §1.1).
const int guardConfigVersion = 3;

/// Upper bound from platform-channels §1.1.
const int maxGuardConfigBytes = 200 * 1024;

/// Result of [exportGuardConfig].
final class GuardExport {
  const GuardExport(this.json, this.issues);

  /// Canonical JSON text, or null when [issues] is not empty.
  final String? json;
  final List<RegistryIssue> issues;
}

/// The registry subset the native Capture Guard needs (platform-channels
/// §1.1): sender and package rules, drop patterns, last-4 patterns,
/// shortcut keywords and the generic hints. `ignore` is database state and
/// is added by the app, not here.
///
/// Deterministic: institutions sorted by code, fixed key order, one-space
/// indent, so the same registry always produces the same bytes (a diff in
/// CI means the registry changed). Patterns are exported exactly as
/// written (including a leading `(?i)`), not folded: the native side runs
/// its own regex engine on the raw body.
GuardExport exportGuardConfig(Registry registry) {
  final senders = <Map<String, Object?>>[];
  final packages = <Map<String, Object?>>[];
  final byInst = <String, Object?>{};
  final last4 = <String, Object?>{};
  for (final i in registry.institutions) {
    for (final s in i.senders) {
      senders.add({
        'match': s.kind == SenderMatchKind.exact ? 'exact' : 'regex',
        'value': s.value,
        'inst': i.code,
      });
    }
    for (final p in i.packages) {
      packages.add({'value': p, 'inst': i.code});
    }
    if (i.drop.isNotEmpty) {
      byInst[i.code] = [for (final p in i.drop) p.source];
    }
    if (i.last4.isNotEmpty) {
      last4[i.code] = [for (final p in i.last4) p.source];
    }
  }
  final shared = registry.shared;
  if (shared.globalLast4.isNotEmpty) {
    last4['*'] = [for (final p in shared.globalLast4) p.source];
  }
  final config = <String, Object?>{
    'v': guardConfigVersion,
    'registryVersion': registry.registryVersion,
    'senders': senders,
    'packages': packages,
    'shortcutKeywords': shared.shortcutKeywords,
    'drop': {
      'global': [for (final p in shared.globalDrop) p.source],
      'byInst': byInst,
    },
    'last4': last4,
    'generic': {
      'senderHints': [for (final p in shared.senderHints) p.source],
      'bodyHints': [for (final p in shared.bodyHints) p.source],
      'alwaysCapture': shared.alwaysCapture,
    },
  };
  final json = '${const JsonEncoder.withIndent(' ').convert(config)}\n';
  if (utf8.encode(json).length > maxGuardConfigBytes) {
    return const GuardExport(null, [
      RegistryIssue('guard.cfg', RegistryIssueCode.guardConfigTooLarge),
    ]);
  }
  return GuardExport(json, const []);
}
