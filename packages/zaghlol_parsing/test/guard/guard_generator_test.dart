import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/guard_files.dart';

void main() {
  final registry = loadGuardTestRegistry();

  group('base config (exportGuardConfig)', () {
    test('checked-in t1_base.json equals regeneration', () {
      final export = exportGuardConfig(registry);
      expect(export.issues, isEmpty);
      final file = File('$guardRoot/configs/t1_base.json');
      if (updateGuardGoldens) {
        file.writeAsStringSync(export.json!);
      }
      expect(file.readAsStringSync(), export.json);
    });

    test('is deterministic byte for byte', () {
      expect(
        exportGuardConfig(registry).json,
        exportGuardConfig(loadGuardTestRegistry()).json,
      );
    });

    test('parses back as a full base config', () {
      final load = parseGuardConfig(
        utf8.encode(exportGuardConfig(registry).json!),
      );
      expect(load.mode, GuardConfigMode.baseOnly);
      expect(load.baseError, isNull);
      expect(load.config!.perSenderPerMin, kGuardRatePerSenderPerMinute);
    });

    test('a non-portable pattern is an issue and no config is written', () {
      final files = _guardRegistryFiles();
      final shared = jsonDecode(files.$2) as Map<String, Object?>;
      (shared['last4']! as List<Object?>).add(r'card (\d{4})');
      final load = RegistryLoader.load(
        manifest: files.$1,
        shared: jsonEncode(shared),
        institutions: files.$3,
      );
      final export = exportGuardConfig(load.registry!);
      expect(export.json, isNull);
      expect(export.issues.single.code, RegistryIssueCode.nonPortableRegex);
      expect(export.issues.single.path, 'shared.json.last4[2]');
      expect(export.issues.single.detail, 'shorthand_escape');
    });

    test('a last4 pattern with two capture groups is rejected', () {
      final files = _guardRegistryFiles();
      final shared = jsonDecode(files.$2) as Map<String, Object?>;
      (shared['last4']! as List<Object?>).add(r'(card) ([0-9]{4})');
      final load = RegistryLoader.load(
        manifest: files.$1,
        shared: jsonEncode(shared),
        institutions: files.$3,
      );
      final export = exportGuardConfig(load.registry!);
      expect(export.issues.single.detail, 'capture_groups');
    });
  });

  group('user config (buildGuardUserConfig)', () {
    test('checked-in t1_user.json equals regeneration', () {
      final build = buildT1User(registry);
      expect(build.error, isNull);
      final file = File('$guardRoot/configs/t1_user.json');
      if (updateGuardGoldens) {
        file.writeAsBytesSync(build.bytes!);
      }
      expect(file.readAsBytesSync(), build.bytes);
    });

    test('sorted and deduplicated, whatever the input order', () {
      GuardUserConfigBuild build(List<GuardIgnoreRuleInput> rules) =>
          buildGuardUserConfig(
            baseRegistryVersion: 3,
            ignoreRules: rules,
            alwaysCaptureSenders: const [
              GuardUserSenderInput(sender: 'ZED', channel: 'sms'),
              GuardUserSenderInput(sender: 'zed', channel: 'sms'),
              GuardUserSenderInput(sender: 'Abc', channel: 'sms'),
            ],
            customTemplateSenders: const [],
            goldActive: true,
          );
      const a = GuardIgnoreRuleInput(
        institutionCode: 'nbe',
        last4: '1234',
        channel: 'sms',
      );
      const b = GuardIgnoreRuleInput(
        institutionCode: 'cib',
        last4: null,
        channel: 'sms',
      );
      final one = build([a, b, a]);
      final two = build([b, a]);
      expect(one.bytes, two.bytes);
      final json = jsonDecode(utf8.decode(one.bytes!)) as Map<String, Object?>;
      expect(json['ignore'], [
        {'inst': 'cib', 'last4': null, 'ch': 'sms'},
        {'inst': 'nbe', 'last4': '1234', 'ch': 'sms'},
      ]);
      expect(json['userSenders'], [
        {'value': 'abc', 'ch': 'sms'},
        {'value': 'zed', 'ch': 'sms'},
      ]);
    });

    test('over the ignore-rule cap is an error, never truncation', () {
      final rules = [
        for (var i = 0; i <= maxGuardIgnoreRules; i++)
          GuardIgnoreRuleInput(
            institutionCode: 'nbe',
            last4: i.toString().padLeft(4, '0'),
            channel: 'sms',
          ),
      ];
      final build = buildGuardUserConfig(
        baseRegistryVersion: 1,
        ignoreRules: rules,
        alwaysCaptureSenders: const [],
        customTemplateSenders: const [],
        goldActive: false,
      );
      expect(build.bytes, isNull);
      expect(build.error!.code, GuardConfigErrorCode.tooMany);
      expect(build.error!.path, r'$.ignore');
    });

    test('exactly at the ignore-rule cap is accepted', () {
      final rules = [
        for (var i = 0; i < maxGuardIgnoreRules; i++)
          GuardIgnoreRuleInput(
            institutionCode: 'nbe',
            last4: i.toString().padLeft(4, '0'),
            channel: 'sms',
          ),
      ];
      final build = buildGuardUserConfig(
        baseRegistryVersion: 1,
        ignoreRules: rules,
        alwaysCaptureSenders: const [],
        customTemplateSenders: const [],
        goldActive: false,
      );
      expect(build.error, isNull);
      expect(build.bytes!.length, lessThanOrEqualTo(maxGuardUserConfigBytes));
      final load = parseGuardConfig(
        utf8.encode(exportGuardConfig(registry).json!),
        build.bytes,
      );
      expect(load.mode, GuardConfigMode.full);
      expect(load.config!.ignore.length, maxGuardIgnoreRules);
    });

    test('over the sender cap is an error', () {
      final build = buildGuardUserConfig(
        baseRegistryVersion: 1,
        ignoreRules: const [],
        alwaysCaptureSenders: [
          for (var i = 0; i <= maxGuardUserSenders; i++)
            GuardUserSenderInput(sender: 'S$i', channel: 'sms'),
        ],
        customTemplateSenders: const [],
        goldActive: false,
      );
      expect(build.error!.code, GuardConfigErrorCode.tooMany);
    });

    test('invalid rows are errors with a path and no value', () {
      GuardConfigError? err(GuardIgnoreRuleInput rule) => buildGuardUserConfig(
        baseRegistryVersion: 1,
        ignoreRules: [rule],
        alwaysCaptureSenders: const [],
        customTemplateSenders: const [],
        goldActive: false,
      ).error;
      final noInst = err(
        const GuardIgnoreRuleInput(
          institutionCode: '',
          last4: '7731',
          channel: 'sms',
        ),
      );
      expect(noInst!.path, r'$.ignore[0].inst');
      final badLast4 = err(
        const GuardIgnoreRuleInput(
          institutionCode: 'nbe',
          last4: '٧٧٣١',
          channel: 'sms',
        ),
      );
      expect(badLast4!.path, r'$.ignore[0].last4');
      expect(badLast4.toString(), isNot(contains('٧٧٣١')));
      final badCh = err(
        const GuardIgnoreRuleInput(
          institutionCode: 'nbe',
          last4: null,
          channel: 'share',
        ),
      );
      expect(badCh!.path, r'$.ignore[0].ch');
    });

    test('custom template senders are kept after Gold lapses (PO Q4, '
        'provisional)', () {
      final build = buildGuardUserConfig(
        baseRegistryVersion: 1,
        ignoreRules: const [],
        alwaysCaptureSenders: const [],
        customTemplateSenders: const [
          GuardUserSenderInput(sender: 'Club-7', channel: 'sms'),
        ],
        goldActive: false,
      );
      final json =
          jsonDecode(utf8.decode(build.bytes!)) as Map<String, Object?>;
      expect(kCaptureCustomTemplateSendersWithoutGold, isTrue);
      expect(json['userSenders'], [
        {'value': 'club-7', 'ch': 'sms'},
      ]);
    });
  });
}

(String, String, Map<String, String>) _guardRegistryFiles() {
  final dir = '$guardRoot/registry';
  return (
    File('$dir/registry_manifest.json').readAsStringSync(),
    File('$dir/shared.json').readAsStringSync(),
    {
      for (final f in Directory('$dir/institutions').listSync())
        if (f is File) f.uri.pathSegments.last: f.readAsStringSync(),
    },
  );
}
