// T-024: deep links from local notifications and widgets
// (03-navigation.md section 6). Only the `zaghlol` scheme is accepted; anything
// else, and any unknown or malformed target, falls back to Home. The input is
// never echoed or logged.

import 'app_routes.dart';

const deepLinkScheme = 'zaghlol';

/// Longest link we look at; longer input is treated as unknown.
const _maxDeepLinkLength = 256;

/// Maps `zaghlol://<target>` to an app location, or null when [uri] is not a
/// Zaghlol deep link (normal in-app locations pass through untouched).
///
/// Targets: `add` (S-30), `review` (S-14), `home` (widget W-01, S-10),
/// `voice` (widget W-02; S-31 is not built yet, so it opens the Add sheet),
/// `budget` and `bills` (Insights tab; the segments arrive with T-054).
String? resolveDeepLink(Uri uri) {
  if (uri.scheme != deepLinkScheme) return null;
  if (uri.toString().length > _maxDeepLinkLength) return AppRoutes.home;
  // `zaghlol://add` parses with host `add`; `zaghlol:///add` with path `/add`.
  final target = uri.host.isNotEmpty
      ? uri.host
      : uri.pathSegments.where((s) => s.isNotEmpty).firstOrNull ?? '';
  return switch (target.toLowerCase()) {
    'add' || 'voice' => AppRoutes.addOverHome,
    'review' => AppRoutes.review,
    'budget' || 'bills' => AppRoutes.insights,
    _ => AppRoutes.home,
  };
}
