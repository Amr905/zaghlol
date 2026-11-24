// T-238 fix round (batch-66 M-1): a database file is never opened while an
// older handle on it is still closing. Synthetic data only.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart';
import 'package:zaghlol/core/db/db_handle.dart';

import '../../support/fake_secret_store.dart';
import 'db_open_harness.dart';

void main() {
  test('an open waits for a handle still closing at the same path, and '
      'fails transiently when it never closes (negative proof)', () async {
    final world = await DbWorld.create(FakeSecretStore(), tag: 'handle');
    addTearDown(world.dispose);
    final path = world.mainFile.path;
    // A handle on that path whose close never finishes.
    final stuck = NativeDatabase.memory();
    trackDbHandle(stuck, path, exited: Completer<void>().future);
    final old = AppDatabase(stuck, validateSchema: false);
    unawaited(closeDbHandle(old));

    expect(
      await awaitDbHandlesClosed(
        path,
        timeout: const Duration(milliseconds: 100),
      ),
      isFalse,
    );
    final result = await world.open();
    expect(result, isA<DbOpenFailed<AppDatabase>>());
    expect(
      (result as DbOpenFailed<AppDatabase>).code,
      DbOpenFailureCode.unavailable,
    );
    expect(world.mainFile.existsSync(), isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('closeDbHandle is idempotent and an open after it proceeds', () async {
    final world = await DbWorld.create(FakeSecretStore(), tag: 'handle2');
    addTearDown(world.dispose);
    final db = openedDb(await world.open());
    final a = closeDbHandle(db);
    expect(identical(a, closeDbHandle(db)), isTrue);
    await a;
    expect(await awaitDbHandlesClosed(world.mainFile.path), isTrue);
    final again = openedDb(await world.open());
    await closeDbHandle(again);
  });
}
