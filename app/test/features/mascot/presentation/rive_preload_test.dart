import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
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

  testWidgets('FU-391: preload starts from the first frame; the in-app '
      'reduce-motion setting stops it', (tester) async {
    Future<int> run({required bool reduce, bool platformOff = false}) async {
      var calls = 0;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: platformOff);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [reduceMotionProvider.overrideWith(() => _Fixed(reduce))],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: RivePreloadOnFirstFrame(
              load: () async => calls++,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();
      return calls;
    }

    expect(await run(reduce: false), 1);
    expect(await run(reduce: true), 0);
    expect(await run(reduce: false, platformOff: true), 0);
  });
}

class _Fixed extends ReduceMotionNotifier {
  _Fixed(this._v);
  final bool _v;
  @override
  bool build() => _v;
}
