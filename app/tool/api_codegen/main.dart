// T-141: regenerates lib/core/backend/generated/api_models.g.dart.
// Run from app/: `dart run tool/api_codegen/main.dart`.

import 'dart:io';

import 'render.dart';

Future<void> main() async {
  final out = File(generatedModelsPath);
  await out.writeAsString(await renderApiModels());
  stdout.writeln('wrote ${out.path}');
}
