// T-064: the Shortcut setup report and the install step, with a fake port
// (and, for the channel, a fake native host at the Pigeon level).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/app_config.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/application/ios_setup_providers.dart';
import 'package:zaghlol/features/capture/application/ios_shortcut_providers.dart';
import 'package:zaghlol/features/capture/data/ios_shortcut_setup_port.dart';
import 'package:zaghlol/features/capture/domain/ios_shortcut_checker.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';

final DateTime _now = DateTime.utc(2026, 11, 14, 12);
final int _nowMs = _now.millisecondsSinceEpoch;
const int _day = 24 * 60 * 60 * 1000;

final class _Port implements ShortcutSetupPort {
  _Port(this.result);
  final ShortcutSetupStatus? result;
  @override
  Future<ShortcutSetupStatus> status() async =>
      result ?? (throw Exception('NOT_AVAILABLE'));
}

ProviderContainer _container({
  ShortcutSetupStatus? status,
  bool ios = true,
  int? baseline,
  List<Uri>? opened,
}) {
  final c = ProviderContainer(
    overrides: [
      captureIosProvider.overrideWithValue(ios),
      clockProvider.overrideWithValue(() => _now),
      iosSetupBaselineMsProvider.overrideWithValue(baseline),
      shortcutSetupPortProvider.overrideWithValue(_Port(status)),
      externalUrlOpenerProvider.overrideWithValue((u) async {
        opened?.add(u);
      }),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('flags the automation that stopped running', () async {
    final c = _container(
      status: ShortcutSetupStatus(
        lastMessageIntentAtMs: _nowMs - _day,
        lastWalletIntentAtMs: _nowMs - 10 * _day,
      ),
    );
    final r = (await c.read(shortcutSetupReportProvider.future))!;
    expect(r.flagged, [ShortcutAutomation.wallet]);
  });

  test('null off iOS and when the host cannot answer', () async {
    expect(
      await _container(
        ios: false,
        status: ShortcutSetupStatus(),
      ).read(shortcutSetupReportProvider.future),
      isNull,
    );
    expect(await _container().read(shortcutSetupReportProvider.future), isNull);
  });

  test('never-run automations use the first-run baseline', () async {
    final r = (await _container(
      status: ShortcutSetupStatus(),
      baseline: _nowMs - 8 * _day,
    ).read(shortcutSetupReportProvider.future))!;
    expect(r.flagged.length, 2);
    expect(r.message.neverRan, isTrue);
  });

  test('install opens the iCloud link', () async {
    final opened = <Uri>[];
    await _container(opened: opened).read(installShortcutProvider)();
    expect(opened, [Uri.parse(AppLinks.shortcutInstall)]);
  });

  test('the Pigeon channel round-trips the times and maps errors', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = IosCaptureHostApi.pigeonChannelCodec;
    const name =
        'dev.flutter.pigeon.zaghlol.IosCaptureHostApi.getShortcutSetupStatus';
    Object? reply;
    messenger.setMockMessageHandler(
      name,
      (_) async => codec.encodeMessage(reply),
    );
    addTearDown(() => messenger.setMockMessageHandler(name, null));

    reply = <Object?>[ShortcutSetupStatus(lastMessageIntentAtMs: 5)];
    final s = await IosShortcutSetupPort().status();
    expect(s.lastMessageIntentAtMs, 5);
    expect(s.lastWalletIntentAtMs, isNull);

    reply = <Object?>['NOT_AVAILABLE', null, null];
    await expectLater(
      IosShortcutSetupPort().status(),
      throwsA(isA<Exception>()),
    );
  });
}
