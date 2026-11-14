// WIRE-NAV: the one place for external URLs the shell opens. They are
// placeholders until the store listings and the legal pages exist; they hold
// no user-facing text.

import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract final class AppLinks {
  /// The store page of the app (RestoreScreen "Update app").
  static const String storePage = 'https://zaghlol.app/get';

  /// T-064: the iCloud share link of the signed Zaghlol.shortcut (Message
  /// keyword automations + Wallet Transaction automation). PLACEHOLDER: the
  /// PO signs the Shortcut on macOS and provides the real link (T-064 PO
  /// inputs); until then the install step opens this host's page.
  static const String shortcutInstall = 'https://www.icloud.com/shortcuts/TODO';

  /// Gold paywall footer links.
  static const String terms = 'https://zaghlol.app/terms';
  static const String privacy = 'https://zaghlol.app/privacy';
  static const String manageSubscription = 'https://zaghlol.app/subscription';
}

/// Opens an external URL. The default does nothing (tests, other hosts); the
/// composition root (main.dart) overrides it with the url_launcher opener
/// (FU-195, `url_launcher_opener.dart`).
typedef ExternalUrlOpener = Future<void> Function(Uri url);

final externalUrlOpenerProvider = Provider<ExternalUrlOpener>(
  (ref) => (url) async {},
  name: 'externalUrlOpenerProvider',
);
