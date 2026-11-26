// T-276: tapping the bird changes the moment on the same live artboard. The
// loader (file / controller) is called once, the State is never recreated and
// the still never shows between two animations. rive_native cannot load in
// flutter test, so a fake handle stands in for the controller.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/mascot/presentation/mascot_moments.dart';
import 'package:zaghlol/features/mascot/presentation/mascot_moods_screen.dart';
import 'package:zaghlol/features/mascot/presentation/rive_mascot.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_mascot.dart';

class _FakeHandle implements RiveMascotHandle {
  final applied = <(ZaghlolMoment, bool, bool)>[];
  bool disposed = false;

  @override
  final Widget widget = const SizedBox(
    key: ValueKey('fake-artboard'),
    width: 10,
    height: 10,
  );

  @override
  void apply(ZaghlolMoment moment, bool talk, {bool replay = false}) =>
      applied.add((moment, talk, replay));

  @override
  void dispose() => disposed = true;
}

class _Loader {
  int calls = 0;
  final handle = _FakeHandle();
  Future<RiveMascotHandle> call() async {
    calls++;
    return handle;
  }
}

Widget _wrap(Widget child, _Loader loader, {Locale? locale}) => ProviderScope(
  overrides: [
    zaghlolRivePresentProvider.overrideWith((ref) async => true),
    riveMascotLoaderProvider.overrideWithValue(loader.call),
  ],
  child: MaterialApp(
    theme: ZaghlolTheme.light,
    locale: locale ?? const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: Center(child: child)),
  ),
);

Future<void> _settle(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await t.pump();
  await t.pump();
}

bool _stillShown(WidgetTester t) => find
    .byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == ZaghlolAvatar.stillAsset,
    )
    .evaluate()
    .isNotEmpty;

void main() {
  testWidgets('tap bubble: same State, loader once, never the still', (
    tester,
  ) async {
    final loader = _Loader();
    await tester.pumpWidget(
      _wrap(const ZaghlolTapBubble(message: 'base'), loader),
    );
    await _settle(tester);
    expect(find.byKey(const ValueKey('fake-artboard')), findsOneWidget);
    final state = tester.state(find.byType(RiveMascot));
    final box = tester.getSize(find.byKey(const ValueKey('zaghlol-avatar')));

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byType(ZaghlolTapBubble));
      // Frame by frame across the tap: the artboard is there in each one.
      for (var f = 0; f < 5; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_stillShown(tester), isFalse, reason: 'tap $i frame $f');
        expect(find.byKey(const ValueKey('fake-artboard')), findsOneWidget);
      }
    }
    await tester.pump(const Duration(seconds: 1));

    expect(loader.calls, 1, reason: 'file/controller loaded once');
    expect(
      identical(tester.state(find.byType(RiveMascot)), state),
      isTrue,
      reason: 'avatar State not recreated',
    );
    expect(loader.handle.disposed, isFalse);
    expect(
      tester.getSize(find.byKey(const ValueKey('zaghlol-avatar'))),
      box,
      reason: 'size is stable',
    );
    // Rapid taps are replays on the same handle (last tap wins).
    expect(
      loader.handle.applied.where((a) => a.$1 == ZaghlolMoment.tap),
      isNotEmpty,
    );
    expect(loader.handle.applied.where((a) => a.$3), isNotEmpty);
  });

  testWidgets('moods lab: switching moods does not reload the file', (
    tester,
  ) async {
    final loader = _Loader();
    await tester.pumpWidget(_wrap(const MascotMoodsScreen(), loader));
    await _settle(tester);
    final state = tester.state(find.byType(RiveMascot));
    await tester.tap(find.byKey(const Key('mood-shocked')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_stillShown(tester), isFalse);
    await tester.tap(find.byKey(const Key('mood-detective')));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.byKey(const Key('mood-detective')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_stillShown(tester), isFalse);
    expect(loader.calls, 1);
    expect(identical(tester.state(find.byType(RiveMascot)), state), isTrue);
    expect(
      loader.handle.applied.map((a) => a.$1),
      containsAllInOrder([ZaghlolMoment.shocked, ZaghlolMoment.detective]),
    );
  });

  testWidgets('reduce motion: tapping shows the still, nothing is loaded', (
    tester,
  ) async {
    final loader = _Loader();
    await tester.pumpWidget(
      _wrap(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const ZaghlolTapBubble(message: 'base'),
        ),
        loader,
      ),
    );
    await _settle(tester);
    await tester.tap(find.byType(ZaghlolTapBubble));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_stillShown(tester), isTrue);
    expect(loader.calls, 0);
  });
}
