// T-238 / E2E-09: Free sees the export preview only; Gold exports a CSV.
// The real app on the emulator. Gold comes from the entitlement notifier's
// existing debug seam (`debugOverride`, a no-op outside debug builds); no
// production code grants Gold. The save dialog (SAF) cannot be driven, so the
// file bytes are received through a destination the test installs. The CSV is
// checked for its header and row count only. Synthetic data; nothing logged
// but counts.
//
// Run: flutter test integration_test/e2e_export_device_test.dart
//      --flavor devSms -d <device> --no-uninstall

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/export_import/application/export.dart';
import 'package:zaghlol/features/export_import/presentation/export_ports.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/main.dart' as app;

import 'support/e2e_common.dart';

class _Capture implements ExportDestination {
  String? name;
  Uint8List? bytes;
  int writes = 0;

  @override
  Future<void> write(String suggestedName, Uint8List b) async {
    writes++;
    name = suggestedName;
    bytes = b;
  }
}

void main() {
  final e = E2e('E2E09');
  const seededRows = 3;

  testWidgets('Free: preview only; Gold: CSV with header and rows', (t) async {
    final semantics = t.ensureSemantics();
    addTearDown(semantics.dispose);
    await e.seedReturningUser();
    e.captureFlutterErrors();
    final cap = _Capture();
    exportDestinationForDeviceTest = () => cap;
    addTearDown(() => exportDestinationForDeviceTest = null);

    await app.main();
    e.say('MAIN_RETURNED');
    await e.waitFor(t, find.text('Home'), what: 'Home');
    await e.settle(t, 2000);
    await e.addTransactions([12550, 99900, 5]);
    await e.settle(t, 800);

    // ---- Free: Settings -> Export & import.
    e.check(
      e.container().read(entitlementStateProvider).isGold == false,
      'a fresh install is Free',
    );
    await t.tap(find.bySemanticsLabel('Settings').first);
    await e.waitFor(t, find.text('Export & import'), what: 'Settings rows');
    await t.ensureVisible(find.text('Export & import').first);
    await t.tap(find.text('Export & import').first);
    await e.waitFor(
      t,
      find.byKey(const ValueKey('exportButton')),
      what: 'the export screen',
    );
    await e.waitFor(
      t,
      find.byKey(const ValueKey('exportPreviewRows')),
      what: 'the preview rows',
    );
    e.check(
      e.found(find.text('The preview is free. Exporting comes with Gold.')),
      'Free sees the "preview is free" banner',
    );
    await e.shot(t, '01-free-preview');
    await t.ensureVisible(find.byKey(const ValueKey('exportButton')));
    await t.tap(find.byKey(const ValueKey('exportButton')));
    await e.settle(t, 2000);
    e.check(
      e.found(find.text('Zaghlol Gold')),
      'Free export opens the paywall',
    );
    e.check(cap.writes == 0, 'Free writes no file');
    await e.shot(t, '02-free-paywall');

    // Back to the export screen.
    var guard = 0;
    while (!e.found(find.byKey(const ValueKey('exportButton'))) &&
        guard++ < 5) {
      await t.pageBack();
      await e.settle(t, 800);
    }
    await e.waitFor(
      t,
      find.byKey(const ValueKey('exportButton')),
      what: 'back on the export screen',
    );

    // ---- Gold through the dev/test seam.
    e.container().read(entitlementStateProvider.notifier).debugOverride(true);
    await e.settle(t, 1500);
    e.check(
      e.container().read(entitlementStateProvider).isGold,
      'the test seam made the notifier Gold (debug build)',
    );
    await e.waitFor(
      t,
      find.text(
        "The file you export isn't encrypted. Save it somewhere you trust.",
      ),
      what: 'the not-encrypted notice (Gold)',
    );
    await e.shot(t, '03-gold-export');
    await t.ensureVisible(find.byKey(const ValueKey('exportButton')));
    await t.tap(find.byKey(const ValueKey('exportButton')));
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (cap.writes == 0 && DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 250));
    }
    await e.settle(t, 800);
    e.check(cap.writes == 1, 'Gold wrote one file (writes=${cap.writes})');
    e.check((cap.name ?? '').endsWith('.csv'), 'the file is a .csv');
    final bytes = cap.bytes;
    if (bytes != null) {
      e.check(
        bytes.length > 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF,
        'the CSV starts with a UTF-8 BOM',
      );
      final text = utf8.decode(bytes.skip(3).toList());
      final lines = text.split('\r\n').where((l) => l.isNotEmpty).toList();
      e.check(
        lines.isNotEmpty && lines.first == exportHeader.join(','),
        'the CSV header matches the export columns',
      );
      e.check(
        lines.length - 1 == seededRows,
        'the CSV has $seededRows data rows (got ${lines.length - 1})',
      );
      e.say('CSV lines=${lines.length} bytes=${bytes.length}');
    } else {
      e.check(false, 'no bytes received');
    }
    e.check(
      e.found(find.text('The file is ready ✓')),
      'the screen says the file is ready',
    );
    await e.shot(t, '04-gold-ready');
    e.finish();
  });
}
