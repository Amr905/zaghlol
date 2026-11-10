import 'dart:io';

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

const String registryLintUsage = '''
Usage: dart run registry_lint [options]

Validates the institution registry, runs every SMS fixture, detects
cross-matching templates and exports the native Guard config subset.

  --registry <dir>        registry bundle (default app/assets/registry)
  --fixtures <dir>        fixtures root, <institution>/<case>.json
                          (default app/test/fixtures/sms)
  --min-fixtures <n>      fixtures required per template (default 4)
  --guard-config <file>   write the Guard config JSON here
  --check-guard-config <file>
                          fail if this file differs from the generated config
  --write-manifest        rewrite registry_manifest.json, then lint
  -h, --help

Exit code: 0 clean, 1 findings, 2 usage or I/O error. Output names files and
fields only; it never prints message text.
''';

/// Runs the lint. Returns the process exit code. Pure apart from the file
/// system access it is asked to do.
Future<int> runRegistryLint(
  List<String> args,
  StringSink out,
  StringSink err,
) async {
  var registryDir = 'app/assets/registry';
  var fixturesDir = 'app/test/fixtures/sms';
  var minFixtures = defaultMinFixturesPerTemplate;
  String? guardOut;
  String? guardCheck;
  var writeManifest = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? value() => i + 1 < args.length ? args[++i] : null;
    switch (a) {
      case '-h' || '--help':
        out.write(registryLintUsage);
        return 0;
      case '--registry':
        final v = value();
        if (v == null) {
          return _usage(err, '--registry needs a value');
        }
        registryDir = v;
      case '--fixtures':
        final v = value();
        if (v == null) {
          return _usage(err, '--fixtures needs a value');
        }
        fixturesDir = v;
      case '--min-fixtures':
        final v = int.tryParse(value() ?? '');
        if (v == null || v < 0 || v > 100) {
          return _usage(err, '--min-fixtures needs an integer 0..100');
        }
        minFixtures = v;
      case '--guard-config':
        guardOut = value();
        if (guardOut == null) {
          return _usage(err, '--guard-config needs a value');
        }
      case '--check-guard-config':
        guardCheck = value();
        if (guardCheck == null) {
          return _usage(err, '--check-guard-config needs a value');
        }
      case '--write-manifest':
        writeManifest = true;
      default:
        return _usage(err, 'unknown argument');
    }
  }

  final reader = _Reader();
  final manifestFile = File('$registryDir/registry_manifest.json');
  final sharedFile = File('$registryDir/shared.json');
  final institutionsDir = Directory('$registryDir/institutions');
  if (!institutionsDir.existsSync()) {
    err.writeln('registry directory not found: $registryDir/institutions');
    return 2;
  }
  final institutions = <String, String>{};
  for (final entity in institutionsDir.listSync(followLinks: false)) {
    if (entity is File) {
      institutions[entity.uri.pathSegments.last] = reader.read(entity);
    }
  }
  final fixtures = <String, String>{};
  final root = Directory(fixturesDir);
  if (root.existsSync()) {
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.json')) {
        var rel = entity.path.substring(root.path.length);
        rel = rel.replaceAll(r'\', '/');
        fixtures[rel.startsWith('/') ? rel.substring(1) : rel] = reader.read(
          entity,
        );
      }
    }
  }
  final manifest = manifestFile.existsSync() ? reader.read(manifestFile) : '{}';
  final shared = sharedFile.existsSync() ? reader.read(sharedFile) : null;

  if (writeManifest) {
    final loaded = RegistryLoader.load(
      manifest: manifest,
      shared: shared,
      institutions: institutions,
      checkManifest: false,
    );
    final reg = loaded.registry;
    if (reg == null) {
      for (final issue in loaded.issues) {
        out.writeln(issue);
      }
      err.writeln('cannot write the manifest while the registry has errors');
      return 1;
    }
    manifestFile.writeAsStringSync(reg.manifestJson());
    out.writeln(
      'wrote ${manifestFile.path} (registryVersion ${reg.registryVersion})',
    );
  }

  final report = lintRegistry(
    manifest: writeManifest ? manifestFile.readAsStringSync() : manifest,
    shared: shared,
    institutions: institutions,
    fixtures: fixtures,
    minFixturesPerTemplate: minFixtures,
  );
  final issues = [...reader.issues, ...report.issues];

  final guard = report.guardConfigJson;
  if (guard != null && guardOut != null) {
    File(guardOut).writeAsStringSync(guard);
    out.writeln('wrote $guardOut');
  }
  if (guard != null && guardCheck != null) {
    final f = File(guardCheck);
    if (!f.existsSync() || f.readAsStringSync() != guard) {
      issues.add(
        RegistryIssue(
          guardCheck,
          RegistryIssueCode.fixtureFailed,
          'guard-config-stale',
        ),
      );
    }
  }

  for (final issue in issues) {
    out.writeln(issue);
  }
  out.writeln(
    'registry: ${report.registry?.institutions.length ?? 0} institutions, '
    'fixtures: ${report.fixturesRun} run, ${report.fixturesPassed} passed, '
    'findings: ${issues.length}',
  );
  return issues.isEmpty ? 0 : 1;
}

int _usage(StringSink err, String message) {
  err.writeln(message);
  err.write(registryLintUsage);
  return 2;
}

/// Reads files with a size cap checked before the read; an oversized file is
/// reported and replaced by an empty string, so the loader reports it too.
final class _Reader {
  final List<RegistryIssue> issues = [];

  String read(File f) {
    try {
      if (f.lengthSync() > maxRegistryFileBytes) {
        issues.add(RegistryIssue(f.path, RegistryIssueCode.tooLarge));
        return '';
      }
      return f.readAsStringSync();
    } on FileSystemException {
      issues.add(
        RegistryIssue(f.path, RegistryIssueCode.invalidJson, 'unreadable'),
      );
      return '';
    }
  }
}
