// T-141: identifiers and the secure_state store (in-memory database).

import 'dart:math';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_state.dart';
import 'package:zaghlol/core/backend/ids.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';

import 'backend_test_support.dart';

void main() {
  group('install ID', () {
    test('is a UUID v4 drawn from the given RNG', () {
      final a = newInstallId(ScriptedRandom([0xff]));
      expect(a, 'ffffffff-ffff-4fff-bfff-ffffffffffff');
      expect(isInstallId(a), isTrue);
      final seen = {
        for (var i = 0; i < 200; i++) newInstallId(Random.secure()),
      };
      expect(seen, hasLength(200));
      expect(seen.every(isInstallId), isTrue);
    });
  });

  group('Idempotency-Key', () {
    test('is a 26-char ULID with the time first; restore checks the shape', () {
      final k = IdempotencyKey.generate(
        ScriptedRandom([0]),
        DateTime.utc(2026, 11, 13),
      );
      expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$').hasMatch(k.value), isTrue);
      expect(IdempotencyKey.restore(k.value), k);
      for (final bad in ['', 'x' * 26, '8${'0' * 25}', 'I${'0' * 25}']) {
        expect(() => IdempotencyKey.restore(bad), throwsFormatException);
      }
      expect(k.toString().contains(k.value), isFalse);
    });
  });

  group('TimeNonce', () {
    test('accepts only the canonical 22-char base64url form', () {
      expect(TimeNonce('kq3V9w0bQ2FwdGFpblphZw').value, hasLength(22));
      for (final bad in [
        'kq3V9w0bQ2FwdGFpblphZ',
        'kq3V9w0bQ2FwdGFpblphZwA',
        'kq3V9w0bQ2FwdGFpblphZx',
        'kq3V9w0bQ2FwdGFpblph+w',
        'kq3V9w0bQ2FwdGFpblphZw==',
      ]) {
        expect(() => TimeNonce(bad), throwsFormatException);
      }
    });
  });

  group('SecureStateBackendStore', () {
    late AppDatabase db;
    late SecureStateBackendStore store;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
      store = SecureStateBackendStore(SecureStateDao(db));
    });
    tearDown(() => db.close());

    test('deleteIfEquals removes only the expected value', () async {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([4, 5]);
      expect(
        await store.compareAndSet(
          'install_registration',
          expected: null,
          next: a,
        ),
        isTrue,
      );
      expect(
        await store.compareAndSet(
          'install_registration',
          expected: null,
          next: b,
        ),
        isFalse,
      );
      expect(await store.deleteIfEquals('install_registration', b), isFalse);
      expect(await store.read('install_registration'), a);
      expect(await store.deleteIfEquals('install_registration', a), isTrue);
      expect(await store.read('install_registration'), isNull);
      expect(await store.deleteIfEquals('install_registration', a), isFalse);
    });
  });
}
