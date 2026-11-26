import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/ui/haptics_sync.dart';
import 'package:zaghlol/core/ui/z_haptics.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';

void main() {
  tearDown(() {
    ZHaptics.enabled = true;
    ZHaptics.reduceMotion = false;
  });

  test('haptics switch and reduce motion flow into ZHaptics', () async {
    final c = ProviderContainer(
      overrides: [
        hapticsEnabledProvider.overrideWith((ref) => Stream.value(false)),
      ],
    );
    addTearDown(c.dispose);
    c.listen(hapticsSyncProvider, (_, _) {});
    await c.read(hapticsEnabledProvider.future);
    c.read(hapticsSyncProvider);
    await Future<void>.delayed(Duration.zero);
    expect(ZHaptics.enabled, isFalse);
    expect(ZHaptics.reduceMotion, isFalse);
    c.read(reduceMotionProvider.notifier).set(true);
    await Future<void>.delayed(Duration.zero);
    c.read(hapticsSyncProvider);
    expect(ZHaptics.reduceMotion, isTrue);
  });
}
