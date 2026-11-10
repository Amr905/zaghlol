import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/share_intake_api.g.dart';
import 'package:zaghlol/core/platform/share_intake_service.dart';

const String _host = 'dev.flutter.pigeon.zaghlol.ShareIntakeHostApi';
const String _events = 'dev.flutter.pigeon.zaghlol.ShareIntakeEventsApi';
const MessageCodec<Object?> _codec = ShareIntakeHostApi.pigeonChannelCodec;

/// Stands in for the Kotlin side: answers the Pigeon host channels from
/// in-memory state, exactly as the generated Kotlin code would reply.
class _FakeNative {
  _FakeNative(this.messenger) {
    _on('listPendingShares', (_) => pending.map((e) => e.descriptor).toList());
    _on('readShare', (List<Object?> args) {
      final id = args[0]! as String;
      final match = pending.where((e) => e.descriptor.id == id);
      if (match.isEmpty) {
        throw PlatformException(code: 'IO_ERROR', message: 'unknown share');
      }
      return match.first;
    });
    _on('discardShare', (List<Object?> args) {
      discarded.add(args[0]! as String);
      pending.removeWhere((e) => e.descriptor.id == args[0]);
      return null;
    });
    _on('takePendingRejection', (_) {
      final r = rejection;
      rejection = null;
      return r;
    });
  }

  final TestDefaultBinaryMessenger messenger;
  final List<ShareContent> pending = <ShareContent>[];
  final List<String> discarded = <String>[];
  ShareRejectReason? rejection;

  void _on(String method, Object? Function(List<Object?> args) handler) {
    messenger.setMockMessageHandler('$_host.$method', (
      ByteData? message,
    ) async {
      final args = (message == null
          ? <Object?>[]
          : _codec.decodeMessage(message)! as List<Object?>);
      try {
        return _codec.encodeMessage(<Object?>[handler(args)]);
      } on PlatformException catch (e) {
        return _codec.encodeMessage(<Object?>[e.code, e.message, e.details]);
      }
    });
  }

  /// Native -> Dart (warm start).
  Future<void> push(String method, Object? arg) {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      '$_events.$method',
      _codec.encodeMessage(<Object?>[arg]),
      (_) => done.complete(),
    );
    return done.future;
  }

  void dispose() {
    for (final m in <String>[
      'listPendingShares',
      'readShare',
      'discardShare',
      'takePendingRejection',
    ]) {
      messenger.setMockMessageHandler('$_host.$m', null);
    }
  }
}

/// Lets the broadcast stream deliver queued events to the test's listener.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

ShareContent _share(
  String id,
  ShareKind kind, {
  String? text,
  Uint8List? bytes,
}) => ShareContent(
  descriptor: ShareDescriptor(
    id: id,
    kind: kind,
    mimeType: kind == ShareKind.text ? 'text/plain' : 'image/png',
    sizeBytes: 10,
    receivedAtMs: 1,
  ),
  text: text,
  bytes: bytes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNative native;
  late ShareIntakeService service;
  late List<ShareIntakeEvent> seen;
  late StreamSubscription<ShareIntakeEvent> sub;

  setUp(() {
    native = _FakeNative(
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger,
    );
    service = ShareIntakeService();
    seen = <ShareIntakeEvent>[];
    sub = service.events.listen(seen.add);
    service.attach();
  });

  tearDown(() async {
    await sub.cancel();
    await service.dispose();
    native.dispose();
  });

  test('a shared text arrives as an event and reads back its text', () async {
    final share = _share('a' * 28, ShareKind.text, text: 'SYNTHETIC msg');
    native.pending.add(share);

    await native.push('onShareReceived', share.descriptor);
    await _pump();

    expect(seen, hasLength(1));
    final event = seen.single as ShareReceived;
    expect(event.descriptor.kind, ShareKind.text);
    final content = await service.read(event.descriptor.id);
    expect(content.text, 'SYNTHETIC msg');
    expect(content.bytes, isNull);
  });

  test('a shared image reads back bytes for the OCR flow', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    native.pending.add(_share('b' * 28, ShareKind.image, bytes: bytes));

    await service.pollPending();
    await _pump();

    expect((seen.single as ShareReceived).descriptor.kind, ShareKind.image);
    final content = await service.read('b' * 28);
    expect(content.bytes, bytes);
    expect(content.text, isNull);
  });

  test('cold start poll reports a refusal once and each share once', () async {
    native.rejection = ShareRejectReason.tooLarge;
    native.pending.add(_share('c' * 28, ShareKind.text, text: 'x'));

    await service.pollPending();
    await _pump();
    await service.pollPending();
    await _pump();

    expect(seen, hasLength(2));
    expect((seen[0] as ShareRejected).reason, ShareRejectReason.tooLarge);
    expect((seen[1] as ShareReceived).descriptor.id, 'c' * 28);
  });

  test(
    'an event and a later poll do not announce the same share twice',
    () async {
      final share = _share('d' * 28, ShareKind.text, text: 'x');
      native.pending.add(share);

      await native.push('onShareReceived', share.descriptor);
      await service.pollPending();
      await _pump();

      expect(seen.whereType<ShareReceived>(), hasLength(1));
    },
  );

  test('warm-start refusal is forwarded', () async {
    await native.push('onShareRejected', ShareRejectReason.unsupportedType);
    await _pump();

    expect(
      (seen.single as ShareRejected).reason,
      ShareRejectReason.unsupportedType,
    );
  });

  test(
    'discard reaches native and a later poll does not resurrect it',
    () async {
      native.pending.add(_share('e' * 28, ShareKind.text, text: 'x'));
      await service.pollPending();
      await _pump();

      await service.discard('e' * 28);
      await service.pollPending();
      await _pump();

      expect(native.discarded, <String>['e' * 28]);
      expect(seen.whereType<ShareReceived>(), hasLength(1));
    },
  );

  test(
    'native errors surface as PlatformException with the contract code',
    () async {
      await expectLater(
        service.read('f' * 28),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'IO_ERROR'),
        ),
      );
    },
  );
}
