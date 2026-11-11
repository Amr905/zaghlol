import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/guard_files.dart';
import 'guard_golden_test.dart' show describeDecision;

void main() {
  final registry = loadGuardTestRegistry();
  final baseBytes = readGuardFile('configs/t1_base.json');
  final userBytes = readGuardFile('configs/t1_user.json');
  final full = parseGuardConfig(baseBytes, userBytes).config!;
  final baseOnly = parseGuardConfig(baseBytes).config!;
  final cases = (readGolden()['cases']! as List<Object?>)
      .cast<Map<String, Object?>>();

  test('Guard body cap equals the pipeline body cap', () {
    expect(kGuardMaxBodyLength, maxParseBodyLength);
  });

  group('parity with ParsingPipeline stage 0', () {
    // The pipeline resolves sms / notification / shortcut_message sources
    // the same way; apple_pay (wallet names) and share are Guard-only.
    const channels = {'sms', 'notification', 'shortcut_message'};
    final pipeline = ParsingPipeline(registry);
    for (final c in cases) {
      if (!channels.contains(c['channel'])) {
        continue;
      }
      test(c['id'], () {
        final source = c['source']! as String;
        final body = c['body']! as String;
        final channel = c['channel']! as String;
        final d = CaptureGuard(c['config'] == 't1' ? full : baseOnly)
            .decide(channel: channel, source: source, body: body);
        final r = pipeline.parse(
          ParseRequest(
            body: body,
            source: source,
            channel: RegistryChannel.fromWire(channel)!,
            receivedAt: DateTime.utc(2026, 11, 11, 10),
          ),
        );
        switch (d) {
          case GuardDrop(reason: GuardDropReason.otpOrPromoInst):
            expect(r, isA<ParseDropped>());
            expect((r as ParseDropped).reason, DropReason.institutionPattern);
          case GuardDrop(reason: GuardDropReason.otpOrPromoGlobal):
            expect(r, isA<ParseDropped>());
            expect((r as ParseDropped).reason, DropReason.globalPattern);
          case GuardKeep():
          case GuardDrop(
            reason: GuardDropReason.ignoredCard ||
                GuardDropReason.ignoredInstitution,
          ):
            // Passed the OTP/promo step: the pipeline must not drop it.
            expect(r, isNot(isA<ParseDropped>()));
          case GuardDrop():
            break;
        }
        if (d case GuardKeep(kind: GuardKeepKind.registry, :final inst)) {
          final institution = registry.resolveSource(
            source,
            RegistryChannel.fromWire(channel)!,
          );
          expect(institution?.code, inst);
        }
        if (d case GuardKeep(:final last4?)) {
          if (r case ParseParsed(:final fields)) {
            expect(fields.last4, last4, reason: 'template last4 = Guard last4');
          }
        }
      });
    }
  });

  group('EC-59: ignore matches institution + last4, never last4 alone', () {
    test('property: a random rule set never drops another institution', () {
      final rnd = Random(20261111);
      const insts = ['nbe', 'cib', 'bm'];
      const sources = {'nbe': 'NBE', 'cib': 'CIB', 'bm': 'BanqueMisr'};
      for (var round = 0; round < 300; round++) {
        final rules = <GuardIgnoreRuleInput>[
          for (var k = 0; k < 1 + rnd.nextInt(6); k++)
            GuardIgnoreRuleInput(
              institutionCode: insts[rnd.nextInt(3)],
              last4: rnd.nextBool()
                  ? null
                  : (1000 + rnd.nextInt(9000)).toString(),
              channel: 'sms',
            ),
        ];
        final build = buildGuardUserConfig(
          baseRegistryVersion: 3,
          ignoreRules: rules,
          alwaysCaptureSenders: const [],
          customTemplateSenders: const [],
          goldActive: false,
        );
        final guard = CaptureGuard(
          parseGuardConfig(baseBytes, build.bytes).config,
        );
        final ruled = {for (final r in rules) r.institutionCode};
        for (final inst in insts) {
          if (ruled.contains(inst)) {
            continue;
          }
          // Every last4 that appears in any rule, on an un-ruled bank.
          for (final r in rules.where((r) => r.last4 != null)) {
            final d = guard.decide(
              channel: 'sms',
              source: sources[inst]!,
              body: 'Purchase EGP 10.00 card **${r.last4}',
            );
            expect(d, isA<GuardKeep>(), reason: 'round $round $inst');
            expect((d as GuardKeep).last4, r.last4);
          }
        }
      }
    });

    test('a rule without an institution can not be loaded', () {
      final load = parseGuardConfig(
        baseBytes,
        readGuardFile('configs/user_last4_only.json'),
      );
      expect(load.mode, GuardConfigMode.baseOnly);
      expect(load.config!.ignore, isEmpty);
      expect(load.userError!.code, GuardConfigErrorCode.missingKey);
      expect(load.userError!.path, r'$.ignore[4].inst');
    });

    test('a generic message is never dropped by a card rule', () {
      final d = CaptureGuard(full).decide(
        channel: 'sms',
        source: 'MyBank',
        body: 'Debit EGP 10.00 card **4567',
      );
      expect(d, isA<GuardKeep>());
    });
  });

  group('config reader', () {
    test('a malformed user part never yields invalid (mutation fuzz)', () {
      final rnd = Random(7731);
      for (var i = 0; i < 2000; i++) {
        final mutated = [...userBytes];
        final edits = 1 + rnd.nextInt(4);
        for (var e = 0; e < edits; e++) {
          switch (rnd.nextInt(3)) {
            case 0:
              mutated[rnd.nextInt(mutated.length)] = rnd.nextInt(256);
            case 1:
              mutated.removeAt(rnd.nextInt(mutated.length));
            default:
              mutated.insert(rnd.nextInt(mutated.length), rnd.nextInt(256));
          }
        }
        final load = parseGuardConfig(baseBytes, mutated);
        expect(load.mode, isNot(GuardConfigMode.invalid));
        expect(load.config, isNotNull);
      }
    });

    test('a truncated or random base never throws', () {
      final rnd = Random(42);
      for (var i = 0; i < 300; i++) {
        // At least the closing brace goes (the file ends with `}\n`).
        final cut = baseBytes.sublist(0, rnd.nextInt(baseBytes.length - 1));
        expect(parseGuardConfig(cut).mode, GuardConfigMode.invalid);
        final noise = List<int>.generate(
          rnd.nextInt(512),
          (_) => rnd.nextInt(256),
        );
        expect(() => parseGuardConfig(noise), returnsNormally);
      }
    });

    test('oversized parts are refused before decoding', () {
      final big = List<int>.filled(maxGuardBaseBytes + 1, 0x20);
      expect(
        parseGuardConfig(big).baseError!.code,
        GuardConfigErrorCode.tooLarge,
      );
      final bigUser = List<int>.filled(maxGuardUserConfigBytes + 1, 0x20);
      final load = parseGuardConfig(baseBytes, bigUser);
      expect(load.mode, GuardConfigMode.baseOnly);
      expect(load.userError!.code, GuardConfigErrorCode.tooLarge);
    });

    test('unknown keys in the base are refused without echoing them', () {
      final json = jsonDecode(utf8.decode(baseBytes)) as Map<String, Object?>;
      json['ZG_CANARY_7731'] = 1;
      final load = parseGuardConfig(utf8.encode(jsonEncode(json)));
      expect(load.mode, GuardConfigMode.invalid);
      expect(load.baseError!.code, GuardConfigErrorCode.unknownKey);
      expect(load.baseError.toString(), isNot(contains('ZG_CANARY')));
    });

    test('a user part with an older registry version is used (full)', () {
      expect(
        parseGuardConfig(
          baseBytes,
          readGuardFile('configs/user_old_registry.json'),
        ).mode,
        GuardConfigMode.full,
      );
    });

    test('PO Q1 default (provisional): keep with base on a bad user part', () {
      expect(kGuardUserConfigFailure, GuardUserConfigFailure.keepWithBase);
    });
  });

  group('SenderRateLimiter', () {
    const keep = GuardKeep(GuardKeepKind.registry, inst: 'nbe');

    test('PO Q3 default (provisional) is 20 per sender per minute', () {
      expect(kGuardRatePerSenderPerMinute, 20);
      expect(full.perSenderPerMin, 20);
    });

    test('forgets the least recently used key beyond the cap', () {
      final l = SenderRateLimiter(1, maxKeys: 3);
      for (final s in ['A', 'B', 'C']) {
        expect(
          l.apply(keep, channel: 'sms', source: s, nowMonotonicMs: 0),
          keep,
        );
      }
      // Touch A, add D: B is evicted, A is still limited.
      expect(
        l.apply(keep, channel: 'sms', source: 'A', nowMonotonicMs: 1),
        isA<GuardDrop>(),
      );
      l.apply(keep, channel: 'sms', source: 'D', nowMonotonicMs: 1);
      expect(l.trackedKeys, 3);
      expect(
        l.apply(keep, channel: 'sms', source: 'B', nowMonotonicMs: 2),
        keep,
      );
      expect(
        l.apply(keep, channel: 'sms', source: 'A', nowMonotonicMs: 2),
        isA<GuardDrop>(),
      );
    });

    test('a clock that goes backwards restarts the window', () {
      final l = SenderRateLimiter(1);
      l.apply(keep, channel: 'sms', source: 'A', nowMonotonicMs: 1000);
      expect(
        l.apply(keep, channel: 'sms', source: 'A', nowMonotonicMs: 10),
        keep,
      );
    });

    test('drops pass through untouched and uncounted', () {
      final l = SenderRateLimiter(1);
      const drop = GuardDrop(GuardDropReason.notFinancial);
      for (var i = 0; i < 5; i++) {
        expect(
          l.apply(drop, channel: 'sms', source: 'A', nowMonotonicMs: 0),
          drop,
        );
      }
      expect(l.trackedKeys, 0);
    });
  });

  group('never logs (T-035 §8)', () {
    const canary = 'ZG_CANARY_7731';
    const canaryLast4 = '7319';

    test('no API prints, and no result or error carries the canary', () {
      final printed = <String>[];
      final strings = <String>[];
      runZoned(
        () {
          final guard = CaptureGuard(full);
          for (final channel in ['sms', 'notification', 'apple_pay', 'x']) {
            final d = guard.decide(
              channel: channel,
              source: 'NBE',
              body: '$canary card **$canaryLast4 EGP 10.00',
            );
            strings.add(d.toString());
            strings.add(
              SenderRateLimiter(1)
                  .apply(d, channel: channel, source: canary, nowMonotonicMs: 0)
                  .toString(),
            );
          }
          final keepD = guard.decide(
            channel: 'sms',
            source: 'NBE',
            body: '$canary card **$canaryLast4 EGP 10.00',
          );
          expect((keepD as GuardKeep).last4, canaryLast4);
          strings.add(keepD.toString());
          final build = buildGuardUserConfig(
            baseRegistryVersion: 3,
            ignoreRules: const [
              GuardIgnoreRuleInput(
                institutionCode: 'nbe',
                last4: canaryLast4,
                channel: 'sms',
              ),
              GuardIgnoreRuleInput(
                institutionCode: 'nbe',
                last4: canary,
                channel: 'sms',
              ),
            ],
            alwaysCaptureSenders: const [
              GuardUserSenderInput(sender: canary, channel: 'sms'),
            ],
            customTemplateSenders: const [],
            goldActive: true,
          );
          strings.add(build.error.toString());
          strings.add(
            const GuardIgnoreRuleInput(
              institutionCode: 'nbe',
              last4: canaryLast4,
              channel: 'sms',
            ).toString(),
          );
          strings.add(
            const GuardUserSenderInput(
              sender: canary,
              channel: 'sms',
            ).toString(),
          );
          final bad = utf8.encode(
            '{"v":1,"baseRegistryVersion":3,"ignore":[{"inst":"nbe",'
            '"last4":"$canary","ch":"sms"}],"userSenders":[]}',
          );
          final load = parseGuardConfig(baseBytes, bad);
          strings.add(load.userError.toString());
          final good = buildGuardUserConfig(
            baseRegistryVersion: 3,
            ignoreRules: const [
              GuardIgnoreRuleInput(
                institutionCode: 'nbe',
                last4: canaryLast4,
                channel: 'sms',
              ),
            ],
            alwaysCaptureSenders: const [],
            customTemplateSenders: const [],
            goldActive: true,
          );
          final g = CaptureGuard(
            parseGuardConfig(baseBytes, good.bytes).config,
          );
          strings.add(
            g
                .decide(
                  channel: 'sms',
                  source: 'NBE',
                  body: '$canary card **$canaryLast4',
                )
                .toString(),
          );
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      expect(printed, isEmpty);
      for (final s in strings) {
        expect(s, isNot(contains(canary)));
        expect(s, isNot(contains(canaryLast4)));
      }
    });

    test('lib/guard has no print, dart:io or dart:developer', () {
      final dir = Directory('lib/guard');
      final files = dir.listSync().whereType<File>().toList();
      expect(files, isNotEmpty);
      for (final f in files) {
        final text = f.readAsStringSync();
        expect(text, isNot(contains('print(')), reason: f.path);
        expect(text, isNot(contains('dart:io')), reason: f.path);
        expect(text, isNot(contains('dart:developer')), reason: f.path);
        expect(text, isNot(contains('log(')), reason: f.path);
      }
    });
  });

  group('performance (loose CI bounds; natives measure on device)', () {
    test('1,000 adversarial 4,000-char decisions take under 2 s', () {
      final guard = CaptureGuard(full);
      final bodies = [
        '1' * 4000,
        'otp ' * 1000,
        ('رمز التحقق ' * 400).substring(0, 4000),
        ('**' * 2000),
        '${'x' * 3996}4567',
        ('otp 1500.' * 500).substring(0, 4000),
        ('1234 ' * 800),
        '${'a' * 3999}1',
        // Keyword-first gap and lead-in shapes (review fix M-1/M-2).
        ('otp is ' * 572).substring(0, 4000),
        ('otp 1 is ' * 445).substring(0, 4000),
        ('otp: ' * 800),
        ('otp ج.م 1 ' * 400).substring(0, 4000),
        ('pin 1 2 ' * 500),
        ('كود ' * 1000),
        (', 1234 ' * 572).substring(0, 4000),
      ];
      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        guard.decide(
          channel: 'sms',
          source: 'NBE',
          body: bodies[i % bodies.length],
        );
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('config parse and compile is fast', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        parseGuardConfig(baseBytes, userBytes);
      }
      sw.stop();
      // 10 loads; the on-device budget is 20 ms each.
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });
  });

  test('describeDecision covers both decision kinds', () {
    expect(describeDecision(const GuardDrop(GuardDropReason.tooLong)), {
      'decision': 'drop',
      'reason': 'too_long',
    });
  });
}
