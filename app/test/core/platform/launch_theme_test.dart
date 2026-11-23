// T-224 AC3: only light/dark/system crosses to native, via the set call.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/launch_theme.dart';

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
}
