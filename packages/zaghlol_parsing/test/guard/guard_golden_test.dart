import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/guard_files.dart';

/// Minimum cases per tag (T-035 design note §7).
const Map<String, int> _minPerTag = {
  'non_financial': 10,
  'otp_drop': 15,
  'negative': 8,
  'inst_ignore': 6,
  'card_ignore': 10,
  'generic_keep': 8,
  'registry_keep': 6,
};

void main() {
  final golden = readGolden();
  final fold = (golden['fold']! as List<Object?>).cast<Map<String, Object?>>();
  final cases = (golden['cases']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final rate = (golden['rate']! as List<Object?>).cast<Map<String, Object?>>();
  final modes = (golden['modes']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final configs = (golden['configs']! as Map<String, Object?>)
      .cast<String, Map<String, Object?>>();

  CaptureGuard guardFor(String id) {
    final c = configs[id]!;
    final user = c['user'] as String?;
    final load = parseGuardConfig(
      readGuardFile(c['base']! as String),
      user == null ? null : readGuardFile(user),
    );
    if (load.config == null) {
      throw StateError('golden config $id does not load');
    }
    return CaptureGuard(load.config);
  }

  final guards = {for (final id in configs.keys) id: guardFor(id)};

  group('golden file', () {
    test('format, synthetic flag and count match what was read', () {
      expect(golden['format'], 1);
      expect(golden['synthetic'], isTrue);
      expect(
        fold.length + cases.length + rate.length + modes.length,
        golden['count'],
      );
      expect(cases.length, greaterThanOrEqualTo(60));
    });

    test('ids are unique', () {
      final ids = [
        for (final list in [fold, cases, rate, modes])
          for (final e in list) e['id'],
      ];
      expect(ids.toSet().length, ids.length);
    });

    test('per-tag minimums (design note §7)', () {
      final counts = <String, int>{};
      for (final c in cases) {
        for (final t in (c['tags']! as List<Object?>).cast<String>()) {
          counts[t] = (counts[t] ?? 0) + 1;
        }
      }
      for (final e in _minPerTag.entries) {
        expect(
          counts[e.key] ?? 0,
          greaterThanOrEqualTo(e.value),
          reason: e.key,
        );
      }
      expect(fold.length, greaterThanOrEqualTo(15));
      expect(modes.length, greaterThanOrEqualTo(4));
      expect(rate.length, greaterThanOrEqualTo(3));
    });
  });

  group('fold', () {
    for (final f in fold) {
      test(f['id'], () {
        expect(foldKey(f['in']! as String), f['out']);
      });
    }
  });

  group('cases', () {
    for (final c in cases) {
      test(c['id'], () {
        final guard = guards[c['config']! as String]!;
        final d = guard.decide(
          channel: c['channel']! as String,
          source: c['source']! as String,
          body: c['body']! as String,
        );
        expect(describeDecision(d), c['expect']);
      });
    }
  });

  group('rate', () {
    for (final r in rate) {
      test(r['id'], () {
        final guard = guards[r['config']! as String]!;
        final limiter = SenderRateLimiter(guard.config!.perSenderPerMin);
        var kept = 0;
        var limited = 0;
        var dropped = 0;
        for (final e
            in (r['events']! as List<Object?>).cast<Map<String, Object?>>()) {
          for (var k = 0; k < (e['n']! as int); k++) {
            final channel = e['channel']! as String;
            final source = e['source']! as String;
            final d = limiter.apply(
              guard.decide(
                channel: channel,
                source: source,
                body: e['body']! as String,
              ),
              channel: channel,
              source: source,
              nowMonotonicMs: e['tMs']! as int,
            );
            switch (d) {
              case GuardKeep():
                kept += 1;
              case GuardDrop(reason: GuardDropReason.rateLimited):
                limited += 1;
              case GuardDrop():
                dropped += 1;
            }
          }
        }
        expect({
          'kept': kept,
          'rateLimited': limited,
          'dropped': dropped,
        }, r['expect']);
      });
    }
  });

  group('modes', () {
    for (final m in modes) {
      test(m['id'], () {
        final user = m['user'] as String?;
        final load = parseGuardConfig(
          readGuardFile(m['base']! as String),
          user == null ? null : readGuardFile(user),
        );
        expect(load.mode.name, m['expect']);
        expect(load.userError != null, m['userError']);
        if (load.mode == GuardConfigMode.invalid) {
          expect(load.config, isNull);
          final d = CaptureGuard(
            load.config,
          ).decide(channel: 'sms', source: 'NBE', body: 'Purchase EGP 10.00');
          expect(describeDecision(d), {
            'decision': 'drop',
            'reason': 'config_invalid',
          });
        }
      });
    }
  });
}

/// The golden `expect` shape of a decision.
Map<String, Object?> describeDecision(GuardDecision d) => switch (d) {
  GuardKeep(:final kind, :final inst, :final last4) => {
    'decision': 'keep',
    'kind': kind.wire,
    'inst': inst,
    'last4': last4,
  },
  GuardDrop(:final reason) => {'decision': 'drop', 'reason': reason.wire},
};
