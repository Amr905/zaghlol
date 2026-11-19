// L-2: errors and debugPrint are muted from the first line of main(), before
// any provider is read or the database opens.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/misc_daos.dart';
import 'package:zaghlol/core/logging/diag_code.dart';
import 'package:zaghlol/core/logging/diag_logger.dart';
import 'package:zaghlol/core/logging/early_error_handlers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

const String _canary = 'ACME debited EGP 1234.50 card 4111111111111111';

final class _Boom extends SafeException {
  _Boom() : super('BOOM_CODE');
}

class _Store implements DiagStore {
  final List<String> codes = [];

  @override
  Future<void> append({
    required int at,
    required DiagLevel level,
    required String code,
    required Map<String, Object?> fields,
  }) async => codes.add(code);

  @override
  Future<void> prune({required int olderThan, required int keepAtMost}) async {}
}

void main() {
  late FlutterExceptionHandler? savedFlutter;
  late bool Function(Object, StackTrace)? savedDispatcher;
  late DebugPrintCallback savedDebugPrint;

  setUp(() {
    savedFlutter = FlutterError.onError;
    savedDispatcher = PlatformDispatcher.instance.onError;
    savedDebugPrint = debugPrint;
    resetEarlyErrorBuffer();
  });
  tearDown(() {
    FlutterError.onError = savedFlutter;
    PlatformDispatcher.instance.onError = savedDispatcher;
    debugPrint = savedDebugPrint;
    resetEarlyErrorBuffer();
  });

  test('debugPrint and errors print nothing before any provider exists', () {
    final printed = <String>[];
    runZoned(
      () {
        installEarlyErrorHandlers(debugPassThrough: false);
        debugPrint('$_canary from a plugin');
        FlutterError.onError!(
          FlutterErrorDetails(exception: StateError(_canary)),
        );
        final handled = PlatformDispatcher.instance.onError!(
          StateError(_canary),
          StackTrace.fromString(_canary),
        );
        expect(handled, isTrue);
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );
    expect(printed, isEmpty);
    expect(earlyErrorBufferedCount, 2);
  });

  test('debug builds keep their normal behaviour', () {
    final prev = debugPrint;
    final prevFlutter = FlutterError.onError;
    installEarlyErrorHandlers(debugPassThrough: true);
    expect(debugPrint, same(prev));
    expect(FlutterError.onError, same(prevFlutter));
    expect(earlyErrorBufferedCount, 0);
  });

  test('buffered errors reach the log as codes only, once', () async {
    installEarlyErrorHandlers(debugPassThrough: false);
    FlutterError.onError!(FlutterErrorDetails(exception: _Boom()));
    PlatformDispatcher.instance.onError!(StateError(_canary), StackTrace.empty);
    final store = _Store();
    final logger = DiagLogger(store);
    await flushEarlyErrors(logger);
    expect(store.codes, [
      DiagCodes.flutterError.value,
      DiagCodes.uncaughtError.value,
    ]);
    expect(store.codes.join(), isNot(contains('ACME')));
    await flushEarlyErrors(logger);
    expect(store.codes, hasLength(2));
    expect(earlyErrorBufferedCount, 0);
  });

  test('the buffer is capped; a database that never opens costs nothing', () {
    installEarlyErrorHandlers(debugPassThrough: false);
    for (var i = 0; i < earlyErrorBufferLimit * 3; i++) {
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));
    }
    expect(earlyErrorBufferedCount, earlyErrorBufferLimit);
  });
}
