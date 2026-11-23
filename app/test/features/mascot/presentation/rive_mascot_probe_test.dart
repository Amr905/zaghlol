import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/mascot/presentation/rive_mascot.dart';

void main() {
  // Batch 64 M1: the state-name probe is off in the app and bounded when on.
  test('state recording is off by default and resets', () {
    RiveMascotProbe.reset();
    expect(RiveMascotProbe.recordStates, isFalse);
    expect(RiveMascotProbe.stateNames, isEmpty);
  });

  test('recordState never keeps more than maxStateNames', () {
    RiveMascotProbe.reset();
    for (var i = 0; i < RiveMascotProbe.maxStateNames + 50; i++) {
      RiveMascotProbe.recordState('s$i');
    }
    expect(RiveMascotProbe.stateNames.length, RiveMascotProbe.maxStateNames);
    expect(
      RiveMascotProbe.stateNames.last,
      's${RiveMascotProbe.maxStateNames + 49}',
    );
    RiveMascotProbe.reset();
  });
}
