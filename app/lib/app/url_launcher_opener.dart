// FU-195: the real ExternalUrlOpener (WIRE-NAV). Terms, Privacy, Manage
// subscription and Update app open outside the app (browser or store). Only
// https URLs are opened; nothing is queried first (canLaunchUrl is not used,
// so no Android <queries> / iOS LSApplicationQueriesSchemes are needed).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';

/// Opens [url] outside the app; false when nothing could open it.
typedef LaunchExternal = Future<bool> Function(Uri url);

/// The platform launcher; tests override it with a fake.
final launchExternalProvider = Provider<LaunchExternal>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
  name: 'launchExternalProvider',
);

/// An [ExternalUrlOpener] over [launch]: https only; a failure is swallowed
/// (a link that does not open must not break the screen that offered it).
ExternalUrlOpener urlLauncherOpener(LaunchExternal launch) => (url) async {
  if (url.scheme != 'https' || url.host.isEmpty) return;
  try {
    await launch(url);
  } on Object {
    // Nothing to show: the link stays where it was.
  }
};

/// The composition root's override (main.dart).
final Override externalUrlOpenerOverride = externalUrlOpenerProvider
    .overrideWith(
      (ref) => urlLauncherOpener(ref.watch(launchExternalProvider)),
    );
