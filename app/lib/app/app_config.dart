// WIRE-NAV: the one place for external URLs the shell opens. They are
// placeholders until the store listings and the legal pages exist; they hold
// no user-facing text.

import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract final class AppLinks {
  /// The store page of the app (RestoreScreen "Update app").
  static const String storePage = 'https://zaghlol.app/get';

  /// Gold paywall footer links.
  static const String terms = 'https://zaghlol.app/terms';
  static const String privacy = 'https://zaghlol.app/privacy';
  static const String manageSubscription = 'https://zaghlol.app/subscription';
}

/// Opens an external URL. The build has no URL launcher dependency yet, so
/// the default does nothing; the composition root overrides it once one is
/// added (see the WIRE-NAV report).
typedef ExternalUrlOpener = Future<void> Function(Uri url);

final externalUrlOpenerProvider = Provider<ExternalUrlOpener>(
  (ref) => (url) async {},
  name: 'externalUrlOpenerProvider',
);
