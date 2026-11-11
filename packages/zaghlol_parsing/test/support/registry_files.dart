import 'dart:convert';
import 'dart:io';

/// Test registry bundle and fixtures on disk (synthetic data only).
const String registryRoot = 'test/fixtures/registry';

/// Registry bundle and fixtures of the pipeline tests (T-033).
const String pipelineRoot = 'test/fixtures/pipeline';

final class RegistryFiles {
  RegistryFiles(this.manifest, this.shared, this.institutions, this.fixtures);

  String manifest;
  String? shared;
  Map<String, String> institutions;
  Map<String, String> fixtures;

  factory RegistryFiles.load([String root = registryRoot]) {
    final bundle = Directory('$root/bundle');
    final institutions = <String, String>{};
    for (final f in Directory('${bundle.path}/institutions').listSync()) {
      if (f is File) {
        institutions[f.uri.pathSegments.last] = f.readAsStringSync();
      }
    }
    final fixtures = <String, String>{};
    final sms = Directory('$root/sms');
    for (final f in sms.listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.json')) {
        final rel = f.path.substring(sms.path.length + 1);
        fixtures[rel] = f.readAsStringSync();
      }
    }
    return RegistryFiles(
      File('${bundle.path}/registry_manifest.json').readAsStringSync(),
      File('${bundle.path}/shared.json').readAsStringSync(),
      institutions,
      fixtures,
    );
  }

  RegistryFiles copy() =>
      RegistryFiles(manifest, shared, {...institutions}, {...fixtures});

  /// Edits one institution JSON in place (decode, change, encode).
  void editInstitution(
    String file,
    void Function(Map<String, Object?> json) edit,
  ) {
    final json = jsonDecode(institutions[file]!) as Map<String, Object?>;
    edit(json);
    institutions[file] = jsonEncode(json);
  }

  void editFixture(String path, void Function(Map<String, Object?> json) edit) {
    final json = jsonDecode(fixtures[path]!) as Map<String, Object?>;
    edit(json);
    fixtures[path] = jsonEncode(json);
  }
}
