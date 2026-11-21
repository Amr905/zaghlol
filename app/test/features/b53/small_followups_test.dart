// Batch 53 follow-ups: FU-229b, FU-166a, FU-237a, FU-172d. Synthetic data.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/platform/app_settings.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/backup/application/schedule_providers.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/gold/presentation/gold_ui_ports.dart';
import 'package:zaghlol/features/gold/presentation/upsell_cap.dart';
import 'package:zaghlol/features/home/application/home_cards.dart';
import 'package:zaghlol/features/onboarding/application/contextual.dart';
import 'package:zaghlol/features/roi/presentation/roi_tips_providers.dart';
import 'package:zaghlol/features/salary/application/salary_providers.dart';
import 'package:zaghlol/features/voice/application/voice_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

Future<(ProviderContainer, SettingsRepository)> _make({
  List<Override> extra = const [],
}) async {
  final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
  addTearDown(db.close);
  final repo = SettingsRepository(SettingsDao(db));
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((ref) async => db),
      settingsRepositoryProvider.overrideWith((ref) async => repo),
      ...extra,
    ],
  );
  addTearDown(c.dispose);
  return (c, repo);
}

RoiSuggestion _tip() => RoiSuggestion(
  rule: RoiRule.coffeeMachine,
  kinds: const [RoiProductKind.homeAppliance],
  currency: Currency.of('EGP'),
  habitYear: Money(Currency.of('EGP'), 2940000),
  year1Saving: Money(Currency.of('EGP'), 1440000),
  year2Saving: Money(Currency.of('EGP'), 2400000),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'FU-229b: mic-denied Open settings calls the app-settings channel',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appSettingsChannel, (call) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(appSettingsChannel, null),
      );
      final (c, _) = await _make();
      await c.read(voiceOpenSettingsProvider)();
      expect(calls, ['open']);
    },
  );

  test('FU-229b: a missing host does not throw', () async {
    final (c, _) = await _make();
    await c.read(openAppSettingsProvider)();
  });

  group('FU-166a weekly upsell cap', () {
    var now = DateTime.utc(2026, 11, 20, 10);
    var shown = 0;
    final overrides = [
      upsellClockProvider.overrideWith(
        (ref) =>
            () => now,
      ),
      paywallTriggerProvider.overrideWith(
        (ref) =>
            (_) => shown++,
      ),
    ];

    setUp(() {
      now = DateTime.utc(2026, 11, 20, 10);
      shown = 0;
    });

    test('the store persists across containers', () async {
      final (c, repo) = await _make();
      await c.read(upsellCapStoreProvider).markShown(now);
      expect(
        await repo.get(Settings.upsellLastShown),
        now.millisecondsSinceEpoch,
      );
      final c2 = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) async => repo),
        ],
      );
      addTearDown(c2.dispose);
      expect(await c2.read(upsellCapStoreProvider).lastShown(), now);
    });

    test(
      'first caller opens once, then waits a week, never for Gold',
      () async {
        final (c, _) = await _make(extra: overrides);
        final ask = c.read(unsolicitedPaywallProvider);
        expect(await ask(GoldCapability.voiceEntry), isTrue);
        expect(await ask(GoldCapability.voiceEntry), isFalse);
        expect(shown, 1);
        now = now.add(const Duration(days: 8));
        expect(await ask(GoldCapability.voiceEntry), isTrue);
        expect(shown, 2);
      },
    );
  });

  test('FU-237a: Not for me survives a restart', () async {
    final (c, repo) = await _make();
    c.listen(roiDismissedProvider, (_, _) {});
    c.read(roiDismissedProvider.notifier).dismiss(_tip());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await repo.get(Settings.roiDismissedTips), {'egp_coffeemachine'});
    final c2 = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWith((ref) async => repo)],
    );
    addTearDown(c2.dispose);
    c2.listen(roiDismissedProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c2.read(roiDismissedProvider), {roiTipKey(_tip())});
    c2.read(roiDismissedProvider.notifier).restore(_tip());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await repo.get(Settings.roiDismissedTips), isEmpty);
  });

  group('FU-172d Home cards sources', () {
    final egp = Currency.of('EGP');
    SetupContext ctx({CivilDate? salary, bool backup = false}) => SetupContext(
      today: CivilDate(2026, 11, 20),
      installedOn: CivilDate(2026, 11, 1),
      paydayConfigured: false,
      hasBudgets: true,
      backupExists: backup,
      latestSalaryCredit: salary,
      firstCycleEnd: CivilDate(2026, 11, 28),
    );

    test('no salary plan: no credit, payday card off', () async {
      final (c, _) = await _make();
      c.listen(setupSalaryCreditProvider, (_, _) {});
      await c.read(salaryPlanProvider.future);
      await c.read(salaryStateProvider.future);
      expect(c.read(setupSalaryCreditProvider).value, isNull);
      expect(
        nextSetupSuggestion(ctx())?.kind,
        isNot(SetupSuggestionKind.payday),
      );
    });

    test('plan and a tied entry: credit exists, payday card shows', () async {
      final (c, repo) = await _make();
      await repo.set(
        Settings.salaryPlan,
        SalaryPlan.tryCreate(amount: Money(egp, 1500000), day: 25),
      );
      await repo.set(
        Settings.salaryState,
        SalaryState.empty.withEntry(
          SalaryEntry(
            txnId: 't1',
            captured: true,
            anchor: CivilDate(2026, 10, 25),
          ),
        ),
      );
      c.listen(setupSalaryCreditProvider, (_, _) {});
      await c.read(salaryPlanProvider.future);
      await c.read(salaryStateProvider.future);
      final credit = c.read(setupSalaryCreditProvider).value;
      expect(credit?.date, CivilDate(2026, 10, 25));
      expect(credit?.amount, Money(egp, 1500000));
      expect(
        nextSetupSuggestion(ctx(salary: credit?.date))?.kind,
        SetupSuggestionKind.payday,
      );
    });

    test('backup exists comes from the backup module', () async {
      var exists = false;
      final (c, _) = await _make(
        extra: [backupExistsProvider.overrideWith((ref) async => exists)],
      );
      expect(await c.read(setupBackupExistsProvider.future), isFalse);
      exists = true;
      c.invalidate(backupExistsProvider);
      c.invalidate(setupBackupExistsProvider);
      final backup = await c.read(setupBackupExistsProvider.future);
      expect(backup, isTrue);
      // Visibility: with a backup the backup card is off, without it it is on.
      expect(nextSetupSuggestion(ctx(backup: backup)), isNull);
      expect(nextSetupSuggestion(ctx())?.kind, SetupSuggestionKind.backup);
    });
  });
}
