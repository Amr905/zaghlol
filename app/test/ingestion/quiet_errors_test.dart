// T-008: uncaught errors in the ingestion engines print nothing (they would
// reach logcat even in release) and become a fixed diag code.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/ingestion/quiet_errors.dart';

import 'ingestion_fakes.dart';

void main() {
  test('uncaught, framework and debugPrint output never prints', () {
    final savedFlutter = FlutterError.onError;
    final savedDispatcher = PlatformDispatcher.instance.onError;
    final savedDebugPrint = debugPrint;
    addTearDown(() {
      FlutterError.onError = savedFlutter;
      PlatformDispatcher.instance.onError = savedDispatcher;
      debugPrint = savedDebugPrint;
    });

    final codes = <String>[];
    final printed = <String>[];
    runZoned(
      () {
        installQuietErrorHandlers(codes.add);
        final handled = PlatformDispatcher.instance.onError!(
          StateError('$canary EGP 5'),
          StackTrace.current,
        );
        expect(handled, isTrue);
        FlutterError.onError!(
          FlutterErrorDetails(exception: StateError(canary)),
        );
        debugPrint('$canary from a plugin');
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );
    expect(printed, isEmpty);
    expect(codes, [uncaughtErrorCode, flutterErrorCode]);
  });
}
