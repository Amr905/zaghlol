import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/home/presentation/home_screen.dart';

void main() {
  test('uses the fallback until a live page reports', () {
    expect(pagerHeight(const {}, 2, 330), 330);
    expect(pagerHeight(const {5: 500}, 2, 330), 330);
  });

  test('ignores stale heights of pages that no longer exist', () {
    // Three currencies measured, then one was removed: the tall page 2 is gone.
    final heights = {0: 300.0, 1: 320.0, 2: 450.0};
    expect(pagerHeight(heights, 3, 330), 450);
    expect(pagerHeight(heights, 2, 330), 320);
  });
}
