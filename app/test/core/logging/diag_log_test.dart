// T-021 tests: allow-listed diagnostic log. AC map:
//  - "Free-text fields rejected at compile time": 'compile-time barrier' group.
//  - "Ring buffer trims correctly": 'ring buffer' group.
//  - Sentinel proofs (self-check §5): 'sentinels' group.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/misc_daos.dart';
import 'package:zaghlol/core/logging/diag_code.dart';
import 'package:zaghlol/core/logging/diag_error_handlers.dart';
import 'package:zaghlol/core/logging/diag_event.dart';
import 'package:zaghlol/core/logging/diag_exporter.dart';
import 'package:zaghlol/core/logging/diag_field.dart';
import 'package:zaghlol/core/logging/diag_logger.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

const String _smsSentinel = 'ACME debited EGP 1234.50 card 4111111111111111';
const String _keySentinel = 'a3f9c2e17b5d4608a3f9c2e17b5d4608';

final class _Boom extends SafeException {
  _Boom() : super('BOOM_CODE');
}

/// Runs `dart analyze` on [source] (placed inside the package so package
/// imports resolve); true if the analyzer reports no error.
Future<bool> _compiles(String source) async {
  final dir = Directory('${Directory.current.path}/.dart_tool/diag_probe')
    ..createSync(recursive: true);
  final file = File('${dir.path}/probe_${source.hashCode}.dart')
    ..writeAsStringSync(source);
  try {
    final r = await Process.run('dart', [
      'analyze',
      '--format=machine',
      file.path,
    ]);
    return !'${r.stdout}'.contains('ERROR|');
  } finally {
    file.deleteSync();
  }
}

