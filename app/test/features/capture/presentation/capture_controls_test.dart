import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/capture_controls_dao.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/edit_card_providers.dart';
import 'package:zaghlol/features/capture/application/guard_config_writer.dart';
import 'package:zaghlol/features/capture/application/ignore_rules.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';
import 'package:zaghlol/features/capture/presentation/capture_controls.dart';
import 'package:zaghlol/features/transactions/application/bulk_edit.dart';

void main() {
  late AppDatabase db;
  var guardWrites = 0;
  late ServiceCaptureControls controls;

  setUp(() {
    guardWrites = 0;
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    controls = ServiceCaptureControls(
      db: db,
      rules: IgnoreRulesService(
        db,
        bulkEdit: BulkEditUseCase(db),
        onRemoved: (_) async {},
        onRuleChanged: () async {
          guardWrites++;
          return const GuardWriteResult(
            GuardWriteStatus(GuardWriteState.written),
          );
        },
        rescanAvailable: true,
      ),
      scanService: null,
      saveDepth: (_) async {},
    );
  });
  tearDown(() => db.close());

  test('toggle off rewrites the Guard config before it returns; undo '
      'rewrites it again and the watch re-emits', () async {
    final seen = <int>[];
    final sub = controls.watchRules().listen((r) => seen.add(r.length));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final added = await controls.add(
      const IgnoreTarget(
        institutionCode: 'cib',
        last4: '1234',
        channel: IgnoreChannel.sms,
      ),
    );
    expect(guardWrites, 1);
    expect(added.created, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen.last, 1);
    final removed = await controls.remove(added.ruleId);
    expect(guardWrites, 2);
    expect(removed.rescanOffer?.institutionCode, 'cib');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen, containsAllInOrder([0, 1, 0]));
    await sub.cancel();
  });

  test('no scanner: re-scan is unavailable and progress is empty', () async {
    expect(controls.rescan(depthMonths: 6), isNull);
    expect(await controls.scanProgress.isEmpty, isTrue);
  });

  test(
    'the T-085 port adapter turns channels off through the same path',
    () async {
      final c = ProviderContainer(
        overrides: [
          captureControlsProvider.overrideWith((ref) async => controls),
        ],
      );
      addTearDown(c.dispose);
      final port = c.read(captureCardPortProvider);
      expect(port, isA<CardCapturePort>());
      await port.turnOff(
        institutionCode: 'cib',
        last4: '1234',
        offChannels: {IgnoreChannel.sms, IgnoreChannel.notification},
      );
      expect(guardWrites, 2);
      final rows = await db.select(db.ignoreRules).get();
      expect(rows.map((r) => (r.last4, r.channel)).toSet(), {
        ('1234', IgnoreChannel.sms),
        ('1234', IgnoreChannel.notification),
      });
    },
  );

  test(
    'an ignored card never reaches the Guard as ignored for other cards',
    () async {
      await controls.add(
        const IgnoreTarget(
          institutionCode: 'cib',
          last4: '1234',
          channel: IgnoreChannel.sms,
        ),
      );
      expect(
        await CaptureControlsDao(db).isIgnored(
          institutionCode: 'cib',
          last4: '9999',
          channel: IgnoreChannel.sms,
        ),
        isFalse,
      );
    },
  );
}
