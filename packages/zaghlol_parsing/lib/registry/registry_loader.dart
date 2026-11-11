import 'dart:convert';

import '../normalize/text_normalizer.dart';
import 'registry_issue.dart';
import 'registry_models.dart';
import 'registry_schema.dart';

/// A validated, fully compiled registry. Immutable; build one per isolate
/// (it holds the precompiled regexes, so there is no shared mutable state).
final class Registry {
  Registry._(this.registryVersion, this.shared, this.institutions);

  /// Max template version over all institutions (parsing-engine §3).
  final int registryVersion;
  final SharedConfig shared;

  /// Sorted by code.
  final List<Institution> institutions;

  Institution? byCode(String code) {
    for (final i in institutions) {
      if (i.code == code) {
        return i;
      }
    }
    return null;
  }

  /// Resolves a sender id (SMS address) or notification package to an
  /// institution, or null (the message is then generic or dropped by the
  /// Guard). Exact sender ids compare case-insensitively on the folded form.
  Institution? resolveSource(String source, RegistryChannel channel) {
    final key = foldKey(source);
    if (channel == RegistryChannel.notification) {
      for (final i in institutions) {
        if (i.packages.contains(source.trim())) {
          return i;
        }
      }
      return null;
    }
    for (final i in institutions) {
      for (final s in i.senders) {
        final hit = switch (s.kind) {
          SenderMatchKind.exact => foldKey(s.value) == key,
          SenderMatchKind.regex => s.regex!.regex.hasMatch(source.trim()),
        };
        if (hit) {
          return i;
        }
      }
    }
    return null;
  }

  /// Canonical `registry_manifest.json` text for this registry.
  String manifestJson() {
    final map = <String, Object?>{
      'schema': registrySchemaVersion,
      'registryVersion': registryVersion,
      'institutions': [for (final i in institutions) i.code],
    };
    return '${const JsonEncoder.withIndent('  ').convert(map)}\n';
  }
}

/// Outcome of [RegistryLoader.load]: a registry, or the issues that stopped
/// it. A registry with any issue is never returned (fail closed: a half
/// loaded registry would silently lose a bank).
final class RegistryLoadResult {
  const RegistryLoadResult(this.registry, this.issues);

  final Registry? registry;
  final List<RegistryIssue> issues;

  bool get ok => registry != null && issues.isEmpty;
}

/// Pure loader: takes file contents, does no I/O, never throws.
abstract final class RegistryLoader {
  /// [institutions] maps a file name (`nbe.json`) to its text.
  static RegistryLoadResult load({
    required String manifest,
    String? shared,
    required Map<String, String> institutions,

    /// False only for tooling that rebuilds the manifest itself.
    bool checkManifest = true,
  }) {
    final issues = <RegistryIssue>[];
    const manifestPath = 'registry_manifest.json';
    final manifestMap = decodeObject(manifestPath, manifest, issues);
    int? declaredVersion;
    List<String> declaredCodes = const [];
    if (manifestMap != null) {
      final r = ObjReader(manifestPath, manifestMap, issues);
      final schema = r.integer('schema', min: 1, max: 1000);
      if (schema != null && schema != registrySchemaVersion) {
        issues.add(
          const RegistryIssue(
            '$manifestPath.schema',
            RegistryIssueCode.badValue,
          ),
        );
      }
      declaredVersion = r.integer('registryVersion', min: 1, max: 1 << 30);
      declaredCodes = r.strings('institutions');
      r.finish();
    }
    if (institutions.length > maxInstitutions) {
      issues.add(
        const RegistryIssue('institutions', RegistryIssueCode.tooLarge),
      );
      return RegistryLoadResult(null, issues);
    }

    var sharedConfig = SharedConfig.empty;
    if (shared != null) {
      final parsed = parseShared('shared.json', shared, issues);
      if (parsed != null) {
        sharedConfig = parsed;
      }
    }

    final parsedInstitutions = <Institution>[];
    final fileNames = institutions.keys.toList()..sort();
    for (final name in fileNames) {
      if (!name.endsWith('.json')) {
        issues.add(
          RegistryIssue('institutions/$name', RegistryIssueCode.badValue),
        );
        continue;
      }
      final code = name.substring(0, name.length - 5);
      final inst = parseInstitution(
        'institutions/$name',
        code,
        institutions[name]!,
        issues,
      );
      if (inst != null) {
        parsedInstitutions.add(inst);
      }
    }
    _checkSenders(parsedInstitutions, issues);

    final maxVersion = parsedInstitutions.fold(
      0,
      (m, i) => i.maxTemplateVersion > m ? i.maxTemplateVersion : m,
    );
    if (manifestMap != null && checkManifest) {
      final actualCodes = [for (final i in parsedInstitutions) i.code];
      final sameCodes =
          declaredCodes.length == actualCodes.length &&
          [...declaredCodes]
              .asMap()
              .entries
              .every((e) => e.value == actualCodes[e.key]);
      if (!sameCodes) {
        issues.add(
          const RegistryIssue(
            '$manifestPath.institutions',
            RegistryIssueCode.manifestMismatch,
          ),
        );
      }
      if (declaredVersion != null && declaredVersion != maxVersion) {
        issues.add(
          const RegistryIssue(
            '$manifestPath.registryVersion',
            RegistryIssueCode.manifestMismatch,
          ),
        );
      }
    }
    if (issues.isNotEmpty) {
      return RegistryLoadResult(null, issues);
    }
    return RegistryLoadResult(
      Registry._(maxVersion, sharedConfig, parsedInstitutions),
      issues,
    );
  }

  static void _checkSenders(
    List<Institution> institutions,
    List<RegistryIssue> issues,
  ) {
    final seen = <String, String>{};
    for (final i in institutions) {
      for (final s in i.senders) {
        if (s.kind != SenderMatchKind.exact) {
          continue;
        }
        final key = foldKey(s.value);
        final owner = seen[key];
        if (owner != null && owner != i.code) {
          issues.add(
            RegistryIssue(
              'institutions/${i.code}.json#senders',
              RegistryIssueCode.duplicateSender,
              owner,
            ),
          );
        }
        seen[key] = i.code;
      }
    }
  }
}
