// T-148: PigeonTextNormalizer passes the string through and replaces every
// failure with a code-only exception (the argument is a passphrase).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/pigeon_text_normalizer.dart';
import 'package:zaghlol/core/platform/text_normalization_api.g.dart';

class _FakeApi extends TextNormalizationHostApi {
  Object? error;
  final List<String> seen = [];

  @override
  Future<String> nfc(String input) async {
    seen.add(input);
    final e = error;
    if (e != null) throw e;
    return input.replaceAll('أ', 'أ');
  }
}

void main() {
  test('returns the platform result', () async {
    final api = _FakeApi();
    final n = PigeonTextNormalizer(api: api);
    expect(await n.nfc('أمان'), 'أمان');
    expect(api.seen, ['أمان']);
  });

  test('a platform error becomes a code-only exception', () async {
    final api = _FakeApi()
      ..error = PlatformException(
        code: 'NORMALIZATION_FAILED',
        message: 'secret-sentinel',
        details: 'secret-sentinel',
      );
    final n = PigeonTextNormalizer(api: api);
    try {
      await n.nfc('secret-sentinel');
      fail('expected an exception');
    } on TextNormalizationException catch (e) {
      expect('$e', isNot(contains('sentinel')));
    }
    api.error = StateError('secret-sentinel');
    await expectLater(n.nfc('x'), throwsA(isA<TextNormalizationException>()));
  });

  test('no channel registered (host test) is a code-only failure', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await expectLater(
      PigeonTextNormalizer().nfc('secret-sentinel'),
      throwsA(
        isA<TextNormalizationException>().having(
          (e) => '$e',
          'text',
          isNot(contains('sentinel')),
        ),
      ),
    );
  });
}
