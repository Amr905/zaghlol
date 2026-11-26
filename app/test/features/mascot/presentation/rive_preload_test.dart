import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/mascot/presentation/rive_mascot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('FU-374: reduce motion skips the preload', () async {
    var calls = 0;
    await preloadRiveMascot(
      animationsDisabled: true,
      load: () async => calls++,
    );
    expect(calls, 0);
    await preloadRiveMascot(
      animationsDisabled: false,
      load: () async => calls++,
    );
    expect(calls, 1);
  });
}
