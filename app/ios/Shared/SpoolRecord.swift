import Foundation

/// The plaintext of one spool entry (platform-channels.md 1.3, same binary
/// record as Android so the Dart drain is shared). Never printed: every
/// textual description is redacted.
struct SpoolRecord: CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{
  let channel: String
  let source: String
  let body: String
  let receivedAtMs: Int64
  let simSlot: Int32?
  let guardInst: String?
  let guardLast4: String?
  /// Diagnostic receive stamp (monotonic ns); 0 when not taken.
  let rxElapsedNs: Int64
  /// Diagnostic boot count; -1 on iOS (not available).
  let bootCount: Int32

  init(
    channel: String, source: String, body: String, receivedAtMs: Int64, simSlot: Int32? = nil,
    guardInst: String? = nil, guardLast4: String? = nil, rxElapsedNs: Int64 = 0,
    bootCount: Int32 = -1
  ) {
    self.channel = channel
    self.source = source
    self.body = body
    self.receivedAtMs = receivedAtMs
    self.simSlot = simSlot
    self.guardInst = guardInst
    self.guardLast4 = guardLast4
    self.rxElapsedNs = rxElapsedNs
    self.bootCount = bootCount
  }

  var description: String { "SpoolRecord(<redacted>)" }
  var debugDescription: String { description }
  var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// The bytes are not a record this code wrote: proof for delete-on-proof.
struct SpoolFormatError: Error {}

/// Layout (big-endian):
/// `u8 v=1 | str8 channel | str16 source | u32 len + UTF-8 body | i64 receivedAtMs |
///  i32 simSlot (-1 = none) | opt8 guardInst | opt8 guardLast4 | i64 rxElapsedNs | i32 bootCount`.
/// Decoding is strict: unknown version, over-long field, invalid UTF-8 or
/// trailing bytes all throw `SpoolFormatError`.
enum SpoolRecordCodec {
  static let version: UInt8 = 1
  static let maxChannelBytes = 32
  static let maxSourceBytes = 256
  static let maxBodyChars = 4_000
  static let maxBodyBytes = 16_000
  static let maxShortBytes = 64
  static let maxRecordBytes =
    1 + 1 + maxChannelBytes + 2 + maxSourceBytes + 4 + maxBodyBytes + 8 + 4
    + 2 * (2 + maxShortBytes) + 8 + 4

  enum EncodeError: Error { case tooLong }

  static func encode(_ r: SpoolRecord) throws -> Data {
    var out = Data()
    out.append(version)
    try appendStr(&out, r.channel, max: maxChannelBytes, lenBits: 8)
    try appendStr(&out, r.source, max: maxSourceBytes, lenBits: 16)
    let body = Array(r.body.utf8)
    guard r.body.count <= maxBodyChars, body.count <= maxBodyBytes else {
      throw EncodeError.tooLong
    }
    appendInt(&out, UInt32(body.count))
    out.append(contentsOf: body)
    appendInt(&out, UInt64(bitPattern: r.receivedAtMs))
    appendInt(&out, UInt32(bitPattern: r.simSlot ?? -1))
    try appendOpt(&out, r.guardInst)
    try appendOpt(&out, r.guardLast4)
    appendInt(&out, UInt64(bitPattern: r.rxElapsedNs))
    appendInt(&out, UInt32(bitPattern: r.bootCount))
    return out
  }

  static func decode(_ bytes: Data) throws -> SpoolRecord {
    guard bytes.count <= maxRecordBytes else { throw SpoolFormatError() }
    var cur = Cursor(bytes: [UInt8](bytes))
    guard try cur.u8() == version else { throw SpoolFormatError() }
    let channel = try cur.str(len: Int(cur.u8()), max: maxChannelBytes)
    let source = try cur.str(len: Int(cur.u16()), max: maxSourceBytes)
    let bodyLen = Int(try cur.u32())
    guard bodyLen <= maxBodyBytes else { throw SpoolFormatError() }
    let body = try cur.str(len: bodyLen, max: maxBodyBytes)
    guard body.count <= maxBodyChars else { throw SpoolFormatError() }
    let receivedAt = Int64(bitPattern: try cur.u64())
    let slot = Int32(bitPattern: try cur.u32())
    guard slot >= -1 else { throw SpoolFormatError() }
    let inst = try cur.opt()
    let last4 = try cur.opt()
    let rx = Int64(bitPattern: try cur.u64())
    let boot = Int32(bitPattern: try cur.u32())
    guard cur.atEnd else { throw SpoolFormatError() }  // trailing bytes
    guard !channel.isEmpty, !source.isEmpty else { throw SpoolFormatError() }
    return SpoolRecord(
      channel: channel, source: source, body: body, receivedAtMs: receivedAt,
      simSlot: slot == -1 ? nil : slot, guardInst: inst, guardLast4: last4, rxElapsedNs: rx,
      bootCount: boot)
  }

  private static func appendInt<T: FixedWidthInteger>(_ out: inout Data, _ v: T) {
    withUnsafeBytes(of: v.bigEndian) { out.append(contentsOf: $0) }
  }

  private static func appendStr(_ out: inout Data, _ s: String, max: Int, lenBits: Int) throws {
    let b = Array(s.utf8)
    guard b.count <= max else { throw EncodeError.tooLong }
    if lenBits == 8 { out.append(UInt8(b.count)) } else { appendInt(&out, UInt16(b.count)) }
    out.append(contentsOf: b)
  }

  private static func appendOpt(_ out: inout Data, _ s: String?) throws {
    guard let s = s else {
      out.append(0)
      return
    }
    out.append(1)
    try appendStr(&out, s, max: maxShortBytes, lenBits: 8)
  }

  private struct Cursor {
    let bytes: [UInt8]
    var pos = 0
    var atEnd: Bool { pos == bytes.count }

    mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
      guard n >= 0, pos + n <= bytes.count else { throw SpoolFormatError() }
      defer { pos += n }
      return bytes[pos..<pos + n]
    }
    mutating func u8() throws -> UInt8 { try take(1).first! }
    mutating func u16() throws -> UInt16 { try take(2).reduce(0) { ($0 << 8) | UInt16($1) } }
    mutating func u32() throws -> UInt32 { try take(4).reduce(0) { ($0 << 8) | UInt32($1) } }
    mutating func u64() throws -> UInt64 { try take(8).reduce(0) { ($0 << 8) | UInt64($1) } }
    mutating func str(len: Int, max: Int) throws -> String {
      guard len <= max else { throw SpoolFormatError() }
      let slice = try take(len)
      guard let s = String(bytes: slice, encoding: .utf8) else { throw SpoolFormatError() }
      return s
    }
    mutating func opt() throws -> String? {
      switch try u8() {
      case 0: return nil
      case 1: return try str(len: Int(u8()), max: SpoolRecordCodec.maxShortBytes)
      default: throw SpoolFormatError()
      }
    }
  }
}
