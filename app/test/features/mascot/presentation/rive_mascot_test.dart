// T-212: the generated zaghlol.riv is bundled and wired in. The animation
// itself is verified with the official Rive runtime by
// tools/mascot_riv/verify (flutter test hosts cannot load rive_native).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/mascot/presentation/interim_mascot.dart';
import 'package:zaghlol/features/mascot/presentation/rive_mascot.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_mascot.dart';

Widget _wrap(Widget child, {bool reduce = false}) => ProviderScope(
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  test('zaghlol.riv is a Rive v7 file under 500 KB', () {
    final bytes = File('assets/rive/zaghlol.riv').readAsBytesSync();
    expect(bytes.length, lessThanOrEqualTo(500 * 1024));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIVE');
    expect(bytes[4], 7, reason: 'major version');
  });

  test('the contract names match the file', () {
    // The names are verified inside the file by tools/mascot_riv/verify/check.mjs;
    // here we only make sure the strings are in the binary.
    final bytes = File('assets/rive/zaghlol.riv').readAsBytesSync();
    bool has(String s) => _indexOf(bytes, s.codeUnits) >= 0;
    expect(has(kRiveArtboard), isTrue);
    expect(has(kRiveStateMachine), isTrue);
    expect(has(kRiveInputState), isTrue);
    expect(has(kRiveInputTalk), isTrue);
    expect(has(kRiveInputReduceMotion), isTrue);
  });

  testWidgets('the asset is declared, so ZaghlolAvatar picks RiveMascot', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(manifest.listAssets(), contains(kZaghlolRivAsset));
    });
    await tester.pumpWidget(_wrap(const ZaghlolAvatar()));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(RiveMascot), findsOneWidget);
    expect(find.byType(InterimMascot), findsNothing);
  });

  testWidgets('without the native Rive library the still is shown', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const RiveMascot(moment: ZaghlolMoment.proud, size: 96)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion shows the still, never Rive', (tester) async {
    await tester.pumpWidget(_wrap(const ZaghlolAvatar(), reduce: true));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(RiveMascot), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}

int _indexOf(Uint8List hay, List<int> needle) {
  for (var i = 0; i <= hay.length - needle.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}
