// T-008: turns a spool entry plus its parse result into a raw_messages row
// (database-schema.md §2.2). Spike scope: the row only; account resolution
// and the transactions insert are T-041. Nothing here logs or prints; the
// body is only ever bound as a parameter by the DAO.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../core/db/app_database.dart';
import '../core/platform/capture_api.g.dart';

/// `SHA-256(sender ‖ 0x00 ‖ normalized body)` as 64 lowercase hex
/// (database-schema.md: "SHA-256(sender ‖ normalized body)"; the separator
/// keeps `ab`+`c` and `a`+`bc` apart). Normalization is the parsing
/// package's display normalizer; T-041 owns the final definition.
String bodyHashOf(String source, String body) {
  final bytes = <int>[
    ...utf8.encode(source),
    0,
    ...utf8.encode(normalizeText(body)),
  ];
  return sha256.convert(bytes).toString();
}

/// The channel strings the spool may carry and raw_messages accepts.
RegistryChannel? registryChannelOf(String channel) =>
    RegistryChannel.fromWire(channel);

/// What the cycle does with one entry.
sealed class MappedEntry {
  const MappedEntry(this.spoolId);

  final String spoolId;
}

/// Store this row.
final class StoreRow extends MappedEntry {
  const StoreRow(super.spoolId, this.row, this.parsed);

  final RawMessagesCompanion row;
  final bool parsed;
}

/// Nothing to store (OTP/promo dropped by the parser, unknown channel); the
/// entry is still acked after the commit.
final class SkipEntry extends MappedEntry {
  const SkipEntry(super.spoolId);
}

MappedEntry mapEntry({
  required SpoolEntry entry,
  required ParseResult? result,
  required int registryVersion,
  required String rowId,
  required int nowMs,
}) {
  final channel = registryChannelOf(entry.channel);
  if (channel == null || result is ParseDropped) return SkipEntry(entry.id);
  final (status, inst, templateId, templateVersion) = switch (result) {
    ParseParsed(
      :final institutionCode,
      :final templateId,
      :final templateVersion,
    ) =>
      ('parsed', institutionCode, templateId, templateVersion),
    ParseUnrecognized(:final institutionCode, :final templateId) => (
      'review',
      institutionCode,
      templateId,
      null,
    ),
    _ => ('review', null, null, null),
  };
  return StoreRow(
    entry.id,
    RawMessagesCompanion.insert(
      id: rowId,
      channel: channel.wire,
      sender: Value(entry.source),
      institutionCode: Value(inst),
      body: entry.body,
      bodyHash: bodyHashOf(entry.source, entry.body),
      receivedAt: entry.receivedAtMs,
      simSlot: Value(entry.simSlot),
      parseStatus: status,
      templateId: Value(templateId),
      templateVersion: Value(templateVersion),
      registryVersion: registryVersion,
      createdAt: nowMs,
    ),
    status == 'parsed',
  );
}
