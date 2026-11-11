import XCTest

@testable import Runner

/// T-148: NFC on iOS. The rows are the shared list in
/// app/test/fixtures/backup/zglb-v1-vectors.json ("nfc"); a Dart test checks
/// that every row there appears here and in the Kotlin test.
final class TextNormalizationTests: XCTestCase {
  private let rows: [(String, String)] = [
    ("0627 0653", "0622"),
    ("0627 0654", "0623"),
    ("0648 0654", "0624"),
    ("0627 0655", "0625"),
    ("064A 0654", "0626"),
    ("06D5 0654", "06C0"),
    ("06C1 0654", "06C2"),
    ("06D2 0654", "06D3"),
    ("0623", "0623"),
    ("0647 0645 0632 0629", "0647 0645 0632 0629"),
    ("0628 0651 0650", "0628 0650 0651"),
    ("0065 0301", "00E9"),
    ("1100 1161 11A8", "AC01"),
    ("212B", "00C5"),
  ]

  private func decode(_ cps: String) -> String {
    var s = String.UnicodeScalarView()
    for part in cps.split(separator: " ") {
      s.append(Unicode.Scalar(UInt32(part, radix: 16)!)!)
    }
    return String(s)
  }

  private func encode(_ s: String) -> String {
    s.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " ")
  }

  func testEverySharedRowNormalizesToItsNfcForm() throws {
    let host = TextNormalizationHost()
    for (input, want) in rows {
      XCTAssertEqual(encode(try host.nfc(input: decode(input))), want, "row \(input)")
    }
  }

  func testDigitsSpacesAndCaseAreLeftAlone() throws {
    let s = "Pass \u{00A0}\u{0663}\u{06F5} X"
    XCTAssertEqual(encode(try TextNormalizationHost().nfc(input: s)), encode(s))
  }

  func testAWholeArabicPassphraseComposes() throws {
    let decomposed = "\u{0643}\u{0644}\u{0645}\u{0629} \u{0627}\u{0654}\u{0645}\u{0627}\u{0646}"
    let composed = "\u{0643}\u{0644}\u{0645}\u{0629} \u{0623}\u{0645}\u{0627}\u{0646}"
    XCTAssertEqual(
      encode(try TextNormalizationHost().nfc(input: decomposed)), encode(composed))
  }

  func testBackupKeyItemIsSeparateFromTheDatabaseKey() {
    let db = DbKeyKeychain.itemQuery(accessGroup: nil)
    let bk = DbKeyKeychain.itemQuery(accessGroup: nil, account: DbKeyKeychain.backupAccount)
    XCTAssertEqual(db[kSecAttrAccount as String] as? String, "db_key_v1")
    XCTAssertEqual(bk[kSecAttrAccount as String] as? String, "backup_key_v1")
    XCTAssertEqual(bk[kSecAttrService as String] as? String, "app.zaghlol.keys")
    let add = DbKeyKeychain.addAttributes(
      value: Data(repeating: 7, count: 32), accessGroup: nil,
      account: DbKeyKeychain.backupAccount)
    XCTAssertEqual(
      add[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    XCTAssertEqual(add[kSecAttrSynchronizable as String] as? Bool, false)
    XCTAssertEqual(SecretStoreRegistration.backupKey.account, "backup_key_v1")
    XCTAssertEqual(SecretStoreRegistration.dbKey.account, "db_key_v1")
  }
}
