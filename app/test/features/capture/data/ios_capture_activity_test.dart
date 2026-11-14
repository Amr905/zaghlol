// T-066: the newest automation capture, from an in-memory database.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/capture/data/ios_capture_activity.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory(), validateSchema: false));
  tearDown(() => db.close());

  Future<void> add(String id, String channel, int at) => db
      .into(db.rawMessages)
      .insert(
        RawMessagesCompanion.insert(
          id: id,
          channel: channel,
          body: 'SYNTHETIC $id',
          bodyHash: id.padLeft(64, '0'),
          receivedAt: at,
          parseStatus: 'parsed',
          registryVersion: 1,
          createdAt: at,
        ),
      );

  test('null without captures; only automation channels count', () async {
    final activity = DriftIosCaptureActivity(db);
    expect(await activity.watchLastCaptureAtMs().first, isNull);
    await add('a', 'sms', 9000);
    await add('b', 'share', 9500);
    await add('c', 'paste', 9600);
    expect(await activity.watchLastCaptureAtMs().first, isNull);
    await add('d', 'shortcut_message', 1000);
    await add('e', 'apple_pay', 2000);
    expect(await activity.watchLastCaptureAtMs().first, 2000);
  });

  test('emits again when a capture arrives', () async {
    final activity = DriftIosCaptureActivity(db);
    final seen = <int?>[];
    final sub = activity.watchLastCaptureAtMs().listen(seen.add);
    await pumpEventQueue();
    await add('f', 'shortcut_message', 5000);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, [null, 5000]);
  });
}
