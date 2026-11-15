// T-161 S-32 widget tests: choose, read, confirm, never auto-save, empty,
// not available, shared text, ar/en, RTL, text scale 1.3. Synthetic data only.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ocr/ocr_port.dart';
import 'package:zaghlol/core/ocr/unavailable_ocr_engine.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/capture/application/scan_providers.dart';
import 'package:zaghlol/features/capture/presentation/scan_confirm_screen.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/presentation/edit/txn_edit_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../transactions/presentation/detail_edit_harness.dart';

const String _enReceipt =
    'Transfer successful\nEGP 1,250.00\nTo: ahmed.ali@instapay\n'
    'From account: **** 4567\nDate: 23/10/2026 11:14\nReference: 62910482112';
const String _arReceipt =
    'تم التحويل بنجاح\n١٬٢٥٠٫٠٠ جم\nالى: ahmed.ali@instapay\n'
    'من حساب: **** ٤٥٦٧\nالتاريخ: ٢٣/١٠/٢٠٢٦ ١١:١٤\nرقم المرجع: 62910482112';

Registry _registry() {
  const dir = 'assets/registry';
  final institutions = <String, String>{};
  for (final f in Directory('$dir/institutions').listSync()) {
    if (f is File) institutions[f.uri.pathSegments.last] = f.readAsStringSync();
  }
  return RegistryLoader.load(
    manifest: File('$dir/registry_manifest.json').readAsStringSync(),
    shared: File('$dir/shared.json').readAsStringSync(),
    institutions: institutions,
  ).registry!;
}

class FakeOcr implements OcrEngine {
  FakeOcr(this.text, {this.fail});
  final String text;
  final OcrFailureCode? fail;
  final List<String> paths = [];

  @override
  Future<OcrOutcome> recognize(
    String encryptedImagePath, {
    List<String> languages = const ['ar', 'en'],
  }) async {
    paths.add(encryptedImagePath);
    if (fail != null) throw OcrException(fail!);
    return OcrOutcome([
      for (final line in text.split('\n'))
        OcrTextLine(
          text: line,
          confidence: 0.9,
          x: 0,
          y: 0,
          width: 1,
          height: 0.05,
        ),
    ]);
  }

  @override
  Future<List<String>> supportedLanguages() async => const ['ar', 'en'];
}

List<Override> scanOverrides(
  FakeEditor editor,
  OcrEngine engine, {
  ScanImagePicker? picker,
}) => [
  transactionEditorProvider.overrideWith((ref) async => editor),
  ocrEngineProvider.overrideWithValue(engine),
  scanImagePickerProvider.overrideWithValue(picker),
  captureRegistryLoaderProvider.overrideWithValue(_registry),
];

