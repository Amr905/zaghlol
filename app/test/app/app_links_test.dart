import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/app_config.dart';

// FU-195: every external page the app links to lives on zaghlol.app over
// HTTPS, and each has a page in site/.
void main() {
  test('external links are https zaghlol.app pages', () {
    const links = {
      'privacy': AppLinks.privacy,
      'terms': AppLinks.terms,
      'subscription': AppLinks.manageSubscription,
      'get': AppLinks.storePage,
      'support': AppLinks.support,
    };
    for (final entry in links.entries) {
      final uri = Uri.parse(entry.value);
      expect(uri.scheme, 'https', reason: entry.key);
      expect(uri.host, 'zaghlol.app', reason: entry.key);
      expect(uri.path, '/${entry.key}', reason: entry.key);
      expect(uri.hasQuery, isFalse, reason: entry.key);
    }
  });
}
