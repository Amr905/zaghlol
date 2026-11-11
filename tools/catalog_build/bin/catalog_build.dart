import 'dart:io';

import 'package:catalog_build/catalog_build.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCatalogBuild(args, stdout, stderr);
}
