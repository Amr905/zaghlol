import 'dart:async';

/// Global setup for every test in `app/test`.
///
/// Golden tests render with the built-in test font (Ahem) so results do not
/// depend on the host. When real fonts are bundled (theme task), load them
/// here with `FontLoader` before `testMain()` so goldens use the final glyphs.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
