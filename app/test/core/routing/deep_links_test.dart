import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/core/routing/deep_links.dart';

void main() {
  test('zaghlol://add opens the Add sheet over Home', () {
    expect(resolveDeepLink(Uri.parse('zaghlol://add')), AppRoutes.addOverHome);
    expect(resolveDeepLink(Uri.parse('zaghlol:///add')), AppRoutes.addOverHome);
  });

  test('review, widget and notification targets', () {
    expect(resolveDeepLink(Uri.parse('zaghlol://review')), AppRoutes.review);
    expect(resolveDeepLink(Uri.parse('zaghlol://home')), AppRoutes.home);
    expect(
      resolveDeepLink(Uri.parse('zaghlol://voice')),
      AppRoutes.addOverHome,
    );
    expect(resolveDeepLink(Uri.parse('zaghlol://budget')), AppRoutes.insights);
    expect(resolveDeepLink(Uri.parse('zaghlol://ADD')), AppRoutes.addOverHome);
  });

  test('unknown, empty and oversized targets fall back to Home', () {
    expect(resolveDeepLink(Uri.parse('zaghlol://nope')), AppRoutes.home);
    expect(resolveDeepLink(Uri.parse('zaghlol://')), AppRoutes.home);
    expect(
      resolveDeepLink(Uri.parse('zaghlol://add/${'a' * 400}')),
      AppRoutes.home,
    );
  });

  test('other schemes and in-app locations are not touched', () {
    expect(resolveDeepLink(Uri.parse('https://add')), isNull);
    expect(resolveDeepLink(Uri.parse('/insights')), isNull);
  });
}
