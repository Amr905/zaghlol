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

  // T-232: every state value 0-14 and `talk` reach the animation the Motion
  // Lab port gave them, as the Flutter runtime reports it when a layer
  // changes state (names are the animation names in zaghlol.riv).
  testWidgets('every state 0-14 and talk play their animation', (t) async {
    RiveMascotProbe.reset();
    resetSharedRiveFileForTest();
    // Moments whose props (fx layer) have their own animation.
    const withProps = {
      ZaghlolMoment.professor,
      ZaghlolMoment.listening,
      ZaghlolMoment.thinking,
      ZaghlolMoment.scanning,
      ZaghlolMoment.counting,
      ZaghlolMoment.saved,
      ZaghlolMoment.payday,
      ZaghlolMoment.oops,
      ZaghlolMoment.sleep,
    };
    var moment = ZaghlolMoment.proud;
    var talk = false;
    late StateSetter set;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                set = setState;
                return RiveMascot(moment: moment, talk: talk, size: 200);
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
    expect(RiveMascotProbe.loaded, 1, reason: 'the Rive file did not load');
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final missing = <String>[];
    for (final m in ZaghlolMoment.values.reversed) {
      final nn = m.index.toString().padLeft(2, '0');
      RiveMascotProbe.stateNames.clear();
      set(() => moment = m);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final names = List<String>.of(RiveMascotProbe.stateNames);
      final mood = 'mood${nn}_${m.name}';
      if (!names.contains(mood)) missing.add('$mood in $names');
      if (withProps.contains(m) && !names.contains('fx${nn}_${m.name}')) {
        missing.add('fx${nn}_${m.name} in $names');
      }
    }
    RiveMascotProbe.stateNames.clear();
    set(() => talk = true);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    if (!RiveMascotProbe.stateNames.contains('talkOn')) {
      missing.add('talkOn in ${RiveMascotProbe.stateNames}');
    }
    // ignore: avoid_print
    print(
      'RIVE_DEVICE states ok=${missing.isEmpty} missing=$missing '
      'paintFailed=${RiveMascotProbe.paintFailed}',
    );
    expect(
      missing,
      isEmpty,
      reason: 'states that did not reach their animation',
    );
    expect(RiveMascotProbe.paintFailed, 0, reason: 'painting threw');
    expect(find.byType(Image), findsNothing, reason: 'the still is showing');
  });
}
