// T-008: raw_messages rows from spool entries, and the spike registry.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/ingestion/raw_message_mapper.dart';
import 'package:zaghlol/ingestion/spike_registry.dart';
import 'package:zaghlol/ingestion/ulid.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'ingestion_fakes.dart';

void main() {
  test('body hash: 64 lowercase hex, sender-bound, separator-safe', () {
    final h = bodyHashOf('5550100', 'paid EGP 5');
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h), isTrue);
    expect(bodyHashOf('5550100', 'paid EGP 5'), h);
    expect(bodyHashOf('5550101', 'paid EGP 5'), isNot(h));
    expect(bodyHashOf('ab', 'c'), isNot(bodyHashOf('a', 'bc')));
    // Arabic-Indic digits normalise to the same hash as ASCII ones.
    expect(bodyHashOf('x', 'EGP ٥'), bodyHashOf('x', 'EGP 5'));
  });

  test('the spike registry loads and parses its synthetic template', () {
    final registry = loadSpikeRegistry();
    final r = ParsingPipeline(registry).parse(
      ParseRequest(
        body: 'spike: you paid EGP 12.50 at SYNTH SHOP card *4321',
        source: '5550100',
        channel: RegistryChannel.sms,
        receivedAt: DateTime.utc(2026, 11, 11),
      ),
    );
    expect(r, isA<ParseParsed>());
    expect((r as ParseParsed).institutionCode, 'spike');
    expect(r.fields.amount!.minor, 1250);
  });

  test('mapEntry: parsed, review and skip', () {
    final e = entry(sid(1));
    final parsed = mapEntry(
      entry: e,
      result: const ParseUnrecognized(
        UnrecognizedReason.noTemplateMatched,
        institutionCode: 'spike',
      ),
      registryVersion: 3,
      rowId: UlidGenerator().next(),
      nowMs: 5,
    ) as StoreRow;
    expect(parsed.row.parseStatus.value, 'review');
    expect(parsed.row.institutionCode.value, 'spike');
    expect(parsed.row.registryVersion.value, 3);
    expect(parsed.row.channel.value, 'sms');
    expect(parsed.row.simSlot.value, 0);
    expect(
      mapEntry(
        entry: e,
        result: const ParseDropped(DropReason.globalPattern),
        registryVersion: 1,
        rowId: 'x',
        nowMs: 0,
      ),
      isA<SkipEntry>(),
    );
    expect(
      mapEntry(
        entry: entry(sid(2), channel: 'fax'),
        result: null,
        registryVersion: 1,
        rowId: 'x',
        nowMs: 0,
      ),
      isA<SkipEntry>(),
    );
  });

  test('ULIDs are 26 Crockford characters', () {
    final g = UlidGenerator();
    for (var i = 0; i < 50; i++) {
      expect(ulidPattern.hasMatch(g.next()), isTrue);
    }
  });
}
