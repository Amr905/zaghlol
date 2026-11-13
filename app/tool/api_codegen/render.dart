// T-141: generation plus `dart format` (the same formatter CI runs), shared by
// main.dart and the drift test so both produce identical bytes.

import 'dart:io';

import 'api_codegen.dart';

/// Paths relative to app/ (the working directory of `flutter test`).
const String openApiPath = '../backend/openapi/zaghlol-v1.yaml';
const String generatedModelsPath =
    'lib/core/backend/generated/api_models.g.dart';

Future<String> renderApiModels() async {
  final source = generateApiModels(await File(openApiPath).readAsString());
  final dir = await Directory.systemTemp.createTemp('api_codegen');
  try {
    final f = File('${dir.path}/api_models.g.dart');
    await f.writeAsString(source);
    final r = await Process.run('dart', ['format', f.path]);
    if (r.exitCode != 0) {
      throw StateError('dart format failed: ${r.stderr}');
    }
    return await f.readAsString();
  } finally {
    await dir.delete(recursive: true);
  }
}