Future<void> pumpScan(
  WidgetTester tester,
  FakeEditor editor,
  OcrEngine engine,
  ScanRequest request, {
  ScanImagePicker? picker,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  bool dark = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    harnessApp(
      scanOverrides(editor, engine, picker: picker),
      ScanConfirmScreen(request: request),
      locale: locale,
      textScale: textScale,
      dark: dark,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('choose -> read -> confirm; nothing saved before Save', (
    tester,
  ) async {
    final ed = FakeEditor();
    final ocr = FakeOcr(_enReceipt);
    await pumpScan(
      tester,
      ed,
      ocr,
      const ScanPick(),
      picker: () async => '/spool/files/img1.bin',
    );
    expect(find.text('Choose an image'), findsWidgets);
    await tester.tap(find.byKey(const Key('scan-choose')));
    await tester.pumpAndSettle();
    expect(ocr.paths, ['/spool/files/img1.bin']);
    // Found: the editor, prefilled from the image.
    expect(find.text("Here's what I found"), findsOneWidget);
    expect(find.text('1250.00'), findsOneWidget);
    expect(find.text('EGP'), findsOneWidget);
    expect(find.text('ahmed.ali@instapay'), findsOneWidget);
    expect(find.textContaining('NBE Visa'), findsOneWidget, reason: 'last4');
    expect(ed.added, isEmpty, reason: 'never auto-saved');

    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final leg = ed.added.single.single;
    expect(leg.source, TxnSource.ocr);
    expect(leg.amount, Money(Currency.of('EGP'), 125000));
    expect(leg.direction, TxnDirection.expense);
    expect(leg.accountId, 'acc1');
    expect(leg.merchant, 'ahmed.ali@instapay');
  });

  testWidgets('Arabic digits and RTL: same amount, Arabic title', (
    tester,
  ) async {
    final ed = FakeEditor();
    await pumpScan(
      tester,
      ed,
      FakeOcr(_arReceipt),
      const ScanImagePath('/spool/files/img2.bin'),
      locale: const Locale('ar', 'EG'),
    );
    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      TextDirection.rtl,
    );
    expect(find.text('1250.00'), findsOneWidget);
    expect(find.text('ahmed.ali@instapay'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(ed.added, isEmpty);
  });

  testWidgets('text scale 1.3 in both locales has no overflow', (tester) async {
    for (final locale in [const Locale('en'), const Locale('ar', 'EG')]) {
      await pumpScan(
        tester,
        FakeEditor(),
        FakeOcr(_enReceipt),
        const ScanImagePath('/p'),
        locale: locale,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull, reason: locale.languageCode);
    }
  });

  testWidgets('a shared image shows the "from share" banner', (tester) async {
    await pumpScan(
      tester,
      FakeEditor(),
      FakeOcr(_enReceipt),
      const ScanImagePath('/p'),
    );
    expect(
      find.text(
        "Here's what I read from the image you sent. Check it and save.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('income screens prefill the Income type', (tester) async {
    final ed = FakeEditor();
    await pumpScan(
      tester,
      ed,
      FakeOcr(
        'Money received\nEGP 3,000.00\nFrom: Mona Samir\nTo account: **** 4567',
      ),
      const ScanImagePath('/p'),
    );
    expect(find.text('Mona Samir'), findsOneWidget);
    expect(find.text('3000.00'), findsOneWidget);
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bills'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(ed.added.single.single.direction, TxnDirection.income);
    expect(ed.added.single.single.source, TxnSource.ocr);
  });

  testWidgets('a receipt without a bank template still confirms', (
    tester,
  ) async {
    await pumpScan(
      tester,
      FakeEditor(),
      FakeOcr('Corner Pharmacy\nTotal 120.00\n23/10/2026'),
      const ScanImagePath('/p'),
    );
    expect(find.text('120.00'), findsOneWidget);
    expect(find.text('Corner Pharmacy'), findsOneWidget);
  });

  testWidgets('nothing found: empty state, no editor, nothing saved', (
    tester,
  ) async {
    final ed = FakeEditor();
    await pumpScan(
      tester,
      ed,
      FakeOcr('Hello there\nNo money here'),
      const ScanImagePath('/p'),
    );
    expect(
      find.text("I couldn't find a payment in this image"),
      findsOneWidget,
    );
    expect(find.byKey(const Key('scan-type')), findsOneWidget);
    expect(ed.added, isEmpty);
  });

  testWidgets('an OCR failure shows the empty state, never the error', (
    tester,
  ) async {
    await pumpScan(
      tester,
      FakeEditor(),
      FakeOcr('', fail: OcrFailureCode.ocrFailed),
      const ScanImagePath('/p'),
    );
    expect(
      find.text("I couldn't find a payment in this image"),
      findsOneWidget,
    );
  });

  testWidgets('Android before its OCR host: clear not-available state', (
    tester,
  ) async {
    await pumpScan(
      tester,
      FakeEditor(),
      const UnavailableOcrEngine(),
      const ScanPick(),
      picker: () async => '/never',
    );
    expect(find.text("I can't read this kind of file"), findsOneWidget);
    expect(find.byKey(const Key('scan-choose')), findsNothing);
    expect(find.byKey(const Key('scan-type')), findsOneWidget);
  });

  testWidgets('a shared image with no OCR path is not available', (
    tester,
  ) async {
    await pumpScan(
      tester,
      FakeEditor(),
      FakeOcr(_enReceipt),
      const ScanImagePath(null),
    );
    expect(find.text("I can't read this kind of file"), findsOneWidget);
  });

  testWidgets('no picker wired: choosing explains it is not available', (
    tester,
  ) async {
    await pumpScan(tester, FakeEditor(), FakeOcr(_enReceipt), const ScanPick());
    await tester.tap(find.byKey(const Key('scan-choose')));
    await tester.pumpAndSettle();
    expect(find.text("I can't read this kind of file"), findsOneWidget);
  });

  testWidgets('shared text is parsed like a pasted message', (tester) async {
    final ed = FakeEditor();
    await pumpScan(tester, ed, FakeOcr(''), const ScanSharedText(_enReceipt));
    expect(
      find.text(
        "Here's what I got from the message you shared. Check it and save.",
      ),
      findsOneWidget,
    );
    expect(find.text('1250.00'), findsOneWidget);
    expect(ed.added, isEmpty);
  });

  testWidgets('shared text with no payment shows the empty state', (
    tester,
  ) async {
    await pumpScan(
      tester,
      FakeEditor(),
      FakeOcr(''),
      const ScanSharedText('see you at lunch tomorrow'),
    );
    expect(
      find.text("I couldn't find a payment in this image"),
      findsOneWidget,
    );
  });
}
