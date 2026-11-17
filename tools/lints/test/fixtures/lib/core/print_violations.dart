// Fixture for no_print_outside_debug.
// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';

import 'dart:core' as core;
import 'dart:developer' as developer;
import 'dart:io';

void logSomething() {
  // expect_lint: no_print_outside_debug
  print('x');
  // expect_lint: no_print_outside_debug
  debugPrint('y');
}

void moreSinks(List<String> xs) {
  // expect_lint: no_print_outside_debug
  stdout.writeln('z');
  // expect_lint: no_print_outside_debug
  developer.log('w');
  // expect_lint: no_print_outside_debug
  core.print('v');
  // expect_lint: no_print_outside_debug
  xs.forEach(print);
}

void notSinks(List<int> xs) {
  final buffer = StringBuffer();
  buffer.write('ok');
  xs.add(1);
}
