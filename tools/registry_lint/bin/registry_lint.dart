import 'dart:io';

import 'package:registry_lint/registry_lint.dart';

Future<void> main(List<String> args) async {
  exitCode = await runRegistryLint(args, stdout, stderr);
}
