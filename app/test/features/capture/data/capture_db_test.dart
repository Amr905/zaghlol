// T-047 test plan 4 and 8 (DB part), plus the alert store: in-memory
// database (DAO-level; the encrypted executor is covered by T-019/T-020).

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/capture_controls_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/features/capture/application/guard_config_writer.dart';
import 'package:zaghlol/features/capture/application/user_sender_service.dart';
import 'package:zaghlol/features/capture/data/alert_store.dart';
import 'package:zaghlol/features/capture/data/guard_inputs_reader.dart';
import 'package:zaghlol/features/capture/domain/alert_absorb.dart';
import 'package:zaghlol/features/capture/domain/sender_validation.dart';
import 'package:zaghlol/features/ingestion/data/drift_ingest_store.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show GuardIgnoreRuleInput, GuardUserSenderInput, buildGuardUserConfig;

import '../support/capture_fakes.dart';

void main() {
  late AppDatabase db;
  late CaptureControlsDao dao;
  const t0 = 1700000000000;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    dao = CaptureControlsDao(db);
  });
  tearDown(() => db.close());

  Future<void> seed() async {
    await dao.addIgnoreRule(
      id: 'r1',
      institutionCode: 'nbe',
      last4: '4567',
      channel: IgnoreChannel.sms,
      createdAt: t0,
    );
    await dao.addIgnoreRule(
      id: 'r2',
      institutionCode: 'revolut',
      channel: IgnoreChannel.notification,
      createdAt: t0,
    );
    await dao.setAlwaysCapture(
      sender: 'mybank',
      channel: SenderChannel.sms,
      always: true,
      at: t0,
    );
    await dao.setAlwaysCapture(
      sender: 'notme',
      channel: SenderChannel.sms,
      always: false,
      at: t0,
    );
    await CustomTemplatesDao(db).insert(
      id: 't1',
      sender: 'com.synthetic.wallet',
      channel: SenderChannel.notification,
      template: const {'k': 1},
      sampleHash: 'a' * 64,
      createdAt: t0,
    );
  }

  test('4. parity: the writer sends exactly what buildGuardUserConfig gives '
      'for the T-046 BatchContext mapping of the same DB state', () async {
    await seed();
    final host = FakeHost();
    final writer = GuardConfigWriter(
      host: host,
      inputs: DriftGuardInputsReader(db),
      baseRegistryVersion: 4,
      scheduler: FakeScheduler(),
    );
    await writer.flush();
    final ctx = await DriftIngestStore(db).readContext();
    for (final gold in [false, true]) {
      final expected = buildGuardUserConfig(
        baseRegistryVersion: 4,
        ignoreRules: [
          for (final r in ctx.ignoreRules)
            GuardIgnoreRuleInput(
              institutionCode: r.institutionCode,
              last4: r.last4,
              channel: r.channel,
            ),
        ],
        alwaysCaptureSenders: [
          for (final s in ctx.captureSenders)
            if (s.alwaysCapture)
              GuardUserSenderInput(sender: s.sender, channel: s.channel),
        ],
        customTemplateSenders: [
          for (final (sender, channel) in ctx.customTemplateSenders)
            GuardUserSenderInput(sender: sender, channel: channel),
        ],
        goldActive: gold,
      );
      // kCaptureCustomTemplateSendersWithoutGold is true (PO Q4): the custom
      // template sender is kept with Gold on or off, so both are equal.
      expect(host.writeCopies.single, expected.bytes, reason: 'gold=$gold');
    }
    final text = utf8.decode(host.writeCopies.single);
    expect(text, contains('com.synthetic.wallet'));
    expect(text, contains('mybank'));
    expect(text, isNot(contains('notme')));
  });

  test('2. L-2: after a write, no settings row and no writer state holds a '
      'sender, institution or last-4', () async {
    await seed();
    final host = FakeHost();
    final writer = GuardConfigWriter(
      host: host,
      inputs: DriftGuardInputsReader(db),
      baseRegistryVersion: 4,
      scheduler: FakeScheduler(),
    );
    final store = DriftAlertStore(db);
    await store.write(
      const PersistedAlerts(absorbedSeq: 5, missedNotifications: 2),
    );
    await writer.flush();
    final all = await SettingsDao(db).all();
    final dump = '$all ${writer.status} ${writer.statuses}';
    for (final secret in ['nbe', '4567', 'mybank', 'revolut', 'wallet']) {
      expect(dump, isNot(contains(secret)));
    }
    expect(host.writeBuffers.single.every((b) => b == 0), isTrue);
  });

  test('inputs change events fire for the three tables', () async {
    final reader = DriftGuardInputsReader(db);
    var n = 0;
    final sub = reader.changes().listen((_) => n++);
    await dao.addIgnoreRule(
      id: 'r',
      institutionCode: 'nbe',
      channel: IgnoreChannel.sms,
      createdAt: t0,
    );
    await dao.setAlwaysCapture(
      sender: 'x',
      channel: SenderChannel.sms,
      always: true,
      at: t0,
    );
    await pumpEventQueue();
    expect(n, greaterThanOrEqualTo(2));
    await sub.cancel();
  });

  group('8. senders', () {
    late UserSenderService service;
    setUp(() => service = UserSenderService(dao, nowMs: () => t0));

    test('channel conflict: typed result, the row is left as it is', () async {
      await dao.setAlwaysCapture(
        sender: 'com.synthetic.app',
        channel: SenderChannel.notification,
        always: false,
        at: t0,
      );
      final r = await service.setAlwaysCapture(
        channel: UserSenderChannel.sms,
        sender: 'com.synthetic.app',
        always: true,
      );
      expect(r, isA<UserSenderConflict>());
      final row = (await dao.sender('com.synthetic.app'))!;
      expect(row.channel, SenderChannel.notification);
      expect(row.alwaysCapture, 0);
    });

    test(
      'deny-listed package and bad shape are refused with no DB write',
      () async {
        for (final v in ['com.whatsapp', 'notapackage', 'Com.Bad.App']) {
          final r = await service.setAlwaysCapture(
            channel: UserSenderChannel.notification,
            sender: v,
            always: true,
          );
          expect(r, isA<UserSenderRefused>(), reason: v);
        }
        expect(await db.select(db.captureSenders).get(), isEmpty);
      },
    );

    test('the 11th notification sender is refused, the 10th accepted, a '
        're-save of an existing one is not counted twice', () async {
      for (var i = 0; i < kMaxNotificationUserSenders; i++) {
        final r = await service.setAlwaysCapture(
          channel: UserSenderChannel.notification,
          sender: 'com.synthetic.app$i',
          always: true,
        );
        expect(r, isA<UserSenderSaved>(), reason: '$i');
      }
      final eleventh = await service.setAlwaysCapture(
        channel: UserSenderChannel.notification,
        sender: 'com.synthetic.extra',
        always: true,
      );
      expect((eleventh as UserSenderRefused).reason, SenderRefusal.tooMany);
      expect(await dao.sender('com.synthetic.extra'), isNull);
      final resave = await service.setAlwaysCapture(
        channel: UserSenderChannel.notification,
        sender: 'com.synthetic.app0',
        always: true,
      );
      expect(resave, isA<UserSenderSaved>());
      // Turning one off is always allowed.
      expect(
        await service.setAlwaysCapture(
          channel: UserSenderChannel.notification,
          sender: 'com.synthetic.app1',
          always: false,
        ),
        isA<UserSenderSaved>(),
      );
    });

    test('SMS senders are saved', () async {
      expect(
        await service.setAlwaysCapture(
          channel: UserSenderChannel.sms,
          sender: 'MYBANK',
          always: true,
        ),
        isA<UserSenderSaved>(),
      );
    });
  });

  group('alert store', () {
    test('round trips, including a 64-bit random seq', () async {
      final store = DriftAlertStore(db, nowMs: () => t0);
      expect((await store.read()).absorbedSeq, isNull);
      const big = 9223372036854775807;
      await store.write(
        const PersistedAlerts(
          absorbedSeq: big,
          missedNotifications: 3,
          unreadableAtMs: 12,
          catchUpFromMs: 99,
          catchUpReason: CatchUpReason.keyInvalidated,
        ),
      );
      final back = await store.read();
      expect(back.absorbedSeq, big);
      expect(back.missedNotifications, 3);
      expect(back.unreadableAtMs, 12);
      expect(back.catchUpFromMs, 99);
      expect(back.catchUpReason, CatchUpReason.keyInvalidated);
      await store.dismissMissedNotifications();
      expect((await store.read()).missedNotifications, 0);
      expect((await store.read()).catchUpFromMs, 99);
      await store.write(PersistedAlerts.empty);
      expect(await db.select(db.settings).get(), hasLength(1));
    });

    test('unreadable stored values read as defaults', () async {
      await SettingsDao(db)
          .write(CaptureAlertKeys.missedNotifications, 'garbage', at: t0);
      await SettingsDao(db).write(CaptureAlertKeys.catchUpReason, 'x', at: t0);
      final back = await DriftAlertStore(db).read();
      expect(back.missedNotifications, 0);
      expect(back.catchUpReason, isNull);
    });
  });
}
