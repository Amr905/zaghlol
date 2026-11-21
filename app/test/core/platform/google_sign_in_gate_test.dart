import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/google_sign_in_gate.dart';

void main() {
  test(
    'FU-189b sessions never interleave and nonce sessions bump the epoch',
    () async {
      final g = GoogleSignInGate();
      final log = <String>[];
      final start = g.epoch;
      final a = g.run(() async {
        log.add('a1');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        log.add('a2');
      }, setsNonce: true);
      final b = g.run(() async => log.add('b'));
      await Future.wait([a, b]);
      expect(log, ['a1', 'a2', 'b']);
      expect(g.epoch, start + 1);
    },
  );

  test('a failing session does not block the next one', () async {
    final g = GoogleSignInGate();
    await expectLater(
      g.run<void>(() async => throw StateError('x')),
      throwsStateError,
    );
    expect(await g.run(() async => 1), 1);
  });
}