void main() {
  late AppDatabase db;
  late DiagLogDao dao;
  var clock = DateTime.utc(2026, 11, 11, 10);
  late DiagLogger logger;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiagLogDao(db);
    clock = DateTime.utc(2026, 11, 11, 10);
    logger = DiagLogger(DiagLogDaoStore(dao), now: () => clock);
  });
  tearDown(() => db.close());

  const imports = '''
import 'package:zaghlol/core/db/daos/misc_daos.dart';
import 'package:zaghlol/core/logging/diag_code.dart';
import 'package:zaghlol/core/logging/diag_event.dart';
import 'package:zaghlol/core/logging/diag_field.dart';
''';

  group('compile-time barrier', () {
    test('control: a well-typed event compiles', () async {
      expect(
        await _compiles(
          '$imports\nvoid main() => const DiagEvent(level: DiagLevel.info, code: DiagCodes.syncOk);',
        ),
        isTrue,
      );
    });

    test('a String code does not compile (message body as code)', () async {
      expect(
        await _compiles(
          "$imports\nvoid main() => DiagEvent(level: DiagLevel.info, code: 'ACME debited EGP 5');",
        ),
        isFalse,
      );
    });

    test('a String as a field does not compile', () async {
      expect(
        await _compiles(
          "$imports\nvoid main() => DiagEvent(level: DiagLevel.info, code: DiagCodes.syncOk, fields: ['body text']);",
        ),
        isFalse,
      );
    });

    test(
      'a String key / a raw DiagField constructor does not compile',
      () async {
        expect(
          await _compiles(
            "$imports\nvoid main() => DiagField.count('body', 3);",
          ),
          isFalse,
        );
        expect(
          await _compiles("$imports\nvoid main() => const DiagCode._('X');"),
          isFalse,
        );
      },
    );
  });

  group('registry-only codes (T-021 fix 21-1)', () {
    test('no public re-reader builds a code from a String', () async {
      expect(
        await _compiles(
          "$imports\nvoid main() => DiagEvent(level: DiagLevel.info, code: DiagCode.tryFromStored('CARD_4111111111111111')!);",
        ),
        isFalse,
      );
      expect(
        await _compiles(
          "$imports\nvoid main() => DiagEvent(level: DiagLevel.info, code: DiagCode.fromRegistry('SYNC_OK')!);",
        ),
        isTrue,
        reason: 'control: the registry lookup is typed and compiles',
      );
    });

    test('fromRegistry only returns registered codes', () {
      expect(DiagCode.fromRegistry('CARD_4111111111111111'), isNull);
      expect(DiagCode.fromRegistry('EGP_1234_50'), isNull);
      expect(DiagCode.fromRegistry(null), isNull);
      expect(DiagCode.fromRegistry('SYNC_OK'), same(DiagCodes.syncOk));
    });
  });

  group('runtime shape checks (strings that remain)', () {
    test('free text, SMS and key-like strings are rejected without echo', () {
      for (final bad in [_smsSentinel, _keySentinel, '1.2 beta', '', 'a b']) {
        for (final make in <DiagField Function()>[
          () => DiagField.version(DiagKey.appVersion, bad),
          () => DiagField.institution(bad),
          () => DiagField.templateId(bad),
        ]) {
          try {
            make();
            fail('accepted a bad value');
          } on DiagFieldException catch (e) {
            expect(e.toString(), anyOf('DIAG_FIELD_BAD_VALUE'));
            expect(e.toString(), isNot(contains(_keySentinel)));
          }
        }
      }
    });

    test('valid shapes and kind mismatches', () {
      expect(
        DiagField.version(DiagKey.appVersion, '1.4.2+17').value,
        '1.4.2+17',
      );
      expect(DiagField.institution('BANK_MISR').value, 'BANK_MISR');
      expect(DiagField.templateId('cib_debit_v2').value, 'cib_debit_v2');
      expect(DiagField.httpStatus(503).value, 503);
      expect(DiagField.duration(const Duration(seconds: 2)).value, 2000);
      expect(
        () => DiagField.count(DiagKey.appVersion, 1),
        throwsA(isA<DiagFieldException>()),
      );
      expect(
        () => DiagField.count(DiagKey.rows, -1),
        throwsA(isA<DiagFieldException>()),
      );
      expect(
        () => DiagField.httpStatus(99),
        throwsA(isA<DiagFieldException>()),
      );
    });
  });

  group('ring buffer', () {
    test('keeps the newest 2000 rows', () async {
      for (var i = 0; i < 2000 + 25; i++) {
        clock = DateTime.utc(2026, 11, 11, 10).add(Duration(seconds: i));
        await logger.record(
          DiagEvent(
            level: DiagLevel.info,
            code: DiagCodes.syncOk,
            fields: [DiagField.count(DiagKey.rows, i)],
          ),
        );
      }
      final rows = await dao.recent(limit: 5000);
      expect(rows.length, 2000);
      expect(jsonDecode(rows.first.fields!)['rows'], 2024);
      expect(jsonDecode(rows.last.fields!)['rows'], 25);
    });

    test('drops events older than 7 days, keeps those at the edge', () async {
      clock = DateTime.utc(2026, 11, 1);
      await logger.record(
        const DiagEvent(level: DiagLevel.info, code: DiagCodes.appStarted),
      );
      clock = DateTime.utc(2026, 11, 4, 10);
      await logger.record(
        const DiagEvent(level: DiagLevel.info, code: DiagCodes.syncOk),
      );
      clock = DateTime.utc(2026, 11, 11, 10);
      await logger.record(
        const DiagEvent(level: DiagLevel.warn, code: DiagCodes.syncFailed),
      );
      final codes = [for (final r in await dao.recent()) r.code];
      expect(codes, ['SYNC_FAILED', 'SYNC_OK']);
    });

    test(
      'record never throws and reports false when the store fails',
      () async {
        final bad = DiagLogger(_ThrowingStore(), now: () => clock);
        expect(
          await bad.record(
            const DiagEvent(level: DiagLevel.info, code: DiagCodes.syncOk),
          ),
          isFalse,
        );
      },
    );
  });

  group('export', () {
    test('renders oldest first with allow-listed fields', () async {
      await logger.record(
        DiagEvent(
          level: DiagLevel.warn,
          code: DiagCodes.syncFailed,
          fields: [
            DiagField.httpStatus(503),
            DiagField.duration(const Duration(milliseconds: 120)),
            DiagField.institution('CIB'),
            DiagField.version(DiagKey.appVersion, '1.0.0'),
          ],
        ),
      );
      final text = await DiagExporter(dao).exportText(now: clock);
      expect(
        text,
        contains(
          '2026-11-11T10:00:00.000Z warn SYNC_FAILED http_status=503 duration_ms=120 institution=CIB app_version=1.0.0',
        ),
      );
    });

    test('a tampered row is sanitised on export', () async {
      await dao.append(
        at: clock.millisecondsSinceEpoch,
        level: DiagLevel.error,
        code: 'SYNC_FAILED',
        fields: {
          'body': _smsSentinel,
          'app_version': _smsSentinel,
          'rows': _smsSentinel,
          'institution': 'CIB',
          'amount_minor': 123450,
        },
      );
      await dao.append(
        at: clock.millisecondsSinceEpoch,
        level: DiagLevel.error,
        code: 'lower.case:code',
      );
      await dao.append(
        at: clock.millisecondsSinceEpoch,
        level: DiagLevel.error,
        code: 'CARD_4111111111111111',
      );
      final text = await DiagExporter(dao).exportText(now: clock);
      expect(text, isNot(contains('4111')));
      expect(text, contains('SYNC_FAILED institution=CIB'));
      expect(text, isNot(contains('ACME')));
      expect(text, isNot(contains('123450')));
      expect(text, isNot(contains('lower')));
      expect(text, isNot(contains('amount')));
    });
  });

  group('sentinels (self-check §5)', () {
    test(
      'a SafeException keeps only its code; message-like text never lands',
      () async {
        installDiagErrorHandlers(logger);
        final prevOnError = PlatformDispatcher.instance.onError;
        final prevFlutter = FlutterError.onError;
        final prevPrint = debugPrint;
        addTearDown(() {
          PlatformDispatcher.instance.onError = null;
          FlutterError.onError = prevFlutter;
          debugPrint = prevPrint;
        });
        expect(prevOnError, isNotNull);

        FlutterError.onError!(
          FlutterErrorDetails(
            exception: Exception('body $_smsSentinel key $_keySentinel'),
          ),
        );
        FlutterError.onError!(FlutterErrorDetails(exception: _Boom()));
        PlatformDispatcher.instance.onError!(
          StateError('$_smsSentinel $_keySentinel'),
          StackTrace.fromString(_smsSentinel),
        );
        PlatformDispatcher.instance.onError!(_Boom(), StackTrace.empty);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final rows = await dao.recent();
        expect(rows.length, 4);
        final everything = [
          for (final r in rows) '${r.code} ${r.level} ${r.fields}',
        ].join('\n');
        expect(everything, isNot(contains('ACME')));
        expect(everything, isNot(contains('4111')));
        expect(everything, isNot(contains('1234')));
        expect(everything, isNot(contains(_keySentinel)));
        expect([for (final r in rows) r.code]..sort(), [
          'FLUTTER_ERROR',
          'FLUTTER_ERROR',
          'UNCAUGHT_ERROR',
          'UNCAUGHT_ERROR',
        ]);
        expect(
          rows.where((r) => r.fields != null).map((r) => jsonDecode(r.fields!)),
          everyElement({'error_code': 'BOOM_CODE'}),
        );
        final text = await DiagExporter(dao).exportText(now: clock);
        expect(text, isNot(contains('ACME')));
        expect(text, isNot(contains(_keySentinel)));
      },
    );

    test('debugPrint is muted', () {
      final lines = <String>[];
      final prev = debugPrint;
      installDiagErrorHandlers(logger);
      final muted = debugPrint;
      debugPrint = prev;
      final old = debugPrintOverrideProbe(muted, lines);
      expect(old, isEmpty);
    });

    test('every DiagCodes value passes the stored-code shape', () {
      for (final c in [
        DiagCodes.flutterError,
        DiagCodes.uncaughtError,
        DiagCodes.unknownError,
        DiagCodes.appStarted,
        DiagCodes.ingestCycle,
        DiagCodes.ingestUncaught,
        DiagCodes.ingestFlutterError,
        DiagCodes.syncOk,
        DiagCodes.syncFailed,
        DiagCodes.catalogUpdated,
        DiagCodes.dbMigrated,
        DiagCodes.backupExclusionFailed,
      ]) {
        expect(DiagCode.fromRegistry(c.value), c);
        expect(DiagCodes.all, contains(c));
      }
      expect(DiagCodes.backupExclusionFailed.value, 'BACKUP_EXCLUSION_FAILED');
    });

    test('toString of a rejected field does not carry the value', () {
      Object? caught;
      try {
        DiagField.templateId(_smsSentinel);
      } on Object catch (e) {
        caught = e;
      }
      expect('$caught', 'DIAG_FIELD_BAD_VALUE');
    });
  });
}

List<String> debugPrintOverrideProbe(
  DebugPrintCallback muted,
  List<String> sink,
) {
  // The muted callback must not forward anything to [sink] / stdout.
  muted(_smsSentinel);
  return sink;
}

final class _ThrowingStore implements DiagStore {
  @override
  Future<void> append({
    required int at,
    required DiagLevel level,
    required String code,
    required Map<String, Object?> fields,
  }) => Future.error(StateError(_smsSentinel));

  @override
  Future<void> prune({required int olderThan, required int keepAtMost}) async {}
}
