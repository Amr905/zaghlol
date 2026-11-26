// T-274: the Home avatar is bigger and loses the artboard's empty top; the
// still and the interim art (no empty top) are never cropped.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_mascot.dart';

Future<Size> _avatarSize(WidgetTester tester, {required bool rive}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [zaghlolRivePresentProvider.overrideWith((ref) async => rive)],
      child: MaterialApp(
        theme: ZaghlolTheme.light,
        home: const Scaffold(
          body: Align(
            alignment: AlignmentDirectional.topStart,
            child: ZaghlolAvatar(size: 92, trimHeadroom: true),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return tester.getSize(find.byKey(const ValueKey('zaghlol-avatar')));
}

void main() {
  testWidgets('Rive artboard: box is trimmed to the bird height', (
    tester,
  ) async {
    final s = await _avatarSize(tester, rive: true);
    expect(s.width, 92);
    expect(s.height, closeTo(92 * ZaghlolAvatar.riveBirdHeightFactor, 0.01));
  });

  testWidgets('interim art: stays square, nothing is cropped', (tester) async {
    final s = await _avatarSize(tester, rive: false);
    expect(s, const Size(92, 92));
  });
}
