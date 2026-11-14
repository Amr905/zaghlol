import 'dart:convert';
import 'dart:io';

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

/// Shared Guard golden data (T-035 §7). Kotlin (T-038) and Swift (T-061)
/// read the same directory; never copy it.
const String guardRoot = 'test/fixtures/guard';

/// Set to `1` to rewrite the generated configs instead of comparing them.
const String guardUpdateEnv = 'ZG_UPDATE_GUARD_GOLDENS';

bool get updateGuardGoldens => Platform.environment[guardUpdateEnv] == '1';

/// The synthetic Guard test registry (`test/fixtures/guard/registry`).
Registry loadGuardTestRegistry() {
  final dir = Directory('$guardRoot/registry');
  final institutions = <String, String>{};
  for (final f in Directory('${dir.path}/institutions').listSync()) {
    if (f is File) {
      institutions[f.uri.pathSegments.last] = f.readAsStringSync();
    }
  }
  final load = RegistryLoader.load(
    manifest: File('${dir.path}/registry_manifest.json').readAsStringSync(),
    shared: File('${dir.path}/shared.json').readAsStringSync(),
    institutions: institutions,
  );
  if (!load.ok) {
    throw StateError('guard test registry: ${load.issues}');
  }
  return load.registry!;
}

/// The database state behind `configs/t1_user.json` (synthetic).
GuardUserConfigBuild buildT1User(Registry registry) => buildGuardUserConfig(
  baseRegistryVersion: registry.registryVersion,
  ignoreRules: const [
    GuardIgnoreRuleInput(institutionCode: 'nbe', last4: '4567', channel: 'sms'),
    GuardIgnoreRuleInput(institutionCode: 'cib', last4: '9910', channel: 'sms'),
    GuardIgnoreRuleInput(
      institutionCode: 'cib',
      last4: null,
      channel: 'notification',
    ),
    GuardIgnoreRuleInput(institutionCode: 'bm', last4: null, channel: 'sms'),
    GuardIgnoreRuleInput(
      institutionCode: 'nbe',
      last4: null,
      channel: 'apple_pay',
    ),
  ],
  alwaysCaptureSenders: const [
    GuardUserSenderInput(sender: 'MyCoop', channel: 'sms'),
    GuardUserSenderInput(sender: '+201000000009', channel: 'sms'),
    GuardUserSenderInput(sender: 'com.example.wallet', channel: 'notification'),
  ],
  customTemplateSenders: const [
    GuardUserSenderInput(sender: 'Club-7', channel: 'sms'),
  ],
  goldActive: false,
);

List<int> readGuardFile(String relative) =>
    File('$guardRoot/$relative').readAsBytesSync();

Map<String, Object?> readGolden() =>
    jsonDecode(File('$guardRoot/golden.json').readAsStringSync())
        as Map<String, Object?>;
