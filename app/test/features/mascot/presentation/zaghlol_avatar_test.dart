import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';

Widget _wrap(
  Widget child, {
  bool rtl = false,
  bool osReduce = false,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: osReduce),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );
}

void main() {
  for (final rtl in [true, false]) {
    final l = rtl ? 'ar' : 'en';
    testWidgets('renders still pose, 15 moments ($l)', (tester) async {
      for (final m in ZaghlolMoment.values) {
        await tester.pumpWidget(
          _wrap(
            ZaghlolAvatar(moment: m, semanticLabel: 'x'),
            rtl: rtl,
          ),
        );
        expect(find.byType(Image), findsOneWidget);
      }
      expect(ZaghlolMoment.values, hasLength(15));
    });
  }

  testWidgets('semantics label comes from caller; null is decorative', (
    tester,
  ) async {
    final h = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(const ZaghlolAvatar(semanticLabel: 'Hi')));
    expect(find.bySemanticsLabel('Hi'), findsOneWidget);
    await tester.pumpWidget(_wrap(const ZaghlolAvatar()));
    expect(find.bySemanticsLabel('Hi'), findsNothing);
    h.dispose();
  });

  testWidgets('does not block taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox(width: 200, height: 200),
            ),
            const ZaghlolAvatar(size: 200),
          ],
        ),
      ),
    );
    await tester.tap(find.byType(GestureDetector));
    expect(taps, 1);
  });

  group('artboard seam', () {
    final artboard = zaghlolArtboardProvider.overrideWithValue(
      (c, m, talk, size) => Text('rive ${m.name} $talk'),
    );

    testWidgets('registered artboard is used, API unchanged', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ZaghlolAvatar(moment: ZaghlolMoment.saved, talk: true),
          overrides: [artboard],
        ),
      );
      expect(find.text('rive saved true'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('OS reduce motion shows still pose', (tester) async {
      await tester.pumpWidget(
        _wrap(const ZaghlolAvatar(), osReduce: true, overrides: [artboard]),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('rive'), findsNothing);
    });

    testWidgets('in-app toggle shows still pose', (tester) async {
      await tester.pumpWidget(
        _wrap(const ZaghlolAvatar(), overrides: [artboard]),
      );
      expect(find.textContaining('rive'), findsOneWidget);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(ZaghlolAvatar)),
      );
      c.read(reduceMotionProvider.notifier).set(true);
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('rive'), findsNothing);
    });
  });

  testWidgets('no running animation in still pose', (tester) async {
    await tester.pumpWidget(_wrap(const ZaghlolAvatar(), osReduce: true));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
