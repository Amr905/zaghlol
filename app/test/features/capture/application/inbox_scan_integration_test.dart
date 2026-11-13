// T-048: the scan over a seeded inbox, the real IngestRawMessages and an
// encrypted database. Synthetic data; the inbox is a fake of the native
// reader (its SQL filtering is T-042's instrumented test).

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/capture_controls_dao.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/application/inbox_scan_service.dart';
import 'package:zaghlol/features/capture/application/scan.dart';
import 'package:zaghlol/features/capture/data/alert_store.dart';
import 'package:zaghlol/features/capture/data/scan_sources.dart';
import 'package:zaghlol/features/capture/domain/alert_absorb.dart';
import 'package:zaghlol/features/capture/domain/scan_plan.dart';

import '../../ingestion/support/ingest_harness.dart';
import '../support/capture_fakes.dart';
import '../support/scan_fakes.dart';

const String phoneSender = '01000000000';

String purchase(int i, {String last4 = '4321'}) =>
    'ZBANK: Purchase EGP $i.00 at Synth Shop card *$last4';

void main() {
  late IngestWorld w;
  late FakeHost host;
  late int clock;
  late InboxScanService service;
  late ScanSettings settings;

  setUp(() async {
    w = await IngestWorld.open();
    host = FakeHost();
    clock = t0 + 400 * 86400000;
    settings = const ScanSettings();
    service = InboxScanService(
      scanner: InboxScanner(
        host: host,
        senders: DriftScanSenderSource(w.db, () => testRegistry),
        store: UseCaseStore(w.useCase()),
        nowMs: () => clock,
      ),
      host: host,
      alerts: DriftAlertStore(w.db),
      watermark: DriftWatermarkSource(w.db),
      settings: () async => settings,
      nowMs: () => clock,
    );
  });
  tearDown(() async {
    await service.scanner.dispose();
    await w.close();
  });

  List<RawInboxMessage> inbox(
    int n, {
    String last4 = '4321',
    String address = 'ZBANK',
  }) => [
    for (var i = 1; i <= n; i++)
      RawInboxMessage(
        address: address,
        body: purchase(i, last4: last4),
        dateMs: clock - 86400000 + i * 60000,
        simSlot: 0,
        providerId: '$i',
      ),
  ];

  test('seeded inbox: transactions appear, OTP and a non-financial message '
      'are skipped, the progress counts match', () async {
    final rows = [
      ...inbox(150),
      RawInboxMessage(
        address: 'ZBANK',
        body: 'ZBANK: your OTP is 123456',
        dateMs: clock - 1000,
        providerId: '9001',
      ),
    ];
    host.onQueryInbox = inboxOf(rows);
    final p = await service.startFirstRun();
    expect(p.phase, ScanPhase.done);
    expect(p.scanned, 151);
    expect(p.imported, 150);
    expect(p.skipped, 1);
    expect(p.institutions, 1);
    expect(await w.count('transactions'), 150);
    expect(await w.count('raw_messages'), 150);
  });

  test(
    'a second scan of the same inbox stores nothing new (no duplicates)',
    () async {
      host.onQueryInbox = inboxOf(inbox(120));
      await service.startFirstRun();
      final before = (
        await w.count('raw_messages'),
        await w.count('transactions'),
      );
      final p = await service.startFirstRun();
      expect(p.imported, 0);
      expect(p.skipped, 120);
      expect((
        await w.count('raw_messages'),
        await w.count('transactions'),
      ), before);
    },
  );

  test(
    'a message captured live and found again by the scan is stored once',
    () async {
      final rows = inbox(3);
      await w.run([sms('live', rows[1].body, rx: rows[1].dateMs)]);
      host.onQueryInbox = inboxOf(rows);
      final p = await service.startFirstRun();
      expect(p.imported, 2);
      expect(await w.count('raw_messages'), 3);
    },
  );

  test('an ignored card is skipped (EC-62); after un-ignoring, the re-scan '
      'imports it (FR-CAP-07) without duplicating the others', () async {
    final dao = CaptureControlsDao(w.db);
    await dao.addIgnoreRule(
      id: 'ig',
      institutionCode: 'zbank',
      last4: '4321',
      channel: 'sms',
      createdAt: t0,
    );
    final rows = [
      ...inbox(5),
      ...inbox(5, last4: '8888').map(
        (r) => RawInboxMessage(
          address: r.address,
          body: r.body,
          dateMs: r.dateMs + 5,
          providerId: '${int.parse(r.providerId) + 100}',
        ),
      ),
    ];
    host.onQueryInbox = inboxOf(rows);
    var p = await service.startFirstRun();
    expect((p.imported, p.skipped), (5, 5));
    expect(await w.count('transactions'), 5);

    await dao.removeIgnoreRule('ig');
    p = await service.rescanInstitution('zbank');
    expect((p.imported, p.skipped), (5, 5));
    expect(await w.count('transactions'), 10);
  });

  group('user-added senders (FU-109 M-1)', () {
    setUp(() async {
      final dao = CaptureControlsDao(w.db);
      for (final s in [phoneSender, 'MYCOOP']) {
        await dao.setAlwaysCapture(
          sender: s,
          channel: 'sms',
          always: true,
          at: t0,
        );
      }
    });

    List<RawInboxMessage> personal() => [
      RawInboxMessage(
        address: phoneSender,
        body: 'You paid EGP 51.00 at Synth Cafe',
        dateMs: clock - 86400000,
        providerId: '1',
      ),
      RawInboxMessage(
        address: phoneSender,
        body: 'see you at 8, bring the book',
        dateMs: clock - 86400000 + 1000,
        providerId: '2',
      ),
    ];

    test('the phone number is not even asked for by default', () async {
      host.onQueryInbox = inboxOf(personal());
      final p = await service.startFirstRun();
      expect(
        host.inboxQueries.expand((q) => q.senderAddresses),
        isNot(contains(phoneSender)),
      );
      expect(p.scanned, 0);
      expect(await w.count('raw_messages'), 0);
    });

    test('with the opt-in: unparsed and non-financial messages from it never '
        'reach raw_messages or the review queue', () async {
      settings = const ScanSettings(includePersonal: true);
      host.onQueryInbox = inboxOf(personal());
      final p = await service.startFirstRun();
      expect(p.phase, ScanPhase.done);
      expect(p.scanned, 2);
      expect(p.imported, 0);
      expect(await w.count('raw_messages'), 0);
      expect(await w.count('review_items'), 0);
    });

    test('an alphanumeric user sender is scanned at full depth and its generic '
        'message goes to review like live capture', () async {
      host.onQueryInbox = inboxOf([
        RawInboxMessage(
          address: 'MYCOOP',
          body: 'You paid EGP 51.00 at Synth Cafe',
          dateMs: clock - 86400000 * 100,
          providerId: '1',
        ),
      ]);
      final p = await service.startFirstRun();
      expect(p.imported, 1);
      expect(await w.count('review_items'), 1);
    });
  });

  test('the watermark is the largest stored sms received_at; a catch-up asks '
      'from there minus the overlap and imports only what is new', () async {
    final rows = inbox(10);
    host.onQueryInbox = inboxOf(rows.take(6).toList());
    await service.startFirstRun();
    final wm = await DriftWatermarkSource(w.db).maxSmsReceivedAtMs();
    expect(wm, rows[5].dateMs);

    host.inboxQueries.clear();
    host.onQueryInbox = inboxOf(rows);
    await service.requestIfPending();
    await service.idle;
    expect(
      host.inboxQueries.first.sinceEpochMs,
      wm! - kCatchUpOverlap.inMilliseconds,
    );
    expect(await w.count('raw_messages'), 10);
  });

  test('DriftWatermarkSource: null on an empty database; notifications do not count', () async {
    expect(await DriftWatermarkSource(w.db).maxSmsReceivedAtMs(), isNull);
    await w.run([notif('n', 'Purchase EGP 5.00 at Synth Shop', rx: t0 + 99)]);
    expect(await DriftWatermarkSource(w.db).maxSmsReceivedAtMs(), isNull);
  });

  test(
    'DriftScanSenderSource: registry exact senders plus the user sms senders, '
    'classified; notification senders are left out',
    () async {
      final dao = CaptureControlsDao(w.db);
      await dao.setAlwaysCapture(
        sender: phoneSender,
        channel: 'sms',
        always: true,
        at: t0,
      );
      await dao.setAlwaysCapture(
        sender: 'MYCOOP',
        channel: 'sms',
        always: true,
        at: t0,
      );
      await dao.setAlwaysCapture(
        sender: 'com.example.pay',
        channel: 'notification',
        always: true,
        at: t0,
      );
      await dao.setAlwaysCapture(
        sender: 'OFFCOOP',
        channel: 'sms',
        always: false,
        at: t0,
      );
      final list = await DriftScanSenderSource(w.db, () => testRegistry).read();
      final byAddress = {for (final s in list) s.address: s.kind};
      expect(byAddress, {
        'ZBANK': ScanSenderKind.registry,
        phoneSender: ScanSenderKind.userPhone,
        'MYCOOP': ScanSenderKind.userNamed,
      });
    },
  );

  test('DriftAlertStore.clearCatchUp removes the request only while it equals '
      'the one that was served', () async {
    final store = DriftAlertStore(w.db);
    await store.write(
      const PersistedAlerts(
        absorbedSeq: 7,
        catchUpFromMs: 1000,
        catchUpReason: CatchUpReason.missedSms,
      ),
    );
    expect(await store.clearCatchUp(ifFromMs: 2000), isFalse);
    expect((await store.read()).catchUpFromMs, 1000);
    expect(await store.clearCatchUp(ifFromMs: 1000), isTrue);
    final after = await store.read();
    expect(
      (after.catchUpFromMs, after.catchUpReason, after.absorbedSeq),
      (null, null, 7),
    );
    expect(await store.clearCatchUp(ifFromMs: 1000), isFalse);
  });

  test('no body, address or amount in any progress value or code', () async {
    host.onQueryInbox = inboxOf(inbox(3));
    final seen = <String>[];
    final sub = service.progress.listen((p) => seen.add('$p ${p.code}'));
    await service.startFirstRun();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    for (final s in seen) {
      expect(s, isNot(contains('ZBANK')));
      expect(s, isNot(contains('EGP')));
    }
  });
}
