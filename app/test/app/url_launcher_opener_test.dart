// FU-195: the composition root's external URL opener over a fake launcher.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/app_config.dart';
import 'package:zaghlol/app/url_launcher_opener.dart';

void main() {
  late List<Uri> launched;
  late ProviderContainer c;
  Object? fail;

  setUp(() {
    launched = [];
    fail = null;
    c = ProviderContainer(
      overrides: [
        externalUrlOpenerOverride,
        launchExternalProvider.overrideWithValue((u) async {
          launched.add(u);
          if (fail != null) throw fail!;
          return true;
        }),
      ],
    );
    addTearDown(c.dispose);
  });

  test('Terms, Privacy, Manage subscription and Update app open', () async {
    final open = c.read(externalUrlOpenerProvider);
    for (final l in [
      AppLinks.terms,
      AppLinks.privacy,
      AppLinks.manageSubscription,
      AppLinks.storePage,
    ]) {
      await open(Uri.parse(l));
    }
    expect(launched.map((u) => u.toString()), [
      AppLinks.terms,
      AppLinks.privacy,
      AppLinks.manageSubscription,
      AppLinks.storePage,
    ]);
  });

  test('only https URLs are opened', () async {
    final open = c.read(externalUrlOpenerProvider);
    await open(Uri.parse('http://zaghlol.app/terms'));
    await open(Uri.parse('javascript:alert(1)'));
    await open(Uri.parse('file:///etc/hosts'));
    expect(launched, isEmpty);
  });

  test('a launcher failure is swallowed', () async {
    fail = StateError('no browser');
    await c.read(externalUrlOpenerProvider)(Uri.parse(AppLinks.terms));
    expect(launched, hasLength(1));
  });

  test('without the override the default opener does nothing', () async {
    final bare = ProviderContainer();
    addTearDown(bare.dispose);
    await bare.read(externalUrlOpenerProvider)(Uri.parse(AppLinks.terms));
  });
}
