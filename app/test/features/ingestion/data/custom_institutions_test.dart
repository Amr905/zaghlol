// WIRE-SVC item 3: saved custom templates feed the ingestion registry; a
// corrupt one is skipped; the T-076 re-parse follows a save.

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/capture/application/template_builder.dart'
    show customTemplateSavedHookProvider;
import 'package:zaghlol/features/ingestion/data/custom_institutions.dart';
import 'package:zaghlol/features/ingestion/data/ingest_factory.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/spike_registry.dart' show RegistryGuardBase;
import 'package:zaghlol/ingestion/ulid.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/test_registry.dart';

const String _sample = 'XYZ: You paid 220.00 EGP at AMAZON on 23/10 card 1234.';

Map<String, Object?> _spec() {
  int at(String t) => _sample.indexOf(t);
  final r = buildCustomTemplate(
    sample: _sample,
    spans: [
      for (final (tag, text) in [
        (CustomTag.amount, '220.00'),
        (CustomTag.currency, 'EGP'),
        (CustomTag.merchant, 'AMAZON'),
        (CustomTag.date, '23/10'),
        (CustomTag.last4, '1234'),
      ])
        TagSpan(tag, at(text), at(text) + text.length),
    ],
    direction: TemplateDirection.expense,
    sender: 'XYZBANK',
  );
  expect(r.error, isNull);
  return r.spec!.toJson();
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory(), validateSchema: false));
  tearDown(() => db.close());

  Future<void> save(String id, String json, {int at = 1}) => db.customStatement(
    'INSERT INTO custom_templates (id, sender, channel, template_json, '
    'sample_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    [id, 'XYZBANK', 'sms', json, 'a' * 64, at],
  );

  ParseResult parse(Registry r, String sender, String body) =>
      ParsingPipeline(r).parse(
        ParseRequest(
          body: body,
          source: sender,
          channel: RegistryChannel.sms,
          receivedAt: DateTime.utc(2026, 10, 25, 12),
        ),
      );

  test(
    'a saved template parses its sender; the built-ins still parse',
    () async {
      await save('01ABCDEF', jsonEncode(_spec()));
      final r = await registryWithCustomTemplates(loadTestRegistry(), db);
      final p = parse(
        r,
        'XYZBANK',
        'XYZ: You paid 75.50 EGP at NOON on 24/10 card 9876.',
      );
      expect(p, isA<ParseParsed>());
      expect(
        parse(
          r,
          zbankSms,
          'ZBANK: Purchase EGP 61.00 at Synth Shop card *4321',
        ),
        isA<ParseParsed>(),
      );
    },
  );

  test('NEGATIVE: a corrupt saved template is skipped; the good one and the '
      'built-ins still parse', () async {
    await save('01BAD1', '{"v":1,"sender":"XYZBANK"}', at: 1);
    await save('01BAD2', '{"v":99}', at: 2);
    await save('01BAD3', '{"v":1,"pattern":5,"channel":[]}', at: 3);
    await save('01GOOD', jsonEncode(_spec()), at: 4);
    final r = await registryWithCustomTemplates(loadTestRegistry(), db);
    expect(r.institutions.length, loadTestRegistry().institutions.length + 1);
    expect(
      parse(
        r,
        'XYZBANK',
        'XYZ: You paid 75.50 EGP at NOON on 24/10 card 9876.',
      ),
      isA<ParseParsed>(),
    );
    expect(
      parse(r, zbankSms, 'ZBANK: Purchase EGP 61.00 at Synth Shop card *4321'),
      isA<ParseParsed>(),
    );
  });

  test('only corrupt rows: the base registry is returned unchanged', () async {
    await save('01BAD1', '{"v":1}');
    final base = loadTestRegistry();
    expect(
      identical(await registryWithCustomTemplates(base, db), base),
      isTrue,
    );
  });

  test('the save hook re-parses a review message of that sender; the '
      'stored raw row is not changed otherwise', () async {
    final base = loadTestRegistry();
    final use = buildIngestRawMessages(
      db,
      pipeline: ParsingPipeline(base),
      guardBase: RegistryGuardBase(base),
      newId: UlidGenerator().next,
    );
    await db.customStatement(
      'INSERT INTO capture_senders (sender, channel, always_capture, '
      'created_at) VALUES (?, ?, 1, 1)',
      ['XYZBANK', 'sms'],
    );
    final r = await use([
      IncomingMessage(
        deliveryId: 'd1',
        channel: 'sms',
        source: 'XYZBANK',
        body: 'XYZ: You paid 75.50 EGP at NOON on 24/10 card 9876.',
        receivedAtMs: DateTime.utc(2026, 10, 25, 12).millisecondsSinceEpoch,
        origin: MessageOrigin.spool,
      ),
    ]);
    expect(r.outcomes['d1'], isA<IngestReview>());
    expect(
      (await db.customSelect('SELECT count(*) c FROM transactions').getSingle())
          .read<int>('c'),
      0,
    );
    await save('01ABCDEF', jsonEncode(_spec()));
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        captureRegistryLoaderProvider.overrideWithValue(() => base),
      ],
    );
    addTearDown(c.dispose);
    final hook = c.read(customTemplateSavedHookProvider);
    await hook();
    final rows = await db
        .customSelect('SELECT amount_minor FROM transactions')
        .get();
    expect(rows.map((x) => x.read<int>('amount_minor')), [7550]);
    // A second run changes nothing (the row is stamped).
    await hook();
    expect(
      (await db.customSelect('SELECT count(*) c FROM transactions').getSingle())
          .read<int>('c'),
      1,
    );
  });
}
