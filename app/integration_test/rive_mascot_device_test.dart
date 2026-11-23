// FU-287 / T-231: does the Rive mascot reach its loaded state on the real
// runtime (rive_native on the Android emulator), or does it fall back to the
// still? The device flows run with system animations off, where the app shows
// the still on purpose, so this test mounts RiveMascot directly.
//
// Run: flutter test integration_test/rive_mascot_device_test.dart
//      --flavor devSms -d <device> --no-uninstall

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rive/rive.dart' as rive;
import 'package:zaghlol/features/mascot/presentation/rive_mascot.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart'
    show ZaghlolMoment;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RiveMascot loads and plays on the device (not the still)', (
    t,
  ) async {
    RiveMascotProbe.reset();
    resetSharedRiveFileForTest();
    var moment = ZaghlolMoment.tourGuide;
    late StateSetter set;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                set = setState;
                return RiveMascot(moment: moment, size: 200);
              },
            ),
          ),
        ),
      ),
    );
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(end) &&
        RiveMascotProbe.loaded == 0 &&
        RiveMascotProbe.failedToLoad == 0) {
      await t.pump(const Duration(milliseconds: 250));
    }
    // ignore: avoid_print
    print(
      'RIVE_DEVICE loaded=${RiveMascotProbe.loaded} '
      'failedToLoad=${RiveMascotProbe.failedToLoad}',
    );
    expect(
      RiveMascotProbe.failedToLoad,
      0,
      reason: 'the Rive file or runtime failed to load (the still shows)',
    );
    expect(RiveMascotProbe.loaded, 1);
    // Let it paint and change state a few times; a paint exception sends the
    // mascot back to the still.
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    set(() => moment = ZaghlolMoment.proud);
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    // ignore: avoid_print
    print('RIVE_DEVICE paintFailed=${RiveMascotProbe.paintFailed}');
    expect(RiveMascotProbe.paintFailed, 0, reason: 'painting threw');
    expect(find.byType(rive.RiveWidget), findsOneWidget);
    expect(find.byType(Image), findsNothing, reason: 'the still is showing');
  });
}
