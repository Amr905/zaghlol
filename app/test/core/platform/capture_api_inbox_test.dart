// T-042: queryInbox over a fake native host at the Pigeon channel level (the
// generated codec): the query fields arrive as sent, pages decode with their
// opaque cursor until a null cursor ends the scan, scannedTotal is per call,
// and native errors (NOT_AVAILABLE, PERMISSION_DENIED, INVALID_ARGUMENT,
// IO_ERROR) stay code-only. Synthetic data only.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';

const String _channel =
    'dev.flutter.pigeon.zaghlol.AndroidCaptureHostApi.queryInbox';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = AndroidCaptureHostApi.pigeonChannelCodec;

  tearDown(() => messenger.setMockMessageHandler(_channel, null));

  /// A fake native reader: [rows] ids 1..n from one sender, paged by
  /// `pageSize` rows read, cursor `v1.0.<lastId>.0000abcd`.
  void fakeNative(int rows, List<InboxQuery> seen) {
    messenger.setMockMessageHandler(_channel, (data) async {
      final q = (codec.decodeMessage(data)! as List<Object?>)[0]! as InboxQuery;
      seen.add(q);
      final after = q.afterCursor == null
          ? 0
          : int.parse(q.afterCursor!.split('.')[2]);
      final size = q.pageSize.clamp(1, 500);
      final ids = [
        for (var id = after + 1; id <= rows && id <= after + size; id++) id,
      ];
      final last = ids.isEmpty ? after : ids.last;
      return codec.encodeMessage(<Object?>[
        InboxPage(
          items: [
            for (final id in ids)
              RawInboxMessage(
                address: 'NBE',
                body: 'Purchase EGP $id.00 at SYNTH SHOP',
                dateMs: 1731300000000 + id,
                simSlot: id.isEven ? 1 : null,
                providerId: '$id',
              ),
          ],
          nextCursor: ids.length < size ? null : 'v1.0.$last.0000abcd',
          scannedTotal: ids.length,
        ),
      ]);
    });
  }

  test('a scan pages until the cursor is null; fields round-trip', () async {
    final seen = <InboxQuery>[];
    fakeNative(1234, seen);
    final api = AndroidCaptureHostApi();
    final items = <RawInboxMessage>[];
    var scanned = 0;
    String? cursor;
    do {
      final page = await api.queryInbox(
        InboxQuery(
          sinceEpochMs: 1731000000000,
          senderAddresses: const ['NBE', 'CIB'],
          afterCursor: cursor,
          pageSize: 500,
        ),
      );
      items.addAll(page.items);
      scanned += page.scannedTotal;
      cursor = page.nextCursor;
    } while (cursor != null);

    expect(seen, hasLength(3));
    expect(seen.map((q) => q.afterCursor), [
      null,
      'v1.0.500.0000abcd',
      'v1.0.1000.0000abcd',
    ]);
    expect(seen.every((q) => q.sinceEpochMs == 1731000000000), isTrue);
    expect(seen.first.senderAddresses, ['NBE', 'CIB']);
    expect(scanned, 1234);
    expect(items.map((m) => int.parse(m.providerId)), [
      for (var i = 1; i <= 1234; i++) i,
    ]);
    expect(items[0].simSlot, isNull);
    expect(items[1].simSlot, 1);
    expect(items[0].dateMs, 1731300000001);
    expect(items[0].address, 'NBE');
  });

  test('an empty last page decodes with a null cursor', () async {
    fakeNative(0, <InboxQuery>[]);
    final page = await AndroidCaptureHostApi().queryInbox(
      InboxQuery(sinceEpochMs: 0, senderAddresses: const [], pageSize: 7),
    );
    expect(page.items, isEmpty);
    expect(page.nextCursor, isNull);
    expect(page.scannedTotal, 0);
  });

  for (final code in [
    'NOT_AVAILABLE',
    'PERMISSION_DENIED',
    'INVALID_ARGUMENT',
    'IO_ERROR',
  ]) {
    test('$code arrives code-only', () async {
      messenger.setMockMessageHandler(_channel, (_) async {
        return codec.encodeMessage(<Object?>[code, null, null]);
      });
      await expectLater(
        AndroidCaptureHostApi().queryInbox(
          InboxQuery(
            sinceEpochMs: 0,
            senderAddresses: const ['NBE'],
            afterCursor: 'v1.0.1.deadbeef',
            pageSize: 500,
          ),
        ),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.message, 'message', isNull)
              .having((e) => e.details, 'details', isNull),
        ),
      );
    });
  }
}
