// T-161 / FU-211: shared items open S-32 once the app is open and unlocked;
// text parses like a pasted message, images go to OCR, every share is
// discarded when S-32 closes. Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/onboarding_gate.dart' show onboardingNeededProvider;
import 'package:zaghlol/core/platform/share_intake_api.g.dart'
    show ShareIntakeHostApi;
import 'package:zaghlol/core/platform/share_intake_service.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/capture/presentation/shared_items_lifecycle.dart';
import 'package:zaghlol/features/security/domain/app_lock_controller.dart';

import '../../transactions/presentation/detail_edit_harness.dart';
import 'scan_confirm_screen_test.dart' show FakeOcr, scanOverrides;

class _Lock extends AppLockController {
  @override
  AppLockState build() => const AppLockState();

  void open() => state = const AppLockState(locked: false);
}

class _Host extends ShareIntakeHostApi {
  _Host(this.shares, {this.text, this.rejection});
  final List<ShareDescriptor> shares;
  final String? text;
  final ShareRejectReason? rejection;
  final List<String> discarded = [];
  final List<String> read = [];

  @override
  Future<List<ShareDescriptor>> listPendingShares() async => shares;

  @override
  Future<ShareRejectReason?> takePendingRejection() async => rejection;

  @override
  Future<ShareContent> readShare(String id) async {
    read.add(id);
    return ShareContent(descriptor: shares.first, text: text);
  }

  @override
  Future<void> discardShare(String id) async => discarded.add(id);
}

ShareDescriptor _d(String id, ShareKind kind, {String? ocrPath}) =>
    ShareDescriptor(
      id: id,
      kind: kind,
      mimeType: kind == ShareKind.text ? 'text/plain' : 'image/png',
      sizeBytes: 10,
      receivedAtMs: 1,
      ocrPath: ocrPath,
    );

const String _receipt =
    'Transfer successful\nEGP 1,250.00\nTo: ahmed.ali@instapay\n'
    'From account: **** 4567\nDate: 23/10/2026 11:14\nReference: 62910482112';

void main() {
  late _Lock lock;

  Future<ShareIntakeService> pump(
    WidgetTester tester,
    _Host host, {
    bool ocrInstalled = true,
  }) async {
    lock = _Lock();
    final service = ShareIntakeService(host: host);
    final key = GlobalKey<NavigatorState>();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harnessApp(
        [
          ...scanOverrides(FakeEditor(), FakeOcr(_receipt)),
          captureShareIntakeProvider.overrideWithValue(service),
          appLockControllerProvider.overrideWith(() => lock),
          onboardingNeededProvider.overrideWith((ref) async => false),
        ],
        SharedItemsLifecycle(
          navigatorKey: key,
          child: const Scaffold(body: Text('home')),
        ),
        navigatorKey: key,
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets('shared text opens S-32 after unlock, then is discarded', (
    tester,
  ) async {
    final host = _Host([_d('t1', ShareKind.text)], text: _receipt);
    final service = await pump(tester, host);
    await service.pollPending();
    await tester.pumpAndSettle();
    expect(find.text('1250.00'), findsNothing, reason: 'locked: nothing shown');
    expect(host.read, isEmpty, reason: 'never read above the lock');

    lock.open();
    await tester.pumpAndSettle();
    expect(find.text('1250.00'), findsOneWidget);
    expect(host.read, ['t1']);
    expect(host.discarded, isEmpty);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(host.discarded, ['t1']);
  });

  testWidgets('a shared image goes to OCR with its spool path', (tester) async {
    final host = _Host([
      _d('i1', ShareKind.image, ocrPath: '/spool/files/i1.bin'),
    ]);
    final service = await pump(tester, host);
    lock.open();
    await service.pollPending();
    await tester.pumpAndSettle();
    expect(find.text('1250.00'), findsOneWidget);
    expect(host.read, isEmpty, reason: 'images are not decrypted in Dart');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(host.discarded, ['i1']);
  });

  testWidgets('an image with no OCR path says not available, then is dropped', (
    tester,
  ) async {
    final host = _Host([_d('i2', ShareKind.image)]);
    final service = await pump(tester, host);
    lock.open();
    await service.pollPending();
    await tester.pumpAndSettle();
    expect(
      find.text("Reading images isn't ready on this phone yet"),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(host.discarded, ['i2']);
  });

  testWidgets('a refused share shows a message and opens nothing', (
    tester,
  ) async {
    final host = _Host(const [], rejection: ShareRejectReason.unsupportedType);
    final service = await pump(tester, host);
    lock.open();
    await service.pollPending();
    await tester.pumpAndSettle();
    expect(
      find.text("I can't read this kind of file"),
      findsOneWidget,
    );
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('an unreadable text share is dropped quietly', (tester) async {
    final host = _Host([_d('t2', ShareKind.text)], text: '');
    final service = await pump(tester, host);
    lock.open();
    await service.pollPending();
    await tester.pumpAndSettle();
    expect(host.discarded, ['t2']);
    expect(find.text('home'), findsOneWidget);
  });
}
