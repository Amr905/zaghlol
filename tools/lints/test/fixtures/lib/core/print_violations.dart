// Fixture for no_print_outside_debug.
// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';

void logSomething() {
  // expect_lint: no_print_outside_debug
  print('x');
  // expect_lint: no_print_outside_debug
  debugPrint('y');
}
