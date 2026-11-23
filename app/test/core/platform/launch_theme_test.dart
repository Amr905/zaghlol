// T-224 AC3: only light/dark/system crosses to native, via the set call.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/launch_theme.dart';
import 'package:zaghlol/core/theme/theme_mode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(launchThemeChannel, null));

  test('writes exactly the wire value for each mode', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(launchThemeChannel, (c) async {
      calls.add(c);
      return null;
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final write = c.read(launchThemeWriterProvider);
    for (final m in ThemeMode.values) {
      await write(m);
    }
    expect(calls.map((e) => e.method).toSet(), {'set'});
    expect(calls.map((e) => e.arguments), ['system', 'light', 'dark']);
  });

  test('a missing host or a platform error never throws', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(launchThemeWriterProvider)(ThemeMode.dark);
    messenger.setMockMethodCallHandler(
      launchThemeChannel,
      (_) async => throw PlatformException(code: 'x'),
    );
    await c.read(launchThemeWriterProvider)(ThemeMode.dark);
  });

  group('system brightness (T-224 fix)', () {
    ProviderContainer make(ThemeMode mode, bool? initial) {
      messenger.setMockMethodCallHandler(launchThemeChannel, (c) async {
        if (c.method == 'systemIsDark') return initial;
        return null;
      });
      final c = ProviderContainer(
        overrides: [appThemeModeProvider.overrideWithValue(mode)],
      );
      addTearDown(c.dispose);
      c.listen(effectiveThemeModeProvider, (_, _) {});
      return c;
    }

    Future<void> pushed(bool dark) => messenger.handlePlatformMessage(
      launchThemeChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('systemIsDark', dark),
      ),
      (_) {},
    );

    test('system follows the reported value and its changes', () async {
      final c = make(ThemeMode.system, false);
      expect(c.read(effectiveThemeModeProvider), ThemeMode.system);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(effectiveThemeModeProvider), ThemeMode.light);
      await pushed(true);
      expect(c.read(effectiveThemeModeProvider), ThemeMode.dark);
      await pushed(false);
      expect(c.read(effectiveThemeModeProvider), ThemeMode.light);
    });

    test('an explicit choice ignores the system value', () async {
      final c = make(ThemeMode.dark, false);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(effectiveThemeModeProvider), ThemeMode.dark);
    });
  });
}
